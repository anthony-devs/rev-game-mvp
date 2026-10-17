import threading
import time

from app.config import Config
from app.guard import RequestGuard

from .conftest import ADMIN, auth, staff_headers


def test_guard_refuses_a_second_identical_request_while_the_first_runs():
    g = RequestGuard()
    assert g.enter("k", 0) is True
    assert g.enter("k", 0) is False  # still running
    g.leave("k", ok=False)  # it failed: sending again is fine
    assert g.enter("k", 0) is True


def test_guard_cooloff_after_success_then_allows_again():
    g = RequestGuard()
    assert g.enter("k", 0.2)
    g.leave("k", ok=True)
    assert g.enter("k", 0.2) is False  # just succeeded
    time.sleep(0.25)
    assert g.enter("k", 0.2) is True


def test_guard_is_thread_safe_only_one_of_many_gets_in():
    g = RequestGuard()
    wins = []

    def go():
        if g.enter("same", 0):
            wins.append(1)

    ts = [threading.Thread(target=go) for _ in range(20)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert len(wins) == 1


def test_backoffice_double_submit_is_refused_then_a_real_repeat_works(store, clock, uploads, support, blobs):
    # Build a client with the real 1.5 s cool-off (the shared test config turns it off).
    from app import create_app
    from app.staff import StaffService
    from app.standing import StandingService
    from app.wallet import WalletService
    from app.account import AccountService

    cfg = Config(**{**ADMIN, "dup_cooloff_seconds": 0.3})
    staff = StaffService(store, cfg, clock)
    app = create_app(store=store, cfg=cfg, verifier=lambda t: {"alice": "alice"}[t], staff=staff, standing=StandingService(store, cfg, clock), uploads=uploads, support=support, wallet=WalletService(store, cfg, clock), account=AccountService(store, lambda uid: None))
    c = app.test_client()
    h = staff_headers(c)
    body = {"username": "rep-one", "name": "Rep One", "password": "Str0ng!Passphrase#9"}
    first = c.post("/admin/api/staff", json=body, headers=h)
    again = c.post("/admin/api/staff", json=body, headers=h)  # the impatient second click
    assert first.status_code == 201, first.get_json()
    assert again.status_code == 409 and again.get_json()["error"] == "duplicate_request"
    assert len([k for k in store.docs if k == "staff/rep-one"]) == 1


def test_player_bets_are_never_blocked_when_repeated_one_after_another(make_client):
    c = make_client()
    for _ in range(3):  # same bet three times in a row is normal play
        assert c.post("/v1/dice/roll", json={"bet": 100, "target": 50, "mode": "under"}, headers=auth()).status_code == 200


def test_two_racing_password_changes_cannot_both_apply(store, cfg, staff):
    staff.create_agent("rep-two", "Rep Two", "Str0ng!Passphrase#1", actor="boss")
    # Both requests pass the first check against the same stored password; only one may win.
    import app.staff as staff_mod

    real_verify = staff_mod.verify_password
    barrier = threading.Barrier(2, timeout=5)
    results = []

    def slow_verify(pw, stored):
        ok = real_verify(pw, stored)
        if pw == "Str0ng!Passphrase#1":
            try:
                barrier.wait()
            except threading.BrokenBarrierError:
                pass
        return ok

    staff_mod.verify_password = slow_verify
    try:
        def change(new):
            try:
                staff.change_own_password("rep-two", "Str0ng!Passphrase#1", new)
                results.append("ok")
            except Exception as e:  # noqa: BLE001
                results.append(getattr(e, "code", type(e).__name__))

        ts = [threading.Thread(target=change, args=(p,)) for p in ("Another!Passphrase#22", "Third!Passphrase#333")]
        [t.start() for t in ts]
        [t.join() for t in ts]
    finally:
        staff_mod.verify_password = real_verify
    assert results.count("ok") == 1 and len(results) == 2
