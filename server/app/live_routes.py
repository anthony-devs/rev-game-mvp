"""Live play endpoints: status, deposits, payouts, provider webhooks (and the mock checkout)."""
from __future__ import annotations

from flask import Blueprint, g, jsonify, request

from .auth import require_auth
from .errors import ApiError, bad_request
from .live import LiveService


def make_live(live: LiveService) -> Blueprint:
    bp = Blueprint("live", __name__)

    def body() -> dict:
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            raise bad_request("invalid_body", "Send a JSON object.")
        return data

    def uid() -> str:
        return getattr(g, "real_uid", g.uid)

    @bp.get("/v1/live/status")
    @require_auth
    def status():
        return jsonify(live.status(uid()))

    @bp.get("/v1/live/agreement")
    @require_auth
    def agreement():
        return jsonify(live.agreement(uid()))

    @bp.post("/v1/live/agreement")
    @require_auth
    def accept_agreement():
        d = body()
        return jsonify(live.accept_agreement(uid(), d.get("version"), d.get("confirmed")))

    @bp.get("/v1/live/payments")
    @require_auth
    def payments():
        return jsonify({"payments": live.payments(uid())})

    @bp.get("/v1/live/payments/<pid>")
    @require_auth
    def one(pid: str):
        return jsonify(live.one(uid(), pid))

    @bp.post("/v1/live/deposits")
    @require_auth
    def deposit():
        d = body()
        return jsonify(live.create_deposit(uid(), d.get("provider"), d.get("amount"), d.get("key")))

    @bp.post("/v1/live/deposits/<pid>/verify")
    @require_auth
    def verify(pid: str):
        return jsonify(live.verify_deposit(uid(), pid))

    @bp.post("/v1/live/payouts")
    @require_auth
    def payout():
        d = body()
        return jsonify(live.request_payout(uid(), d.get("provider"), d.get("amount"), d.get("destination"), d.get("key")))

    @bp.post("/v1/live/webhooks/<provider>")
    def webhook(provider: str):
        # No sign in here: the provider's signature is the proof.
        if not live.handle_webhook(provider, request.headers, request.get_data()):
            raise ApiError(401, "bad_signature", "Signature check failed.")
        return jsonify({"ok": True})

    @bp.post("/v1/live/mock/pay")
    @require_auth
    def mock_pay():
        """Stands in for the customer finishing the gateway's own page (mock mode only)."""
        if live.cfg.payments_mode != "mock":
            raise ApiError(404, "not_found", "Not found.")
        live.require_live()
        d = body()
        pay = live._own(uid(), str(d.get("paymentId", "")))
        prov = live.providers.get(pay["provider"])
        if pay["kind"] != "deposit" or not pay.get("providerRef") or not hasattr(prov, "complete"):
            raise bad_request("not_mock", "Nothing to complete.")
        prov.complete(pay["providerRef"], "success" if d.get("outcome") == "success" else "failed")
        return jsonify({"ok": True})

    return bp
