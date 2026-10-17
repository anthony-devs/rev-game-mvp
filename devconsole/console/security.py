"""Sign-in and session security.

Password (scrypt) + one-time code from an authenticator app (TOTP, RFC 6238) on every sign-in.
Wrong attempts lock the account and the address. Sessions are random tokens kept hashed on the
server, in HttpOnly SameSite=Strict cookies, with an idle and an absolute timeout. Every change
needs a CSRF token, and the sensitive ones (deploy, migrate, maintenance) ask for a fresh code.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import struct
import time

from .db import DB

SCRYPT_N, SCRYPT_R, SCRYPT_P = 2**14, 8, 1


def hash_password(pw: str) -> str:
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(pw.encode(), salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P, maxmem=64 * 1024 * 1024, dklen=32)
    return "scrypt$%d$%d$%d$%s$%s" % (SCRYPT_N, SCRYPT_R, SCRYPT_P, base64.b64encode(salt).decode(), base64.b64encode(h).decode())


def verify_password(pw: str, stored: str) -> bool:
    try:
        _, n, r, p, salt, want = stored.split("$")
        h = hashlib.scrypt(pw.encode(), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p), maxmem=64 * 1024 * 1024, dklen=32)
        return hmac.compare_digest(h, base64.b64decode(want))
    except Exception:
        return False


def password_problems(pw: str) -> list[str]:
    out = []
    if len(pw) < 14:
        out.append("at least 14 characters")
    if not any(c.islower() for c in pw) or not any(c.isupper() for c in pw):
        out.append("upper and lower case letters")
    if not any(c.isdigit() for c in pw):
        out.append("a number")
    if not any(not c.isalnum() for c in pw):
        out.append("a symbol")
    return out


# ------------------------------------------------------------------------ TOTP

def new_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def totp_at(secret: str, counter: int, digits: int = 6) -> str:
    key = base64.b32decode(secret + "=" * (-len(secret) % 8), casefold=True)
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    off = mac[-1] & 0x0F
    return str((struct.unpack(">I", mac[off:off + 4])[0] & 0x7FFFFFFF) % 10**digits).zfill(digits)


def otpauth_uri(secret: str, user: str, issuer: str = "REV Games Console") -> str:
    from urllib.parse import quote

    return f"otpauth://totp/{quote(issuer)}:{quote(user)}?secret={secret}&issuer={quote(issuer)}&digits=6&period=30"


def check_totp(db: DB, secret: str, code: str, now: float | None = None) -> bool:
    """Accepts the current code and one step either side. Each code works once, ever."""
    code = (code or "").strip().replace(" ", "")
    if not secret or not code.isdigit() or len(code) != 6:
        return False
    now = now if now is not None else time.time()
    counter = int(now // 30)
    last = int(db.get("totp_last", "0"))
    hit = None
    for c in (counter - 1, counter, counter + 1):
        if hmac.compare_digest(totp_at(secret, c), code):
            hit = c
    if hit is None or hit <= last:
        return False
    db.put("totp_last", str(hit))
    return True


# ------------------------------------------------------------- lockout / sessions

class Guard:
    def __init__(self, db: DB, cfg):
        self.db, self.cfg = db, cfg

    def locked(self, *keys: str) -> bool:
        since = time.time() - self.cfg.login_lock_minutes * 60
        return any(self.db.q("SELECT COUNT(*) n FROM fails WHERE key=? AND at>?", (k, since))[0]["n"] >= self.cfg.login_max_fails for k in keys)

    def fail(self, *keys: str) -> None:
        for k in keys:
            self.db.x("INSERT INTO fails(key,at) VALUES(?,?)", (k, time.time()))
        self.db.x("DELETE FROM fails WHERE at<?", (time.time() - 86400,))

    def clear(self, *keys: str) -> None:
        for k in keys:
            self.db.x("DELETE FROM fails WHERE key=?", (k,))

    def start_session(self, user: str, ip: str) -> tuple[str, str]:
        token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(24)
        now = time.time()
        self.db.x("INSERT INTO sessions VALUES(?,?,?,?,?,?)", (hashlib.sha256(token.encode()).hexdigest(), user, csrf, now, now, ip))
        return token, csrf

    def session(self, token: str) -> dict | None:
        if not token:
            return None
        h, now = hashlib.sha256(token.encode()).hexdigest(), time.time()
        rows = self.db.q("SELECT * FROM sessions WHERE token_hash=?", (h,))
        if not rows:
            return None
        s = rows[0]
        if now - s["last_seen"] > self.cfg.idle_minutes * 60 or now - s["created"] > self.cfg.max_hours * 3600:
            self.db.x("DELETE FROM sessions WHERE token_hash=?", (h,))
            return None
        self.db.x("UPDATE sessions SET last_seen=? WHERE token_hash=?", (now, h))
        return dict(s)

    def end_session(self, token: str) -> None:
        self.db.x("DELETE FROM sessions WHERE token_hash=?", (hashlib.sha256(token.encode()).hexdigest(),))

    def end_all(self) -> None:
        self.db.x("DELETE FROM sessions")
