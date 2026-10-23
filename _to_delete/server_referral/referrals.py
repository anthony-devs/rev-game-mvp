"""Referrals: every player has a code. A friend who enters it gets round bonuses straight away, and the
player who invited them gets round bonuses once the friend has played a few rounds (so empty sign-ups
earn nothing). Bonuses are rounds only: no cash, so they cannot be farmed for money.

    referral_codes/{code}        {uid}                      look a code up
    users/{uid}.referralCode     the player's own code
    referrals/{friendUid}        {referrer, status, at}     status: joined -> rewarded
    referral_pending/{friendUid} {referrer}                 written by the round that qualified them, paid by process()
    progress.refBy / refDone     set on the friend; refDone once the qualifying round was recorded
"""
from __future__ import annotations

import hashlib
import logging
import time
from datetime import timedelta

from . import boosts
from .config import Config
from .errors import ApiError, bad_request
from .rounds import load_progress
from .store import Store, Txn, progress_path, wallet_path
from .util import Clock, as_utc, utcnow
from .wallet import load_wallet

log = logging.getLogger("referrals")
ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"  # no 0/O/1/I


def _code_for(uid: str, salt: int = 0) -> str:
    h = hashlib.sha256(f"{uid}:{salt}".encode()).digest()
    n = int.from_bytes(h[:8], "big")
    out = ""
    for _ in range(7):
        n, r = divmod(n, len(ALPHABET))
        out += ALPHABET[r]
    return out


class ReferralService:
    def __init__(self, store: Store, cfg: Config, clock: Clock = utcnow):
        self.store, self.cfg, self.clock = store, cfg, clock
        # Rewards are looked for only when something suggests there may be one, never on a timer:
        # every look is a database read, and a once-a-second look used up the whole free daily quota.
        self._dirty = True  # one look at start-up, in case a restart left rewards waiting
        self._due = 0.0
        self._retry_at = 0.0
        self._last_kick = 0.0

    def notify(self, delay: float = 3.0) -> None:
        """A friend just qualified: look for the reward in a few seconds (after that round has finished saving)."""
        self._dirty = True
        self._due = time.monotonic() + delay

    def kick(self, every: float = 60.0) -> None:
        """Someone opened the app: look for waiting rewards, at most once per ``every`` seconds (a safety net)."""
        now = time.monotonic()
        if now - self._last_kick >= every:
            self._last_kick = now
            self.notify(0.0)

    def process_due(self) -> int:
        """Called every second by the worker. Free (no database read) unless a look is due."""
        now = time.monotonic()
        if not self._dirty or now < self._due or now < self._retry_at:
            return 0
        self._dirty = False
        try:
            done = self.process()
        except Exception:
            self._dirty, self._retry_at = True, now + 60  # database trouble: try again in a minute, not every second
            raise
        if done >= 50:
            self._dirty = True  # a full batch: there may be more
        return done

    # ---------------------------------------------------------------- codes
    def code(self, uid: str) -> str:
        user = self.store.read(f"users/{uid}") or {}
        if user.get("referralCode"):
            return user["referralCode"]

        def fn(txn: Txn):
            for salt in range(10):
                code = _code_for(uid, salt)
                row = txn.get(f"referral_codes/{code}")
                if row is None:
                    txn.set(f"referral_codes/{code}", {"uid": uid, "at": self.clock()})
                    txn.set(f"users/{uid}", {**(txn.get(f"users/{uid}") or {}), "referralCode": code})
                    return code
                if row.get("uid") == uid:
                    return code
            raise ApiError(500, "code_failed", "Could not make a code. Try again.")

        return self.store.run(fn)

    def summary(self, uid: str) -> dict:
        code = self.code(uid)
        invited = self.store.count("referrals", ("referrer", "==", uid))
        rewarded = self.store.count("referrals", ("rewardedBy", "==", uid))
        w = self.store.read(wallet_path(uid)) or {}
        user = self.store.read(f"users/{uid}") or {}
        return {
            "enabled": self.cfg.referral_enabled, "code": code,
            "link": f"{self.cfg.public_url}/r/{code}" if self.cfg.public_url else "",
            "friendRounds": self.cfg.referral_friend_rounds, "referrerRounds": self.cfg.referral_referrer_rounds,
            "qualifyRounds": self.cfg.referral_qualify_rounds, "maxRewards": self.cfg.referral_max_rewards,
            "invited": invited, "rewarded": rewarded, "roundsEarned": int(user.get("referralRoundsEarned") or 0),
            "boost": boosts.view(w, self.clock()),
            "canApply": not user.get("referredBy") and self._within_window(user),
        }

    def _within_window(self, user: dict) -> bool:
        made = as_utc(user.get("createdAt"))
        return made is None or self.clock() - made <= timedelta(days=self.cfg.referral_window_days)

    # ---------------------------------------------------------------- apply
    def apply(self, uid: str, code: str) -> dict:
        if not self.cfg.referral_enabled:
            raise ApiError(400, "referrals_off", "Referrals are not available right now.")
        code = "".join(ch for ch in str(code or "").upper() if ch.isalnum())[:12]
        if len(code) < 4:
            raise bad_request("bad_code", "Enter the code your friend shared.")
        row = self.store.read(f"referral_codes/{code}")
        if row is None:
            raise ApiError(404, "code_not_found", "That code doesn't exist. Check it and try again.")
        referrer = row["uid"]
        if referrer == uid:
            raise bad_request("own_code", "You can't use your own code.")
        bonus = self.cfg.referral_friend_rounds

        def fn(txn: Txn):
            now = self.clock()
            user = txn.get(f"users/{uid}") or {}
            if user.get("referredBy"):
                raise ApiError(409, "already_referred", "You've already used a referral code.")
            if not self._within_window(user):
                raise ApiError(400, "too_late", f"Referral codes can only be added in your first {self.cfg.referral_window_days} days.")
            w = load_wallet(txn, uid, self.cfg, now)
            n = int(bonus * boosts.multiplier(w, now))
            w = {**w, "rExtra": int(w.get("rExtra", 0) or 0) + n, "updatedAt": now}
            txn.set_wallet(uid, w)
            p = load_progress(txn, uid)
            p["refBy"], p["refDone"] = referrer, False
            txn.set_progress(uid, p)
            txn.set(f"users/{uid}", {**user, "referredBy": referrer, "referralRoundsEarned": int(user.get("referralRoundsEarned") or 0) + n})
            txn.set(f"referrals/{uid}", {"referrer": referrer, "status": "joined", "at": now})
            return n

        n = self.store.run(fn)
        return {"ok": True, "rounds": n, "message": f"{n} bonus rounds added."}

    # ------------------------------------------------------ pay the inviter
    def process(self, limit: int = 50) -> int:
        """Pays inviters whose friend has now played enough rounds. Safe to repeat."""
        done = 0
        for friend, d in self.store.list("referral_pending", limit=limit):
            referrer = d.get("referrer")
            try:
                self._reward(friend, referrer)
                done += 1
            except Exception:
                log.exception("referral reward failed for %s", friend)
        return done

    def _reward(self, friend: str, referrer: str) -> None:
        bonus = self.cfg.referral_referrer_rounds
        cap = self.cfg.referral_max_rewards

        def fn(txn: Txn):
            ref = txn.get(f"referrals/{friend}")
            if ref is None or ref.get("status") == "rewarded":
                txn.delete(f"referral_pending/{friend}")
                return
            user = txn.get(f"users/{referrer}")
            if user is None:
                txn.delete(f"referral_pending/{friend}")
                return
            now = self.clock()
            if int(user.get("referralRewards") or 0) < cap:
                w = load_wallet(txn, referrer, self.cfg, now)
                n = int(bonus * boosts.multiplier(w, now))
                txn.set_wallet(referrer, {**w, "rExtra": int(w.get("rExtra", 0) or 0) + n, "updatedAt": now})
                txn.set(f"users/{referrer}", {**user, "referralRewards": int(user.get("referralRewards") or 0) + 1,
                                              "referralRoundsEarned": int(user.get("referralRoundsEarned") or 0) + n})
            txn.set(f"referrals/{friend}", {**ref, "status": "rewarded", "rewardedAt": now, "rewardedBy": referrer})
            txn.delete(f"referral_pending/{friend}")

        self.store.run(fn)
