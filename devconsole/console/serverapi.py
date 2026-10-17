"""Talking to a game server: plain health checks, and signed calls to /internal/dev/*.

The signature is HMAC-SHA256 over method, path+query, timestamp, a one-time nonce and the body
hash, using that server's DEV_API_SECRET. It must match ``sign`` in the server's devapi.py."""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import time

import requests

from .config import Target


def sign(secret: str, method: str, path_qs: str, ts: str, nonce: str, body: bytes) -> str:
    msg = "\n".join([method.upper(), path_qs, ts, nonce, hashlib.sha256(body).hexdigest()])
    return hmac.new(secret.encode(), msg.encode(), hashlib.sha256).hexdigest()


class Reply:
    def __init__(self, status: int, data, ms: float, error: str = ""):
        self.status, self.data, self.ms, self.error = status, data, ms, error

    @property
    def ok(self) -> bool:
        return 200 <= self.status < 300


def plain(t: Target, method: str, path: str, timeout: float = 10, headers: dict | None = None, **kw) -> Reply:
    t0 = time.perf_counter()
    try:
        r = requests.request(method, t.url + path, timeout=timeout, headers=headers, allow_redirects=False, **kw)
        try:
            data = r.json()
        except ValueError:
            data = r.text[:300]
        return Reply(r.status_code, data, (time.perf_counter() - t0) * 1000)
    except requests.RequestException as e:
        return Reply(0, None, (time.perf_counter() - t0) * 1000, type(e).__name__)


def signed(t: Target, method: str, path: str, body: dict | None = None, timeout: float = 15) -> Reply:
    if len(t.secret) < 32:
        return Reply(0, None, 0, "no_secret")
    raw = json.dumps(body).encode() if body is not None else b""
    ts, nonce = str(int(time.time())), os.urandom(12).hex()
    headers = {"X-Dev-Time": ts, "X-Dev-Nonce": nonce, "X-Dev-Sig": sign(t.secret, method, path, ts, nonce, raw), "Content-Type": "application/json"}
    return plain(t, method, path, timeout, headers, data=raw if body is not None else None)
