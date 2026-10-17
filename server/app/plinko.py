"""Plinko. A ball drops through ``rows`` rows of pegs; at every peg it goes left or right with
equal chance, and lands in one of ``rows + 1`` slots. Each slot pays a multiplier.

The path is fixed by the provably fair random numbers (one per row), so the same seeds always
give the same drop. Slot ``i`` is reached by ``i`` right-turns, so its chance is the binomial
``C(rows, i) / 2^rows``. Multiplier tables are built from that exact chance so the return to
player (RTP) is known:

    RTP = sum over slots of  chance(slot) * multiplier(slot)      (house edge = 1 - RTP)

Tables are rounded down to 2 places, so the published RTP can only be at or below the target.
"""
from __future__ import annotations

import math
import uuid
from functools import lru_cache

from .allowance import spend, view as rounds_view
from .config import Config
from .errors import ApiError, bad_request
from .fairness import FairnessService
from .rounds import record_round
from .store import Doc, Store, Txn, is_live
from .wallet import Clock, load_wallet, money, utcnow

ROWS = (8, 10, 12, 14, 16)
RISKS = ("low", "medium", "high")

# (lowest multiplier before scaling, steepness). Higher risk = smaller middle, much bigger edges.
_SHAPE = {"low": (0.5, 2.6), "medium": (0.3, 4.6), "high": (0.1, 7.2)}
_MIN_MULT = 0.2  # no slot ever pays less than 0.2x


def chances(rows: int) -> list[float]:
    return [math.comb(rows, i) / 2**rows for i in range(rows + 1)]


def _build(rows: int, risk: str, rtp: float) -> list[float]:
    floor, steep = _SHAPE[risk]
    mid = rows / 2
    w = [floor + (math.exp(steep * (abs(i - mid) / mid) ** 1.5) - 1) for i in range(rows + 1)]
    p = chances(rows)

    def table(s: float) -> list[float]:
        return [max(_MIN_MULT, math.floor(s * x * 100) / 100) for x in w]

    def value(s: float) -> float:
        return sum(a * b for a, b in zip(table(s), p))

    lo, hi = 0.0, 10.0
    for _ in range(60):  # find the scale whose rounded table returns as close to rtp as possible without exceeding it
        m = (lo + hi) / 2
        if value(m) > rtp:
            hi = m
        else:
            lo = m
    return table(lo)


@lru_cache(maxsize=256)
def _cached(rows: int, risk: str, rtp_key: int) -> tuple[float, ...]:
    return tuple(_build(rows, risk, rtp_key / 1_000_000))


# Practice (demo) boards: every slot pays at least this, except the middle one, which pays less than
# the bet. The ball only lands in the middle about one drop in four, so players win most drops
# but still lose now and then, which is what makes a win feel like luck.
_DEMO_FLOOR = {"low": 1.3, "medium": 1.2, "high": 1.1}
_DEMO_MIDDLE = {"low": 0.7, "medium": 0.5, "high": 0.3}


def multipliers(rows: int, risk: str, edge: float) -> list[float]:
    """The payout for each slot, left to right. A negative ``edge`` is the generous demo table."""
    table = list(_cached(rows, risk, round((1 - edge) * 1_000_000)))
    if edge < 0:
        table = [max(m, _DEMO_FLOOR[risk]) for m in table]
        table[rows // 2] = _DEMO_MIDDLE[risk]
    return table


def rtp_of(table: list[float], rows: int) -> float:
    return round(sum(a * b for a, b in zip(table, chances(rows))), 4)


def path_from(rng, rows: int) -> list[int]:
    """0 = left, 1 = right at each row."""
    return [1 if rng.random() >= 0.5 else 0 for _ in range(rows)]


class PlinkoService:
    def __init__(self, store: Store, cfg: Config, clock: Clock = utcnow, rng=None, fair: FairnessService | None = None):
        self.store, self.cfg, self.clock = store, cfg, clock
        self.fair = fair or FairnessService(store, clock, rng_override=rng)

    def edge_for(self, uid: str) -> float:
        return self.cfg.plinko_house_edge if is_live(uid) else self.cfg.demo_plinko_edge

    def quote(self, uid: str, rows, risk) -> dict:
        rows, risk = self._validate_setup(rows, risk)
        edge = self.edge_for(uid)
        table = multipliers(rows, risk, edge)
        top = max(table)
        # A single drop can never be allowed to pay more than the payout cap.
        max_bet = min(self.cfg.plinko_max_bet, math.floor(self.cfg.plinko_max_payout / top)) if top > 0 else self.cfg.plinko_max_bet
        return {
            "rows": rows,
            "risk": risk,
            "multipliers": table,
            "rtp": rtp_of(table, rows),
            "minBet": self.cfg.plinko_min_bet,
            "maxBet": max(self.cfg.plinko_min_bet, max_bet),
        }

    def drop(self, uid: str, bet, rows, risk) -> dict:
        bet = self._validate_bet(bet)
        q = self.quote(uid, rows, risk)
        if bet > q["maxBet"]:
            raise bad_request("invalid_bet", f"The most you can bet on this setting is {q['maxBet']:g}.")
        table = q["multipliers"]

        def fn(txn: Txn):
            now = self.clock()
            txn.preload_player(uid)
            wallet = load_wallet(txn, uid, self.cfg, now)
            if wallet["balance"] < bet:
                raise ApiError(402, "insufficient_credits", "Not enough credits for this bet.")
            wallet = spend(wallet, self.cfg, uid, now)
            rng, fair = self.fair.begin(txn, uid, now)
            path = path_from(rng, q["rows"])
            slot = sum(path)
            multiplier = table[slot]
            payout = money(bet * multiplier)
            after_bet = money(wallet["balance"] - bet)
            balance = money(after_bet + payout)
            txn.set_wallet(uid, {**wallet, "balance": balance, "updatedAt": now})

            round_id = uuid.uuid4().hex
            record_round(
                txn,
                self.cfg,
                uid,
                round_id,
                game="plinko",
                bet=bet,
                payout=payout,
                multiplier=multiplier,
                status="won" if payout > bet else "lost",
                label=f"Landed in slot {slot + 1}, {multiplier:g}x ({q['risk']}, {q['rows']} rows)",
                details={"rows": q["rows"], "risk": q["risk"], "path": path, "slot": slot, "multiplier": multiplier},
                fair=fair,
                now=now,
            )
            return {
                "roundId": round_id,
                "path": path,
                "slot": slot,
                "multiplier": multiplier,
                "win": payout > bet,
                "payout": payout,
                "balanceAfterBet": after_bet,
                "balance": balance,
                "fairness": fair,
                "rounds": rounds_view(wallet, self.cfg, uid, now),
                **q,
            }

        return self.store.run(fn)

    def replay(self, rng, rnd: Doc) -> bool:
        d = rnd["details"]
        path = path_from(rng, int(d["rows"]))
        return path == list(d["path"]) and sum(path) == d["slot"]

    # ---- validation ------------------------------------------------------------

    def _validate_bet(self, bet) -> float:
        if isinstance(bet, bool) or not isinstance(bet, (int, float)) or not math.isfinite(bet):
            raise bad_request("invalid_bet", "Bet must be a number.")
        if bet < self.cfg.plinko_min_bet or bet > self.cfg.plinko_max_bet:
            raise bad_request("invalid_bet", f"Bet must be between {self.cfg.plinko_min_bet:g} and {self.cfg.plinko_max_bet:g}.")
        return money(bet)

    @staticmethod
    def _validate_setup(rows, risk):
        if isinstance(rows, bool) or not isinstance(rows, (int, float)) or int(rows) != rows or int(rows) not in ROWS:
            raise bad_request("invalid_rows", f"Rows must be one of {', '.join(map(str, ROWS))}.")
        if risk not in RISKS:
            raise bad_request("invalid_risk", "Risk must be low, medium or high.")
        return int(rows), risk
