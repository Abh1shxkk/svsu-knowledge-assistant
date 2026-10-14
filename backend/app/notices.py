"""Notifications, worked out on request from the current data, and deadline reminder emails."""
import smtplib
from datetime import date
from email.message import EmailMessage

from . import auth, policy, store
from .config import settings

DEFAULT_DAYS = 3  # deadlines show in the bell this many days ahead unless the person set a reminder


def _days_to(iso: str) -> int | None:
    try:
        return (date.fromisoformat(iso) - date.today()).days
    except (TypeError, ValueError):
        return None


def _due(title: str, days: int) -> str:
    return f"{title} is due today" if days == 0 else f"{title} is due in {days} day{'s' if days > 1 else ''}"


def for_user(user: dict, ctx: policy.Ctx) -> list[dict]:
    """[{key, text, href}] — key changes when the news does, so 'mark all read' only hides what was seen."""
    r = store.records_of("documents", "deadlines", "conflicts", "unanswered", "reminders")
    role, me = user.get("role"), user.get("login_id")
    docs = {d["id"]: d for d in r["documents"] if policy.can_view(user, d, ctx)}
    out = []
    if role in policy.APPROVERS:
        n = sum(d.get("status") == "Pending" for d in docs.values())
        if n:
            out.append({"key": f"pending:{n}", "text": f"{n} document{'s' if n > 1 else ''} waiting for your approval", "href": "/review"})
        out += [{"key": f"cf:{c['id']}", "text": f"Conflict: {c.get('topic', '')}", "href": "/reports"}
                for c in r["conflicts"] if c.get("status") == "Open"]
        out += [{"key": f"rq:{u['id']}", "text": f"Document requested: {u.get('q', '')}", "href": "/reports"}
                for u in r["unanswered"] if u.get("status") == "Requested"]
    out += [{"key": f"doc:{d['id']}:{d['status']}", "text": f"{d.get('title', '')}: {d['status'].lower()}", "href": f"/library/{d['id']}"}
            for d in docs.values() if d.get("uploader_id") == me and d.get("status") in ("Changes requested", "Rejected")]
    window = {x["deadline"]: int(x.get("days", DEFAULT_DAYS)) for x in r["reminders"] if x.get("owner") == me}
    for x in r["deadlines"]:
        days = _days_to(x.get("date"))
        if not x.get("done") and x.get("doc") in docs and days is not None and 0 <= days <= window.get(x["id"], DEFAULT_DAYS):
            out.append({"key": f"dl:{x['id']}:{days}", "text": _due(x.get("title", "A deadline"), days), "href": "/deadlines"})
    return out


def send_due_reminders() -> int:
    """Email everyone whose reminder falls today. Each reminder is sent at most once a day."""
    if not settings.smtp_host:
        return 0
    today, sent = date.today().isoformat(), 0
    deadlines = {x["id"]: x for x in store.list_of("deadlines")}
    docs = {d["id"]: d for d in store.list_of("documents")}
    ctx = policy.Ctx.from_settings(store.list_of("settings"))
    for rem in store.list_of("reminders"):
        x = deadlines.get(rem.get("deadline"))
        if not x or x.get("done") or rem.get("sent") == today or "Email" not in rem.get("via", []):
            continue
        if _days_to(x.get("date")) != int(rem.get("days", DEFAULT_DAYS)):
            continue
        rec = auth.user_record(rem.get("owner", ""))
        if not rec or not rec.get("email") or rec.get("active") is False:
            continue
        doc = docs.get(x.get("doc"))
        if not doc or not policy.can_view(auth._profile(rem["owner"], rec), doc, ctx):  # lost access since
            continue
        msg = EmailMessage()
        msg["From"], msg["To"] = settings.smtp_from or settings.smtp_user, rec["email"]
        msg["Subject"] = f"Reminder: {x.get('title')} — due {x.get('date')}"
        msg.set_content(f"{_due(x.get('title', 'A deadline'), int(rem.get('days', 0)))} ({x.get('date')}).\n"
                        f"Responsible: {x.get('owner', '')}. Applies to: {x.get('aud', '')}.\n\n"
                        "Sent by the SVSU Knowledge Assistant.")
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as smtp:
            smtp.starttls()
            if settings.smtp_user:
                smtp.login(settings.smtp_user, settings.smtp_pass)
            smtp.send_message(msg)
        store.put("reminders", rem["id"], {**rem, "sent": today})
        sent += 1
    return sent
