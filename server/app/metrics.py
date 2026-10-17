"""Numbers for the founder and developer dashboards, collected without costing reads.

Everything that happens often (a round, a deposit, a request, a player being seen) is counted
in memory and written to Firestore in one small batch every 30 seconds with atomic increments.
The dashboards then read a handful of daily summary documents instead of scanning players.

    stats_daily/<YYYY-MM-DD>   wagered / paid / wins per game per mode, money in and out, crashes
    crash_groups/<fingerprint> one document per distinct crash, with a count
    users/<uid>.lastSeenAt     refreshed at most once every few hours per player

Request timings and the recent error list stay in memory only (the developer console reads them).
"""
from __future__ import annotations

import hashlib
import logging
import os
import re
import socket
import threading
import time
from collections import OrderedDict, deque
from datetime import datetime, timedelta

from .store import Store, is_live
from .util import Clock, utcnow

log = logging.getLogger("metrics")

SEEN_EVERY_SECONDS = 3 * 3600
MAX_PENDING = 20000


def day_key(now: datetime) -> str:
    return now.strftime("%Y-%m-%d")


def _clip(v, n: int) -> str:
    return str(v or "")[:n]


_NOISE = re.compile(r"0x[0-9a-fA-F]+|\b\d{3,}\b|:\d+(:\d+)?")


def fingerprint(source: str, kind: str, stack: str, message: str) -> str:
    """Same bug, same fingerprint: numbers and addresses are stripped before hashing."""
    lines = [l.strip() for l in (stack or "").splitlines() if l.strip()][:6]
    basis = "|".join([source, _NOISE.sub("#", kind or ""), *[_NOISE.sub("#", l) for l in lines]]) if lines else "|".join([source, _NOISE.sub("#", kind or ""), _NOISE.sub("#", message or "")[:120]])
    return hashlib.sha1(basis.encode()).hexdigest()[:20]


class Metrics:
    def __init__(self, store: Store, clock: Clock = utcnow, flush_seconds: float = 30.0, background: bool = False):
        self.store, self.clock = store, clock
        self.started = time.time()
        self.instance = os.environ.get("K_REVISION") or socket.gethostname()
        self._lock = threading.Lock()
        # requests
        self.requests = 0
        self.quota_errors = 0
        self._lat: deque = deque(maxlen=5000)  # (unix time, ms, status)
        self.errors: deque = deque(maxlen=100)
        # buffered counters
        self._counts: dict[str, dict] = {}  # day -> nested increments
        self._seen_rounds: OrderedDict = OrderedDict()
        self._seen_money: OrderedDict = OrderedDict()
        self._last_seen: dict[str, float] = {}
        self._pending_seen: dict[str, datetime] = {}
        self._crashes: dict[str, dict] = {}
        self._known_groups: set[str] = set()
        self._rate: dict[str, deque] = {}
        self.flush_failures = 0
        self.last_flush_at: float | None = None
        if background:
            threading.Thread(target=self._loop, args=(flush_seconds,), daemon=True, name="metrics-flush").start()
            import atexit

            atexit.register(self.flush)

    # ---------------------------------------------------------------- requests

    def observe(self, method: str, path: str, status: int, ms: float) -> None:
        self.requests += 1
        self._lat.append((time.time(), ms, status))

    def record_error(self, exc: BaseException, path: str, trace: str) -> None:
        quota = type(exc).__name__ in ("ResourceExhausted", "TooManyRequests")
        if quota:
            self.quota_errors += 1
        self.errors.append({"at": time.time(), "type": type(exc).__name__, "message": _clip(exc, 300), "path": path, "trace": _clip(trace, 3000), "quota": quota})
        if not quota:
            self.record_crash("server", type(exc).__name__, _clip(exc, 300), trace, {"path": path})

    def snapshot(self, window: float = 300.0) -> dict:
        cutoff = time.time() - window
        rows = [r for r in list(self._lat) if r[0] >= cutoff]
        n = len(rows)
        errs = sum(1 for r in rows if r[2] >= 500)
        ms = sorted(r[1] for r in rows)

        def pct(p):
            return round(ms[min(len(ms) - 1, int(len(ms) * p))], 1) if ms else 0.0

        return {
            "windowSeconds": int(window), "requests": n, "serverErrors": errs, "errorRate": round(errs / n, 4) if n else 0.0,
            "p50": pct(0.5), "p95": pct(0.95), "p99": pct(0.99),
            "uptimeSeconds": int(time.time() - self.started), "totalRequests": self.requests, "quotaErrors": self.quota_errors,
            "instance": self.instance, "flushFailures": self.flush_failures, "lastFlushAt": self.last_flush_at,
        }

    # ------------------------------------------------------------ money / rounds

    def _bump(self, path: tuple, amount: float, now: datetime | None = None) -> None:
        d = self._counts.setdefault(day_key(now or self.clock()), {})
        for k in path[:-1]:
            d = d.setdefault(k, {})
        d[path[-1]] = round(d.get(path[-1], 0) + amount, 2)

    def _once(self, seen: OrderedDict, key) -> bool:
        if key in seen:
            return False
        seen[key] = True
        if len(seen) > 5000:
            seen.popitem(last=False)
        return True

    def record_round(self, uid: str, round_id: str, game: str, bet: float, payout: float) -> None:
        with self._lock:
            if not self._once(self._seen_rounds, (uid, round_id)):
                return  # a retried transaction calls this again
            mode = "live" if is_live(uid) else "demo"
            self._bump((mode, game, "rounds"), 1)
            self._bump((mode, game, "wagered"), float(bet))
            self._bump((mode, game, "paid"), float(payout))
            if payout > bet:
                self._bump((mode, game, "wins"), 1)

    def record_money(self, kind: str, key: str, amount: float) -> None:
        """kind: deposit | payout | refund. Counted once per payment id."""
        with self._lock:
            if not self._once(self._seen_money, (kind, key)):
                return
            self._bump(("money", f"{kind}s"), float(amount))
            self._bump(("money", f"{kind}_count"), 1)

    # ---------------------------------------------------------------- activity

    def touch(self, uid: str) -> None:
        """The player used the app. Written to their profile at most every few hours."""
        now = time.monotonic()
        if now - self._last_seen.get(uid, -1e12) < SEEN_EVERY_SECONDS:
            return
        with self._lock:
            if len(self._last_seen) > MAX_PENDING:
                self._last_seen.clear()
            self._last_seen[uid] = now
            if len(self._pending_seen) < MAX_PENDING:
                self._pending_seen[uid] = self.clock()

    # ------------------------------------------------------------------ crashes

    def allow_crash_report(self, who: str, per_minute: int = 10, global_per_minute: int = 300) -> bool:
        now = time.monotonic()
        with self._lock:
            for key, limit in ((who, per_minute), ("*", global_per_minute)):
                q = self._rate.setdefault(key, deque())
                while q and now - q[0] > 60:
                    q.popleft()
                if len(q) >= limit:
                    return False
            for key in (who, "*"):
                self._rate[key].append(now)
            if len(self._rate) > 5000:
                self._rate.clear()
            return True

    def record_crash(self, source: str, kind: str, message: str, stack: str, meta: dict | None = None) -> str:
        fp = fingerprint(source, kind, stack, message)
        meta = meta or {}
        with self._lock:
            g = self._crashes.setdefault(fp, {"count": 0})
            g["count"] += 1
            g.update(source=source, kind=_clip(kind, 120), message=_clip(message, 300), stack=_clip(stack, 2500),
                     platform=_clip(meta.get("platform"), 40), appVersion=_clip(meta.get("appVersion"), 40),
                     path=_clip(meta.get("path"), 120), lastSeenAt=self.clock())
            self._bump(("crashes", source), 1)
        return fp

    # ------------------------------------------------------------------- flush

    def _loop(self, every: float) -> None:
        while True:
            time.sleep(every)
            try:
                self.flush()
            except Exception:
                log.exception("metrics flush failed")

    def flush(self) -> None:
        with self._lock:
            counts, self._counts = self._counts, {}
            seen, self._pending_seen = self._pending_seen, {}
            crashes, self._crashes = self._crashes, {}
        try:
            for day, deltas in counts.items():
                self.store.incr(f"stats_daily/{day}", deltas)
            for uid, at in seen.items():
                self.store.merge(f"users/{uid}", {"lastSeenAt": at})
            for fp, g in crashes.items():
                path = f"crash_groups/{fp}"
                n = g.pop("count")
                if fp not in self._known_groups and self.store.read(path) is None:
                    g.update(firstSeenAt=g["lastSeenAt"], status="open")
                self._known_groups.add(fp)
                self.store.merge(path, g)
                self.store.incr(path, {"count": n})
            self.last_flush_at = time.time()
        except Exception:
            self.flush_failures += 1
            with self._lock:  # keep the numbers for the next try (bounded, so a long outage can't eat memory)
                for day, deltas in counts.items():
                    self._merge_back(self._counts.setdefault(day, {}), deltas)
                if len(self._pending_seen) + len(seen) < MAX_PENDING:
                    self._pending_seen = {**seen, **self._pending_seen}
            raise

    def _merge_back(self, dst: dict, src: dict) -> None:
        for k, v in src.items():
            if isinstance(v, dict):
                self._merge_back(dst.setdefault(k, {}), v)
            else:
                dst[k] = round(dst.get(k, 0) + v, 2)

    # ------------------------------------------------------------------ reading

    def daily(self, days: int) -> list[dict]:
        """The last ``days`` daily summaries, oldest first. One read per day."""
        today = self.clock().replace(hour=0, minute=0, second=0, microsecond=0)
        out = []
        for i in range(days - 1, -1, -1):
            d = day_key(today - timedelta(days=i))
            out.append({"day": d, **(self.store.read(f"stats_daily/{d}") or {})})
        return out
