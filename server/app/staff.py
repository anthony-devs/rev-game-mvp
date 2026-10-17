"""Staff accounts and sign-in.

Two kinds of staff:

* **admin**   one account, defined by ``ADMIN_USERNAME`` + ``ADMIN_PASSWORD`` (or
              ``ADMIN_PASSWORD_HASH``) in the server's environment. It is never stored in the
              database and it can't be edited from the web. After signing in the admin still has
              to "connect" to the dashboard with ``ADMIN_KEY``.
* **agent**   customer service reps. Only the admin can create or edit them.

Passwords are stored as scrypt hashes. Sessions are signed tokens that expire, and are
refused the moment an account is switched off or its password changes. Repeated wrong
passwords lock the username (from that IP) for a while.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import logging
import os
import re
import secrets
from datetime import timedelta
from functools import wraps
from pathlib import Path

from flask import Blueprint, Response, g, jsonify, request
from itsdangerous import BadSignature, URLSafeSerializer

from .config import Config
from .errors import ApiError, bad_request
from .store import Store, Txn
from .util import Clock, as_utc, utcnow

log = logging.getLogger("staff")
UI_DIR = Path(__file__).parent / "staff_ui"

RESERVED = {
    "admin", "rev-admin", "revadmin", "rev_admin", "administrator", "root", "superuser", "owner",
    "support", "staff", "system", "moderator", "mod", "rev", "revgames", "rev-games", "customer-service",
    "customerservice", "cs", "agent", "test", "demo",
}
USERNAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{3,31}$")
COMMON_PASSWORDS = {"password", "passw0rd", "letmein", "welcome", "qwerty", "123456", "iloveyou", "changeme", "revgames"}
HOME = {"admin": "/admin", "agent": "/support"}


# ------------------------------------------------------------------ passwords

def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    n, r, p = 2**14, 8, 1
    digest = hashlib.scrypt(password.encode(), salt=salt, n=n, r=r, p=p, dklen=32)
    return "scrypt${}${}${}${}${}".format(n, r, p, base64.b64encode(salt).decode(), base64.b64encode(digest).decode())


def verify_password(password: str, stored: str) -> bool:
    try:
        scheme, n, r, p, salt, digest = stored.split("$")
        if scheme != "scrypt":
            return False
        want = base64.b64decode(digest)
        got = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p), dklen=len(want))
        return hmac.compare_digest(got, want)
    except Exception:
        return False


_DUMMY = hash_password("not-a-real-password")  # burned on unknown usernames so timing doesn't leak who exists


def password_problems(password: str, username: str = "") -> list[str]:
    out = []
    if not isinstance(password, str) or len(password) < 12:
        out.append("at least 12 characters")
    if isinstance(password, str):
        if len(password) > 128:
            out.append("at most 128 characters")
        if not re.search(r"[a-z]", password):
            out.append("a lowercase letter")
        if not re.search(r"[A-Z]", password):
            out.append("an uppercase letter")
        if not re.search(r"\d", password):
            out.append("a number")
        if not re.search(r"[^A-Za-z0-9]", password):
            out.append("a symbol")
        low = password.lower()
        if username and username.lower() in low:
            out.append("no part of the username")
        if any(c in low for c in COMMON_PASSWORDS):
            out.append("nothing easy to guess")
    return out


def check_password(password: str, username: str = "") -> None:
    problems = password_problems(password, username)
    if problems:
        raise bad_request("weak_password", "Password needs " + ", ".join(problems) + ".")


def username_problem(username: str) -> str | None:
    if not isinstance(username, str) or not USERNAME_RE.match(username):
        return "Use 4 to 32 lowercase letters, numbers, dots, dashes or underscores."
    if username in RESERVED:
        return "That username is reserved."
    return None


def _dev_secret() -> str:
    """No SESSION_SECRET set. Locally, keep a generated one in data/.session_secret so a
    restart (or the Flask reloader) doesn't sign everyone out. On Cloud Run there is no
    writable home for it, so use a throwaway one and warn."""
    path = Path(__file__).resolve().parents[1] / "data" / ".session_secret"
    try:
        if path.exists():
            saved = path.read_text().strip()
            if len(saved) >= 32:
                return saved
        if not os.environ.get("K_SERVICE"):
            path.parent.mkdir(parents=True, exist_ok=True)
            fresh = secrets.token_urlsafe(32)
            path.write_text(fresh)
            try:
                path.chmod(0o600)
            except OSError:
                pass
            log.info("SESSION_SECRET is not set: saved a local one to %s", path)
            return fresh
    except OSError:
        pass
    log.warning("SESSION_SECRET is not set: staff sessions will end whenever the server restarts.")
    return secrets.token_urlsafe(32)


# --------------------------------------------------------------------- service

class StaffService:
    def __init__(self, store: Store, cfg: Config, clock: Clock = utcnow):
        self.store, self.cfg, self.clock = store, cfg, clock
        secret = cfg.session_secret
        if not secret:
            secret = _dev_secret()
        self._signer = URLSafeSerializer(secret, salt="rev-staff-session")
        self.admin_username = ""
        self._admin_hash = ""
        self.admin_problem: str | None = None
        self._setup_admin()

    # -- the admin account lives in the environment
    def _setup_admin(self) -> None:
        cfg = self.cfg
        if not cfg.admin_username and not cfg.admin_password and not cfg.admin_password_hash:
            self.admin_problem = "ADMIN_USERNAME / ADMIN_PASSWORD are not set."
            return
        name = cfg.admin_username.strip().lower()
        bad = username_problem(name)
        if bad:
            self.admin_problem = f"ADMIN_USERNAME is not allowed: {bad}"
        elif len(name) < 6:
            self.admin_problem = "ADMIN_USERNAME must be at least 6 characters."
        elif cfg.admin_password_hash:
            if not cfg.admin_password_hash.startswith("scrypt$"):
                self.admin_problem = "ADMIN_PASSWORD_HASH is not a hash made by manage.py."
            else:
                self._admin_hash = cfg.admin_password_hash
        elif cfg.admin_password:
            problems = password_problems(cfg.admin_password, name)
            if problems:
                self.admin_problem = "ADMIN_PASSWORD needs " + ", ".join(problems) + "."
            else:
                self._admin_hash = hash_password(cfg.admin_password)
        else:
            self.admin_problem = "Set ADMIN_PASSWORD or ADMIN_PASSWORD_HASH."
        if self.admin_problem:
            log.error("Admin login is OFF. %s", self.admin_problem)
        else:
            self.admin_username = name

    @property
    def admin_enabled(self) -> bool:
        return bool(self._admin_hash)

    # -- accounts
    def _agent(self, username: str) -> dict | None:
        return self.store.read(f"staff/{username}")

    def get(self, username: str) -> dict | None:
        username = (username or "").strip().lower()
        if self.admin_enabled and username == self.admin_username:
            return {"username": username, "name": "Administrator", "role": "admin", "active": True, "ver": 0, "mustChange": False}
        doc = self._agent(username)
        return {**doc, "role": "agent"} if doc else None

    def list_agents(self) -> list[dict]:
        rows = [d for _i, d in self.store.list("staff", 500)]
        rows.sort(key=lambda d: d["username"])
        return [self.public(d) for d in rows]

    @staticmethod
    def public(d: dict) -> dict:
        def iso(v):
            v = as_utc(v)
            return v.isoformat() if v else None

        return {
            "username": d["username"],
            "name": d.get("name", ""),
            "role": d.get("role", "agent"),
            "active": bool(d.get("active", True)),
            "mustChange": bool(d.get("mustChange")),
            "createdAt": iso(d.get("createdAt")),
            "createdBy": d.get("createdBy"),
            "lastLoginAt": iso(d.get("lastLoginAt")),
        }

    def create_agent(self, username: str, name: str, password: str, *, actor: str) -> dict:
        username = (username or "").strip().lower()
        bad = username_problem(username)
        if bad:
            raise bad_request("invalid_username", bad)
        if self.admin_enabled and username == self.admin_username:
            raise bad_request("invalid_username", "That username is reserved.")
        name = (name or "").strip()
        if not (2 <= len(name) <= 60):
            raise bad_request("invalid_name", "Give the rep's name (2 to 60 characters).")
        check_password(password, username)
        doc = {
            "username": username,
            "name": name,
            "role": "agent",
            "active": True,
            "mustChange": True,
            "ver": 1,
            "passwordHash": hash_password(password),
            "createdAt": self.clock(),
            "createdBy": actor,
            "lastLoginAt": None,
        }

        def fn(txn: Txn):
            if txn.get(f"staff/{username}") is not None:
                raise ApiError(409, "username_taken", "That username is already used.")
            txn.set(f"staff/{username}", doc)

        self.store.run(fn)
        return self.public(doc)

    def update_agent(self, username: str, *, name=None, active=None, password=None) -> dict:
        username = (username or "").strip().lower()

        def fn(txn: Txn):
            doc = txn.get(f"staff/{username}")
            if doc is None:
                raise ApiError(404, "staff_not_found", "No rep with that username.")
            if name is not None:
                n = str(name).strip()
                if not (2 <= len(n) <= 60):
                    raise bad_request("invalid_name", "Give the rep's name (2 to 60 characters).")
                doc["name"] = n
            if active is not None:
                if bool(active) != doc.get("active", True):
                    doc["ver"] = int(doc.get("ver", 1)) + 1  # signs them out everywhere
                doc["active"] = bool(active)
            if password is not None:
                check_password(password, username)
                doc["passwordHash"] = hash_password(password)
                doc["mustChange"] = True
                doc["ver"] = int(doc.get("ver", 1)) + 1
            txn.set(f"staff/{username}", doc)
            return doc

        return self.public(self.store.run(fn))

    def change_own_password(self, username: str, current: str, new: str) -> str:
        """Returns a fresh session token (the old ones stop working)."""
        doc = self._agent(username)
        if doc is None:
            raise ApiError(400, "managed_by_environment", "This account's password is set on the server.")
        if not verify_password(current or "", doc["passwordHash"]):
            raise ApiError(403, "wrong_password", "Your current password is wrong.")
        check_password(new, username)
        if verify_password(new, doc["passwordHash"]):
            raise bad_request("same_password", "Pick a different password.")

        def fn(txn: Txn):
            d = txn.get(f"staff/{username}")
            if d is None or d.get("passwordHash") != doc["passwordHash"]:
                # Two changes raced (a double click, two tabs): the first one wins, never both.
                raise ApiError(409, "password_just_changed", "Your password was just changed. Sign in again with the new one.")
            d["passwordHash"] = hash_password(new)
            d["mustChange"] = False
            d["ver"] = int(d.get("ver", 1)) + 1
            txn.set(f"staff/{username}", d)
            return d

        d = self.store.run(fn)
        return self._token(d)

    # -- sessions
    def _token(self, acct: dict) -> str:
        exp = self.clock().timestamp() + self.cfg.session_hours * 3600
        return self._signer.dumps({"u": acct["username"], "r": acct["role"], "v": acct.get("ver", 0), "e": exp})

    def session(self, token: str) -> dict:
        try:
            p = self._signer.loads(token)
            acct = self.get(p["u"])
            if acct is None or not acct.get("active", True) or acct.get("ver", 0) != p["v"] or acct["role"] != p["r"]:
                raise ValueError
            if self.clock().timestamp() > p["e"]:
                raise ValueError
        except (BadSignature, ValueError, KeyError, TypeError):
            raise ApiError(401, "staff_unauthenticated", "Sign in again.")
        return acct

    # -- sign-in with lock-out
    def _throttle_key(self, username: str, ip: str) -> str:
        return "staff_login/" + hashlib.sha256(f"{username}|{ip}".encode()).hexdigest()[:40]

    def login(self, username: str, password: str, ip: str = "") -> dict:
        username = (username or "").strip().lower()
        password = password if isinstance(password, str) else ""
        key = self._throttle_key(username, ip)
        now = self.clock()
        rec = self.store.read(key) or {}
        locked = as_utc(rec.get("lockedUntil"))
        if locked and locked > now:
            mins = max(1, int((locked - now).total_seconds() // 60) + 1)
            raise ApiError(429, "login_locked", f"Too many wrong attempts. Try again in {mins} minute(s).")

        acct = self.get(username)
        stored = None
        if acct is not None and acct.get("active", True):
            stored = self._admin_hash if acct["role"] == "admin" else acct.get("passwordHash")
        ok = verify_password(password, stored or _DUMMY) and stored is not None

        if not ok:
            first = as_utc(rec.get("firstAt"))
            if first is None or first + self._window() < now:
                fails, first = 1, now
            else:
                fails = int(rec.get("fails", 0)) + 1
            new = {"fails": fails, "firstAt": first, "lockedUntil": None}
            if fails >= self.cfg.login_max_fails:
                new = {"fails": 0, "firstAt": None, "lockedUntil": now + self._window_lock()}
            self.store.run(lambda txn: txn.set(key, new))
            raise ApiError(401, "bad_credentials", "Wrong username or password.")

        self.store.run(lambda txn: txn.set(key, {"fails": 0, "firstAt": None, "lockedUntil": None}))
        if acct["role"] == "agent":
            self.store.run(lambda txn: txn.set(f"staff/{username}", {**txn.get(f"staff/{username}"), "lastLoginAt": now}))
        return {
            "token": self._token(acct),
            "username": acct["username"],
            "name": acct.get("name", ""),
            "role": acct["role"],
            "mustChangePassword": bool(acct.get("mustChange")),
            "redirect": HOME[acct["role"]],
            "expiresInHours": self.cfg.session_hours,
        }

    def _window(self):
        return timedelta(minutes=self.cfg.login_lock_minutes)

    _window_lock = _window

    # -- request guard
    def require(self, *roles: str):
        """Decorator: the caller must hold a valid staff session with one of ``roles``."""

        def deco(view):
            @wraps(view)
            def wrapper(*args, **kwargs):
                header = request.headers.get("Authorization", "")
                if not header.startswith("Bearer "):
                    raise ApiError(401, "staff_unauthenticated", "Sign in to continue.")
                acct = self.session(header[7:].strip())
                if acct["role"] not in roles:
                    raise ApiError(403, "wrong_role", "This account can't open that.")
                g.staff = acct
                return view(*args, **kwargs)

            return wrapper

        return deco


# ------------------------------------------------------------------- blueprint

PAGE_HEADERS = {
    "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; "
    "img-src 'self' blob: data:; media-src 'self' blob:; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "no-store",
}


def html_page(path: Path) -> Response:
    resp = Response(path.read_text(encoding="utf-8"), mimetype="text/html")
    resp.headers.update(PAGE_HEADERS)
    return resp


def client_ip() -> str:
    fwd = request.headers.get("X-Forwarded-For", "")
    return (fwd.split(",")[0].strip() if fwd else request.remote_addr) or ""


def make_staff(staff: StaffService) -> Blueprint:
    bp = Blueprint("staff", __name__)

    @bp.get("/staff")
    def login_page():
        return html_page(UI_DIR / "login.html")

    @bp.post("/staff/api/login")
    def login():
        d = request.get_json(silent=True)
        if not isinstance(d, dict):
            raise bad_request("invalid_body", "Send a JSON object.")
        return jsonify(staff.login(d.get("username"), d.get("password"), client_ip()))

    @bp.get("/staff/api/me")
    @staff.require("admin", "agent")
    def me():
        a = g.staff
        return jsonify({"username": a["username"], "name": a.get("name", ""), "role": a["role"], "mustChangePassword": bool(a.get("mustChange")), "redirect": HOME[a["role"]]})

    @bp.post("/staff/api/password")
    @staff.require("agent")
    def password():
        d = request.get_json(silent=True) or {}
        token = staff.change_own_password(g.staff["username"], d.get("current"), d.get("new"))
        return jsonify({"token": token})

    return bp
