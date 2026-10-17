"""REV Games developer console.

A separate program from the game server, on purpose: it has to keep working, and keep
recording, when the server is down. It reaches servers only through signed calls to
/internal/dev/* and plain health checks, and keeps its own history in a local SQLite file.
"""
from __future__ import annotations

import hmac
import json
import logging
import time
from functools import wraps
from pathlib import Path
from urllib.parse import urlparse

from flask import Flask, Response, abort, g, jsonify, request, send_from_directory

from . import serverapi
from .actions import ActionError, Runner, load_actions
from .config import Config, Target
from .db import DB
from .guard import RequestGuard, request_key
from .monitor import Monitor
from .security import Guard, check_totp, verify_password
from .smoke import run_smoke

UI = Path(__file__).parent / "ui"
COOKIE = "dc_session"
# A password check is slow on purpose; this keeps the time the same whether or not the user exists.
_DUMMY = "scrypt$16384$8$1$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


def create_app(cfg: Config | None = None, db: DB | None = None, runner: Runner | None = None, monitor: Monitor | None = None) -> Flask:
    cfg = cfg or Config().with_targets()
    db = db or DB(cfg.db_path)
    guard = Guard(db, cfg)
    runner = runner or Runner(db, cfg, load_actions(cfg.actions_file))
    monitor = monitor or Monitor(db, cfg)
    targets = {t.name: t for t in cfg.targets}
    app = Flask(__name__, static_folder=None)
    app.config["MAX_CONTENT_LENGTH"] = 64 * 1024
    app.extensions.update(db=db, guard=guard, runner=runner, monitor=monitor, cfg=cfg)
    if cfg.run_monitor and cfg.targets:
        monitor.start()

    def ip() -> str:
        if cfg.trust_proxy:
            parts = [p.strip() for p in request.headers.get("X-Forwarded-For", "").split(",") if p.strip()]
            if len(parts) >= cfg.trust_proxy:
                return parts[-cfg.trust_proxy]  # the address our own proxy saw, not one the client wrote
        return request.remote_addr or ""

    # ---------------------------------------------------------------- hardening

    dup_guard = RequestGuard()

    @app.before_request
    def _no_duplicates():
        # The same action sent twice (a slow answer, a double click) runs once.
        if request.method != "POST" or not request.path.startswith("/api/"):
            return None
        who = request.cookies.get(COOKIE, "") or request.remote_addr or ""
        key = request_key(who, request.method, request.path, request.content_type or "", request.content_length, request.get_data(cache=True))
        if not dup_guard.enter(key, 1.5):
            return jsonify({"error": "That is already being processed. Please wait a moment."}), 409
        g._dup_key = key
        return None

    @app.teardown_request
    def _release_duplicate(exc):
        key = g.pop("_dup_key", None)
        if key is not None:
            dup_guard.leave(key, exc is None and getattr(g, "_dup_status", 500) < 400)

    @app.before_request
    def _gate():
        if cfg.allowed_ips and ip() not in cfg.allowed_ips:
            abort(404)  # don't even admit there is something here
        if request.method not in ("GET", "HEAD", "OPTIONS"):
            origin = request.headers.get("Origin")
            if origin and urlparse(origin).netloc != request.host:
                abort(403)

    @app.after_request
    def _headers(resp):
        g._dup_status = resp.status_code
        resp.headers["Content-Security-Policy"] = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["X-Frame-Options"] = "DENY"
        resp.headers["Referrer-Policy"] = "no-referrer"
        resp.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        resp.headers["Cross-Origin-Opener-Policy"] = "same-origin"
        if cfg.cookie_secure:
            resp.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
        if request.path.startswith("/api/"):
            resp.headers["Cache-Control"] = "no-store"
        return resp

    def fail(status: int, msg: str):
        r = jsonify({"error": msg})
        r.status_code = status
        return r

    def body() -> dict:
        d = request.get_json(silent=True)
        return d if isinstance(d, dict) else {}

    def authed(view=None, *, write=False, stepup=False):
        """Signed in. ``write`` also needs the CSRF token; ``stepup`` also needs a fresh authenticator code."""

        def deco(v):
            @wraps(v)
            def wrapper(*a, **kw):
                s = guard.session(request.cookies.get(COOKIE, ""))
                if s is None:
                    return fail(401, "Sign in required.")
                g.user, g.session = s["user"], s
                if write:
                    given = request.headers.get("X-CSRF", "")
                    if not hmac.compare_digest(given, s["csrf"]):
                        return fail(403, "Page expired. Reload.")
                if stepup:
                    if not check_totp(db, cfg.totp_secret, str(body().get("totp") or "")):
                        db.audit(g.user, ip(), "stepup_failed", request.path)
                        return fail(403, "Enter a NEW code from your authenticator app (each code works once).")
                return v(*a, **kw)

            return wrapper

        return deco(view) if view else deco

    def target_or_404(name: str) -> Target:
        t = targets.get(name)
        if t is None:
            abort(404)
        return t

    # ------------------------------------------------------------------- pages

    @app.get("/")
    def index():
        return send_from_directory(UI, "index.html")

    @app.get("/static/<path:name>")
    def static_files(name):
        if name not in ("app.js", "app.css"):
            abort(404)
        return send_from_directory(UI, name)

    @app.get("/healthz")
    def healthz():
        return {"ok": True}

    # -------------------------------------------------------------------- login

    @app.post("/api/login")
    def login():
        d = body()
        user, who = str(d.get("username") or "")[:80], ip()
        ukey, ikey = f"u:{user.lower()}", f"ip:{who}"
        if not cfg.user or not cfg.password_hash or not cfg.totp_secret:
            return fail(503, "Console is not set up. Run: python manage.py setup")
        if guard.locked(ukey, ikey):
            db.audit(user, who, "login_locked")
            return fail(429, f"Too many attempts. Try again in {cfg.login_lock_minutes} minutes.")
        pw_ok = verify_password(str(d.get("password") or ""), cfg.password_hash if hmac.compare_digest(user.lower().encode(), cfg.user.lower().encode()) else _DUMMY)
        totp_ok = check_totp(db, cfg.totp_secret, str(d.get("totp") or "")) if pw_ok and user.lower() == cfg.user.lower() else False
        if not (pw_ok and totp_ok and user.lower() == cfg.user.lower()):
            guard.fail(ukey, ikey)
            db.audit(user, who, "login_failed")
            time.sleep(0.4)
            return fail(401, "Wrong username, password or code.")  # never says which one
        guard.clear(ukey, ikey)
        token, csrf = guard.start_session(cfg.user, who)
        db.audit(cfg.user, who, "login")
        r = jsonify({"user": cfg.user, "csrf": csrf})
        r.set_cookie(COOKIE, token, httponly=True, secure=cfg.cookie_secure, samesite="Strict", max_age=cfg.max_hours * 3600, path="/")
        return r

    @app.post("/api/logout")
    @authed(write=True)
    def logout():
        guard.end_session(request.cookies.get(COOKIE, ""))
        db.audit(g.user, ip(), "logout")
        r = jsonify({"ok": True})
        r.delete_cookie(COOKIE, path="/")
        return r

    @app.post("/api/logout-everywhere")
    @authed(write=True, stepup=True)
    def logout_all():
        guard.end_all()
        db.audit(g.user, ip(), "logout_everywhere")
        return jsonify({"ok": True})

    @app.get("/api/session")
    @authed
    def session():
        return jsonify({"user": g.user, "csrf": g.session["csrf"], "targets": [t.name for t in cfg.targets]})

    # ---------------------------------------------------------------- monitoring

    @app.get("/api/overview")
    @authed
    def overview():
        return jsonify({"targets": [monitor.summary(t) for t in cfg.targets], "now": time.time(),
                        "incidents": [dict(r) for r in db.q("SELECT * FROM incidents ORDER BY started DESC LIMIT 15")]})

    @app.post("/api/targets/<name>/probe")
    @authed(write=True)
    def probe_now(name):
        t = target_or_404(name)
        monitor.probe(t, deep=True)
        return jsonify(monitor.summary(t))

    @app.get("/api/targets/<name>/history")
    @authed
    def history(name):
        t = target_or_404(name)
        hours = max(1, min(request.args.get("hours", 6, type=int), 168))
        rows = db.q("SELECT at, ok, ms FROM probes WHERE target=? AND at>? ORDER BY at", (t.name, time.time() - hours * 3600))
        step = max(1, len(rows) // 240)
        return jsonify({"points": [{"at": r["at"], "ok": bool(r["ok"]), "ms": r["ms"]} for r in rows[::step]]})

    @app.get("/api/targets/<name>/errors")
    @authed
    def errors(name):
        r = serverapi.signed(target_or_404(name), "GET", "/internal/dev/errors")
        return jsonify(r.data) if r.ok else fail(502, r.error or f"Server said HTTP {r.status}")

    @app.get("/api/targets/<name>/crashes")
    @authed
    def crashes(name):
        r = serverapi.signed(target_or_404(name), "GET", "/internal/dev/crashes")
        return jsonify(r.data) if r.ok else fail(502, r.error or f"Server said HTTP {r.status}")

    @app.post("/api/targets/<name>/smoke")
    @authed(write=True)
    def smoke(name):
        t = target_or_404(name)
        res = run_smoke(t)
        db.x("INSERT INTO tests(target,at,passed,failed,results) VALUES(?,?,?,?,?)", (t.name, res["at"], res["passed"], res["failed"], json.dumps(res["results"])))
        db.audit(g.user, ip(), "smoke", {"target": t.name, "passed": res["passed"], "failed": res["failed"]})
        return jsonify(res)

    @app.get("/api/targets/<name>/smoke")
    @authed
    def last_smoke(name):
        r = db.q("SELECT * FROM tests WHERE target=? ORDER BY id DESC LIMIT 1", (target_or_404(name).name,))
        return jsonify({"target": name, "at": r[0]["at"], "passed": r[0]["passed"], "failed": r[0]["failed"], "results": json.loads(r[0]["results"])} if r else {})

    # ----------------------------------------------------------- server controls

    @app.post("/api/targets/<name>/maintenance")
    @authed(write=True, stepup=True)
    def maintenance(name):
        t, d = target_or_404(name), body()
        if str(d.get("confirm") or "").upper() != ("PAUSE" if d.get("on") else "RESUME"):
            return fail(400, "Type PAUSE (or RESUME) to confirm.")
        r = serverapi.signed(t, "POST", "/internal/dev/maintenance", {"on": bool(d.get("on")), "scope": "live" if d.get("scope") == "live" else "all", "message": str(d.get("message") or "")[:200], "by": g.user})
        db.audit(g.user, ip(), "maintenance", {"target": t.name, "on": bool(d.get("on")), "scope": d.get("scope"), "status": r.status})
        return jsonify(r.data) if r.ok else fail(502, r.error or f"Server said HTTP {r.status}")

    @app.get("/api/targets/<name>/migrations")
    @authed
    def migrations(name):
        r = serverapi.signed(target_or_404(name), "GET", "/internal/dev/migrations")
        return jsonify(r.data) if r.ok else fail(502, r.error or f"Server said HTTP {r.status}")

    @app.post("/api/targets/<name>/migrations")
    @authed(write=True, stepup=True)
    def migrations_run(name):
        t, d = target_or_404(name), body()
        apply = bool(d.get("apply"))
        if apply and str(d.get("confirm") or "").upper() != "MIGRATE":
            return fail(400, "Type MIGRATE to apply.")
        r = serverapi.signed(t, "POST", "/internal/dev/migrations/run", {"apply": apply, "by": g.user}, timeout=300)
        db.audit(g.user, ip(), "migrate_apply" if apply else "migrate_dry_run", {"target": t.name, "status": r.status})
        return jsonify(r.data) if r.ok else fail(502, r.error or f"Server said HTTP {r.status}")

    # ------------------------------------------------------------------ actions

    @app.get("/api/actions")
    @authed
    def actions():
        return jsonify({"actions": runner.catalog(), "runs": runner.recent()})

    @app.post("/api/actions/<aid>/run")
    @authed(write=True, stepup=True)
    def run_action(aid):
        d = body()
        a = next((x for x in runner.catalog() if x["id"] == aid), None)
        if a is None:
            return fail(404, "No such action.")
        if str(d.get("confirm") or "") != a["confirm"]:
            return fail(400, f"Type {a['confirm']} to confirm.")
        t = targets.get(str(d.get("target") or "")) if d.get("target") else None
        if (a["pre"] or a["post"]) and t is None:
            return fail(400, "Pick a target server for this action.")
        try:
            rid = runner.start(aid, t, d.get("params") if isinstance(d.get("params"), dict) else {}, g.user)
        except ActionError as e:
            return fail(400, str(e))
        db.audit(g.user, ip(), "action_start", {"action": aid, "run": rid, "target": t.name if t else None, "params": d.get("params")})
        return jsonify({"run": rid}), 202

    @app.get("/api/runs/<rid>")
    @authed
    def run_status(rid):
        r = runner.get(rid)
        return jsonify(r) if r else fail(404, "No such run.")

    @app.get("/api/audit")
    @authed
    def audit():
        rows = [dict(r) for r in db.q("SELECT at, actor, ip, action, detail FROM audit ORDER BY id DESC LIMIT 100")]
        return jsonify({"rows": rows, "chainIntact": db.audit_ok()})

    return app
