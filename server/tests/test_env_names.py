import os
import subprocess
import sys
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1]


def read(env: dict, expr: str) -> str:
    code = f"from app.config import Config; c = Config(); print({expr})"
    run_env = {k: v for k, v in os.environ.items() if not k.endswith(("_LIVE", "_DEMO")) and k not in ("DICE_HOUSE_EDGE", "DEMO_WIN_BOOST")}
    out = subprocess.run([sys.executable, "-c", code], cwd=SERVER, env={**run_env, **env}, capture_output=True, text=True, check=True)
    return out.stdout.strip()


def test_new_live_and_demo_names_work():
    assert read({"DICE_EDGE_LIVE": "0.08", "DICE_EDGE_DEMO": "-0.5"}, "(c.dice_house_edge, c.demo_dice_edge)") == "(0.08, -0.5)"
    assert read({"SLOTS_LUCK_LIVE": "0.8", "WIN_BOOST_LIVE": "-0.1"}, "(c.live_slots_factor, c.live_win_boost)") == "(0.8, -0.1)"


def test_old_names_still_work_and_new_ones_win():
    assert read({"DICE_HOUSE_EDGE": "0.07"}, "c.dice_house_edge") == "0.07"
    assert read({"DICE_HOUSE_EDGE": "0.07", "DICE_EDGE_LIVE": "0.09"}, "c.dice_house_edge") == "0.09"
    assert read({"DEMO_WIN_BOOST": "0.2"}, "c.demo_win_boost") == "0.2"


def test_live_win_boost_cannot_be_positive_or_wipe_out_wins():
    assert read({"WIN_BOOST_LIVE": "0.5"}, "c.live_win_boost") == "0.0"
    assert read({"WIN_BOOST_LIVE": "-5"}, "c.live_win_boost") == "-0.9"
