import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

os.environ.setdefault("APP_ENV", "test")  # no .env.* file is read during tests
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import create_app  # noqa: E402
from app.config import Config  # noqa: E402
from app.account import AccountService  # noqa: E402
from app.blackjack import BlackjackService  # noqa: E402
from app.crash import CrashService  # noqa: E402
from app.dice import DiceService  # noqa: E402
from app.plinko import PlinkoService  # noqa: E402
from app.fairness import FairnessService  # noqa: E402
from app.roulette import RouletteService  # noqa: E402
from app.slots import SlotsService  # noqa: E402
from app.standing import StandingService  # noqa: E402
from app.staff import StaffService  # noqa: E402
from app.support import SupportService  # noqa: E402
from app.uploads import MemoryBlobs, UploadService  # noqa: E402
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


ADMIN_USER = "boss-owner"
ADMIN_PASS = "Str0ng!Passphrase#1"
ADMIN_KEY = "secret-key"
ADMIN = dict(dup_cooloff_seconds=0, admin_key=ADMIN_KEY, admin_username=ADMIN_USER, admin_password=ADMIN_PASS, session_secret="s" * 32)


@pytest.fixture
def cfg():
    # Demo odds neutral here: the older tests check the printed tables. Mode odds have their own tests.
    return Config(**ADMIN, demo_dice_edge=0.05, demo_plinko_edge=0.04, demo_crash_edge=0.03, demo_slots_factor=1.0, demo_slots_generous=False, live_slots_factor=1.0, demo_win_boost=0.0, live_agreement_required=False, rounds_enabled=False, live_agreement_version="1")


@pytest.fixture
def deleted_auth():
    return []


@pytest.fixture
def standing(store, cfg, clock):
    return StandingService(store, cfg, clock)


@pytest.fixture
def staff(store, cfg, clock):
    return StaffService(store, cfg, clock)


@pytest.fixture
def blobs():
    return MemoryBlobs()


@pytest.fixture
def uploads(store, cfg, clock, blobs):
    return UploadService(store, cfg, blobs, clock)


@pytest.fixture
def support(store, cfg, uploads, clock):
    return SupportService(store, cfg, uploads, clock)


@pytest.fixture
def make_client(store, clock, cfg, deleted_auth, standing, staff, uploads, support):
    def make(slots_rng=None, crash_rng=None, dice_rng=None, roulette_rng=None, bj_rng=None, plinko_rng=None):
        # One shared fairness service; a game given a scripted rng gets its own
        # override service so the other games keep real HMAC randomness.
        fair = FairnessService(store, clock)

        def own(rng):
            return FairnessService(store, clock, rng_override=rng) if rng is not None else fair

        slots = SlotsService(store, cfg, clock, fair=own(slots_rng))
        crash = CrashService(store, cfg, clock, rng=crash_rng, sleep=lambda s: clock.advance(s), fair=own(crash_rng))
        dice = DiceService(store, cfg, clock, fair=own(dice_rng))
        plinko = PlinkoService(store, cfg, clock, fair=own(plinko_rng))
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
            plinko=plinko,
            roulette=roulette,
            blackjack=blackjack,
            account=AccountService(store, deleted_auth.append),
            standing=standing,
            staff=staff,
            uploads=uploads,
            support=support,
        )
        return app.test_client()

    return make


def auth(user="alice"):
    return {"Authorization": f"Bearer {user}"}


def staff_login(c, username=ADMIN_USER, password=ADMIN_PASS):
    r = c.post("/staff/api/login", json={"username": username, "password": password})
    return r


def staff_headers(c, username=ADMIN_USER, password=ADMIN_PASS, key=ADMIN_KEY):
    r = staff_login(c, username, password)
    assert r.status_code == 200, r.get_json()
    h = {"Authorization": "Bearer " + r.get_json()["token"]}
    if key is not None:
        h["X-Admin-Key"] = key
    return h


# 1x1 PNG, a tiny MP4-looking header and a PDF header: enough for the type check.
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 40
PDF = b"%PDF-1.4\n" + b"x" * 40
MP4 = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 40
