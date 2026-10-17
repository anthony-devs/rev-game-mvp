from __future__ import annotations

import logging
import threading
import os
import time

from .env import load_env

ENV_FILES = load_env()  # must run before .config reads the environment

from functools import wraps

from flask import Flask, Response, g, jsonify, request, stream_with_context

from .account import AccountService, firebase_account_deleter
from .admin import make_admin
from .catalog import CatalogService
from .live import LiveService
from .live_routes import make_live
from .providers import build_providers
from .auth import Verifier, firebase_verifier, require_auth
from .blackjack import BlackjackService
from .config import Config
from .crash import CrashService
from .dice import MAX_TARGET, MIN_TARGET, DiceService
from .errors import ApiError, bad_request
from .fairness import FairnessService
from .roulette import RouletteService
from .slots import SlotsService
from .staff import StaffService, make_staff
from .standing import StandingService
from .store import FirestoreStore, Store, live_uid
from .support import CATEGORIES, SupportService
from .support_site import make_support_site
from .uploads import UploadService, file_response
from .wallet import WalletService


def _total_bet(data: dict) -> float | None:
    """The amount a play request would stake (a single bet, or a roulette table)."""
    try:
        if isinstance(data.get("bets"), list):
            return sum(float(b.get("amount", 0)) for b in data["bets"] if isinstance(b, dict))
        if data.get("bet") is not None:
            return float(data["bet"])
    except (TypeError, ValueError):
        return None
    return None


def _warm_up(store) -> None:
    """Open the database connection and fetch Google's token keys in the background, so the
    first player after a deploy doesn't pay for the cold start."""

    def go():
        try:
            store.list("games", limit=1)
        except Exception as e:
            logging.getLogger("app").info("warm-up: database not ready yet (%s)", e)

    threading.Thread(target=go, daemon=True).start()


def create_app(store: Store | None = None, verifier: Verifier | None = None, cfg: Config | None = None, **services) -> Flask:
    """Build the app. Tests pass a MemoryStore and a fake verifier; production
    passes nothing and gets Firestore + real Firebase token checks."""
    app = Flask(__name__)
    logging.basicConfig(level=logging.INFO)
    cfg = cfg or Config()

    if store is None:
        import firebase_admin
        from firebase_admin import firestore

        if not firebase_admin._apps:
            # Credentials come from the Cloud Run service account (or `gcloud auth application-default login` locally).
            firebase_admin.initialize_app(options={"projectId": os.environ.get("FIREBASE_PROJECT_ID", "rev-games")})
        store = FirestoreStore(firestore.client())
    app.config["VERIFIER"] = verifier or firebase_verifier()
    if isinstance(store, FirestoreStore):
        _warm_up(store)

    fair = services.get("fair") or FairnessService(store)
    wallet = services.get("wallet") or WalletService(store, cfg)
    slots = services.get("slots") or SlotsService(store, cfg, fair=fair)
    crash = services.get("crash") or CrashService(store, cfg, fair=fair)
    dice = services.get("dice") or DiceService(store, cfg, fair=fair)
    roulette = services.get("roulette") or RouletteService(store, cfg, fair=fair)
    blackjack = services.get("blackjack") or BlackjackService(store, cfg, fair=fair)
    account = services.get("account") or AccountService(store, firebase_account_deleter())
    standing = services.get("standing") or StandingService(store, cfg)
    staff = services.get("staff") or StaffService(store, cfg)
    uploads = services.get("uploads") or UploadService(store, cfg)
    catalog = services.get("catalog") or CatalogService(store, cfg.catalog_cache_seconds)
    app.extensions["catalog"] = catalog
    support = services.get("support") or SupportService(store, cfg, uploads)
    live = services.get("live") or LiveService(store, cfg, services.get("providers") or build_providers(store, cfg), standing)
    app.extensions["live"] = live
    app.config["MAX_CONTENT_LENGTH"] = int((cfg.upload_max_mb + 1) * 1024 * 1024)
    app.register_blueprint(make_staff(staff))
    app.register_blueprint(make_live(live))
    app.register_blueprint(make_admin(store, standing, cfg, staff, uploads, live))
    app.register_blueprint(make_support_site(store, support, standing, uploads, staff))
    fair.replayers = {
        "slots": slots.replay,
        "crash": crash.replay,
        "dice": dice.replay,
        "roulette": roulette.replay,
        "blackjack": blackjack.replay,
    }

    # ---- timing --------------------------------------------------------------
    # One line per request with how long it took, so slowness shows up in the log.
    # Anything over SLOW_MS is logged as a warning.
    @app.before_request
    def _start_timer():
        g._t0 = time.perf_counter()

    @app.after_request
    def _log_timing(resp):
        t0 = g.get("_t0")
        if t0 is not None and not request.path.startswith(("/staff", "/admin/api", "/support/api")):
            ms = (time.perf_counter() - t0) * 1000
            level = logging.WARNING if ms >= cfg.slow_ms else logging.INFO
            app.logger.log(level, "%s %s -> %s in %.0f ms%s", request.method, request.path, resp.status_code, ms, " (SLOW)" if ms >= cfg.slow_ms else "")
        return resp

    # ---- errors --------------------------------------------------------------

    @app.errorhandler(ApiError)
    def api_error(e: ApiError):
        return jsonify(e.to_json()), e.status

    @app.errorhandler(404)
    def not_found(_):
        return jsonify({"error": "not_found", "message": "Not found."}), 404

    @app.errorhandler(413)
    def too_big(_):
        return jsonify({"error": "file_too_large", "message": f"Files can be up to {cfg.upload_max_mb:g} MB."}), 413

    @app.errorhandler(405)
    def not_allowed(_):
        return jsonify({"error": "method_not_allowed", "message": "Method not allowed."}), 405

    @app.errorhandler(Exception)
    def crash_guard(e: Exception):
        if type(e).__name__ in ("ResourceExhausted", "TooManyRequests"):  # Firestore quota / rate limit
            app.logger.warning("database quota exceeded (resets daily on the free plan)")
            return jsonify({"error": "database_busy", "message": "The database quota is used up for now. Try again later."}), 503
        app.logger.exception("unhandled error")
        return jsonify({"error": "server_error", "message": "Something went wrong."}), 500

    def body() -> dict:
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            raise bad_request("invalid_body", "Send a JSON object.")
        return data

    def gate(kind: str):
        """Refuse the request if the account's standing doesn't allow ``kind``
        (play, credits or delete). Put it under ``@require_auth``."""

        def deco(view):
            @wraps(view)
            def wrapper(*args, **kwargs):
                bet = None
                if kind == "play" and request.method == "POST":
                    data = request.get_json(silent=True)
                    if isinstance(data, dict):
                        bet = _total_bet(data)
                standing.enforce(getattr(g, "real_uid", g.uid), kind, bet)
                return view(*args, **kwargs)

            return wrapper

        return deco

    # ---- routes --------------------------------------------------------------

    @app.get("/healthz")
    def healthz():
        return {"ok": True}

    @app.get("/v1/games")
    @require_auth
    def list_games():
        return {"games": catalog.games()}

    @app.get("/v1/wallet")
    @require_auth
    def get_wallet():
        return jsonify(wallet.get(g.uid))

    @app.post("/v1/wallet/claim-daily")
    @require_auth
    @gate('credits')
    def claim_daily():
        return jsonify(wallet.claim_daily(g.uid))

    @app.post("/v1/wallet/top-up")
    @require_auth
    @gate('credits')
    def top_up():
        return jsonify(wallet.top_up(g.uid))

    @app.post("/v1/wallet/reset")
    @require_auth
    @gate('credits')
    def reset_wallet():
        return jsonify(wallet.reset(g.uid))

    @app.get("/v1/config")
    def game_config():
        """Limits the app shows before a game opens. Public, nothing secret."""
        return jsonify(
            {
                "startingBalance": cfg.starting_balance,
                "dailyRewards": list(cfg.daily_rewards),
                "dice": {
                    "minBet": cfg.dice_min_bet,
                    "maxBet": cfg.dice_max_bet,
                    "houseEdge": cfg.dice_house_edge,
                    "minTarget": MIN_TARGET,
                    "maxTarget": MAX_TARGET,
                },
                "roulette": {"minBet": cfg.roulette_min_bet, "maxTotal": cfg.roulette_max_total},
                "blackjack": {"minBet": cfg.blackjack_min_bet, "maxBet": cfg.blackjack_max_bet},
                "crash": {"minBet": cfg.crash_min_bet, "maxBet": cfg.crash_max_bet},
            }
        )

    @app.delete("/v1/account")
    @require_auth
    @gate('delete')
    def delete_account():
        live.assert_can_delete(g.uid)  # money first: nothing is deleted while real balance or payouts are open
        try:
            uploads.purge(g.uid)
        except Exception:
            app.logger.exception("could not delete attachments for %s", g.uid)
        account.delete(g.uid)
        store.delete_user(live_uid(g.uid))
        return jsonify({"deleted": True})

    @app.get("/v1/account/standing")
    @require_auth
    def account_standing():
        return jsonify(standing.public(standing.summary(g.uid)))

    @app.post("/v1/account/appeal")
    @require_auth
    def account_appeal():
        data = body()
        atts = uploads.resolve(g.uid, data.get("attachments"))
        return jsonify(standing.appeal(g.uid, data.get("actionId"), data.get("message"), atts)), 201

    # ---- attachments and support (open to everyone who can sign in, even if restricted) ----

    @app.post("/v1/uploads")
    @require_auth
    def upload_file():
        f = request.files.get("file")
        if f is None:
            raise bad_request("no_file", "Attach a file.")
        return jsonify(uploads.save(g.uid, f.filename or "file", f.read())), 201

    @app.get("/v1/uploads/<fid>")
    @require_auth
    def get_upload(fid: str):
        meta, data = uploads.read(g.uid, fid)
        return file_response(meta, data)

    @app.get("/v1/support/categories")
    def support_categories():
        return jsonify({"categories": [{"id": k, "label": v} for k, v in CATEGORIES.items()], "maxFiles": cfg.upload_max_files, "maxMb": cfg.upload_max_mb})

    @app.get("/v1/support/tickets")
    @require_auth
    def tickets_list():
        return jsonify({"tickets": support.list_for_user(g.uid)})

    @app.post("/v1/support/tickets")
    @require_auth
    def tickets_create():
        d = body()
        profile = store.read(f"users/{g.uid}") or {}
        return jsonify(support.create(g.uid, profile, d.get("subject"), d.get("category"), d.get("message"), d.get("attachments"))), 201

    @app.get("/v1/support/tickets/<tid>")
    @require_auth
    def tickets_get(tid: str):
        return jsonify(support.get_for_user(g.uid, tid))

    @app.post("/v1/support/tickets/<tid>/messages")
    @require_auth
    def tickets_reply(tid: str):
        d = body()
        return jsonify(support.user_reply(g.uid, tid, d.get("message"), d.get("attachments"))), 201

    @app.post("/v1/support/tickets/<tid>/read")
    @require_auth
    def tickets_read(tid: str):
        support.user_mark_read(g.uid, tid)
        return jsonify({"ok": True})

    @app.post("/v1/support/tickets/<tid>/close")
    @require_auth
    def tickets_close(tid: str):
        return jsonify(support.user_close(g.uid, tid))

    @app.get("/v1/fairness")
    @require_auth
    def fairness_current():
        return jsonify(fair.current(g.uid))

    @app.post("/v1/fairness/rotate")
    @require_auth
    def fairness_rotate():
        data = request.get_json(silent=True) or {}
        return jsonify(fair.rotate(g.uid, data.get("clientSeed") if isinstance(data, dict) else None))

    @app.get("/v1/fairness/verify/<round_id>")
    @require_auth
    def fairness_verify(round_id: str):
        return jsonify(fair.verify(g.uid, round_id))

    @app.post("/v1/dice/roll")
    @require_auth
    @gate('play')
    def dice_roll():
        data = body()
        return jsonify(dice.roll(g.uid, data.get("bet"), data.get("target"), data.get("mode")))

    @app.post("/v1/roulette/spin")
    @require_auth
    @gate('play')
    def roulette_spin():
        return jsonify(roulette.spin(g.uid, body().get("bets")))

    @app.get("/v1/blackjack/active")
    @require_auth
    def blackjack_active():
        return jsonify({"active": blackjack.active(g.uid)})

    @app.post("/v1/blackjack/deal")
    @require_auth
    @gate('play')
    def blackjack_deal():
        return jsonify(blackjack.deal(g.uid, body().get("bet")))

    @app.post("/v1/blackjack/<round_id>/<action>")
    @require_auth
    def blackjack_action(round_id: str, action: str):
        return jsonify(blackjack.act(g.uid, round_id, action))

    @app.get("/v1/slots/config")
    @require_auth
    def slots_config():
        return jsonify(slots.config(g.uid, wallet.get(g.uid)["balance"]))

    @app.post("/v1/slots/spin")
    @require_auth
    @gate('play')
    def slots_spin():
        return jsonify(slots.spin(g.uid, body().get("bet")))

    @app.post("/v1/crash/rounds")
    @require_auth
    @gate('play')
    def crash_start():
        data = body()
        return jsonify(crash.start(g.uid, data.get("bet"), data.get("autoCashout")))

    @app.post("/v1/crash/rounds/<round_id>/cashout")
    @require_auth
    def crash_cashout(round_id: str):
        return jsonify(crash.cash_out(g.uid, round_id))

    @app.get("/v1/crash/rounds/<round_id>/events")
    @require_auth
    def crash_events(round_id: str):
        stream = crash.events(g.uid, round_id)
        first = next(stream)  # raises ApiError(404) before the stream starts

        def generate():
            yield first
            yield from stream

        return Response(
            stream_with_context(generate()),
            mimetype="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    return app
