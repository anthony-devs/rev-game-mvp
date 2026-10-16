"""All tunable numbers in one place. Override with environment variables."""
import os
from dataclasses import dataclass


def _f(name: str, default: float) -> float:
    return float(os.environ.get(name, default))


@dataclass(frozen=True)
class Config:
    # Wallet
    starting_balance: float = _f("STARTING_BALANCE", 10000)
    daily_bonus: float = _f("DAILY_BONUS", 1000)  # day 1 of the streak
    daily_cooldown_seconds: int = int(_f("DAILY_COOLDOWN_SECONDS", 24 * 3600))
    # Reward for each day of a 7 day streak. Miss more than 48h and it starts over.
    daily_rewards: tuple = (1000, 1000, 1500, 2000, 2500, 3000, 10000)
    streak_grace_seconds: int = int(_f("STREAK_GRACE_SECONDS", 48 * 3600))

    # Slots
    slots_bet_steps: tuple = (10, 20, 50, 100, 200, 500, 1000)
    slots_default_bet: float = 100

    # Crash
    crash_min_bet: float = _f("CRASH_MIN_BET", 10)
    crash_max_bet: float = _f("CRASH_MAX_BET", 500000)
    crash_house_edge: float = _f("CRASH_HOUSE_EDGE", 0.03)
    crash_growth_rate: float = _f("CRASH_GROWTH_RATE", 0.12)
    crash_max_multiplier: float = _f("CRASH_MAX_MULTIPLIER", 5000)

    # Dice
    dice_min_bet: float = _f("DICE_MIN_BET", 10)
    dice_max_bet: float = _f("DICE_MAX_BET", 100000)
    dice_house_edge: float = _f("DICE_HOUSE_EDGE", 0.03)

    # Roulette (European, single zero: RTP 97.30%)
    roulette_min_bet: float = _f("ROULETTE_MIN_BET", 10)
    roulette_max_total: float = _f("ROULETTE_MAX_TOTAL", 100000)
    roulette_max_bets: int = 60

    # Blackjack (3:2, dealer stands on all 17s, double on two cards)
    blackjack_min_bet: float = _f("BLACKJACK_MIN_BET", 10)
    blackjack_max_bet: float = _f("BLACKJACK_MAX_BET", 100000)

    # Progress: XP per round is bet / this (at least 1)
    xp_bet_divisor: float = _f("XP_BET_DIVISOR", 10)
