"""Access rules: every role × visibility × status, plus write rules. Pure functions, no database."""
import pytest

from app.policy import Ctx, DEFAULT_MATRIX, can_answer, can_view, visible_records, write_error

VIS = ["Public (students & staff)", "All Staff", "Department only", "Management Only"]
CTX = Ctx(vis=VIS, matrix=DEFAULT_MATRIX)


def user(role, login_id="u1", dept="Examination"):
    return {"role": role, "login_id": login_id, "dept": dept}


def doc(visibility="All Staff", status="Active", dept="Examination", uploader_id="up1", id="D1"):
    return {"id": id, "visibility": visibility, "status": status, "dept": dept, "uploader_id": uploader_id}


@pytest.mark.parametrize("role,vis,expected", [
    ("Viewer", "Public (students & staff)", True),
    ("Viewer", "All Staff", True),
    ("Viewer", "Management Only", False),
    ("Uploader", "Management Only", False),
    ("Approver", "Management Only", True),
    ("Administrator", "Management Only", True),
])
def test_visibility_by_role(role, vis, expected):
    assert can_view(user(role), doc(visibility=vis), CTX) is expected


def test_department_only_needs_same_department():
    d = doc(visibility="Department only", dept="Examination")
    assert can_view(user("Viewer", dept="Examination"), d, CTX)
    assert not can_view(user("Viewer", dept="Finance"), d, CTX)
    assert not can_view(user("Viewer", dept=""), d, CTX)
    assert can_view(user("Approver", dept="Finance"), d, CTX)


@pytest.mark.parametrize("status", ["Pending", "Draft", "Changes requested", "Rejected"])
def test_unpublished_hidden_from_viewers_but_not_uploader_or_approver(status):
    d = doc(status=status, uploader_id="up1")
    assert not can_view(user("Viewer"), d, CTX)
    assert not can_view(user("Uploader", login_id="someone-else"), d, CTX)
    assert can_view(user("Uploader", login_id="up1"), d, CTX)  # their own upload
    assert can_view(user("Approver"), d, CTX)


def test_unknown_visibility_is_hidden():
    assert not can_view(user("Viewer"), doc(visibility="Secret"), CTX)


def test_matrix_change_is_enforced():
    strict = Ctx(vis=VIS, matrix={**DEFAULT_MATRIX, "Viewer": [1, 0, 0, 0]})
    assert not can_view(user("Viewer"), doc(visibility="All Staff"), strict)


@pytest.mark.parametrize("status,expected", [("Active", True), ("Superseded", True), ("Expired", True),
                                             ("Withdrawn", False), ("Pending", False)])
def test_answerable_statuses(status, expected):
    assert can_answer(user("Administrator"), doc(status=status), CTX) is expected


def test_visible_records_filters_everything():
    records = {
        "documents": [doc(id="open"), doc(id="secret", visibility="Management Only")],
        "deadlines": [{"id": "dl1", "doc": "open"}, {"id": "dl2", "doc": "secret"}],
        "collections": [{"id": "c1", "docs": ["open", "secret"]}],
        "chats": [{"id": "mine", "owner": "u1"}, {"id": "theirs", "owner": "u2"}, {"id": "legacy"}],
        "bm_answers": [], "bm_passages": [{"id": "bp", "owner": "u1", "doc": "secret"}],
        "unanswered": [{"id": "q"}], "feedback": [{"id": "f"}], "conflicts": [{"id": "c"}],
        "users": [{"id": "x"}], "audit": [{"id": "a"}],
        "settings": [{"id": "lists", "VIS": VIS}, {"id": "roles", "matrix": DEFAULT_MATRIX}],
    }
    v = visible_records(user("Viewer"), records)
    assert [d["id"] for d in v["documents"]] == ["open"]
    assert [x["id"] for x in v["deadlines"]] == ["dl1"]
    assert v["collections"][0]["docs"] == ["open"]
    assert [x["id"] for x in v["chats"]] == ["mine"]
    assert v["bm_passages"] == []  # bookmark of a document they can't see
    assert v["feedback"] == v["conflicts"] == v["users"] == v["audit"] == []
    admin = visible_records(user("Administrator", login_id="adm"), records)
    assert {x["id"] for x in admin["chats"]} == {"legacy"}  # unowned old chats go to admins only
    assert len(admin["users"]) == 1 and len(admin["audit"]) == 1


def test_uploader_cannot_publish_or_reject():
    old = doc(status="Pending", uploader_id="u1")
    for status in ("Active", "Rejected", "Withdrawn"):
        assert write_error(user("Uploader"), "documents", {**old, "status": status}, old, CTX)
    assert write_error(user("Approver"), "documents", {**old, "status": "Active"}, old, CTX) is None


def test_uploader_submits_new_and_resubmits_own():
    assert write_error(user("Uploader"), "documents", doc(status="Pending"), None, CTX) is None
    assert write_error(user("Uploader"), "documents", doc(status="Active"), None, CTX)  # can't self-publish
    mine = doc(status="Changes requested", uploader_id="u1")
    assert write_error(user("Uploader"), "documents", {**mine, "status": "Pending"}, mine, CTX) is None
    theirs = doc(status="Changes requested", uploader_id="other")
    assert write_error(user("Uploader"), "documents", {**theirs, "status": "Pending"}, theirs, CTX)


def test_viewer_writes():
    v = user("Viewer")
    assert write_error(v, "documents", doc(status="Pending"), None, CTX)
    assert write_error(v, "chats", {"id": "c"}, None, CTX) is None              # can save own chats
    assert write_error(v, "chats", {"id": "c"}, {"id": "c", "owner": "u2"}, CTX)  # not someone else's
    assert write_error(v, "feedback", {"id": "f"}, None, CTX) is None
    assert write_error(v, "users", {"id": "x"}, None, CTX)
    assert write_error(v, "settings", {"id": "lists"}, None, CTX)


def test_nobody_writes_audit_and_only_admin_deletes_documents():
    assert write_error(user("Administrator"), "audit", {"id": "a"}, None, CTX)
    d = doc()
    assert write_error(user("Approver"), "documents", None, d, CTX)
    assert write_error(user("Administrator"), "documents", None, d, CTX) is None
