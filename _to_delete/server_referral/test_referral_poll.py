from app.referrals import ReferralService
from app.store import MemoryStore


def _service(cfg):
    store = MemoryStore()
    reads = []
    real = store.list
    store.list = lambda c, *a, **k: (reads.append(c), real(c, *a, **k))[1]
    return ReferralService(store, cfg), reads


def test_idle_worker_makes_no_database_reads(cfg):
    svc, reads = _service(cfg)
    svc.process_due()  # the one look at start-up
    assert len(reads) == 1
    for _ in range(50):  # fifty seconds of an idle worker
        svc.process_due()
    assert len(reads) == 1


def test_a_qualifying_friend_triggers_one_look(cfg):
    svc, reads = _service(cfg)
    svc.process_due()
    svc.notify(0.0)
    svc.process_due(); svc.process_due()
    assert len(reads) == 2


def test_app_opening_is_throttled(cfg):
    svc, reads = _service(cfg)
    svc.process_due()
    svc.kick(60); svc.process_due()
    svc.kick(60); svc.process_due()  # a second app opening straight after: no extra look
    assert len(reads) == 2


def test_database_trouble_backs_off(cfg):
    svc, reads = _service(cfg)
    boom = {"on": True}
    real = svc.store.list

    def flaky(c, *a, **k):
        reads.append(c)
        if boom["on"]:
            raise RuntimeError("quota")
        return real(c, *a, **k)

    svc.store.list = flaky
    try:
        svc.process_due()
    except RuntimeError:
        pass
    for _ in range(20):  # the worker keeps ticking: it must not retry every second
        svc.process_due()
    assert len(reads) == 1
