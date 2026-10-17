import time

import pytest

from console.actions import ActionError, load_actions, render_argv
from console.monitor import problems_from
from console.security import check_totp, hash_password, totp_at, verify_password
from console.serverapi import sign
from .conftest import DEV_SECRET, PASSWORD, SECRET, USER, login


# ------------------------------------------------------------------ sign-in

def test_totp_matches_the_rfc_vector():
    import base64

    sec = base64.b32encode(b"12345678901234567890").decode()
    assert totp_at(sec, 59 // 30, 8) == "94287082"


def test_a_code_works_only_once(app):
    db = app.extensions["db"]
    now = time.time()
    code = totp_at(SECRET, int(now // 30))
    assert check_totp(db, SECRET, code, now) is True
    assert check_totp(db, SECRET, code, now) is False  # replay
    assert check_totp(db, SECRET, "000000", now) is False


def test_passwords_are_hashed_and_checked():
    h = hash_password("Another-Long-Pass-1!")
    assert "Another" not in h and verify_password("Another-Long-Pass-1!", h) and not verify_password("nope", h)


def test_login_needs_password_and_code(client, codes):
    assert client.get("/api/overview").status_code == 401
    assert client.post("/api/login", json={"username": USER, "password": "wrong", "totp": codes.code()}).status_code == 401
    assert client.post("/api/login", json={"username": USER, "password": PASSWORD, "totp": "123456"}).status_code == 401
    assert client.post("/api/login", json={"username": "someone", "password": PASSWORD, "totp": codes.code()}).status_code == 401
    r = login(client, codes)
    assert r.status_code == 200
    cookie = r.headers["Set-Cookie"]
    assert "HttpOnly" in cookie and "SameSite=Strict" in cookie
    assert client.get("/api/overview").status_code == 200


def test_error_never_says_which_part_was_wrong(client, codes):
    a = client.post("/api/login", json={"username": USER, "password": "wrong", "totp": codes.code()}).get_json()
    b = client.post("/api/login", json={"username": "nobody", "password": PASSWORD, "totp": codes.code()}).get_json()
    assert a == b


def test_repeated_failures_lock_the_account_even_with_the_right_details(client, codes):
    for _ in range(5):
        client.post("/api/login", json={"username": USER, "password": "wrong", "totp": "111111"})
    assert login(client, codes).status_code == 429


def test_changes_need_the_csrf_token(client, codes):
    csrf = login(client, codes).get_json()["csrf"]
    assert client.post("/api/targets/prod/smoke", json={}).status_code == 403
    assert client.post("/api/logout", json={}, headers={"X-CSRF": "wrong"}).status_code == 403
    assert client.post("/api/logout", json={}, headers={"X-CSRF": csrf}).status_code == 200
    assert client.get("/api/overview").status_code == 401


def test_other_sites_cannot_post(client, codes):
    csrf = login(client, codes).get_json()["csrf"]
    r = client.post("/api/logout", json={}, headers={"X-CSRF": csrf, "Origin": "https://evil.example"})
    assert r.status_code == 403


def test_sessions_expire_when_idle(client, codes, app):
    login(client, codes)
    db = app.extensions["db"]
    db.x("UPDATE sessions SET last_seen = last_seen - 100000")
    assert client.get("/api/overview").status_code == 401


def test_security_headers(client):
    r = client.get("/")
    assert "default-src 'none'" in r.headers["Content-Security-Policy"] and "script-src 'self'" in r.headers["Content-Security-Policy"]
    assert "unsafe-inline" not in r.headers["Content-Security-Policy"]
    assert r.headers["X-Frame-Options"] == "DENY" and r.headers["X-Content-Type-Options"] == "nosniff"


def test_ip_allowlist_hides_the_console(cfg, codes):
    from dataclasses import replace

    from console import create_app
    from console.db import DB

    app = create_app(replace(cfg, allowed_ips=("10.9.9.9",)), DB(":memory:"))
    assert app.test_client().get("/").status_code == 404


# ------------------------------------------------------------- step-up actions

def test_actions_need_a_fresh_code_and_the_typed_word(client, codes):
    csrf = login(client, codes).get_json()["csrf"]
    H = {"X-CSRF": csrf}
    base = {"confirm": "RUN", "params": {"word": "hi"}}
    assert client.post("/api/actions/echo/run", json={**base, "totp": "000000"}, headers=H).status_code == 403
    assert client.post("/api/actions/echo/run", json={**base, "confirm": "no", "totp": codes.code()}, headers=H).status_code == 400
    r = client.post("/api/actions/echo/run", json={**base, "totp": codes.code()}, headers=H)
    assert r.status_code == 202
    rid = r.get_json()["run"]
    for _ in range(50):
        run = client.get(f"/api/runs/{rid}").get_json()
        if run["status"] != "running":
            break
        time.sleep(0.1)
    assert run["status"] == "ok" and "hello hi" in run["output"]
    audit = client.get("/api/audit").get_json()
    assert audit["chainIntact"] is True and any(x["action"] == "action_start" for x in audit["rows"])


def test_action_parameters_cannot_inject_commands(client, codes):
    csrf = login(client, codes).get_json()["csrf"]
    r = client.post("/api/actions/echo/run", json={"confirm": "RUN", "params": {"word": "x'); import os #"}, "totp": codes.code()}, headers={"X-CSRF": csrf})
    assert r.status_code == 400
    r = client.post("/api/actions/echo/run", json={"confirm": "RUN", "params": {"word": "ok", "extra": "1"}, "totp": codes.code()}, headers={"X-CSRF": csrf})
    assert r.status_code == 400


def test_render_argv_refuses_bad_values_and_never_uses_a_shell():
    acts = load_actions(__file__.replace("tests/test_console.py", "actions.json"))
    ok = render_argv(acts["backup-firestore"], {"bucket": "my-bucket", "name": "pre-migrate"})
    assert ok[-3:] == ["gs://my-bucket/backups/pre-migrate", "--project", "rev-games"]
    for bad in ({"bucket": "a b"}, {"bucket": "x;rm -rf /", "name": "n"}, {"bucket": "ok-bucket", "name": "../../etc"}, {"bucket": "$(id)", "name": "n"}):
        with pytest.raises(ActionError):
            render_argv(acts["backup-firestore"], bad)
    assert all(isinstance(p, str) for p in ok)


def test_audit_chain_detects_tampering(app, client, codes):
    login(client, codes)
    db = app.extensions["db"]
    assert db.audit_ok()
    db.x("UPDATE audit SET actor='someone-else' WHERE id=1")
    assert not db.audit_ok()


# ------------------------------------------------------------------- monitoring

def test_problems_are_explained():
    diag = {"service": "rev", "metrics": {"requests": 100, "errorRate": 0.2, "p95": 3000, "quotaErrors": 3, "flushFailures": 0},
            "checks": {"adminKeyStrong": False, "sessionSecretStrong": True, "paymentsMode": "mock", "mockPaymentsInCloud": True, "webhookSecretDefault": False, "emailMode": "mock"},
            "listeners": {"users": {"active": False}}, "maintenance": {"on": True, "scope": "all"}, "openCrashes": 2}
    codes = {p["code"]: p["severity"] for p in problems_from(True, 100, diag, {"ok": False, "quota": True}, 5)}
    assert codes["db_quota"] == "critical" and codes["error_rate"] == "critical" and codes["mock_payments"] == "critical" and codes["cert_expiring"] == "warning"
    assert codes["quota_errors"] == "critical" and codes["listener_users"] == "warning" and codes["maintenance"] == "info" and codes["admin_key"] == "warning"


def test_down_is_one_clear_problem():
    assert [p["code"] for p in problems_from(False, 0, None, None, None)] == ["down"]


def test_healthy_server_has_no_problems():
    diag = {"service": "local", "metrics": {"requests": 50, "errorRate": 0, "p95": 80, "quotaErrors": 0}, "checks": {"adminKeyStrong": True, "sessionSecretStrong": True, "paymentsMode": "mock"}, "listeners": {}, "maintenance": {"on": False}, "openCrashes": 0}
    assert problems_from(True, 40, diag, {"ok": True}, 90) == []


def test_incident_opens_after_two_failures_and_closes_on_recovery(cfg):
    from console.db import DB
    from console.monitor import Monitor

    sent = []
    db, mon = DB(":memory:"), None
    mon = Monitor(db, cfg, notify=sent.append)
    t = cfg.targets[0]
    mon.probe(t, deep=False)  # port 9: nothing listens, so this fails
    assert not db.q("SELECT * FROM incidents")
    mon.probe(t, deep=False)
    assert len(db.q("SELECT * FROM incidents WHERE ended IS NULL")) == 1 and "DOWN" in sent[0]
    mon.probe(t, deep=False)
    assert len(sent) == 1  # one alert for the whole outage, not one per check
    assert mon.summary(t)["status"] == "down"


def test_signature_matches_the_servers_algorithm():
    """The console and the game server must compute the same signature. Skipped if the server folder isn't next door."""
    import importlib.util
    from pathlib import Path

    path = Path(__file__).resolve().parents[2] / "server" / "app" / "devapi.py"
    if not path.is_file():
        pytest.skip("server folder not found")
    src = path.read_text()
    ns = {}
    start = src.index("def sign(")
    end = src.index("def make_devapi")
    exec("import hashlib, hmac\n" + src[start:end], ns)
    for args in (("k" * 32, "post", "/internal/dev/maintenance?x=1", "1700000000", "n" * 20, b'{"on":true}'), ("z" * 40, "GET", "/internal/dev/diag", "1", "a" * 16, b"")):
        assert sign(*args) == ns["sign"](*args)
