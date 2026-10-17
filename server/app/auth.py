"""Firebase ID token check. The Flutter app sends: Authorization: Bearer <token>."""
from __future__ import annotations

from functools import wraps
from typing import Callable

from flask import current_app, g, request

from .errors import ApiError
from .store import live_uid

# Game requests sent with "X-Play-Mode: live" play on the player's real-money record.
LIVE_PLAY_PREFIXES = ("/v1/slots", "/v1/crash", "/v1/dice", "/v1/plinko", "/v1/roulette", "/v1/blackjack", "/v1/fairness", "/v1/rounds")

# A verifier takes the raw token and returns the Firebase uid (or raises).
Verifier = Callable[[str], str]


def firebase_verifier() -> Verifier:
    from firebase_admin import auth

    def verify(token: str) -> str:
        # A phone clock a few seconds ahead makes Firebase say "token used too early".
        decoded = auth.verify_id_token(token, clock_skew_seconds=30)
        return decoded["uid"]

    return verify


def require_auth(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            raise ApiError(401, "unauthenticated", "Sign in to continue.")
        try:
            g.uid = current_app.config["VERIFIER"](header[7:].strip())
        except Exception as e:
            current_app.logger.warning("token rejected on %s %s: %s", request.method, request.path, e)
            raise ApiError(401, "unauthenticated", "Your session expired. Sign in again.")
        metrics = current_app.extensions.get("metrics")
        if metrics is not None:
            metrics.touch(g.uid)  # "last seen", written at most every few hours
        g.real_uid = g.uid  # who signed in; g.uid becomes the live record below in live mode
        if request.headers.get("X-Play-Mode", "").lower() == "live" and request.path.startswith(LIVE_PLAY_PREFIXES):
            live = current_app.extensions.get("live")
            if live is None:
                raise ApiError(403, "live_unavailable", "Live play isn't available.")
            live.require_live_play(g.real_uid)
            g.uid = live_uid(g.real_uid)
        return view(*args, **kwargs)

    return wrapper
