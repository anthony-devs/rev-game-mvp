"""Versioned data changes, run from the developer console (or ``python manage.py migrate``).

Each migration is idempotent (safe to run twice), has a dry run that only counts, and is recorded
in ``meta/migrations`` once applied. Add new ones at the END of ``MIGRATIONS`` and never edit one
that has already run in production.
"""
from __future__ import annotations

from typing import Callable

from .store import Store
from .util import Clock, as_utc, utcnow


def m001_backfill_last_seen(store: Store, apply: bool) -> dict:
    """Players created before 'last seen' existed get it from their last sign-in, so the
    active / inactive numbers are right on day one."""
    todo = 0
    for uid, d in store.list("users", 20000):
        if d.get("lastSeenAt") is None and d.get("lastLoginAt") is not None:
            todo += 1
            if apply:
                store.merge(f"users/{uid}", {"lastSeenAt": as_utc(d["lastLoginAt"])})
    return {"players": todo}


# (id, what it does, function). Append only.
MIGRATIONS: list[tuple[str, str, Callable[[Store, bool], dict]]] = [
    ("001_backfill_last_seen", "Give existing players a 'last seen' date from their last sign-in.", m001_backfill_last_seen),
]


class Migrator:
    def __init__(self, store: Store, clock: Clock = utcnow):
        self.store, self.clock = store, clock

    def _applied(self) -> dict:
        return (self.store.read("meta/migrations") or {}).get("applied", {})

    def status(self) -> list[dict]:
        done = self._applied()
        return [{"id": mid, "description": desc, "applied": mid in done, "appliedAt": (done.get(mid) or {}).get("at"), "by": (done.get(mid) or {}).get("by"),
                 "result": (done.get(mid) or {}).get("result")} for mid, desc, _f in MIGRATIONS]

    def run(self, apply: bool, actor: str) -> list[dict]:
        """Run every pending migration in order. Dry run unless ``apply``."""
        done, report = self._applied(), []
        for mid, desc, fn in MIGRATIONS:
            if mid in done:
                continue
            result = fn(self.store, apply)
            report.append({"id": mid, "description": desc, "result": result, "applied": apply})
            if apply:
                at = self.clock().isoformat()
                self.store.merge("meta/migrations", {"applied": {**self._applied(), mid: {"at": at, "by": actor, "result": result}}})
        return report
