"""The app's data in PostgreSQL: JSON records grouped by kind, plus password hashes."""
from sqlalchemy import Column, Integer, String, Table, UniqueConstraint, case, cast, select, Text
from sqlalchemy.dialects.postgresql import JSONB, insert

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
meta.create_all(engine, tables=[records, credentials])


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
    q = select(_light).where(records.c.kind == "documents", cast(records.c.data, Text).ilike(like))
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
