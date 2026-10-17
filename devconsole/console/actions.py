"""Things the developer can DO from the console. The browser never sends a command.

Two kinds, both defined here or in ``actions.json``:
  * built-in   talk to a server through the signed developer API (maintenance, migrations, flush)
  * external   a fixed command line from ``actions.json`` (deploy, rollback, backup, run the tests).
               Arguments are a list (no shell), the only variable parts are named parameters that
               must match a pattern, and every run needs a fresh authenticator code and a typed word.

Only one thing runs at a time. Output is kept (capped) and every run is in the audit log.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import threading
import time
import uuid
from pathlib import Path

from . import serverapi
from .config import Config, Target
from .db import DB

MAX_OUTPUT = 200_000
SAFE_ENV = ("PATH", "HOME", "LANG", "CLOUDSDK_CONFIG", "GOOGLE_APPLICATION_CREDENTIALS", "USER")


class ActionError(Exception):
    pass


def load_actions(path: str) -> dict[str, dict]:
    p = Path(path)
    items = json.loads(p.read_text()) if p.is_file() else []
    out = {}
    for a in items:
        if not re.fullmatch(r"[a-z0-9-]{2,40}", a["id"]) or not isinstance(a["argv"], list) or not all(isinstance(x, str) for x in a["argv"]):
            raise ValueError(f"bad action definition: {a.get('id')}")
        out[a["id"]] = a
    return out


def render_argv(action: dict, params: dict) -> list[str]:
    """Fill {name} slots with validated values. Anything not declared, or not matching, is refused."""
    spec = action.get("params") or {}
    values = {}
    for name, rule in spec.items():
        v = str(params.get(name, rule.get("default", "")))
        if not re.fullmatch(rule["pattern"], v):
            raise ActionError(f"'{name}' is not valid ({rule.get('label', name)}).")
        values[name] = v
    extra = set(params) - set(spec)
    if extra:
        raise ActionError("Unknown parameter: " + ", ".join(sorted(extra)))
    argv = []
    for part in action["argv"]:
        argv.append(re.sub(r"\{(\w+)\}", lambda m: values[m.group(1)] if m.group(1) in values else m.group(0), part))
    return argv


class Runner:
    def __init__(self, db: DB, cfg: Config, actions: dict[str, dict]):
        self.db, self.cfg, self.actions = db, cfg, actions
        self._busy = threading.Lock()

    def catalog(self) -> list[dict]:
        return [{"id": a["id"], "label": a["label"], "description": a.get("description", ""), "danger": bool(a.get("danger")), "confirm": a.get("confirm", "RUN"),
                 "params": {k: {"label": v.get("label", k), "default": v.get("default", ""), "pattern": v["pattern"]} for k, v in (a.get("params") or {}).items()},
                 "pre": a.get("pre", []), "post": a.get("post", [])} for a in self.actions.values()]

    def start(self, action_id: str, target: Target | None, params: dict, actor: str, sync: bool = False) -> str:
        a = self.actions.get(action_id)
        if a is None:
            raise ActionError("No such action.")
        argv = render_argv(a, params)
        if not self._busy.acquire(blocking=False):
            raise ActionError("Another action is still running.")
        rid = uuid.uuid4().hex[:12]
        self.db.x("INSERT INTO runs(id,action,target,actor,started,status,output,params) VALUES(?,?,?,?,?,?,?,?)",
                  (rid, action_id, target.name if target else "", actor, time.time(), "running", "", json.dumps(params)))
        job = lambda: self._run(rid, a, argv, target)
        if sync:
            job()
        else:
            threading.Thread(target=job, daemon=True, name=f"run-{rid}").start()
        return rid

    def _log(self, rid: str, text: str) -> None:
        cur = self.db.q("SELECT output FROM runs WHERE id=?", (rid,))[0]["output"]
        self.db.x("UPDATE runs SET output=? WHERE id=?", ((cur + text)[-MAX_OUTPUT:], rid))

    def _hook(self, rid: str, name: str, target: Target | None) -> bool:
        if target is None:
            self._log(rid, f"[{name}] skipped: no target selected\n")
            return True
        if name == "flush":
            r = serverapi.signed(target, "POST", "/internal/dev/flush", {})
        elif name == "maintenance_on":
            r = serverapi.signed(target, "POST", "/internal/dev/maintenance", {"on": True, "scope": "all", "message": "We're upgrading. Back in a few minutes.", "by": "console"})
        elif name == "maintenance_off":
            r = serverapi.signed(target, "POST", "/internal/dev/maintenance", {"on": False, "by": "console"})
        elif name == "smoke":
            from .smoke import run_smoke

            res = run_smoke(target)
            self._log(rid, f"[smoke] {res['passed']} passed, {res['failed']} failed\n" + "".join(f"  {'ok ' if c['ok'] else 'FAIL'} {c['name']}: {c['detail']}\n" for c in res["results"] if not c["ok"]))
            return res["failed"] == 0
        else:
            self._log(rid, f"[{name}] unknown hook\n")
            return False
        self._log(rid, f"[{name}] {'ok' if r.ok else 'failed: HTTP ' + str(r.status) + ' ' + r.error}\n")
        return r.ok

    def _run(self, rid: str, a: dict, argv: list[str], target: Target | None) -> None:
        status = "failed"
        try:
            for h in a.get("pre", []):
                if not self._hook(rid, h, target) and h != "flush":
                    raise ActionError(f"pre-step '{h}' failed; nothing was run")
            cwd = a.get("cwd") or None
            if cwd == "$SERVER_DIR":
                cwd = self.cfg.server_dir
            env = {k: os.environ[k] for k in SAFE_ENV if k in os.environ}
            for k in a.get("env", []):
                if k in os.environ:
                    env[k] = os.environ[k]
            self._log(rid, "$ " + " ".join(argv) + "\n")
            p = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, shell=False)
            deadline = time.time() + int(a.get("timeout", 900))
            killer = threading.Timer(max(1, deadline - time.time()), p.kill)
            killer.start()
            try:
                for line in p.stdout:  # type: ignore[union-attr]
                    self._log(rid, line)
            finally:
                killer.cancel()
            code = p.wait()
            timed_out = time.time() >= deadline and code != 0
            status = "ok" if code == 0 else ("timeout" if timed_out else f"failed (exit {code})")
            if code == 0:
                for h in a.get("post", []):
                    self._hook(rid, h, target)
        except FileNotFoundError as e:
            self._log(rid, f"Could not start: {e}\n")
        except ActionError as e:
            self._log(rid, f"{e}\n")
        except Exception as e:
            self._log(rid, f"Error: {type(e).__name__}: {e}\n")
        finally:
            self.db.x("UPDATE runs SET ended=?, status=? WHERE id=?", (time.time(), status, rid))
            self._busy.release()

    def get(self, rid: str) -> dict | None:
        r = self.db.q("SELECT * FROM runs WHERE id=?", (rid,))
        return dict(r[0]) if r else None

    def recent(self, n: int = 20) -> list[dict]:
        return [{**dict(r), "output": ""} for r in self.db.q("SELECT * FROM runs ORDER BY started DESC LIMIT ?", (n,))]
