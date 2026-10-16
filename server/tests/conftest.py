import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import create_app  # noqa: E402
from app.config import Config  # noqa: E402
from app.account import AccountService  # noqa: E402
from app.blackjack import BlackjackService  # noqa: E402
from app.crash import CrashService  # noqa: E402
from app.dice import DiceService  # noqa: E402
from app.fairness import FairnessService  # noqa: E402
from app.roulette import RouletteService  # noqa: E402
from app.slots import SlotsService  # noqa: E402
from app.store import MemoryStore  # noqa: E402
from app.wallet import WalletService  # noqa: E402


class FakeClock:
    def __init__(self):
        self.now = datetime(2026, 1, 1, tzinfo=timezone.utc)

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += timedelta(seconds=seconds)


class FixedRng:
    """random.random() returns the queued values; everything else is seeded."""

    def __init__(self, values):
        import random

        self.values = list(values)
        self._r = random.Random(1)

    def random(self):
        return self.values.pop(0) if self.values else self._r.random()

    def choice(self, seq):
        return self._r.choice(seq)

    def shuffle(self, seq):
        self._r.shuffle(seq)


@pytest.fixture
def clock():
    return FakeClock()


@pytest.fixture
def store():
    return MemoryStore()


@pytest.fixture
def cfg():
    return Config()


@pytest.fixture
def deleted_auth():
    return []


@pytest.fixture
def make_client(store, clock, cfg, deleted_auth):
    def make(slots_rng=None, crash_rng=None, dice_rng=None, roulette_rng=None, bj_rng=None):
        # One shared fairness service; a game given a scripted rng gets its own
        # override service so the other games keep real HMAC randomness.
        fair = FairnessService(store, clock)

        def own(rng):
            return FairnessService(store, clock, rng_override=rng) if rng is not None else fair

        slots = SlotsService(store, cfg, clock, fair=own(slots_rng))
        crash = CrashService(store, cfg, clock, rng=crash_rng, sleep=lambda s: clock.advance(s), fair=own(crash_rng))
        dice = DiceService(store, cfg, clock, fair=own(dice_rng))
        roulette = RouletteService(store, cfg, clock, fair=own(roulette_rng))
        blackjack = BlackjackService(store, cfg, clock, fair=own(bj_rng))
        app = create_app(
            store=store,
            cfg=cfg,
            verifier=lambda token: {"alice": "alice", "bob": "bob"}[token],
            fair=fair,
            wallet=WalletService(store, cfg, clock),
            slots=slots,
            crash=crash,
            dice=dice,
            roulette=roulette,
            blackjack=blackjack,
            account=AccountService(store, deleted_auth.append),
        )
        return app.test_client()

    return make


def auth(user="alice"):
    return {"Authorization": f"Bearer {user}"}
