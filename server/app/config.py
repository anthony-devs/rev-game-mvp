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
    crash_house_edge: float = _f("CRASH_HOUSE_EDGE", 0.05)  # live; demo uses demo_crash_edge
    crash_growth_rate: float = _f("CRASH_GROWTH_RATE", 0.12)
    crash_max_multiplier: float = _f("CRASH_MAX_MULTIPLIER", 5000)

    # Dice
    dice_min_bet: float = _f("DICE_MIN_BET", 10)
    dice_max_bet: float = _f("DICE_MAX_BET", 100000)
    dice_house_edge: float = _f("DICE_HOUSE_EDGE", 0.05)

    # Roulette (European, single zero: RTP 97.30%)
    roulette_min_bet: float = _f("ROULETTE_MIN_BET", 10)
    roulette_max_total: float = _f("ROULETTE_MAX_TOTAL", 100000)
    roulette_max_bets: int = 60

    # Blackjack (3:2, dealer stands on all 17s, double on two cards)
    blackjack_min_bet: float = _f("BLACKJACK_MIN_BET", 10)
    blackjack_max_bet: float = _f("BLACKJACK_MAX_BET", 100000)

    # Progress: XP per round is bet / this (at least 1)
    xp_bet_divisor: float = _f("XP_BET_DIVISOR", 10)

    # Account standing (bans, suspensions, restrictions, investigations)
    admin_key: str = os.environ.get("ADMIN_KEY", "")  # empty = admin dashboard disabled
    slow_ms: float = _f("SLOW_REQUEST_MS", 800)  # log a warning for requests slower than this
    # How long the server may reuse a player's standing between requests (a ban takes effect within this many seconds).
    catalog_cache_seconds: float = _f("CATALOG_CACHE_SECONDS", 20)  # how long the game list is reused
    standing_cache_seconds: float = _f("STANDING_CACHE_SECONDS", 15)
    probation_hours: int = int(_f("PROBATION_HOURS", 72))  # after a suspension / restriction ends
    probation_max_bet: float = _f("PROBATION_MAX_BET", 1000)
    appeal_cooldown_hours: int = int(_f("APPEAL_COOLDOWN_HOURS", 24))
    risk_window_days: int = int(_f("RISK_WINDOW_DAYS", 3))  # "restricted in the past N days"

    # Staff accounts. The admin login lives in the environment, never in the database.
    admin_username: str = os.environ.get("ADMIN_USERNAME", "")  # not "admin" / "rev-admin"
    admin_password: str = os.environ.get("ADMIN_PASSWORD", "")  # or ADMIN_PASSWORD_HASH (see manage.py)
    admin_password_hash: str = os.environ.get("ADMIN_PASSWORD_HASH", "")
    session_secret: str = os.environ.get("SESSION_SECRET", "")  # signs staff sessions; set it in production
    session_hours: float = _f("STAFF_SESSION_HOURS", 8)
    login_max_fails: int = int(_f("LOGIN_MAX_FAILS", 5))
    login_lock_minutes: int = int(_f("LOGIN_LOCK_MINUTES", 15))

    # Attachments (appeals and support)
    storage_bucket: str = os.environ.get("FIREBASE_STORAGE_BUCKET", "")  # empty = save to UPLOAD_DIR
    upload_dir: str = os.environ.get("UPLOAD_DIR", "")
    upload_max_mb: float = _f("UPLOAD_MAX_MB", 25)
    upload_max_files: int = int(_f("UPLOAD_MAX_FILES", 5))  # per message or appeal
    upload_daily_limit: int = int(_f("UPLOAD_DAILY_LIMIT", 40))

    # Support
    max_open_tickets: int = int(_f("MAX_OPEN_TICKETS", 5))

    # Odds by mode. Live (real money) uses the numbers above and below. Demo credits are made
    # deliberately generous so a new player wins often. Provable fairness is unchanged: the
    # random outcome is the same, only what a win pays (or how often the slot hits) differs.
    # Many regulators require free-play to mirror live odds. Set these to the live values
    # (dice 0.05, crash 0.05, slots 0.96, boost 0) before launching in such a market.
    demo_dice_edge: float = _f("DEMO_DICE_EDGE", -0.15)  # negative = the player has the edge (115% back)
    demo_crash_edge: float = _f("DEMO_CRASH_EDGE", -0.15)  # a round never busts below 1.15x
    demo_slots_factor: float = _f("DEMO_SLOTS_FACTOR", 1.5)  # slot wins come 1.5x as often
    live_slots_factor: float = _f("LIVE_SLOTS_FACTOR", 0.96)  # live slot wins come a little less often
    demo_win_boost: float = _f("DEMO_WIN_BOOST", 0.4)  # roulette / blackjack winnings pay 40% extra

    # Live (real money) play. Amounts are in LIVE_CURRENCY; 1 credit in live mode = 1 unit of it.
    live_enabled: bool = os.environ.get("LIVE_ENABLED", "1").lower() in ("1", "true", "yes")
    live_currency: str = os.environ.get("LIVE_CURRENCY", "NGN").upper()
    live_min_deposit: float = _f("LIVE_MIN_DEPOSIT", 500)
    live_max_deposit: float = _f("LIVE_MAX_DEPOSIT", 500000)
    live_min_payout: float = _f("LIVE_MIN_PAYOUT", 1000)
    live_max_payout: float = _f("LIVE_MAX_PAYOUT", 1000000)
    live_max_open_payouts: int = int(_f("LIVE_MAX_OPEN_PAYOUTS", 3))  # waiting for review at once
    # "mock" = fake gateways for development. Real gateways need their own keys (see providers.py).
    payments_mode: str = os.environ.get("PAYMENTS_MODE", "mock").lower()
    # Safety: never run the fake gateways on Cloud Run unless this is set on purpose.
    allow_mock_in_cloud: bool = os.environ.get("ALLOW_MOCK_PAYMENTS", "0") in ("1", "true", "yes")
    webhook_secret: str = os.environ.get("PAYMENT_WEBHOOK_SECRET", "dev-webhook-secret")


    # Email (founder dashboard). No SMTP_HOST = mock mode: messages are logged, nothing is sent.
    smtp_host: str = os.environ.get("SMTP_HOST", "")
    smtp_port: int = int(_f("SMTP_PORT", 587))
    smtp_user: str = os.environ.get("SMTP_USER", "")
    smtp_password: str = os.environ.get("SMTP_PASSWORD", "")
    mail_from: str = os.environ.get("MAIL_FROM", "REV Games <no-reply@example.com>")
    campaign_max_recipients: int = int(_f("CAMPAIGN_MAX_RECIPIENTS", 1000))
    active_days: int = int(_f("ACTIVE_DAYS", 30))  # "active" = seen in this many days

    # Developer console link. Off unless DEV_API_SECRET is set (32+ characters). Requests must be
    # signed with it, so the console is the only thing that can call /internal/dev/*.
    dev_api_secret: str = os.environ.get("DEV_API_SECRET", "")
    dev_allowed_ips: str = os.environ.get("DEV_ALLOWED_IPS", "")  # optional, comma separated
    app_version: str = os.environ.get("APP_VERSION", "dev")
