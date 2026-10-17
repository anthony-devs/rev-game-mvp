"""Runs the console's checks against a REAL game server started in-process (memory database)."""
import sys
import threading
from dataclasses import replace
from pathlib import Path

import pytest

SERVER = Path(__file__).resolve().parents[2] / "server"
pytestmark = pytest.mark.skipif(not (SERVER / "app" / "__init__.py").is_file(), reason="server folder not found")

DEV_SECRET = "q" * 40


def _verify(token):
    if token != "real-token":
        raise ValueError("bad token")  # like Firebase refusing a forged token
    return "u1"


@pytest.fixture(scope="module")
def live_server():
    sys.path.insert(0, str(SERVER))
    import os

    os.environ.setdefault("APP_ENV", "test")
    from werkzeug.serving import make_server

    from app import create_app
    from app.config import Config
    from app.store import MemoryStore

    cfg = Config(admin_key="k" * 24, admin_username="owner-x", admin_password="Str0ng!Passphrase#1", session_secret="s" * 40, dev_api_secret=DEV_SECRET)
    app = create_app(store=MemoryStore(), cfg=cfg, verifier=_verify, account=lambda uid: None)
    srv = make_server("127.0.0.1", 0, app, threaded=True)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_port}"
    srv.shutdown()
    sys.path.remove(str(SERVER))


def test_every_check_passes_against_a_healthy_server(live_server):
    from console.config import Target
    from console.smoke import run_smoke

    res = run_smoke(Target("it", live_server, DEV_SECRET))
    failed = [(c["name"], c["detail"]) for c in res["results"] if not c["ok"]]
    assert failed == [], failed
    assert res["passed"] >= 14


def test_a_wrong_secret_is_caught_by_the_checks(live_server):
    from console.config import Target
    from console.smoke import run_smoke

    res = run_smoke(Target("it", live_server, "w" * 40))
    bad = {c["name"] for c in res["results"] if not c["ok"]}
    assert "Signed developer link works" in bad and "Database can be read" in bad


def test_monitor_reads_diagnostics_and_flags_nothing_serious(live_server, tmp_path):
    from console.config import Config, Target
    from console.db import DB
    from console.monitor import Monitor

    t = Target("it", live_server, DEV_SECRET)
    cfg = Config(targets=(t,))
    db, sent = DB(":memory:"), []
    mon = Monitor(db, cfg, notify=sent.append)
    r = mon.probe(t, deep=True)
    assert r["ok"] and not sent
    s = mon.summary(t)
    assert s["status"] == "up" and s["diag"]["metrics"] is not None
    assert not [p for p in s["problems"] if p["severity"] == "critical"], s["problems"]
