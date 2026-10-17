import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from console import create_app  # noqa: E402
from console.actions import Runner  # noqa: E402
from console.config import Config, Target  # noqa: E402
from console.db import DB  # noqa: E402
from console.security import hash_password, new_totp_secret, totp_at  # noqa: E402

USER, PASSWORD = "dev-anthony", "Correct-Horse-Battery-9!"
SECRET = new_totp_secret()
PW_HASH = hash_password(PASSWORD)
DEV_SECRET = "s" * 40


class Clockwork:
    """Hands out a fresh TOTP code each call, as if 30 seconds passed (codes work once)."""

    def __init__(self):
        self.counter = int(time.time() // 30)

    def code(self):
        self.counter += 1
        return totp_at(SECRET, self.counter)


@pytest.fixture(autouse=True)
def _no_login_delay(monkeypatch):
    """The failed-login pause is real in production; skip it in tests (without touching time.sleep elsewhere)."""
    import types

    import console

    monkeypatch.setattr(console, "time", types.SimpleNamespace(sleep=lambda s: None, time=time.time, monotonic=time.monotonic))


@pytest.fixture
def cfg():
    return Config(user=USER, password_hash=PW_HASH, totp_secret=SECRET, db_path=":memory:", cookie_secure=False, run_monitor=False,
                  targets=(Target("prod", "http://127.0.0.1:9", DEV_SECRET),), actions_file="/nonexistent")


@pytest.fixture
def codes(monkeypatch):
    clk = Clockwork()
    # The server accepts counter-1..counter+1 around real time. Ours runs ahead, so freeze "now" to match.
    import console.security as sec

    real = sec.check_totp
    monkeypatch.setattr(sec, "check_totp", lambda db, secret, code, now=None: real(db, secret, code, now=clk.counter * 30))
    import console

    monkeypatch.setattr(console, "check_totp", sec.check_totp)
    return clk


@pytest.fixture
def app(cfg, codes):
    actions = {"echo": {"id": "echo", "label": "Echo", "argv": ["python3", "-c", "print('hello {word}')"], "params": {"word": {"pattern": "[a-z]{1,10}", "label": "Word"}}, "confirm": "RUN"}}
    db = DB(":memory:")
    return create_app(cfg, db, Runner(db, cfg, actions))


@pytest.fixture
def client(app):
    return app.test_client()


def login(client, codes, password=PASSWORD, user=USER):
    r = client.post("/api/login", json={"username": user, "password": password, "totp": codes.code()})
    return r
