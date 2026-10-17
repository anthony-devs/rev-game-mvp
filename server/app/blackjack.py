"""Blackjack. One deck shuffled per hand, blackjack pays 3 to 2, dealer stands on
every 17, double down on any first two cards, split a pair once (split aces get one
card each). No insurance.

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


def _norm(rnd: Doc) -> Doc:
    """Hands saved before splitting existed have a single ``player`` list."""
    if "hands" not in rnd:
        rnd["hands"] = [{"cards": rnd.get("player", []), "bet": rnd.get("bet", rnd.get("initialBet", 0)), "doubled": bool(rnd.get("doubled"))}]
        rnd["active"] = 0
    return rnd


def _can_split(rnd: Doc) -> bool:
    """One split per hand, on a pair of the same rank, as the first move."""
    hands = rnd["hands"]
    if len(hands) != 1 or hands[0]["doubled"] or len(hands[0]["cards"]) != 2:
        return False
    a, b = hands[0]["cards"]
    return a[:-1] == b[:-1]


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
                "initialBet": bet,
                "deck": deck,
                "next": 4,
                "hands": [{"cards": [deck[0], deck[2]], "bet": bet, "doubled": False}],
                "active": 0,
                "dealer": [deck[1], deck[3]],
                "status": "player",
                "fair": fair,
                "createdAt": now,
            }
            wallet = spend(wallet, self.cfg, uid, now)
            wallet = {**wallet, "balance": money(wallet["balance"] - bet), "updatedAt": now}
            rounds = rounds_view(wallet, self.cfg, uid, now)

            player_bj, dealer_bj = is_blackjack(rnd["hands"][0]["cards"]), is_blackjack(rnd["dealer"])
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
        if action not in ("hit", "stand", "double", "split"):
            raise bad_request("invalid_action", "Unknown action.")

        def fn(txn: Txn):
            now = self.clock()
            rnd = txn.get(blackjack_path(round_id))
            if rnd is None or rnd["uid"] != uid:
                raise ApiError(404, "round_not_found", "Round not found.")
            if rnd["status"] != "player":
                raise ApiError(409, "round_not_active", "This hand is already over.")
            rnd = _norm(rnd)
            txn.preload_player(uid)
            wallet = load_wallet(txn, uid, self.cfg, now)
            hand = rnd["hands"][rnd["active"]]

            if action == "split":
                if not _can_split(rnd):
                    raise bad_request("cannot_split", "You can only split a pair on your first move.")
                extra = rnd["initialBet"]
                if wallet["balance"] < extra:
                    raise ApiError(402, "insufficient_credits", "Not enough credits to split.")
                wallet = {**wallet, "balance": money(wallet["balance"] - extra), "updatedAt": now}
                a, b = hand["cards"]
                aces = a[:-1] == "A"
                first = {"cards": [a, self._draw(rnd)], "bet": rnd["initialBet"], "doubled": False}
                second = {"cards": [b, self._draw(rnd)], "bet": rnd["initialBet"], "doubled": False}
                rnd["hands"] = [first, second]
                rnd["active"] = 0
                rnd["split"] = True
                if aces:  # split aces get one card each and no more play
                    return self._dealer_turn(txn, uid, round_id, rnd, wallet, now)
                if total(first["cards"]) >= 21:  # first hand already has 21: on to the next
                    return self._advance(txn, uid, round_id, rnd, wallet, now)
                txn.set_wallet(uid, wallet)
                txn.set(blackjack_path(round_id), rnd)
                return self._public(rnd, wallet["balance"])

            if action == "hit":
                hand["cards"].append(self._draw(rnd))
                if total(hand["cards"]) >= 21:
                    return self._advance(txn, uid, round_id, rnd, wallet, now)
            elif action == "double":
                if len(hand["cards"]) != 2 or hand["doubled"]:
                    raise bad_request("cannot_double", "You can only double on your first two cards.")
                extra = rnd["initialBet"]
                if wallet["balance"] < extra:
                    raise ApiError(402, "insufficient_credits", "Not enough credits to double.")
                wallet = {**wallet, "balance": money(wallet["balance"] - extra), "updatedAt": now}
                hand["bet"] = money(hand["bet"] + extra)
                hand["doubled"] = True
                hand["cards"].append(self._draw(rnd))
                return self._advance(txn, uid, round_id, rnd, wallet, now)
            else:  # stand
                return self._advance(txn, uid, round_id, rnd, wallet, now)

            # hit that left the hand below 21: it continues
            txn.set(blackjack_path(round_id), rnd)
            return self._public(rnd, wallet["balance"])

        return self.store.run(fn)

    # ---- internals --------------------------------------------------------------

    @staticmethod
    def _draw(rnd: Doc) -> str:
        card = rnd["deck"][rnd["next"]]
        rnd["next"] += 1
        return card

    def _advance(self, txn, uid, round_id, rnd, wallet, now):
        """The active hand is finished: move to the next hand, or let the dealer play."""
        if rnd["active"] + 1 < len(rnd["hands"]):
            rnd["active"] += 1
            nxt = rnd["hands"][rnd["active"]]
            if total(nxt["cards"]) >= 21:  # dealt 21 on the second hand: nothing to decide
                return self._advance(txn, uid, round_id, rnd, wallet, now)
            txn.set_wallet(uid, wallet)
            txn.set(blackjack_path(round_id), rnd)
            return self._public(rnd, wallet["balance"])
        return self._dealer_turn(txn, uid, round_id, rnd, wallet, now)

    def _dealer_turn(self, txn, uid, round_id, rnd, wallet, now):
        hands = rnd["hands"]
        if any(total(h["cards"]) <= 21 for h in hands):
            while total(rnd["dealer"]) < 17:
                rnd["dealer"].append(self._draw(rnd))
        d = total(rnd["dealer"])
        split = len(hands) > 1
        outcomes = []
        for h in hands:
            p = total(h["cards"])
            if p > 21:
                outcomes.append("bust")
            elif d > 21 or p > d:
                outcomes.append("win")
            elif p == d:
                outcomes.append("push")
            else:
                outcomes.append("lose")
        if not split:
            return self._finish(txn, uid, round_id, rnd, wallet, now, outcomes[0])
        return self._finish(txn, uid, round_id, rnd, wallet, now, None, outcomes)

    def _finish(self, txn: Txn, uid, round_id, rnd, wallet, now, outcome, outcomes=None):
        hands = rnd["hands"]
        rate = {"blackjack": 2.5, "win": 2.0, "push": 1.0, "lose": 0.0, "bust": 0.0}
        if outcomes is None:
            outcomes = [outcome]
        bet = money(sum(h["bet"] for h in hands))
        payout = money(sum(h["bet"] * rate[o] for h, o in zip(hands, outcomes)))
        if outcome is None:  # split: summarise
            outcome = "win" if payout > bet else ("push" if payout == bet else "lose")
        boost = self.cfg.live_win_boost if is_live(uid) else self.cfg.demo_win_boost
        if payout > bet and boost:  # demo pays winnings (above the stake) extra; live can pay less
            payout = money(bet + (payout - bet) * (1 + boost))
        balance = money(wallet["balance"] + payout)
        rnd["status"] = "done"
        rnd["outcomes"] = outcomes
        d = total(rnd["dealer"])
        if len(hands) == 1:
            p = total(hands[0]["cards"])
            label = {
                "blackjack": "Blackjack, pays 3 to 2",
                "win": f"Dealer busts with {d}" if d > 21 else f"You {p}, dealer {d}",
                "push": f"Push at {p}",
                "lose": f"Dealer {d}, you {p}",
                "bust": f"Bust with {p}",
            }[outcomes[0]]
        else:
            word = {"win": "won", "push": "push", "lose": "lost", "bust": "bust", "blackjack": "won"}
            label = "Split: " + ", ".join(f"hand {i + 1} {word[o]}" for i, o in enumerate(outcomes))
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
                "player": hands[0]["cards"],
                "hands": [h["cards"] for h in hands],
                "dealer": rnd["dealer"],
                "outcome": outcome,
                "outcomes": outcomes,
                "doubled": any(h["doubled"] for h in hands),
                "split": len(hands) > 1,
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
        rnd = _norm(rnd)
        playing = rnd["status"] == "player"
        dealer = [rnd["dealer"][0], HIDDEN] if playing else rnd["dealer"]
        hands = rnd["hands"]
        active = hands[rnd["active"]]
        outcomes = rnd.get("outcomes") or [None] * len(hands)
        out = {
            "roundId": rnd["id"],
            "status": rnd["status"],
            "bet": money(sum(h["bet"] for h in hands)),
            "player": active["cards"],
            "dealer": dealer,
            "playerTotal": total(active["cards"]),
            "dealerTotal": total([rnd["dealer"][0]]) if playing else total(rnd["dealer"]),
            "doubled": any(h["doubled"] for h in hands),
            "canDouble": playing and len(active["cards"]) == 2 and not active["doubled"] and balance >= rnd["initialBet"],
            "canSplit": playing and _can_split(rnd) and balance >= rnd["initialBet"],
            "split": len(hands) > 1,
            "active": rnd["active"],
            "hands": [
                {"cards": h["cards"], "total": total(h["cards"]), "bet": h["bet"], "doubled": h["doubled"], "outcome": o}
                for h, o in zip(hands, outcomes)
            ],
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
