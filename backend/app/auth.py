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
    rec = next((u for u in store.all_records()["users"] if str(u.get("login_id", "")) == login_id), None)
    if rec and rec.get("active") is False:  # deactivated in Administration
        return None
    return {"login_id": login_id, "employee_id": 0,
            "name": rec["name"] if rec else login_id, "email": rec.get("email", "") if rec else "",
            "dept": rec.get("dept", "") if rec else ""}


def app_role(login_id: str) -> str:
    """Role this app grants the user: a bootstrap admin, their saved role, or Viewer by default."""
    login_id = str(login_id).strip()
    if settings.dev_admin_user and login_id == settings.dev_admin_user:
        return "Administrator"
    for u in store.all_records()["users"]:
        if str(u.get("login_id", "")) == login_id:
            return u["role"] if u["role"] in ROLES else "Viewer"
    return "Viewer"


def make_token(user: dict, role: str) -> str:
    payload = {**user, "role": role,
               "exp": datetime.now(timezone.utc) + timedelta(hours=settings.token_hours)}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def current_user(authorization: str = Header(default="")) -> dict:
    token = authorization.removeprefix("Bearer ").strip()
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise HTTPException(401, "Please sign in again.")


def require_role(*allowed: str):
    def check(user: dict = Depends(current_user)) -> dict:
        if user.get("role") not in allowed:
            raise HTTPException(403, "You don't have permission for this action.")
        return user
    return check
