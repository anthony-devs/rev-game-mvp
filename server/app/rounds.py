"""Settling a round: history entry, XP, level and player stats.

Every game calls ``record_round`` inside the same transaction that moves the
money, so history, progress and wallet never disagree.
"""
from __future__ import annotations

from datetime import datetime

from .config import Config
from .store import Doc, Txn
from .util import money


def xp_for_next(level: int) -> int:
    """XP needed to leave this level. Level 7 needs 2,000."""
    return 500 + 250 * (level - 1)


def default_progress() -> Doc:
    return {
        "level": 1,
        "xp": 0,
        "xpForNext": xp_for_next(1),
        "streakDays": 0,
        "totalRounds": 0,
        "totalWins": 0,
        "biggestWin": 0.0,
        "bestMultiplier": 0.0,
        "lastPlayedAt": None,
    }


def load_progress(txn: Txn, uid: str) -> Doc:
    return {**default_progress(), **(txn.get_progress(uid) or {})}


def record_round(
    txn: Txn,
    cfg: Config,
    uid: str,
    round_id: str,
    *,
    game: str,
    bet: float,
    payout: float,
    multiplier: float,
    status: str,  # won | lost | cashedOut | push
    label: str,
    details: dict,
    fair: dict,
    now: datetime,
    progress: Doc | None = None,
) -> Doc:
    """Writes the history entry and updates progress. Returns the new progress."""
    bet, payout = money(bet), money(payout)
    txn.add_round(
        uid,
        round_id,
        {
            "game": game,
            "bet": bet,
            "payout": payout,
            "net": money(payout - bet),
            "multiplier": multiplier,
            "status": status,
            "label": label,
            "details": details,
            "fairness": fair,
            "createdAt": now,
            "settledAt": now,
        },
    )

    p = progress if progress is not None else load_progress(txn, uid)
    p["totalRounds"] += 1
    if payout > bet:
        p["totalWins"] += 1
        p["biggestWin"] = max(float(p["biggestWin"]), money(payout - bet))
        p["bestMultiplier"] = max(float(p["bestMultiplier"]), float(multiplier))
    p["xp"] += max(1, int(bet // cfg.xp_bet_divisor))
    while p["xp"] >= p["xpForNext"]:
        p["xp"] -= p["xpForNext"]
        p["level"] += 1
        p["xpForNext"] = xp_for_next(p["level"])
    p["lastPlayedAt"] = now
    txn.set_progress(uid, p)
    return p
