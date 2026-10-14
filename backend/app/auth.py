"""App-managed accounts: an Administrator creates a login (Login ID + password); the password is
stored as a bcrypt hash in the project's PostgreSQL database. Each person's role and details live in
the `users` records.
"""
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from fastapi import Depends, Header, HTTPException

from . import store
from .config import settings

ROLES = ["Administrator", "Approver", "Uploader", "Viewer"]


def password_problem(password: str) -> str | None:
    """None if the password is acceptable, else what's wrong with it."""
    if len(password) < 10:
        return "Use at least 10 characters."
    if password.isdigit() or password.isalpha():
        return "Mix letters with numbers or symbols."
    return None


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode()


def _check(password: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), hashed.encode())
    except ValueError:
        return False


def verify(login_id: str, password: str) -> dict | None:
    """Return the user if the Login ID + password match, else None."""
    login_id = login_id.strip()
    # Local test admin (dev only).
    if settings.dev_admin_user and login_id == settings.dev_admin_user and password == settings.dev_admin_pass:
        return {"login_id": login_id, "employee_id": 0, "name": "Test Administrator", "email": "", "dev": True}
    hashed = store.get_credential(login_id)
    if not hashed or not _check(password, hashed):
        return None
    rec = user_record(login_id)
    if not rec or rec.get("active") is False:  # no account, or deactivated in Administration
        return None
    return _profile(login_id, rec)


def user_record(login_id: str) -> dict | None:
    return store.get("users", "us-" + str(login_id).strip())


def _profile(login_id: str, rec: dict) -> dict:
    return {"login_id": login_id, "employee_id": 0, "name": rec.get("name") or login_id,
            "email": rec.get("email", ""), "dept": rec.get("dept", ""),
            "role": rec["role"] if rec.get("role") in ROLES else "Viewer"}


def app_role(login_id: str) -> str:
    """Role this app grants the user: the test admin, their saved role, or Viewer by default."""
    if settings.dev_admin_user and str(login_id).strip() == settings.dev_admin_user:
        return "Administrator"
    rec = user_record(login_id)
    return rec["role"] if rec and rec.get("role") in ROLES else "Viewer"


def make_token(user: dict, role: str) -> str:
    payload = {**user, "role": role,
               "exp": datetime.now(timezone.utc) + timedelta(hours=settings.token_hours)}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def make_ticket(login_id: str) -> str:
    """Proof that the password was right, valid for 5 minutes, exchanged for a session with a code."""
    payload = {"login_id": login_id, "ticket": True, "exp": datetime.now(timezone.utc) + timedelta(minutes=5)}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def read_ticket(ticket: str) -> str:
    try:
        payload = jwt.decode(ticket, settings.jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        payload = {}
    if not payload.get("ticket"):
        raise HTTPException(401, "Sign-in took too long. Enter your password again.")
    return payload["login_id"]


def current_user(authorization: str = Header(default="")) -> dict:
    """The signed-in person, read fresh on every request: a role change, deactivation or deleted
    account takes effect immediately, not when their sign-in expires."""
    token = authorization.removeprefix("Bearer ").strip()
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise HTTPException(401, "Please sign in again.")
    if payload.get("ticket"):  # half-way through two-step sign-in: not a session
        raise HTTPException(401, "Please sign in again.")
    if payload.get("dev"):
        if payload.get("login_id") != settings.dev_admin_user:  # test admin was removed from .env
            raise HTTPException(401, "Please sign in again.")
        return payload
    rec = user_record(payload.get("login_id", ""))
    if not rec or rec.get("active") is False:
        raise HTTPException(401, "Your account is no longer active.")
    return {**_profile(payload["login_id"], rec), "dev": False}


def require_role(*allowed: str):
    def check(user: dict = Depends(current_user)) -> dict:
        if user.get("role") not in allowed:
            raise HTTPException(403, "You don't have permission for this action.")
        return user
    return check
