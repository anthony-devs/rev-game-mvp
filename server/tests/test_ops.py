"""Founder insights, crash reports, email, maintenance and the developer API."""
import json
import os
import time
import uuid
from dataclasses import replace
from datetime import timedelta

import pytest

from app import create_app
from app.devapi import sign
from app.messaging import MessagingService, MockMailer
from app.store import MemoryStore
from app.util import utcnow
from .conftest import ADMIN_KEY, auth, staff_headers

SECRET = "d" * 40


@pytest.fixture
def app_parts(store, cfg, clock):
    mailer = MockMailer()
    cfg2 = replace(cfg, dev_api_secret=SECRET)
    messaging = MessagingService(store, cfg2, mailer, clock, background=False, pause=0)
    app = create_app(store=store, cfg=cfg2, verifier=lambda t: {"alice": "alice", "bob": "bob"}[t], messaging=messaging, account=lambda uid: None)
    return app, mailer


@pytest.fixture
def c(app_parts):
    return app_parts[0].test_client()


def signed(c, method, path, body=None, secret=SECRET, ts=None, nonce=None):
    raw = json.dumps(body).encode() if body is not None else b""
    ts, nonce = str(ts if ts is not None else int(time.time())), nonce or uuid.uuid4().hex
    h = {"X-Dev-Time": ts, "X-Dev-Nonce": nonce, "X-Dev-Sig": sign(secret, method, path, ts, nonce, raw), "Content-Type": "application/json"}
    return c.open(path, method=method, data=raw, headers=h)


# --------------------------------------------------------------- profit tracker

def test_rounds_and_money_are_counted_and_flushed(c, store):
    m = c.application.extensions["metrics"]
    m.record_round("alice", "r1", "dice", 100, 150)
    m.record_round("alice", "r1", "dice", 100, 150)  # a retried transaction: still one round
    m.record_round("L_alice", "r2", "slots", 200, 0)
    m.record_money("deposit", "p1", 1000)
    m.record_money("deposit", "p1", 1000)
    m.record_money("payout", "p2", 300)
    assert store.read("stats_daily/" + m.clock().strftime("%Y-%m-%d")) is None  # nothing written yet
    m.flush()
    p = c.application.extensions["metrics"].daily(1)[0]
    assert p["demo"]["dice"] == {"rounds": 1, "wagered": 100.0, "paid": 150.0, "wins": 1}
    assert p["live"]["slots"]["wagered"] == 200.0
    assert p["money"]["deposits"] == 1000.0 and p["money"]["payouts"] == 300.0


def test_a_real_round_reaches_the_tracker(c, store):
    assert c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers=auth()).status_code == 200
    m = c.application.extensions["metrics"]
    m.flush()
    assert m.daily(1)[0]["demo"]["dice"]["rounds"] == 1


def test_profit_endpoint_totals_live_only_as_profit(c, store):
    m = c.application.extensions["metrics"]
    m.record_round("L_alice", "a", "dice", 1000, 400)
    m.record_round("L_bob", "b", "dice", 500, 0)
    m.record_round("bob", "c", "dice", 999, 0)  # demo: must not count as profit
    m.record_money("deposit", "d1", 2000)
    m.flush()
    h = staff_headers(c)
    d = c.get("/admin/api/insights/profit?days=7", headers=h).get_json()
    assert d["live"]["ggr"] == 1100 and d["live"]["wagered"] == 1500 and d["demo"]["wagered"] == 999
    assert d["money"]["netCash"] == 2000 and len(d["series"]) == 7


def test_dashboard_has_windows_and_all_time(c, store):
    m = c.application.extensions["metrics"]
    m.record_round("L_alice", "a", "dice", 1000, 400)
    m.record_round("L_bob", "b", "slots", 500, 0)
    m.record_round("bob", "c", "dice", 999, 0)
    m.record_money("deposit", "d1", 2000)
    m.flush()
    h = staff_headers(c)
    d = c.get("/admin/api/insights/dashboard", headers=h).get_json()
    w = d["windows"]
    assert w["today"]["live"]["ggr"] == 1100 and w["today"]["live"]["rounds"] == 2 and w["today"]["demo"]["wagered"] == 999
    assert w["all"]["live"]["wagered"] == 1500 and w["all"]["money"]["deposits"] == 2000
    assert w["today"]["live"]["games"]["dice"]["rtp"] == 0.4
    assert len(d["series"]) == 30 and d["players"]["total"] >= 0 and "p95" in d["health"]
    assert c.get("/admin/api/insights/dashboard", headers=auth()).status_code == 401


def test_all_time_adds_finished_days_once(c, store):
    from datetime import timedelta
    m = c.application.extensions["metrics"]
    day = (m.clock() - timedelta(days=3)).strftime("%Y-%m-%d")
    store.merge(f"stats_daily/{day}", {"live": {"dice": {"rounds": 4, "wagered": 400.0, "paid": 100.0, "wins": 1}}})
    h = staff_headers(c)
    first = c.get("/admin/api/insights/dashboard", headers=h).get_json()
    assert first["windows"]["all"]["live"]["wagered"] == 400 and first["since"] == day
    assert store.read("stats_total/closed")["through"]


def test_insights_need_the_admin(c):
    assert c.get("/admin/api/insights/profit").status_code == 401
    assert c.get("/admin/api/insights/profit", headers=auth()).status_code == 401


# ------------------------------------------------------------ active / inactive

def test_activity_counts_active_and_inactive(c, store):
    now = utcnow()
    store.merge("users/a", {"lastSeenAt": now})
    store.merge("users/b", {"lastSeenAt": now - timedelta(days=3)})
    store.merge("users/c", {"lastSeenAt": now - timedelta(days=90)})
    store.merge("users/d", {"displayName": "never"})
    d = c.get("/admin/api/insights/activity", headers=staff_headers(c)).get_json()
    assert (d["total"], d["active24h"], d["active7d"], d["active30d"], d["inactive"]) == (4, 1, 2, 2, 2)


def test_signing_in_marks_the_player_seen(c, store):
    c.get("/v1/wallet", headers=auth())
    c.application.extensions["metrics"].flush()
    assert store.read("users/alice")["lastSeenAt"] is not None


# ---------------------------------------------------------------------- crashes

def test_crash_reports_are_grouped_and_rate_limited(c):
    body = {"kind": "StateError", "message": "Bad state 12345", "stack": "#0 foo (a.dart:10:5)\n#1 bar (b.dart:99:1)", "platform": "ios", "appVersion": "1.0.0"}
    assert c.post("/v1/telemetry/crash", json=body, headers=auth()).status_code == 200
    assert c.post("/v1/telemetry/crash", json={**body, "message": "Bad state 99999", "stack": body["stack"].replace("10:5", "11:5")}, headers=auth("bob")).status_code == 200
    c.application.extensions["metrics"].flush()
    h = staff_headers(c)
    groups = c.get("/admin/api/insights/crashes", headers=h).get_json()["crashes"]
    assert len(groups) == 1 and groups[0]["count"] == 2 and groups[0]["status"] == "open"
    gid = groups[0]["id"]
    assert c.post(f"/admin/api/insights/crashes/{gid}/status", json={"status": "resolved"}, headers=h).status_code == 200
    assert c.get("/admin/api/insights/crashes?status=open", headers=h).get_json()["crashes"] == []
    assert c.post("/admin/api/insights/crashes/nope/status", json={"status": "resolved"}, headers=h).status_code == 404
    assert c.post("/v1/telemetry/crash", json=body).status_code == 401  # must be signed in
    sent = [c.post("/v1/telemetry/crash", json={**body, "kind": f"K{i}"}, headers=auth()).get_json() for i in range(15)]
    assert any(s.get("dropped") for s in sent)


def test_server_errors_are_recorded(c):
    m = c.application.extensions["metrics"]
    try:
        raise ValueError("boom")
    except ValueError as e:
        import traceback

        m.record_error(e, "/v1/x", traceback.format_exc())
    assert m.errors[-1]["type"] == "ValueError"
    m.flush()
    assert m.daily(1)[0]["crashes"]["server"] == 1


# ------------------------------------------------------------------------ email

def test_campaign_goes_to_the_right_people_once(app_parts, store, clock):
    app, mailer = app_parts
    c = app.test_client()
    now = clock()
    store.merge("users/a", {"email": "a@x.com", "displayName": "Ann Lee", "lastSeenAt": now})
    store.merge("users/b", {"email": "b@x.com", "lastSeenAt": now - timedelta(days=60)})
    store.merge("users/c", {"email": "c@x.com", "lastSeenAt": now - timedelta(days=60), "emailOptOut": True})
    store.merge("users/d", {"displayName": "no email", "lastSeenAt": now - timedelta(days=60)})
    h = staff_headers(c)
    assert c.post("/admin/api/email/count", json={"audience": "inactive"}, headers=h).get_json()["count"] == 3
    send = lambda **kw: c.post("/admin/api/email/send", json={"audience": "inactive", "subject": "We miss you", "body": "Hi {name}, come back soon!", "key": "k" * 12, "confirm": "SEND", **kw}, headers=h)
    assert send(confirm="yes").status_code == 400
    r = send()
    assert r.status_code == 202, r.get_json()
    assert [m["to"] for m in mailer.sent] == ["b@x.com"]
    assert "Hi there," in mailer.sent[0]["text"]
    assert send().status_code in (409, 429)  # same key / too soon: never twice
    camp = c.get("/admin/api/email/campaigns", headers=h).get_json()["campaigns"][0]
    assert camp["sent"] == 1 and camp["skipped"] == 2 and camp["status"] == "done"


def test_email_one_player_by_address(app_parts, store):
    app, mailer = app_parts
    c = app.test_client()
    store.merge("users/a", {"email": "ann@x.com", "displayName": "Ann Lee"})
    r = c.post("/admin/api/email/send", json={"audience": "user:ANN@x.com", "subject": "Hello", "body": "Hi {name}, your payout is ready.", "key": "z" * 12, "confirm": "SEND"}, headers=staff_headers(c))
    assert r.status_code == 202 and "Hi Ann," in mailer.sent[0]["text"]


# ------------------------------------------------------------------ maintenance

def test_maintenance_blocks_new_bets_but_not_finishing_a_round(c, store):
    flags = c.application.extensions["flags"]
    flags.set_maintenance(True, "all", "Upgrading", "dev")
    r = c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers=auth())
    assert r.status_code == 503 and r.get_json()["error"] == "maintenance" and r.get_json()["message"] == "Upgrading"
    assert c.post("/v1/crash/rounds/abc/cashout", headers=auth()).status_code != 503
    assert c.get("/v1/wallet", headers=auth()).status_code == 200
    flags.set_maintenance(False, "all", "", "dev")
    assert c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers=auth()).status_code == 200


def test_live_only_maintenance_leaves_demo_open(c):
    c.application.extensions["flags"].set_maintenance(True, "live", "Payments upgrade", "dev")
    assert c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers=auth()).status_code == 200
    assert c.post("/v1/live/deposits", json={"provider": "paystack", "amount": 5000, "key": "k" * 10}, headers=auth()).status_code == 503


def test_catalog_tells_the_app_when_it_is_paused(c):
    assert c.get("/v1/games", headers=auth()).get_json()["maintenance"] is None
    c.application.extensions["flags"].set_maintenance(True, "live", "Payments upgrade", "dev")
    m = c.get("/v1/games", headers=auth()).get_json()["maintenance"]
    assert m == {"message": "Payments upgrade", "scope": "live"}


def test_status_works_without_login_and_without_the_database(c, store, monkeypatch):
    flags = c.application.extensions["flags"]

    def boom(*a, **k):
        raise RuntimeError("429 Quota exceeded")

    monkeypatch.setattr(store, "merge", boom)  # the database refuses writes
    doc = flags.set_maintenance(True, "all", "Upgrading", "dev")
    assert doc["shared"] is False  # saved on this server only, and the developer is told
    r = c.get("/v1/status")  # no token
    assert r.status_code == 200 and r.get_json()["maintenance"] == {"message": "Upgrading", "scope": "all"}
    flags.set_maintenance(False, "all", "", "dev")
    assert c.get("/v1/status").get_json()["maintenance"] is None


def test_maintenance_survives_a_restart(store, tmp_path):
    from app.system import SystemFlags

    path = tmp_path / "maintenance.json"
    SystemFlags(store, path=path).set_maintenance(True, "live", "Payments upgrade", "dev")
    again = SystemFlags(store, path=path)
    assert again.public() == {"message": "Payments upgrade", "scope": "live"}


def test_status_reports_database_trouble(c):
    m = c.application.extensions["metrics"]
    assert c.get("/v1/status").get_json()["degraded"] is False
    m.record_error(RuntimeError("429 Quota exceeded"), "/v1/games", "")
    assert c.get("/v1/status").get_json()["degraded"] is True


# ---------------------------------------------------------------- developer API

def test_dev_api_is_off_without_a_secret(store, cfg):
    app = create_app(store=store, cfg=cfg, verifier=lambda t: "alice", account=lambda uid: None)
    assert app.test_client().get("/internal/dev/diag").status_code == 404


def test_dev_api_needs_a_valid_signature(c):
    assert c.get("/internal/dev/diag").status_code == 401
    assert signed(c, "GET", "/internal/dev/diag", secret="e" * 40).status_code == 401
    assert signed(c, "GET", "/internal/dev/diag", ts=int(time.time()) - 600).status_code == 401
    nonce = uuid.uuid4().hex
    assert signed(c, "GET", "/internal/dev/diag", nonce=nonce).status_code == 200
    assert signed(c, "GET", "/internal/dev/diag", nonce=nonce).status_code == 401  # replayed
    assert c.get("/internal/dev/diag", headers=auth()).status_code == 401  # a player token is not enough


def test_dev_api_signature_covers_the_body_and_query(c):
    ts, nonce = str(int(time.time())), uuid.uuid4().hex
    good = sign(SECRET, "POST", "/internal/dev/maintenance", ts, nonce, b'{"on":false}')
    r = c.post("/internal/dev/maintenance", data=b'{"on":true}', headers={"X-Dev-Time": ts, "X-Dev-Nonce": nonce, "X-Dev-Sig": good, "Content-Type": "application/json"})
    assert r.status_code == 401  # body changed after signing
    assert signed(c, "GET", "/internal/dev/crashes?status=open").status_code == 200


def test_dev_diag_reports_health_without_secrets(c):
    c.get("/healthz")
    d = signed(c, "GET", "/internal/dev/diag")
    text = d.get_data(as_text=True)
    assert d.status_code == 200 and ADMIN_KEY not in text and SECRET not in text
    j = d.get_json()
    assert j["checks"]["liveEnabled"] is True and "metrics" in j and j["maintenance"] == {"on": False}


def test_dev_can_toggle_maintenance_and_run_migrations(c, store, clock):
    r = signed(c, "POST", "/internal/dev/maintenance", {"on": True, "scope": "all", "message": "Deploying", "by": "dev"})
    assert r.get_json()["on"] is True
    assert c.post("/v1/slots/spin", json={"bet": 10}, headers=auth()).status_code == 503
    assert signed(c, "POST", "/internal/dev/maintenance", {"on": False}).get_json()["on"] is False
    store.merge("users/old", {"lastLoginAt": clock()})
    st = signed(c, "GET", "/internal/dev/migrations").get_json()["migrations"]
    assert st[0]["applied"] is False
    dry = signed(c, "POST", "/internal/dev/migrations/run", {"apply": False}).get_json()["report"]
    assert dry[0]["result"] == {"players": 1} and "lastSeenAt" not in store.read("users/old")
    signed(c, "POST", "/internal/dev/migrations/run", {"apply": True, "by": "dev"})
    assert store.read("users/old")["lastSeenAt"] is not None
    assert signed(c, "GET", "/internal/dev/migrations").get_json()["migrations"][0]["applied"] is True
    assert signed(c, "POST", "/internal/dev/migrations/run", {"apply": True}).get_json()["report"] == []  # runs once


def test_dev_db_checks(c):
    assert signed(c, "GET", "/internal/dev/db-check").get_json()["ok"] is True
    assert signed(c, "POST", "/internal/dev/selftest", {}).get_json()["ok"] is True


def test_account_view_pulls_it_together(c, store):
    store.merge("users/alice", {"displayName": "Ann", "email": "a@x.com"})
    d = c.get("/admin/api/insights/accounts/alice", headers=staff_headers(c)).get_json()
    assert d["name"] == "Ann" and d["money"]["deposited"] == 0
    assert c.get("/admin/api/insights/accounts/nobody", headers=staff_headers(c)).status_code == 404
