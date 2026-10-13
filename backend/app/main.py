"""SVSU Knowledge Assistant API."""
import json
import uuid
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from fastapi import Body, Depends, FastAPI, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from . import auth, extract, policy, rag, store
from .config import settings


@asynccontextmanager
async def lifespan(_: FastAPI):
    if store.is_empty():
        _seed()
    yield


app = FastAPI(title="SVSU Knowledge Assistant", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


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


@app.post("/login")
def login(body: Login):
    user = auth.verify(body.login_id, body.password)
    if not user:
        raise HTTPException(401, "Wrong Login ID or password.")
    user["role"] = auth.app_role(user["login_id"])
    return {"token": auth.make_token(user, user["role"]), "user": user}


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
def create_account(body: Account, admin: dict = Depends(auth.require_role("Administrator"))):
    login_id = body.login_id.strip()
    if not login_id:
        raise HTTPException(400, "Login ID is required.")
    if err := auth.password_problem(body.password):
        raise HTTPException(400, err)
    if store.get_credential(login_id) or any(str(u.get("login_id", "")) == login_id for u in store.all_records()["users"]):
        raise HTTPException(409, "An account with that Login ID already exists.")
    role = body.role if body.role in auth.ROLES else "Viewer"
    store.put("users", "us-" + login_id, {
        "id": "us-" + login_id, "login_id": login_id, "name": body.name, "email": body.email,
        "dept": body.dept, "role": role, "active": True, "last": "Never",
    })
    store.set_credential(login_id, auth.hash_password(body.password))
    _audit(admin, "Added user", f"{body.name} ({login_id}) as {role}")
    return {"ok": True}


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


@app.put("/accounts/{login_id}/password")
def reset_password(login_id: str, body: PasswordReset, admin: dict = Depends(auth.require_role("Administrator"))):
    if err := auth.password_problem(body.password):
        raise HTTPException(400, err)
    store.set_credential(login_id, auth.hash_password(body.password))
    _audit(admin, "Reset password", login_id)
    return {"ok": True}


@app.get("/records")
def get_records(user: dict = Depends(auth.current_user)):
    return policy.visible_records(user, store.all_records())


@app.put("/records/{kind}/{id}")
def put_record(kind: str, id: str, data: dict = Body(...), user: dict = Depends(auth.current_user)):
    _check_kind(kind)
    old = store.get(kind, id)
    if err := policy.write_error(user, kind, data, old, _ctx()):
        raise HTTPException(403, err)
    if kind in policy.OWNED or kind == "collections":  # the server, not the browser, records the owner
        data["owner"] = (old or {}).get("owner") or user["login_id"]
    if kind == "documents":
        if old is None:
            data["uploader_id"] = user["login_id"]
        else:
            data["uploader_id"] = old.get("uploader_id")
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
    if kind == "users" and old.get("login_id"):
        store.delete_credential(str(old["login_id"]))
        _audit(user, "Deleted user", f"{old.get('name', '')} ({old['login_id']})")
    store.delete(kind, id)
    if kind == "documents":
        rag.remove_document(id)
        _audit(user, "Deleted", old.get("title", id))
    return {"ok": True}


@app.post("/ask")
def ask(body: Ask, user: dict = Depends(auth.current_user)):
    ctx = _ctx()
    docs = {d["id"]: d for d in store.all_records()["documents"] if policy.can_answer(user, d, ctx)}
    scope = [i for i in body.scope_ids if i in docs]  # never more than this person may see
    return rag.answer(body.question, scope, list(docs), docs, body.lang, body.history)


@app.post("/extract")
async def extract_file(file: UploadFile,
                       user: dict = Depends(auth.require_role("Administrator", "Approver", "Uploader"))):
    try:
        res = extract.extract(file.filename, await file.read())
    except ValueError as e:
        raise HTTPException(415, str(e))
    res["suggestion"] = extract.suggest(res["pages"], file.filename, store.get("settings", "lists") or {})
    return res


@app.post("/documents/{doc_id}/deadlines")
def find_deadlines(doc_id: str, user: dict = Depends(auth.require_role(*policy.UPLOADERS))):
    doc = store.get("documents", doc_id)
    if not doc or not policy.can_view(user, doc, _ctx()):
        raise HTTPException(404, "Document not found")
    return extract.deadlines(doc)


def _ctx() -> policy.Ctx:
    return policy.Ctx.from_settings(store.all_records()["settings"])


_STATUS_ACTION = {"Active": "Approved", "Rejected": "Rejected", "Changes requested": "Changes requested",
                  "Withdrawn": "Withdrawn", "Superseded": "Superseded", "Pending": "Submitted"}


def _audit_action(kind: str, new: dict, old: dict | None) -> tuple[str, str] | None:
    """What changed, worded for the audit log — decided by the server from the data, not by the browser."""
    if kind == "users":
        return ("Added user" if old is None else "Updated user", new.get("name", new.get("id", "")))
    if kind != "documents":
        return None
    title = new.get("title", "")
    if old is None:
        return "Submitted", title
    if new.get("status") != old.get("status"):
        restored = new.get("status") == "Active" and old.get("status") == "Withdrawn"
        return ("Restored" if restored else _STATUS_ACTION.get(new["status"], "Changed status")), title
    if new.get("visibility") != old.get("visibility"):
        return "Changed access", f"{title} → {new.get('visibility')}"
    return "Edited", title


def _audit(user: dict, act: str, what: str) -> None:
    now, entry_id = datetime.now(), uuid.uuid4().hex
    store.put("audit", entry_id, {
        "id": entry_id, "t": now.strftime("%d %b %Y, %I:%M %p").lstrip("0"),
        "at": now.isoformat(timespec="seconds"), "who": user.get("name") or user.get("login_id"),
        "act": act, "what": what,
    })


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
