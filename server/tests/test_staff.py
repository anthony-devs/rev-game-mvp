"""Staff sign-in, roles, rep management, lock-out."""
from datetime import timedelta

import pytest

from app.config import Config
from app.staff import StaffService, hash_password, password_problems, verify_password

from .conftest import ADMIN, ADMIN_KEY, ADMIN_PASS, ADMIN_USER, auth, staff_headers, staff_login

REP_PASS = "Rep!Strong#Pass99"


def make_rep(c, h, username="amaka.cs", name="Amaka", password=REP_PASS):
    return c.post("/admin/api/staff", json={"username": username, "name": name, "password": password}, headers=h)


def test_password_hashing_and_policy():
    h = hash_password("Abcdef!12345x")
    assert verify_password("Abcdef!12345x", h) and not verify_password("nope", h) and "Abcdef" not in h
    assert not verify_password("x", "garbage")
    assert password_problems("Abcdef!12345x", "bob") == []
    assert len(password_problems("short")) >= 3
    assert password_problems("Password!12345") != []  # contains a common word


@pytest.mark.parametrize("name", ["admin", "rev-admin", "Admin", "root"])
def test_admin_username_cannot_be_reserved(store, clock, name):
    svc = StaffService(store, Config(**{**ADMIN, "admin_username": name}), clock)
    assert not svc.admin_enabled and "ADMIN_USERNAME" in svc.admin_problem


def test_weak_admin_password_switches_admin_off(store, clock):
    svc = StaffService(store, Config(**{**ADMIN, "admin_password": "password"}), clock)
    assert not svc.admin_enabled


def test_admin_password_hash_works(store, clock):
    h = hash_password("An0ther!Strong#Pw")
    svc = StaffService(store, Config(**{**ADMIN, "admin_password": "", "admin_password_hash": h}), clock)
    assert svc.login(ADMIN_USER, "An0ther!Strong#Pw")["role"] == "admin"


def test_login_routes_by_role(make_client):
    c = make_client()
    r = staff_login(c).get_json()
    assert r["role"] == "admin" and r["redirect"] == "/admin" and r["token"]
    h = staff_headers(c)
    assert make_rep(c, h).status_code == 201
    r = staff_login(c, "amaka.cs", REP_PASS).get_json()
    assert r["role"] == "agent" and r["redirect"] == "/support" and r["mustChangePassword"] is True


def test_bad_logins_look_the_same(make_client):
    c = make_client()
    a = staff_login(c, ADMIN_USER, "wrong")
    b = staff_login(c, "nobody.here", "wrong")
    assert a.status_code == b.status_code == 401 and a.get_json() == b.get_json()
    assert staff_login(c, "admin", ADMIN_PASS).status_code == 401  # the reserved name never works


def test_lock_out_after_repeated_failures_then_recovers(make_client, clock):
    c = make_client()
    for _ in range(5):
        assert staff_login(c, ADMIN_USER, "wrong").status_code == 401
    locked = staff_login(c, ADMIN_USER, ADMIN_PASS)
    assert locked.status_code == 429  # even the right password is refused while locked
    clock.advance(16 * 60)
    assert staff_login(c).status_code == 200


def test_session_expires_and_garbage_is_refused(make_client, clock):
    c = make_client()
    h = staff_headers(c)
    assert c.get("/admin/api/ping", headers=h).status_code == 200
    assert c.get("/admin/api/ping", headers={"Authorization": "Bearer junk", "X-Admin-Key": ADMIN_KEY}).status_code == 401
    clock.advance(9 * 3600)
    assert c.get("/admin/api/ping", headers=h).status_code == 401


def test_only_admin_manages_reps_and_roles_are_separated(make_client):
    c = make_client()
    h = staff_headers(c)
    assert make_rep(c, h).status_code == 201
    rep_token = staff_login(c, "amaka.cs", REP_PASS).get_json()["token"]
    rep = {"Authorization": f"Bearer {rep_token}", "X-Admin-Key": ADMIN_KEY}
    assert c.get("/admin/api/staff", headers=rep).status_code == 403  # a rep can't open admin even with the key
    assert c.post("/admin/api/staff", json={"username": "x.rep.1", "name": "X", "password": REP_PASS}, headers=rep).status_code == 403
    assert c.get("/support/api/meta", headers={"Authorization": h["Authorization"]}).status_code == 403  # admin isn't a rep
    assert c.get("/support/api/meta", headers={"Authorization": f"Bearer {rep_token}"}).status_code == 200
    assert c.get("/support/api/meta").status_code == 401


def test_rep_creation_rules(make_client):
    c = make_client()
    h = staff_headers(c)
    for bad in ("admin", "rev-admin", "ab", "Has Space", ADMIN_USER):
        assert make_rep(c, h, username=bad).status_code == 400, bad
    assert make_rep(c, h, password="weak").get_json()["error"] == "weak_password"
    assert make_rep(c, h).status_code == 201
    assert make_rep(c, h).status_code == 409
    listed = c.get("/admin/api/staff", headers=h).get_json()
    assert [s["username"] for s in listed["staff"]] == ["amaka.cs"] and "passwordHash" not in str(listed)


def test_edit_deactivate_and_reset_sign_the_rep_out(make_client):
    c = make_client()
    h = staff_headers(c)
    make_rep(c, h)
    tok = lambda: {"Authorization": "Bearer " + staff_login(c, "amaka.cs", REP_PASS).get_json()["token"]}
    old = tok()
    assert c.get("/support/api/meta", headers=old).status_code == 200
    assert c.post("/admin/api/staff/amaka.cs", json={"name": "Amaka O."}, headers=h).get_json()["name"] == "Amaka O."
    assert c.get("/support/api/meta", headers=old).status_code == 200  # a rename doesn't sign anyone out
    c.post("/admin/api/staff/amaka.cs", json={"active": False}, headers=h)
    assert c.get("/support/api/meta", headers=old).status_code == 401
    assert staff_login(c, "amaka.cs", REP_PASS).status_code == 401
    c.post("/admin/api/staff/amaka.cs", json={"active": True, "password": "N3w!Phrase#Here77"}, headers=h)
    assert staff_login(c, "amaka.cs", REP_PASS).status_code == 401
    assert staff_login(c, "amaka.cs", "N3w!Phrase#Here77").status_code == 200
    assert c.post("/admin/api/staff/ghost.rep", json={"name": "Zed"}, headers=h).status_code == 404


def test_rep_changes_own_password(make_client):
    c = make_client()
    make_rep(c, staff_headers(c))
    old = {"Authorization": "Bearer " + staff_login(c, "amaka.cs", REP_PASS).get_json()["token"]}
    r = c.post("/staff/api/password", json={"current": "wrong", "new": "Fresh!Phrase#77abc"}, headers=old)
    assert r.status_code == 403
    assert c.post("/staff/api/password", json={"current": REP_PASS, "new": "weak"}, headers=old).status_code == 400
    r = c.post("/staff/api/password", json={"current": REP_PASS, "new": "Fresh!Phrase#77abc"}, headers=old)
    assert r.status_code == 200
    assert c.get("/support/api/meta", headers=old).status_code == 401  # old session is gone
    new = {"Authorization": "Bearer " + r.get_json()["token"]}
    assert c.get("/support/api/meta", headers=new).get_json()["me"]["mustChangePassword"] is False
    # the admin's password is environment-managed
    assert c.post("/staff/api/password", json={"current": ADMIN_PASS, "new": "Fresh!Phrase#77abc"}, headers=staff_headers(c)).status_code == 403


def test_pages_are_served_with_security_headers(make_client):
    c = make_client()
    for path in ("/staff", "/admin", "/support"):
        r = c.get(path)
        assert r.status_code == 200 and "frame-ancestors 'none'" in r.headers["Content-Security-Policy"] and r.headers["Cache-Control"] == "no-store"
