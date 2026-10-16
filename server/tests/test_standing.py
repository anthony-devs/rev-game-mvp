"""Bans, suspensions, payout restrictions, investigations, appeals, probation, dashboard."""
import pytest

from app.config import Config

from .conftest import ADMIN, FixedRng, auth, staff_headers

HOUR = 3600
DAY = 24 * HOUR


@pytest.fixture
def cfg():
    return Config(**ADMIN)


@pytest.fixture(autouse=True)
def users(store):
    for uid in ("alice", "bob"):
        store.docs[f"users/{uid}"] = {"displayName": uid.title(), "email": f"{uid}@x.com", "isAnonymous": False}


def admin(c, key=None):
    """Signed in as the admin, connected with the key (or with a wrong one)."""
    return staff_headers(c) if key is None else staff_headers(c, key=key)


def play(c, bet=100, user="alice"):
    return c.post("/v1/slots/spin", json={"bet": bet}, headers=auth(user))


def big(c, bet, user="alice"):
    """Slots only goes up to 1000 per spin; dice takes larger bets."""
    return c.post("/v1/dice/roll", json={"bet": bet, "target": 50, "mode": "over"}, headers=auth(user))


def daily(c, user="alice"):
    return c.post("/v1/wallet/claim-daily", headers=auth(user))


def code(resp):
    return resp.get_json().get("error")


# ---- baseline -----------------------------------------------------------------

def test_clean_player_plays_and_claims(make_client):
    c = make_client()
    assert play(c).status_code == 200
    assert daily(c).status_code == 200
    s = c.get("/v1/account/standing", headers=auth()).get_json()
    assert s["state"] == "good" and not s["blocksPlay"] and s["active"] == []


# ---- ban ----------------------------------------------------------------------

def test_ban_blocks_every_way_to_play_or_get_credits(make_client, standing):
    c = make_client(crash_rng=FixedRng([0.5]))
    standing.apply("alice", "ban", "Chargeback abuse", actor="t")
    expect = [
        play(c),
        c.post("/v1/dice/roll", json={"bet": 10, "target": 50, "mode": "over"}, headers=auth()),
        c.post("/v1/roulette/spin", json={"bets": [{"type": "red", "amount": 10}]}, headers=auth()),
        c.post("/v1/blackjack/deal", json={"bet": 10}, headers=auth()),
        c.post("/v1/crash/rounds", json={"bet": 10}, headers=auth()),
        daily(c),
        c.post("/v1/wallet/top-up", headers=auth()),
        c.post("/v1/wallet/reset", headers=auth()),
    ]
    for r in expect:
        assert r.status_code == 403, r.get_json()
        assert code(r) in ("account_banned",)
        assert r.get_json()["standing"]["state"] == "banned"
    # Reading is still fine, so the app can show the ban screen and let them appeal.
    assert c.get("/v1/wallet", headers=auth()).status_code == 200
    assert c.get("/v1/account/standing", headers=auth()).get_json()["state"] == "banned"
    # Other players are untouched.
    assert play(c, user="bob").status_code == 200


def test_banned_player_cannot_delete_account_to_dodge_it(make_client, standing, deleted_auth):
    c = make_client()
    standing.apply("alice", "ban", "x", actor="t")
    r = c.delete("/v1/account", headers=auth())
    assert r.status_code == 403 and code(r) == "account_locked" and deleted_auth == []


def test_cannot_double_apply_and_validation(standing):
    from app.errors import ApiError

    standing.apply("alice", "ban", "x", actor="t")
    with pytest.raises(ApiError) as e:
        standing.apply("alice", "ban", "again", actor="t")
    assert e.value.code == "already_active"
    with pytest.raises(ApiError) as e:
        standing.apply("alice", "suspension", "no duration", actor="t")
    assert e.value.code == "duration_required"
    with pytest.raises(ApiError):
        standing.apply("alice", "nonsense", "x", actor="t")
    with pytest.raises(ApiError):
        standing.apply("alice", "investigation", "", actor="t")


# ---- suspension, expiry and probation -----------------------------------------

def test_suspension_expires_then_probation_caps_bets_and_credits(make_client, standing, clock):
    c = make_client()
    standing.apply("alice", "suspension", "Spam", actor="t", duration_hours=24)
    assert code(play(c)) == "account_suspended"
    clock.advance(25 * HOUR)

    # Suspension is over; 72h probation starts from its end date.
    assert play(c, 100).status_code == 200
    r = big(c, 1500)
    assert r.status_code == 403 and code(r) == "probation_bet_cap"
    assert code(daily(c)) == "credits_restricted"
    s = c.get("/v1/account/standing", headers=auth()).get_json()
    assert s["state"] == "probation" and s["probationMaxBet"] == 1000

    clock.advance(3 * DAY)
    assert big(c, 1500).status_code == 200
    assert daily(c).status_code == 200
    actions = standing.actions("alice")
    assert actions[0]["status"] == "expired" and actions[0]["outcome"] == "expired"


def test_summary_is_settled_when_read_after_expiry(standing, clock, store):
    standing.apply("alice", "suspension", "x", actor="t", duration_hours=1)
    clock.advance(2 * HOUR)
    pub = standing.public(standing.summary("alice"))
    assert pub["blocksPlay"] is False
    assert store.read("users/alice/account/standing")["active"] == []


# ---- payout restriction -------------------------------------------------------

def test_payout_restriction_can_leave_play_open(make_client, standing):
    c = make_client()
    standing.apply("alice", "payout_restriction", "Bonus abuse", actor="t", blocks_play=False)
    assert play(c).status_code == 200
    r = daily(c)
    assert r.status_code == 403 and code(r) == "credits_restricted"
    assert code(c.post("/v1/wallet/top-up", headers=auth())) == "credits_restricted"
    assert code(c.post("/v1/wallet/reset", headers=auth())) == "credits_restricted"


def test_payout_restriction_blocks_play_by_default(make_client, standing):
    c = make_client()
    standing.apply("alice", "payout_restriction", "Bonus abuse", actor="t")
    assert code(play(c)) == "account_restricted"


# ---- investigation ------------------------------------------------------------

def test_investigation_pauses_play_and_clearing_it_has_no_probation(make_client, standing):
    c = make_client()
    a = standing.apply("alice", "investigation", "Unusual wins", actor="t")
    assert code(play(c)) == "account_under_review"
    standing.lift("alice", a["id"], actor="t", note="Nothing found", outcome="cleared")
    assert big(c, 5000).status_code == 200  # no probation cap
    assert daily(c).status_code == 200


# ---- appeals ------------------------------------------------------------------

def test_appeal_flow_reject_then_approve(make_client, standing, clock):
    c = make_client()
    a = standing.apply("alice", "ban", "Multi-accounting", actor="t", public_note="Send us your details")
    aid = a["id"]

    short = c.post("/v1/account/appeal", json={"actionId": aid, "message": "pls"}, headers=auth())
    assert short.status_code == 400
    ok = c.post("/v1/account/appeal", json={"actionId": aid, "message": "This was my brother on the same wifi, not me."}, headers=auth())
    assert ok.status_code == 201
    appeal_id = ok.get_json()["id"]
    assert c.post("/v1/account/appeal", json={"actionId": aid, "message": "x" * 30}, headers=auth()).status_code == 409
    assert c.get("/v1/account/standing", headers=auth()).get_json()["active"][0]["appealStatus"] == "pending"

    from app.errors import ApiError

    with pytest.raises(ApiError) as e:
        standing.decide_appeal("alice", appeal_id, "reject", "", actor="t")
    assert e.value.code == "response_required"
    standing.decide_appeal("alice", appeal_id, "reject", "Evidence doesn't match.", actor="t")
    entry = c.get("/v1/account/standing", headers=auth()).get_json()["active"][0]
    assert entry["appealStatus"] == "rejected" and entry["appealResponse"] == "Evidence doesn't match."
    assert code(play(c)) == "account_banned"

    again = c.post("/v1/account/appeal", json={"actionId": aid, "message": "Here is more evidence for you."}, headers=auth())
    assert again.status_code == 429 and again.get_json()["error"] == "appeal_cooldown"
    clock.advance(25 * HOUR)
    second = c.post("/v1/account/appeal", json={"actionId": aid, "message": "Here is more evidence for you."}, headers=auth())
    assert second.status_code == 201

    standing.decide_appeal("alice", second.get_json()["id"], "approve", "Thanks, restored.", actor="t", probation_hours=0)
    assert big(c, 5000).status_code == 200
    assert standing.actions("alice")[0]["outcome"] == "appeal_approved"
    with pytest.raises(ApiError) as e:
        standing.decide_appeal("alice", second.get_json()["id"], "approve", "", actor="t")
    assert e.value.code == "appeal_decided"


def test_cannot_appeal_someone_elses_or_inactive_action(make_client, standing):
    c = make_client()
    a = standing.apply("bob", "ban", "x", actor="t")
    r = c.post("/v1/account/appeal", json={"actionId": a["id"], "message": "this is not even my ban at all"}, headers=auth("alice"))
    assert r.status_code == 404


def test_no_appeal_when_disabled(make_client, standing):
    c = make_client()
    a = standing.apply("alice", "ban", "Fraud", actor="t", appeal_allowed=False)
    r = c.post("/v1/account/appeal", json={"actionId": a["id"], "message": "please reconsider this decision"}, headers=auth())
    assert r.status_code == 403 and code(r) == "appeal_not_allowed"


# ---- "restricted in the past 3 days" ------------------------------------------

def test_risk_restricted_in_past_three_days(standing, clock):
    assert standing.risk("alice")["restrictedInWindow"] is False
    a = standing.apply("alice", "payout_restriction", "x", actor="t")
    r = standing.risk("alice")
    assert r["restrictedInWindow"] and r["typesInWindow"] == ["payout_restriction"] and r["activeNow"] == [a["id"]]
    standing.lift("alice", a["id"], actor="t", probation_hours=0)
    clock.advance(2 * DAY)
    assert standing.risk("alice")["restrictedInWindow"] is True  # ended 2 days ago
    clock.advance(2 * DAY)
    r = standing.risk("alice")
    assert r["restrictedInWindow"] is False and r["actionsLast30d"] == 1
    assert standing.risk("alice", days=7)["restrictedInWindow"] is True


def test_risk_repeat_offender_and_counts(standing, clock):
    for kind in ("suspension", "payout_restriction", "investigation"):
        a = standing.apply("alice", kind, "x", actor="t", duration_hours=1 if kind == "suspension" else None)
        standing.lift("alice", a["id"], actor="t", probation_hours=0)
        clock.advance(HOUR)
    r = standing.risk("alice")
    assert r["repeatOffender"] and r["suspensionsLast30d"] == 1 and r["totalActions"] == 3


def test_delete_stays_blocked_during_probation(make_client, standing, clock, deleted_auth):
    c = make_client()
    a = standing.apply("alice", "suspension", "x", actor="t", duration_hours=1)
    standing.lift("alice", a["id"], actor="t")
    assert c.delete("/v1/account", headers=auth()).status_code == 403
    clock.advance(4 * DAY)
    assert c.delete("/v1/account", headers=auth()).status_code == 200 and deleted_auth == ["alice"]


# ---- dashboard API ------------------------------------------------------------

def test_dashboard_needs_login_then_key(make_client):
    c = make_client()
    assert c.get("/admin/api/users").status_code == 401  # no session
    only_login = {k: v for k, v in admin(c).items() if k != "X-Admin-Key"}
    r = c.get("/admin/api/users", headers=only_login)
    assert r.status_code == 401 and r.get_json()["error"] == "bad_admin_key"  # signed in but not connected
    assert c.get("/admin/api/users", headers=admin(c, key="nope")).status_code == 401
    assert c.get("/admin/api/ping", headers=admin(c)).status_code == 200
    assert c.get("/admin/api/session", headers=only_login).status_code == 200  # step 1 works without the key


def test_dashboard_is_off_without_a_key(store, clock):
    from app import create_app
    from app.staff import StaffService
    from app.standing import StandingService

    cfg = Config(**{**ADMIN, "admin_key": ""})
    off = create_app(store=store, cfg=cfg, verifier=lambda t: "alice", standing=StandingService(store, cfg, clock), staff=StaffService(store, cfg, clock)).test_client()
    assert off.get("/admin/api/ping", headers=staff_headers(off, key=None)).status_code == 503
    assert off.get("/admin").status_code == 200  # the page itself is only HTML, no data


def test_admin_end_to_end(make_client):
    c = make_client()
    h = admin(c)
    users = c.get("/admin/api/users?q=ali", headers=h).get_json()["users"]
    assert [u["uid"] for u in users] == ["alice"] and users[0]["state"] == "good"

    created = c.post(
        "/admin/api/users/alice/actions",
        json={"type": "suspension", "reasonCode": "conduct", "durationHours": 48},
        headers=h,
    )
    assert created.status_code == 201
    j = created.get_json()
    assert j["reason"] == "Conduct warning" and j["publicNote"] and j["createdBy"] == "boss-owner"
    assert code(play(c)) == "account_suspended"  # takes effect immediately

    detail = c.get("/admin/api/users/alice", headers=h).get_json()
    assert detail["standing"]["state"] == "suspended" and detail["risk"]["restrictedInWindow"] is True
    assert detail["actions"][0]["status"] == "active"

    recent = c.get("/admin/api/recent?days=3", headers=h).get_json()["users"]
    assert [u["uid"] for u in recent] == ["alice"] and recent[0]["types"] == ["suspension"]

    lifted = c.post(f"/admin/api/users/alice/actions/{j['id']}/lift", json={"reasonCode": "served", "probationHours": 0}, headers=h)
    assert lifted.status_code == 200
    assert play(c).status_code == 200
    feed = c.get("/admin/api/feed", headers=h).get_json()["events"]
    assert {e["actor"] for e in feed} == {"boss-owner"}


def test_admin_unknown_user_and_bad_type(make_client):
    c = make_client()
    h = admin(c)
    ok = {"type": "ban", "reasonCode": "tos"}
    assert c.post("/admin/api/users/ghost/actions", json=ok, headers=h).status_code == 404
    assert c.post("/admin/api/users/alice/actions", json={"type": "meh", "reasonCode": "tos"}, headers=h).status_code == 400
