"""Checks you can run against a live server at any time. They only read, except one scratch
document the database self-test writes and deletes. Nothing here can touch a player."""
from __future__ import annotations

import time

from . import serverapi
from .config import Target
from .monitor import cert_days_left


def _t(name, fn):
    t0 = time.perf_counter()
    try:
        ok, detail = fn()
    except Exception as e:  # a check that crashes is a failed check, not a crashed console
        ok, detail = False, f"{type(e).__name__}: {e}"
    return {"name": name, "ok": bool(ok), "detail": detail, "ms": round((time.perf_counter() - t0) * 1000, 1)}


def run_smoke(t: Target) -> dict:
    P = lambda m, p, **kw: serverapi.plain(t, m, p, **kw)
    checks = []

    def health():
        r = P("GET", "/healthz")
        return r.status == 200 and r.data == {"ok": True}, f"HTTP {r.status} in {r.ms:.0f} ms"

    def speed():
        times = sorted(P("GET", "/healthz").ms for _ in range(5))
        return times[2] < 800, f"median {times[2]:.0f} ms (limit 800)"

    def games_locked():
        r = P("GET", "/v1/games")
        return r.status == 401, f"HTTP {r.status} (should be 401 without a sign-in)"

    def bad_token():
        r = P("GET", "/v1/wallet", headers={"Authorization": "Bearer not-a-real-token"})
        return r.status == 401, f"HTTP {r.status}"

    def config_public():
        r = P("GET", "/v1/config")
        d = r.data if isinstance(r.data, dict) else {}
        need = {"dice", "roulette", "blackjack", "crash"}
        return r.status == 200 and need <= set(d), f"HTTP {r.status}, has {sorted(need & set(d))}"

    def json_404():
        r = P("GET", "/v1/definitely-not-here")
        return r.status == 404 and isinstance(r.data, dict) and r.data.get("error") == "not_found", f"HTTP {r.status}"

    def admin_locked():
        r1, r2 = P("GET", "/admin/api/users"), P("GET", "/admin/api/insights/profit")
        return r1.status == 401 and r2.status == 401, f"users {r1.status}, profit {r2.status} (both should be 401)"

    def dev_unsigned():
        r = P("GET", "/internal/dev/diag")
        return r.status in (401, 404), f"HTTP {r.status} (401 or 404 expected without a signature)"

    def dev_bad_sig():
        r = P("GET", "/internal/dev/diag", headers={"X-Dev-Time": str(int(time.time())), "X-Dev-Nonce": "a" * 24, "X-Dev-Sig": "0" * 64})
        return r.status in (401, 404), f"HTTP {r.status}"

    def redirects_https():
        if not t.https:
            return True, "skipped (not https)"
        r = serverapi.plain(Target(t.name, "http://" + t.url[len("https://"):], t.secret), "GET", "/healthz", timeout=8)
        return r.status in (0, 301, 302, 307, 308, 403, 404), f"plain http answered {r.status or r.error}"

    def cert():
        if not t.https:
            return True, "skipped (not https)"
        d = cert_days_left(t.url)
        return d is not None and d > 14, "unreadable" if d is None else f"{d:.0f} days left"

    def signed_diag():
        r = serverapi.signed(t, "GET", "/internal/dev/diag")
        return r.ok, "no dev secret set" if r.error == "no_secret" else f"HTTP {r.status}"

    def db_read():
        r = serverapi.signed(t, "GET", "/internal/dev/db-check")
        d = r.data if isinstance(r.data, dict) else {}
        return r.ok and d.get("ok") is True, ("quota used up" if d.get("quota") else f"{d.get('ms')} ms") if r.ok else f"HTTP {r.status}"

    def db_write():
        r = serverapi.signed(t, "POST", "/internal/dev/selftest", {})
        d = r.data if isinstance(r.data, dict) else {}
        return r.ok and d.get("ok") is True, f"{d.get('ms')} ms" if d.get("ok") else str(d.get("message") or f"HTTP {r.status}")

    def not_in_maintenance():
        r = serverapi.signed(t, "GET", "/internal/dev/diag")
        d = r.data if isinstance(r.data, dict) else {}
        return r.ok and not (d.get("maintenance") or {}).get("on"), "maintenance is ON" if (d.get("maintenance") or {}).get("on") else "off"

    for name, fn in [
        ("Server answers its health check", health), ("Health check is fast (median of 5)", speed), ("Games need a sign-in", games_locked),
        ("A fake sign-in token is refused", bad_token), ("Public config has every game", config_public), ("Unknown URLs return JSON 404", json_404),
        ("Admin data is locked", admin_locked), ("Developer API refuses unsigned calls", dev_unsigned), ("Developer API refuses a wrong signature", dev_bad_sig),
        ("Plain http is not served", redirects_https), ("HTTPS certificate is healthy", cert),
        ("Signed developer link works", signed_diag), ("Database can be read", db_read), ("Database accepts writes", db_write), ("Not in maintenance mode", not_in_maintenance),
    ]:
        checks.append(_t(name, fn))
    return {"target": t.name, "at": time.time(), "passed": sum(c["ok"] for c in checks), "failed": sum(not c["ok"] for c in checks), "results": checks}
