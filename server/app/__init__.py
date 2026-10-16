from __future__ import annotations

import logging
import os

from flask import Flask, Response, g, jsonify, request, stream_with_context

from .account import AccountService, firebase_account_deleter
from .auth import Verifier, firebase_verifier, require_auth
from .blackjack import BlackjackService
from .config import Config
from .crash import CrashService
from .dice import MAX_TARGET, MIN_TARGET, DiceService
from .errors import ApiError, bad_request
from .fairness import FairnessService
from .roulette import RouletteService
from .slots import SlotsService
from .store import FirestoreStore, Store
from .wallet import WalletService


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

    fair = services.get("fair") or FairnessService(store)
    wallet = services.get("wallet") or WalletService(store, cfg)
    slots = services.get("slots") or SlotsService(store, cfg, fair=fair)
    crash = services.get("crash") or CrashService(store, cfg, fair=fair)
    dice = services.get("dice") or DiceService(store, cfg, fair=fair)
    roulette = services.get("roulette") or RouletteService(store, cfg, fair=fair)
    blackjack = services.get("blackjack") or BlackjackService(store, cfg, fair=fair)
    account = services.get("account") or AccountService(store, firebase_account_deleter())
    fair.replayers = {
        "slots": slots.replay,
        "crash": crash.replay,
        "dice": dice.replay,
        "roulette": roulette.replay,
        "blackjack": blackjack.replay,
    }

    # ---- errors --------------------------------------------------------------

    @app.errorhandler(ApiError)
    def api_error(e: ApiError):
        return jsonify(e.to_json()), e.status

    @app.errorhandler(404)
    def not_found(_):
        return jsonify({"error": "not_found", "message": "Not found."}), 404

    @app.errorhandler(405)
    def not_allowed(_):
        return jsonify({"error": "method_not_allowed", "message": "Method not allowed."}), 405

    @app.errorhandler(Exception)
    def crash_guard(e: Exception):
        app.logger.exception("unhandled error")
        return jsonify({"error": "server_error", "message": "Something went wrong."}), 500

    def body() -> dict:
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            raise bad_request("invalid_body", "Send a JSON object.")
        return data

    # ---- routes --------------------------------------------------------------

    @app.get("/healthz")
    def healthz():
        return {"ok": True}

    @app.get("/v1/wallet")
    @require_auth
    def get_wallet():
        return jsonify(wallet.get(g.uid))

    @app.post("/v1/wallet/claim-daily")
    @require_auth
    def claim_daily():
        return jsonify(wallet.claim_daily(g.uid))

    @app.post("/v1/wallet/top-up")
    @require_auth
    def top_up():
        return jsonify(wallet.top_up(g.uid))

    @app.post("/v1/wallet/reset")
    @require_auth
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
    def delete_account():
        account.delete(g.uid)
        return jsonify({"deleted": True})

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
    def dice_roll():
        data = body()
        return jsonify(dice.roll(g.uid, data.get("bet"), data.get("target"), data.get("mode")))

    @app.post("/v1/roulette/spin")
    @require_auth
    def roulette_spin():
        return jsonify(roulette.spin(g.uid, body().get("bets")))

    @app.get("/v1/blackjack/active")
    @require_auth
    def blackjack_active():
        return jsonify({"active": blackjack.active(g.uid)})

    @app.post("/v1/blackjack/deal")
    @require_auth
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
    def slots_spin():
        return jsonify(slots.spin(g.uid, body().get("bet")))

    @app.post("/v1/crash/rounds")
    @require_auth
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
