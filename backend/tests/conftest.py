"""API tests run against their own database (svsu_test), never the real one. OpenAI is replaced with
deterministic stand-ins, so tests are free, offline and repeatable."""
import hashlib
import os

os.environ.update({
    "DB_NAME": "svsu_test", "DATABASE_URL": "", "DEMO_DATA": "false", "SMTP_HOST": "",
    "DEV_ADMIN_USER": "testadmin", "DEV_ADMIN_PASS": "test-admin-pass-1",
    "JWT_SECRET": "test-secret-not-used-anywhere-else-0123456789",
})

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app import extract, main, rag  # noqa: E402
from app.config import settings  # noqa: E402
from app.database import engine  # noqa: E402

assert engine.url.database == "svsu_test", "tests must never touch the real database"


def fake_embed(texts, batch=256):
    out = []
    for t in texts:
        h = hashlib.sha256(t.encode()).digest()
        out.append([(h[i % 32] - 128) / 128 for i in range(settings.embed_dim)])
    return out


def fake_chat(system, user, as_json=False, model=None):
    if "search queries" in system:
        return {"queries": []}
    if "Excerpts:" in user:
        return {"label": "One source", "banner": None, "body": [{"p": "Twelve days {1}."}],
                "cites": [{"excerpt": 1, "quote": ""}], "follow": []}
    if "deadline" in system:
        return {"deadlines": []}
    return {}  # suggested details


@pytest.fixture(scope="session")
def client():
    rag.embed = fake_embed
    rag.chat = extract.chat = fake_chat
    with engine.begin() as c:
        c.execute(text("TRUNCATE records, credentials, blocks"))
    with TestClient(main.app) as c:
        yield c


def login(client, login_id, password):
    r = client.post("/login", json={"login_id": login_id, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": "Bearer " + r.json()["token"]}


@pytest.fixture(scope="session")
def admin(client):
    return login(client, "testadmin", "test-admin-pass-1")


@pytest.fixture(scope="session")
def people(client, admin):
    """One account per role, all in the Examination department."""
    heads = {}
    for role in ("Administrator", "Approver", "Uploader", "Viewer"):
        lid = "t-" + role.lower()
        r = client.post("/accounts", headers=admin, json={
            "login_id": lid, "name": f"Test {role}", "dept": "Examination", "role": role, "password": "Password-123"})
        assert r.status_code == 200, r.text
        heads[role] = login(client, lid, "Password-123")
    return heads
