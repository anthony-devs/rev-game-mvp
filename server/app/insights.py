"""What the founder reads: profit, activity, crashes, and one player's whole account.

All of it comes from small summary documents, counters and database-side counts, so opening a
page costs a handful of reads, not a scan of every player.
"""
from __future__ import annotations

from datetime import datetime, timedelta

from .metrics import Metrics, day_key
from .standing import _iso
from .store import Store, live_uid, wallet_path
from .util import Clock, as_utc, money, utcnow

GAMES = ("slots", "crash", "dice", "plinko", "roulette", "blackjack")


def _mode_totals(day: dict, mode: str) -> dict:
    t = {"rounds": 0, "wagered": 0.0, "paid": 0.0, "wins": 0, "games": {}}
    for game in GAMES:
        g = (day.get(mode) or {}).get(game) or {}
        row = {k: float(g.get(k, 0) or 0) for k in ("rounds", "wagered", "paid", "wins")}
        t["games"][game] = row
        for k in ("rounds", "wagered", "paid", "wins"):
            t[k] += row[k]
    return t


def _add(dst: dict, src: dict) -> None:
    """dst += src for nested dicts of numbers."""
    for k, v in (src or {}).items():
        if isinstance(v, dict):
            _add(dst.setdefault(k, {}), v)
        elif isinstance(v, (int, float)) and not isinstance(v, bool):
            dst[k] = round(dst.get(k, 0) + v, 2)


def _window(days: list[dict]) -> dict:
    """Totals over some daily summaries: live and demo play, plus the money that moved."""
    acc: dict = {}
    for d in days:
        _add(acc, {"live": d.get("live") or {}, "demo": d.get("demo") or {}, "money": d.get("money") or {}})
    out = {}
    for mode in ("live", "demo"):
        t = _mode_totals(acc, mode)
        t["ggr"] = money(t["wagered"] - t["paid"])
        t["rtp"] = round(t["paid"] / t["wagered"], 4) if t["wagered"] else None
        t["winRate"] = round(t["wins"] / t["rounds"], 4) if t["rounds"] else None
        t["avgBet"] = money(t["wagered"] / t["rounds"]) if t["rounds"] else 0
        t["hold"] = round(t["ggr"] / t["wagered"], 4) if t["wagered"] else None
        for g in t["games"].values():
            g["ggr"] = money(g["wagered"] - g["paid"])
            g["rtp"] = round(g["paid"] / g["wagered"], 4) if g["wagered"] else None
            g["winRate"] = round(g["wins"] / g["rounds"], 4) if g["rounds"] else None
        t["wagered"], t["paid"] = money(t["wagered"]), money(t["paid"])
        out[mode] = t
    m = acc.get("money") or {}
    out["money"] = {k: money(float(m.get(k, 0) or 0)) for k in ("deposits", "payouts", "refunds", "roundpacks")}
    out["money"].update({k: int(m.get(k, 0) or 0) for k in ("deposit_count", "payout_count", "roundpack_count")})
    out["money"]["netCash"] = money(out["money"]["deposits"] - out["money"]["payouts"])
    return out


class Insights:
    def __init__(self, store: Store, cfg, metrics: Metrics, live=None, standing=None, clock: Clock = utcnow):
        self.store, self.cfg, self.metrics, self.live, self.standing, self.clock = store, cfg, metrics, live, standing, clock
        self.crash_watch = store.watch_list("crash_groups", 100, order_by="lastSeenAt")

    # ------------------------------------------------------------------ profit

    def profit(self, days: int = 30) -> dict:
        days = max(1, min(int(days), 90))
        series, live_tot, demo_tot = [], _mode_totals({}, "live"), _mode_totals({}, "demo")
        money_tot = {"deposits": 0.0, "payouts": 0.0, "refunds": 0.0, "deposit_count": 0, "payout_count": 0}
        for day in self.metrics.daily(days):
            lv, dm = _mode_totals(day, "live"), _mode_totals(day, "demo")
            m = day.get("money") or {}
            for t, add in ((live_tot, lv), (demo_tot, dm)):
                for k in ("rounds", "wagered", "paid", "wins"):
                    t[k] += add[k]
                for gname, row in add["games"].items():
                    cur = t["games"][gname]
                    for k in row:
                        cur[k] += row[k]
            for k in money_tot:
                money_tot[k] += float(m.get(k, 0) or 0)
            series.append({"day": day["day"], "liveGgr": money(lv["wagered"] - lv["paid"]), "liveWagered": money(lv["wagered"]),
                           "deposits": money(m.get("deposits", 0) or 0), "payouts": money(m.get("payouts", 0) or 0)})

        def finish(t):
            t["ggr"] = money(t["wagered"] - t["paid"])
            t["rtp"] = round(t["paid"] / t["wagered"], 4) if t["wagered"] else None
            t["winRate"] = round(t["wins"] / t["rounds"], 4) if t["rounds"] else None
            for g in t["games"].values():
                g["ggr"] = money(g["wagered"] - g["paid"])
                g["rtp"] = round(g["paid"] / g["wagered"], 4) if g["wagered"] else None
            for k in ("wagered", "paid"):
                t[k] = money(t[k])
            return t

        net_cash = money(money_tot["deposits"] - money_tot["payouts"])
        return {
            "days": days, "currency": self.cfg.live_currency, "live": finish(live_tot), "demo": finish(demo_tot),
            "money": {**{k: money(v) for k, v in money_tot.items()}, "netCash": net_cash},
            "series": series,
            "note": "Live profit (GGR) = money wagered minus money paid back to players. Demo credits are not real money. "
                    "Net cash = deposits minus payouts that were actually sent; funds players still hold are not counted.",
        }

    # ---------------------------------------------------------------- activity

    def activity(self) -> dict:
        now = self.clock()
        total = self.store.count("users")
        seen = {k: self.store.count("users", ("lastSeenAt", ">=", now - timedelta(days=d))) for k, d in (("day", 1), ("week", 7), ("month", self.cfg.active_days))}
        return {
            "total": total, "active24h": seen["day"], "active7d": seen["week"], f"active{self.cfg.active_days}d": seen["month"],
            "activeDays": self.cfg.active_days, "inactive": max(0, total - seen["month"]),
            "stickiness": round(seen["day"] / seen["month"], 3) if seen["month"] else None,
            "note": "Seen = the player opened the app and signed in to the server. Updated at most every few hours per player.",
        }

    def recent_players(self, rows) -> dict:
        """From the newest players already held in memory: who is active, who has gone quiet."""
        cutoff = self.clock() - timedelta(days=self.cfg.active_days)
        active, quiet = [], []
        for uid, d in rows:
            seen = as_utc(d.get("lastSeenAt") or d.get("lastLoginAt"))
            row = {"uid": uid, "name": d.get("displayName"), "email": d.get("email"), "lastSeenAt": _iso(seen)}
            (active if seen and seen >= cutoff else quiet).append(row)
        key = lambda r: r["lastSeenAt"] or ""
        return {"active": sorted(active, key=key, reverse=True)[:30], "quiet": sorted(quiet, key=key, reverse=True)[:30]}

    # ----------------------------------------------------------------- crashes

    def crashes(self, status: str = "") -> list[dict]:
        out = []
        for fp, d in self.crash_watch.rows():
            if status and d.get("status", "open") != status:
                continue
            out.append({"id": fp, "source": d.get("source"), "kind": d.get("kind"), "message": d.get("message"), "stack": d.get("stack"),
                        "platform": d.get("platform"), "appVersion": d.get("appVersion"), "path": d.get("path"), "count": int(d.get("count", 0)),
                        "status": d.get("status", "open"), "firstSeenAt": _iso(d.get("firstSeenAt")), "lastSeenAt": _iso(d.get("lastSeenAt")),
                        "resolvedBy": d.get("resolvedBy")})
        out.sort(key=lambda r: r["lastSeenAt"] or "", reverse=True)
        return out

    def set_crash_status(self, fp: str, status: str, actor: str) -> None:
        if self.store.read(f"crash_groups/{fp}") is None:
            from .errors import ApiError

            raise ApiError(404, "crash_not_found", "No such crash.")
        self.store.merge(f"crash_groups/{fp}", {"status": status, "resolvedBy": actor if status == "resolved" else None})

    # ------------------------------------------------------------- one account

    def account(self, uid: str) -> dict:
        u = self.store.read(f"users/{uid}")
        if u is None:
            from .errors import ApiError

            raise ApiError(404, "user_not_found", "No user with that id.")
        lid = live_uid(uid)
        demo_w, live_w = self.store.read(wallet_path(uid)) or {}, self.store.read(wallet_path(lid)) or {}
        prog = lambda p: {k: (self.store.read(p) or {}).get(k) for k in ("level", "totalRounds", "totalWins", "biggestWin")}
        pays = self.live._mine(uid) if self.live else []
        dep = sum(p["amount"] for p in pays if p["kind"] == "deposit" and p["status"] == "succeeded")
        out = sum(p["amount"] for p in pays if p["kind"] == "payout" and p["status"] == "paid")
        pending = sum(p["amount"] for p in pays if p["kind"] == "payout" and p["status"] in ("pending_review", "processing"))
        events = []
        for a in (self.standing.actions(uid) if self.standing else []):
            events.append({"at": _iso(a["createdAt"]), "kind": "standing", "text": f"{a['type']} ({a['status']}): {a.get('label') or ''}"})
        for p in pays[:30]:
            events.append({"at": _iso(p["createdAt"]), "kind": "money", "text": f"{p['kind']} {p['amount']:g} {p['currency']} via {p['provider']}: {p['status'].replace('_', ' ')}"})
        events.sort(key=lambda e: e["at"] or "", reverse=True)
        pub = self.standing.public(self.standing.summary(uid)) if self.standing else {}
        return {
            "uid": uid, "name": u.get("displayName"), "email": u.get("email"), "anonymous": bool(u.get("isAnonymous")),
            "createdAt": _iso(u.get("createdAt")), "lastLoginAt": _iso(u.get("lastLoginAt")), "lastSeenAt": _iso(u.get("lastSeenAt")),
            "state": pub.get("state"), "activeActions": [a["type"] for a in pub.get("active", [])],
            "demo": {"balance": demo_w.get("balance"), **prog(f"users/{uid}/progress/current")},
            "live": {"balance": live_w.get("balance"), **prog(f"users/{lid}/progress/current")},
            "money": {"deposited": money(dep), "paidOut": money(out), "payoutPending": money(pending), "netToHouse": money(dep - out - float(live_w.get("balance") or 0) - pending),
                      "currency": self.cfg.live_currency},
            "timeline": events[:40],
        }

    # ---------------------------------------------------------------- overview

    def overview(self) -> dict:
        today = self.metrics.daily(1)[0]
        lv = _mode_totals(today, "live")
        pending = 0
        if self.live is not None:
            pending = sum(1 for p in self.live.staff_list("payout", "pending_review", limit=100))
        open_crashes = sum(1 for c in self.crashes("open"))
        return {
            "activity": self.activity(),
            "todayLiveGgr": money(lv["wagered"] - lv["paid"]), "todayLiveWagered": money(lv["wagered"]),
            "pendingPayouts": pending, "openCrashes": open_crashes, "currency": self.cfg.live_currency,
        }

    # --------------------------------------------------------------- dashboard

    ALLTIME_LOOKBACK = 180  # days read the very first time; after that only the new days

    def _closed_days(self) -> dict:
        """Totals of every finished day, kept in one small document and topped up with yesterday's numbers."""
        now = self.clock().replace(hour=0, minute=0, second=0, microsecond=0)
        doc = self.store.read("stats_total/closed") or {}
        through = doc.get("through")
        yesterday = now - timedelta(days=1)
        if through:
            start = as_utc(datetime.strptime(through, "%Y-%m-%d")) + timedelta(days=1)
        else:
            start = now - timedelta(days=self.ALLTIME_LOOKBACK)
        start = max(start, now - timedelta(days=self.ALLTIME_LOOKBACK))
        totals = {"live": doc.get("live") or {}, "demo": doc.get("demo") or {}, "money": doc.get("money") or {}}
        first = doc.get("since")
        day, new = start, False
        while day <= yesterday:
            key = day_key(day)
            d = self.store.read(f"stats_daily/{key}")
            if d:
                _add(totals, {"live": d.get("live") or {}, "demo": d.get("demo") or {}, "money": d.get("money") or {}})
                first = first or key
            day += timedelta(days=1)
            new = True
        if new:
            self.store.merge("stats_total/closed", {**totals, "through": day_key(yesterday), "since": first})
        return {**totals, "since": first}

    def dashboard(self) -> dict:
        now = self.clock()
        days = self.metrics.daily(30)  # oldest first, today last
        today, yday = days[-1], days[-2]
        closed = self._closed_days()
        all_time = _window([{"live": closed["live"], "demo": closed["demo"], "money": closed["money"]}, today])
        windows = {
            "today": _window([today]), "yesterday": _window([yday]),
            "week": _window(days[-7:]), "month": _window(days), "all": all_time,
        }
        series = []
        for d in days:
            lv, dm = _mode_totals(d, "live"), _mode_totals(d, "demo")
            m = d.get("money") or {}
            series.append({"day": d["day"], "ggr": money(lv["wagered"] - lv["paid"]), "wagered": money(lv["wagered"]), "paid": money(lv["paid"]),
                           "rounds": int(lv["rounds"]), "demoRounds": int(dm["rounds"]),
                           "deposits": money(m.get("deposits", 0) or 0), "payouts": money(m.get("payouts", 0) or 0)})
        act = self.activity()
        midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
        new_today = self.store.count("users", ("createdAt", ">=", midnight))
        new_week = self.store.count("users", ("createdAt", ">=", midnight - timedelta(days=6)))
        pending = self.live.staff_list("payout", "pending_review", limit=100) if self.live is not None else []
        crashes_open = sum(1 for _ in self.crashes("open"))
        health = self.metrics.snapshot()
        return {
            "currency": self.cfg.live_currency, "asOf": _iso(now), "since": closed.get("since"),
            "windows": windows, "series": series,
            "players": {**act, "newToday": new_today, "newWeek": new_week},
            "payouts": {"pending": len(pending), "pendingAmount": money(sum(float(p.get("amount") or 0) for p in pending))},
            "health": {"requests": health["requests"], "errorRate": health["errorRate"], "p50": health["p50"], "p95": health["p95"],
                       "uptimeSeconds": health["uptimeSeconds"], "quotaErrors": health["quotaErrors"], "flushFailures": health["flushFailures"],
                       "openCrashes": crashes_open},
            "note": "Live figures are real money. Demo credits are practice and are never counted as profit. Profit (GGR) = wagered minus paid back to players.",
        }
