"""Switches the developer flips at runtime, kept in Firestore so every server instance obeys.

A snapshot listener keeps them in memory, so checking a flag on each request costs nothing.
"""
from __future__ import annotations

from .store import Store
from .util import Clock, utcnow

# Starting something new is blocked in maintenance. Finishing what's open (cash out, blackjack
# actions, withdrawals already requested) is never blocked, so nobody is stranded mid-round.
STARTERS = (
    ("POST", "/v1/dice/roll"), ("POST", "/v1/roulette/spin"), ("POST", "/v1/blackjack/deal"), ("POST", "/v1/slots/spin"),
    ("POST", "/v1/crash/rounds"), ("POST", "/v1/wallet/claim-daily"), ("POST", "/v1/wallet/top-up"), ("POST", "/v1/wallet/reset"),
    ("POST", "/v1/live/deposits"), ("POST", "/v1/live/payouts"),
)


class SystemFlags:
    def __init__(self, store: Store, clock: Clock = utcnow):
        self.store, self.clock = store, clock
        self._watch = store.watch_list("system_flags", 10)

    def maintenance(self) -> dict | None:
        for uid, d in self._watch.rows():
            if uid == "maintenance" and d.get("on"):
                return d
        return None

    def set_maintenance(self, on: bool, scope: str, message: str, actor: str) -> dict:
        scope = scope if scope in ("all", "live") else "all"
        doc = {"on": bool(on), "scope": scope, "message": (message or "We're making things better. Back shortly.")[:200], "by": actor, "at": self.clock()}
        self.store.merge("system_flags/maintenance", doc)
        return doc

    def blocks(self, method: str, path: str, live_mode: bool) -> str | None:
        """The message to show if this request must wait for maintenance to end."""
        m = self.maintenance()
        if m is None or (method, path) not in STARTERS:
            return None
        if m.get("scope") == "live" and not (live_mode or path.startswith("/v1/live/")):
            return None
        return m.get("message") or "Back shortly."
