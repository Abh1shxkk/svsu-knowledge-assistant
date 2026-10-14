"""Document engine: every paragraph is embedded once (at upload) and stored in PostgreSQL with
pgvector. A question is embedded, matched against the stored vectors within the asker's scope, and
answered with citations. No OCR or re-reading of files happens at search time."""
import json
import re
from pgvector.sqlalchemy import Vector
from datetime import date
from sqlalchemy import Column, Integer, String, Table, Text, case, literal, select, text

from .config import settings
from .database import engine, meta
from .llm import chat, embed
from .policy import ANSWERABLE

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
LABELS = ["One source", "Multiple sources", "Revised policy", "Historical record",
          "Conflicting instructions", "Insufficient evidence", "Needs clarification"]
LANGS = {"en": "English", "hi": "Hindi (Devanagari script)",
         "auto": "the same language and script as the question (Hindi typed in English letters, "
                 "i.e. Hinglish, gets a simple Hinglish answer in English letters)"}
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
    "Rules: Prefer Active documents. {history_rule} If two Active documents disagree, label Conflicting instructions with a conflict banner and "
    "present both. If the excerpts do not answer the question, label Insufficient evidence with an insuff "
    "banner and say what the closest document does cover. If the question is too vague, label Needs "
    "clarification and offer 3 to 5 specific questions in an opts block. Never use outside knowledge. "
    "Never say 'excerpts'; call them documents or records. Write the answer in {lang}."
)


def _today() -> str:
    return f"{date.today():%d %B %Y} ({date.today():%d/%m/%Y})"


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
    q = (select(blocks.c.id, blocks.c.doc_id, blocks.c.page, blocks.c.block, blocks.c.text, (1 - dist).label("score"))
         .where(blocks.c.doc_id.in_(ids)).order_by(dist).limit(limit))
    with engine.connect() as c:
        return [dict(r._mapping) for r in c.execute(q)]


def similar(doc_id: str, ids: list[str], probes: int = 5) -> dict[str, float]:
    """Other documents (among ids) whose paragraphs most closely match this one's first paragraphs."""
    with engine.connect() as c:
        vectors = list(c.scalars(select(blocks.c.embedding).where(blocks.c.doc_id == doc_id)
                                 .order_by(blocks.c.id).limit(probes)))
    best: dict[str, float] = {}
    for v in vectors:
        for h in _search(list(v), [i for i in ids if i != doc_id], 1):
            best[h["doc_id"]] = max(best.get(h["doc_id"], 0.0), h["score"])
    return best


_REWRITE = (
    "You turn a staff member's question into queries for a semantic search over Swami Vivekanand Subharti "
    "University's official documents (notices, circulars, policies), written in English and Hindi. "
    "Write 2 or 3 short, self-contained search queries: one in English, one in Hindi (Devanagari), and one "
    "more only if the question has a second part. Expand abbreviations and informal wording (CL = casual "
    "leave, EL = earned leave, kitne = how many). If it is a follow-up, use the earlier questions to say "
    "what it refers to. Keep names, dates, codes and reference numbers exactly, and also write any date as "
    "DD/MM/YYYY (documents write dates that way); use today's date for words like today, now or next. "
    "Do not answer the question. "
    'Reply as JSON {"queries": ["...", "..."]}.'
)


def rewrite(question: str, history: list[str]) -> list[str]:
    """The LLM only rewrites the question for search; the search itself is semantic (pgvector)."""
    earlier = "\n".join(f"- {h}" for h in history[-3:])
    res = chat(_REWRITE, f"Today: {_today()}\n" + (f"Earlier questions:\n{earlier}\n\n" if earlier else "")
               + f"Question: {question}",
               as_json=True, model=settings.fast_model)
    queries = [q.strip() for q in res.get("queries") or [] if isinstance(q, str) and q.strip()][:3]
    return list(dict.fromkeys([question, *queries]))  # the person's own words are always searched too


_PER_DOC = 3  # so one long document can't crowd out the others (e.g. old vs new rules)

# Codes, reference numbers and dates: meaning-based search can miss these, so they are also matched exactly.
_EXACT = re.compile(r"[A-Za-z0-9]+(?:[-/.][A-Za-z0-9]+)+|[A-Za-z]*\d[A-Za-z0-9]*|\b[A-Z]{2,}\b")


def exact_terms(queries: list[str]) -> list[str]:
    terms = {t for q in queries for t in _EXACT.findall(q)
             if len(t) >= 3 and not (t.isdigit() and len(t) <= 4)}  # bare numbers like 12 or 2026 match everything
    return sorted(terms)[:8]


def _like(t: str) -> str:
    return "%" + t.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def _keyword(terms: list[str], ids: list[str], limit: int) -> list[dict]:
    """Paragraphs containing the exact terms (any case), the most terms first."""
    if not terms or not ids:
        return []
    found = sum((case((blocks.c.text.ilike(_like(t)), 1), else_=0) for t in terms), literal(0))
    q = (select(blocks.c.id, blocks.c.doc_id, blocks.c.page, blocks.c.block, blocks.c.text, found.label("found"))
         .where(blocks.c.doc_id.in_(ids), found > 0).order_by(found.desc()).limit(limit))
    with engine.connect() as c:
        return [dict(r._mapping) for r in c.execute(q)]


def _search_all(vectors: list[list[float]], ids: list[str], limit: int, terms: list[str] = ()) -> list[dict]:
    """Meaning-based search with every query plus exact matches of codes and dates, merged by rank
    (reciprocal rank fusion), with a cap on paragraphs per document."""
    best: dict[tuple, dict] = {}
    for v in vectors:
        for h in _search(v, ids, limit * 3):
            key = (h["doc_id"], h["page"], h["block"])
            if key not in best or h["score"] > best[key]["score"]:
                best[key] = h
    rank: dict[tuple, float] = {}
    for r, h in enumerate(sorted(best.values(), key=lambda h: -h["score"])):
        rank[(h["doc_id"], h["page"], h["block"])] = 1 / (60 + r)
    for r, h in enumerate(_keyword(list(terms), ids, limit * 3)):
        key = (h["doc_id"], h["page"], h["block"])
        rank[key] = rank.get(key, 0) + 1 / (60 + r)
        best.setdefault(key, {**{k: h[k] for k in ("id", "doc_id", "page", "block", "text")}, "score": 0.0})
    picked, per_doc = [], {}
    for h in sorted(best.values(), key=lambda h: -rank[(h["doc_id"], h["page"], h["block"])]):
        if per_doc.get(h["doc_id"], 0) < _PER_DOC:
            picked.append(h)
            per_doc[h["doc_id"]] = per_doc.get(h["doc_id"], 0) + 1
        if len(picked) == limit:
            break
    return picked


_HISTORY_RULES = {
    True: "Use Superseded or Expired documents only for historical questions or to compare old and new "
          "rules, and say so (label Revised policy or Historical record, with a banner).",
    False: "Superseded or Expired documents may be used, but always say they are no longer in force "
           "(label Revised policy or Historical record, with a banner).",
}


def answer(question: str, scope_ids: list[str], permitted_ids: list[str], docs: dict, lang: str,
           history: list[str] = (), ai: dict | None = None) -> dict:
    """docs: id -> document record. Answers only from answerable documents inside the scope.

    1. the LLM rewrites the question into search queries, 2. semantic search finds the paragraphs,
    3. the LLM writes the answer from those paragraphs only, citing each one.
    """
    usable = lambda ids: [i for i in ids if i in docs and docs[i]["status"] in ANSWERABLE]  # noqa: E731
    queries = rewrite(question, list(history))
    vectors = embed(queries)
    ai = ai or {}
    terms = exact_terms(queries)
    hits = _search_all(vectors, usable(scope_ids), int(ai.get("maxSources") or settings.top_k), terms)
    result = _generate(question, hits, docs, lang, ai.get("histOnly", True) is not False) if hits else dict(_INSUFFICIENT)
    result["queries"] = queries[1:] or queries
    if result["label"] == "Insufficient evidence" and set(scope_ids) != set(permitted_ids):
        # Nothing in scope, but maybe in documents the person narrowed away: say which.
        outside = {h["doc_id"] for h in _search_all(vectors, usable(permitted_ids), 5, terms)
                   if h["score"] >= 0.4} - set(scope_ids)
        if outside:
            return {
                "source": "documents", "label": "Outside your scope", "cites": [], "follow": [],
                "queries": result["queries"], "missing": sorted(outside),
                "banner": {"kind": "scope", "text": "The documents needed for this answer are outside "
                                                    "the scope you selected."},
                "body": [{"p": "Your current scope doesn't include the records that answer this question. "
                               "These permitted documents look relevant:"},
                         {"ul": [f"**{docs[i]['title']}** ({docs[i]['ref']})" for i in sorted(outside)]}],
            }
    return result


def _neighbours(hits: list[dict]) -> dict[int, str]:
    """Each hit's text with the paragraph before and after it in the same document (block ids follow the
    document's order), so a sentence that continues in the next paragraph still reaches the answer."""
    ids = [h["id"] for h in hits if h.get("id")]
    if not ids:
        return {}
    wanted = {i + d for i in ids for d in (-1, 0, 1)}
    with engine.connect() as c:
        rows = {r.id: r for r in c.execute(select(blocks.c.id, blocks.c.doc_id, blocks.c.text).where(blocks.c.id.in_(wanted)))}
    out = {}
    for h in hits:
        i = h.get("id")
        if i in rows:
            parts = [rows[j].text for j in (i - 1, i, i + 1) if j in rows and rows[j].doc_id == rows[i].doc_id]
            out[i] = "\n".join(parts)
    return out


def _text(x) -> str:
    """The model sometimes wraps a string in an object ({"question": "..."}); the screens need plain text."""
    if isinstance(x, str):
        return x
    if isinstance(x, dict):
        return next((str(v) for v in x.values() if isinstance(v, (str, int, float))), "")
    return "" if x is None else str(x)


def _clean_body(body) -> list[dict]:
    """Keep only the block shapes the screens draw, with every piece of text a string."""
    out: list[dict] = []
    for part in body if isinstance(body, list) else []:
        if isinstance(part, str):
            part = {"p": part}
        if not isinstance(part, dict):
            continue
        for key in ("p", "sub"):
            if key in part:
                out.append({key: _text(part[key])})
        for key in ("ul", "opts"):
            if isinstance(part.get(key), list):
                out.append({key: [t for t in map(_text, part[key]) if t]})
        if isinstance(part.get("table"), dict):
            t = part["table"]
            out.append({"table": {"head": [_text(h) for h in t.get("head") or []],
                                  "rows": [[_text(c) for c in r] for r in t.get("rows") or [] if isinstance(r, list)]}})
    return out


def _clean_banner(b) -> dict | None:
    return {"kind": _text(b.get("kind")), "text": _text(b.get("text"))} if isinstance(b, dict) and b.get("text") else None


def _generate(question: str, hits, docs: dict, lang: str, hist_only: bool = True) -> dict:
    around = _neighbours(hits)

    def excerpt(n, p):
        d = docs[p["doc_id"]]
        dates = f"effective {d.get('effective') or '?'}" + (f" to {d['expiry']}" if d.get("expiry") else "")
        return f"[{n}] \"{d['title']}\" ({d['ref']}; {d['status']}; {dates}; page {p['page']})\n{around.get(p.get('id'), p['text'])}"

    system = _SYSTEM.replace("{lang}", LANGS.get(lang, LANGS["auto"])).replace("{history_rule}", _HISTORY_RULES[hist_only])
    res = chat(system,
               "Excerpts:\n" + "\n\n".join(excerpt(n, h) for n, h in enumerate(hits, 1))
               + f"\n\nToday's date: {_today()} (anything dated earlier has already happened)."
               + f"\nQuestion: {question}", as_json=True)
    # The model's own list of the excerpts it used (numbers may arrive as text).
    listed = {int(c["excerpt"]): c.get("quote") for c in res.get("cites") or []
              if isinstance(c, dict) and str(c.get("excerpt", "")).strip().isdigit() and 1 <= int(c["excerpt"]) <= len(hits)}
    body = _clean_body(res.get("body"))
    if listed and not re.search(r"\{\d+\}", json.dumps(body)):
        # It listed sources but left out the {n} markers: cite them at the end of the answer, never drop them.
        marks = " " + "".join(f"{{{n}}}" for n in listed)
        last = next((p for p in reversed(body) if isinstance(p, dict) and isinstance(p.get("p"), str)), None)
        if last:
            last["p"] += marks
        else:
            body.append({"sub": "Sources:" + marks})
    # Renumber excerpt references {n} as 1, 2, 3… in the order they first appear in the answer.
    quotes = listed
    text = json.dumps(body, ensure_ascii=False)
    order = list(dict.fromkeys(int(n) for n in re.findall(r"\{(\d+)\}", text) if 1 <= int(n) <= len(hits)))
    text = re.sub(r"\{(\d+)\}", lambda m: f"{{{order.index(int(m[1])) + 1}}}" if int(m[1]) in order else "", text)
    cites = []
    for n in order:
        p = hits[n - 1]
        quote = quotes.get(n) or ""
        cites.append({"doc": p["doc_id"], "page": p["page"], "block": p["block"],
                      "quote": quote if quote and quote in p["text"] else p["text"][:160]})  # quotes from the context fall back
    return {"source": "documents", "label": res.get("label") if res.get("label") in LABELS else "One source",
            "banner": _clean_banner(res.get("banner")), "body": json.loads(text), "cites": cites,
            "follow": [t for t in map(_text, res.get("follow") or []) if t][:3]}


_INSUFFICIENT = {
    "source": "documents", "label": "Insufficient evidence", "cites": [], "follow": [],
    "banner": {"kind": "insuff", "text": "No document you can access answers this question. "
                                         "The assistant does not guess when the records are silent."},
    "body": [{"p": "I couldn't find this in the records available to you."}],
}
