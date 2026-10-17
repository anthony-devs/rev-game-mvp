"""Dice, roulette, blackjack, fairness, streak, reset, account delete."""
from datetime import timedelta

from .conftest import FixedRng, auth


class StackedRng(FixedRng):
    """shuffle() puts the given cards on top of the deck, in order."""

    def __init__(self, top, values=()):
        super().__init__(values)
        self.top = list(top)

    def shuffle(self, seq):
        rest = [c for c in seq if c not in self.top]
        seq[:] = self.top + rest


def bal(c, user="alice"):
    return c.get("/v1/wallet", headers=auth(user)).get_json()["balance"]


# ---- dice ---------------------------------------------------------------------

def test_dice_win_and_loss_pay_exactly(make_client):
    c = make_client(dice_rng=FixedRng([0.9, 0.1]))  # roll 90.00 then 10.00
    r = c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "over"}, headers=auth()).get_json()
    assert r["win"] and r["roll"] == 90.0 and r["payout"] == round(100 * r["multiplier"], 2)
    assert r["balance"] == 10000 - 100 + r["payout"]
    r2 = c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "over"}, headers=auth()).get_json()
    assert not r2["win"] and r2["payout"] == 0
    assert r2["balance"] == r["balance"] - 100


def test_dice_rejects_bad_input_and_overspend(make_client):
    c = make_client()
    for body in (
        {"bet": 100, "target": 1, "mode": "over"},
        {"bet": 100, "target": 99, "mode": "under"},
        {"bet": 100, "target": 50, "mode": "sideways"},
        {"bet": -5, "target": 50, "mode": "over"},
        {"bet": 5, "target": 50, "mode": "over"},
        {"bet": "x", "target": 50, "mode": "over"},
    ):
        assert c.post("/v1/dice/roll", json=body, headers=auth()).status_code == 400
    r = c.post("/v1/dice/roll", json={"bet": 99999, "target": 50, "mode": "over"}, headers=auth())
    assert r.status_code == 402 and bal(c) == 10000


def test_dice_edge_is_five_percent(make_client):
    c = make_client()
    r = c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers=auth()).get_json()
    assert abs(r["multiplier"] * r["chance"] / 100 - 0.95) < 0.002


# ---- roulette -----------------------------------------------------------------

def test_roulette_payouts(make_client):
    # 7 is red, odd, low, dozen 1
    c = make_client(roulette_rng=FixedRng([7.5 / 37]))
    bets = [
        {"type": "straight", "value": 7, "amount": 10},   # 360
        {"type": "red", "amount": 100},                   # 200
        {"type": "black", "amount": 100},                 # 0
        {"type": "odd", "amount": 50},                    # 100
        {"type": "dozen", "value": 1, "amount": 30},      # 90
        {"type": "high", "amount": 20},                   # 0
    ]
    r = c.post("/v1/roulette/spin", json={"bets": bets}, headers=auth()).get_json()
    assert r["number"] == 7
    assert r["payout"] == 360 + 200 + 100 + 90
    assert r["balance"] == 10000 - 310 + 750


def test_roulette_zero_loses_outside_bets(make_client):
    c = make_client(roulette_rng=FixedRng([0.0]))
    bets = [{"type": "red", "amount": 100}, {"type": "even", "amount": 100}, {"type": "straight", "value": 0, "amount": 10}]
    r = c.post("/v1/roulette/spin", json={"bets": bets}, headers=auth()).get_json()
    assert r["number"] == 0 and r["payout"] == 360


def test_roulette_validation(make_client):
    c = make_client()
    for bets in ([], [{"type": "nope", "amount": 10}], [{"type": "straight", "value": 40, "amount": 10}],
                 [{"type": "red", "amount": 0}], [{"type": "red", "amount": 10 ** 7}]):
        assert c.post("/v1/roulette/spin", json={"bets": bets}, headers=auth()).status_code == 400
    assert bal(c) == 10000


# ---- blackjack ----------------------------------------------------------------
# deal order: player, dealer, player, dealer; then hits come from the top.

def deal(c, bet=100):
    return c.post("/v1/blackjack/deal", json={"bet": bet}, headers=auth())


def act(c, rid, a):
    return c.post(f"/v1/blackjack/{rid}/{a}", headers=auth())


def test_blackjack_natural_pays_three_to_two(make_client):
    c = make_client(bj_rng=StackedRng(["AS", "9H", "KD", "7C"]))
    r = deal(c).get_json()
    assert r["status"] == "done" and r["result"]["outcome"] == "blackjack"
    assert bal(c) == 10000 + 150


def test_blackjack_hidden_card_and_stand_win(make_client):
    c = make_client(bj_rng=StackedRng(["10S", "9H", "9D", "8C", "2S"]))
    r = deal(c).get_json()
    assert r["dealer"][1] == "??" and r["status"] == "player"
    assert bal(c) == 9900
    r = act(c, r["roundId"], "stand").get_json()
    assert "??" not in r["dealer"] and bal(c) == 10100  # 19 beats 17


def test_blackjack_bust_and_push(make_client):
    c = make_client(bj_rng=StackedRng(["10S", "9H", "6D", "8C", "KS"]))
    r = deal(c).get_json()
    r = act(c, r["roundId"], "hit").get_json()  # 16 + K = bust
    assert r["status"] == "done" and r["result"]["outcome"] == "bust" and bal(c) == 9900
    c2 = make_client(bj_rng=StackedRng(["10S", "10H", "8D", "8C"]))  # 18 v 18
    r = deal(c2).get_json()
    r = act(c2, r["roundId"], "stand").get_json()
    assert r["result"]["outcome"] == "push" and bal(c2) == 9900  # shared store: alice already lost 100


def test_blackjack_double(make_client):
    c = make_client(bj_rng=StackedRng(["5S", "9H", "6D", "8C", "KS"]))  # 11 vs 17, double K -> 21
    r = deal(c).get_json()
    assert r["canDouble"]
    r = act(c, r["roundId"], "double").get_json()
    assert bal(c) == 10000 + 200  # staked 200, won 400


def test_blackjack_split_plays_two_hands(make_client):
    # 8 8 v 9 7. Split draws 3 and 2, hit A with K (21, moves on), hit B with K (20), stand, dealer draws 2 -> 18.
    c = make_client(bj_rng=StackedRng(["8S", "9H", "8D", "7C", "3S", "2S", "KS", "KH", "2H"]))
    r = deal(c).get_json()
    assert r["canSplit"] and bal(c) == 9900
    r = act(c, r["roundId"], "split").get_json()
    assert r["split"] and len(r["hands"]) == 2 and r["active"] == 0 and bal(c) == 9800
    assert r["hands"][0]["cards"] == ["8S", "3S"] and r["hands"][1]["cards"] == ["8D", "2S"]
    assert not r["canSplit"]
    r = act(c, r["roundId"], "hit").get_json()  # hand 1 reaches 21 and moves on
    assert r["active"] == 1 and r["status"] == "player"
    r = act(c, r["roundId"], "hit").get_json()  # hand 2: 20
    r = act(c, r["roundId"], "stand").get_json()
    assert r["status"] == "done" and r["result"]["outcome"] == "win"
    assert bal(c) == 10000 + 200  # staked 200, both hands beat 18


def test_blackjack_split_aces_get_one_card_each(make_client):
    c = make_client(bj_rng=StackedRng(["AS", "9H", "AD", "7C", "KS", "5S", "2H"]))
    r = deal(c).get_json()
    r = act(c, r["roundId"], "split").get_json()
    assert r["status"] == "done"  # no further play on split aces
    assert [h["total"] for h in r["hands"]] == [21, 16]
    assert r["result"]["outcome"] == "push" and bal(c) == 10000  # 21 beats 18, 16 loses


def test_blackjack_split_rules(make_client):
    c = make_client(bj_rng=StackedRng(["10S", "9H", "6D", "8C"]))
    r = deal(c).get_json()
    assert not r["canSplit"]
    assert act(c, r["roundId"], "split").status_code == 400
    act(c, r["roundId"], "stand")
    c2 = make_client(bj_rng=StackedRng(["8S", "9H", "8D", "7C", "3S", "2S"]))
    r = deal(c2).get_json()
    assert act(c2, r["roundId"], "split").status_code == 200
    assert act(c2, r["roundId"], "split").status_code == 400  # one split only


def test_blackjack_one_active_hand_and_resume(make_client):
    c = make_client(bj_rng=StackedRng(["10S", "6H", "5D", "10C"]))
    r = deal(c).get_json()
    assert deal(c).status_code == 409
    a = c.get("/v1/blackjack/active", headers=auth()).get_json()["active"]
    assert a["roundId"] == r["roundId"] and a["dealer"][1] == "??"
    assert c.get("/v1/blackjack/active", headers=auth("bob")).get_json()["active"] is None
    assert act(c, "bogus", "hit").status_code in (404, 409)


# ---- fairness -----------------------------------------------------------------

def test_fairness_rotate_reveals_and_verifies_every_game(make_client):
    c = make_client()
    ids = []
    ids.append(c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "over"}, headers=auth()).get_json()["roundId"])
    ids.append(c.post("/v1/roulette/spin", json={"bets": [{"type": "red", "amount": 10}]}, headers=auth()).get_json()["roundId"])
    ids.append(c.post("/v1/slots/spin", json={"bet": 100}, headers=auth()).get_json()["roundId"])
    v = c.get(f"/v1/fairness/verify/{ids[0]}", headers=auth()).get_json()
    assert v["status"] == "pending" and v["serverSeed"] is None
    rot = c.post("/v1/fairness/rotate", json={"clientSeed": "mine"}, headers=auth()).get_json()
    assert rot["revealed"]["serverSeed"] and rot["current"]["clientSeed"] == "mine" and rot["current"]["nonce"] == 0
    for i in ids:
        v = c.get(f"/v1/fairness/verify/{i}", headers=auth()).get_json()
        assert v["status"] == "verified" and v["hashMatches"] and v["outcomeMatches"], v


def test_fairness_blackjack_blocks_rotation_until_hand_ends(make_client):
    c = make_client(bj_rng=StackedRng(["10S", "6H", "5D", "10C"]))
    r = deal(c).get_json()
    assert c.post("/v1/fairness/rotate", json={}, headers=auth()).status_code == 409
    act(c, r["roundId"], "stand")
    assert c.post("/v1/fairness/rotate", json={}, headers=auth()).status_code == 200


def test_fairness_rejects_bad_client_seed_and_other_users_rounds(make_client):
    c = make_client()
    rid = c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "over"}, headers=auth()).get_json()["roundId"]
    assert c.post("/v1/fairness/rotate", json={"clientSeed": "x" * 40}, headers=auth()).status_code == 400
    assert c.get(f"/v1/fairness/verify/{rid}", headers=auth("bob")).status_code == 404


# ---- progress, streak, reset, account ----------------------------------------------

def test_streak_grows_then_resets_after_gap(make_client, clock):
    c = make_client()
    got = []
    for _ in range(3):
        r = c.post("/v1/wallet/claim-daily", headers=auth()).get_json()
        got.append((r["claimed"], r["streakDays"]))
        clock.advance(25 * 3600)
    assert got == [(1000, 1), (1000, 2), (1500, 3)]
    clock.advance(3 * 24 * 3600)
    r = c.post("/v1/wallet/claim-daily", headers=auth()).get_json()
    assert (r["claimed"], r["streakDays"]) == (1000, 1)


def test_reset_restores_starting_balance(make_client):
    c = make_client()
    c.post("/v1/dice/roll", json={"bet": 5000, "target": 50, "mode": "over"}, headers=auth())
    assert c.post("/v1/wallet/reset", headers=auth()).get_json()["balance"] == 10000


def test_rounds_give_xp_and_history(make_client, store):
    c = make_client()
    for _ in range(3):
        c.post("/v1/dice/roll", json={"bet": 1000, "target": 50, "mode": "over"}, headers=auth())
    p = store.docs["users/alice/progress/current"]
    assert p["totalRounds"] == 3 and p["xp"] + (p["level"] - 1) * 500 >= 300
    rounds = [d for k, d in store.docs.items() if "/rounds/" in k]
    assert len(rounds) == 3 and all(d["game"] == "dice" and "fairness" in d for d in rounds)


def test_delete_account_wipes_everything_for_that_user_only(make_client, store, deleted_auth):
    c = make_client()
    for u in ("alice", "bob"):
        c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "over"}, headers=auth(u))
    assert c.delete("/v1/account", headers=auth()).status_code == 200
    assert deleted_auth == ["alice"]
    assert not [k for k in store.docs if "alice" in k]
    assert [k for k in store.docs if "bob" in k]
    assert c.delete("/v1/account").status_code == 401


def test_public_config_has_limits(make_client):
    j = make_client().get("/v1/config").get_json()
    assert j["dice"]["minTarget"] and j["dailyRewards"][-1] == 10000


# ---- legal pages and unsubscribe -------------------------------------------------

def test_legal_pages_are_public_and_complete(make_client):
    c = make_client()
    docs = c.get("/v1/legal").get_json()["documents"]
    assert {d["slug"] for d in docs} == {"terms", "privacy", "refunds", "cookies", "about"}
    for d in docs:
        j = c.get(f"/v1/legal/{d['slug']}").get_json()
        assert j["sections"] and not any("{" in x["body"] for x in j["sections"])
        assert c.get(f"/legal/{d['slug']}").status_code == 200
    assert c.get("/v1/legal/nope").status_code == 404


def test_unsubscribe_link_needs_the_right_token(make_client, store):
    from app import legal
    c = make_client()
    store.docs["users/alice"] = {"email": "a@b.co"}
    assert c.get("/unsubscribe?u=alice&t=bad").status_code == 400
    tok = legal.unsubscribe_token("s" * 32, "alice")
    assert c.get(f"/unsubscribe?u=alice&t={tok}").status_code == 200
    assert store.docs["users/alice"]["emailOptOut"] is True


def test_web_build_can_call_the_server(make_client):
    c = make_client()
    r = c.options("/v1/games", headers={"Origin": "http://localhost:5555", "Access-Control-Request-Method": "GET"})
    assert r.headers.get("Access-Control-Allow-Origin") == "http://localhost:5555"
    assert "Authorization" in r.headers.get("Access-Control-Allow-Headers", "")
    r = c.get("/v1/legal", headers={"Origin": "https://evil.example"})
    assert "Access-Control-Allow-Origin" not in r.headers


def test_fairness_check_works_right_after_a_crash_round_ends(make_client):
    c = make_client(crash_rng=FixedRng([0.5]))
    rid = c.post("/v1/crash/rounds", json={"bet": 100}, headers=auth()).get_json()["roundId"]
    # while the round runs, the check has to wait
    assert c.post("/v1/fairness/rotate", json={}, headers=auth()).status_code == 409
    c.get(f"/v1/crash/rounds/{rid}/events", headers=auth()).get_data()  # plays out to the crash
    assert c.post("/v1/fairness/rotate", json={}, headers=auth()).status_code == 200
