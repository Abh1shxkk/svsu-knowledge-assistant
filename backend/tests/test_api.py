"""The API end to end, per role, against the test database."""
import io
import json

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


def _model_writes(monkeypatch, text):
    from app import rag
    monkeypatch.setattr(rag, "chat_stream", lambda *a, **k: iter([text[:9], text[9:]]))
    hits = [{"doc_id": "D1", "page": 1, "block": "b1", "text": "Invigilators must report 48 minutes before the session."}]
    docs = {"D1": {"title": "T", "ref": "R", "status": "Active", "effective": "", "expiry": ""}}
    return list(rag._generate("q", hits, docs, "en", check=False))


def test_answer_keeps_citations_when_the_model_forgets_the_markers(monkeypatch):
    events = _model_writes(monkeypatch, 'They report **48 minutes** before.\n---META---\n'
                                        '{"label": "One source", "cites": [{"excerpt": "1", "quote": "48 minutes before the session"}]}')
    res = events[-1]["done"]
    assert res["body"][0]["p"].endswith("{1}")
    assert res["cites"] == [{"doc": "D1", "page": 1, "block": "b1", "quote": "48 minutes before the session"}]
    assert "".join(e.get("delta", "") for e in events).strip() == "They report **48 minutes** before."  # no META shown


def test_markdown_answers_become_paragraphs_lists_and_tables(monkeypatch):
    md = ("Invigilators report early [1].\nThey sign in at the desk.\n\n- Bring ID [1]\n- Be on time\n\n"
          "| Date | Time |\n|---|---|\n| 14/10/2026 | 09:00 [1, 1] |\n---META---\n"
          '{"label": "Revised policy", "banner": {"kind": "revised", "text": {"text": "Changed."}}, '
          '"follow": [{"question": "When do exams end?"}, null, "Where?"]}')
    res = _model_writes(monkeypatch, md)[-1]["done"]
    assert res["body"] == [{"p": "Invigilators report early {1}. They sign in at the desk."}, {"ul": ["Bring ID {1}", "Be on time"]},
                           {"table": {"head": ["Date", "Time"], "rows": [["14/10/2026", "09:00 {1}{1}"]]}}]
    assert res["label"] == "Revised policy" and res["banner"] == {"kind": "revised", "text": "Changed."}
    assert res["follow"] == ["When do exams end?", "Where?"]


def test_answer_without_details_still_shows_text_and_sources(monkeypatch):
    res = _model_writes(monkeypatch, "They report 48 minutes early [1].")[-1]["done"]
    assert res["label"] == "One source" and res["cites"][0]["doc"] == "D1"


def test_reranking_keeps_the_passages_that_answer(monkeypatch):
    from app import rag
    hits = [{"doc_id": "D1", "text": f"passage {i}"} for i in range(5)]
    docs = {"D1": {"title": "T"}}
    monkeypatch.setattr(rag, "chat", lambda *a, **k: {"scores": [1, 9, 0, 9, 3]})
    assert [h["text"] for h in rag.rerank("q", hits, 3, docs)] == ["passage 1", "passage 3", "passage 4"]
    monkeypatch.setattr(rag, "chat", lambda *a, **k: {"scores": [1, 2]})        # a muddled reply: search order
    assert [h["text"] for h in rag.rerank("q", hits, 2, docs)] == ["passage 0", "passage 1"]


def test_fact_check_flags_unsupported_statements(monkeypatch):
    from app import rag
    monkeypatch.setattr(rag, "chat", lambda *a, **k: {"unsupported": ["Total is 2056", {"s": "Held online"}]})
    assert rag.fact_check("answer", "records") == ["Total is 2056", "Held online"]
    monkeypatch.setattr(rag, "chat", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("down")))
    assert rag.fact_check("answer", "records") == []                          # a failed check never blocks the answer


def test_answers_stream_progress_text_and_the_final_answer(client, people):
    ap, v = people["Approver"], people["Viewer"]
    page = [[{"id": "b1", "text": "Staff may take twelve days of casual leave.", "kind": "p"}]]
    assert put(client, ap, "documents", doc("ST1", status="Active", pages=page)).status_code == 200
    r = client.post("/ask/stream", headers=v, json={"question": "Casual leave?", "scope_ids": ["ST1"]})
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/event-stream")
    events = [json.loads(line[6:]) for line in r.text.splitlines() if line.startswith("data: ")]
    assert events[0] == {"status": "Searching the records…"}
    assert "".join(e.get("delta", "") for e in events).startswith("Twelve days")
    done = events[-1]["done"]
    assert done["cites"][0]["doc"] == "ST1" and done["checks"] == []
    assert done["body"] == client.post("/ask", headers=v, json={"question": "Casual leave?", "scope_ids": ["ST1"]}).json()["body"]


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


def test_bulk_import_queues_processes_and_reports(client, people):
    from app import jobs
    up, ap = people["Uploader"], people["Approver"]
    form = {"batch": "batch-1", "visibility": "All Staff", "publish": "false"}
    txt = ("notice.txt", io.BytesIO(b"Hostel gates close at 10 PM for all resident students from November."), "text/plain")
    assert client.post("/imports", headers=up, data={**form, "publish": "true"}, files={"file": txt}).status_code == 403
    assert client.post("/imports", headers=up, data=form, files={"file": ("x.doc", io.BytesIO(b"x"))}).status_code == 415
    txt[1].seek(0)
    assert client.post("/imports", headers=up, data=form, files={"file": txt}).status_code == 200
    again = ("copy.txt", io.BytesIO(b"Hostel gates close at 10 PM for all resident students from November."), "text/plain")
    assert client.post("/imports", headers=up, data=form, files={"file": again}).status_code == 200
    assert client.post("/imports", headers=up, data=form, files={"file": ("blank.txt", io.BytesIO(b"   "), "text/plain")}).status_code == 200
    while jobs.run_once():
        pass
    [b] = [b for b in client.get("/imports", headers=up).json() if b["batch"] == "batch-1"]
    assert b["counts"] == {"done": 1, "duplicate": 1, "failed": 1}
    assert "No text" in b["failed"][0]["error"]
    mine = [d for d in client.get("/records", headers=up).json()["documents"] if (d.get("file") or {}).get("name") == "notice.txt"]
    assert mine and mine[0]["status"] == "Pending" and mine[0]["uploader_id"] == "t-uploader"
    assert client.get("/imports", headers=ap).json() == [] or all(x["batch"] != "batch-1" for x in client.get("/imports", headers=ap).json())
    assert client.post("/imports/batch-1/retry", headers=up).json() == {"requeued": 1}


def test_quality_report_from_generated_questions(client, people, admin):
    from app import evaluate
    ap = people["Approver"]
    page = [[{"id": "b1", "text": "Every regular employee is entitled to twelve days of casual leave in a calendar year.", "kind": "p"}]]
    assert put(client, ap, "documents", doc("QT1", status="Active", pages=page)).status_code == 200
    summary = evaluate.run(n=3, new=True)
    assert summary["questions"] >= 1 and 0 <= summary["answered_correctly"] <= 100
    assert client.get("/reports/quality", headers=ap).json()["latest"]["id"] == summary["id"]
    assert client.post("/reports/quality/run", headers=ap).status_code == 403   # administrators start a run
    assert client.post("/reports/quality/run", headers=admin).status_code == 200


def test_quality_judge_reads_tables_and_lists():
    from app.rag import flat_text as _flat
    body = [{"p": "Schedule:"}, {"ul": ["Item one"]}, {"table": {"head": ["Date", "Subject"], "rows": [["14/10/2026", "Cataloguing"]]}}]
    assert _flat(body).split(chr(10)) == ["Schedule:", "Item one", "Date | Subject", "14/10/2026 | Cataloguing"]


def test_big_tables_and_long_paragraphs_are_split_into_searchable_pieces():
    from app.extract import _CHUNK, _split_long
    header = "College | Students | Faculty | Total"
    table = "\n".join([header] + [f"College number {i} of the university | {100 + i} | 05 | {105 + i}" for i in range(40)])
    pieces = _split_long(table)
    assert len(pieces) > 1 and all(p.startswith(header) for p in pieces)        # every piece keeps the headings
    assert all(len(p) <= _CHUNK + 120 for p in pieces)
    rows = [ln for p in pieces for ln in p.split(chr(10)) if ln != header]
    assert len(rows) == 40                                                        # no row lost or repeated
    prose = "The committee met on Monday. " * 60
    assert len(_split_long(prose.strip())) > 1
    assert _split_long("A short paragraph.") == ["A short paragraph."]


def test_distinctive_words_are_matched_exactly(client, people):
    """A rare word in the question (here Hindi) finds its paragraph even when meaning-based search doesn't."""
    from app import rag
    ap = people["Approver"]
    common = [[{"id": f"b{i}", "text": f"विश्वविद्यालय परिसर में कार्यक्रम संख्या {i} आयोजित होगा।", "kind": "p"} for i in range(1, 9)]]
    target = [[{"id": "b1", "text": "मुख्य संयोजक श्री चरण सिंह जी हैं जिनका मोबाईल नं० 09045454765 है।", "kind": "p"}]]
    assert put(client, ap, "documents", doc("HW1", status="Active", pages=common)).status_code == 200
    assert put(client, ap, "documents", doc("HW2", status="Active", pages=target)).status_code == 200
    terms = rag.search_terms(["मुख्य संयोजक कौन हैं?"], ["HW1", "HW2"])
    assert "संयोजक" in terms and "विश्वविद्यालय" not in terms


def test_documents_past_expiry_become_expired_automatically(client, people):
    from datetime import date
    from app import jobs, store
    ap = people["Approver"]
    assert put(client, ap, "documents", doc("EXP1", status="Active", expiry="2026-10-10")).status_code == 200
    assert put(client, ap, "documents", doc("EXP2", status="Active", expiry="2026-10-20")).status_code == 200
    jobs.expire_documents(date(2026, 10, 14))
    d1, d2 = store.get("documents", "EXP1"), store.get("documents", "EXP2")
    assert d1["status"] == "Expired" and d1["approvals"][-1]["step"] == "Expired automatically"
    assert d2["status"] == "Active"


def test_two_step_sign_in_with_codes_recovery_codes_and_admin_reset(client, admin):
    import pyotp
    assert client.post("/accounts", headers=admin, json={
        "login_id": "t-mfa", "name": "Two Step", "dept": "Examination", "role": "Viewer", "password": "Password-123"}).status_code == 200
    me = login(client, "t-mfa", "Password-123")
    secret = client.post("/me/mfa/setup", headers=me).json()["secret"]
    assert client.post("/me/mfa/enable", headers=me, json={"code": "000000"}).status_code == 400
    recovery = client.post("/me/mfa/enable", headers=me, json={"code": pyotp.TOTP(secret).now()}).json()["recovery"]
    assert len(recovery) == 8

    r = client.post("/login", json={"login_id": "t-mfa", "password": "Password-123"}).json()
    assert r["mfa"] == "code" and "token" not in r
    assert client.get("/me", headers={"Authorization": "Bearer " + r["ticket"]}).status_code == 401  # not a session
    assert client.post("/login/mfa", json={"ticket": r["ticket"], "code": "123456"}).status_code == 401
    assert "token" in client.post("/login/mfa", json={"ticket": r["ticket"], "code": pyotp.TOTP(secret).now()}).json()
    assert "token" in client.post("/login/mfa", json={"ticket": r["ticket"], "code": recovery[0]}).json()
    assert client.post("/login/mfa", json={"ticket": r["ticket"], "code": recovery[0]}).status_code == 401  # used up

    assert "t-mfa" in client.get("/accounts/mfa", headers=admin).json()
    assert client.delete("/accounts/t-mfa/mfa", headers=admin).status_code == 200
    assert "token" in client.post("/login", json={"login_id": "t-mfa", "password": "Password-123"}).json()


def test_repeated_wrong_passwords_lock_sign_in(client, admin):
    from app import mfa
    assert client.post("/accounts", headers=admin, json={
        "login_id": "t-lock", "name": "Lock", "dept": "Examination", "role": "Viewer", "password": "Password-123"}).status_code == 200
    for _ in range(mfa.MAX_TRIES):
        assert client.post("/login", json={"login_id": "t-lock", "password": "wrong-pass-1"}).status_code == 401
    assert client.post("/login", json={"login_id": "t-lock", "password": "Password-123"}).status_code == 429
    mfa.succeeded("t-lock")  # the lock lifts after 5 minutes
    assert client.post("/login", json={"login_id": "t-lock", "password": "Password-123"}).status_code == 200


def test_required_two_step_is_set_up_during_sign_in(client, admin, people):
    import pyotp
    assert put(client, admin, "settings", {"id": "security", "requireMfa": True}).status_code == 200
    try:
        r = client.post("/login", json={"login_id": "t-approver", "password": "Password-123"}).json()
        assert r["mfa"] == "setup"
        secret = client.post("/login/mfa/setup", json={"ticket": r["ticket"]}).json()["secret"]
        done = client.post("/login/mfa", json={"ticket": r["ticket"], "code": pyotp.TOTP(secret).now()}).json()
        assert done["token"] and len(done["recovery"]) == 8
        assert "token" in client.post("/login", json={"login_id": "t-viewer", "password": "Password-123"}).json()  # not required
        ap = {"Authorization": "Bearer " + done["token"]}
        assert client.post("/me/mfa/disable", headers=ap, json={"password": "Password-123"}).status_code == 400
    finally:
        put(client, admin, "settings", {"id": "security", "requireMfa": False})
        client.delete("/accounts/t-approver/mfa", headers=admin)


def test_cited_passage_is_located_on_the_original_pdf_page(client, people, admin):
    import pymupdf
    from app import store
    up, v = people["Uploader"], people["Viewer"]
    pdf = pymupdf.open()
    page = pdf.new_page()  # 595 x 842 points
    page.insert_text((72, 100), "Subject: Revised timings for the university hostels.")
    page.insert_text((72, 300), "All students must return to the hostel by 9:00 PM on working days.")
    page.insert_text((72, 316), "Late entry needs written permission from the warden in advance.")
    page.insert_text((72, 600), "Copy to: All Heads of Institutions and notice boards.")
    ex = client.post("/extract", headers=up, files={"file": ("h.pdf", io.BytesIO(pdf.tobytes()), "application/pdf")}).json()
    assert put(client, up, "documents", doc("HL1", status="Pending", file=ex["file"])).status_code == 200
    url = "/documents/HL1/file/page/1/highlight"

    quote = "students must return to the hostel by 9:00 PM on working days. Late entry needs written permission"
    rects = client.get(url, headers=up, params={"q": quote}).json()["rects"]
    assert len(rects) == 2                                       # one box per line of the passage
    assert all(0.33 < r[1] < 0.39 and r[0] < 0.2 for r in rects)  # where it was written (y 300-316 of 842)
    assert rects[0][1] < rects[1][1]

    # A misread word or two still finds the passage; an unrelated quote finds nothing.
    assert client.get(url, headers=up, params={"q": "students must retum to the hoste1 by 9:00 PM"}).json()["rects"]
    assert client.get(url, headers=up, params={"q": "The examination fee is due on the first of March"}).json()["rects"] == []
    assert client.get("/documents/HL1/file/page/2/highlight", headers=up, params={"q": quote}).status_code == 404
    assert client.get(url, headers=v, params={"q": quote}).status_code == 404   # not published: not theirs to see

    from app import locate
    assert store.has_file(locate.words_key(ex["file"]["key"], 1))  # positions are kept, not worked out each time
    assert client.delete("/records/documents/HL1", headers=admin).status_code == 200
    assert not store.has_file(locate.words_key(ex["file"]["key"], 1))  # and removed with the document


def test_quotes_match_ocr_words_loosely():
    from app import locate
    # OCR output for two lines, with a misread ("retum") and punctuation stuck to words.
    line1 = ["All", "students", "must", "retum", "to", "the", "hostel,"]
    line2 = ["by", "9:00", "PM", "on", "working", "days."]
    words = [(t, 0.1 + i * 0.1, 0.30, 0.18 + i * 0.1, 0.32) for i, t in enumerate(line1)]
    words += [(t, 0.1 + i * 0.1, 0.34, 0.18 + i * 0.1, 0.36) for i, t in enumerate(line2)]
    words += [("students", 0.1, 0.8, 0.2, 0.82), ("hostel", 0.3, 0.8, 0.4, 0.82)]  # the same words, far away
    rects = locate.match(words, "students must return to the hostel by 9:00 PM on working days")
    assert len(rects) == 2 and all(r[3] < 0.4 for r in rects)  # the two lines, not the stray words below
    assert locate.match(words, "fee payment schedule for March") == []
    assert locate.match([("परीक्षा", .1, .1, .2, .12), ("ड्यूटी", .21, .1, .3, .12), ("समय", .31, .1, .4, .12)], "परीक्षा ड्यूटी का समय")
