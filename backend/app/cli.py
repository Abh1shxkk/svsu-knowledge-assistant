"""Command-line admin tasks.

    python -m app.cli create-admin --login-id 636325823 --name "Abhishek Chauhan" --dept Administration
    python -m app.cli backup --to D:/backups/svsu      # a dated, compressed copy of the whole database

The password is typed at a hidden prompt, so it never appears on screen or in shell history.
Restore a backup with: pg_restore --clean --dbname <DATABASE_URL> <file>
"""
import argparse
import getpass
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from . import auth, store


def create_admin(login_id: str, name: str, email: str, dept: str) -> None:
    password = getpass.getpass("New password: ")
    if err := auth.password_problem(password):
        sys.exit(err)
    if getpass.getpass("Repeat password: ") != password:
        sys.exit("The passwords don't match.")
    existing = store.get("users", "us-" + login_id) or {}
    store.put("users", "us-" + login_id, {
        **existing, "id": "us-" + login_id, "login_id": login_id, "name": name or existing.get("name", login_id),
        "email": email or existing.get("email", ""), "dept": dept or existing.get("dept", ""),
        "role": "Administrator", "active": True, "last": existing.get("last", "Never"),
    })
    store.set_credential(login_id, auth.hash_password(password))
    print(f"{name or login_id} ({login_id}) is now an Administrator. Sign in with that Login ID.")


def backup(folder: str, keep: int) -> None:
    """pg_dump in custom format (compressed, restorable with pg_restore); keeps the newest `keep` files."""
    from .database import engine
    pg_dump = shutil.which("pg_dump")
    if not pg_dump:  # local development: the PostgreSQL that pgserver bundles
        import pgserver
        pg_dump = str(Path(pgserver.__file__).parent / "pginstall" / "bin" / "pg_dump")
    out_dir = Path(folder)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"svsu-{datetime.now():%Y%m%d-%H%M%S}.dump"
    url = engine.url.set(drivername="postgresql").render_as_string(hide_password=False)
    subprocess.run([pg_dump, "--format=custom", "--file", str(out), url], check=True)
    for old in sorted(out_dir.glob("svsu-*.dump"))[:-keep]:
        old.unlink()
    print(f"Saved {out} ({out.stat().st_size // 1024} KB)")


def main() -> None:
    p = argparse.ArgumentParser(prog="python -m app.cli")
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("create-admin", help="create an administrator, or make an existing account one")
    a.add_argument("--login-id", required=True)
    a.add_argument("--name", default="")
    a.add_argument("--email", default="")
    a.add_argument("--dept", default="")
    b = sub.add_parser("backup", help="save a copy of the database (run daily from Task Scheduler or cron)")
    b.add_argument("--to", default="D:/backups/svsu")
    b.add_argument("--keep", type=int, default=30, help="how many backups to keep")
    args = p.parse_args()
    if args.cmd == "create-admin":
        create_admin(args.login_id.strip(), args.name, args.email, args.dept)
    elif args.cmd == "backup":
        backup(args.to, args.keep)


if __name__ == "__main__":
    main()
