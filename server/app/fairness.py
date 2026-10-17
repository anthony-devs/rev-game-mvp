"""Provably fair randomness.

Each player has a secret *server seed*. Its SHA-256 hash is published first
(``users/{uid}/fairness/current``), together with a *client seed* and a
*nonce* that goes up by one every round. A round's random numbers are

    HMAC_SHA256(server_seed, "client_seed:nonce:cursor")

so the server cannot change a result after the fact. When the player
*rotates* the seed, the old server seed is revealed in ``seed_history`` and
anyone can check that (1) it hashes to the published value and (2) it
reproduces the stored results.

A seed is never revealed while a round that depends on it is still open
(a running crash round or an unfinished blackjack hand), because that would
leak the outcome. ``lockUntil`` blocks rotation until those rounds end.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta
from typing import Callable, Optional

from .errors import ApiError, bad_request
from .store import Doc, Store, Txn, fair_public_path, fair_secret_path, round_path, seed_history_path
from .util import Clock, as_utc as _as_utc, utcnow


def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


class HmacRng:
    """Deterministic random numbers from a seed pair. Same API the games use."""

    def __init__(self, server_seed: str, client_seed: str, nonce: int):
        self.server_seed, self.client_seed, self.nonce = server_seed, client_seed, nonce
        self._cursor = 0
        self._buf: list[float] = []

    def _refill(self) -> None:
        msg = f"{self.client_seed}:{self.nonce}:{self._cursor}".encode()
        digest = hmac.new(self.server_seed.encode(), msg, hashlib.sha256).digest()
        self._cursor += 1
        # 6 bytes -> 48 bits per number, 5 numbers per digest.
        self._buf = [int.from_bytes(digest[i : i + 6], "big") / 2**48 for i in range(0, 30, 6)]

    def random(self) -> float:
        if not self._buf:
            self._refill()
        return self._buf.pop(0)

    def choice(self, seq):
        return seq[int(self.random() * len(seq))]

    def shuffle(self, seq: list) -> None:
        for i in range(len(seq) - 1, 0, -1):
            j = int(self.random() * (i + 1))
            seq[i], seq[j] = seq[j], seq[i]


def _new_pair(now: datetime, client_seed: Optional[str] = None, uid: str = "") -> tuple[Doc, Doc]:
    server_seed = secrets.token_hex(32)
    pub = {
        "serverSeedHash": sha256_hex(server_seed),
        "clientSeed": client_seed or f"rev-{secrets.token_hex(3)}",
        "nonce": 0,
        "createdAt": now,
    }
    secret = {"serverSeed": server_seed, "lockUntil": None}
    return pub, secret


class FairnessService:
    def __init__(self, store: Optional[Store] = None, clock: Clock = utcnow, rng_override=None):
        self.store, self.clock = store, clock
        self.override = rng_override  # tests inject a scripted RNG
        self.replayers: dict[str, Callable[[HmacRng, Doc], bool]] = {}

    # ---- used inside a game's transaction -------------------------------------

    def begin(self, txn: Txn, uid: str, now: datetime, lock_until: Optional[datetime] = None):
        """Next nonce for this player. Returns (rng, info) where info goes on the round."""
        pub = txn.get(fair_public_path(uid))
        secret = txn.get(fair_secret_path(uid))
        if pub is None or secret is None:
            pub, secret = _new_pair(now, uid=uid)
        nonce = pub["nonce"]
        info = {"serverSeedHash": pub["serverSeedHash"], "clientSeed": pub["clientSeed"], "nonce": nonce}

        current_lock = _as_utc(secret.get("lockUntil"))
        new_lock = current_lock
        if lock_until is not None and (current_lock is None or lock_until > current_lock):
            new_lock = lock_until
        txn.set(fair_public_path(uid), {**pub, "nonce": nonce + 1})
        txn.set(fair_secret_path(uid), {**secret, "lockUntil": new_lock})

        rng = self.override or HmacRng(secret["serverSeed"], pub["clientSeed"], nonce)
        return rng, info

    def release(self, txn: Txn, uid: str) -> None:
        """A long round (blackjack hand) finished: the seed may be rotated again."""
        secret = txn.get(fair_secret_path(uid))
        if secret is not None:
            txn.set(fair_secret_path(uid), {**secret, "lockUntil": None})

    # ---- endpoints ------------------------------------------------------------

    def current(self, uid: str) -> dict:
        def fn(txn: Txn):
            pub = txn.get(fair_public_path(uid))
            if pub is None:
                pub, secret = _new_pair(self.clock(), uid=uid)
                txn.set(fair_public_path(uid), pub)
                txn.set(fair_secret_path(uid), secret)
            return pub

        return self._public(self.store.run(fn))

    def rotate(self, uid: str, client_seed=None) -> dict:
        if client_seed is not None:
            if not isinstance(client_seed, str) or not (1 <= len(client_seed.strip()) <= 32):
                raise bad_request("invalid_client_seed", "Client seed must be 1 to 32 characters.")
            client_seed = client_seed.strip()

        def fn(txn: Txn):
            now = self.clock()
            pub = txn.get(fair_public_path(uid))
            secret = txn.get(fair_secret_path(uid))
            revealed = None
            if pub is not None and secret is not None:
                lock = _as_utc(secret.get("lockUntil"))
                if lock is not None and now < lock:
                    raise ApiError(
                        409,
                        "round_in_progress",
                        "A round is still in progress. Finish it, then try again.",
                    )
                revealed = {
                    "serverSeedHash": pub["serverSeedHash"],
                    "serverSeed": secret["serverSeed"],
                    "clientSeed": pub["clientSeed"],
                    "nonceEnd": pub["nonce"],
                    "revealedAt": now,
                }
                txn.set(seed_history_path(uid, pub["serverSeedHash"]), revealed)
            keep = client_seed or (pub["clientSeed"] if pub else None)
            new_pub, new_secret = _new_pair(now, keep, uid)
            txn.set(fair_public_path(uid), new_pub)
            txn.set(fair_secret_path(uid), new_secret)
            return revealed, new_pub

        revealed, pub = self.store.run(fn)
        return {
            "revealed": self._revealed(revealed) if revealed else None,
            "current": self._public(pub),
        }

    def verify(self, uid: str, round_id: str) -> dict:
        rnd = self.store.read(round_path(uid, round_id))
        if rnd is None:
            raise ApiError(404, "round_not_found", "Round not found.")
        proof = rnd.get("fairness") or {}
        seed_hash = proof.get("serverSeedHash")
        if not seed_hash:
            raise ApiError(404, "no_fairness_data", "This round has no fairness data.")
        history = self.store.read(seed_history_path(uid, seed_hash))
        base = {
            "roundId": round_id,
            "game": rnd.get("game"),
            "serverSeedHash": seed_hash,
            "clientSeed": proof.get("clientSeed"),
            "nonce": proof.get("nonce"),
        }
        if history is None:
            return {**base, "status": "pending", "serverSeed": None}

        seed = history["serverSeed"]
        hash_ok = sha256_hex(seed) == seed_hash
        replay = self.replayers.get(rnd.get("game"))
        outcome_ok = None
        if hash_ok and replay is not None:
            rng = HmacRng(seed, proof["clientSeed"], int(proof["nonce"]))
            try:
                outcome_ok = bool(replay(rng, rnd))
            except Exception:
                outcome_ok = False
        ok = hash_ok and outcome_ok is not False
        return {
            **base,
            "status": "verified" if ok else "mismatch",
            "serverSeed": seed,
            "hashMatches": hash_ok,
            "outcomeMatches": outcome_ok,
        }

    # ---- shapes ---------------------------------------------------------------

    @staticmethod
    def _public(pub: Doc) -> dict:
        return {"serverSeedHash": pub["serverSeedHash"], "clientSeed": pub["clientSeed"], "nonce": pub["nonce"]}

    @staticmethod
    def _revealed(rev: Doc) -> dict:
        return {
            "serverSeedHash": rev["serverSeedHash"],
            "serverSeed": rev["serverSeed"],
            "clientSeed": rev["clientSeed"],
            "nonceEnd": rev["nonceEnd"],
        }


def lock_for(now: datetime, seconds: float) -> datetime:
    return now + timedelta(seconds=seconds)
