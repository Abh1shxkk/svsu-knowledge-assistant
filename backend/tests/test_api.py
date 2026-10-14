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


def test_deleting_deadline_or_user_removes_their_private_records(client, people, admin):
    ap, v = people["Approver"], people["Viewer"]
    assert put(client, ap, "deadlines", {"id": "dlR", "doc": "F1", "date": "2099-01-01", "title": "x"}).status_code == 200
    assert put(client, v, "reminders", {"id": "rmR", "deadline": "dlR", "days": 3, "via": []}).status_code == 200
    assert client.delete("/records/deadlines/dlR", headers=ap).status_code == 200
    assert client.get("/records", headers=v).json()["reminders"] == []
    r = client.post("/accounts", headers=admin, json={"login_id": "t-gone", "name": "Gone", "role": "Viewer", "password": "Password-123"})
    assert r.status_code == 200
    gone = login(client, "t-gone", "Password-123")
    assert put(client, gone, "chats", {"id": "chGone", "title": "x", "msgs": []}).status_code == 200
    assert client.delete("/records/users/us-t-gone", headers=admin).status_code == 200
    assert not any(c["id"] == "chGone" for c in client.get("/records", headers=admin).json()["chats"])


def test_openai_key_is_admin_only_and_never_returned(client, people, admin, monkeypatch):
    from app import llm
    monkeypatch.setattr(llm, "check_key", lambda k: None if k.endswith("good") else "OpenAI rejected this key.")
    key = "sk-test-" + "x" * 30 + "good"
    for who in ("Approver", "Uploader", "Viewer"):
        assert client.get("/admin/openai-key", headers=people[who]).status_code == 403
        assert client.put("/admin/openai-key", headers=people[who], json={"key": key}).status_code == 403
    assert client.put("/admin/openai-key", headers=admin, json={"key": "not-a-key"}).status_code == 400
    assert client.put("/admin/openai-key", headers=admin, json={"key": "sk-" + "y" * 30 + "bad"}).status_code == 400
    r = client.put("/admin/openai-key", headers=admin, json={"key": key})
    assert r.status_code == 200 and r.json()["source"] == "admin" and r.json()["last4"] == "good"
    assert llm.api_key() == (key, "admin")  # used for answers from now on
    leaked = client.get("/records", headers=admin).text + client.get("/admin/openai-key", headers=admin).text
    assert key not in leaked
    assert client.delete("/admin/openai-key", headers=admin).json()["source"] != "admin"


def test_uploader_can_edit_after_changes_requested(client, people):
    up, ap = people["Uploader"], people["Approver"]
    assert put(client, up, "documents", doc("CR1")).status_code == 200
    assert put(client, ap, "documents", doc("CR1", status="Changes requested")).status_code == 200
    # Editing keeps the status; access can change too; then they resubmit.
    assert put(client, up, "documents", doc("CR1", status="Changes requested", title="Fixed")).status_code == 200
    assert put(client, up, "documents", doc("CR1", status="Changes requested", visibility="Public (students & staff)")).status_code == 200
    assert put(client, up, "documents", doc("CR1", status="Pending")).status_code == 200
    assert put(client, up, "documents", doc("CR1", status="Active")).status_code == 403


def test_collection_keeps_documents_its_editor_cannot_see(client, people, admin):
    v, ap = people["Viewer"], people["Approver"]
    for i in ("K1", "K2"):
        assert put(client, ap, "documents", doc(i, status="Active")).status_code == 200
    assert put(client, v, "collections", {"id": "coK", "name": "c", "docs": ["K1", "K2"]}).status_code == 200
    assert put(client, ap, "documents", doc("K2", status="Active", visibility="Management Only")).status_code == 200
    mine = next(c for c in client.get("/records", headers=v).json()["collections"] if c["id"] == "coK")
    assert mine["docs"] == ["K1"]
    assert put(client, v, "collections", {**mine, "name": "renamed"}).status_code == 200
    full = next(c for c in client.get("/records", headers=admin).json()["collections"] if c["id"] == "coK")
    assert full["docs"] == ["K1", "K2"]


def test_export_handles_number_cells(client, people):
    answer = {"body": [{"table": {"head": ["Leave", 1], "rows": [["CL", 12]]}}], "cites": []}
    r = client.post("/export/docx", headers=people["Viewer"], json={"title": "t", "items": [{"q": "q", "answer": answer}]})
    assert r.status_code == 200


def test_search_matches_content_not_field_names(client, people):
    v = people["Viewer"]
    for word in ("status", "uploader_id", "Original upload", "kind"):
        assert client.get("/search", params={"q": word}, headers=v).json() == [], word
    assert "F1" in client.get("/search", params={"q": "casual leave"}, headers=v).json()


def test_deadlines_and_reminders_need_access_to_the_document(client, people):
    ap, up, v = people["Approver"], people["Uploader"], people["Viewer"]
    assert put(client, ap, "documents", doc("MO1", status="Active", visibility="Management Only")).status_code == 200
    assert put(client, ap, "deadlines", {"id": "dlMO", "doc": "MO1", "date": "2099-01-01", "title": "secret"}).status_code == 200
    assert put(client, up, "deadlines", {"id": "dlMO", "doc": "MO1", "date": "2099-01-01", "title": "tampered"}).status_code == 404
    assert client.delete("/records/deadlines/dlMO", headers=up).status_code == 404
    assert put(client, v, "reminders", {"id": "rmMO", "deadline": "dlMO", "days": 1, "via": ["Email"]}).status_code == 404


def test_answer_keeps_citations_when_the_model_forgets_the_markers(monkeypatch):
    from app import rag
    hits = [{"doc_id": "D1", "page": 1, "block": "b1", "text": "Invigilators must report 48 minutes before the session."}]
    docs = {"D1": {"title": "T", "ref": "R", "status": "Active", "effective": "", "expiry": ""}}
    monkeypatch.setattr(rag, "chat", lambda *a, **k: {
        "label": "One source", "body": [{"p": "They report **48 minutes** before."}],
        "cites": [{"excerpt": "1", "quote": "48 minutes before the session"}], "follow": []})
    res = rag._generate("q", hits, docs, "en")
    assert res["body"][0]["p"].endswith("{1}")
    assert res["cites"] == [{"doc": "D1", "page": 1, "block": "b1", "quote": "48 minutes before the session"}]


ROWS = [["Date", "Subject", "Time"], ["14/10/2026", "Library Cataloguing", "09:00 AM"], ["15/10/2026", "Library Classification", "02:00 PM"]]
WANT = "Date | Subject | Time\n14/10/2026 | Library Cataloguing | 09:00 AM\n15/10/2026 | Library Classification | 02:00 PM"


def test_word_tables_are_read_row_by_row():
    from docx import Document
    from app import extract
    d = Document()
    d.add_paragraph("Exam schedule for the first semester.")
    t = d.add_table(rows=3, cols=3)
    for r, row in enumerate(ROWS):
        for c, v in enumerate(row):
            t.cell(r, c).text = v
    buf = io.BytesIO()
    d.save(buf)
    texts = [b["text"] for p in extract.extract("t.docx", buf.getvalue())["pages"] for b in p]
    assert texts == ["Exam schedule for the first semester.", WANT]  # tables used to be skipped entirely


def test_pdf_tables_are_read_row_by_row_even_when_written_column_by_column():
    import pymupdf
    from app import extract
    pdf = pymupdf.open()
    page = pdf.new_page()
    page.insert_text((50, 60), "Exam schedule for the first semester.")
    xs, y0, rh = [50, 170, 360, 480], 90, 24
    for col in range(3):
        for r, row in enumerate(ROWS):
            page.insert_text((xs[col] + 4, y0 + r * rh + 16), row[col])
    for r in range(4):
        page.draw_line((xs[0], y0 + r * rh), (xs[-1], y0 + r * rh))
    for x in xs:
        page.draw_line((x, y0), (x, y0 + 3 * rh))
    texts = [b["text"] for p in extract.extract("t.pdf", pdf.tobytes())["pages"] for b in p]
    assert texts == ["Exam schedule for the first semester.", WANT]


def test_deleting_a_chat_removes_bookmarks_of_its_answers(client, people):
    v = people["Viewer"]
    assert put(client, v, "chats", {"id": "chB", "title": "x", "msgs": []}).status_code == 200
    assert put(client, v, "bm_answers", {"id": "baB", "chat": "chB", "msg": "m1", "q": "q"}).status_code == 200
    assert client.delete("/records/chats/chB", headers=v).status_code == 200
    assert not any(b["id"] == "baB" for b in client.get("/records", headers=v).json()["bm_answers"])


def test_original_file_is_kept_shown_to_permitted_people_and_removed_with_the_document(client, people, admin):
    up, ap, v = people["Uploader"], people["Approver"], people["Viewer"]
    raw = b"Original notice text about the library timings."
    ex = client.post("/extract", headers=up, files={"file": ("notice.txt", io.BytesIO(raw), "text/plain")}).json()
    assert ex["file"]["name"] == "notice.txt"
    d = doc("OF1", status="Pending", file=ex["file"])
    assert put(client, up, "documents", d).status_code == 200
    assert client.get("/documents/OF1/file", headers=up).content == raw          # their own pending upload
    assert client.get("/documents/OF1/file", headers=v).status_code == 404       # not published yet
    assert put(client, ap, "documents", {**d, "status": "Active"}).status_code == 200
    assert client.get("/documents/OF1/file", headers=v).content == raw
    fake = doc("OF2", status="Pending", file={"key": "0" * 64, "name": "x.pdf", "mime": "application/pdf"})
    assert put(client, up, "documents", fake).status_code == 200
    assert client.get("/documents/OF2/file", headers=up).status_code == 404     # unknown files aren't attached
    assert client.delete("/records/documents/OF1", headers=admin).status_code == 200
    from app import store
    assert not store.has_file(ex["file"]["key"])


def test_pdf_pages_are_served_as_pictures_to_permitted_people(client, people):
    import pymupdf
    up, v = people["Uploader"], people["Viewer"]
    pdf = pymupdf.open()
    for i in range(2):
        pdf.new_page().insert_text((72, 72), f"Page {i + 1} of the notice about hostel timings.")
    ex = client.post("/extract", headers=up, files={"file": ("n.pdf", io.BytesIO(pdf.tobytes()), "application/pdf")}).json()
    assert ex["file"]["pages"] == 2
    assert put(client, up, "documents", doc("PG1", status="Pending", file=ex["file"])).status_code == 200
    r = client.get("/documents/PG1/file/page/2", headers=up)
    assert r.status_code == 200 and r.content[:2] == bytes([0xFF, 0xD8])  # a JPEG
    assert client.get("/documents/PG1/file/page/3", headers=up).status_code == 404
    assert client.get("/documents/PG1/file/page/1", headers=v).status_code == 404   # not published


def test_answer_text_is_always_plain_strings(monkeypatch):
    """The model sometimes returns objects where text belongs; that used to crash the Ask page."""
    from app import rag
    hits = [{"doc_id": "D1", "page": 1, "block": "b1", "text": "Exams start on 12 October."}]
    docs = {"D1": {"title": "T", "ref": "R", "status": "Active", "effective": "", "expiry": ""}}
    monkeypatch.setattr(rag, "chat", lambda *a, **k: {
        "label": "One source", "banner": {"kind": "revised", "text": {"text": "Changed."}},
        "body": ["Plain {1}", {"ul": [{"item": "First"}, "Second"]}, {"table": {"head": ["A", 1], "rows": [[{"v": "x"}, 2]]}}],
        "cites": [{"excerpt": 1}], "follow": [{"question": "When do exams end?"}, None, "Where?"]})
    res = rag._generate("q", hits, docs, "en")
    assert res["follow"] == ["When do exams end?", "Where?"]
    assert res["body"] == [{"p": "Plain {1}"}, {"ul": ["First", "Second"]}, {"table": {"head": ["A", "1"], "rows": [["x", "2"]]}}]
    assert res["banner"] == {"kind": "revised", "text": "Changed."}


def test_tiny_fragments_join_the_next_paragraph():
    from app import extract
    text = "NOTICE\n\nARTI\n\nThe first sessional test will be held as per the following schedule.\n\nHead"
    texts = [b["text"] for p in extract.extract("n.txt", text.encode())["pages"] for b in p]
    assert texts == ["NOTICE\nARTI\nThe first sessional test will be held as per the following schedule.\nHead"]


def test_exact_codes_find_the_right_paragraph(client, people):
    """Meaning-based search alone can miss codes; the exact match brings the right document first."""
    ap, v = people["Approver"], people["Viewer"]
    other = [[{"id": "b1", "text": "General guidance for invigilators during examinations.", "kind": "p"}]]
    coded = [[{"id": "b1", "text": "MLIS-104 Information Sources and Systems is held at 09:00 AM.", "kind": "p"}]]
    assert put(client, ap, "documents", doc("EX1", status="Active", pages=other)).status_code == 200
    assert put(client, ap, "documents", doc("EX2", status="Active", pages=coded)).status_code == 200
    r = client.post("/ask", headers=v, json={"question": "When is MLIS-104?", "scope_ids": ["EX1", "EX2"]}).json()
    assert r["cites"][0]["doc"] == "EX2"


def test_corrected_text_must_be_well_formed(client, people):
    up = people["Uploader"]
    for bad in ("text", [["b1"]], [[{"id": "b1", "text": "a"}, {"id": "b1", "text": "b"}]], [[{"id": "b1", "text": 5}]]):
        assert put(client, up, "documents", doc("BAD1", pages=bad)).status_code == 400, bad
    fixed = [[{"id": "b1", "text": "Corrected OCR text.", "kind": "p"}]]
    assert put(client, up, "documents", doc("BAD1", pages=fixed)).status_code == 200
