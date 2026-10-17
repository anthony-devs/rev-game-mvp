"""Wallet rules: daily streak reward, top up, reset. Shared helpers for the games."""
from __future__ import annotations

from datetime import timedelta

from . import allowance
from .config import Config
from .errors import ApiError
from .rounds import load_progress
from .store import Doc, Store, Txn, is_live, wallet_path
from .util import Clock, as_utc as _as_utc, money, utcnow

__all__ = ["WalletService", "load_wallet", "money", "utcnow", "Clock", "_as_utc"]


def load_wallet(txn: Txn, uid: str, cfg: Config, now) -> Doc:
    """The player's wallet, created with the starting credits if missing."""
    w = txn.get_wallet(uid)
    if w is None and is_live(uid):
        w = {"balance": 0.0, "lastDailyClaimAt": None, "updatedAt": now}  # real money starts at zero
    if w is None:
        w = {"balance": cfg.starting_balance, "lastDailyClaimAt": None, "updatedAt": now}
    return w


class WalletService:
    def __init__(self, store: Store, cfg: Config, clock: Clock = utcnow):
        self.store, self.cfg, self.clock = store, cfg, clock
        self.on_money = None  # set by the app: records round-pack revenue for the dashboard

    def get(self, uid: str) -> dict:
        # Fast path: one plain read. Only a brand-new player needs the transaction that creates the wallet.
        doc = self.store.read(wallet_path(uid))
        if doc is not None:
            return self._public(doc, uid)

        def fn(txn: Txn):
            now = self.clock()
            existing = txn.get_wallet(uid)
            w = existing if existing is not None else load_wallet(txn, uid, self.cfg, now)
            if existing is None:
                txn.set_wallet(uid, w)
            return w

        return self._public(self.store.run(fn), uid)

    def claim_daily(self, uid: str) -> dict:
        """One reward per 24h. Claim within 48h of the last one and the streak grows."""

        def fn(txn: Txn):
            now = self.clock()
            w = load_wallet(txn, uid, self.cfg, now)
            last = _as_utc(w.get("lastDailyClaimAt"))
            if last is not None:
                ready = last + timedelta(seconds=self.cfg.daily_cooldown_seconds)
                if now < ready:
                    raise ApiError(
                        429,
                        "daily_not_ready",
                        "Your daily credits are not ready yet.",
                        secondsLeft=int((ready - now).total_seconds()),
                    )

            progress = load_progress(txn, uid)
            keeps_streak = last is not None and (now - last).total_seconds() <= self.cfg.streak_grace_seconds
            streak = progress["streakDays"] + 1 if keeps_streak else 1
            rewards = self.cfg.daily_rewards
            reward = rewards[(streak - 1) % len(rewards)]

            w = {
                **w,
                "balance": money(w["balance"] + reward),
                "lastDailyClaimAt": now,
                "updatedAt": now,
            }
            txn.set_wallet(uid, w)
            progress["streakDays"] = streak
            txn.set_progress(uid, progress)
            return w, reward, streak

        w, reward, streak = self.store.run(fn)
        out = self._public(w, uid)
        out["claimed"] = reward
        out["streakDays"] = streak
        return out

    def top_up(self, uid: str) -> dict:
        """Demo credits: refills to the starting balance, never above it."""

        def fn(txn: Txn):
            now = self.clock()
            existing = txn.get_wallet(uid)
            w = existing if existing is not None else load_wallet(txn, uid, self.cfg, now)
            if w["balance"] < self.cfg.starting_balance:
                w = {**w, "balance": money(self.cfg.starting_balance), "updatedAt": now}
                txn.set_wallet(uid, w)
            elif existing is None:
                txn.set_wallet(uid, w)
            return w

        return self._public(self.store.run(fn), uid)

    def reset(self, uid: str) -> dict:
        """Back to the starting balance (up or down). History and level stay."""

        def fn(txn: Txn):
            now = self.clock()
            w = load_wallet(txn, uid, self.cfg, now)
            w = {**w, "balance": money(self.cfg.starting_balance), "updatedAt": now}
            txn.set_wallet(uid, w)
            return w

        return self._public(self.store.run(fn), uid)

    def buy_rounds(self, uid: str, size, key=None) -> dict:
        """Buy a pack of extra rounds with the wallet balance (credits in demo, money in live)."""
        if isinstance(size, bool) or not isinstance(size, int):
            raise ApiError(400, "bad_pack", "Choose one of the round packs shown.")
        key = str(key)[:64] if key else None

        def fn(txn: Txn):
            now = self.clock()
            w = load_wallet(txn, uid, self.cfg, now)
            w, cost = allowance.buy(w, self.cfg, uid, now, size, key)
            if cost:
                txn.set_wallet(uid, w)
            return w, cost

        w, cost = self.store.run(fn)
        if cost and is_live(uid) and self.on_money is not None:
            self.on_money("roundpack", key or f"{uid}:{w.get('rExtra')}:{w.get('balance')}", cost)
        out = self._public(w, uid)
        out["bought"] = size if cost else 0
        out["charged"] = cost
        return out

    def _public(self, w: Doc, uid: str = "") -> dict:
        last = _as_utc(w.get("lastDailyClaimAt"))
        return {
            "balance": money(w["balance"]),
            "lastDailyClaimAt": last.isoformat() if last else None,
            "rounds": allowance.view(w, self.cfg, uid, self.clock()),
        }
