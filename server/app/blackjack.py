"""Blackjack. One deck shuffled per hand, blackjack pays 3 to 2, dealer stands on
every 17, double down on any first two cards. No split, no insurance.

The shuffled deck lives only on the server (``blackjack_rounds``). The app is
shown the dealer's hidden card only when the hand is over.
"""
from __future__ import annotations

import math
import uuid

from .allowance import spend, view as rounds_view
from .config import Config
from .errors import ApiError, bad_request
from .fairness import FairnessService, lock_for
from .rounds import record_round
from .store import Doc, Store, Txn, blackjack_active_path, blackjack_path, is_live
from .wallet import Clock, load_wallet, money, utcnow

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
SUITS = ["S", "H", "D", "C"]
HIDDEN = "??"


def new_deck() -> list[str]:
    return [r + s for s in SUITS for r in RANKS]


def shuffled_deck(rng) -> list[str]:
    deck = new_deck()
    rng.shuffle(deck)
    return deck


def card_value(card: str) -> int:
    rank = card[:-1]
    if rank == "A":
        return 11
    if rank in ("10", "J", "Q", "K"):
        return 10
    return int(rank)


def total(cards: list[str]) -> int:
    t = sum(card_value(c) for c in cards)
    aces = sum(1 for c in cards if c[:-1] == "A")
    while t > 21 and aces:
        t -= 10
        aces -= 1
    return t


def is_blackjack(cards: list[str]) -> bool:
    return len(cards) == 2 and total(cards) == 21


class BlackjackService:
    def __init__(self, store: Store, cfg: Config, clock: Clock = utcnow, rng=None, fair: FairnessService | None = None):
        self.store, self.cfg, self.clock = store, cfg, clock
        self.fair = fair or FairnessService(store, clock, rng_override=rng)

    # ---- start / resume ---------------------------------------------------------

    def active(self, uid: str) -> dict | None:
        ptr = self.store.read(blackjack_active_path(uid))
        if not ptr or not ptr.get("roundId"):
            return None
        rnd = self.store.read(blackjack_path(ptr["roundId"]))
        if rnd is None or rnd["uid"] != uid or rnd["status"] != "player":
            return None
        wallet = self.store.read_wallet(uid) or {"balance": self.cfg.starting_balance}
        return self._public(rnd, wallet["balance"])

    def deal(self, uid: str, bet) -> dict:
        bet = self._validate_bet(bet)
        round_id = uuid.uuid4().hex

        def fn(txn: Txn):
            now = self.clock()
            txn.preload_player(uid)
            wallet = load_wallet(txn, uid, self.cfg, now)

            ptr = txn.get(blackjack_active_path(uid))
            if ptr and ptr.get("roundId"):
                old = txn.get(blackjack_path(ptr["roundId"]))
                if old and old["uid"] == uid and old["status"] == "player":
                    raise ApiError(
                        409,
                        "round_in_progress",
                        "Finish your current hand first.",
                        state=self._public(old, wallet["balance"]),
                    )

            if wallet["balance"] < bet:
                raise ApiError(402, "insufficient_credits", "Not enough credits for this bet.")

            rng, fair = self.fair.begin(txn, uid, now, lock_until=lock_for(now, 3600))
            deck = shuffled_deck(rng)
            rnd = {
                "id": round_id,
                "uid": uid,
                "bet": bet,
                "initialBet": bet,
                "deck": deck,
                "next": 4,
                "player": [deck[0], deck[2]],
                "dealer": [deck[1], deck[3]],
                "status": "player",
                "doubled": False,
                "fair": fair,
                "createdAt": now,
            }
            wallet = spend(wallet, self.cfg, uid, now)
            wallet = {**wallet, "balance": money(wallet["balance"] - bet), "updatedAt": now}
            rounds = rounds_view(wallet, self.cfg, uid, now)

            player_bj, dealer_bj = is_blackjack(rnd["player"]), is_blackjack(rnd["dealer"])
            if player_bj or dealer_bj:
                outcome = "push" if (player_bj and dealer_bj) else ("blackjack" if player_bj else "lose")
                return {**self._finish(txn, uid, round_id, rnd, wallet, now, outcome), "rounds": rounds}

            txn.set_wallet(uid, wallet)
            txn.set(blackjack_path(round_id), rnd)
            txn.set(blackjack_active_path(uid), {"roundId": round_id})
            return {**self._public(rnd, wallet["balance"]), "rounds": rounds}

        return self.store.run(fn)

    # ---- actions ----------------------------------------------------------------

    def act(self, uid: str, round_id: str, action: str) -> dict:
        if action not in ("hit", "stand", "double"):
            raise bad_request("invalid_action", "Unknown action.")

        def fn(txn: Txn):
            now = self.clock()
            rnd = txn.get(blackjack_path(round_id))
            if rnd is None or rnd["uid"] != uid:
                raise ApiError(404, "round_not_found", "Round not found.")
            if rnd["status"] != "player":
                raise ApiError(409, "round_not_active", "This hand is already over.")
            txn.preload_player(uid)
            wallet = load_wallet(txn, uid, self.cfg, now)

            if action == "hit":
                rnd["player"].append(self._draw(rnd))
                t = total(rnd["player"])
                if t > 21:
                    return self._finish(txn, uid, round_id, rnd, wallet, now, "bust")
                if t == 21:
                    return self._dealer_turn(txn, uid, round_id, rnd, wallet, now)
            elif action == "double":
                if len(rnd["player"]) != 2 or rnd["doubled"]:
                    raise bad_request("cannot_double", "You can only double on your first two cards.")
                extra = rnd["initialBet"]
                if wallet["balance"] < extra:
                    raise ApiError(402, "insufficient_credits", "Not enough credits to double.")
                wallet = {**wallet, "balance": money(wallet["balance"] - extra), "updatedAt": now}
                rnd["bet"] = money(rnd["bet"] + extra)
                rnd["doubled"] = True
                rnd["player"].append(self._draw(rnd))
                if total(rnd["player"]) > 21:
                    return self._finish(txn, uid, round_id, rnd, wallet, now, "bust")
                return self._dealer_turn(txn, uid, round_id, rnd, wallet, now)
            else:  # stand
                return self._dealer_turn(txn, uid, round_id, rnd, wallet, now)

            # hit that left the player below 21: hand continues
            txn.set(blackjack_path(round_id), rnd)
            return self._public(rnd, wallet["balance"])

        return self.store.run(fn)

    # ---- internals --------------------------------------------------------------

    @staticmethod
    def _draw(rnd: Doc) -> str:
        card = rnd["deck"][rnd["next"]]
        rnd["next"] += 1
        return card

    def _dealer_turn(self, txn, uid, round_id, rnd, wallet, now):
        while total(rnd["dealer"]) < 17:
            rnd["dealer"].append(self._draw(rnd))
        p, d = total(rnd["player"]), total(rnd["dealer"])
        outcome = "win" if (d > 21 or p > d) else ("push" if p == d else "lose")
        return self._finish(txn, uid, round_id, rnd, wallet, now, outcome)

    def _finish(self, txn: Txn, uid, round_id, rnd, wallet, now, outcome):
        bet = rnd["bet"]
        payout = {
            "blackjack": money(bet * 2.5),
            "win": money(bet * 2),
            "push": money(bet),
            "lose": 0.0,
            "bust": 0.0,
        }[outcome]
        boost = self.cfg.live_win_boost if is_live(uid) else self.cfg.demo_win_boost
        if payout > bet and boost:  # demo pays winnings (above the stake) extra; live can pay less
            payout = money(bet + (payout - bet) * (1 + boost))
        balance = money(wallet["balance"] + payout)
        rnd["status"] = "done"
        p, d = total(rnd["player"]), total(rnd["dealer"])
        label = {
            "blackjack": "Blackjack, pays 3 to 2",
            "win": f"Dealer busts with {d}" if d > 21 else f"You {p}, dealer {d}",
            "push": f"Push at {p}",
            "lose": f"Dealer {d}, you {p}",
            "bust": f"Bust with {p}",
        }[outcome]
        record_round(
            txn,
            self.cfg,
            uid,
            round_id,
            game="blackjack",
            bet=bet,
            payout=payout,
            multiplier=money(payout / bet),
            status="won" if outcome in ("blackjack", "win") else ("push" if outcome == "push" else "lost"),
            label=label,
            details={
                "player": rnd["player"],
                "dealer": rnd["dealer"],
                "outcome": outcome,
                "doubled": rnd["doubled"],
                "dealt": rnd["deck"][: rnd["next"]],
            },
            fair=rnd["fair"],
            now=now,
        )
        txn.set_wallet(uid, {**wallet, "balance": balance, "updatedAt": now})
        txn.set(blackjack_path(round_id), rnd)
        txn.delete(blackjack_active_path(uid))
        self.fair.release(txn, uid)
        result = {"outcome": outcome, "payout": payout, "net": money(payout - bet), "label": label}
        return self._public(rnd, balance, result)

    def _public(self, rnd: Doc, balance: float, result: dict | None = None) -> dict:
        playing = rnd["status"] == "player"
        dealer = [rnd["dealer"][0], HIDDEN] if playing else rnd["dealer"]
        out = {
            "roundId": rnd["id"],
            "status": rnd["status"],
            "bet": rnd["bet"],
            "player": rnd["player"],
            "dealer": dealer,
            "playerTotal": total(rnd["player"]),
            "dealerTotal": total([rnd["dealer"][0]]) if playing else total(rnd["dealer"]),
            "doubled": rnd["doubled"],
            "canDouble": playing and len(rnd["player"]) == 2 and not rnd["doubled"] and balance >= rnd["initialBet"],
            "balance": money(balance),
        }
        if result is not None:
            out["result"] = result
            out["fairness"] = rnd["fair"]
        return out

    def replay(self, rng, rnd: Doc) -> bool:
        dealt = rnd["details"]["dealt"]
        return shuffled_deck(rng)[: len(dealt)] == list(dealt)

    def _validate_bet(self, bet) -> float:
        if isinstance(bet, bool) or not isinstance(bet, (int, float)) or not math.isfinite(bet):
            raise bad_request("invalid_bet", "Bet must be a number.")
        if bet < self.cfg.blackjack_min_bet or bet > self.cfg.blackjack_max_bet:
            raise bad_request(
                "invalid_bet",
                f"Bet must be between {self.cfg.blackjack_min_bet:g} and {self.cfg.blackjack_max_bet:g}.",
            )
        return money(bet)
