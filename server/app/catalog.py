"""The game list. Built-in defaults, with the Firestore ``games`` collection layered on top.

    games/dice        { enabled: false }                    -> shown as paused
    games/mines       { name: 'Mines', tag: 'Instant', comingSoon: true, type: 'dice' }

The app loads this from ``GET /v1/games`` instead of reading Firestore itself, so
when the server is down or its database isn't set up the app knows and says so.
"""
from __future__ import annotations

import threading
import time

from .errors import ApiError
from .util import is_quota, is_transient
from .store import Store

TYPES = {"slots", "roulette", "blackjack", "dice", "crash", "plinko"}


def _g(id_, type_, name, tag, order, *, soon=False, min_bet=10, max_bet=100000, rtp=0.96) -> dict:
    g = {"id": id_, "type": type_, "name": name, "tag": tag, "enabled": True, "comingSoon": soon, "sortOrder": order}
    if not soon:
        g.update(minBet=min_bet, maxBet=max_bet, rtp=rtp)
    return g


DEFAULT_GAMES = [
    _g("slots", "slots", "Golden Reels", "Slots", 1, max_bet=1000, rtp=0.96),
    _g("crash", "crash", "Dash Crash", "Instant", 2, max_bet=500000, rtp=0.97),
    _g("roulette", "roulette", "Euro Roulette", "Table", 3, rtp=0.973),
    _g("blackjack", "blackjack", "Blackjack", "Table", 4, rtp=0.99),
    _g("dice", "dice", "Dice", "Instant", 5, rtp=0.95),
    _g("plinko", "plinko", "Plinko", "Instant", 6, rtp=0.96),
    _g("soon-lucky7", "slots", "Lucky Sevens", "Slots", 20, soon=True),
    _g("soon-fruit", "slots", "Fruit Frenzy", "Slots", 21, soon=True),
    _g("soon-diamond", "slots", "Diamond Deluxe", "Slots", 22, soon=True),
    _g("soon-mines", "dice", "Mines", "Instant", 23, soon=True),
    _g("soon-baccarat", "blackjack", "Baccarat", "Table", 25, soon=True),
]

_FIELDS = {"type", "name", "tag", "enabled", "comingSoon", "minBet", "maxBet", "rtp", "sortOrder"}


class CatalogService:
    def __init__(self, store: Store, ttl: float = 20.0):
        self.store = store
        self.ttl = ttl
        self._cache: tuple[float, list[dict]] | None = None
        self._lock = threading.Lock()

    def games(self) -> list[dict]:
        """Cached for a few seconds, so opening the lobby doesn't hit the database every time.
        If the database fails but we have an older copy, keep serving it."""
        now = time.monotonic()
        hit = self._cache
        if hit and now - hit[0] < self.ttl:
            return hit[1]
        with self._lock:  # one refresh at a time; the rest wait and reuse it
            hit = self._cache
            if hit and time.monotonic() - hit[0] < self.ttl:
                return hit[1]
            try:
                games = self._build()
            except ApiError:
                if hit:
                    return hit[1]
                raise
            self._cache = (time.monotonic(), games)
            return games

    def invalidate(self) -> None:
        self._cache = None

    def _build(self) -> list[dict]:
        try:
            remote = self.store.list("games", limit=100)
        except Exception as e:
            if is_quota(e):
                raise  # a quota problem is "busy", not "not set up": the app-wide handler answers it
            if is_transient(e):  # timeouts, connection drops, Firestore briefly unavailable
                raise ApiError(503, "service_unavailable", "We're experiencing downtime. Please try again shortly.") from e
            # Firestore missing, no credentials, API not enabled...
            raise ApiError(503, "not_initialized", "We're getting things ready. Please try again in a few minutes.") from e
        by_id = {g["id"]: dict(g) for g in DEFAULT_GAMES}
        for gid, doc in remote:
            base = by_id.get(gid, {"id": gid, "type": "slots", "name": gid, "tag": "", "enabled": True, "comingSoon": False, "sortOrder": 100})
            for k, v in (doc or {}).items():
                if k in _FIELDS:
                    base[k] = v
            if base.get("type") not in TYPES:
                base["type"] = "slots"
            by_id[gid] = base
        return sorted(by_id.values(), key=lambda g: (g.get("sortOrder") or 0, g["id"]))
