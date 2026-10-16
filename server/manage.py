#!/usr/bin/env python3
"""Small helpers for running the server.

    python manage.py hash-password     make ADMIN_PASSWORD_HASH (so no plain password sits in a file)
    python manage.py gen-secret        make a value for ADMIN_KEY or SESSION_SECRET
    python manage.py gen-password      make a strong password
"""
import getpass
import secrets
import string
import sys


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "hash-password":
        from app.staff import hash_password, password_problems

        pw = getpass.getpass("Admin password: ")
        problems = password_problems(pw)
        if problems:
            print("Too weak. It needs " + ", ".join(problems) + ".")
            return 1
        if pw != getpass.getpass("Again: "):
            print("They don't match.")
            return 1
        print("\nADMIN_PASSWORD_HASH=" + hash_password(pw))
        return 0
    if cmd == "gen-secret":
        print(secrets.token_urlsafe(32))
        return 0
    if cmd == "gen-password":
        alphabet = string.ascii_letters + string.digits + "!@#$%^&*-_=+"
        while True:
            pw = "".join(secrets.choice(alphabet) for _ in range(18))
            if any(c.islower() for c in pw) and any(c.isupper() for c in pw) and any(c.isdigit() for c in pw) and any(c in "!@#$%^&*-_=+" for c in pw):
                print(pw)
                return 0
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
