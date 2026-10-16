"""SVSU Knowledge Assistant API."""
import asyncio
import json
import re
import uuid
from contextlib import asynccontextmanager, suppress
from datetime import date, datetime, timedelta
from pathlib import Path
import pymupdf
from fastapi import Body, Form, Depends, FastAPI, HTTPException, Query, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from . import auth, evaluate, export, extract, jobs, llm, locate, mfa, notices, policy, rag, store
from .config import settings


async def _hourly_loop():
    while True:  # each reminder goes out at most once a day
        with suppress(Exception):
            await asyncio.to_thread(jobs.expire_documents)
        if settings.smtp_host:
            with suppress(Exception):
                await asyncio.to_thread(notices.send_due_reminders)
        await asyncio.sleep(3600)


async def _worker_loop():
    while True:  # one background job at a time; sleeps while the queue is empty
        try:
            busy = await asyncio.to_thread(jobs.run_once)
        except Exception:  # noqa: BLE001 — e.g. the database restarting; try again shortly
            busy = False
        if not busy:
            await asyncio.sleep(3)


@asynccontextmanager
async def lifespan(_: FastAPI):
    if store.is_empty():
        _seed()
    jobs.requeue_stuck()
    tasks = [asyncio.create_task(loop()) for loop in (_hourly_loop, _worker_loop)] if settings.run_worker else []
    yield
    for t in tasks:
        t.cancel()


app = FastAPI(title="SVSU Knowledge Assistant", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=[o.strip() for o in settings.cors_origins.split(",") if o.strip()],
                   allow_methods=["*"], allow_headers=["*"])

Approver = Depends(auth.require_role(*policy.APPROVERS))
Admin = Depends(auth.require_role("Administrator"))


class Login(BaseModel):
    login_id: str
    password: str


class Ask(BaseModel):
    question: str
    scope_ids: list[str]       # documents the person chose to search (narrowed to what they may see)
    lang: str = "auto"         # auto | en | hi
    history: list[str] = []    # earlier questions in this chat, so follow-ups can be rewritten


@app.get("/health")
def health():
    return {"ok": True}


_LOCKED = "Too many wrong attempts. Wait 5 minutes and try again."


@app.post("/login")
def login(body: Login):
    """The password; then, for people with two-step verification (or whose role requires it), a ticket
    for /login/mfa instead of a session."""
    login_id = body.login_id.strip()
    if mfa.locked(login_id):
        raise HTTPException(429, _LOCKED)
    user = auth.verify(login_id, body.password)
    if not user:
        mfa.failed(login_id)
        raise HTTPException(401, "Wrong Login ID or password.")
    user["role"] = auth.app_role(login_id)
    if not user.get("dev") and (mfa.is_on(login_id) or mfa.required(user["role"])):
        return {"mfa": "code" if mfa.is_on(login_id) else "setup", "ticket": auth.make_ticket(login_id)}
    mfa.succeeded(login_id)
    return _session(user)


def _session(user: dict) -> dict:
    if rec := auth.user_record(user["login_id"]):  # shown as "Last active" in Administration
        store.put("users", rec["id"], {**rec, "last": store.stamp(datetime.now())})
    return {"token": auth.make_token(user, user["role"]), "user": user}


class Ticket(BaseModel):
    ticket: str
    code: str = ""


@app.post("/login/mfa/setup")
def login_mfa_setup(body: Ticket):
    """Setting up two-step verification during sign-in, when the person's role requires it."""
    login_id = auth.read_ticket(body.ticket)
    if mfa.is_on(login_id):
        raise HTTPException(400, "Two-step verification is already set up.")
    return mfa.start(login_id)


@app.post("/login/mfa")
def login_mfa(body: Ticket):
    """The code from the authenticator app (or a recovery code). During set-up, the first code switches
    two-step verification on and the recovery codes come back once."""
    login_id = auth.read_ticket(body.ticket)
    if mfa.locked(login_id):
        raise HTTPException(429, _LOCKED)
    rec = auth.user_record(login_id)
    if not rec or rec.get("active") is False:
        raise HTTPException(401, "Your account is no longer active.")
    on = mfa.is_on(login_id)
    recovery = None if on else mfa.enable(login_id, body.code)
    if not (mfa.check(login_id, body.code) if on else recovery):
        mfa.failed(login_id)
        raise HTTPException(401, "That code isn't right. Check that your phone's clock is correct and try again.")
    mfa.succeeded(login_id)
    user = {**auth._profile(login_id, rec), "role": auth.app_role(login_id)}
    if recovery:
        _audit(user, "Turned on two-step verification", login_id)
    return {**_session(user), **({"recovery": recovery} if recovery else {})}


@app.get("/me")
def me(user: dict = Depends(auth.current_user)):
    return user


class Account(BaseModel):
    login_id: str
    name: str
    email: str = ""
    dept: str = ""
    role: str = "Viewer"
    password: str


class PasswordReset(BaseModel):
    password: str


@app.post("/accounts")
def create_account(body: Account, admin: dict = Admin):
    login_id = body.login_id.strip()
    if not login_id:
        raise HTTPException(400, "Login ID is required.")
    if err := auth.password_problem(body.password):
        raise HTTPException(400, err)
    if store.get_credential(login_id) or auth.user_record(login_id):
        raise HTTPException(409, "An account with that Login ID already exists.")
    role = body.role if body.role in auth.ROLES else "Viewer"
    store.put("users", "us-" + login_id, {
        "id": "us-" + login_id, "login_id": login_id, "name": body.name, "email": body.email,
        "dept": body.dept, "role": role, "active": True, "last": "Never",
    })
    store.set_credential(login_id, auth.hash_password(body.password))
    _audit(admin, "Added user", f"{body.name} ({login_id}) as {role}")
    return {"ok": True}


class Profile(BaseModel):
    name: str
    email: str = ""


@app.put("/me/profile")
def update_profile(body: Profile, user: dict = Depends(auth.current_user)):
    """People edit their own name and email. Role and department are set by an administrator,
    because they decide what the person may see."""
    if user.get("dev"):
        raise HTTPException(400, "The local test admin has no profile. Create a real account to use this.")
    name, email = body.name.strip(), body.email.strip()
    if not name:
        raise HTTPException(400, "Enter your name.")
    if email and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        raise HTTPException(400, "That email address doesn't look right.")
    rec = auth.user_record(user["login_id"])
    store.put("users", rec["id"], {**rec, "name": name, "email": email})
    _audit({**user, "name": name}, "Updated profile", f"{name} ({user['login_id']})")
    return {**user, "name": name, "email": email}


class PasswordChange(BaseModel):
    current: str
    new: str


@app.put("/me/password")
def change_own_password(body: PasswordChange, user: dict = Depends(auth.current_user)):
    if user.get("dev"):
        raise HTTPException(400, "The local test admin's password is set in backend/.env.")
    if not auth.verify(user["login_id"], body.current):
        raise HTTPException(400, "Your current password is wrong.")
    if err := auth.password_problem(body.new):
        raise HTTPException(400, err)
    store.set_credential(user["login_id"], auth.hash_password(body.new))
    return {"ok": True}


@app.get("/me/mfa")
def my_mfa(user: dict = Depends(auth.current_user)):
    return {**mfa.status(user["login_id"]), "required": mfa.required(user["role"])}


@app.post("/me/mfa/setup")
def my_mfa_setup(user: dict = Depends(auth.current_user)):
    if user.get("dev"):
        raise HTTPException(400, "The local test admin can't use two-step verification. Create a real account.")
    if mfa.is_on(user["login_id"]):
        raise HTTPException(400, "Two-step verification is already on.")
    return mfa.start(user["login_id"])


class Code(BaseModel):
    code: str


@app.post("/me/mfa/enable")
def my_mfa_enable(body: Code, user: dict = Depends(auth.current_user)):
    codes = mfa.enable(user["login_id"], body.code)
    if not codes:
        raise HTTPException(400, "That code isn't right. Check that your phone's clock is correct and try again.")
    _audit(user, "Turned on two-step verification", user["login_id"])
    return {"recovery": codes}


@app.post("/me/mfa/disable")
def my_mfa_disable(body: PasswordReset, user: dict = Depends(auth.current_user)):
    if mfa.required(user["role"]):
        raise HTTPException(400, "Two-step verification is required for your role.")
    if not auth.verify(user["login_id"], body.password):
        raise HTTPException(400, "Your password is wrong.")
    mfa.remove(user["login_id"])
    _audit(user, "Turned off two-step verification", user["login_id"])
    return {"ok": True}


@app.get("/accounts/mfa")
def accounts_mfa(admin: dict = Admin):
    """Who has two-step verification on, for the Users list."""
    return [u["login_id"] for u in store.list_of("users") if u.get("login_id") and mfa.is_on(u["login_id"])]


@app.delete("/accounts/{login_id}/mfa")
def reset_mfa(login_id: str, admin: dict = Admin):
    """For a lost phone: the person signs in with the password and sets it up again."""
    mfa.remove(login_id)
    _audit(admin, "Reset two-step verification", login_id)
    return {"ok": True}


@app.put("/accounts/{login_id}/password")
def reset_password(login_id: str, body: PasswordReset, admin: dict = Admin):
    if err := auth.password_problem(body.password):
        raise HTTPException(400, err)
    store.set_credential(login_id, auth.hash_password(body.password))
    _audit(admin, "Reset password", login_id)
    return {"ok": True}


@app.get("/records")
def get_records(user: dict = Depends(auth.current_user)):
    """Everything the screens list, filtered to this person. Documents come without their text."""
    return policy.visible_records(user, store.records_of(*(store.KINDS - {"questions"})))


@app.get("/documents/{doc_id}")
def get_document(doc_id: str, user: dict = Depends(auth.current_user)):
    """One document with its full text."""
    return _visible_doc(user, doc_id)


@app.get("/search")
def search(q: str, user: dict = Depends(auth.current_user)):
    """Ids of documents whose details or text contain q."""
    ctx = _ctx()
    return [d["id"] for d in store.search_documents(q.strip()) if q.strip() and policy.can_view(user, d, ctx)]


@app.put("/records/{kind}/{id}")
def put_record(kind: str, id: str, data: dict = Body(...), user: dict = Depends(auth.current_user)):
    _check_kind(kind)
    old = store.get(kind, id)
    if err := policy.write_error(user, kind, data, old, _ctx()):
        raise HTTPException(403, err)
    data["id"] = id
    if kind in policy.OWNED or kind in ("collections", "feedback"):  # the server, not the browser, records the owner
        data["owner"] = (old or {}).get("owner") or user["login_id"]
    if kind == "users":
        _check_user_change(user, data, old)
    if kind == "deadlines":  # only for documents this person can see, before and after
        for doc_id in {(old or {}).get("doc"), data.get("doc")} - {None}:
            _visible_doc(user, doc_id)
    if kind == "reminders":
        dl = store.get("deadlines", data.get("deadline", ""))
        if not dl:
            raise HTTPException(404, "Deadline not found")
        _visible_doc(user, dl.get("doc", ""))
    if kind == "collections" and old:  # keep documents this person can't see; they were filtered out of their copy
        ctx = _ctx()
        hidden = [i for i in old.get("docs", []) if (d := store.get("documents", i)) and not policy.can_view(user, d, ctx)]
        data["docs"] = list(dict.fromkeys([*data.get("docs", []), *hidden]))
    if kind == "documents":
        if "pages" in data and not _valid_pages(data["pages"]):  # e.g. text corrected in the browser
            raise HTTPException(400, "The document text isn't in the expected form.")
        data["uploader_id"] = old.get("uploader_id") if old else user["login_id"]
        if old and "pages" not in data:  # metadata edits from lists that don't carry the text
            data["pages"] = old.get("pages", [])
        data["text_hash"] = extract.text_hash(data.get("pages") or [])
        f = data.get("file")
        if f != (old or {}).get("file") and not (isinstance(f, dict) and store.has_file(str(f.get("key", "")))):
            data["file"] = (old or {}).get("file")  # only files that were really uploaded
        if old is None or old.get("pages") != data.get("pages"):
            rag.index_document(data)  # index first: a failure saves nothing
    store.put(kind, id, data)
    if action := _audit_action(kind, data, old):
        _audit(user, *action)
    return {"ok": True}


@app.delete("/records/{kind}/{id}")
def delete_record(kind: str, id: str, user: dict = Depends(auth.current_user)):
    _check_kind(kind)
    old = store.get(kind, id)
    if old is None:
        raise HTTPException(404, "Not found")
    if err := policy.write_error(user, kind, None, old, _ctx()):
        raise HTTPException(403, err)
    if kind == "deadlines" and old.get("doc"):
        _visible_doc(user, old["doc"])
    if kind == "users":
        _check_user_change(user, None, old)
        if old.get("login_id"):
            store.delete_credential(str(old["login_id"]))
            mfa.remove(str(old["login_id"]))
            _forget_owner(str(old["login_id"]))
        _audit(user, "Deleted user", f"{old.get('name', '')} ({old.get('login_id', '')})")
    if kind == "deadlines":
        _forget_deadline(id)
    if kind == "chats":  # bookmarks of its answers go with it
        for b in store.list_of("bm_answers"):
            if b.get("chat") == id:
                store.delete("bm_answers", b["id"])
    store.delete(kind, id)
    if kind == "documents":
        rag.remove_document(id)
        _forget_document(id)
        key = (old.get("file") or {}).get("key")
        if key and not any((d.get("file") or {}).get("key") == key for d in store.list_of("documents")):
            store.delete_file(key)  # no other document uses this upload
        _audit(user, "Deleted", old.get("title", id))
    return {"ok": True}


def _answer_events(body: Ask, user: dict):
    ctx, ai = _ctx(), _setting("ai")
    docs = {d["id"]: d for d in store.list_of("documents") if policy.can_answer(user, d, ctx)}
    scope = [i for i in body.scope_ids if i in docs]  # never more than this person may see
    for e in rag.answer_events(body.question, scope, list(docs), docs, body.lang, body.history, ai):
        if "done" in e:
            result, now = e["done"], datetime.now()
            store.put("questions", uuid.uuid4().hex, {  # usage figures for Reports; who asked is not kept
                "at": now.isoformat(timespec="seconds"), "label": result["label"], "cited": bool(result.get("cites")),
                "dept": user.get("dept", "")})
            if result["label"] == "Insufficient evidence" and ai.get("logUnans", True):
                _log_unanswered(body.question, user.get("dept") or "Unassigned", now)
        yield e


@app.post("/ask")
def ask(body: Ask, user: dict = Depends(auth.current_user)):
    return rag.last(_answer_events(body, user))


@app.post("/ask/stream")
def ask_stream(body: Ask, user: dict = Depends(auth.current_user)):
    """The same answer as /ask, sent while it is made (server-sent events): progress, the text as the
    model writes it, then the finished answer."""
    def events():
        try:
            for e in _answer_events(body, user):
                yield f"data: {json.dumps(e, ensure_ascii=False)}\n\n"
        except Exception as e:  # noqa: BLE001 — the response has started, so the error goes in the stream
            yield f"data: {json.dumps({'error': 'The answer could not be completed. Please try again.'})}\n\n"
            raise e
    return StreamingResponse(events(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@app.post("/extract")
def extract_file(file: UploadFile, user: dict = Depends(auth.require_role(*policy.UPLOADERS))):
    """Plain `def`: FastAPI runs it on a worker thread, so a long OCR job doesn't hold up other people."""
    raw = file.file.read()
    try:
        res = extract.extract(file.filename, raw)
    except ValueError as e:
        raise HTTPException(415, str(e))
    res["file"] = extract.keep_original(file.filename, raw)  # people can open the real document later
    lists = _setting("lists")
    res["suggestion"] = extract.suggest(res["pages"], file.filename, lists)
    res["duplicate"] = _duplicate(user, extract.text_hash(res["pages"]), res["suggestion"].get("ref", ""))
    return res


@app.get("/documents/{doc_id}/file")
def document_file(doc_id: str, user: dict = Depends(auth.current_user)):
    """The original uploaded file, for people who may open the document."""
    f = _visible_doc(user, doc_id).get("file")
    stored = store.get_file(f["key"]) if f else None
    if not stored:
        raise HTTPException(404, "The original file isn't stored for this document.")
    name, mime, data = stored
    safe = re.sub(r"[^\w.\- ]", "_", name)
    return Response(data, media_type=mime, headers={"Content-Disposition": f'inline; filename="{safe}"'})


@app.get("/documents/{doc_id}/file/page/{n}")
def document_page_image(doc_id: str, n: int, user: dict = Depends(auth.current_user)):
    """One page of the original PDF as a picture, so every browser (phones included) shows it the same."""
    f = _visible_doc(user, doc_id).get("file")
    stored = store.get_file(f["key"]) if f else None
    if not stored or stored[1] != "application/pdf":
        raise HTTPException(404, "No original PDF for this document.")
    pdf = pymupdf.open(stream=stored[2], filetype="pdf")
    if not 1 <= n <= len(pdf):
        raise HTTPException(404, "No such page.")
    jpg = pdf[n - 1].get_pixmap(dpi=130).tobytes("jpeg", jpg_quality=80)  # light enough for phones
    return Response(jpg, media_type="image/jpeg", headers={"Cache-Control": "private, max-age=86400"})


@app.get("/documents/{doc_id}/file/page/{n}/highlight")
def document_page_highlight(doc_id: str, n: int, q: str = Query(max_length=4000), user: dict = Depends(auth.current_user)):
    """Where a cited passage sits on page n of the original, as boxes in fractions of the page, so the viewer
    can highlight it on the scan itself. Plain `def`: the first call for a scanned page runs OCR."""
    f = _visible_doc(user, doc_id).get("file")
    stored = store.get_file(f["key"]) if f else None
    if not stored:
        raise HTTPException(404, "The original file isn't stored for this document.")
    _, mime, data = stored
    pages = len(pymupdf.open(stream=data, filetype="pdf")) if mime == "application/pdf" else 1 if mime.startswith("image/") else 0
    if not 1 <= n <= pages:
        raise HTTPException(404, "No such page.")
    return {"rects": locate.locate(f["key"], mime, data, n, q)}


@app.post("/documents/{doc_id}/deadlines")
def find_deadlines(doc_id: str, user: dict = Depends(auth.require_role(*policy.UPLOADERS))):
    return extract.deadlines(_visible_doc(user, doc_id))


@app.get("/documents/{doc_id}/checks")
def review_checks(doc_id: str, user: dict = Approver):
    """Automatic checks shown to the reviewer: [[ok|warn, text], ...]."""
    d = _visible_doc(user, doc_id)
    others = [x for x in store.list_of("documents") if x["id"] != doc_id and x.get("status") == "Active"]
    missing = [k for k in ("title", "ref", "type", "authority", "dept", "date", "visibility", "audience", "tags") if not d.get(k)]
    same_ref = next((x for x in others if d.get("ref") and x.get("ref", "").strip().lower() == d["ref"].strip().lower()), None)
    close = sorted(rag.similar(doc_id, [x["id"] for x in others]).items(), key=lambda kv: -kv[1])
    near = next((x for x in others if close and x["id"] == close[0][0] and close[0][1] >= 0.9), None)
    pages = d.get("pages") or []
    empty = sum(1 for p in pages if not p)
    checks = [
        ["warn", "Missing: " + ", ".join(missing)] if missing else ["ok", "Required fields complete"],
        ["warn", f"Another active document has reference {d['ref']}: {same_ref['title']}"] if same_ref
        else ["ok", "Reference number is unique"] if d.get("ref") else ["warn", "No reference number"],
        ["warn", f"Closely matches active document {near['ref']} ({near['title']}). Check whether this revises it."]
        if near and not d.get("revisionOf") else ["ok", "No conflicting active document found"],
        ["warn", "Visibility is Management Only. Change to All Staff on approval if staff should see it."]
        if d.get("visibility") == "Management Only" else ["ok", "Visibility: " + d.get("visibility", "")],
        ["warn", f"No text on {empty} of {len(pages)} page(s)"] if empty or not pages
        else ["ok", f"Text extracted from all {len(pages)} page(s)"],
    ]
    if d.get("ocr") is not None and d["ocr"] < 70:
        checks.append(["warn", f"OCR confidence is {d['ocr']}%. Compare the text with the original before approving."])
    if d.get("expiry") and d.get("effective") and d["expiry"] < d["effective"]:
        checks.append(["warn", "Expiry date is before the effective date"])
    return checks


class DocRequest(BaseModel):
    q: str
    dept: str
    note: str = ""


@app.post("/unanswered/request")
def request_document(body: DocRequest, user: dict = Depends(auth.current_user)):
    """Anyone may ask for the document that would answer a question; approvers see it in Reports."""
    u = _log_unanswered(body.q, body.dept, datetime.now(), count=False)
    store.put("unanswered", u["id"], {**u, "status": "Requested", "dept": body.dept, "note": body.note,
                                      "requested_by": user.get("name", "")})
    _audit(user, "Requested document", f"{body.q} → {body.dept}")
    return {"ok": True}


class TagRename(BaseModel):
    old: str
    new: str


@app.post("/admin/tags/rename")
def rename_tag(body: TagRename, admin: dict = Admin):
    lists, new = _setting("lists"), body.new.strip()
    tags = lists.get("TAGS", [])
    if body.old not in tags or not new:
        raise HTTPException(400, "Choose a tag and a new name.")
    if new in tags:
        raise HTTPException(409, "That tag already exists.")
    store.put("settings", "lists", {**lists, "TAGS": [new if t == body.old else t for t in tags]})
    for d in store.list_of("documents"):
        if body.old in d.get("tags", []):
            full = store.get("documents", d["id"])
            store.put("documents", d["id"], {**full, "tags": [new if t == body.old else t for t in full["tags"]]})
    _audit(admin, "Renamed tag", f"{body.old} → {new}")
    return {"ok": True}


class ApiKey(BaseModel):
    key: str


def _key_status() -> dict:
    """What the Administration screen shows: never the key itself, only its last 4 characters."""
    key, source = llm.api_key()
    saved = store.get_secret(llm.KEY_NAME)
    return {"source": source, "last4": key[-4:] if key else "", **(saved[1] if saved else {})}


@app.get("/admin/openai-key")
def openai_key_status(admin: dict = Admin):
    return _key_status()


@app.put("/admin/openai-key")
def set_openai_key(body: ApiKey, admin: dict = Admin):
    key = body.key.strip()
    if not key.startswith("sk-") or len(key) < 20 or any(c.isspace() for c in key):
        raise HTTPException(400, "That doesn't look like an OpenAI API key (they start with sk-).")
    if err := llm.check_key(key):
        raise HTTPException(400, err)
    store.set_secret(llm.KEY_NAME, key, {"by": admin.get("name") or admin.get("login_id"), "at": store.stamp(datetime.now())})
    _audit(admin, "Changed OpenAI API key", f"key ending {key[-4:]}")
    return _key_status()


@app.delete("/admin/openai-key")
def remove_openai_key(admin: dict = Admin):
    """Go back to the key in the server's .env file."""
    store.delete_secret(llm.KEY_NAME)
    _audit(admin, "Removed OpenAI API key", "using the server's .env key")
    return _key_status()


# ---------- bulk import ----------

@app.post("/imports")
def import_file(file: UploadFile, batch: str = Form(...), visibility: str = Form(...), publish: bool = Form(False),
                dept: str = Form(""), user: dict = Depends(auth.require_role(*policy.UPLOADERS))):
    """Queue one file of a bulk import; the background worker reads, describes and indexes it."""
    if publish and user["role"] not in policy.APPROVERS:
        raise HTTPException(403, "Only approvers can publish without review.")
    if visibility not in _ctx().vis:
        raise HTTPException(400, "Choose who can see these documents.")
    if not re.fullmatch(r"[\w-]{4,64}", batch):
        raise HTTPException(400, "Bad batch id.")
    raw = file.file.read()
    try:
        extract.check_supported(file.filename)
    except ValueError as e:
        raise HTTPException(415, str(e))
    info = extract.keep_original(file.filename, raw)
    jobs.add("import", batch, {"key": info["key"], "name": file.filename, "visibility": visibility, "publish": publish,
                               "dept": dept, "by_login": user["login_id"], "by_name": user.get("name") or user["login_id"]})
    return {"ok": True}


@app.get("/imports")
def import_progress(user: dict = Depends(auth.require_role(*policy.UPLOADERS))):
    return jobs.batches(None if user["role"] == "Administrator" else user["login_id"])


@app.post("/imports/{batch}/retry")
def retry_import(batch: str, user: dict = Depends(auth.require_role(*policy.UPLOADERS))):
    return {"requeued": jobs.retry(batch, None if user["role"] == "Administrator" else user["login_id"])}


# ---------- answer quality ----------

@app.get("/reports/quality")
def quality_report(user: dict = Approver):
    running = [b for b in jobs.batches(None, "evaluate") if b["counts"].get("queued") or b["counts"].get("running")]
    return {"latest": evaluate.latest(), "running": bool(running)}


@app.post("/reports/quality/run")
def run_quality_test(new: bool = False, admin: dict = Admin):
    """Ask the automatic test questions again (new=true writes a fresh set first). Runs in the background."""
    jobs.add("evaluate", "eval-" + uuid.uuid4().hex[:8], {"n": 50, "new": new, "by_login": admin["login_id"]})
    return {"ok": True}


@app.get("/notifications")
def notifications(user: dict = Depends(auth.current_user)):
    return notices.for_user(user, _ctx())


@app.get("/reports/summary")
def report_summary(user: dict = Approver):
    """Usage figures from the question log: this month, and questions per week for 8 weeks."""
    qs, today = store.list_of("questions"), date.today()
    month = [q for q in qs if q["at"][:7] == today.isoformat()[:7]]
    monday = today - timedelta(days=today.weekday())
    weeks = [monday - timedelta(weeks=7 - i) for i in range(8)]
    per_week = [sum(1 for q in qs if w.isoformat() <= q["at"][:10] < (w + timedelta(days=7)).isoformat()) for w in weeks]
    return {
        "month": len(month), "cited": round(100 * sum(q["cited"] for q in month) / len(month)) if month else 0,
        "weeks": [{"label": f"{w.day} {w:%b}", "value": n} for w, n in zip(weeks, per_week)],
    }


class Export(BaseModel):
    title: str
    items: list[dict]  # [{q, answer}]


@app.post("/export/docx")
def export_docx(body: Export, user: dict = Depends(auth.current_user)):
    ctx = _ctx()
    docs = {d["id"]: d for d in store.list_of("documents") if policy.can_view(user, d, ctx)}
    return Response(export.answers_docx(body.title, body.items, docs),
                    media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    headers={"Content-Disposition": 'attachment; filename="svsu-cited-summary.docx"'})


# ---------- helpers ----------

def _ctx() -> policy.Ctx:
    return policy.Ctx.from_settings(store.list_of("settings"))


def _setting(id: str) -> dict:
    return store.get("settings", id) or {}


def _valid_pages(pages) -> bool:
    """Pages of blocks, each with a unique id and text (a string, or a list of cells for sheet rows)."""
    if not isinstance(pages, list) or not all(isinstance(p, list) for p in pages):
        return False
    blocks = [b for page in pages for b in page]
    if not all(isinstance(b, dict) and isinstance(b.get("id"), str) for b in blocks):
        return False
    text_ok = lambda t: isinstance(t, str) or (isinstance(t, list) and all(isinstance(c, str) for c in t))  # noqa: E731
    return all(text_ok(b.get("text")) for b in blocks) and len({b["id"] for b in blocks}) == len(blocks)


def _visible_doc(user: dict, doc_id: str) -> dict:
    doc = store.get("documents", doc_id)
    if not doc or not policy.can_view(user, doc, _ctx()):
        raise HTTPException(404, "Document not found")
    return doc


def _duplicate(user: dict, text_hash: str, ref: str) -> dict | None:
    """An existing document this upload repeats: same text, or the same reference number."""
    ctx, ref = _ctx(), ref.strip().lower()
    for d in store.list_of("documents"):
        if policy.can_view(user, d, ctx) and ((text_hash and d.get("text_hash") == text_hash)
                                              or (ref and d.get("ref", "").strip().lower() == ref)):
            return {k: d.get(k) for k in ("id", "title", "ref", "status")}
    return None


def _log_unanswered(q: str, dept: str, now: datetime, count: bool = True) -> dict:
    """Group repeats of the same question; returns the record."""
    q = q.strip()
    u = next((x for x in store.list_of("unanswered") if x.get("q", "").strip().lower() == q.lower()), None)
    u = u or {"id": uuid.uuid4().hex, "q": q, "count": 0, "dept": dept, "status": "Open"}
    u = {**u, "count": u["count"] + (1 if count else 0), "last": now.date().isoformat()}
    if u["status"] == "Resolved" and count:
        u["status"] = "Open"  # asked again after it was resolved
    store.put("unanswered", u["id"], u)
    return u


def _forget_deadline(deadline_id: str) -> None:
    """Remove everyone's reminders for a deleted deadline."""
    for r in store.list_of("reminders"):
        if r.get("deadline") == deadline_id:
            store.delete("reminders", r["id"])


def _forget_owner(login_id: str) -> None:
    """A deleted account's private records (chats, bookmarks, reminders, preferences) go with it."""
    for kind, items in store.records_of(*policy.OWNED).items():
        for x in items:
            if x.get("owner") == login_id:
                store.delete(kind, x["id"])


def _forget_document(doc_id: str) -> None:
    """Remove a deleted document's deadlines and bookmarks, and every reference to it."""
    r = store.records_of("deadlines", "bm_passages", "collections", "conflicts", "documents")
    for kind in ("deadlines", "bm_passages"):
        for x in r[kind]:
            if x.get("doc") == doc_id:
                store.delete(kind, x["id"])
                if kind == "deadlines":
                    _forget_deadline(x["id"])
    for c in r["collections"]:
        if doc_id in c.get("docs", []):
            store.put("collections", c["id"], {**c, "docs": [i for i in c["docs"] if i != doc_id]})
    for c in r["conflicts"]:
        if doc_id in c.get("docs", []):
            store.delete("conflicts", c["id"])
    for d in r["documents"]:
        if doc_id in d.get("related", []) or doc_id in (d.get("revisionOf"), d.get("supersededBy")):
            full = store.get("documents", d["id"])
            full["related"] = [i for i in full.get("related", []) if i != doc_id]
            for k in ("revisionOf", "supersededBy"):
                if full.get(k) == doc_id:
                    full[k] = None
            store.put("documents", d["id"], full)


def _check_user_change(user: dict, new: dict | None, old: dict | None) -> None:
    """Accounts are created through /accounts; nobody may lock themselves or everyone out."""
    if old is None:
        raise HTTPException(400, "Use Add user to create an account.")
    if new is not None:
        new["login_id"] = old.get("login_id")  # the sign-in name never changes
        if new.get("role") not in auth.ROLES:
            raise HTTPException(400, "Choose a valid role.")
    keeps_admin = new is not None and new.get("role") == "Administrator" and new.get("active") is not False
    if str(old.get("login_id")) == str(user.get("login_id")) and not keeps_admin and old.get("role") == "Administrator":
        raise HTTPException(400, "You can't remove your own administrator access or account.")
    if old.get("role") == "Administrator" and old.get("active") is not False and not keeps_admin:
        others = [u for u in store.list_of("users") if u["id"] != old["id"]
                  and u.get("role") == "Administrator" and u.get("active") is not False]
        if not others:
            raise HTTPException(400, "There must always be at least one active administrator.")


_STATUS_ACTION = {"Active": "Approved", "Rejected": "Rejected", "Changes requested": "Changes requested",
                  "Withdrawn": "Withdrawn", "Superseded": "Superseded", "Pending": "Submitted", "Draft": "Saved draft"}
_SETTING_NAMES = {"ai": "AI answer settings", "roles": "Access levels", "lists": "Tags and departments"}


def _audit_action(kind: str, new: dict, old: dict | None) -> tuple[str, str] | None:
    """What changed, worded for the audit log — decided by the server from the data, not by the browser."""
    if kind == "users":
        if old and new.get("active") != old.get("active"):
            return ("Reactivated user" if new.get("active") else "Deactivated user"), new.get("name", "")
        if old and new.get("role") != old.get("role"):
            return "Changed role", f"{new.get('name', '')} → {new.get('role')}"
        return "Updated user", new.get("name", new.get("id", ""))
    if kind == "settings":
        return "Edited", _SETTING_NAMES.get(new["id"], new["id"])
    if kind == "conflicts" and old is None:
        return "Reported conflict", new.get("topic", "")
    if kind != "documents":
        return None
    title = new.get("title", "")
    if old is None:
        return _STATUS_ACTION.get(new.get("status"), "Submitted"), title
    if new.get("status") != old.get("status"):
        restored = new.get("status") == "Active" and old.get("status") == "Withdrawn"
        return ("Restored" if restored else _STATUS_ACTION.get(new["status"], "Changed status")), title
    if new.get("visibility") != old.get("visibility"):
        return "Changed access", f"{title} → {new.get('visibility')}"
    return "Edited", title


def _audit(user: dict, act: str, what: str) -> None:
    store.audit(user.get("name") or user.get("login_id"), act, what)


def _check_kind(kind: str) -> None:
    if kind not in store.KINDS:
        raise HTTPException(404, f"Unknown record kind: {kind}")


def _seed() -> None:
    """First run only: the reference lists, AI settings and access matrix. The prototype's sample
    documents, people and activity are added only when DEMO_DATA is on (development)."""
    s = json.loads((Path(__file__).parent.parent / "seed.json").read_text(encoding="utf-8"))
    lists = {k: s[k] for k in ("TAGS", "AUDS", "DEPTS", "TYPES", "AUTHS", "INSTS", "VIS", "VIS_DESC")}
    kinds: dict[str, list] = {"settings": [{"id": "lists", **lists}, {"id": "ai", **s["aiSettings"]},
                                           {"id": "roles", "matrix": s["roleMatrix"]}]}
    if settings.demo_data:
        for d in s["docs"]:
            d["sample"] = True
            rag.index_document(d)
        kinds |= {
            "documents": s["docs"], "collections": s["collections"], "deadlines": s["deadlines"],
            "unanswered": s["unanswered"], "users": s["users"], "audit": s["audit"],
            "bm_passages": s["bmPassages"], "feedback": s["feedback"], "conflicts": s["conflicts"],
        }
    for kind, items in kinds.items():
        for i, item in reversed(list(enumerate(items))):  # oldest first, so lists read newest first
            item.setdefault("id", f"{kind}-{i + 1}")
            store.put(kind, item["id"], item)
