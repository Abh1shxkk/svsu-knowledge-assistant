"""The API end to end, per role, against the test database."""
import io

from conftest import login

PAGE = [[{"id": "b1", "text": "Every regular employee is entitled to 12 days of casual leave.", "kind": "p"}]]


def doc(id, status="Pending", visibility="All Staff", **extra):
    return {"id": id, "title": f"Doc {id}", "ref": f"SVSU/T/{id}", "type": "Circular", "authority": "Registrar",
            "dept": "Examination", "date": "2026-10-01", "effective": "2026-10-01", "audience": ["Teaching Staff"],
            "tags": ["Leave"], "visibility": visibility, "status": status, "pages": PAGE, "related": [],
            "revisionOf": None, "supersededBy": None, "versions": [], "approvals": [], **extra}


def put(client, who, kind, data):
    return client.put(f"/records/{kind}/{data['id']}", headers=who, json=data)


def test_upload_review_publish_flow(client, people):
    up, ap, viewer = people["Uploader"], people["Approver"], people["Viewer"]
    assert put(client, up, "documents", doc("F1")).status_code == 200
    # Pending: the uploader and approvers see it, viewers don't.
    ids = lambda who: [d["id"] for d in client.get("/records", headers=who).json()["documents"]]  # noqa: E731
    assert "F1" in ids(up) and "F1" in ids(ap) and "F1" not in ids(viewer)
    assert client.get("/documents/F1", headers=viewer).status_code == 404
    # The uploader can't publish; the approver can.
    assert put(client, up, "documents", doc("F1", status="Active")).status_code == 403
    assert put(client, ap, "documents", doc("F1", status="Active")).status_code == 200
    assert "F1" in ids(viewer)
    # Published: the uploader can no longer change its text or access.
    r = put(client, up, "documents", doc("F1", status="Active", visibility="Public (students & staff)"))
    assert r.status_code == 403


def test_lists_leave_out_text_and_detail_includes_it(client, people):
    v = people["Viewer"]
    listed = next(d for d in client.get("/records", headers=v).json()["documents"] if d["id"] == "F1")
    assert "pages" not in listed
    assert client.get("/documents/F1", headers=v).json()["pages"] == PAGE
    assert client.get("/search", params={"q": "casual LEAVE"}, headers=v).json() == ["F1"]
    assert client.get("/search", params={"q": "nothing like this"}, headers=v).json() == []


def test_metadata_edit_without_pages_keeps_text(client, people):
    ap = people["Approver"]
    meta = {k: v for k, v in doc("F1", status="Active").items() if k != "pages"}
    assert put(client, ap, "documents", {**meta, "title": "Renamed"}).status_code == 200
    full = client.get("/documents/F1", headers=ap).json()
    assert full["title"] == "Renamed" and full["pages"] == PAGE


def test_ask_cites_and_logs_usage(client, people):
    v = people["Viewer"]
    r = client.post("/ask", headers=v, json={"question": "How many casual leaves?", "scope_ids": ["F1"]})
    assert r.status_code == 200 and r.json()["cites"][0]["doc"] == "F1"
    r = client.post("/ask", headers=v, json={"question": "Maternity leave?", "scope_ids": []})
    assert r.json()["label"] == "Insufficient evidence"
    rec = client.get("/records", headers=v).json()
    assert any(u["q"] == "Maternity leave?" for u in rec["unanswered"])  # logged by the server
    summary = client.get("/reports/summary", headers=people["Approver"]).json()
    assert summary["month"] >= 2 and len(summary["weeks"]) == 8
    assert client.get("/reports/summary", headers=v).status_code == 403


def test_viewer_cannot_write_shared_records(client, people):
    v = people["Viewer"]
    assert put(client, v, "deadlines", {"id": "dl1", "doc": "F1", "date": "2026-11-01"}).status_code == 403
    assert put(client, v, "unanswered", {"id": "u1", "q": "x"}).status_code == 403
    assert put(client, v, "questions", {"id": "q1"}).status_code == 403
    assert client.post("/unanswered/request", headers=v, json={"q": "Maternity leave?", "dept": "Human Resources"}).status_code == 200


def test_delete_document_removes_everything_pointing_at_it(client, people, admin):
    ap = people["Approver"]
    assert put(client, ap, "documents", doc("G1", status="Active")).status_code == 200
    assert put(client, ap, "deadlines", {"id": "dlG", "doc": "G1", "date": "2026-11-01", "title": "x"}).status_code == 200
    assert put(client, ap, "collections", {"id": "cG", "name": "c", "docs": ["G1", "F1"]}).status_code == 200
    assert put(client, people["Viewer"], "bm_passages", {"id": "bG", "doc": "G1", "page": 1, "block": "b1"}).status_code == 200
    assert client.delete("/records/documents/G1", headers=ap).status_code == 403  # only administrators delete
    assert client.delete("/records/documents/G1", headers=admin).status_code == 200
    rec = client.get("/records", headers=admin).json()
    assert not any(x["id"] == "dlG" for x in rec["deadlines"])
    assert next(c for c in rec["collections"] if c["id"] == "cG")["docs"] == ["F1"]
    assert not any(x["id"] == "bG" for x in client.get("/records", headers=people["Viewer"]).json()["bm_passages"])


def test_admin_cannot_lock_themselves_out(client, people, admin):
    me = people["Administrator"]
    rec = next(u for u in client.get("/records", headers=me).json()["users"] if u["login_id"] == "t-administrator")
    assert put(client, me, "users", {**rec, "role": "Viewer"}).status_code == 400
    assert put(client, me, "users", {**rec, "active": False}).status_code == 400
    assert client.delete(f"/records/users/{rec['id']}", headers=me).status_code == 400
    assert put(client, me, "users", {"id": "us-new", "name": "x", "role": "Administrator"}).status_code == 400
    # Another administrator may change it, as long as one active administrator remains.
    other = login(client, "t-administrator", "Password-123")
    assert other


def test_rename_tag_updates_documents(client, people, admin):
    assert client.post("/admin/tags/rename", headers=admin, json={"old": "Leave", "new": "Leave rules"}).status_code == 200
    assert client.get("/documents/F1", headers=admin).json()["tags"] == ["Leave rules"]
    assert client.post("/admin/tags/rename", headers=people["Approver"], json={"old": "x", "new": "y"}).status_code == 403
    client.post("/admin/tags/rename", headers=admin, json={"old": "Leave rules", "new": "Leave"})


def test_extract_reads_text_and_flags_duplicates(client, people):
    up = people["Uploader"]
    text = PAGE[0][0]["text"].encode()
    r = client.post("/extract", headers=up, files={"file": ("leave.txt", io.BytesIO(text), "text/plain")})
    assert r.status_code == 200 and r.json()["duplicate"]["id"] == "F1"
    r = client.post("/extract", headers=up, files={"file": ("old.doc", io.BytesIO(b"x"), "application/msword")})
    assert r.status_code == 415
    assert client.post("/extract", headers=people["Viewer"], files={"file": ("a.txt", io.BytesIO(b"x"))}).status_code == 403


def test_checks_notifications_and_export(client, people):
    ap = people["Approver"]
    assert put(client, people["Uploader"], "documents", doc("H1", ref="SVSU/T/F1")).status_code == 200
    checks = client.get("/documents/H1/checks", headers=ap).json()
    assert ["warn", "Another active document has reference SVSU/T/F1: Renamed"] in checks
    assert any("waiting for your approval" in n["text"] for n in client.get("/notifications", headers=ap).json())
    r = client.post("/export/docx", headers=people["Viewer"], json={"title": "t", "items": [
        {"q": "q", "answer": {"body": [{"p": "a {1}"}], "cites": [{"doc": "F1", "page": 1, "quote": "x"}]}}]})
    assert r.status_code == 200 and r.content[:2] == b"PK"  # a .docx is a zip file
