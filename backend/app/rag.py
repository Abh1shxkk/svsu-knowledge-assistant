"""Document engine: every paragraph is embedded once (at upload) and stored in PostgreSQL with
pgvector. A question is embedded, matched against the stored vectors within the asker's scope, and
answered with citations. No OCR or re-reading of files happens at search time."""
import json
import re
from pgvector.sqlalchemy import Vector
from sqlalchemy import Column, Integer, String, Table, Text, select, text

from .config import settings
from .database import engine, meta
from .llm import chat, embed

blocks = Table(
    "blocks", meta,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("doc_id", String(64), nullable=False, index=True),
    Column("page", Integer, nullable=False),
    Column("block", String(32), nullable=False),
    Column("text", Text, nullable=False),
    Column("embedding", Vector(settings.embed_dim), nullable=False),
)
meta.create_all(engine, tables=[blocks])
with engine.begin() as _c:
    _c.execute(text("CREATE INDEX IF NOT EXISTS blocks_embedding_idx ON blocks USING hnsw (embedding vector_cosine_ops)"))

# The assistant never answers from drafts, pending, rejected or withdrawn documents.
ANSWERABLE = {"Active", "Superseded", "Expired"}
LABELS = ["One source", "Multiple sources", "Revised policy", "Historical record",
          "Conflicting instructions", "Insufficient evidence", "Needs clarification"]
LANGS = {"en": "English", "hi": "Hindi (Devanagari script)", "auto": "the same language as the question"}
BODY_FORMAT = (
    '"body" is a list of blocks: {"p": "paragraph"}, {"ul": ["item", ...]}, '
    '{"table": {"head": ["column", ...], "rows": [["cell", ...], ...]}}, {"sub": "small note"}, '
    '{"opts": ["specific question", ...]}. Use **bold** for key dates and numbers.'
)
_SYSTEM = (
    "You answer questions about Swami Vivekanand Subharti University (SVSU) records using ONLY the "
    "numbered excerpts. Reply as JSON with keys label, banner, body, cites, follow.\n"
    f"label: one of {LABELS}.\n"
    'banner: null, or {"kind": "revised"|"historical"|"conflict"|"insuff", "text": "one sentence"}.\n'
    f"{BODY_FORMAT} Mark every claim with {{n}}, where n is the number of the excerpt that supports it.\n"
    'cites: one per excerpt you used, [{"excerpt": n, "quote": "the exact words copied from excerpt n '
    'that support your claim, at most 20 words"}].\n'
    "follow: up to 3 short follow-up questions the records could answer.\n"
    "Rules: Prefer Active documents. Use Superseded or Expired documents only for historical questions "
    "or to compare old and new rules, and say so (label Revised policy or Historical record, with a "
    "banner). If two Active documents disagree, label Conflicting instructions with a conflict banner and "
    "present both. If the excerpts do not answer the question, label Insufficient evidence with an insuff "
    "banner and say what the closest document does cover. If the question is too vague, label Needs "
    "clarification and offer 3 to 5 specific questions in an opts block. Never use outside knowledge. "
    "Never say 'excerpts'; call them documents or records. Write the answer in {lang}."
)


def block_text(b: dict) -> str:
    return " | ".join(b["text"]) if isinstance(b["text"], list) else b["text"]


def remove_document(doc_id: str) -> None:
    with engine.begin() as c:
        c.execute(blocks.delete().where(blocks.c.doc_id == doc_id))


def index_document(doc: dict) -> None:
    """Embed every paragraph of a document once and store it, replacing any older version."""
    paras = [(p, b) for p, page in enumerate(doc["pages"], 1) for b in page if block_text(b).strip()]
    vectors = embed([f"{doc['title']}\n{block_text(b)}" for _, b in paras]) if paras else []
    with engine.begin() as c:  # one transaction: the old version is only replaced if the new one lands
        c.execute(blocks.delete().where(blocks.c.doc_id == doc["id"]))
        if paras:
            c.execute(blocks.insert(), [
                {"doc_id": doc["id"], "page": p, "block": b["id"], "text": block_text(b), "embedding": v}
                for v, (p, b) in zip(vectors, paras)])


def _search(vector: list[float], ids: list[str], limit: int) -> list[dict]:
    """Closest paragraphs among the given documents, with a cosine similarity score."""
    if not ids:
        return []
    dist = blocks.c.embedding.cosine_distance(vector)
    q = (select(blocks.c.doc_id, blocks.c.page, blocks.c.block, blocks.c.text, (1 - dist).label("score"))
         .where(blocks.c.doc_id.in_(ids)).order_by(dist).limit(limit))
    with engine.connect() as c:
        return [dict(r._mapping) for r in c.execute(q)]


def answer(question: str, scope_ids: list[str], permitted_ids: list[str], docs: dict, lang: str) -> dict:
    """docs: id -> document record. Answers only from answerable documents inside the scope."""
    usable = lambda ids: [i for i in ids if i in docs and docs[i]["status"] in ANSWERABLE]  # noqa: E731
    vector = embed([question])[0]
    hits = _search(vector, usable(scope_ids), settings.top_k)
    result = _generate(question, hits, docs, lang) if hits else _INSUFFICIENT
    if result["label"] == "Insufficient evidence" and set(scope_ids) != set(permitted_ids):
        # Nothing in scope, but maybe in documents the person narrowed away: say which.
        outside = {h["doc_id"] for h in _search(vector, usable(permitted_ids), 5)
                   if h["score"] >= 0.4} - set(scope_ids)
        if outside:
            return {
                "source": "documents", "label": "Outside your scope", "cites": [], "follow": [],
                "missing": sorted(outside),
                "banner": {"kind": "scope", "text": "The documents needed for this answer are outside "
                                                    "the scope you selected."},
                "body": [{"p": "Your current scope doesn't include the records that answer this question. "
                               "These permitted documents look relevant:"},
                         {"ul": [f"**{docs[i]['title']}** ({docs[i]['ref']})" for i in sorted(outside)]}],
            }
    return result


def _generate(question: str, hits, docs: dict, lang: str) -> dict:
    def excerpt(n, p):
        d = docs[p["doc_id"]]
        dates = f"effective {d.get('effective') or '?'}" + (f" to {d['expiry']}" if d.get("expiry") else "")
        return f"[{n}] \"{d['title']}\" ({d['ref']}; {d['status']}; {dates}; page {p['page']})\n{p['text']}"

    res = chat(_SYSTEM.replace("{lang}", LANGS.get(lang, LANGS["auto"])),
               "Excerpts:\n" + "\n\n".join(excerpt(n, h) for n, h in enumerate(hits, 1))
               + f"\n\nQuestion: {question}", as_json=True)
    # Renumber excerpt references {n} as 1, 2, 3… in the order they first appear in the answer.
    quotes = {c.get("excerpt"): c.get("quote") for c in res.get("cites") or []}
    text = json.dumps(res.get("body") or [], ensure_ascii=False)
    order = list(dict.fromkeys(int(n) for n in re.findall(r"\{(\d+)\}", text) if 1 <= int(n) <= len(hits)))
    text = re.sub(r"\{(\d+)\}", lambda m: f"{{{order.index(int(m[1])) + 1}}}" if int(m[1]) in order else "", text)
    cites = []
    for n in order:
        p = hits[n - 1]
        quote = quotes.get(n) or ""
        cites.append({"doc": p["doc_id"], "page": p["page"], "block": p["block"],
                      "quote": quote if quote and quote in p["text"] else p["text"][:160]})
    return {"source": "documents", "label": res.get("label") if res.get("label") in LABELS else "One source",
            "banner": res.get("banner"), "body": json.loads(text), "cites": cites,
            "follow": (res.get("follow") or [])[:3]}


_INSUFFICIENT = {
    "source": "documents", "label": "Insufficient evidence", "cites": [], "follow": [],
    "banner": {"kind": "insuff", "text": "No document you can access answers this question. "
                                         "The assistant does not guess when the records are silent."},
    "body": [{"p": "I couldn't find this in the records available to you."}],
}
