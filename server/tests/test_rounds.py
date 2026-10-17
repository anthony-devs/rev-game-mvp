"""Rounds: 14 free per window shared by all games, then bought rounds."""
import dataclasses

import pytest

from .conftest import auth

H = {"X-Play-Mode": "live"}


@pytest.fixture
def on(cfg):
    object.__setattr__(cfg, "rounds_enabled", True)
    yield cfg
    object.__setattr__(cfg, "rounds_enabled", False)


def spin(c, who="alice"):
    return c.post("/v1/slots/spin", json={"bet": 10}, headers=auth(who))


def test_fourteen_free_rounds_shared_across_games(make_client, on):
    c = make_client()
    for _ in range(7):
        assert spin(c).status_code == 200
    for _ in range(7):
        assert c.post("/v1/dice/roll", json={"bet": 10, "target": 50, "mode": "under"}, headers=auth()).status_code == 200
    before = c.get("/v1/wallet", headers=auth()).json["balance"]
    r = spin(c)
    assert r.status_code == 402 and r.json["error"] == "no_rounds"
    assert r.json["price"] == 50 and r.json["secondsLeft"] > 0 and 5 in r.json["packs"]
    assert c.get("/v1/wallet", headers=auth()).json["balance"] == before  # a refused round costs nothing
    assert c.get("/v1/wallet", headers=auth()).json["rounds"]["available"] == 0


def test_rounds_come_back_after_the_window(make_client, on, clock):
    c = make_client()
    for _ in range(14):
        assert spin(c).status_code == 200
    assert spin(c).status_code == 402
    clock.advance(6 * 3600 - 5)
    assert spin(c).status_code == 402
    clock.advance(10)
    j = spin(c).json
    assert j["rounds"]["freeLeft"] == 13


def test_buying_rounds_charges_the_balance_once(make_client, on):
    c = make_client()
    for _ in range(14):
        spin(c)
    before = c.get("/v1/wallet", headers=auth()).json["balance"]
    r = c.post("/v1/rounds/buy", json={"size": 5, "key": "k1"}, headers=auth())
    assert r.status_code == 200 and r.json["bought"] == 5 and r.json["charged"] == 250
    assert r.json["balance"] == before - 250 and r.json["rounds"]["extra"] == 5
    again = c.post("/v1/rounds/buy", json={"size": 5, "key": "k1"}, headers=auth())
    assert again.json["balance"] == before - 250 and again.json["bought"] == 0  # same key: charged once
    for _ in range(5):
        assert spin(c).status_code == 200
    assert spin(c).status_code == 402


def test_bad_pack_and_poor_wallet(make_client, on, store):
    c = make_client()
    assert c.post("/v1/rounds/buy", json={"size": 7}, headers=auth()).json["error"] == "bad_pack"
    store.merge("users/alice/wallet/current", {"balance": 100.0})
    r = c.post("/v1/rounds/buy", json={"size": 5}, headers=auth())
    assert r.status_code == 402 and r.json["error"] == "insufficient_credits"


def test_daily_claim_keeps_the_counters(make_client, on):
    c = make_client()
    spin(c)
    c.post("/v1/rounds/buy", json={"size": 5, "key": "a"}, headers=auth())
    c.post("/v1/wallet/claim-daily", headers=auth())
    w = c.get("/v1/wallet", headers=auth()).json["rounds"]
    assert w["extra"] == 5 and w["freeLeft"] == 13


def test_players_have_their_own_allowance(make_client, on):
    c = make_client()
    for _ in range(14):
        spin(c, "alice")
    assert spin(c, "alice").status_code == 402
    assert spin(c, "bob").status_code == 200


def test_round_cooloff_slows_rapid_taps(make_client, cfg):
    object.__setattr__(cfg, "round_cooloff_seconds", 30.0)
    try:
        c = make_client()
        assert spin(c).status_code == 200
        r = spin(c)
        assert r.status_code == 429 and r.json["error"] == "slow_down"
        assert c.post("/v1/dice/roll", json={"bet": 10, "target": 50, "mode": "under"}, headers=auth()).status_code == 429  # any game
        assert spin(c, "bob").status_code == 200  # other players are not held up
    finally:
        object.__setattr__(cfg, "round_cooloff_seconds", 0.0)
