"""Live play: real-money deposits and payouts.

The rules that keep money safe, in one place:

  * A payment is ONE document that only moves forward through fixed states. Every move is
    made inside a database transaction that first checks the current state, so doing the
    same thing twice (double tap, retry, webhook + app check, two admins) changes nothing
    the second time.
  * Deposits   created -> pending -> succeeded | failed | flagged
      - the app sends an idempotency key; the same key always returns the same payment
      - a wallet is credited ONLY after the provider confirms the payment server to server
        (or a signed webhook triggers that same check), never because the app says so
      - amount and currency must match what we asked for, and one provider reference can
        be credited once
  * Payouts    pending_review -> processing -> paid | failed ;  pending_review|failed -> rejected
      - the money leaves the player's wallet the moment they ask (so it can't be played or
        requested twice) and is given back only by an admin rejection
      - nothing is sent until an admin approves THAT payout and types its reference
      - the provider call is idempotent by payment id, so a retry can never pay twice

Live play uses its own wallet (``users/L_<uid>/wallet/current``) so real money and demo
credits never mix. See ``store.live_uid``.
"""
from __future__ import annotations

import math
import os
import re
import secrets
import uuid
from datetime import datetime

from .config import Config
from .errors import ApiError, bad_request
from .providers import Provider, ProviderError
from .standing import StandingService
from .store import (
    Doc,
    Store,
    Txn,
    live_uid,
    payment_key_path,
    payment_path,
    payment_ref_path,
    user_payment_path,
    wallet_path,
)
from .util import Clock, as_utc, money, utcnow

KEY_RE = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
DEPOSIT_DONE = {"succeeded", "failed", "flagged"}
DUPLICATE_WINDOW_SECONDS = 120


def _iso(value) -> str | None:
    v = as_utc(value)
    return v.isoformat() if v else None


class LiveService:
    def __init__(self, store: Store, cfg: Config, providers: dict[str, Provider], standing: StandingService, clock: Clock = utcnow):
        self.store, self.cfg, self.providers, self.standing, self.clock = store, cfg, providers, standing, clock
        self._payments_watch = store.watch_list("payments", 300, order_by="createdAt")

    # ------------------------------------------------------------------ gates

    def available(self) -> tuple[bool, str]:
        if not self.cfg.live_enabled:
            return False, "Live play is switched off."
        if self.cfg.payments_mode == "mock" and os.environ.get("K_SERVICE") and not self.cfg.allow_mock_in_cloud:
            # Fail closed: fake gateways must never take "real" money on a deployed server.
            return False, "Live play isn't available yet."
        return True, ""

    def require_live(self) -> None:
        ok, why = self.available()
        if not ok:
            raise ApiError(403, "live_unavailable", why)

    def require_live_play(self, uid: str) -> None:
        """Called before any game request in live mode."""
        self.require_live()

    # ------------------------------------------------------------------ views

    def status(self, uid: str) -> dict:
        ok, why = self.available()
        payments = self._mine(uid)
        wallet = self.store.read(wallet_path(live_uid(uid))) or {}
        return {
            "enabled": ok,
            "message": why,
            "currency": self.cfg.live_currency,
            "mock": self.cfg.payments_mode == "mock",
            "balance": money(wallet.get("balance", 0)),
            "limits": {
                "minDeposit": self.cfg.live_min_deposit,
                "maxDeposit": self.cfg.live_max_deposit,
                "minPayout": self.cfg.live_min_payout,
                "maxPayout": self.cfg.live_max_payout,
            },
            "providers": [p.public() for p in self.providers.values()],
            "openPayouts": sum(1 for p in payments if p["kind"] == "payout" and p["status"] in ("pending_review", "processing")),
            "pendingDeposits": [self.public(p) for p in payments if p["kind"] == "deposit" and p["status"] in ("created", "pending")][:5],
        }

    def payments(self, uid: str, limit: int = 50) -> list[dict]:
        return [self.public(p) for p in self._mine(uid)[:limit]]

    def one(self, uid: str, pid: str) -> dict:
        return self.public(self._own(uid, pid))

    def _mine(self, uid: str) -> list[Doc]:
        rows = [d for _i, d in self.store.list(f"users/{uid}/payments", 200)]
        rows.sort(key=lambda d: as_utc(d["createdAt"]), reverse=True)
        return rows

    def _own(self, uid: str, pid: str) -> Doc:
        doc = self.store.read(user_payment_path(uid, pid)) if re.fullmatch(r"[0-9a-f]{32}", pid or "") else None
        if doc is None:
            raise ApiError(404, "payment_not_found", "No such payment.")
        return doc

    @staticmethod
    def public(d: Doc) -> dict:
        out = {
            "id": d["id"],
            "kind": d["kind"],
            "provider": d["provider"],
            "amount": d["amount"],
            "currency": d["currency"],
            "status": d["status"],
            "createdAt": _iso(d.get("createdAt")),
            "updatedAt": _iso(d.get("updatedAt")),
        }
        if d["kind"] == "deposit":
            out["checkout"] = d.get("checkout")
        else:
            out["reference"] = d.get("code")
            out["destination"] = {k: v for k, v in (d.get("destination") or {}).items() if k != "accountNumber"}
            out["destination"]["accountLast4"] = str((d.get("destination") or {}).get("accountNumber", ""))[-4:]
            out["note"] = d.get("reviewNote") or d.get("failReason") or ""
        return out

    # ------------------------------------------------------------------ helpers

    def _provider(self, pid, need: str) -> Provider:
        p = self.providers.get(pid) if isinstance(pid, str) else None
        if p is None or not getattr(p, need):
            raise bad_request("invalid_provider", "That payment method isn't available.")
        return p

    def _amount(self, value, lo: float, hi: float, what: str) -> float:
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise bad_request("invalid_amount", "Enter an amount.")
        amt = money(value)
        if abs(amt - value) > 1e-9:
            raise bad_request("invalid_amount", "Use at most 2 decimals.")
        if amt < lo or amt > hi:
            raise bad_request("invalid_amount", f"A {what} must be between {lo:g} and {hi:g} {self.cfg.live_currency}.")
        return amt

    @staticmethod
    def _key(value) -> str:
        if not isinstance(value, str) or not KEY_RE.match(value):
            raise bad_request("invalid_key", "Missing request key. Update the app and try again.")
        return value

    @staticmethod
    def _log(doc: Doc, status: str, by: str, note: str, now: datetime) -> None:
        doc["status"] = status
        doc["updatedAt"] = now
        doc.setdefault("history", []).append({"at": now, "status": status, "by": by, "note": note})

    @staticmethod
    def _write(txn: Txn, doc: Doc) -> None:
        txn.set(payment_path(doc["id"]), doc)
        txn.set(user_payment_path(doc["uid"], doc["id"]), doc)

    def _credit_wallet(self, txn: Txn, uid: str, delta: float, now: datetime) -> float:
        lid = live_uid(uid)
        w = txn.get_wallet(lid) or {"balance": 0.0, "lastDailyClaimAt": None}
        bal = money(w["balance"] + delta)
        if bal < 0:
            raise ApiError(402, "insufficient_credits", "Not enough balance.")
        txn.set_wallet(lid, {**w, "balance": bal, "updatedAt": now})
        return bal

    # ------------------------------------------------------------------ deposits

    def create_deposit(self, uid: str, provider_id, amount, key) -> dict:
        self.require_live()
        self.standing.enforce(uid, "deposit")
        prov = self._provider(provider_id, "deposit")
        amt = self._amount(amount, self.cfg.live_min_deposit, self.cfg.live_max_deposit, "deposit")
        key = self._key(key)
        now0 = self.clock()
        # A second tap with a different key (reopened sheet) still lands on the same open payment.
        recent = next(
            (
                p
                for p in self._mine(uid)
                if p["kind"] == "deposit" and p["status"] in ("created", "pending") and p["provider"] == prov.id
                and p["amount"] == amt and (now0 - as_utc(p["createdAt"])).total_seconds() < DUPLICATE_WINDOW_SECONDS
            ),
            None,
        )

        def claim(txn: Txn):
            kp = payment_key_path("deposit", uid, key)
            hit = txn.get(kp)
            if hit is not None:
                doc = txn.get(user_payment_path(uid, hit["paymentId"]))
                if doc is None or doc["provider"] != prov.id or doc["amount"] != amt:
                    raise ApiError(409, "key_reused", "That request key was already used for a different payment.")
                return doc, False
            if recent is not None:
                txn.set(kp, {"paymentId": recent["id"], "uid": uid})
                return recent, False
            now = self.clock()
            doc = {
                "id": uuid.uuid4().hex, "uid": uid, "kind": "deposit", "provider": prov.id,
                "amount": amt, "currency": self.cfg.live_currency, "status": "created", "idemKey": key,
                "providerRef": None, "checkout": None, "createdAt": now, "updatedAt": now, "history": [],
            }
            self._log(doc, "created", uid, "Deposit started.", now)
            txn.set(kp, {"paymentId": doc["id"], "uid": uid})
            self._write(txn, doc)
            return doc, True

        doc, fresh = self.store.run(claim)
        if not fresh:
            return self.public(doc)
        try:
            charge = prov.create_charge(doc)
        except Exception as e:  # provider down
            self._fail_deposit(uid, doc["id"], "provider_error", str(e))
            raise ApiError(502, "provider_unavailable", "The payment provider isn't responding. Nothing was charged.") from e

        def attach(txn: Txn):
            d = txn.get(user_payment_path(uid, doc["id"]))
            if d["status"] != "created":
                return d
            now = self.clock()
            d["providerRef"], d["checkout"] = charge["ref"], charge["checkout"]
            self._log(d, "pending", "system", "Waiting for the provider.", now)
            txn.set(payment_ref_path(prov.id, charge["ref"]), {"paymentId": d["id"], "uid": uid, "credited": False})
            self._write(txn, d)
            return d

        return self.public(self.store.run(attach))

    def _fail_deposit(self, uid: str, pid: str, by: str, note: str) -> Doc:
        def fn(txn: Txn):
            d = txn.get(user_payment_path(uid, pid))
            if d is None or d["status"] not in ("created", "pending"):
                return d
            self._log(d, "failed", by, note[:200], self.clock())
            self._write(txn, d)
            return d

        return self.store.run(fn)

    def verify_deposit(self, uid: str, pid: str, by: str = "player") -> dict:
        """Ask the provider what happened. Safe to call any number of times."""
        self.require_live()
        d = self._own(uid, pid)
        if d["kind"] != "deposit":
            raise bad_request("not_a_deposit", "That isn't a deposit.")
        if d["status"] == "created":
            return self.public(d)  # the provider hasn't been asked yet
        if d["status"] in DEPOSIT_DONE:
            return self.public(d)
        prov = self.providers[d["provider"]]
        try:
            res = prov.fetch_charge(d["providerRef"])
        except Exception as e:
            raise ApiError(502, "provider_unavailable", "Couldn't check the payment yet. Try again in a moment.") from e
        if res["status"] == "success":
            return self.public(self._credit(uid, pid, res, by))
        if res["status"] == "failed":
            return self.public(self._fail_deposit(uid, pid, by, "The provider reported the payment as failed."))
        return self.public(d)

    def _credit(self, uid: str, pid: str, res: dict, by: str) -> Doc:
        def fn(txn: Txn):
            d = txn.get(user_payment_path(uid, pid))
            if d is None or d["status"] != "pending":
                return d  # already credited / failed / flagged: nothing more to do
            now = self.clock()
            ref = txn.get(payment_ref_path(d["provider"], d["providerRef"]))
            if ref is None or ref.get("paymentId") != d["id"] or ref.get("credited"):
                self._log(d, "flagged", by, "Provider reference doesn't match, or was already credited.", now)
                self._write(txn, d)
                return d
            if money(res.get("amount", 0)) != d["amount"] or str(res.get("currency", "")).upper() != d["currency"]:
                self._log(d, "flagged", by, f"Provider says {res.get('amount')} {res.get('currency')}, expected {d['amount']} {d['currency']}.", now)
                self._write(txn, d)
                return d
            bal = self._credit_wallet(txn, uid, d["amount"], now)
            txn.set(payment_ref_path(d["provider"], d["providerRef"]), {**ref, "credited": True})
            self._log(d, "succeeded", by, f"Credited. Balance {bal:g}.", now)
            self._write(txn, d)
            return d

        return self.store.run(fn)

    def handle_webhook(self, provider_id: str, headers, raw: bytes) -> bool:
        """Provider says a payment changed. We only use it as a prompt to check, never as the proof."""
        prov = self.providers.get(provider_id)
        if prov is None:
            return False
        ev = prov.verify_webhook(headers, raw)
        if ev is None:
            return False
        ref = self.store.read(payment_ref_path(provider_id, ev["ref"]))
        if ref is None:
            return True  # unknown reference: acknowledge so the provider stops retrying
        try:
            self.verify_deposit(ref["uid"], ref["paymentId"], by="webhook")
        except ApiError:
            pass
        return True

    # ------------------------------------------------------------------ payouts

    def _destination(self, dest) -> dict:
        if not isinstance(dest, dict):
            raise bad_request("invalid_destination", "Enter where to send the money.")
        bank = str(dest.get("bankName", "")).strip()
        name = str(dest.get("accountName", "")).strip()
        num = str(dest.get("accountNumber", "")).strip()
        if not (2 <= len(bank) <= 60) or not (2 <= len(name) <= 80) or not re.fullmatch(r"\d{6,20}", num):
            raise bad_request("invalid_destination", "Check the bank name, account name and account number.")
        return {"bankName": bank, "accountName": name, "accountNumber": num}

    def request_payout(self, uid: str, provider_id, amount, destination, key) -> dict:
        self.require_live()
        self.standing.enforce(uid, "payout")
        prov = self._provider(provider_id, "payout")
        amt = self._amount(amount, self.cfg.live_min_payout, self.cfg.live_max_payout, "payout")
        dest = self._destination(destination)
        key = self._key(key)
        open_now = sum(1 for p in self._mine(uid) if p["kind"] == "payout" and p["status"] in ("pending_review", "processing"))

        def fn(txn: Txn):
            kp = payment_key_path("payout", uid, key)
            hit = txn.get(kp)
            if hit is not None:
                doc = txn.get(user_payment_path(uid, hit["paymentId"]))
                if doc is None or doc["amount"] != amt or doc["provider"] != prov.id:
                    raise ApiError(409, "key_reused", "That request key was already used for a different payout.")
                return doc
            if open_now >= self.cfg.live_max_open_payouts:
                raise ApiError(429, "too_many_payouts", "You already have payouts waiting. Wait for them to finish first.")
            now = self.clock()
            self._credit_wallet(txn, uid, -amt, now)  # the money is held from this moment
            doc = {
                "id": uuid.uuid4().hex, "uid": uid, "kind": "payout", "provider": prov.id, "amount": amt,
                "currency": self.cfg.live_currency, "status": "pending_review", "idemKey": key, "destination": dest,
                "code": secrets.token_hex(3).upper(), "providerRef": None, "createdAt": now, "updatedAt": now,
                "history": [], "reviewedBy": None, "reviewNote": "",
            }
            self._log(doc, "pending_review", uid, "Payout requested. Funds held.", now)
            txn.set(kp, {"paymentId": doc["id"], "uid": uid})
            self._write(txn, doc)
            return doc

        return self.public(self.store.run(fn))

    def assert_can_delete(self, uid: str) -> None:
        bal = (self.store.read(wallet_path(live_uid(uid))) or {}).get("balance", 0)
        if bal > 0 or any(p["kind"] == "payout" and p["status"] in ("pending_review", "processing") for p in self._mine(uid)):
            raise ApiError(409, "live_balance", "Withdraw your live balance (and wait for open payouts) before deleting your account.")

    # ------------------------------------------------------------------ staff

    def _find(self, pid: str) -> Doc:
        d = self.store.read(payment_path(pid)) if re.fullmatch(r"[0-9a-f]{32}", pid or "") else None
        if d is None:
            raise ApiError(404, "payment_not_found", "No such payment.")
        return d

    def staff_list(self, kind: str = "", status: str = "", limit: int = 200) -> list[dict]:
        rows = [d for _i, d in self._payments_watch.rows()]
        rows.sort(key=lambda d: as_utc(d["createdAt"]), reverse=True)
        out = []
        names: dict = {}
        for d in rows:
            if kind and d["kind"] != kind or status and d["status"] != status:
                continue
            if d["uid"] not in names:  # one read per player, not per payment
                names[d["uid"]] = self.store.read(f"users/{d['uid']}") or {}
            u = names[d["uid"]]
            out.append({**self.public(d), "uid": d["uid"], "player": u.get("displayName") or u.get("email") or d["uid"], "code": d.get("code")})
            if len(out) >= limit:
                break
        return out

    def staff_detail(self, pid: str) -> dict:
        d = self._find(pid)
        uid = d["uid"]
        mine = self._mine(uid) or [d]
        dep = sum(p["amount"] for p in mine if p["kind"] == "deposit" and p["status"] == "succeeded")
        paid = sum(p["amount"] for p in mine if p["kind"] == "payout" and p["status"] == "paid")
        lid = live_uid(uid)
        rounds = sorted((r for _i, r in self.store.list(f"users/{lid}/rounds", 100)), key=lambda r: as_utc(r["createdAt"]), reverse=True)
        pub = self.standing.public(self.standing.summary(uid))
        u = self.store.read(f"users/{uid}") or {}
        return {
            "payment": {**self.public(d), "uid": uid, "code": d.get("code"), "destination": d.get("destination"), "providerRef": d.get("providerRef"),
                        "reviewedBy": d.get("reviewedBy"), "history": [{**h, "at": _iso(h["at"])} for h in d.get("history", [])]},
            "player": {
                "uid": uid, "name": u.get("displayName"), "email": u.get("email"), "standing": pub["state"],
                "liveBalance": money((self.store.read(wallet_path(lid)) or {}).get("balance", 0)),
                "totalDeposited": money(dep), "totalPaidOut": money(paid),
                "liveRounds": len(rounds),
                "recentRounds": [{"game": r.get("game"), "bet": r.get("bet"), "payout": r.get("returned", r.get("payout")), "at": _iso(r.get("createdAt"))} for r in rounds[:8]],
            },
        }

    def approve_payout(self, pid: str, actor: str, confirm, note: str = "") -> dict:
        """Admin says: I checked THIS payout, send it. ``confirm`` must be its reference."""
        d = self._find(pid)
        if d["kind"] != "payout":
            raise bad_request("not_a_payout", "That isn't a payout.")
        if str(confirm or "").strip().upper() != d.get("code"):
            raise bad_request("bad_confirmation", "Type this payout's reference to approve it.")

        def claim(txn: Txn):
            cur = txn.get(payment_path(pid))
            if cur["status"] != "pending_review":  # someone already approved / rejected it
                raise ApiError(409, "not_reviewable", f"This payout is {cur['status'].replace('_', ' ')}, so it can't be approved.")
            cur["reviewedBy"], cur["reviewNote"] = actor, note[:300]
            self._log(cur, "processing", actor, "Approved. Sending to the provider." + (f" Note: {note[:200]}" if note else ""), self.clock())
            self._write(txn, cur)
            return cur

        return self._send(self.store.run(claim), actor)

    def retry_payout(self, pid: str, actor: str) -> dict:
        d = self._find(pid)
        if d["kind"] != "payout" or d["status"] not in ("processing", "failed"):
            raise ApiError(409, "not_retryable", "Only a payout that is processing or failed can be retried.")
        if d["status"] == "failed":
            def reopen(txn: Txn):
                cur = txn.get(payment_path(pid))
                if cur["status"] == "failed":
                    self._log(cur, "processing", actor, "Retrying.", self.clock())
                    self._write(txn, cur)
                return cur

            d = self.store.run(reopen)
        return self._send(d, actor)

    def sync_payout(self, pid: str, actor: str) -> dict:
        d = self._find(pid)
        if d["kind"] != "payout" or d["status"] != "processing":
            raise ApiError(409, "not_syncable", "Only a processing payout can be synced.")
        prov = self.providers[d["provider"]]
        if hasattr(prov, "settle_pending_payout"):
            prov.settle_pending_payout(pid)  # the mock bank settles now
        res = prov.fetch_payout(d)
        return self._apply_payout_result(d, res, actor)

    def _send(self, d: Doc, actor: str) -> dict:
        prov = self.providers[d["provider"]]
        try:
            res = prov.send_payout(d)  # idempotent by payment id
        except Exception as e:
            self._note(d["id"], actor, f"Provider error: {e}"[:200])
            raise ApiError(502, "provider_unavailable", "The provider didn't answer. The payout is still 'processing'; retry in a moment.") from e
        return self._apply_payout_result(d, res, actor)

    def _note(self, pid: str, actor: str, text: str) -> None:
        def fn(txn: Txn):
            cur = txn.get(payment_path(pid))
            cur.setdefault("history", []).append({"at": self.clock(), "status": cur["status"], "by": actor, "note": text})
            self._write(txn, cur)

        self.store.run(fn)

    def _apply_payout_result(self, d: Doc, res: dict, actor: str) -> dict:
        status = res.get("status")

        def fn(txn: Txn):
            cur = txn.get(payment_path(d["id"]))
            now = self.clock()
            if cur["status"] != "processing":
                return cur  # already finished by another call
            if res.get("ref"):
                cur["providerRef"] = res["ref"]
            if status == "success":
                self._log(cur, "paid", actor, f"Provider paid it ({cur['providerRef']}).", now)
            elif status == "failed":
                cur["failReason"] = res.get("reason") or "The provider could not send it."
                self._log(cur, "failed", actor, cur["failReason"], now)
            else:
                cur.setdefault("history", []).append({"at": now, "status": "processing", "by": actor, "note": "Provider is still processing it."})
            self._write(txn, cur)
            return cur

        return self.public(self.store.run(fn))

    def reject_payout(self, pid: str, actor: str, reason: str) -> dict:
        """Give the money back. Allowed once, and only if it was never paid."""
        reason = (reason or "").strip()
        if len(reason) < 3:
            raise bad_request("reason_required", "Say why you are rejecting it.")
        d = self._find(pid)
        if d["kind"] != "payout":
            raise bad_request("not_a_payout", "That isn't a payout.")
        if d["status"] == "failed":  # make sure the provider really didn't pay
            res = self.providers[d["provider"]].fetch_payout(d)
            if res.get("status") in ("success", "pending"):
                raise ApiError(409, "provider_has_it", "The provider shows this payout as paid or in progress. Sync it instead.")

        def fn(txn: Txn):
            cur = txn.get(payment_path(pid))
            if cur["status"] not in ("pending_review", "failed"):
                raise ApiError(409, "not_rejectable", f"This payout is {cur['status'].replace('_', ' ')}, so it can't be rejected.")
            now = self.clock()
            self._credit_wallet(txn, cur["uid"], cur["amount"], now)  # refund, exactly once (state moves on below)
            cur["reviewedBy"], cur["reviewNote"] = actor, reason[:300]
            self._log(cur, "rejected", actor, f"Rejected: {reason[:200]}. Funds returned.", now)
            self._write(txn, cur)
            return cur

        return self.public(self.store.run(fn))

    def staff_verify_deposit(self, pid: str, actor: str) -> dict:
        d = self._find(pid)
        if d["kind"] != "deposit":
            raise bad_request("not_a_deposit", "That isn't a deposit.")
        return self.verify_deposit(d["uid"], pid, by=actor)
