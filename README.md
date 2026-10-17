# REV GAMES

**Provably fair casino games, played for demo credits or real money.**

Slots, Crash, Dice, Plinko, Roulette and Blackjack on iOS and Android. Every outcome is decided and verifiable on the server, deposits and payouts run through Paystack, Flutterwave, Stripe, Apple Pay and Google Pay, and a dedicated back-office handles moderation, payout approval, profit tracking and operations.

Flutter · BLoC · Firebase · Flask · Google Cloud Run

---

## Contents
- [Product](#product)
- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Money safety](#money-safety)
- [Back-office and operations](#back-office-and-operations)
- [Getting started](#getting-started)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Launch checklist](#launch-checklist)
- [Documentation](#documentation)

---

## Product

### Games
| Game | Rules |
|---|---|
| Slots | Server-spun reels, paytable returned with every spin |
| Crash | Live multiplier stream; cash out before it busts |
| Dice | Over/under with a chosen target, 10 to 90 |
| Plinko | 8 to 16 rows, low / medium / high risk, 96% live return, per-drop payout cap |
| Roulette | European, single zero (RTP 97.30%) |
| Blackjack | 3:2 blackjack, dealer stands on all 17s, double on two cards |

### Provably fair
Each player has a server seed (published as a hash before play) and a client seed. Results derive from an HMAC of both plus a nonce. When the player rotates seeds the old server seed is revealed and any round can be re-computed and checked in the **Fairness** page.

### Two wallets
| | Demo credits | Live money |
|---|---|---|
| Funds | Free credits | Player deposits, withdraws |
| Record | Own wallet, history, seeds, level | A fully separate player record (`L_<uid>`) |
| Odds | Configurable (`DEMO_*`) | House edge: dice 5%, crash 5%, standard roulette and blackjack, slots factor 0.96 |

Players pick the wallet they play from in the header, as on the large betting apps. The two can never mix.

### Payments
- **Deposits:** Paystack, Flutterwave (cards, bank, USSD, mobile money), Stripe (cards), Apple Pay and Google Pay (card wallets settled through Stripe).
- **Payouts:** to a bank account through the same providers.
- Apple and Google in-app purchase are not used: both stores prohibit it for real-money gambling stakes.

---

## Architecture

```
Flutter app ──(Firebase ID token)──> Flask API (Cloud Run) ──> Cloud Firestore
     ▲                                   │
     └── reads its own wallet / history ◄┘   the server is the only writer
         through Firestore snapshots
                                         └──> payment providers (server to server)

Developer console ──(HMAC-signed)──> /internal/dev/*
```

- **The app decides nothing.** It sends a bet; the server rolls, pays and writes wallet, round and progress in a single transaction.
- **Firestore rules** let a player read their own documents and write none.
- **Account standing** (ban, suspension, restriction, investigation, probation) is enforced on every request, with appeals and an audit trail.
- **Efficient on Firestore:** cached admin answers, snapshot listeners that bill only for changes, database-side counts, and counters batched into atomic increments every 30 seconds.

| Layer | Technology |
|---|---|
| Mobile app | Flutter, BLoC, Firebase Auth, Firestore snapshots, `flutter_svg` |
| API | Python 3.12, Flask, Firebase Admin SDK, gunicorn |
| Data | Cloud Firestore |
| Hosting | Google Cloud Run (API); the developer console runs on its own host |
| Tests | pytest: 159 server tests, 23 console tests (one starts a real server) |

---

## Repository layout

```
rev_game_mvp/
├── lib/              Flutter app
├── assets/           Fonts, sounds, game art, payment logos
├── server/           Game API, back-office, payments ledger
├── devconsole/       Developer console (separate program)
├── firestore.rules   Read-own-data, no client writes
└── firebase.json
```

---

## Money safety

The ledger lives in `server/app/live.py` and is covered by tests.

- **Credit only on proof.** A deposit is credited only after the server asks the provider directly and the amount and currency match. A client claim or a webhook alone never credits; webhooks are signed and only trigger a check.
- **No double deposit.** One idempotency key per attempt; a re-opened sheet with the same provider and amount within two minutes reuses the open payment; each provider reference can be credited once.
- **No double payout.** The wallet is debited when the payout is requested; every status change happens in a transaction that first checks the current status; the provider call is idempotent by payment id; a rejection refunds once, only from `pending_review` or `failed`, and only if the provider does not show it paid or pending.
- **Every payout is approved by a person.** The founder approves each payout individually by typing that payout's own six-character reference. There is no bulk approve.
- **Safe to close.** Account deletion is refused while live balance or an open payout exists.
- **Guard rails.** Min and max deposit and payout, a cap on open payouts, standing checks on `deposit` and `payout`, and a maintenance switch that pauses new bets and deposits while letting open rounds finish.

---

## Back-office and operations

| Where | Who | What |
|---|---|---|
| `/admin` | Founder | Moderation: restrictions, bans, investigations, appeals, customer-service reps |
| `/admin/payments` | Founder | Payout desk: approve or reject each payout, check deposits |
| `/admin/insights` | Founder | Profit tracker, account tracking, payouts waiting, active and inactive players, crash groups, email |
| `/support` | Customer service | Tickets, replies, attachments |
| `devconsole` | Developer | Uptime and alerting, live checks, maintenance mode, migrations, deploy and rollback, audit log |

### Developer console
A separate program with its own login (password plus authenticator code), its own history in a local SQLite file, and no dependency on the game database, so it keeps working and keeps recording when the API is down. It reaches the API only through HMAC-signed calls to `/internal/dev/*`.

- Health checks every 30 seconds; two failures open an incident and alert Slack, Discord or Telegram.
- A plain-language problems list: Firestore quota, error rate, latency, fake gateways on a cloud server, weak secrets, expiring certificate, stopped data feeds.
- Fifteen live checks, including a database write test.
- Maintenance mode and versioned data migrations (dry run first).
- Deploy, roll back, back up Firestore and migrate region or project from fixed, parameter-checked commands.
- Hash-chained audit log.

Details: [`devconsole/README.md`](devconsole/README.md).

---

## Getting started

Requirements: Flutter, Python 3.12+, a Firebase project with Firestore and Authentication.

```bash
# API
cd server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env.local        # set ADMIN_*, ADMIN_KEY, SESSION_SECRET (see the comments)
python -m pytest -q tests
python wsgi.py                    # http://localhost:8080

# App
cd ..
flutter pub get
flutter run --dart-define=APP_VERSION=1.0.0

# Firestore rules
firebase deploy --only firestore:rules

# Developer console (separate terminal)
cd devconsole && python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt && python manage.py setup
```

The app finds the API through `lib/core/api/api_config.dart`.

---

## Configuration

All server settings are environment variables; `server/.env.example` documents every one.

| Area | Variables |
|---|---|
| Admin | `ADMIN_USERNAME`, `ADMIN_PASSWORD_HASH`, `ADMIN_KEY`, `SESSION_SECRET` |
| Live money | `LIVE_ENABLED`, `LIVE_CURRENCY`, `LIVE_MIN/MAX_DEPOSIT`, `LIVE_MIN/MAX_PAYOUT`, `LIVE_MAX_OPEN_PAYOUTS`, `PAYMENTS_MODE`, `PAYMENT_WEBHOOK_SECRET` |
| Odds | `DICE_HOUSE_EDGE`, `PLINKO_HOUSE_EDGE`, `PLINKO_MAX_PAYOUT`, `CRASH_HOUSE_EDGE`, `LIVE_SLOTS_FACTOR`, `DEMO_DICE_EDGE`, `DEMO_PLINKO_EDGE`, `DEMO_CRASH_EDGE`, `DEMO_SLOTS_FACTOR`, `DEMO_WIN_BOOST` |
| Email | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `MAIL_FROM` |
| Developer link | `DEV_API_SECRET`, `DEV_ALLOWED_IPS`, `APP_VERSION` |

Generate secrets with `python manage.py gen-secret` and the admin password hash with `python manage.py hash-password`.

---

## Deployment

```bash
cd server
gcloud run deploy rev-games-server --source . --region <region> --project <project>
```

1. Set the environment variables on the service (use Secret Manager for secrets).
2. `python manage.py migrate` (dry run), then `python manage.py migrate --apply`.
3. `firebase deploy --only firestore:rules`.
4. Run the console's **Tests** tab against the new revision.

Use the Firebase **Blaze** plan: the free plan's daily read and write quotas are hard limits and will take the service down under real traffic.

Optionally set `--min-instances 1 --no-cpu-throttling` so snapshot feeds and counters stay warm between requests.

---

## Launch checklist

What is in place and what must be finished before real money moves.

### In place
- [x] Server-side game logic, provably fair verification, account standing and appeals
- [x] Live wallet separation, deposit and payout ledger with idempotency and per-payout approval
- [x] Founder insights, moderation, payout desk, customer support, email tooling
- [x] Developer console, signed server link, maintenance mode, migrations
- [x] Client crash reporting and server error capture
- [x] Test suites (server 159, console 23)

### Must be completed before launch
- [ ] **Payment gateways.** `server/app/providers.py` contains mock providers only, and the server refuses any other `PAYMENTS_MODE` until a real adapter exists. Write one adapter per gateway implementing `create_charge`, `fetch_charge`, `verify_webhook`, `send_payout`, `fetch_payout` (Paystack, Flutterwave, Stripe), with live API keys and real webhook secrets. Test each end to end with small real amounts in the provider's test mode first, including failed, abandoned and duplicate-webhook cases.
- [ ] **Licence and legal.** A gambling licence for every market served, terms and privacy policy, and store approval (Apple and Google both restrict real-money gambling apps by region and licence).
- [ ] **Player protection.** Age verification and KYC before the first withdrawal, self-exclusion, deposit and loss limits, reality checks, and a cooling-off period. The server has the hooks (standing types, per-action limits); the player-facing flows are still to build.
- [ ] **Anti-fraud and AML.** Transaction monitoring, withdrawal velocity and name-match rules, multi-account detection, and a wagering requirement before withdrawal.
- [ ] **Free-play odds.** Many regulators require demo odds to match live odds. Set the `DEMO_*` values equal to the live ones where that applies.
- [ ] **Secrets and hardening.** Strong unique `ADMIN_KEY`, `SESSION_SECRET`, `DEV_API_SECRET`; hashed admin password; `PAYMENTS_MODE` set; console behind HTTPS with `CONSOLE_ALLOWED_IPS`; secrets in Secret Manager.
- [ ] **Capacity and backups.** Blaze plan, load test at expected peak, scheduled Firestore exports, alert channel configured in the console.
- [ ] **Logos.** Replace the Simple Icons marks in `assets/logos` with each brand's official assets and add Paystack and Flutterwave SVGs.
- [ ] **Incident plan.** Who is on call, how to pause play (console maintenance mode), how to reconcile a payment dispute.

---

## Documentation
- [`server/README.md`](server/README.md): API, tuning, moderation, live play, insights, developer link
- [`devconsole/README.md`](devconsole/README.md): security model, setup, deploying the console
- [`assets/logos/README.md`](assets/logos/README.md): payment logos

## Author
Anthony Ude · [github.com/anthony-devs](https://github.com/anthony-devs) · Enugu, Nigeria
