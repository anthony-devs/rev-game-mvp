"""Dash Crash. The server picks the crash point and never sends it early.

Flow
  1. POST /crash/rounds        bet is taken, crash point stored (secret).
  2. GET  .../events (stream)  server tells the app when it crashed or hit auto cash out.
  3. POST .../cashout          pays out at the server's own clock, or says too late.

The multiplier at time t is exp(growth * t). The app draws the same curve
locally; the server clock decides every payout.
"""
from __future__ import annotations

import math
import secrets
import time
import uuid
from datetime import datetime
from typing import Iterator

from .allowance import spend, view as rounds_view
from .config import Config
from .errors import ApiError, bad_request
from .fairness import FairnessService, lock_for
from .rounds import record_round
from .store import Doc, Store, Txn, is_live
from .wallet import Clock, _as_utc, load_wallet, money, utcnow


class CrashService:
    def __init__(
        self,
        store: Store,
        cfg: Config,
        clock: Clock = utcnow,
        rng=None,
        sleep=time.sleep,
        fair: FairnessService | None = None,
    ):
        self.store, self.cfg, self.clock = store, cfg, clock
        self.fair = fair or FairnessService(store, clock, rng_override=rng)
        self.sleep = sleep

    # ---- maths ---------------------------------------------------------------

    def multiplier_at(self, seconds: float) -> float:
        return math.exp(self.cfg.crash_growth_rate * max(seconds, 0.0))

    def seconds_to(self, multiplier: float) -> float:
        return math.log(multiplier) / self.cfg.crash_growth_rate

    def edge_for(self, uid: str) -> float:
        return self.cfg.crash_house_edge if is_live(uid) else self.cfg.demo_crash_edge

    def draw_crash_point(self, rng=None, edge: float | None = None) -> float:
        rng = rng or self.fair.override or secrets.SystemRandom()
        r = rng.random()
        edge = self.cfg.crash_house_edge if edge is None else edge
        raw = math.floor(100 * (1 - edge) / (1 - r)) / 100
        return min(max(raw, 1.0), self.cfg.crash_max_multiplier)

    @staticmethod
    def floor2(value: float) -> float:
        return math.floor(value * 100 + 1e-9) / 100

    # ---- start ---------------------------------------------------------------

    def start(self, uid: str, bet, auto_cashout=None) -> dict:
        bet = self._validate_bet(bet)
        auto = self._validate_auto(auto_cashout)
        round_id = uuid.uuid4().hex

        def fn(txn: Txn):
            now = self.clock()
            txn.preload_player(uid)
            wallet = load_wallet(txn, uid, self.cfg, now)
            if wallet["balance"] < bet:
                raise ApiError(402, "insufficient_credits", "Not enough credits for this bet.")
            wallet = spend(wallet, self.cfg, uid, now)
            balance = money(wallet["balance"] - bet)
            txn.set_wallet(uid, {**wallet, "balance": balance, "updatedAt": now})
            nonlocal rounds
            rounds = rounds_view(wallet, self.cfg, uid, now)
            # Peek at the nonce first so the seed stays locked until this round is over.
            rng, fair = self.fair.begin(txn, uid, now, lock_until=lock_for(now, 120))
            edge = self.edge_for(uid)
            crash_point = self.draw_crash_point(rng, edge)
            txn.set_crash(
                round_id,
                {
                    "uid": uid,
                    "bet": bet,
                    "auto": auto,
                    "crashPoint": crash_point,
                    "edge": edge,
                    "startedAt": now,
                    "startBalance": balance,
                    "status": "running",
                    "fair": fair,
                },
            )
            return balance

        rounds: dict = {}
        balance = self.store.run(fn)
        return {
            "roundId": round_id,
            "rounds": rounds,
            "balance": balance,
            "growthRate": self.cfg.crash_growth_rate,
            "serverTime": self.clock().isoformat(),
        }

    # ---- cash out ------------------------------------------------------------

    def cash_out(self, uid: str, round_id: str, received_at=None) -> dict:
        result = self.settle(uid, round_id, received_at)
        if result["status"] == "crashed":
            raise ApiError(
                409, "too_late", "The round already crashed.", crashPoint=result["crashPoint"], balance=result["balance"]
            )
        if result["status"] == "already":
            raise ApiError(409, "already_settled", "This round is already settled.", balance=result["balance"])
        return {"multiplier": result["multiplier"], "payout": result["payout"], "balance": result["balance"]}

    def settle(self, uid: str, round_id: str, received_at=None) -> dict:
        """Atomically settle a running round using the server clock.

        status is one of: cashedOut, crashed, already (settled by someone else).
        An auto cash out target that was reached before the crash always pays,
        even if this call arrives late.

        ``received_at`` is when the request reached the server. Slow database calls between arrival and
        this transaction must not cost the player their cash out, so the multiplier is the one at arrival.
        """

        def fn(txn: Txn):
            now = self.clock()
            at_time = min(received_at, now) if received_at is not None else now
            txn.preload_player(uid)
            rnd = txn.get_crash(round_id)
            if rnd is None or rnd["uid"] != uid:
                raise ApiError(404, "round_not_found", "Round not found.")
            wallet = load_wallet(txn, uid, self.cfg, now)

            if rnd["status"] != "running":
                return {"status": "already", "balance": money(wallet["balance"])}

            elapsed = (at_time - _as_utc(rnd["startedAt"])).total_seconds()
            m_now = self.floor2(self.multiplier_at(elapsed))
            crash_point = rnd["crashPoint"]
            auto = rnd.get("auto")

            if auto is not None and auto < crash_point and m_now >= auto:
                at = auto  # target reached before the crash
            elif m_now >= crash_point:
                txn.set_crash(round_id, {**rnd, "status": "crashed"})
                self.fair.release(txn, uid)  # the round is over: the fairness check may go ahead
                self._log_round(txn, uid, round_id, rnd, payout=0.0, multiplier=crash_point, outcome="crashed", now=now)
                return {"status": "crashed", "crashPoint": crash_point, "balance": money(wallet["balance"])}
            else:
                at = m_now

            payout = money(rnd["bet"] * at)
            balance = money(wallet["balance"] + payout)
            txn.set_wallet(uid, {**wallet, "balance": balance, "updatedAt": now})
            txn.set_crash(round_id, {**rnd, "status": "cashedOut", "cashedAt": at, "payout": payout})
            self.fair.release(txn, uid)
            self._log_round(txn, uid, round_id, rnd, payout=payout, multiplier=at, outcome="cashedOut", now=now)
            return {"status": "cashedOut", "multiplier": at, "payout": payout, "balance": balance}

        return self.store.run(fn)

    def _log_round(self, txn: Txn, uid, round_id, rnd: Doc, payout, multiplier, outcome, now):
        cashed = outcome == "cashedOut"
        record_round(
            txn,
            self.cfg,
            uid,
            round_id,
            game="crash",
            bet=rnd["bet"],
            payout=payout,
            multiplier=multiplier,
            status="cashedOut" if cashed else "lost",
            label=f"Cashed out at {multiplier:.2f}x" if cashed else f"Busted at {multiplier:.2f}x",
            details={"crashPoint": rnd["crashPoint"], "edge": rnd.get("edge"), "auto": rnd.get("auto"), "cashedAt": multiplier if cashed else None},
            fair=rnd.get("fair") or {},
            now=now,
        )

    def replay(self, rng, rnd: Doc) -> bool:
        """Fairness check: the same seeds must give the stored crash point."""
        return self.draw_crash_point(rng, rnd["details"].get("edge")) == rnd["details"]["crashPoint"]

    # ---- event stream --------------------------------------------------------

    def events(self, uid: str, round_id: str) -> Iterator[str]:
        """Server-sent events until the round ends. Yields ready-to-send text."""
        rnd = self.store.read_crash(round_id)
        if rnd is None or rnd["uid"] != uid:
            raise ApiError(404, "round_not_found", "Round not found.")

        started = _as_utc(rnd["startedAt"])
        crash_at = self.seconds_to(rnd["crashPoint"]) if rnd["crashPoint"] > 1 else 0.0
        auto = rnd.get("auto")
        auto_at = self.seconds_to(auto) if auto and auto < rnd["crashPoint"] else None
        auto_done = False
        known_balance = rnd.get("startBalance")
        last_beat = 0.0

        yield sse("open", {"roundId": round_id})
        while True:
            elapsed = (self.clock() - started).total_seconds()

            if auto_at is not None and not auto_done and elapsed >= auto_at:
                auto_done = True
                res = self.settle(uid, round_id)
                if res["status"] == "cashedOut":
                    known_balance = res["balance"]
                    yield sse("cashedOut", {k: res[k] for k in ("multiplier", "payout", "balance")})

            if elapsed >= crash_at:
                # Tell the app straight away: the screen must stop the moment the round crashes, however slow the
                # database is. Nothing here waits for it (the balance after the bet is already in the round).
                balance = known_balance
                if balance is None:
                    balance = (self.store.read_wallet(uid) or {"balance": 0})["balance"]
                yield sse("crashed", {"crashPoint": rnd["crashPoint"], "balance": money(balance)})
                # A cash out sent just before the crash may still be on its way. Give it a moment, then close the round.
                self.sleep(self.cfg.crash_settle_grace_seconds)
                if (self.store.read_crash(round_id) or {}).get("status") == "running":
                    self.settle(uid, round_id)  # marks it crashed
                return

            if elapsed - last_beat >= 1.0:
                last_beat = elapsed
                yield ": ping\n\n"  # keeps proxies from closing the stream
            self.sleep(min(0.05, max(crash_at - elapsed, 0.001)))

    # ---- validation ----------------------------------------------------------

    def _validate_bet(self, bet) -> float:
        if isinstance(bet, bool) or not isinstance(bet, (int, float)) or not math.isfinite(bet):
            raise bad_request("invalid_bet", "Bet must be a number.")
        if bet < self.cfg.crash_min_bet or bet > self.cfg.crash_max_bet:
            raise bad_request(
                "invalid_bet",
                f"Bet must be between {self.cfg.crash_min_bet:g} and {self.cfg.crash_max_bet:g}.",
            )
        return money(bet)

    @staticmethod
    def _validate_auto(auto):
        if auto is None:
            return None
        if isinstance(auto, bool) or not isinstance(auto, (int, float)) or not math.isfinite(auto):
            raise bad_request("invalid_auto", "Auto cash out must be a number.")
        if auto < 1.1 or auto > 100:
            raise bad_request("invalid_auto", "Auto cash out must be between 1.1 and 100.")
        return round(float(auto), 2)


def sse(event: str, data: dict) -> str:
    import json

    return f"event: {event}\ndata: {json.dumps(data)}\n\n"
