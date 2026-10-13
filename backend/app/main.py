"""SVSU Knowledge Assistant API."""
import json
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import Body, Depends, FastAPI, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from . import auth, extract, rag, store


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
    scope_ids: list[str]       # documents the person chose to search
    permitted_ids: list[str]   # every document the person may see
    lang: str = "auto"         # auto | en | hi


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
    if not login_id or not body.password:
        raise HTTPException(400, "Login ID and password are required.")
    if store.get_credential(login_id) or any(str(u.get("login_id", "")) == login_id for u in store.all_records()["users"]):
        raise HTTPException(409, "An account with that Login ID already exists.")
    role = body.role if body.role in auth.ROLES else "Viewer"
    store.put("users", "us-" + login_id, {
        "id": "us-" + login_id, "login_id": login_id, "name": body.name, "email": body.email,
        "dept": body.dept, "role": role, "active": True, "last": "Never",
    })
    store.set_credential(login_id, auth.hash_password(body.password))
    return {"ok": True}


@app.put("/accounts/{login_id}/password")
def reset_password(login_id: str, body: PasswordReset, admin: dict = Depends(auth.require_role("Administrator"))):
    if not body.password:
        raise HTTPException(400, "Password is required.")
    store.set_credential(login_id, auth.hash_password(body.password))
    return {"ok": True}


@app.get("/records")
def get_records(user: dict = Depends(auth.current_user)):
    return store.all_records()


@app.put("/records/{kind}/{id}")
def put_record(kind: str, id: str, data: dict = Body(...),
               user: dict = Depends(auth.require_role("Administrator", "Approver", "Uploader"))):
    _check_kind(kind)
    if kind == "documents":
        old = store.get(kind, id)
        if old is None or old.get("pages") != data.get("pages"):
            rag.index_document(data)  # index first: a failure saves nothing
    store.put(kind, id, data)
    return {"ok": True}


@app.delete("/records/{kind}/{id}")
def delete_record(kind: str, id: str,
                  user: dict = Depends(auth.require_role("Administrator", "Approver", "Uploader"))):
    _check_kind(kind)
    if kind == "users":
        rec = store.get(kind, id)
        if rec and rec.get("login_id"):
            store.delete_credential(str(rec["login_id"]))
    store.delete(kind, id)
    if kind == "documents":
        rag.remove_document(id)
    return {"ok": True}


@app.post("/ask")
def ask(body: Ask, user: dict = Depends(auth.current_user)):
    docs = {d["id"]: d for d in store.all_records()["documents"]}
    return rag.answer(body.question, body.scope_ids, body.permitted_ids, docs, body.lang)


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
def find_deadlines(doc_id: str, user: dict = Depends(auth.current_user)):
    doc = store.get("documents", doc_id)
    if not doc:
        raise HTTPException(404, "Document not found")
    return extract.deadlines(doc)


def _check_kind(kind: str) -> None:
    if kind not in store.KINDS:
        raise HTTPException(404, f"Unknown record kind: {kind}")


def _seed() -> None:
    """First run only: load the prototype's sample data so every screen has content."""
    s = json.loads((Path(__file__).parent.parent / "seed.json").read_text(encoding="utf-8"))
    for d in s["docs"]:
        d["sample"] = True
        rag.index_document(d)
    lists = {k: s[k] for k in ("TAGS", "AUDS", "DEPTS", "TYPES", "AUTHS", "INSTS", "VIS", "VIS_DESC")}
    kinds = {
        "documents": s["docs"], "collections": s["collections"], "deadlines": s["deadlines"],
        "unanswered": s["unanswered"], "users": s["users"], "audit": s["audit"],
        "bm_passages": s["bmPassages"],
        "feedback": s["feedback"], "conflicts": s["conflicts"],
        "settings": [{"id": "lists", **lists}, {"id": "ai", **s["aiSettings"]},
                     {"id": "roles", "matrix": s["roleMatrix"]}],
    }
    for kind, items in kinds.items():
        for i, item in reversed(list(enumerate(items))):  # oldest first, so lists read newest first
            item.setdefault("id", f"{kind}-{i + 1}")
            store.put(kind, item["id"], item)
