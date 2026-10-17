# REV GAMES server

Flask API that decides every game result and owns the wallet. The Flutter app
only animates what this server returns.

| Method | Path | What |
|---|---|---|
| GET | `/healthz` | Liveness |
| GET | `/v1/wallet` | Balance (creates the wallet if missing) |
| POST | `/v1/wallet/claim-daily` | +1000 credits, once per 24h |
| POST | `/v1/wallet/top-up` | Refill to 10000 when below it |
| GET | `/v1/slots/config` | Bets, pay table, RTP, your balance |
| POST | `/v1/slots/spin` `{bet}` | One spin |
| POST | `/v1/crash/rounds` `{bet, autoCashout?}` | Take the bet, start a round |
| GET | `/v1/crash/rounds/{id}/events` | Server-sent events: `cashedOut`, `crashed` |
| POST | `/v1/crash/rounds/{id}/cashout` | Cash out at the server's clock |

Every call except `/healthz` needs `Authorization: Bearer <Firebase ID token>`.
Errors look like `{"error": "insufficient_credits", "message": "..."}`.

## Firestore

```
users/{uid}/wallet/current       balance, lastDailyClaimAt, updatedAt
users/{uid}/progress/current     level, xp, streak, stats
users/{uid}/rounds/{id}          history of settled rounds (with fairness proof)
users/{uid}/fairness/current     public seed hash, client seed, nonce
users/{uid}/seed_history/{hash}  server seeds revealed after a rotate
fair_secrets/{uid}               live server seed (server only)
crash_rounds/{id}                secret crash point (server only)
blackjack_rounds/{id}            shuffled deck (server only)
blackjack_active/{uid}           hand in progress (server only)
```

Money changes only inside Firestore transactions (`app/store.py`), so two fast
taps cannot spend the same credits twice.

## Run the tests

```bash
cd server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest
```

## Run locally against your real Firestore

```bash
gcloud auth application-default login          # once
export FIREBASE_PROJECT_ID=rev-games
python -m flask --app wsgi run --port 8080
```

Then run the app with `--dart-define=API_URL=http://10.0.2.2:8080` (Android
emulator) or `http://localhost:8080` (iOS simulator).

## Deploy to Cloud Run

```bash
gcloud run deploy rev-game-server \
  --source server \
  --region europe-west1 \
  --allow-unauthenticated \
  --timeout 3600 \
  --set-env-vars FIREBASE_PROJECT_ID=rev-games
```

`--allow-unauthenticated` is correct: the service checks the Firebase token
itself. The Cloud Run service account needs the **Cloud Datastore User** role
(the default compute account already has it). Put the printed URL into the
app: `--dart-define=API_URL=https://rev-game-server-xxxx.a.run.app`.

## Tuning

Environment variables: `STARTING_BALANCE`, `DAILY_BONUS`, `CRASH_HOUSE_EDGE`,
`CRASH_GROWTH_RATE`, `CRASH_MAX_BET` (see `app/config.py`). The slots pay table
lives in `app/slots.py` and the tests check that its RTP stays 0.96.

## API

All routes need `Authorization: Bearer <Firebase ID token>` except `/healthz` and `/v1/config`.

| Route | What |
| --- | --- |
| `GET /v1/wallet`, `POST /v1/wallet/claim-daily`, `/top-up`, `/reset` | credits (daily streak: 1000, 1000, 1500, 2000, 2500, 3000, 10000) |
| `POST /v1/slots/spin`, `/v1/crash/...` | slots and crash |
| `POST /v1/dice/roll {bet,target,mode}` | dice, 3% edge |
| `POST /v1/roulette/spin {bets:[{type,value?,amount}]}` | European roulette |
| `GET /v1/blackjack/active`, `POST /deal {bet}`, `POST /<id>/hit\|stand\|double` | blackjack, 3:2 |
| `GET /v1/fairness`, `POST /v1/fairness/rotate`, `GET /v1/fairness/verify/<round>` | provably fair seeds |
| `DELETE /v1/account` | deletes all data and the sign-in account |

## Provably fair

Results come from `HMAC_SHA256(server_seed, "client_seed:nonce:cursor")`. The
hash of the server seed is public before you play. Rotating the seed reveals
the old one; `verify` replays the stored round with it. A seed cannot be
rotated while a crash round or blackjack hand is still open.

## Not done yet

Rate limiting, App Check verification, and shared multiplayer crash rounds.
Play limits are enforced by the app only. No split or insurance in blackjack.


## Account standing, appeals and the moderation dashboard

Four action types, all enforced on the server (`app/standing.py`):

| Type | Play | Daily / top-up / reset | Ends |
|---|---|---|---|
| `ban` | blocked | blocked | when staff lift it or an appeal is approved |
| `suspension` | blocked | blocked | on its end date (needs a duration) |
| `payout_restriction` | blocked (can be left open) | blocked | on its end date or when lifted |
| `investigation` | blocked | blocked | when staff close it |

* After a suspension, restriction or ban ends the player is on **probation** (`PROBATION_HOURS`, default 72): bets are capped at `PROBATION_MAX_BET` (1000) and free credits stay off. Clearing an investigation has no probation.
* Routes that start a round or give credits return `403` with `account_banned | account_suspended | account_restricted | account_under_review | credits_restricted | probation_bet_cap`, plus a `standing` object. Open hands/rounds can still be settled. Account deletion is refused while an action or probation is open.
* `GET /v1/account/standing` and `POST /v1/account/appeal {actionId, message}` are for the player.
* Appeals: one pending at a time; after a rejection the player waits `APPEAL_COOLDOWN_HOURS` (24).
* Firestore: `users/{uid}/account/standing` (the app listens to this), `users/{uid}/standing_actions/*`, `users/{uid}/appeals/*`, `moderation_log/*` (audit). Only the server writes them.

### Dashboard

```bash
ADMIN_KEY=choose-a-long-random-string python wsgi.py     # or gunicorn
open http://localhost:8080/admin                          # paste the key
```
Search a player, apply or lift actions, answer appeals, and see the risk checks (restricted in the past N days, probation, repeat offender, open appeals). The app updates within a second. Without `ADMIN_KEY` the dashboard is off. It is one shared key; put it behind IAP/VPN before using it for real.


## Running

```bash
cd server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.local.example .env.local      # then fill in the key path and ADMIN_KEY
python wsgi.py                        # http://localhost:8080  (dashboard at /admin)
```

Settings come from `.env.<APP_ENV>` then `.env` (real environment variables win). Only the `*.example` files are committed.
Production: `gunicorn -b 0.0.0.0:$PORT -w 1 --threads 8 wsgi:app` (see the Dockerfile).


## Staff sites

| URL | Who | What |
|---|---|---|
| `/staff` | everyone | the one sign-in page |
| `/admin` | the admin | after signing in, enter `ADMIN_KEY`. Players, bans, bulk actions, appeals, and the Team tab where reps are created |
| `/support` | support reps | ticket queue, replies with attachments, canned replies, internal notes, read-only view of a player's standing |

* The admin account is `ADMIN_USERNAME` + `ADMIN_PASSWORD` (or `ADMIN_PASSWORD_HASH`). The username can't be `admin` or `rev-admin`.
* Only the admin creates or edits reps. New reps must change their password at first sign-in.
* Reasons for bans, suspensions, lifts and appeal decisions come from fixed lists. Free text is accepted only when "Other" is picked.
* Appeals and tickets accept photos, videos and PDFs (checked by content, 25 MB each, 5 per message). Set `FIREBASE_STORAGE_BUCKET` in production.
* `python manage.py hash-password | gen-secret | gen-password` help with the secrets above.


## Live play (real money)

The app has a Demo / Live switch. Live uses a separate wallet (`users/L_<uid>`), so demo
credits and real money never mix. Right now all gateways are **mocks** (`PAYMENTS_MODE=mock`).

**Money rules (all in `app/live.py`, tested in `tests/test_live.py`)**

- A deposit credits the wallet only after the provider confirms it server to server (or a
  signed webhook triggers that check). The app's word is never trusted.
- Every deposit/payout request carries an idempotency key. The same key returns the same
  payment, so a double tap or retry can't charge or pay twice. A reopened sheet with the
  same amount and provider within 2 minutes reuses the open payment too.
- A payment is one document that only moves forward. Each move happens in a transaction that
  first checks the current state, so two webhooks, two admin clicks or an app retry can't
  credit or pay twice.
- A payout takes the money out of the wallet immediately (so it can't be played or requested
  twice) and waits for an admin. The admin opens **/admin/payments**, checks the player, and
  must type that payout's own reference to approve it. Rejecting returns the money, once.
  The provider call is idempotent by payment id.
- Accounts with an active ban, suspension, payout restriction or investigation can't deposit
  or withdraw. An account with live money or an open payout can't be deleted.

**Going real**: write one class per gateway in `app/providers.py` with the five methods
(`create_charge`, `fetch_charge`, `verify_webhook`, `send_payout`, `fetch_payout`), register
it in `build_providers`, set the keys, and point each gateway's webhook at
`/v1/live/webhooks/<provider>`. Apple/Google *in-app purchase* may not be used for real-money
gambling stakes, so Apple Pay / Google Pay are card-wallet payments settled through Stripe.

**Before launch** you still need: a gambling licence for your market, KYC/age checks before
the first payout, wagering requirements (to stop deposit-and-withdraw laundering), and daily
payout limits. None of that is built yet.
