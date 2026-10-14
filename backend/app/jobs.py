"""Background work — bulk imports and quality tests — run here, one job at a time, outside web requests.

The queue is a table in the same PostgreSQL database, so no extra service is needed. Any number of
workers can share it safely (each claims a job with FOR UPDATE SKIP LOCKED): the API runs one, and a
bigger server can add more with `python -m app.cli worker`.
"""
import time
import uuid
from datetime import date

from sqlalchemy import Column, DateTime, Integer, String, Table, Text, func, select, text, update
from sqlalchemy.dialects.postgresql import JSONB

from . import extract, rag, store
from .database import engine, meta
from .rag import block_text

jobs = Table(
    "jobs", meta,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("kind", String(20), nullable=False),                  # import | evaluate
    Column("batch", String(64), nullable=False, index=True),     # jobs started together
    Column("status", String(12), nullable=False, index=True),    # queued | running | done | duplicate | failed
    Column("data", JSONB, nullable=False),
    Column("result", JSONB),
    Column("error", Text),
    Column("updated", DateTime, server_default=func.now(), onupdate=func.now()),
)
meta.create_all(engine, tables=[jobs])


def add(kind: str, batch: str, data: dict) -> None:
    with engine.begin() as c:
        c.execute(jobs.insert().values(kind=kind, batch=batch, status="queued", data=data))


def requeue_stuck() -> None:
    """Jobs left running when the server stopped start again."""
    with engine.begin() as c:
        c.execute(update(jobs).where(jobs.c.status == "running").values(status="queued"))


def _claim() -> dict | None:
    with engine.begin() as c:
        row = c.execute(text(
            "UPDATE jobs SET status = 'running', updated = now() WHERE id = (SELECT id FROM jobs "
            "WHERE status = 'queued' ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1) "
            "RETURNING id, kind, batch, data")).first()
    return dict(row._mapping) if row else None


def _finish(job_id: int, status: str, result: dict | None = None, error: str | None = None) -> None:
    with engine.begin() as c:
        c.execute(update(jobs).where(jobs.c.id == job_id).values(status=status, result=result, error=error))


def run_once() -> bool:
    """Do the next queued job, if any. A failure is recorded on the job, never raised."""
    job = _claim()
    if not job:
        return False
    try:
        status, result = _HANDLERS[job["kind"]](job["data"])
        _finish(job["id"], status, result)
    except Exception as e:  # noqa: BLE001 — record any failure on the job so it can be retried
        _finish(job["id"], "failed", error=f"{type(e).__name__}: {e}"[:500])
    return True


def work_forever(idle: float = 3.0) -> None:
    while True:
        if not run_once():
            time.sleep(idle)


def batches(login_id: str | None, kind: str = "import") -> list[dict]:
    """Progress of each batch (newest first); login_id=None means everyone's (administrators)."""
    q = select(jobs.c.batch, jobs.c.status, jobs.c.data, jobs.c.result, jobs.c.error, jobs.c.updated).where(jobs.c.kind == kind)
    if login_id is not None:
        q = q.where(jobs.c.data["by_login"].astext == login_id)
    out: dict[str, dict] = {}
    with engine.connect() as c:
        for r in c.execute(q.order_by(jobs.c.id)):
            b = out.setdefault(r.batch, {"batch": r.batch, "by": r.data.get("by_name", ""), "publish": r.data.get("publish", False),
                                         "counts": {}, "failed": [], "updated": None})
            b["counts"][r.status] = b["counts"].get(r.status, 0) + 1
            b["updated"] = max(filter(None, [b["updated"], r.updated.isoformat(timespec="seconds") if r.updated else None]), default=None)
            if r.status == "failed":
                b["failed"].append({"name": r.data.get("name", ""), "error": r.error or ""})
    return sorted(out.values(), key=lambda b: b["updated"] or "", reverse=True)


def retry(batch: str, login_id: str | None) -> int:
    q = update(jobs).where(jobs.c.batch == batch, jobs.c.status == "failed")
    if login_id is not None:
        q = q.where(jobs.c.data["by_login"].astext == login_id)
    with engine.begin() as c:
        return c.execute(q.values(status="queued", error=None)).rowcount


# ---------- bulk import ----------

def _import(d: dict) -> tuple[str, dict]:
    """Read one stored upload, fill in its details with the AI's suggestions and the batch settings,
    index it and save it — published, or waiting for approval."""
    stored = store.get_file(d["key"])
    if not stored:
        raise ValueError("The uploaded file is missing.")
    name, _, raw = stored
    ex = extract.extract(name, raw)
    if not any(ex["pages"]):
        raise ValueError("No text could be read from this file.")
    fingerprint = extract.text_hash(ex["pages"])
    dup = next((x for x in store.list_of("documents") if fingerprint and x.get("text_hash") == fingerprint), None)
    if dup:
        return "duplicate", {"doc": dup["id"], "title": dup.get("title", "")}
    lists = store.get("settings", "lists") or {}
    sg = extract.suggest(ex["pages"], name, lists)
    today, by = date.today().isoformat(), d["by_name"]
    text_all = " ".join(block_text(b) for page in ex["pages"] for b in page)
    doc = {
        "id": "D" + uuid.uuid4().hex[:12], "title": sg.get("title") or name.rsplit(".", 1)[0].replace("_", " "),
        "ref": sg.get("ref", ""), "type": sg.get("type", ""), "authority": sg.get("authority", ""),
        "dept": d.get("dept") or sg.get("dept", ""), "institution": (lists.get("INSTS") or [""])[0],
        "date": sg.get("date", ""), "effective": sg.get("effective") or sg.get("date", ""), "expiry": sg.get("expiry", ""),
        "audience": sg.get("audience", []), "tags": sg.get("tags", []), "visibility": d["visibility"],
        "status": "Active" if d["publish"] else "Pending", "fileType": ex["kind"],
        "lang": "hi" if sum("ऀ" <= ch <= "ॿ" for ch in text_all) > len(text_all) * 0.2 else "en",
        "description": sg.get("description", ""), "uploadedBy": by, "uploadedOn": today, "uploader_id": d["by_login"],
        "related": [], "revisionOf": None, "supersededBy": None,
        "versions": [{"v": "1.0", "date": today, "by": by, "note": "Bulk import"}],
        "approvals": [{"step": "Imported in bulk and published" if d["publish"] else "Imported in bulk", "by": by,
                       "date": today, "kind": "ok" if d["publish"] else "", "note": name}],
        "pages": ex["pages"], "file": extract.keep_original(name, raw), "text_hash": fingerprint,
        "unsure": ex.get("unsure", []), **({"ocr": ex["ocr"]} if ex.get("ocr") is not None else {}),
    }
    rag.index_document(doc)
    store.put("documents", doc["id"], doc)
    store.audit(by, "Imported" if d["publish"] else "Submitted", doc["title"])
    return "done", {"doc": doc["id"], "title": doc["title"]}


def _evaluate(d: dict) -> tuple[str, dict]:
    from . import evaluate  # only when a test runs
    return "done", evaluate.run(int(d.get("n", 50)), bool(d.get("new")))


_HANDLERS = {"import": _import, "evaluate": _evaluate}


# ---------- expiry ----------

def expire_documents(today: date | None = None) -> list[str]:
    """Active documents past their expiry date become Expired: still found for history questions,
    never answered from as if current. Runs hourly; returns the titles it expired."""
    today_s, done = (today or date.today()).isoformat(), []
    for light in store.list_of("documents"):
        if light.get("status") == "Active" and light.get("expiry") and light["expiry"] < today_s:
            d = store.get("documents", light["id"])
            d["status"] = "Expired"
            d["approvals"] = [*d.get("approvals", []), {"step": "Expired automatically", "by": "System",
                                                        "date": today_s, "kind": "warn", "note": f"Expiry date {d['expiry']}"}]
            store.put("documents", d["id"], d)
            store.audit("System", "Expired", d["title"])
            done.append(d["title"])
    return done
