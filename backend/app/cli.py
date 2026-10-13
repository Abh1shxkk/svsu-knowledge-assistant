"""Command-line admin tasks.

    python -m app.cli create-admin --login-id 636325823 --name "Abhishek Chauhan" --dept Administration

The password is typed at a hidden prompt, so it never appears on screen or in shell history.
"""
import argparse
import getpass
import sys

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


def main() -> None:
    p = argparse.ArgumentParser(prog="python -m app.cli")
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("create-admin", help="create an administrator, or make an existing account one")
    a.add_argument("--login-id", required=True)
    a.add_argument("--name", default="")
    a.add_argument("--email", default="")
    a.add_argument("--dept", default="")
    args = p.parse_args()
    if args.cmd == "create-admin":
        create_admin(args.login_id.strip(), args.name, args.email, args.dept)


if __name__ == "__main__":
    main()
