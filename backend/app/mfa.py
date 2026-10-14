"""Two-step verification: a 6-digit code from an authenticator app (TOTP) after the password, with
one-time recovery codes for a lost phone. Also slows down guessing: repeated wrong passwords or codes
lock that Login ID for a few minutes.

Each person's state is one row in the secrets table, "mfa:<login_id>": the TOTP secret, plus in its
details whether it is switched on and the bcrypt hashes of the unused recovery codes.
"""
import base64
import io
import secrets as rnd
import time
from datetime import datetime

import pyotp
import qrcode
import qrcode.image.svg

from . import auth, store

ISSUER = "SVSU Knowledge Assistant"
MAX_TRIES, LOCK_SECONDS = 5, 300
_failures: dict[str, tuple[int, float]] = {}  # login_id -> (failures in a row, locked until)


def locked(login_id: str) -> bool:
    return _failures.get(login_id.strip(), (0, 0))[1] > time.time()


def failed(login_id: str) -> None:
    n = _failures.get(login_id.strip(), (0, 0))[0] + 1
    _failures[login_id.strip()] = (0, time.time() + LOCK_SECONDS) if n >= MAX_TRIES else (n, 0)


def succeeded(login_id: str) -> None:
    _failures.pop(login_id.strip(), None)


def _row(login_id: str) -> tuple[str, dict] | None:
    return store.get_secret("mfa:" + login_id)


def is_on(login_id: str) -> bool:
    row = _row(login_id)
    return bool(row and row[1].get("on"))


def status(login_id: str) -> dict:
    row = _row(login_id)
    return {"on": bool(row and row[1].get("on")), "recovery_left": len(row[1].get("recovery", [])) if row else 0}


def start(login_id: str) -> dict:
    """A new secret, not yet switched on, with the QR code the authenticator app scans."""
    secret = pyotp.random_base32()
    store.set_secret("mfa:" + login_id, secret, {"on": False})
    uri = pyotp.TOTP(secret).provisioning_uri(name=login_id, issuer_name=ISSUER)
    buf = io.BytesIO()
    qrcode.make(uri, image_factory=qrcode.image.svg.SvgPathImage, box_size=8).save(buf)
    return {"secret": secret, "uri": uri, "qr": "data:image/svg+xml;base64," + base64.b64encode(buf.getvalue()).decode()}


def enable(login_id: str, code: str) -> list[str] | None:
    """Switches it on when the code matches the new secret; returns the recovery codes (shown once)."""
    row = _row(login_id)
    if not row or row[1].get("on") or not pyotp.TOTP(row[0]).verify(code.strip(), valid_window=1):
        return None
    codes = [f"{rnd.randbelow(10**8):08d}" for _ in range(8)]
    store.set_secret("mfa:" + login_id, row[0], {"on": True, "at": datetime.now().isoformat(timespec="seconds"),
                                                 "recovery": [auth.hash_password(c) for c in codes]})
    return [f"{c[:4]}-{c[4:]}" for c in codes]


def check(login_id: str, code: str) -> bool:
    """A current authenticator code, or an unused recovery code (which is then used up)."""
    row = _row(login_id)
    if not row or not row[1].get("on"):
        return False
    code = code.strip().replace(" ", "")
    if code.isdigit() and len(code) == 6:
        return pyotp.TOTP(row[0]).verify(code, valid_window=1)
    plain = code.replace("-", "")
    hashes = row[1].get("recovery", [])
    for h in hashes:
        if auth._check(plain, h):
            store.set_secret("mfa:" + login_id, row[0], {**row[1], "recovery": [x for x in hashes if x != h]})
            return True
    return False


def remove(login_id: str) -> None:
    store.delete_secret("mfa:" + login_id)


def required(role: str) -> bool:
    """Administrators can require it for the accounts that can change or publish records."""
    return bool((store.get("settings", "security") or {}).get("requireMfa")) and role in ("Administrator", "Approver")
