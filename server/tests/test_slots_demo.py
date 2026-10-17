import random

from app.slots import DEMO_PAY_ODDS, PAY_ROWS, SlotsService


def test_demo_slots_land_777_now_and_then_but_live_almost_never(cfg, store):
    svc = SlotsService(store, cfg)
    rng = random.Random(7)
    n = 20000
    demo = sum(1 for _ in range(n) if svc._draw(rng, 1.0, True)[0] == 100)
    live = sum(1 for _ in range(n) if svc._draw(rng, cfg.live_slots_factor, False)[0] == 100)
    assert 0.012 < demo / n < 0.03  # roughly 1 spin in 50
    assert live / n < 0.002  # roughly 1 in 2,500
    assert sum(DEMO_PAY_ODDS) < 0.6 and len(DEMO_PAY_ODDS) == len(PAY_ROWS)
