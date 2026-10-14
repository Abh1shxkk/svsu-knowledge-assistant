"""Automatic answer-quality test.

The model writes questions from random paragraphs of published documents (in English, Hinglish and
Hindi, the way staff ask), together with the correct answer. Each question then goes through the real
search and answer steps, and the report says how often the right paragraph was found, the right
document cited and the answer judged correct.

Honest limit: questions written from a paragraph tend to reuse its words, so these figures are an
upper bound on what real, messier questions get. The same question set is kept and reused, so runs
can be compared; make a new set when many documents have been added.
"""
import random
from datetime import datetime

from sqlalchemy import func, select

from . import rag, store
from .config import settings
from .database import engine
from .llm import chat, embed
from .policy import ANSWERABLE

STYLES = ["a clear question in English",
          "an informal question in Hinglish (Hindi typed in English letters), as staff type on a phone",
          "a question in Hindi (Devanagari)"]
_WRITE = ("You write test questions for a search assistant over Swami Vivekanand Subharti University documents. "
          "From the passage, write ONE question a staff member might really ask whose answer is in the passage, "
          "and the short correct answer. Write the question as {style}. Don't copy the passage's sentences or "
          "mention 'the passage' or 'the document'. Reply as JSON {{\"question\": \"...\", \"answer\": \"...\"}}.")
_JUDGE = ("You check a search assistant. Given a question, the expected answer and the assistant's answer, decide "
          "whether the assistant's answer gives the expected facts correctly (wording, language and extra detail "
          "may differ; a wrong or missing date, number, name or code is incorrect; saying it cannot find the "
          "answer is incorrect). Reply as JSON {\"correct\": true or false}.")


def _published() -> dict[str, dict]:
    return {d["id"]: d for d in store.list_of("documents") if d.get("status") in ANSWERABLE}


def make_set(n: int) -> list[dict]:
    """n questions from random paragraphs long enough to hold an answer, spread across documents."""
    docs = list(_published())
    if not docs:
        return []
    q = (select(rag.blocks.c.doc_id, rag.blocks.c.page, rag.blocks.c.block, rag.blocks.c.text)
         .where(rag.blocks.c.doc_id.in_(docs), func.length(rag.blocks.c.text) >= 80)
         .order_by(func.random()).limit(n * 3))
    with engine.connect() as c:
        rows = [dict(r._mapping) for r in c.execute(q)]
    picked, per_doc = [], {}
    for r in rows:  # no more than a few paragraphs from any one document
        if per_doc.get(r["doc_id"], 0) < max(2, n // max(len(docs), 1)):
            picked.append(r)
            per_doc[r["doc_id"]] = per_doc.get(r["doc_id"], 0) + 1
        if len(picked) == n:
            break
    items = []
    for i, r in enumerate(picked):
        style = STYLES[i % len(STYLES)]
        res = chat(_WRITE.format(style=style), r["text"][:3000], as_json=True, model=settings.fast_model)
        if isinstance(res.get("question"), str) and isinstance(res.get("answer"), str):
            items.append({**{k: r[k] for k in ("doc_id", "page", "block")}, "question": res["question"],
                          "answer": res["answer"], "style": style.split(" (")[0]})
    store.put("eval", "set", {"id": "set", "made": datetime.now().isoformat(timespec="seconds"), "items": items})
    return items


def run(n: int = 50, new: bool = False) -> dict:
    saved = store.get("eval", "set")
    items = make_set(n) if new or not saved or not saved.get("items") else saved["items"][:n]
    docs = _published()
    top_k = int((store.get("settings", "ai") or {}).get("maxSources") or settings.top_k)
    results = []
    for it in items:
        if it["doc_id"] not in docs:  # the document was withdrawn or deleted since the set was made
            continue
        queries = rag.rewrite(it["question"], [])
        hits = rag._search_all(embed(queries), list(docs), top_k, rag.exact_terms(queries))
        found = any((h["doc_id"], h["page"], h["block"]) == (it["doc_id"], it["page"], it["block"]) for h in hits)
        answer = rag._generate(it["question"], hits, docs, "auto") if hits else dict(rag._INSUFFICIENT)
        said = " ".join(str(p.get("p") or p.get("sub") or " ".join(map(str, p.get("ul") or [])) or "") for p in answer["body"])
        verdict = chat(_JUDGE, f"Question: {it['question']}\nExpected answer: {it['answer']}\nAssistant's answer: {said}",
                       as_json=True, model=settings.fast_model, temperature=0)
        results.append({**it, "found": found, "doc_found": any(h["doc_id"] == it["doc_id"] for h in hits),
                        "cited": any(c["doc"] == it["doc_id"] for c in answer.get("cites", [])),
                        "correct": verdict.get("correct") is True, "got": said[:400]})
    pct = lambda key: round(100 * sum(r[key] for r in results) / len(results)) if results else 0  # noqa: E731
    by_style = {s: round(100 * sum(r["correct"] for r in rs) / len(rs)) for s in {r["style"] for r in results}
                if (rs := [r for r in results if r["style"] == s])}
    report = {
        "id": "run-" + datetime.now().strftime("%Y%m%d-%H%M%S"), "at": datetime.now().isoformat(timespec="seconds"),
        "questions": len(results), "paragraph_found": pct("found"), "document_found": pct("doc_found"),
        "cited_right_document": pct("cited"), "answered_correctly": pct("correct"), "correct_by_style": by_style,
        "misses": [{k: r[k] for k in ("question", "answer", "got", "found")} for r in results if not r["correct"]][:40],
    }
    store.put("eval", report["id"], report)
    return {k: v for k, v in report.items() if k != "misses"}


def latest() -> dict | None:
    runs = [r for r in store.list_of("eval") if r.get("id", "").startswith("run-")]
    return max(runs, key=lambda r: r["at"]) if runs else None
