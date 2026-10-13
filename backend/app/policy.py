"""Who may see, answer from and change what.

The single source of truth for access. The server applies it to every response and every write;
the browser never decides. Pure functions, so every rule is unit-tested (tests/test_policy.py).
"""
from dataclasses import dataclass, field

APPROVERS = {"Administrator", "Approver"}
UPLOADERS = APPROVERS | {"Uploader"}
HIDDEN = {"Pending", "Draft", "Changes requested", "Rejected"}  # not published yet
ANSWERABLE = {"Active", "Superseded", "Expired"}               # the assistant may cite these
EDITABLE = {"Draft", "Pending", "Changes requested"}            # an uploader may still change their own
OWNED = {"chats", "bm_answers", "bm_passages", "reminders", "prefs"}  # private to the person who made them
DEFAULT_MATRIX = {"Administrator": [1, 1, 1, 1], "Approver": [1, 1, 1, 1],
                  "Uploader": [1, 1, 1, 0], "Viewer": [1, 1, 1, 0]}


@dataclass
class Ctx:
    """The settings the rules depend on: visibility levels (in order) and role → allowed levels."""
    vis: list[str] = field(default_factory=list)
    matrix: dict[str, list[int]] = field(default_factory=dict)

    @classmethod
    def from_settings(cls, settings: list[dict]) -> "Ctx":
        by_id = {s["id"]: s for s in settings}
        return cls(vis=by_id.get("lists", {}).get("VIS", []),
                   matrix=by_id.get("roles", {}).get("matrix", DEFAULT_MATRIX))


def can_view(user: dict, doc: dict, ctx: Ctx) -> bool:
    role = user.get("role", "Viewer")
    if role == "Administrator":
        return True
    if doc.get("status") in HIDDEN:  # unpublished: approvers, and the person who uploaded it
        return role in APPROVERS or (bool(doc.get("uploader_id")) and doc["uploader_id"] == user.get("login_id"))
    vis = doc.get("visibility", "")
    allowed = ctx.matrix.get(role, DEFAULT_MATRIX["Viewer"])
    if vis not in ctx.vis:
        return False
    i = ctx.vis.index(vis)
    if i >= len(allowed) or not allowed[i]:
        return False
    if vis == "Department only" and role not in APPROVERS:
        return bool(user.get("dept")) and user["dept"] == doc.get("dept")
    return True


def can_answer(user: dict, doc: dict, ctx: Ctx) -> bool:
    return doc.get("status") in ANSWERABLE and can_view(user, doc, ctx)


def visible_records(user: dict, records: dict[str, list[dict]]) -> dict[str, list[dict]]:
    """Everything this person may receive, nothing else."""
    ctx = Ctx.from_settings(records["settings"])
    role, me = user.get("role", "Viewer"), user.get("login_id")
    docs = [d for d in records["documents"] if can_view(user, d, ctx)]
    ids = {d["id"] for d in docs}
    mine = lambda x: x.get("owner") == me or (role == "Administrator" and not x.get("owner"))  # noqa: E731
    return {
        "documents": [{k: v for k, v in d.items() if k != "pages"} for d in docs],  # text loads per document
        "deadlines": [x for x in records["deadlines"] if x.get("doc") in ids],
        "collections": [{**c, "docs": [i for i in c.get("docs", []) if i in ids]} for c in records["collections"]],
        "chats": [x for x in records["chats"] if mine(x)],
        "bm_answers": [x for x in records["bm_answers"] if mine(x)],
        "bm_passages": [x for x in records["bm_passages"] if mine(x) and x.get("doc") in ids],
        "reminders": [x for x in records.get("reminders", []) if x.get("owner") == me],
        "prefs": [x for x in records.get("prefs", []) if x.get("owner") == me],
        "unanswered": records["unanswered"],
        "feedback": records["feedback"] if role in APPROVERS else [],
        "conflicts": records["conflicts"] if role in APPROVERS else [],
        "users": records["users"] if role == "Administrator" else [],
        "audit": records["audit"] if role == "Administrator" else [],
        "settings": records["settings"],
    }


def write_error(user: dict, kind: str, new: dict | None, old: dict | None, ctx: Ctx) -> str | None:
    """None if this person may save `new` over `old` (new=None means delete), else the reason."""
    role, me = user.get("role", "Viewer"), user.get("login_id")
    admin = role == "Administrator"
    if kind in ("audit", "questions"):
        return "This is written by the server."
    if kind in ("users", "settings"):
        return None if admin else "Only administrators can change this."
    if kind in OWNED or kind == "collections":
        owner = (old or {}).get("owner")
        return None if admin or old is None or owner in (None, me) else "That belongs to someone else."
    if kind == "documents":
        if role not in UPLOADERS:
            return "Only uploaders, approvers and administrators can change documents."
        if old is not None and not can_view(user, old, ctx):
            return "Document not found."
        if new is None:
            return None if admin else "Only administrators can delete documents."
        if new.get("visibility") not in ctx.vis:
            return "Choose who can see this document."
        if role not in APPROVERS:
            # Uploaders only work on their own unpublished documents, and can only save or submit them.
            if old is not None and (old.get("uploader_id") != me or old.get("status") not in EDITABLE):
                return "Only approvers can change a published document."
            if new.get("status") not in ("Draft", "Pending"):
                return "Only approvers can publish, reject or withdraw documents."
        return None
    if kind == "deadlines":
        return None if role in UPLOADERS else "Only uploaders, approvers and administrators can change deadlines."
    if kind in ("feedback", "conflicts"):  # anyone may add one; approvers manage them
        own = kind == "feedback" and old is not None and old.get("owner") == me and new is not None
        return None if old is None and new is not None or own or role in APPROVERS else "Only approvers can change this."
    if kind == "unanswered":  # logged by the server; approvers assign and close them
        return None if role in APPROVERS else "Only approvers can change this."
    return "Unknown record kind."
