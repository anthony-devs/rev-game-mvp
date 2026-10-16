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
