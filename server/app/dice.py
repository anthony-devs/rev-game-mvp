"""Dice. Roll a number from 0.00 to 99.99, win if it lands on your side of the target.

chance      = how many of the 10,000 possible rolls win
multiplier  = (1 - house edge) * 100 / chance        (rounded down to 4 places)
"""
from __future__ import annotations

import math
import secrets
import uuid

from .allowance import spend, view as rounds_view
from .config import Config
from .errors import ApiError, bad_request
from .fairness import FairnessService
from .rounds import record_round
from .store import Doc, Store, Txn, is_live
from .wallet import Clock, load_wallet, money, utcnow

MIN_TARGET, MAX_TARGET = 10.0, 90.0  # win chance stays between 10% and 90%


def chance_for(target: float, mode: str) -> float:
    """Win chance in percent. Rolls are 0.00 to 99.99, so "over" has 99.99 - target."""
    return round(target if mode == "under" else 99.99 - target, 2)


def multiplier_for(chance: float, edge: float) -> float:
    return math.floor((1 - edge) * 100 / chance * 10000 + 1e-9) / 10000


def roll_from(rng) -> float:
    return math.floor(rng.random() * 10000) / 100


def is_win(roll: float, target: float, mode: str) -> bool:
    return roll < target if mode == "under" else roll > target


class DiceService:
    def __init__(self, store: Store, cfg: Config, clock: Clock = utcnow, rng=None, fair: FairnessService | None = None):
        self.store, self.cfg, self.clock = store, cfg, clock
        self.fair = fair or FairnessService(store, clock, rng_override=rng)

    def edge_for(self, uid: str) -> float:
        return self.cfg.dice_house_edge if is_live(uid) else self.cfg.demo_dice_edge

    def quote(self, target, mode, edge: float | None = None) -> dict:
        target, mode = self._validate_target(target, mode)
        edge = self.cfg.dice_house_edge if edge is None else edge
        chance = chance_for(target, mode)
        return {
            "target": target,
            "mode": mode,
            "chance": chance,
            "multiplier": multiplier_for(chance, edge),
        }

    def roll(self, uid: str, bet, target, mode) -> dict:
        bet = self._validate_bet(bet)
        q = self.quote(target, mode, self.edge_for(uid))

        def fn(txn: Txn):
            now = self.clock()
            txn.preload_player(uid)
            wallet = load_wallet(txn, uid, self.cfg, now)
            if wallet["balance"] < bet:
                raise ApiError(402, "insufficient_credits", "Not enough credits for this bet.")
            wallet = spend(wallet, self.cfg, uid, now)
            rng, fair = self.fair.begin(txn, uid, now)
            roll = roll_from(rng)
            win = is_win(roll, q["target"], q["mode"])
            multiplier = q["multiplier"] if win else 0.0
            payout = money(bet * multiplier)
            after_bet = money(wallet["balance"] - bet)
            balance = money(after_bet + payout)
            txn.set_wallet(uid, {**wallet, "balance": balance, "updatedAt": now})

            round_id = uuid.uuid4().hex
            side = "under" if q["mode"] == "under" else "over"
            record_round(
                txn,
                self.cfg,
                uid,
                round_id,
                game="dice",
                bet=bet,
                payout=payout,
                multiplier=multiplier,
                status="won" if win else "lost",
                label=f"Rolled {roll:.2f}, {side} {q['target']:.2f}",
                details={"roll": roll, "target": q["target"], "mode": q["mode"], "chance": q["chance"], "multiplier": q["multiplier"]},
                fair=fair,
                now=now,
            )
            return {
                "roundId": round_id,
                "roll": roll,
                "win": win,
                "multiplier": multiplier,
                "payout": payout,
                "balanceAfterBet": after_bet,
                "balance": balance,
                "fairness": fair,
                "rounds": rounds_view(wallet, self.cfg, uid, now),
                **q,
            }

        return self.store.run(fn)

    def replay(self, rng, rnd: Doc) -> bool:
        return roll_from(rng) == rnd["details"]["roll"]

    # ---- validation ------------------------------------------------------------

    def _validate_bet(self, bet) -> float:
        if isinstance(bet, bool) or not isinstance(bet, (int, float)) or not math.isfinite(bet):
            raise bad_request("invalid_bet", "Bet must be a number.")
        if bet < self.cfg.dice_min_bet or bet > self.cfg.dice_max_bet:
            raise bad_request(
                "invalid_bet", f"Bet must be between {self.cfg.dice_min_bet:g} and {self.cfg.dice_max_bet:g}."
            )
        return money(bet)

    @staticmethod
    def _validate_target(target, mode):
        if mode not in ("under", "over"):
            raise bad_request("invalid_mode", "Mode must be under or over.")
        if isinstance(target, bool) or not isinstance(target, (int, float)) or not math.isfinite(target):
            raise bad_request("invalid_target", "Target must be a number.")
        target = round(float(target), 2)
        if target < MIN_TARGET or target > MAX_TARGET:
            raise bad_request("invalid_target", f"Target must be between {MIN_TARGET:g} and {MAX_TARGET:g}.")
        return target, mode
