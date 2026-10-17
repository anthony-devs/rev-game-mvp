import json
import random

from app.config import Config
from app.slots import PAY_ROWS, RTP, SlotsService
from app.store import MemoryStore

from .conftest import FixedRng, auth


# ---- auth ------------------------------------------------------------------

def test_requires_token(make_client):
    c = make_client()
    assert c.get("/v1/wallet").status_code == 401
    assert c.get("/v1/wallet", headers={"Authorization": "Bearer nobody"}).status_code == 401
    assert c.get("/healthz").status_code == 200


# ---- wallet ----------------------------------------------------------------

def test_wallet_created_with_starting_balance(make_client):
    c = make_client()
    r = c.get("/v1/wallet", headers=auth())
    assert r.json["balance"] == 10000


def test_daily_claim_once_per_day(make_client, clock):
    c = make_client()
    r = c.post("/v1/wallet/claim-daily", headers=auth())
    assert r.status_code == 200 and r.json["balance"] == 11000
    r = c.post("/v1/wallet/claim-daily", headers=auth())
    assert r.status_code == 429 and r.json["error"] == "daily_not_ready" and r.json["secondsLeft"] == 86400
    clock.advance(86400)
    assert c.post("/v1/wallet/claim-daily", headers=auth()).json["balance"] == 12000


def test_top_up_only_refills(make_client, store):
    c = make_client()
    assert c.post("/v1/wallet/top-up", headers=auth()).json["balance"] == 10000
    store.wallets["alice"]["balance"] = 5
    assert c.post("/v1/wallet/top-up", headers=auth()).json["balance"] == 10000
    store.wallets["alice"]["balance"] = 50000
    assert c.post("/v1/wallet/top-up", headers=auth()).json["balance"] == 50000


# ---- slots -----------------------------------------------------------------

def test_slots_config(make_client):
    r = make_client().get("/v1/slots/config", headers=auth())
    assert r.json["betSteps"][0] == 10 and r.json["startBalance"] == 10000
    assert abs(r.json["rtp"] - 0.96) < 1e-9
    assert [p["multiplier"] for p in r.json["payRows"]][0] == 100


def test_slots_rtp_matches_table():
    assert abs(RTP - 0.96) < 1e-9
    assert abs(sum(r.probability for r in PAY_ROWS) - 0.2904) < 1e-9


def test_slots_win_pays_and_logs(make_client, store):
    c = make_client(slots_rng=FixedRng([0.0001]))  # first row: three sevens
    r = c.post("/v1/slots/spin", json={"bet": 100}, headers=auth())
    assert r.status_code == 200
    j = r.json
    assert j["multiplier"] == 100 and j["payout"] == 10000
    assert j["balanceAfterBet"] == 9900 and j["balance"] == 19900
    assert [col[1] for col in j["columns"]] == ["seven"] * 3
    assert store.wallets["alice"]["balance"] == 19900
    assert len(store.rounds) == 1


def test_slots_loss_never_looks_like_a_win(make_client):
    c = make_client(slots_rng=FixedRng([0.99] * 200))
    for _ in range(200):
        j = c.post("/v1/slots/spin", json={"bet": 10}, headers=auth()).json
        mid = [col[1] for col in j["columns"]]
        assert j["multiplier"] == 0
        assert not (mid[0] == mid[1] == mid[2]) and mid.count("cherry") != 2


def test_slots_two_cherries(make_client):
    c = make_client(slots_rng=FixedRng([0.1]))
    j = c.post("/v1/slots/spin", json={"bet": 10}, headers=auth()).json
    mid = [col[1] for col in j["columns"]]
    assert j["multiplier"] == 2 and mid.count("cherry") == 2


def test_slots_rejects_bad_bets(make_client, store):
    c = make_client()
    for bet in (0, -10, 15, "100", None, True, 10_000):
        r = c.post("/v1/slots/spin", json={"bet": bet}, headers=auth())
        assert r.status_code == 400 and r.json["error"] == "invalid_bet", bet
    assert c.post("/v1/slots/spin", data="nope", headers=auth()).status_code == 400
    assert store.wallets.get("alice") is None  # nothing was charged or created


def test_slots_insufficient_credits(make_client, store):
    c = make_client()
    c.get("/v1/wallet", headers=auth())
    store.wallets["alice"]["balance"] = 50
    r = c.post("/v1/slots/spin", json={"bet": 100}, headers=auth())
    assert r.status_code == 402 and r.json["error"] == "insufficient_credits"
    assert store.wallets["alice"]["balance"] == 50


def test_slots_long_run_rtp(cfg):
    svc = SlotsService(MemoryStore(), cfg, rng=random.Random(7))
    n, paid = 200_000, 0
    for _ in range(n):
        m, _line, _label = svc._draw()
        paid += m
    assert 0.93 < paid / n < 0.99


# ---- crash -----------------------------------------------------------------

def start(c, bet=100, auto=None, user="alice"):
    body = {"bet": bet}
    if auto is not None:
        body["autoCashout"] = auto
    return c.post("/v1/crash/rounds", json=body, headers=auth(user))


def test_crash_start_takes_bet_and_hides_crash_point(make_client, store):
    c = make_client(crash_rng=FixedRng([0.5]))
    r = start(c)
    assert r.status_code == 200
    assert r.json["balance"] == 9900 and r.json["growthRate"] == 0.12
    assert "crashPoint" not in json.dumps(r.json)
    rid = r.json["roundId"]
    assert store.crash[rid]["crashPoint"] == 1.94  # floor(100*0.97/0.5)/100


def test_crash_cashout_pays_server_clock(make_client, clock, store):
    c = make_client(crash_rng=FixedRng([0.9]))  # crash point 9.70
    rid = start(c).json["roundId"]
    clock.advance(10)  # exp(1.2) = 3.32
    r = c.post(f"/v1/crash/rounds/{rid}/cashout", headers=auth())
    assert r.status_code == 200
    assert r.json["multiplier"] == 3.32 and r.json["payout"] == 332.0
    assert r.json["balance"] == 9900 + 332
    again = c.post(f"/v1/crash/rounds/{rid}/cashout", headers=auth())
    assert again.status_code == 409 and again.json["error"] == "already_settled"
    assert store.wallets["alice"]["balance"] == 10232


def test_crash_too_late(make_client, clock, store):
    c = make_client(crash_rng=FixedRng([0.5]))  # crash 1.94 at ~5.5s
    rid = start(c).json["roundId"]
    clock.advance(30)
    r = c.post(f"/v1/crash/rounds/{rid}/cashout", headers=auth())
    assert r.status_code == 409 and r.json["error"] == "too_late" and r.json["crashPoint"] == 1.94
    assert store.wallets["alice"]["balance"] == 9900


def test_crash_other_player_cannot_touch_round(make_client):
    c = make_client(crash_rng=FixedRng([0.9]))
    rid = start(c).json["roundId"]
    r = c.post(f"/v1/crash/rounds/{rid}/cashout", headers=auth("bob"))
    assert r.status_code == 404


def test_crash_validation(make_client):
    c = make_client()
    for bet in (0, 5, 10**7, "x", None):
        assert start(c, bet).status_code == 400
    assert start(c, 100, auto=1.0).status_code == 400
    assert start(c, 100, auto=500).status_code == 400
    assert start(c, 20000).status_code == 402


def events(c, rid):
    r = c.get(f"/v1/crash/rounds/{rid}/events", headers=auth())
    assert r.status_code == 200 and r.mimetype == "text/event-stream"
    out = []
    for block in r.get_data(as_text=True).split("\n\n"):
        if block.startswith("event:"):
            name, data = block.split("\n")
            out.append((name[7:], json.loads(data[6:])))
    return out


def test_crash_stream_ends_with_crash(make_client, store):
    c = make_client(crash_rng=FixedRng([0.5]))
    rid = start(c).json["roundId"]
    ev = events(c, rid)
    assert [n for n, _ in ev] == ["open", "crashed"]
    assert ev[-1][1] == {"crashPoint": 1.94, "balance": 9900}
    assert store.crash[rid]["status"] == "crashed"


def test_crash_auto_cashout_wins(make_client, store):
    c = make_client(crash_rng=FixedRng([0.9]))  # crash 9.70
    rid = start(c, 100, auto=2.0).json["roundId"]
    ev = events(c, rid)
    names = [n for n, _ in ev]
    assert names == ["open", "cashedOut", "crashed"]
    assert ev[1][1]["multiplier"] == 2.0 and ev[1][1]["payout"] == 200
    assert ev[2][1]["balance"] == 10100
    assert store.wallets["alice"]["balance"] == 10100


def test_crash_auto_above_crash_point_loses(make_client, store):
    c = make_client(crash_rng=FixedRng([0.5]))  # crash 1.94
    rid = start(c, 100, auto=3.0).json["roundId"]
    names = [n for n, _ in events(c, rid)]
    assert names == ["open", "crashed"]
    assert store.wallets["alice"]["balance"] == 9900


def test_crash_late_cashout_still_pays_reached_auto(make_client, clock, store):
    c = make_client(crash_rng=FixedRng([0.9]))
    rid = start(c, 100, auto=2.0).json["roundId"]
    clock.advance(100)  # long after the crash, nobody settled yet
    r = c.post(f"/v1/crash/rounds/{rid}/cashout", headers=auth())
    assert r.status_code == 200 and r.json["multiplier"] == 2.0
    assert store.wallets["alice"]["balance"] == 10100


def test_crash_house_edge_long_run(cfg):
    from app.crash import CrashService

    svc = CrashService(MemoryStore(), cfg, rng=random.Random(3))
    n = 200_000
    # Always cash out at 2.0: should win ~ (1-edge)/2 of the time, so RTP ~ 0.97.
    wins = sum(1 for _ in range(n) if svc.draw_crash_point() >= 2.0)
    assert 0.94 < 2 * wins / n < 1.0


def test_games_list_defaults_and_overrides(make_client, store):
    c = make_client()
    r = c.get("/v1/games", headers=auth())
    assert r.status_code == 200
    games = {g["id"]: g for g in r.json["games"]}
    assert games["slots"]["name"] == "Golden Reels" and games["slots"]["enabled"] is True
    assert games["soon-plinko"]["comingSoon"] is True
    store.docs["games/dice"] = {"enabled": False, "name": "Dice Deluxe", "bogus": 1}
    store.docs["games/new-one"] = {"name": "New One", "type": "crash", "sortOrder": 6}
    # The list is cached for a few seconds, so a console edit shows up on the next refresh.
    assert {g["id"]: g for g in c.get("/v1/games", headers=auth()).json["games"]}["dice"]["enabled"] is True
    c.application.extensions["catalog"].invalidate()
    out = c.get("/v1/games", headers=auth()).json["games"]
    games = {g["id"]: g for g in out}
    assert games["dice"]["enabled"] is False and games["dice"]["name"] == "Dice Deluxe" and "bogus" not in games["dice"]
    assert games["new-one"]["type"] == "crash"
    ids = [g["id"] for g in out]
    assert ids.index("slots") < ids.index("crash") < ids.index("new-one")


def test_games_requires_sign_in(make_client):
    assert make_client().get("/v1/games").status_code == 401


def test_games_503_when_database_not_ready(make_client, store, monkeypatch):
    c = make_client()

    def boom(*a, **k):
        raise RuntimeError("no credentials")

    monkeypatch.setattr(store, "list", boom)
    r = c.get("/v1/games", headers=auth())
    assert r.status_code == 503 and r.json["error"] == "not_initialized"
