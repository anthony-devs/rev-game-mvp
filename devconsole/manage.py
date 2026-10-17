#!/usr/bin/env python3
"""One-time setup helpers.

    python manage.py setup         choose your password; prints the three CONSOLE_* values and a TOTP secret
    python manage.py gen-secret    a value for DEV_API_SECRET (put the SAME value on the game server and here)
"""
import getpass
import secrets
import sys

from console.security import hash_password, new_totp_secret, otpauth_uri, password_problems


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "gen-secret":
        print(secrets.token_urlsafe(48))
        return 0
    if cmd == "setup":
        user = input("Console username (not 'admin'): ").strip()
        if not user or user.lower() in ("admin", "root", "administrator", "developer"):
            print("Pick something less guessable.")
            return 1
        pw = getpass.getpass("Password: ")
        bad = password_problems(pw)
        if bad:
            print("Too weak. It needs " + ", ".join(bad) + ".")
            return 1
        if pw != getpass.getpass("Again: "):
            print("They don't match.")
            return 1
        secret = new_totp_secret()
        print("\nPut these in the console's environment (never in a file you commit):\n")
        print(f"CONSOLE_USER={user}")
        print(f"CONSOLE_PASSWORD_HASH={hash_password(pw)}")
        print(f"CONSOLE_TOTP_SECRET={secret}\n")
        print("Add the authenticator account: open Google Authenticator / 1Password / Authy, choose")
        print("'enter a setup key', and type the TOTP secret above (time based, 6 digits). Or use this link:\n")
        print(otpauth_uri(secret, user) + "\n")
        print("Keep a backup of the TOTP secret somewhere safe (a password manager). Without it you can't sign in.")
        return 0
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
