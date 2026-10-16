"""European roulette (one zero). RTP 36/37 = 97.30%.

Bets: straight (0-36, pays 35:1), red, black, odd, even, low (1-18),
high (19-36) pay 1:1, dozen (1, 2, 3) pays 2:1. Zero loses every outside bet.
"""
from __future__ import annotations

import math
import uuid

from .config import Config
from .errors import ApiError, bad_request
from .fairness import FairnessService
from .rounds import record_round
from .store import Doc, Store, Txn
from .wallet import Clock, load_wallet, money, utcnow

REDS = frozenset({1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36})

# type -> total return multiplier on a win (stake included)
RETURNS = {"straight": 36, "red": 2, "black": 2, "odd": 2, "even": 2, "low": 2, "high": 2, "dozen": 3}


def color_of(n: int) -> str:
    return "green" if n == 0 else ("red" if n in REDS else "black")


def wins(bet: dict, n: int) -> bool:
    t, v = bet["type"], bet.get("value")
    if t == "straight":
        return n == v
    if n == 0:
        return False
    if t == "red":
        return n in REDS
    if t == "black":
        return n not in REDS
    if t == "odd":
        return n % 2 == 1
    if t == "even":
        return n % 2 == 0
    if t == "low":
        return 1 <= n <= 18
    if t == "high":
        return 19 <= n <= 36
    if t == "dozen":
        return (v - 1) * 12 < n <= v * 12
    return False


def spin_number(rng) -> int:
    return int(rng.random() * 37)


class RouletteService:
    def __init__(self, store: Store, cfg: Config, clock: Clock = utcnow, rng=None, fair: FairnessService | None = None):
        self.store, self.cfg, self.clock = store, cfg, clock
        self.fair = fair or FairnessService(store, clock, rng_override=rng)

    def spin(self, uid: str, bets) -> dict:
        bets = self._validate(bets)
        total = money(sum(b["amount"] for b in bets))

        def fn(txn: Txn):
            now = self.clock()
            wallet = load_wallet(txn, uid, self.cfg, now)
            if wallet["balance"] < total:
                raise ApiError(402, "insufficient_credits", "Not enough credits for these bets.")
            rng, fair = self.fair.begin(txn, uid, now)
            number = spin_number(rng)
            results = []
            payout = 0.0
            for b in bets:
                won = wins(b, number)
                pay = money(b["amount"] * RETURNS[b["type"]]) if won else 0.0
                payout += pay
                results.append({**b, "won": won, "payout": pay})
            payout = money(payout)
            after_bet = money(wallet["balance"] - total)
            balance = money(after_bet + payout)
            txn.set_wallet(uid, {**wallet, "balance": balance, "updatedAt": now})

            round_id = uuid.uuid4().hex
            color = color_of(number)
            record_round(
                txn,
                self.cfg,
                uid,
                round_id,
                game="roulette",
                bet=total,
                payout=payout,
                multiplier=money(payout / total),
                status="won" if payout > total else ("push" if payout == total else "lost"),
                label=f"{number} {color}",
                details={"number": number, "color": color, "bets": results},
                fair=fair,
                now=now,
            )
            return {
                "roundId": round_id,
                "number": number,
                "color": color,
                "totalBet": total,
                "payout": payout,
                "net": money(payout - total),
                "results": results,
                "balanceAfterBet": after_bet,
                "balance": balance,
                "fairness": fair,
            }

        return self.store.run(fn)

    def replay(self, rng, rnd: Doc) -> bool:
        return spin_number(rng) == rnd["details"]["number"]

    def _validate(self, bets) -> list[dict]:
        if not isinstance(bets, list) or not bets:
            raise bad_request("no_bets", "Place at least one bet.")
        if len(bets) > self.cfg.roulette_max_bets:
            raise bad_request("too_many_bets", "Too many bets on the table.")
        out = []
        for b in bets:
            if not isinstance(b, dict):
                raise bad_request("invalid_bet", "Each bet must be an object.")
            t, v, amount = b.get("type"), b.get("value"), b.get("amount")
            if t not in RETURNS:
                raise bad_request("invalid_bet", "Unknown bet type.")
            if isinstance(amount, bool) or not isinstance(amount, (int, float)) or not math.isfinite(amount) or amount <= 0:
                raise bad_request("invalid_bet", "Bet amount must be a positive number.")
            if amount < self.cfg.roulette_min_bet:
                raise bad_request("invalid_bet", f"Minimum bet is {self.cfg.roulette_min_bet:g}.")
            if t == "straight":
                if isinstance(v, bool) or not isinstance(v, int) or not 0 <= v <= 36:
                    raise bad_request("invalid_bet", "Pick a number from 0 to 36.")
            elif t == "dozen":
                if isinstance(v, bool) or not isinstance(v, int) or v not in (1, 2, 3):
                    raise bad_request("invalid_bet", "Pick dozen 1, 2 or 3.")
            else:
                v = None
            out.append({"type": t, "value": v, "amount": money(amount)})
        total = sum(b["amount"] for b in out)
        if total > self.cfg.roulette_max_total:
            raise bad_request("invalid_bet", f"Total bet cannot be above {self.cfg.roulette_max_total:g}.")
        return out
