"""The project's own PostgreSQL database: documents, users, chats, deadlines — and the embeddings,
stored with pgvector. One database for everything."""
from sqlalchemy import MetaData, create_engine, make_url, text

from .config import settings


def _url() -> str:
    if settings.database_url:
        return settings.database_url
    # Local: start (or reuse) a PostgreSQL server whose data lives in pg_data_dir.
    import pgserver
    server_uri = pgserver.get_server(settings.pg_data_dir, cleanup_mode=None).get_uri()
    admin = create_engine(_driver(server_uri), isolation_level="AUTOCOMMIT")
    with admin.connect() as c:
        if not c.scalar(text("SELECT 1 FROM pg_database WHERE datname = :n"), {"n": settings.db_name}):
            c.execute(text(f'CREATE DATABASE "{settings.db_name}"'))
    admin.dispose()
    # Swap in our database name; the URI may carry a socket path as a query (?host=/path) on Linux.
    return make_url(server_uri).set(database=settings.db_name).render_as_string(hide_password=False)


def _driver(url: str) -> str:
    return url.replace("postgresql://", "postgresql+psycopg://", 1)


engine = create_engine(_driver(_url()), pool_pre_ping=True)
meta = MetaData()

with engine.begin() as _c:
    _c.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
