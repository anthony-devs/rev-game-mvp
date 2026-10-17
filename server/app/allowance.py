"""Rounds: a shared allowance across every game, refilled over time, with extra rounds you can buy.

The counters live in the player's wallet document (the one every round already reads and writes),
so limiting rounds costs no extra database operations.

  rWinStart  when the current window opened (the first round played after the last window ended)
  rUsed      free rounds used in this window
  rExtra     bought rounds still unused (they never expire)
"""
from __future__ import annotations

from datetime import timedelta

from .config import Config
from .errors import ApiError
from .store import Doc, is_live
from .util import as_utc, money


def _setting(cfg: Config, uid: str) -> tuple[int, float]:
    return (cfg.rounds_free_live, cfg.round_price_live) if is_live(uid) else (cfg.rounds_free_demo, cfg.round_price_demo)


def _fresh(wallet: Doc, cfg: Config, now) -> tuple:
    """(window start, used) with an ended window treated as empty."""
    start = as_utc(wallet.get("rWinStart"))
    if start is None or now >= start + timedelta(hours=cfg.rounds_window_hours):
        return None, 0
    return start, int(wallet.get("rUsed", 0) or 0)


def view(wallet: Doc, cfg: Config, uid: str, now) -> dict:
    free, price = _setting(cfg, uid)
    start, used = _fresh(wallet, cfg, now)
    extra = int(wallet.get("rExtra", 0) or 0)
    left_free = max(0, free - used)
    resets = start + timedelta(hours=cfg.rounds_window_hours) if start else None
    return {
        "enabled": cfg.rounds_enabled, "live": is_live(uid), "free": free, "freeLeft": left_free, "extra": extra,
        "available": left_free + extra, "price": price, "packs": list(cfg.round_packs),
        "resetsAt": resets.isoformat() if resets else None,
        "secondsLeft": int((resets - now).total_seconds()) if resets else 0,
        "windowHours": cfg.rounds_window_hours,
    }


def spend(wallet: Doc, cfg: Config, uid: str, now) -> Doc:
    """Use one round (free first, then bought). Raises ``no_rounds`` when there is none left."""
    if not cfg.rounds_enabled:
        return wallet
    free, _price = _setting(cfg, uid)
    start, used = _fresh(wallet, cfg, now)
    extra = int(wallet.get("rExtra", 0) or 0)
    if used < free:
        return {**wallet, "rWinStart": start or now, "rUsed": used + 1, "rExtra": extra}
    if extra > 0:
        return {**wallet, "rWinStart": start, "rUsed": used, "rExtra": extra - 1}
    v = view(wallet, cfg, uid, now)
    raise ApiError(402, "no_rounds", "You have used your free rounds. Wait for them to refresh or buy more rounds.",
                   secondsLeft=v["secondsLeft"], price=v["price"], packs=v["packs"], live=v["live"])


def buy(wallet: Doc, cfg: Config, uid: str, now, size: int, key: str | None) -> tuple[Doc, float]:
    """Buy ``size`` rounds from the wallet balance. The same key twice charges once."""
    if not cfg.rounds_enabled:
        raise ApiError(400, "rounds_off", "Rounds are not limited right now.")
    if size not in cfg.round_packs:
        raise ApiError(400, "bad_pack", "Choose one of the round packs shown.")
    if key and wallet.get("rLastKey") == key:
        return wallet, 0.0  # a retry of a purchase that already went through
    _free, price = _setting(cfg, uid)
    cost = money(size * price)
    if wallet["balance"] < cost:
        raise ApiError(402, "insufficient_credits", "Not enough balance for this pack.")
    out = {**wallet, "balance": money(wallet["balance"] - cost), "rExtra": int(wallet.get("rExtra", 0) or 0) + size,
           "rLastKey": key, "updatedAt": now}
    return out, cost
