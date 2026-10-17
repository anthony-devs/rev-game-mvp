# REV Games developer console

Your private control room. It is a **separate program** from the game server, so it can tell you when the
server is down, run checks against it, and deploy or migrate it. It never touches the game's Firestore for
its own history (that lives in a local SQLite file), so it costs the game **zero database reads**.

```
founder  ->  /admin and /admin/insights     (on the game server: money, players, crashes, email)
you      ->  this console                   (own login + authenticator code, own host)
                 |  signed requests (HMAC) to /internal/dev/*          plain GET /healthz every 30 s
                 v
            game server
```

## What it does

| Tab | |
|---|---|
| Overview | Up/down, latency, 24 h / 7 d uptime, request error rate, p50/p95, version, open incidents, and a plain-language **Problems** list (quota used up, high error rate, fake payment gateways on a cloud server, weak secrets, certificate expiring, a live data feed stopped, ...). Alerts go to Slack/Discord/Telegram once per problem, not every 30 s. |
| Tests | 15 live checks: answers fast, games need a sign-in, forged tokens refused, admin locked, developer API refuses unsigned calls, HTTPS certificate, database read **and write**, not in maintenance. |
| Errors & crashes | Recent server errors with traces, and the crash groups reported by the app. |
| Controls | **Maintenance mode** (pause new bets/deposits, all or live-money only; open rounds can still finish) and **data migrations** (dry run first). |
| Deploy & tools | Fixed commands from `actions.json`: run the server tests, back up Firestore, deploy to Cloud Run (flush counters -> deploy -> smoke test), roll back, migrate to another region/project. |
| Audit log | Every sign-in, failed attempt and change, hash-chained so tampering shows. |

## Security model

- Password (scrypt) **and** a 6-digit authenticator code on every sign-in; each code works once.
- 5 wrong attempts lock the username and the address for 15 minutes. The error never says which part was wrong.
- Sessions: random tokens stored hashed, `HttpOnly` + `Secure` + `SameSite=Strict` cookie, 30 min idle / 8 h absolute, CSRF token on every change, same-origin check.
- Deploy, migrate, maintenance and "sign out everywhere" need a **new** authenticator code **and** a typed word.
- The browser never sends a command. `actions.json` holds fixed argument lists (no shell); the only blanks are named parameters that must match a pattern.
- Strict CSP (no inline script or style), no framing, no caching of API answers. Optional IP allowlist (`CONSOLE_ALLOWED_IPS`).
- Server link: every call is signed with `DEV_API_SECRET` (method, path, time, one-time nonce, body hash). 60 s window, replay refused, wrong signatures rate-limited, off entirely unless the secret is 32+ characters.
- Secrets live only in environment variables.

Be honest about the limits: if your laptop or the console host is compromised, so is everything it can deploy. Run the console on a machine you trust, behind HTTPS, ideally with `CONSOLE_ALLOWED_IPS` set, and keep the TOTP secret in a password manager.

## Set up

```bash
cd devconsole
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
python manage.py setup            # prints CONSOLE_USER / CONSOLE_PASSWORD_HASH / CONSOLE_TOTP_SECRET and the authenticator link
python manage.py gen-secret       # a DEV_API_SECRET; put the SAME value on the game server
cp .env.example .env.local        # fill it in
cp targets.example.json targets.json
set -a; source .env.local; set +a
python wsgi.py                    # http://127.0.0.1:9090
```

On the **game server** add `DEV_API_SECRET=<same value>` (and restart). Without it the developer API is off.

Tests: `python -m pytest -q tests` (23 tests, including one that starts a real game server and runs every check against it).

## Deploying

The console is one small container (`Dockerfile`). Put it somewhere other than the game server (a small VM, Fly.io, another Cloud Run service with a mounted volume) so it survives the server being down. Keep `CONSOLE_DB` on persistent storage. `TRUST_PROXY=1` behind one proxy.

`gcloud` must be installed and signed in on the machine that runs the console for the Deploy & tools actions to work.

## Cost note

Cloud Run bills the game server per request. The counters flush every 30 s and on shutdown, and the live data feeds reconnect on the next request, so no always-on instance is required. If you want the dashboards to be instant after long quiet periods, add `--min-instances 1 --no-cpu-throttling` to the deploy action (it costs roughly the price of one small always-on container).
