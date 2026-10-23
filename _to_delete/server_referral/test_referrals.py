from datetime import timedelta

from .conftest import auth


def wallet_rounds(c, user):
    return c.get("/v1/wallet", headers=auth(user)).get_json()["rounds"]["extra"]


def setup_users(c, store, clock):
    for u in ("alice", "bob"):
        c.get("/v1/wallet", headers=auth(u))
        store.merge(f"users/{u}", {"createdAt": clock()})


def test_code_is_stable_and_unique(make_client, store, clock):
    c = make_client()
    setup_users(c, store, clock)
    a = c.get("/v1/referral", headers=auth("alice")).get_json()
    assert a["code"] == c.get("/v1/referral", headers=auth("alice")).get_json()["code"]
    assert a["code"] != c.get("/v1/referral", headers=auth("bob")).get_json()["code"]
    assert c.get("/v1/referral").status_code == 401


def test_friend_gets_rounds_now_and_inviter_after_friend_plays(make_client, store, clock, cfg):
    c = make_client()
    setup_users(c, store, clock)
    code = c.get("/v1/referral", headers=auth("alice")).get_json()["code"]
    r = c.post("/v1/referral/apply", json={"code": code.lower()}, headers=auth("bob"))
    assert r.status_code == 200 and r.get_json()["rounds"] == cfg.referral_friend_rounds
    assert wallet_rounds(c, "bob") == cfg.referral_friend_rounds
    assert wallet_rounds(c, "alice") == 0
    ref = c.application.extensions["referrals"]
    # not paid until bob has played enough rounds
    ref.process()
    assert wallet_rounds(c, "alice") == 0
    store.merge("referral_pending/bob", {"referrer": "alice"})  # what the qualifying round writes
    ref.process()
    assert wallet_rounds(c, "alice") == cfg.referral_referrer_rounds
    ref.process()  # repeating pays nothing more
    assert wallet_rounds(c, "alice") == cfg.referral_referrer_rounds
    s = c.get("/v1/referral", headers=auth("alice")).get_json()
    assert s["invited"] == 1 and s["rewarded"] == 1


def test_the_qualifying_round_queues_the_reward(make_client, store, clock, cfg):
    from dataclasses import replace
    c = make_client()
    setup_users(c, store, clock)
    code = c.get("/v1/referral", headers=auth("alice")).get_json()["code"]
    c.post("/v1/referral/apply", json={"code": code}, headers=auth("bob"))
    q = c.application.extensions["referrals"].cfg.referral_qualify_rounds
    for _ in range(q):
        c.post("/v1/dice/roll", json={"bet": 10, "target": 50, "mode": "over"}, headers=auth("bob"))
        clock.advance(5)
    assert store.read("referral_pending/bob") is not None


def test_rules(make_client, store, clock):
    c = make_client()
    setup_users(c, store, clock)
    mine = c.get("/v1/referral", headers=auth("alice")).get_json()["code"]
    assert c.post("/v1/referral/apply", json={"code": mine}, headers=auth("alice")).status_code == 400  # own code
    assert c.post("/v1/referral/apply", json={"code": "ZZZZZZZ"}, headers=auth("bob")).status_code == 404
    assert c.post("/v1/referral/apply", json={"code": mine}, headers=auth("bob")).status_code == 200
    assert c.post("/v1/referral/apply", json={"code": mine}, headers=auth("bob")).status_code == 409  # only once
    clock.advance(60 * 60 * 24 * 30)
    store.merge("users/bob", {"referredBy": None, "createdAt": clock() - timedelta(days=30)})
    assert c.post("/v1/referral/apply", json={"code": mine}, headers=auth("bob")).status_code == 400  # too late


def test_event_boost_multiplies_daily_and_referral_rounds(make_client, store, clock, cfg):
    c = make_client()
    setup_users(c, store, clock)
    ev = c.application.extensions["events"]
    e = ev.create({"title": "Boost weekend", "kind": "wager", "startsAt": clock() - timedelta(minutes=1), "endsAt": clock() + timedelta(days=1),
                   "prizes": [], "boostMult": 2, "boostMinutes": 30})
    assert e["boost"] == {"mult": 2.0, "minutes": 30}
    r = c.post(f"/v1/events/{e['id']}/boost", headers=auth("bob"))
    assert r.status_code == 200 and r.get_json()["boost"]["mult"] == 2.0
    assert c.post(f"/v1/events/{e['id']}/boost", headers=auth("bob")).status_code == 409  # once per event
    assert c.get("/v1/wallet", headers=auth("bob")).get_json()["boost"]["mult"] == 2.0
    code = c.get("/v1/referral", headers=auth("alice")).get_json()["code"]
    # bob's referral bonus is doubled while the boost runs
    c.post("/v1/referral/apply", json={"code": code}, headers=auth("bob"))
    assert wallet_rounds(c, "bob") == cfg.referral_friend_rounds * 2
    clock.advance(31 * 60)
    assert c.get("/v1/wallet", headers=auth("bob")).get_json()["boost"] is None  # it ends
    got = c.get(f"/v1/events/{e['id']}", headers=auth("bob")).get_json()
    assert got["boostClaimed"] is True


def test_boost_only_while_event_runs(make_client, store, clock):
    c = make_client()
    setup_users(c, store, clock)
    ev = c.application.extensions["events"]
    e = ev.create({"title": "Later", "kind": "wager", "startsAt": clock() + timedelta(hours=2), "endsAt": clock() + timedelta(days=1), "prizes": [], "boostMult": 2})
    assert c.post(f"/v1/events/{e['id']}/boost", headers=auth("bob")).status_code == 400
    plain = ev.create({"title": "Plain", "kind": "wager", "startsAt": clock() - timedelta(minutes=1), "endsAt": clock() + timedelta(days=1), "prizes": []})
    assert c.post(f"/v1/events/{plain['id']}/boost", headers=auth("bob")).status_code == 400
