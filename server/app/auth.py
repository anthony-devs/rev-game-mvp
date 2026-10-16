"""Firebase ID token check. The Flutter app sends: Authorization: Bearer <token>."""
from __future__ import annotations

from functools import wraps
from typing import Callable

from flask import current_app, g, request

from .errors import ApiError

# A verifier takes the raw token and returns the Firebase uid (or raises).
Verifier = Callable[[str], str]


def firebase_verifier() -> Verifier:
    from firebase_admin import auth

    def verify(token: str) -> str:
        decoded = auth.verify_id_token(token)
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
        except Exception:
            raise ApiError(401, "unauthenticated", "Your session expired. Sign in again.")
        return view(*args, **kwargs)

    return wrapper
