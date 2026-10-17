"""Watches every server from outside it, so it notices when the server itself is down.

Every PROBE_SECONDS: GET /healthz (is it up, how fast). Every few probes: the signed diagnostics
(error rate, latency, database, config sanity). Two failed checks in a row open an incident and
send an alert; the first good check closes it. Problems are derived from the numbers, with a
plain explanation, and alerted once (not every 30 seconds).
"""
from __future__ import annotations

import json
import logging
import socket
import ssl
import threading
import time
from datetime import datetime, timezone
from urllib.parse import urlparse

import requests

from . import serverapi
from .config import Config, Target
from .db import DB

log = logging.getLogger("monitor")
DEEP_EVERY = 4
FAILS_TO_OPEN = 2
REALERT_SECONDS = 1800
KEEP_SECONDS = 7 * 86400


def problems_from(health_ok: bool, ms: float, diag: dict | None, dbcheck: dict | None, cert_days: float | None) -> list[dict]:
    """Pure function: numbers in, a list of {severity, code, text} out. severity: critical | warning | info."""
    out = []

    def add(sev, code, text):
        out.append({"severity": sev, "code": code, "text": text})

    if not health_ok:
        add("critical", "down", "The server did not answer its health check.")
        return out
    if ms > 2000:
        add("warning", "slow_health", f"The health check took {ms:.0f} ms.")
    if cert_days is not None and cert_days < 14:
        add("critical" if cert_days < 3 else "warning", "cert_expiring", f"The HTTPS certificate expires in {cert_days:.0f} days.")
    if dbcheck is not None and not dbcheck.get("ok"):
        if dbcheck.get("quota"):
            add("critical", "db_quota", "Firestore's daily quota is used up. Games and dashboards will fail until it resets or billing is enabled.")
        else:
            add("critical", "db_down", f"The database check failed: {dbcheck.get('error') or 'unknown'}.")
    if diag:
        m, c = diag.get("metrics", {}), diag.get("checks", {})
        if m.get("requests", 0) >= 20 and m.get("errorRate", 0) >= 0.05:
            add("critical", "error_rate", f"{m['errorRate'] * 100:.1f}% of the last {m['requests']} requests failed.")
        elif m.get("requests", 0) >= 20 and m.get("errorRate", 0) >= 0.01:
            add("warning", "error_rate", f"{m['errorRate'] * 100:.1f}% of recent requests failed.")
        if m.get("requests", 0) >= 20 and m.get("p95", 0) > 2000:
            add("warning", "slow", f"Slow: 1 in 20 requests takes over {m['p95']:.0f} ms.")
        if m.get("quotaErrors", 0):
            add("critical", "quota_errors", f"{m['quotaErrors']} requests hit the Firestore quota since the server started.")
        if m.get("flushFailures", 0):
            add("warning", "metrics_flush", "Profit and activity counters could not be saved to the database.")
        for name, l in (diag.get("listeners") or {}).items():
            if not l.get("active", True):
                add("warning", f"listener_{name}", f"The live '{name}' data feed stopped; it will retry by itself.")
        if c.get("mockPaymentsInCloud"):
            add("critical", "mock_payments", "Fake payment gateways are configured on a cloud server. Real money must not use these.")
        if c.get("paymentsMode") == "mock" and diag.get("service") != "local":
            add("warning", "mock_mode", "PAYMENTS_MODE is still 'mock' on a deployed server.")
        if c.get("webhookSecretDefault") and c.get("paymentsMode") != "mock":
            add("critical", "webhook_secret", "The payment webhook secret is still the default.")
        if not c.get("adminKeyStrong"):
            add("warning", "admin_key", "ADMIN_KEY is missing or shorter than 16 characters.")
        if not c.get("sessionSecretStrong"):
            add("warning", "session_secret", "SESSION_SECRET is missing or shorter than 32 characters.")
        if c.get("emailMode") == "mock" and diag.get("service") != "local":
            add("info", "email_mock", "Email is in mock mode: campaigns are not really sent.")
        if (diag.get("maintenance") or {}).get("on"):
            add("info", "maintenance", f"Maintenance mode is ON ({diag['maintenance'].get('scope')}).")
        if diag.get("openCrashes"):
            add("info", "crashes", f"{diag['openCrashes']} open crash group(s) to look at.")
    return out


def cert_days_left(url: str) -> float | None:
    u = urlparse(url)
    if u.scheme != "https" or not u.hostname:
        return None
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((u.hostname, u.port or 443), timeout=8) as s, ctx.wrap_socket(s, server_hostname=u.hostname) as ss:
            exp = datetime.strptime(ss.getpeercert()["notAfter"], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
            return (exp - datetime.now(timezone.utc)).total_seconds() / 86400
    except Exception:
        return None


class Monitor:
    def __init__(self, db: DB, cfg: Config, notify=None):
        self.db, self.cfg = db, cfg
        self.notify = notify or self._send_alert
        self._fails: dict[str, int] = {}
        self._n: dict[str, int] = {}
        self._alerted: dict[str, float] = {}
        self._stop = threading.Event()

    # ------------------------------------------------------------------ run

    def start(self) -> None:
        threading.Thread(target=self._loop, daemon=True, name="monitor").start()

    def _loop(self) -> None:
        while not self._stop.is_set():
            for t in self.cfg.targets:
                try:
                    self.probe(t)
                except Exception:
                    log.exception("probe failed for %s", t.name)
            try:
                self.db.x("DELETE FROM probes WHERE at<?", (time.time() - KEEP_SECONDS,))
            except Exception:
                pass
            self._stop.wait(self.cfg.probe_seconds)

    def probe(self, t: Target, deep: bool | None = None) -> dict:
        now = time.time()
        r = serverapi.plain(t, "GET", "/healthz", timeout=10)
        ok = r.status == 200 and isinstance(r.data, dict) and r.data.get("ok") is True
        self.db.x("INSERT INTO probes(target,at,ok,ms,status,detail) VALUES(?,?,?,?,?,?)", (t.name, now, int(ok), round(r.ms, 1), r.status, r.error or ""))
        self._n[t.name] = self._n.get(t.name, 0) + 1
        self._incidents(t, ok, r)
        diag = dbc = None
        if ok and (deep if deep is not None else self._n[t.name] % DEEP_EVERY == 1) and len(t.secret) >= 32:
            d = serverapi.signed(t, "GET", "/internal/dev/diag")
            diag = d.data if d.ok else None
            b = serverapi.signed(t, "GET", "/internal/dev/db-check")
            dbc = b.data if b.ok else {"ok": False, "error": f"HTTP {b.status}"}
        row = self.db.q("SELECT * FROM latest WHERE target=?", (t.name,))
        cert = row[0]["cert_days"] if row else None
        if t.https and (not row or now - row[0]["at"] > 3600 or deep):
            cert = cert_days_left(t.url)
        if diag is not None or not row:
            self.db.x("INSERT INTO latest(target,at,diag,dbcheck,cert_days) VALUES(?,?,?,?,?) ON CONFLICT(target) DO UPDATE SET at=excluded.at, diag=COALESCE(excluded.diag,diag), dbcheck=COALESCE(excluded.dbcheck,dbcheck), cert_days=excluded.cert_days",
                      (t.name, now, json.dumps(diag) if diag else None, json.dumps(dbc) if dbc else None, cert))
        self._alert_problems(t, self.problems(t))
        return {"ok": ok, "ms": round(r.ms, 1), "status": r.status}

    def _incidents(self, t: Target, ok: bool, r) -> None:
        open_ = self.db.q("SELECT * FROM incidents WHERE target=? AND ended IS NULL", (t.name,))
        if ok:
            self._fails[t.name] = 0
            if open_:
                self.db.x("UPDATE incidents SET ended=? WHERE id=?", (time.time(), open_[0]["id"]))
                mins = (time.time() - open_[0]["started"]) / 60
                self.notify(f"✅ {t.name} is back up after {mins:.0f} min.")
            return
        self._fails[t.name] = self._fails.get(t.name, 0) + 1
        if self._fails[t.name] >= FAILS_TO_OPEN and not open_:
            reason = r.error or f"HTTP {r.status}"
            self.db.x("INSERT INTO incidents(target,started,reason) VALUES(?,?,?)", (t.name, time.time(), reason))
            self.notify(f"🔴 {t.name} is DOWN ({reason}). {t.url}")

    def _alert_problems(self, t: Target, probs: list[dict]) -> None:
        now = time.time()
        for p in probs:
            if p["severity"] != "critical" or p["code"] == "down":  # "down" has its own incident alert
                continue
            k = f"{t.name}:{p['code']}"
            if now - self._alerted.get(k, 0) > REALERT_SECONDS:
                self._alerted[k] = now
                self.notify(f"🚨 {t.name}: {p['text']}")

    def _send_alert(self, text: str) -> None:
        log.warning("ALERT %s", text)
        try:
            if self.cfg.alert_webhook:
                requests.post(self.cfg.alert_webhook, json={"text": text, "content": text}, timeout=8)
            if self.cfg.telegram_token and self.cfg.telegram_chat:
                requests.post(f"https://api.telegram.org/bot{self.cfg.telegram_token}/sendMessage", json={"chat_id": self.cfg.telegram_chat, "text": text}, timeout=8)
        except requests.RequestException:
            log.exception("could not send alert")

    # ---------------------------------------------------------------- reading

    def problems(self, t: Target) -> list[dict]:
        last = self.db.q("SELECT * FROM probes WHERE target=? ORDER BY id DESC LIMIT 1", (t.name,))
        row = self.db.q("SELECT * FROM latest WHERE target=?", (t.name,))
        diag = json.loads(row[0]["diag"]) if row and row[0]["diag"] else None
        dbc = json.loads(row[0]["dbcheck"]) if row and row[0]["dbcheck"] else None
        cert = row[0]["cert_days"] if row else None
        if not last:
            return []
        if len(t.secret) < 32:
            extra = [{"severity": "info", "code": "no_secret", "text": "No dev secret for this target, so only health checks run."}]
        else:
            extra = []
        return problems_from(bool(last[0]["ok"]), last[0]["ms"], diag, dbc, cert) + extra

    def summary(self, t: Target) -> dict:
        now = time.time()

        def window(sec):
            rows = self.db.q("SELECT ok, ms FROM probes WHERE target=? AND at>?", (t.name, now - sec))
            if not rows:
                return None
            ms = sorted(r["ms"] for r in rows if r["ok"])
            return {"checks": len(rows), "uptime": round(sum(r["ok"] for r in rows) / len(rows), 4), "avgMs": round(sum(ms) / len(ms), 1) if ms else None, "p95Ms": ms[int(len(ms) * 0.95) - 1] if len(ms) >= 20 else (ms[-1] if ms else None)}

        last = self.db.q("SELECT * FROM probes WHERE target=? ORDER BY id DESC LIMIT 1", (t.name,))
        spark = [{"ok": bool(r["ok"]), "ms": r["ms"]} for r in reversed(self.db.q("SELECT ok, ms FROM probes WHERE target=? ORDER BY id DESC LIMIT 60", (t.name,)))]
        row = self.db.q("SELECT * FROM latest WHERE target=?", (t.name,))
        diag = json.loads(row[0]["diag"]) if row and row[0]["diag"] else None
        inc = self.db.q("SELECT * FROM incidents WHERE target=? AND ended IS NULL", (t.name,))
        return {
            "name": t.name, "url": t.url, "hasSecret": len(t.secret) >= 32,
            "status": "unknown" if not last else ("up" if last[0]["ok"] else "down"), "lastCheckAt": last[0]["at"] if last else None, "lastMs": last[0]["ms"] if last else None,
            "h24": window(86400), "d7": window(7 * 86400), "spark": spark, "problems": self.problems(t), "incident": dict(inc[0]) if inc else None,
            "diag": diag and {"version": diag.get("version"), "revision": diag.get("revision"), "service": diag.get("service"), "metrics": diag.get("metrics"), "maintenance": diag.get("maintenance"), "listeners": diag.get("listeners"), "openCrashes": diag.get("openCrashes")},
        }
