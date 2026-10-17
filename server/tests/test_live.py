"""Live play: money must never be credited twice or paid twice."""
import threading
import uuid

import pytest

from .conftest import auth, staff_headers


def key():
    return uuid.uuid4().hex


@pytest.fixture
def c(make_client):
    return make_client()


@pytest.fixture
def live(c):
    return c.application.extensions["live"]


def live_balance(store, uid="alice"):
    return (store.docs.get(f"users/L_{uid}/wallet/current") or {}).get("balance", 0)


def deposit(c, amount=5000, provider="paystack", k=None, user="alice"):
    return c.post("/v1/live/deposits", json={"provider": provider, "amount": amount, "key": k or key()}, headers=auth(user))


def pay_mock(c, pid, outcome="success", user="alice"):
    assert c.post("/v1/live/mock/pay", json={"paymentId": pid, "outcome": outcome}, headers=auth(user)).status_code == 200


def fund(c, amount=5000, user="alice"):
    d = deposit(c, amount, user=user).get_json()
    pay_mock(c, d["id"], user=user)
    r = c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth(user))
    assert r.get_json()["status"] == "succeeded"
    return d["id"]


# ------------------------------------------------------------------ deposits

def test_deposit_credits_only_after_provider_confirms(c, store):
    d = deposit(c).get_json()
    assert d["status"] == "pending" and d["checkout"]["type"] == "mock"
    # Asking before the customer paid changes nothing.
    assert c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth()).get_json()["status"] == "pending"
    assert live_balance(store) == 0
    pay_mock(c, d["id"])
    assert c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth()).get_json()["status"] == "succeeded"
    assert live_balance(store) == 5000


def test_double_tap_same_key_makes_one_payment(c, store):
    k = key()
    a = deposit(c, k=k).get_json()
    b = deposit(c, k=k).get_json()
    assert a["id"] == b["id"]
    pay_mock(c, a["id"])
    for _ in range(3):
        c.post(f"/v1/live/deposits/{a['id']}/verify", headers=auth())
    assert live_balance(store) == 5000
    assert len(c.get("/v1/live/payments", headers=auth()).get_json()["payments"]) == 1


def test_reopened_sheet_with_new_key_reuses_the_open_payment(c):
    a = deposit(c).get_json()
    b = deposit(c).get_json()  # different key, same provider + amount, seconds later
    assert a["id"] == b["id"]
    assert deposit(c, 7000).get_json()["id"] != a["id"]


def test_verify_and_webhook_together_credit_once(c, live, store):
    d = deposit(c).get_json()
    pay_mock(c, d["id"])
    raw, headers = live.providers["paystack"].webhook_body(d["checkout"]["ref"])
    for _ in range(2):
        assert c.post("/v1/live/webhooks/paystack", data=raw, headers=headers).status_code == 200
    c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth())
    c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth())
    assert live_balance(store) == 5000


def test_webhook_needs_a_valid_signature(c, live, store):
    d = deposit(c).get_json()
    pay_mock(c, d["id"])
    raw, _ = live.providers["paystack"].webhook_body(d["checkout"]["ref"])
    assert c.post("/v1/live/webhooks/paystack", data=raw, headers={"X-Mock-Signature": "nope"}).status_code == 401
    assert live_balance(store) == 0


def test_concurrent_verifies_credit_once(c, store):
    d = deposit(c).get_json()
    pay_mock(c, d["id"])
    threads = [threading.Thread(target=lambda: c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth())) for _ in range(8)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert live_balance(store) == 5000


def test_failed_payment_credits_nothing(c, store):
    d = deposit(c).get_json()
    pay_mock(c, d["id"], "fail")
    assert c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth()).get_json()["status"] == "failed"
    pay_mock(c, d["id"])  # too late: a failed payment can't be revived
    c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth())
    assert live_balance(store) == 0


def test_amount_mismatch_is_flagged_not_credited(c, live, store):
    d = deposit(c).get_json()
    store.docs[f"mock_charges/{d['checkout']['ref']}"]["status"] = "success"
    store.docs[f"mock_charges/{d['checkout']['ref']}"]["amount"] = 1  # provider says they paid less
    assert c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth()).get_json()["status"] == "flagged"
    assert live_balance(store) == 0


def test_deposit_validation(c):
    assert deposit(c, 10).status_code == 400  # under the minimum
    assert deposit(c, 5000, provider="nope").status_code == 400
    assert c.post("/v1/live/deposits", json={"provider": "paystack", "amount": 5000}, headers=auth()).status_code == 400  # no key
    k = key()
    assert deposit(c, 5000, k=k).status_code == 200
    assert deposit(c, 6000, k=k).status_code == 409  # same key, different request


def test_nobody_else_can_verify_my_deposit(c):
    d = deposit(c).get_json()
    assert c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth("bob")).status_code == 404


def test_apple_and_google_pay_cannot_pay_out(c):
    fund(c)
    r = c.post("/v1/live/payouts", json={"provider": "apple_pay", "amount": 1000, "key": key(), "destination": DEST}, headers=auth())
    assert r.status_code == 400


# ------------------------------------------------------------------ payouts

DEST = {"bankName": "GTBank", "accountName": "Anthony Ude", "accountNumber": "0123456789"}


def payout(c, amount=2000, k=None, dest=None, user="alice", provider="paystack"):
    return c.post("/v1/live/payouts", json={"provider": provider, "amount": amount, "key": k or key(), "destination": dest or DEST}, headers=auth(user))


@pytest.fixture
def admin(c):
    return staff_headers(c)


def approve(c, admin, p, confirm=None):
    return c.post(f"/admin/api/payments/{p['id']}/approve", json={"confirm": confirm or p["reference"]}, headers=admin)


def test_payout_holds_the_money_and_waits_for_review(c, store, admin):
    fund(c, 5000)
    p = payout(c, 2000).get_json()
    assert p["status"] == "pending_review" and live_balance(store) == 3000
    assert store.docs.get(f"mock_payouts/{p['id']}") is None  # nothing sent without an admin


def test_payout_double_tap_makes_one_payout(c, store):
    fund(c, 5000)
    k = key()
    a, b = payout(c, 2000, k=k).get_json(), payout(c, 2000, k=k).get_json()
    assert a["id"] == b["id"] and live_balance(store) == 3000


def test_cannot_withdraw_more_than_the_balance(c, store):
    fund(c, 5000)
    assert payout(c, 6000).status_code == 402
    payout(c, 4000)
    assert payout(c, 4000).status_code == 402  # the first one already holds the money
    assert live_balance(store) == 1000


def test_admin_must_type_the_reference_for_that_payout(c, admin, store):
    fund(c, 5000)
    p = payout(c).get_json()
    assert approve(c, admin, p, confirm="WRONG1").status_code == 400
    other = payout(c, 1000).get_json()
    assert approve(c, admin, p, confirm=other["reference"]).status_code == 400  # another payout's reference doesn't work
    assert approve(c, admin, p).get_json()["status"] == "paid"


def test_players_cannot_approve_anything(c):
    fund(c, 5000)
    p = payout(c).get_json()
    assert c.post(f"/admin/api/payments/{p['id']}/approve", json={"confirm": p["reference"]}, headers=auth()).status_code == 401


def test_approving_twice_pays_once(c, admin, store, live):
    fund(c, 5000)
    p = payout(c).get_json()
    assert approve(c, admin, p).status_code == 200
    assert approve(c, admin, p).status_code == 409
    assert c.post(f"/admin/api/payments/{p['id']}/retry", headers=admin).status_code == 409  # paid, nothing to retry
    paid = [k for k in store.docs if k.startswith("mock_payouts/")]
    assert len(paid) == 1


def test_provider_is_idempotent_even_if_asked_twice(c, live, store):
    fund(c, 5000)
    p = payout(c).get_json()
    doc = store.docs[f"payments/{p['id']}"]
    prov = live.providers["paystack"]
    a, b = prov.send_payout(doc), prov.send_payout(doc)
    assert a["ref"] == b["ref"] and len([k for k in store.docs if k.startswith("mock_payouts/")]) == 1


def test_concurrent_approvals_pay_once(c, admin, store):
    fund(c, 5000)
    p = payout(c).get_json()
    results = []
    ts = [threading.Thread(target=lambda: results.append(approve(c, admin, p).status_code)) for _ in range(6)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert sorted(results).count(200) == 1
    assert len([k for k in store.docs if k.startswith("mock_payouts/")]) == 1


def test_reject_refunds_once(c, admin, store):
    fund(c, 5000)
    p = payout(c, 2000).get_json()
    assert live_balance(store) == 3000
    r = c.post(f"/admin/api/payments/{p['id']}/reject", json={"reason": "Name does not match"}, headers=admin)
    assert r.get_json()["status"] == "rejected" and live_balance(store) == 5000
    assert c.post(f"/admin/api/payments/{p['id']}/reject", json={"reason": "again"}, headers=admin).status_code == 409
    assert approve(c, admin, p).status_code == 409  # a rejected payout can't be paid
    assert live_balance(store) == 5000


def test_cannot_reject_a_paid_payout(c, admin, store):
    fund(c, 5000)
    p = payout(c, 2000).get_json()
    approve(c, admin, p)
    assert c.post(f"/admin/api/payments/{p['id']}/reject", json={"reason": "too late"}, headers=admin).status_code == 409
    assert live_balance(store) == 3000


def test_failed_payout_can_be_retried_or_refunded_but_not_both_paid(c, admin, store):
    fund(c, 5000)
    bad = dict(DEST, accountNumber="1234560000")  # the mock bank rejects this
    p = payout(c, 2000, dest=bad).get_json()
    assert approve(c, admin, p).get_json()["status"] == "failed"
    assert live_balance(store) == 3000  # still held
    r = c.post(f"/admin/api/payments/{p['id']}/reject", json={"reason": "Bank rejected the account"}, headers=admin)
    assert r.get_json()["status"] == "rejected" and live_balance(store) == 5000


def test_pending_payout_syncs_to_paid_without_refund(c, admin, store):
    fund(c, 5000)
    p = payout(c, 2000, dest=dict(DEST, accountNumber="1234569999")).get_json()
    assert approve(c, admin, p).get_json()["status"] == "processing"
    # Can't refund something the bank still has.
    assert c.post(f"/admin/api/payments/{p['id']}/reject", json={"reason": "not yet"}, headers=admin).status_code == 409
    assert c.post(f"/admin/api/payments/{p['id']}/sync", headers=admin).get_json()["status"] == "paid"
    assert live_balance(store) == 3000


def test_restricted_account_cannot_deposit_or_withdraw(c, standing, store):
    fund(c, 5000)
    store.docs["users/alice/account/standing"] = {
        "active": [{"id": "x", "type": "ban", "blocksPlay": True, "expiresAt": None}], "probationUntil": None, "updatedAt": None,
    }
    standing._cache.clear()
    assert payout(c).status_code == 403
    assert deposit(c).status_code == 403


def test_account_with_live_money_cannot_be_deleted(c, store):
    fund(c, 5000)
    assert c.delete("/v1/account", headers=auth()).status_code == 409


def test_open_payout_limit(c):
    fund(c, 50000)
    for _ in range(3):
        assert payout(c, 1000).status_code == 200
    assert payout(c, 1000).status_code == 429


# ------------------------------------------------------------------ live play

def test_live_play_uses_the_live_wallet_not_demo(c, store):
    demo_before = store.docs.get("users/alice/wallet/current")
    fund(c, 5000)
    r = c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers={**auth(), "X-Play-Mode": "live"})
    assert r.status_code == 200
    j = r.get_json()
    assert live_balance(store) == j["balance"] and j["balanceAfterBet"] == 4900
    assert store.docs.get("users/alice/wallet/current") == demo_before  # demo credits untouched
    assert any(k.startswith("users/L_alice/rounds/") for k in store.docs)


def test_live_play_with_no_deposit_is_refused_not_given_free_credits(c, store):
    r = c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers={**auth("bob"), "X-Play-Mode": "live"})
    assert r.status_code == 402
    assert live_balance(store, "bob") == 0


def test_demo_play_is_unchanged(c, store):
    r = c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers=auth())
    assert r.status_code == 200 and "users/L_alice/wallet/current" not in store.docs


def test_free_credit_endpoints_ignore_live_mode(c, store):
    fund(c, 5000)
    c.post("/v1/wallet/top-up", headers={**auth(), "X-Play-Mode": "live"})
    assert live_balance(store) == 5000


def test_live_switched_off(make_client):
    from dataclasses import replace
    from app.config import Config
    c = make_client()
    c.application.extensions["live"].cfg = replace(c.application.extensions["live"].cfg, live_enabled=False)
    assert deposit(c).status_code == 403
    assert c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers={**auth(), "X-Play-Mode": "live"}).status_code == 403


def test_fake_gateways_refuse_to_run_on_cloud_run(c, monkeypatch):
    monkeypatch.setenv("K_SERVICE", "rev-games")
    assert deposit(c).status_code == 403
    assert c.get("/v1/live/status", headers=auth()).get_json()["enabled"] is False


def test_admin_payments_page_is_served(c):
    r = c.get("/admin/payments")
    assert r.status_code == 200 and b"Payments" in r.data


def test_admin_list_and_detail(c, admin):
    fund(c, 5000)
    p = payout(c).get_json()
    rows = c.get("/admin/api/payments?kind=payout&status=pending_review", headers=admin).get_json()["payments"]
    assert [r["id"] for r in rows] == [p["id"]] and rows[0]["code"] == p["reference"]
    d = c.get(f"/admin/api/payments/{p['id']}", headers=admin).get_json()
    assert d["player"]["totalDeposited"] == 5000 and d["player"]["liveBalance"] == 3000


# ------------------------------------------------------------------ odds by mode

def test_demo_dice_pays_more_than_live(make_client):
    from dataclasses import replace
    from app.config import Config
    from app.dice import DiceService
    from app.store import MemoryStore

    cfg = Config()  # the real defaults, not the neutral test ones
    svc = DiceService(MemoryStore(), cfg)
    demo, live = svc.quote(50, "under", svc.edge_for("alice")), svc.quote(50, "under", svc.edge_for("L_alice"))
    assert demo["multiplier"] > 2.2 and live["multiplier"] < 1.95  # 115% back vs 95% back


def test_demo_odds_on_every_game_beat_live_with_real_defaults():
    from app.config import Config
    from app.slots import RTP, PAY_ROWS
    cfg = Config()
    assert cfg.demo_dice_edge < 0 < cfg.dice_house_edge
    assert cfg.demo_crash_edge < 0 < cfg.crash_house_edge
    assert RTP * cfg.demo_slots_factor > 1.2 > 1.0 > RTP * cfg.live_slots_factor
    assert sum(r.probability for r in PAY_ROWS) * cfg.demo_slots_factor < 0.9  # demo can still lose
    assert cfg.demo_win_boost > 0


def test_roulette_winnings_pay_extra_in_demo_only():
    from dataclasses import replace
    from app.config import Config
    from app.fairness import FairnessService
    from app.roulette import RouletteService
    from app.store import MemoryStore
    from .conftest import FixedRng

    cfg = replace(Config(), demo_win_boost=0.5)
    for uid, expect in (("alice", 250.0), ("L_alice", 200.0)):  # red 1 wins: 2x back; demo adds 50% of the 100 profit
        s = MemoryStore()
        s.docs[f"users/{uid}/wallet/current"] = {"balance": 1000.0, "lastDailyClaimAt": None}
        svc = RouletteService(s, cfg, fair=FairnessService(s, rng_override=FixedRng([1.5 / 37])))
        assert svc.spin(uid, [{"type": "red", "amount": 100}])["payout"] == expect


def test_slots_hit_more_often_in_demo_than_live():
    import random
    from dataclasses import replace
    from app.config import Config
    from app.slots import SlotsService
    from app.store import MemoryStore

    cfg = Config()
    svc = SlotsService(MemoryStore(), cfg)
    n = 40000
    rate = {}
    for name, f in (("demo", cfg.demo_slots_factor), ("live", cfg.live_slots_factor)):
        r = random.Random(7)
        rate[name] = sum(svc._draw(r, f)[0] > 0 for _ in range(n)) / n
    assert rate["demo"] > rate["live"] * 1.4


def test_crash_demo_never_busts_below_its_floor():
    import random
    from app.config import Config
    from app.crash import CrashService
    from app.store import MemoryStore

    cfg = Config()
    svc = CrashService(MemoryStore(), cfg, rng=random.Random(3))
    r = random.Random(5)
    assert min(svc.draw_crash_point(r, cfg.demo_crash_edge) for _ in range(5000)) >= 1.15
    assert min(svc.draw_crash_point(r, cfg.crash_house_edge) for _ in range(5000)) <= 1.05
