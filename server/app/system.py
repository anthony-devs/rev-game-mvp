"""Switches the developer flips at runtime, kept in Firestore so every server instance obeys.

A snapshot listener keeps them in memory, so checking a flag on each request costs nothing.
"""
from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

from .store import Store
from .util import Clock, utcnow

log = logging.getLogger("revgames.flags")

# Starting something new is blocked in maintenance. Finishing what's open (cash out, blackjack
# actions, withdrawals already requested) is never blocked, so nobody is stranded mid-round.
STARTERS = (
    ("POST", "/v1/dice/roll"), ("POST", "/v1/plinko/drop"), ("POST", "/v1/roulette/spin"), ("POST", "/v1/blackjack/deal"), ("POST", "/v1/slots/spin"),
    ("POST", "/v1/crash/rounds"), ("POST", "/v1/wallet/claim-daily"), ("POST", "/v1/wallet/top-up"), ("POST", "/v1/wallet/reset"),
    ("POST", "/v1/live/deposits"), ("POST", "/v1/live/payouts"),
)


class SystemFlags:
    """Maintenance mode that does not depend on Firestore being reachable.

    The flag lives in three places and the newest wins: in memory (set the moment the developer
    flips it), a small file next to the server (survives a restart), and Firestore (shared with
    other instances, and read through a snapshot listener). If Firestore is down or out of quota,
    pausing still works on this server and players are still told why.
    """

    def __init__(self, store: Store, clock: Clock = utcnow, path: str | os.PathLike | None = None):
        self.store, self.clock = store, clock
        self._watch = store.watch_list("system_flags", 10)
        self._path = Path(path) if path else None
        self._local: dict | None = self._load()

    # -------------------------------------------------------------- local copy
    def _load(self) -> dict | None:
        if not self._path:
            return None
        try:
            d = json.loads(self._path.read_text("utf-8"))
            d["at"] = datetime.fromisoformat(d["at"])
            return d
        except Exception:
            return None

    def _save(self, doc: dict) -> None:
        if not self._path:
            return
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self._path.with_suffix(".tmp")
            tmp.write_text(json.dumps({**doc, "at": doc["at"].isoformat()}), "utf-8")
            os.replace(tmp, self._path)
        except Exception as e:
            log.warning("could not save the maintenance flag to disk: %s", e)

    @staticmethod
    def _ts(d: dict | None) -> float:
        at = (d or {}).get("at")
        try:
            return (at if at.tzinfo else at.replace(tzinfo=timezone.utc)).timestamp()
        except Exception:
            return 0.0

    # ------------------------------------------------------------------- reads
    def _current(self) -> dict | None:
        remote = None
        try:
            for uid, d in self._watch.rows():
                if uid == "maintenance":
                    remote = d
        except Exception:
            remote = None  # Firestore unreachable: the local copy still answers
        best = self._local if self._ts(self._local) >= self._ts(remote) else remote
        return best

    def maintenance(self) -> dict | None:
        d = self._current()
        return d if d and d.get("on") else None

    def public(self) -> dict | None:
        """What players are told (no names, no internals)."""
        m = self.maintenance()
        return {"message": m.get("message") or "Back shortly.", "scope": m.get("scope", "all")} if m else None

    # ------------------------------------------------------------------ writes
    def set_maintenance(self, on: bool, scope: str, message: str, actor: str) -> dict:
        scope = scope if scope in ("all", "live") else "all"
        doc = {"on": bool(on), "scope": scope, "message": (message or "We're making things better. Back shortly.")[:200], "by": actor, "at": self.clock()}
        self._local = doc  # in force immediately, whatever Firestore is doing
        self._save(doc)
        try:
            self.store.merge("system_flags/maintenance", doc)
            doc = {**doc, "shared": True}
        except Exception as e:
            log.warning("maintenance saved on this server only (database unreachable): %s", type(e).__name__)
            doc = {**doc, "shared": False}
        return doc

    def blocks(self, method: str, path: str, live_mode: bool) -> str | None:
        """The message to show if this request must wait for maintenance to end."""
        m = self.maintenance()
        if m is None or (method, path) not in STARTERS:
            return None
        if m.get("scope") == "live" and not (live_mode or path.startswith("/v1/live/")):
            return None
        return m.get("message") or "Back shortly."
