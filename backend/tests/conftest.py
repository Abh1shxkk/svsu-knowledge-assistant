"""API tests run against their own database (svsu_test), never the real one. OpenAI is replaced with
deterministic stand-ins, so tests are free, offline and repeatable."""
import hashlib
import os

os.environ.update({
    "DB_NAME": "svsu_test", "DATABASE_URL": "", "DEMO_DATA": "false", "SMTP_HOST": "", "RUN_WORKER": "false",
    "DEV_ADMIN_USER": "testadmin", "DEV_ADMIN_PASS": "test-admin-pass-1",
    "JWT_SECRET": "test-secret-not-used-anywhere-else-0123456789",
})

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app import evaluate, extract, main, rag  # noqa: E402
from app.config import settings  # noqa: E402
from app.database import engine  # noqa: E402

assert engine.url.database == "svsu_test", "tests must never touch the real database"


def fake_embed(texts, batch=256):
    out = []
    for t in texts:
        h = hashlib.sha256(t.encode()).digest()
        out.append([(h[i % 32] - 128) / 128 for i in range(settings.embed_dim)])
    return out


def fake_chat(system, user, as_json=False, model=None, temperature=None):
    if "write test questions" in system:
        return {"question": "How many casual leaves can staff take?", "answer": "12 days"}
    if "You check a search assistant" in system:
        return {"correct": "Twelve days" in user}
    if "search queries" in system:
        return {"queries": []}
    if "deadline" in system:
        return {"deadlines": []}
    return {}  # suggested details (and no re-ranking or fact-check findings)


ANSWER = 'Twelve days [1].\n---META---\n{"label": "One source", "banner": null, "cites": [{"excerpt": 1, "quote": ""}], "follow": []}'


def fake_stream(system, user, model=None, temperature=None):
    for i in range(0, len(ANSWER), 7):  # in small pieces, as the real model streams
        yield ANSWER[i:i + 7]


@pytest.fixture(scope="session")
def client():
    rag.embed = fake_embed
    rag.chat = extract.chat = evaluate.chat = fake_chat
    rag.chat_stream = fake_stream
    with engine.begin() as c:
        c.execute(text("TRUNCATE records, credentials, blocks, secrets, files, jobs"))
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
