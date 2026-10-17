"""Payment-method list, USDT / PayPal / bank payouts and the Live Money Agreement."""
import uuid
from dataclasses import replace

import pytest

from .conftest import auth, staff_headers
from .test_live import deposit, fund, payout, admin, approve, live_balance


@pytest.fixture
def c(make_client):
    return make_client()


TRON = "TQn9Y2khEsLJW1ChVWFMSMeRDow5KcbLSE"
EVM = "0x52908400098527886E0F7030069857D2E4169EE7"


def test_method_list_has_bank_usdt_paypal_with_details(c):
    s = c.get("/v1/live/status", headers=auth()).get_json()
    by = {p["id"]: p for p in s["providers"]}
    assert {"bank_ng", "usdt_trc20", "usdt_bep20", "usdt_erc20", "paypal", "paystack"} <= set(by)
    assert by["bank_ng"]["category"] == "bank" and by["usdt_trc20"]["category"] == "crypto" and by["paypal"]["category"] == "wallet"
    assert by["usdt_trc20"]["network"] == "TRC20" and by["usdt_trc20"]["payCurrency"] == "USDT"
    assert by["paypal"]["destination"] == "paypal" and by["apple_pay"]["payout"] is False


def test_usdt_deposit_quotes_in_usdt_and_credits_after_confirmation(c, store):
    d = deposit(c, 15500, provider="usdt_trc20").get_json()
    assert d["checkout"]["payCurrency"] == "USDT" and d["checkout"]["payAmount"] == 10.0
    assert live_balance(store) == 0
    assert c.post("/v1/live/mock/pay", json={"paymentId": d["id"], "outcome": "success"}, headers=auth()).status_code == 200
    assert c.post(f"/v1/live/deposits/{d['id']}/verify", headers=auth()).get_json()["status"] == "succeeded"
    assert live_balance(store) == 15500


def test_paypal_deposit_quote(c):
    d = deposit(c, 3100, provider="paypal").get_json()
    assert d["checkout"]["payCurrency"] == "USD" and d["checkout"]["payAmount"] == 2.0


def test_usdt_payout_needs_a_valid_address_for_that_network(c, store, admin):
    fund(c, 20000)
    bad = payout(c, provider="usdt_trc20", dest={"address": EVM})
    assert bad.status_code == 400 and bad.get_json()["error"] == "invalid_destination"
    bad2 = payout(c, provider="usdt_erc20", dest={"address": TRON})
    assert bad2.status_code == 400
    ok = payout(c, 5000, provider="usdt_trc20", dest={"address": TRON})
    assert ok.status_code == 200, ok.get_json()
    p = ok.get_json()
    assert p["destination"]["masked"].startswith(TRON[:5]) and TRON not in str(p)  # the full address is never echoed back
    assert live_balance(store) == 15000
    assert approve(c, admin, p).get_json()["status"] == "paid"


def test_paypal_payout_validates_email_and_masks_it(c, store, admin):
    fund(c, 20000)
    assert payout(c, provider="paypal", dest={"email": "not-an-email"}).status_code == 400
    r = payout(c, 4000, provider="paypal", dest={"email": "Ann.Lee@Example.com"})
    assert r.status_code == 200
    assert r.get_json()["destination"]["masked"] == "an***@example.com"
    assert approve(c, admin, r.get_json()).get_json()["status"] == "paid"


def test_bank_payout_still_works_through_the_nigerian_bank_method(c, store):
    fund(c, 20000)
    r = payout(c, 3000, provider="bank_ng", dest={"bankName": "GTBank", "accountName": "Ann Lee", "accountNumber": "0123456789"})
    assert r.status_code == 200 and r.get_json()["destination"]["accountLast4"] == "6789"


# ------------------------------------------------------------------ the agreement

@pytest.fixture
def strict(make_client):
    c = make_client()
    live = c.application.extensions["live"]
    live.cfg = replace(live.cfg, live_agreement_required=True)
    return c


ALL = ["age", "legal", "risk", "agree"]


def live_headers(user="alice"):
    return {**auth(user), "X-Play-Mode": "live"}


def test_agreement_text_is_served_with_the_ticks(strict):
    d = strict.get("/v1/live/agreement", headers=auth()).get_json()
    assert d["accepted"] is False and d["version"] == "1" and len(d["sections"]) >= 8
    assert {x["id"] for x in d["confirmations"]} == set(ALL)


def test_cannot_deposit_or_play_live_before_accepting(strict, store):
    assert deposit(strict).status_code == 403 and deposit(strict).get_json()["error"] == "agreement_required"
    r = strict.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers=live_headers())
    assert r.status_code == 403 and r.get_json()["error"] == "agreement_required"
    assert strict.get("/v1/live/status", headers=auth()).get_json()["agreement"]["accepted"] is False


def test_must_tick_everything_and_use_the_current_version(strict):
    assert strict.post("/v1/live/agreement", json={"version": "1", "confirmed": ["age", "legal"]}, headers=auth()).status_code == 400
    assert strict.post("/v1/live/agreement", json={"version": "0", "confirmed": ALL}, headers=auth()).status_code == 409


def test_accepting_unlocks_live_and_is_remembered(strict, store):
    assert strict.post("/v1/live/agreement", json={"version": "1", "confirmed": ALL}, headers=auth()).status_code == 200
    assert store.docs["users/alice/consents/live"]["version"] == "1"
    assert deposit(strict).status_code == 200
    assert strict.get("/v1/live/status", headers=auth()).get_json()["agreement"]["accepted"] is True
    # someone else still has to accept
    assert deposit(strict, user="bob").status_code == 403


def test_a_new_version_asks_everyone_again(strict):
    strict.post("/v1/live/agreement", json={"version": "1", "confirmed": ALL}, headers=auth())
    live = strict.application.extensions["live"]
    live.cfg = replace(live.cfg, live_agreement_version="2")
    assert deposit(strict).status_code == 403


def test_players_can_still_withdraw_without_accepting_a_new_version(strict, store):
    strict.post("/v1/live/agreement", json={"version": "1", "confirmed": ALL}, headers=auth())
    fund(strict, 5000)
    live = strict.application.extensions["live"]
    live.cfg = replace(live.cfg, live_agreement_version="2")
    r = payout(strict, 2000, provider="bank_ng", dest={"bankName": "GTBank", "accountName": "Ann Lee", "accountNumber": "0123456789"})
    assert r.status_code == 200  # their own money is never held hostage to a new document
