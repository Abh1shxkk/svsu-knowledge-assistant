"""The app's data in PostgreSQL: JSON records grouped by kind, plus password hashes."""
from sqlalchemy import Column, Integer, LargeBinary, String, Table, UniqueConstraint, case, cast, func, literal_column, select, Text
from sqlalchemy.dialects.postgresql import JSONB, insert
import uuid
from datetime import datetime

from .database import engine, meta

KINDS = {"documents", "collections", "deadlines", "chats", "bm_answers", "bm_passages", "feedback",
         "unanswered", "conflicts", "users", "audit", "settings", "reminders", "prefs", "questions"}

records = Table(
    "records", meta,
    Column("seq", Integer, primary_key=True, autoincrement=True),  # insertion order; lists read newest first
    Column("kind", String(30), nullable=False),
    Column("id", String(64), nullable=False),
    Column("data", JSONB, nullable=False),
    UniqueConstraint("kind", "id"),
)
# Password hashes live in their own table and are NEVER returned by records_of().
credentials = Table(
    "credentials", meta,
    Column("login_id", String(64), primary_key=True),
    Column("hash", String(200), nullable=False),
)
# Service keys set in Administration (e.g. the OpenAI key). Like credentials: never in records_of().
secrets = Table(
    "secrets", meta,
    Column("name", String(64), primary_key=True),
    Column("value", Text, nullable=False),
    Column("meta", JSONB, nullable=False),  # who set it and when, shown without the value
)
# Original uploaded files, keyed by a hash of their content (the same file is stored once).
files = Table(
    "files", meta,
    Column("key", String(64), primary_key=True),
    Column("name", String(255), nullable=False),
    Column("mime", String(100), nullable=False),
    Column("data", LargeBinary, nullable=False),
)
meta.create_all(engine, tables=[records, credentials, secrets, files])


# Lists leave out each document's full text ("pages"); get() returns it, one document at a time.
_light = case((records.c.kind == "documents", records.c.data.op("-", return_type=JSONB)("pages")), else_=records.c.data)


def records_of(*kinds: str) -> dict[str, list[dict]]:
    """The given kinds (all of them if none are named), newest first, documents without their text."""
    kinds = kinds or tuple(KINDS)
    out: dict[str, list[dict]] = {k: [] for k in kinds}
    q = select(records.c.kind, _light).where(records.c.kind.in_(kinds)).order_by(records.c.seq.desc())
    with engine.connect() as c:
        for kind, data in c.execute(q):
            out[kind].append(data)
    return out


def list_of(kind: str) -> list[dict]:
    return records_of(kind)[kind]


def search_documents(text: str) -> list[dict]:
    """Documents whose details or text contain `text` (any case), without their text."""
    like = "%" + text.replace("\\", "\\\\").replace("%", r"\%").replace("_", r"\_") + "%"
    d = records.c.data  # the details people see and the paragraph text, not field names or workflow notes
    words = func.concat_ws(" ", *(d[k].astext for k in ("title", "ref", "description", "dept", "type", "authority")),
                           cast(d["tags"], Text),
                           cast(func.jsonb_path_query_array(d["pages"], literal_column("'$[*][*].text'::jsonpath")), Text))
    q = select(_light).where(records.c.kind == "documents", words.ilike(like))
    with engine.connect() as c:
        return list(c.scalars(q))


def get(kind: str, id: str) -> dict | None:
    with engine.connect() as c:
        return c.scalar(select(records.c.data).where(records.c.kind == kind, records.c.id == id))


def put(kind: str, id: str, data: dict) -> None:
    stmt = insert(records).values(kind=kind, id=id, data=data)
    with engine.begin() as c:
        c.execute(stmt.on_conflict_do_update(index_elements=["kind", "id"], set_={"data": stmt.excluded.data}))


def delete(kind: str, id: str) -> None:
    with engine.begin() as c:
        c.execute(records.delete().where(records.c.kind == kind, records.c.id == id))


def is_empty() -> bool:
    with engine.connect() as c:
        return c.scalar(select(records.c.seq).limit(1)) is None


def get_credential(login_id: str) -> str | None:
    with engine.connect() as c:
        return c.scalar(select(credentials.c.hash).where(credentials.c.login_id == str(login_id)))


def set_credential(login_id: str, hash: str) -> None:
    stmt = insert(credentials).values(login_id=str(login_id), hash=hash)
    with engine.begin() as c:
        c.execute(stmt.on_conflict_do_update(index_elements=["login_id"], set_={"hash": hash}))


def delete_credential(login_id: str) -> None:
    with engine.begin() as c:
        c.execute(credentials.delete().where(credentials.c.login_id == str(login_id)))


def get_secret(name: str) -> tuple[str, dict] | None:
    with engine.connect() as c:
        row = c.execute(select(secrets.c.value, secrets.c.meta).where(secrets.c.name == name)).first()
    return (row.value, row.meta) if row else None


def set_secret(name: str, value: str, meta: dict) -> None:
    stmt = insert(secrets).values(name=name, value=value, meta=meta)
    with engine.begin() as c:
        c.execute(stmt.on_conflict_do_update(index_elements=["name"], set_={"value": value, "meta": meta}))


def delete_secret(name: str) -> None:
    with engine.begin() as c:
        c.execute(secrets.delete().where(secrets.c.name == name))


def put_file(key: str, name: str, mime: str, data: bytes) -> None:
    stmt = insert(files).values(key=key, name=name, mime=mime, data=data)
    with engine.begin() as c:
        c.execute(stmt.on_conflict_do_nothing(index_elements=["key"]))


def get_file(key: str) -> tuple[str, str, bytes] | None:
    """(name, mime, data)"""
    with engine.connect() as c:
        row = c.execute(select(files.c.name, files.c.mime, files.c.data).where(files.c.key == key)).first()
    return tuple(row) if row else None


def has_file(key: str) -> bool:
    with engine.connect() as c:
        return c.scalar(select(files.c.key).where(files.c.key == key)) is not None


def delete_file(key: str) -> None:
    """The file and anything kept alongside it (word positions, stored as "<start of key>.w<page>")."""
    with engine.begin() as c:
        c.execute(files.delete().where((files.c.key == key) | files.c.key.like(key[:56] + ".%")))


def stamp(t: datetime) -> str:
    """"14 Oct 2026, 3:05 PM" — how times are shown in the audit log and user lists."""
    return t.strftime("%d %b %Y, %I:%M %p").lstrip("0")


def audit(who: str, act: str, what: str) -> None:
    now, entry_id = datetime.now(), uuid.uuid4().hex
    put("audit", entry_id, {"id": entry_id, "t": stamp(now), "at": now.isoformat(timespec="seconds"),
                            "who": who, "act": act, "what": what})
