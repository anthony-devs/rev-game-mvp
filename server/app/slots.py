"""Golden Reels: 3 reels, 1 payline. Same outcome table as the app's mock.

RTP = sum(probability * multiplier) = 0.96
"""
from __future__ import annotations

import secrets
import uuid
from dataclasses import dataclass

from .allowance import spend, view as rounds_view
from .config import Config
from .errors import ApiError, bad_request
from .fairness import FairnessService
from .rounds import record_round
from .store import Doc, Store, Txn, is_live
from .wallet import Clock, load_wallet, money, utcnow

SYMBOLS = ["seven", "bar", "bell", "cherry", "diamond"]  # same names as the Dart enum


@dataclass(frozen=True)
class PayRow:
    symbols: tuple
    label: str
    multiplier: int
    probability: float


PAY_ROWS = (
    PayRow(("seven",) * 3, "Seven", 100, 0.0004),
    PayRow(("diamond",) * 3, "Diamond", 50, 0.001),
    PayRow(("bell",) * 3, "Bell", 25, 0.004),
    PayRow(("bar",) * 3, "Bar", 15, 0.008),
    PayRow(("cherry",) * 3, "Cherry", 10, 0.012),
    PayRow(("cherry", "cherry"), "Any 2 cherries", 2, 0.265),
)

RTP = round(sum(r.probability * r.multiplier for r in PAY_ROWS), 6)

# Practice (demo) credits: wins are frequent and even 777 comes up now and then (about 1 spin in 50).
# The same order as PAY_ROWS. Real-money play always uses the printed table above.
DEMO_PAY_ODDS = (0.02, 0.03, 0.05, 0.06, 0.07, 0.30)
BIG_WIN_MULTIPLIER = 50


class SlotsService:
    def __init__(self, store: Store, cfg: Config, clock: Clock = utcnow, rng=None, fair: FairnessService | None = None):
        self.store, self.cfg, self.clock = store, cfg, clock
        self.fair = fair or FairnessService(store, clock, rng_override=rng)

    # ---- config the app shows ------------------------------------------------

    def factor_for(self, uid: str) -> float:
        """How often wins come, relative to the pay table. 1.0 = the table as printed."""
        return self.cfg.live_slots_factor if is_live(uid) else self.cfg.demo_slots_factor

    def demo_for(self, uid: str) -> bool:
        return (not is_live(uid)) and self.cfg.demo_slots_generous

    def config(self, uid: str, balance: float) -> dict:
        steps = list(self.cfg.slots_bet_steps)
        return {
            "minBet": steps[0],
            "maxBet": steps[-1],
            "betSteps": steps,
            "defaultBet": self.cfg.slots_default_bet,
            "startBalance": balance,  # the player's real balance
            "bigWinMultiplier": BIG_WIN_MULTIPLIER,
            "rtp": round(RTP * self.cfg.live_slots_factor, 4) if is_live(uid) else RTP,  # live shows what it really returns
            "payRows": [
                {"symbols": list(r.symbols), "label": r.label, "multiplier": r.multiplier, "probability": 0}
                for r in PAY_ROWS
            ],
        }

    # ---- one spin ------------------------------------------------------------

    def spin(self, uid: str, bet) -> dict:
        bet = self._validate_bet(bet)

        def fn(txn: Txn):
            now = self.clock()
            txn.preload_player(uid)
            wallet = load_wallet(txn, uid, self.cfg, now)
            if wallet["balance"] < bet:
                raise ApiError(402, "insufficient_credits", "Not enough credits for this bet.")
            wallet = spend(wallet, self.cfg, uid, now)

            rng, fair = self.fair.begin(txn, uid, now)
            factor = self.factor_for(uid)
            demo = self.demo_for(uid)
            multiplier, line, label = self._draw(rng, factor, demo)
            payout = money(bet * multiplier)
            after_bet = money(wallet["balance"] - bet)
            balance = money(after_bet + payout)

            txn.set_wallet(uid, {**wallet, "balance": balance, "updatedAt": now})
            round_id = uuid.uuid4().hex
            columns = [[self._any(rng), line[i], self._any(rng)] for i in range(3)]
            record_round(
                txn,
                self.cfg,
                uid,
                round_id,
                game="slots",
                bet=bet,
                payout=payout,
                multiplier=multiplier,
                status="won" if multiplier > 0 else "lost",
                label=label,
                details={"line": line, "multiplier": multiplier, "factor": factor, "demo": demo},
                fair=fair,
                now=now,
            )
            return {
                "roundId": round_id,
                "columns": columns,
                "multiplier": multiplier,
                "payout": payout,
                "balanceAfterBet": after_bet,
                "balance": balance,
                "label": label,
                "fairness": fair,
                "rounds": rounds_view(wallet, self.cfg, uid, now),
            }

        return self.store.run(fn)

    def replay(self, rng, rnd: Doc) -> bool:
        """Fairness check: the same seeds must give the stored line."""
        multiplier, line, _ = self._draw(rng, rnd["details"].get("factor", 1.0), bool(rnd["details"].get("demo")))
        return multiplier == rnd["details"]["multiplier"] and list(line) == list(rnd["details"]["line"])

    # ---- helpers -------------------------------------------------------------

    def _validate_bet(self, bet) -> float:
        if isinstance(bet, bool) or not isinstance(bet, (int, float)):
            raise bad_request("invalid_bet", "Bet must be a number.")
        if bet not in self.cfg.slots_bet_steps:
            raise bad_request("invalid_bet", "That bet amount is not allowed.")
        return float(bet)

    def _any(self, rng) -> str:
        return rng.choice(SYMBOLS)

    def _draw(self, rng=None, factor: float = 1.0, demo: bool = False) -> tuple[int, list[str], str]:
        rng = rng or self.fair.override or secrets.SystemRandom()
        r = rng.random()
        acc = 0.0
        hit = None
        for i, row in enumerate(PAY_ROWS):
            acc += DEMO_PAY_ODDS[i] if demo else row.probability * factor
            if r < acc:
                hit = row
                break
        if hit is None:
            return 0, self._losing_line(rng), "No win"
        if len(hit.symbols) == 3:
            return hit.multiplier, [hit.symbols[0]] * 3, f"3x {hit.label} - pays x{hit.multiplier}"
        return hit.multiplier, self._two_cherries(rng), f"2x Cherry - pays x{hit.multiplier}"

    def _losing_line(self, rng) -> list[str]:
        while True:
            line = [self._any(rng), self._any(rng), self._any(rng)]
            cherries = line.count("cherry")
            triple = line[0] == line[1] == line[2]
            if not triple and cherries != 2:
                return line

    def _two_cherries(self, rng) -> list[str]:
        other = rng.choice([s for s in SYMBOLS if s != "cherry"])
        line = ["cherry", "cherry", other]
        rng.shuffle(line)
        return line
