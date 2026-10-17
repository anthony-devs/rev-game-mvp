import math

import pytest

from app.plinko import RISKS, ROWS, chances, multipliers, path_from, rtp_of

from .conftest import FixedRng, auth


# ----------------------------------------------------------------- tables

@pytest.mark.parametrize("rows", ROWS)
@pytest.mark.parametrize("risk", RISKS)
def test_live_tables_never_return_more_than_the_target(rows, risk):
    t = multipliers(rows, risk, 0.04)
    assert len(t) == rows + 1
    assert t == t[::-1]  # symmetric board
    assert 0.955 <= rtp_of(t, rows) <= 0.96  # rounded down: at or under 96%, never over
    assert min(t) >= 0.2 and t[0] == max(t)


@pytest.mark.parametrize("risk", RISKS)
def test_demo_table_is_generous(risk):
    assert rtp_of(multipliers(12, risk, -0.10), 12) >= 1.09


@pytest.mark.parametrize("rows", [8, 12, 16])
@pytest.mark.parametrize("risk", RISKS)
def test_shipped_demo_board_wins_on_every_drop(risk, rows):
    t = multipliers(rows, risk, -0.60)  # the default demo edge
    middle = t[rows // 2]
    assert middle < 1.0 and all(m > 1.0 for i, m in enumerate(t) if i != rows // 2)  # only the middle slot loses
    assert chances(rows)[rows // 2] < 0.28  # and the ball lands there about one drop in four
    assert rtp_of(t, rows) >= 1.5
    assert max(multipliers(rows, risk, 0.04)) > 1 > min(multipliers(rows, risk, 0.04))  # live still loses often


def test_higher_risk_pays_more_at_the_edges_and_less_in_the_middle():
    low, med, high = (multipliers(12, r, 0.04) for r in RISKS)
    assert low[0] < med[0] < high[0]
    assert low[6] > high[6]


def test_slot_chances_add_up():
    assert math.isclose(sum(chances(12)), 1.0)


def test_path_uses_one_number_per_row():
    rng = FixedRng([0.1, 0.9, 0.5, 0.49])
    assert path_from(rng, 4) == [0, 1, 1, 0]


# ----------------------------------------------------------------- API

def test_quote_returns_the_board(make_client):
    c = make_client()
    q = c.get("/v1/plinko/quote?rows=12&risk=medium", headers=auth()).get_json()
    assert q["rows"] == 12 and len(q["multipliers"]) == 13 and q["minBet"] == 10
    assert q["maxBet"] <= 100000


def test_quote_differs_between_demo_and_live(make_client, cfg):
    object.__setattr__(cfg, "demo_plinko_edge", -0.10)  # the shipped default; the shared test config keeps demo neutral
    c = make_client()
    demo = c.get("/v1/plinko/quote?rows=12&risk=high", headers=auth()).get_json()
    live = c.get("/v1/plinko/quote?rows=12&risk=high", headers={**auth(), "X-Play-Mode": "live"}).get_json()
    assert demo["rtp"] > live["rtp"] and live["rtp"] <= 0.96


def test_drop_follows_the_path_and_pays_the_slot(make_client):
    # 12 rows, all right: slot 12 (the far edge)
    c = make_client(plinko_rng=FixedRng([0.9] * 12))
    r = c.post("/v1/plinko/drop", json={"bet": 100, "rows": 12, "risk": "medium"}, headers=auth())
    assert r.status_code == 200
    d = r.get_json()
    assert d["path"] == [1] * 12 and d["slot"] == 12
    assert d["multiplier"] == d["multipliers"][12] and d["payout"] == round(100 * d["multiplier"], 2)
    assert d["balance"] == d["balanceAfterBet"] + d["payout"]


def test_centre_slot_loses_money(make_client):
    c = make_client(plinko_rng=FixedRng([0.1, 0.9] * 6))  # 6 rights, 6 lefts -> slot 6
    d = c.post("/v1/plinko/drop", json={"bet": 100, "rows": 12, "risk": "high"}, headers=auth()).get_json()
    assert d["slot"] == 6 and d["multiplier"] < 1 and d["win"] is False


def test_round_is_recorded_and_verifiable(make_client, store):
    c = make_client()
    d = c.post("/v1/plinko/drop", json={"bet": 50, "rows": 8, "risk": "low"}, headers=auth()).get_json()
    saved = store.docs[f"users/alice/rounds/{d['roundId']}"]
    assert saved["game"] == "plinko" and saved["details"]["path"] == d["path"]
    assert c.get(f"/v1/fairness/verify/{d['roundId']}", headers=auth()).get_json()["status"] == "pending"
    c.post("/v1/fairness/rotate", json={}, headers=auth())
    v = c.get(f"/v1/fairness/verify/{d['roundId']}", headers=auth()).get_json()
    assert v["status"] == "verified" and v["outcomeMatches"] is True


@pytest.mark.parametrize(
    "body",
    [
        {"bet": 1, "rows": 12, "risk": "low"},  # under the minimum
        {"bet": 10_000_000, "rows": 12, "risk": "low"},
        {"bet": "100", "rows": 12, "risk": "low"},
        {"bet": 100, "rows": 7, "risk": "low"},
        {"bet": 100, "rows": 12, "risk": "extreme"},
        {"bet": 100, "rows": True, "risk": "low"},
        {"bet": 100, "rows": 12.5, "risk": "low"},
    ],
)
def test_bad_requests_are_refused(make_client, body):
    c = make_client()
    assert c.post("/v1/plinko/drop", json=body, headers=auth()).status_code == 400


def test_max_bet_is_capped_so_one_drop_cannot_pay_a_fortune(make_client, cfg):
    c = make_client()
    q = c.get("/v1/plinko/quote?rows=16&risk=high", headers={**auth(), "X-Play-Mode": "live"}).get_json()
    assert q["maxBet"] * max(q["multipliers"]) <= cfg.plinko_max_payout
    r = c.post("/v1/plinko/drop", json={"bet": q["maxBet"] + 1000, "rows": 16, "risk": "high"}, headers=auth())
    assert r.status_code == 400 and "most you can bet" in r.get_json()["message"]


def test_not_enough_credits(make_client, store):
    c = make_client()
    c.get("/v1/wallet", headers=auth())
    store.docs["users/alice/wallet/current"]["balance"] = 5
    r = c.post("/v1/plinko/drop", json={"bet": 100, "rows": 12, "risk": "low"}, headers=auth())
    assert r.status_code == 402


def test_catalog_lists_plinko_as_playable(make_client):
    c = make_client()
    games = {g["id"]: g for g in c.get("/v1/games", headers=auth()).get_json()["games"]}
    assert games["plinko"]["comingSoon"] is False and games["plinko"]["type"] == "plinko"
    assert "soon-plinko" not in games


def test_maintenance_blocks_new_drops(make_client):
    c = make_client()
    c.application.extensions["flags"].set_maintenance(True, "all", "Upgrading", "dev")
    r = c.post("/v1/plinko/drop", json={"bet": 100, "rows": 12, "risk": "low"}, headers=auth())
    assert r.status_code == 503 and r.get_json()["error"] == "maintenance"
