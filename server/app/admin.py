"""Admin dashboard API and page.

Three locks, in this order:
    1. the admin signs in at ``/staff`` (username + password from the server's environment)
    2. the dashboard asks for ``ADMIN_KEY`` ("connect")
    3. every request carries both, and both are checked every time

With no ``ADMIN_KEY`` set the dashboard is switched off.
"""
from __future__ import annotations

import hmac
import time
from functools import wraps
from pathlib import Path

from flask import Blueprint, g, jsonify, request

from . import reasons
from .config import Config
from .errors import ApiError, bad_request
from .staff import StaffService, html_page
from .standing import TYPES, StandingService, _iso
from .store import Store
from .uploads import UploadService, file_response
from .util import as_utc

UI_DIR = Path(__file__).parent / "admin_ui"
MAX_BULK = 200


def make_admin(store: Store, standing: StandingService, cfg: Config, staff: StaffService, uploads: UploadService, live=None) -> Blueprint:
    bp = Blueprint("admin", __name__)
    session = staff.require("admin")

    def guarded(view):
        """Signed in as the admin AND connected with the admin key."""

        @wraps(view)
        @session
        def wrapper(*args, **kwargs):
            if not cfg.admin_key:
                raise ApiError(503, "admin_disabled", "Set ADMIN_KEY on the server to use the dashboard.")
            given = request.headers.get("X-Admin-Key", "")
            if not hmac.compare_digest(given.encode(), cfg.admin_key.encode()):
                raise ApiError(401, "bad_admin_key", "Wrong admin key.")
            g.actor = g.staff["username"]
            return view(*args, **kwargs)

        return wrapper

    # Every dashboard read is billed per document. Answers are kept for a short while and
    # dropped the moment staff change anything, so the page is never stale after an action.
    CACHE_SECONDS = 90  # 1.5 min; any staff action clears it sooner
    _cache: dict = {}
    users_watch = store.watch_list("users", 150, order_by="lastLoginAt")

    def cached(key, ttl: float, build):
        now = time.monotonic()
        hit = _cache.get(key)
        if hit is not None and now - hit[0] < ttl and request.args.get("fresh") != "1":
            return hit[1]
        value = build()
        _cache[key] = (now, value)
        if len(_cache) > 200:
            _cache.clear()
        return value

    @bp.after_request
    def _drop_cache_on_change(resp):
        if request.method not in ("GET", "HEAD", "OPTIONS"):
            _cache.clear()
        return resp

    def body() -> dict:
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            raise bad_request("invalid_body", "Send a JSON object.")
        return data

    def user_row(uid: str, doc: dict) -> dict:
        pub = standing.public(standing.summary(uid))
        return {
            "uid": uid,
            "displayName": doc.get("displayName"),
            "email": doc.get("email"),
            "isAnonymous": bool(doc.get("isAnonymous")),
            "lastLoginAt": _iso(doc.get("lastLoginAt")),
            "state": pub["state"],
            "blocksPlay": pub["blocksPlay"],
            "activeTypes": [a["type"] for a in pub["active"]],
        }

    @bp.get("/admin")
    def page():
        return html_page(UI_DIR / "index.html")

    @bp.get("/admin/payments")
    def payments_page():
        return html_page(Path(__file__).parent / "payments_ui" / "index.html")

    if live is not None:
        # ---- money: every payout is approved on its own, by name, with its reference typed in
        @bp.get("/admin/api/payments")
        @guarded
        def pay_list():
            kind, status = request.args.get("kind", ""), request.args.get("status", "")
            return jsonify(cached(("pay", kind, status), CACHE_SECONDS, lambda: {
                "payments": live.staff_list(kind, status),
                "currency": cfg.live_currency,
                "mock": cfg.payments_mode == "mock",
            }))

        @bp.get("/admin/api/payments/<pid>")
        @guarded
        def pay_one(pid: str):
            return jsonify(live.staff_detail(pid))

        @bp.post("/admin/api/payments/<pid>/approve")
        @guarded
        def pay_approve(pid: str):
            d = body()
            return jsonify(live.approve_payout(pid, g.actor, d.get("confirm"), str(d.get("note") or "")))

        @bp.post("/admin/api/payments/<pid>/reject")
        @guarded
        def pay_reject(pid: str):
            return jsonify(live.reject_payout(pid, g.actor, str(body().get("reason") or "")))

        @bp.post("/admin/api/payments/<pid>/retry")
        @guarded
        def pay_retry(pid: str):
            return jsonify(live.retry_payout(pid, g.actor))

        @bp.post("/admin/api/payments/<pid>/sync")
        @guarded
        def pay_sync(pid: str):
            return jsonify(live.sync_payout(pid, g.actor))

        @bp.post("/admin/api/payments/<pid>/verify")
        @guarded
        def pay_verify(pid: str):
            return jsonify(live.staff_verify_deposit(pid, g.actor))

    @bp.get("/admin/api/session")
    @session
    def whoami():
        """Step 1 check: am I signed in as the admin? (the key isn't needed yet)"""
        return jsonify({"username": g.staff["username"], "keyRequired": True, "dashboardEnabled": bool(cfg.admin_key)})

    @bp.get("/admin/api/ping")
    @guarded
    def ping():
        return jsonify(
            {
                "ok": True,
                "types": list(TYPES),
                "riskWindowDays": cfg.risk_window_days,
                "probationHours": cfg.probation_hours,
                "reasons": reasons.public_catalog(),
                "actor": g.actor,
            }
        )

    @bp.get("/admin/api/users")
    @guarded
    def users():
        q = (request.args.get("q") or "").strip().lower()

        # Kept current by a listener: no reads until a player document actually changes.
        everyone = [(as_utc(doc.get("lastLoginAt")), uid, doc) for uid, doc in users_watch.rows()]
        rows = []
        for t, uid, doc in everyone:
            hay = " ".join(str(x or "") for x in (uid, doc.get("email"), doc.get("displayName"))).lower()
            if not q or q in hay:
                rows.append((t, uid, doc))
        rows.sort(key=lambda r: r[0].timestamp() if r[0] else 0, reverse=True)
        return jsonify(cached(("users", q), CACHE_SECONDS, lambda: {"users": [user_row(uid, doc) for _t, uid, doc in rows[:50]]}))

    @bp.get("/admin/api/users/<uid>")
    @guarded
    def user(uid: str):
        days = request.args.get("days", type=int) or cfg.risk_window_days
        return jsonify(cached(("user", uid, days), CACHE_SECONDS, lambda: _user_detail(uid, days)))

    def _user_detail(uid: str, days: int):
        doc = store.read(f"users/{uid}")
        if doc is None:
            raise ApiError(404, "user_not_found", "No user with that id.")
        wallet = store.read_wallet(uid) or {}
        rounds = sorted(
            (d for _i, d in store.list(f"users/{uid}/rounds", 5, order_by="createdAt")),
            key=lambda d: as_utc(d["createdAt"]),
            reverse=True,
        )
        return (
            {
                "user": user_row(uid, doc),
                "balance": wallet.get("balance"),
                "standing": standing.public(standing.summary(uid)),
                "risk": standing.risk(uid, days),
                "actions": [standing.action_json(a) for a in standing.actions(uid)],
                "appeals": [standing.appeal_json(a) for a in standing.appeals(uid)],
                "recentRounds": [
                    {"game": r.get("game"), "bet": r.get("bet"), "net": r.get("net"), "at": _iso(r.get("createdAt"))} for r in rounds[:5]
                ],
            }
        )

    def resolve_user(token: str) -> str | None:
        """A uid, or an email address, to a uid that exists."""
        token = (token or "").strip()
        if not token:
            return None
        if store.read(f"users/{token}") is not None:
            return token
        low = token.lower()
        for uid, doc in store.list("users", 1000):
            if str(doc.get("email") or "").lower() == low:
                return uid
        return None

    def apply_one(uid: str, d: dict, label: str, message: str, is_custom: bool):
        return standing.apply(
            uid,
            d.get("type"),
            label,
            actor=g.actor,
            public_note=(d.get("publicNote") or "") if is_custom else message,
            internal_note=d.get("internalNote") or "",
            duration_hours=d.get("durationHours") or None,
            blocks_play=d.get("blocksPlay"),
            appeal_allowed=d.get("appealAllowed", True),
        )

    def pick_apply_reason(d: dict):
        if d.get("type") not in TYPES:
            raise bad_request("invalid_type", f"Type must be one of {', '.join(TYPES)}.")
        label, message, custom = reasons.resolve(reasons.APPLY[d["type"]], d.get("reasonCode"), d.get("customReason"))
        if not custom and (d.get("publicNote") or "").strip():
            raise bad_request("custom_text_not_allowed", 'Typing your own text is only allowed when you pick "Other".')
        return label, message, custom

    def pick_lift_reason(d: dict) -> str:
        label, message, _c = reasons.resolve(reasons.LIFT, d.get("reasonCode"), d.get("customReason"), field="reason for lifting")
        return label

    def hours_of(d: dict):
        h = d.get("probationHours")
        return float(h) if h not in (None, "") else None

    @bp.post("/admin/api/users/<uid>/actions")
    @guarded
    def create_action(uid: str):
        if store.read(f"users/{uid}") is None:
            raise ApiError(404, "user_not_found", "No user with that id.")
        d = body()
        label, message, custom = pick_apply_reason(d)
        return jsonify(standing.action_json(apply_one(uid, d, label, message, custom))), 201

    @bp.post("/admin/api/users/<uid>/actions/<action_id>/lift")
    @guarded
    def lift_action(uid: str, action_id: str):
        d = body()
        standing.lift(uid, action_id, actor=g.actor, note=pick_lift_reason(d), probation_hours=hours_of(d))
        return jsonify({"lifted": True})

    @bp.post("/admin/api/users/<uid>/appeals/<appeal_id>/decide")
    @guarded
    def decide(uid: str, appeal_id: str):
        d = body()
        decision = d.get("decision")
        if decision not in ("approve", "reject"):
            raise bad_request("invalid_decision", "Decision must be approve or reject.")
        items = reasons.APPEAL_APPROVE if decision == "approve" else reasons.APPEAL_REJECT
        _label, message, _c = reasons.resolve(items, d.get("reasonCode"), d.get("customReason"), field="response")
        out = standing.decide_appeal(uid, appeal_id, decision, message, actor=g.actor, probation_hours=hours_of(d))
        return jsonify(standing.appeal_json(out))

    @bp.post("/admin/api/bulk")
    @guarded
    def bulk():
        """Apply or lift the same action for many players. Each player succeeds or fails on its own."""
        d = body()
        op = d.get("op")
        tokens = d.get("players")
        if op not in ("apply", "lift"):
            raise bad_request("invalid_op", "op must be apply or lift.")
        if not isinstance(tokens, list) or not tokens or not all(isinstance(t, str) for t in tokens):
            raise bad_request("invalid_players", "Send a list of user ids or emails.")
        tokens = list(dict.fromkeys(t.strip() for t in tokens if t.strip()))
        if len(tokens) > MAX_BULK:
            raise bad_request("too_many_players", f"Up to {MAX_BULK} players at a time.")
        if op == "apply":
            label, message, custom = pick_apply_reason(d)
        else:
            if d.get("type") not in (None, "") and d["type"] not in TYPES:
                raise bad_request("invalid_type", f"Type must be one of {', '.join(TYPES)}.")
            lift_note = pick_lift_reason(d)
        results = []
        for token in tokens:
            uid = resolve_user(token)
            if uid is None:
                results.append({"player": token, "ok": False, "error": "No such player."})
                continue
            try:
                if op == "apply":
                    a = apply_one(uid, d, label, message, custom)
                    results.append({"player": token, "uid": uid, "ok": True, "actionId": a["id"]})
                else:
                    active = [e for e in standing.summary(uid).get("active", []) if not d.get("type") or e["type"] == d["type"]]
                    if not active:
                        results.append({"player": token, "uid": uid, "ok": False, "error": "Nothing active to lift."})
                        continue
                    for e in active:
                        standing.lift(uid, e["id"], actor=g.actor, note=lift_note, probation_hours=hours_of(d))
                    results.append({"player": token, "uid": uid, "ok": True, "lifted": len(active)})
            except ApiError as e:
                results.append({"player": token, "uid": uid, "ok": False, "error": e.message})
        return jsonify({"results": results, "done": sum(r["ok"] for r in results), "failed": sum(not r["ok"] for r in results)})

    # ---- customer service reps (only the admin manages these) ------------------

    @bp.get("/admin/api/staff")
    @guarded
    def staff_list():
        return jsonify({"staff": staff.list_agents(), "admin": staff.admin_username})

    @bp.post("/admin/api/staff")
    @guarded
    def staff_create():
        d = body()
        out = staff.create_agent(d.get("username"), d.get("name"), d.get("password"), actor=g.actor)
        return jsonify(out), 201

    @bp.post("/admin/api/staff/<username>")
    @guarded
    def staff_update(username: str):
        d = body()
        return jsonify(staff.update_agent(username, name=d.get("name"), active=d.get("active"), password=d.get("password")))

    # ---- attachments on appeals -----------------------------------------------

    @bp.get("/admin/api/files/<uid>/<fid>")
    @guarded
    def files(uid: str, fid: str):
        meta, data = uploads.read(uid, fid)
        return file_response(meta, data, download=request.args.get("download") == "1")

    @bp.get("/admin/api/feed")
    @guarded
    def feed():
        days = request.args.get("days", type=int) or 30
        return jsonify(cached(("feed", days), CACHE_SECONDS, lambda: {"events": [standing.log_json(e) for e in standing.recent_events(days)[:100]]}))

    @bp.get("/admin/api/recent")
    @guarded
    def recent():
        """Players with a moderation event in the last N days (default 3)."""
        days = request.args.get("days", type=int) or cfg.risk_window_days
        return jsonify(cached(("recent", days), CACHE_SECONDS, lambda: _recent(days)))

    def _recent(days: int):
        by_user: dict[str, dict] = {}
        for e in standing.recent_events(days):
            if e["event"] not in ("created", "lifted", "expired", "appeal_approved"):
                continue
            row = by_user.setdefault(e["uid"], {"uid": e["uid"], "events": [], "types": set()})
            row["events"].append({"event": e["event"], "type": e["type"], "at": _iso(e["at"])})
            row["types"].add(e["type"])
        out = []
        for uid, row in by_user.items():
            doc = store.read(f"users/{uid}") or {}
            out.append({**user_row(uid, doc), "events": row["events"], "types": sorted(row["types"])})
        return {"days": days, "users": out}

    return bp
