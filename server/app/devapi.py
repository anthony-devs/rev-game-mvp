"""The server's side of the developer console. Nothing else may call it.

Every request must be signed with ``DEV_API_SECRET`` (HMAC-SHA256 over the method, path, a
timestamp, a one-time nonce and the body). Unsigned, stale, replayed or wrongly signed requests
get a plain 401, and the whole thing is switched off (404) unless a 32+ character secret is set.
Optionally limit it to ``DEV_ALLOWED_IPS``.

It exposes health numbers, recent errors and crash groups, maintenance mode, database checks and
migrations. It never returns secrets, tokens or player money details.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import platform
import sys
import time
from collections import OrderedDict, deque

from flask import Blueprint, current_app, jsonify, request

from .errors import ApiError, bad_request
from .util import is_quota

WINDOW_SECONDS = 60
PREFIX = "/internal/dev"


def sign(secret: str, method: str, path_qs: str, ts: str, nonce: str, body: bytes) -> str:
    msg = "\n".join([method.upper(), path_qs, ts, nonce, hashlib.sha256(body).hexdigest()])
    return hmac.new(secret.encode(), msg.encode(), hashlib.sha256).hexdigest()


def make_devapi(store, cfg, metrics, flags, migrator, insights, services: dict) -> Blueprint:
    bp = Blueprint("devapi", __name__)
    nonces: OrderedDict = OrderedDict()
    fails: dict[str, deque] = {}

    def client_ip() -> str:
        return request.remote_addr or ""

    def guard():
        if len(cfg.dev_api_secret) < 32:
            raise ApiError(404, "not_found", "Not found.")
        ip = client_ip()
        q = fails.setdefault(ip, deque())
        now = time.monotonic()
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= 20:
            raise ApiError(429, "slow_down", "Too many bad requests.")

        def deny(why: str):
            q.append(now)
            current_app.logger.warning("dev api refused (%s) from %s %s", why, ip, request.path)
            raise ApiError(401, "unauthorized", "Not allowed.")

        allowed = [x.strip() for x in cfg.dev_allowed_ips.split(",") if x.strip()]
        if allowed and ip not in allowed:
            deny("ip")
        ts, nonce, sig = request.headers.get("X-Dev-Time", ""), request.headers.get("X-Dev-Nonce", ""), request.headers.get("X-Dev-Sig", "")
        if not ts.isdigit() or abs(time.time() - int(ts)) > WINDOW_SECONDS or not (16 <= len(nonce) <= 64):
            deny("stale")
        path_qs = request.path + ("?" + request.query_string.decode() if request.query_string else "")
        want = sign(cfg.dev_api_secret, request.method, path_qs, ts, nonce, request.get_data())
        if not hmac.compare_digest(want, sig):
            deny("signature")
        if nonce in nonces:
            deny("replay")
        nonces[nonce] = now
        while len(nonces) > 5000 or (nonces and now - next(iter(nonces.values())) > WINDOW_SECONDS * 2):
            nonces.popitem(last=False)

    @bp.before_request
    def _guard():
        if request.path.startswith(PREFIX):
            guard()

    def body() -> dict:
        d = request.get_json(silent=True)
        if not isinstance(d, dict):
            raise bad_request("invalid_body", "Send a JSON object.")
        return d

    def listeners() -> dict:
        out = {}
        for name, w in (("users", services.get("users_watch")), ("payments", getattr(services.get("live"), "_payments_watch", None)),
                        ("moderation", getattr(services.get("standing"), "_log_watch", None)), ("crashes", insights.crash_watch),
                        ("flags", flags._watch), ("campaigns", services.get("campaigns"))):
            if w is None:
                continue
            unsub = getattr(w, "_unsub", None)
            out[name] = {"kind": type(w).__name__, "active": bool(getattr(unsub, "is_active", True)) if unsub is not None else (type(w).__name__ == "WatchedList"),
                         "rows": len(getattr(w, "_rows", None) or [])}
        return out

    @bp.get(PREFIX + "/diag")
    def diag():
        m = metrics.snapshot(300)
        k_service = os.environ.get("K_SERVICE")
        checks = {
            "adminKeySet": bool(cfg.admin_key), "adminKeyStrong": len(cfg.admin_key) >= 16,
            "sessionSecretStrong": len(cfg.session_secret) >= 32, "adminPasswordHashed": bool(cfg.admin_password_hash) or not cfg.admin_password,
            "paymentsMode": cfg.payments_mode, "mockPaymentsInCloud": bool(k_service) and cfg.payments_mode == "mock" and not cfg.allow_mock_in_cloud,
            "liveEnabled": cfg.live_enabled, "emailMode": "smtp" if cfg.smtp_host else "mock",
            "devIpAllowlist": bool(cfg.dev_allowed_ips), "webhookSecretDefault": cfg.webhook_secret == "dev-webhook-secret",
        }
        mt = flags.maintenance()
        return jsonify({
            "service": k_service or "local", "revision": os.environ.get("K_REVISION"), "version": cfg.app_version, "python": platform.python_version(),
            "store": type(store).__name__, "metrics": m, "checks": checks, "listeners": listeners(),
            "maintenance": ({"on": True, "scope": mt.get("scope"), "message": mt.get("message"), "by": mt.get("by")} if mt else {"on": False}),
            "openCrashes": sum(1 for _ in insights.crashes("open")),
        })

    @bp.get(PREFIX + "/errors")
    def errors():
        return jsonify({"errors": [{**e, "at": e["at"]} for e in list(metrics.errors)[::-1]]})

    @bp.get(PREFIX + "/crashes")
    def crashes():
        return jsonify({"crashes": insights.crashes(request.args.get("status", ""))[:50]})

    @bp.get(PREFIX + "/db-check")
    def db_check():
        t0 = time.perf_counter()
        try:
            store.read("meta/ping")
            store.list("games", 1)
            return jsonify({"ok": True, "ms": round((time.perf_counter() - t0) * 1000, 1)})
        except Exception as e:
            return jsonify({"ok": False, "error": type(e).__name__, "message": str(e)[:200], "quota": is_quota(e)})

    @bp.post(PREFIX + "/selftest")
    def selftest():
        """Write, read and delete one scratch document: proves the database accepts writes."""
        t0 = time.perf_counter()
        try:
            token = os.urandom(6).hex()
            store.run(lambda txn: txn.set("meta/selftest", {"token": token, "at": time.time()}))
            ok = (store.read("meta/selftest") or {}).get("token") == token
            store.run(lambda txn: txn.delete("meta/selftest"))
            return jsonify({"ok": ok, "ms": round((time.perf_counter() - t0) * 1000, 1)})
        except Exception as e:
            return jsonify({"ok": False, "error": type(e).__name__, "message": str(e)[:200]})

    @bp.post(PREFIX + "/maintenance")
    def maintenance():
        d = body()
        doc = flags.set_maintenance(bool(d.get("on")), str(d.get("scope") or "all"), str(d.get("message") or ""), str(d.get("by") or "developer")[:40])
        return jsonify({"on": doc["on"], "scope": doc["scope"], "message": doc["message"], "shared": doc.get("shared", True)})

    @bp.get(PREFIX + "/migrations")
    def migrations_status():
        return jsonify({"migrations": migrator.status()})

    @bp.post(PREFIX + "/migrations/run")
    def migrations_run():
        d = body()
        return jsonify({"report": migrator.run(bool(d.get("apply")), str(d.get("by") or "developer")[:40])})

    @bp.post(PREFIX + "/flush")
    def flush():
        """Write buffered counters now (before a deploy) and drop the dashboards' caches."""
        try:
            metrics.flush()
        except Exception as e:
            return jsonify({"ok": False, "error": type(e).__name__})
        return jsonify({"ok": True})

    return bp
