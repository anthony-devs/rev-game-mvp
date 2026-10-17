"""Payment providers: Paystack, Flutterwave, Stripe, Apple Pay and Google Pay.

Everything here is a MOCK for now (``PAYMENTS_MODE=mock``). The mock behaves like a real
gateway on purpose, so the rest of the system is built and tested against the real shape:

    create_charge   start a payment, get back a provider reference + what the app should open
    fetch_charge    ask the PROVIDER (server to server) whether that payment succeeded
    verify_webhook  check a webhook really came from the provider (signature)
    send_payout     send money out. Must be idempotent: the same payment id never pays twice
    fetch_payout    ask the provider what happened to a payout

The money rules (credit once, pay once, admin approval) live in ``live.py`` and do not
depend on which provider is used. To go real, write a class with these five methods for
each gateway and register it in ``build_providers``. Never trust the app's word that a
payment worked: only ``fetch_charge`` / a verified webhook may credit a wallet.

Real gateway notes (for when the accounts exist):
    Paystack     initialize + verify transaction; webhook header ``x-paystack-signature`` (HMAC SHA512 of the body)
    Flutterwave  standard payments + verify transaction; webhook header ``verif-hash``
    Stripe       PaymentIntent; webhook header ``Stripe-Signature``. Apple Pay and Google Pay are
                 payment sheets that confirm a Stripe PaymentIntent, so they settle through Stripe.
    Apple/Google in-app purchase is for digital goods. Real-money gambling stakes are not allowed
    to use it (App Store 5.3 / Google Play real-money gambling policy), which is why Apple Pay and
    Google Pay here are card-wallet payments, not in-app purchases.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import secrets
from typing import Optional

from .config import Config
from .store import Store

Doc = dict


class ProviderError(Exception):
    """The provider could not be reached or refused the request."""


class Provider:
    id = ""
    label = ""
    deposit = True
    payout = True

    def public(self) -> dict:
        return {"id": self.id, "label": self.label, "deposit": self.deposit, "payout": self.payout}

    def create_charge(self, payment: Doc) -> dict:  # -> {"ref": str, "checkout": dict}
        raise NotImplementedError

    def fetch_charge(self, ref: str) -> dict:  # -> {"status": success|failed|pending, "amount", "currency"}
        raise NotImplementedError

    def verify_webhook(self, headers, raw: bytes) -> Optional[dict]:  # -> {"ref": str} or None if the signature is bad
        raise NotImplementedError

    def send_payout(self, payment: Doc) -> dict:  # -> {"ref": str, "status": success|pending|failed, "reason"?}
        raise NotImplementedError

    def fetch_payout(self, payment: Doc) -> dict:  # -> {"status": success|pending|failed|unknown}
        raise NotImplementedError


# --------------------------------------------------------------------------- mock

def sign(secret: str, raw: bytes) -> str:
    return hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()


class MockProvider(Provider):
    """A fake gateway whose state lives in the store (so it survives restarts and several instances).

    Test hooks: a payout to an account number ending ``0000`` fails at the provider, one ending
    ``9999`` stays pending until the admin presses Sync, anything else succeeds.
    """

    def __init__(self, pid: str, label: str, store: Store, secret: str, *, deposit: bool = True, payout: bool = True):
        self.id, self.label, self.deposit, self.payout = pid, label, deposit, payout
        self.store, self.secret = store, secret

    # -- deposits
    def create_charge(self, payment: Doc) -> dict:
        ref = f"mock_{self.id}_{secrets.token_hex(8)}"
        self.store.run(lambda t: t.set(f"mock_charges/{ref}", {
            "provider": self.id, "paymentId": payment["id"], "amount": payment["amount"],
            "currency": payment["currency"], "status": "pending",
        }))
        return {"ref": ref, "checkout": {"type": "mock", "provider": self.id, "label": self.label, "ref": ref}}

    def fetch_charge(self, ref: str) -> dict:
        c = self.store.read(f"mock_charges/{ref}")
        if c is None:
            return {"status": "failed", "amount": 0, "currency": ""}
        return {"status": c["status"], "amount": c["amount"], "currency": c["currency"]}

    def complete(self, ref: str, outcome: str) -> None:
        """What the customer does on the gateway's page. Only the mock has this."""
        status = "success" if outcome == "success" else "failed"

        def fn(txn):
            c = txn.get(f"mock_charges/{ref}")
            if c is not None and c["status"] == "pending":
                txn.set(f"mock_charges/{ref}", {**c, "status": status})

        self.store.run(fn)

    def webhook_body(self, ref: str) -> tuple[bytes, dict]:
        """A signed webhook for this charge, as the gateway would send it."""
        raw = json.dumps({"event": "charge.completed", "ref": ref}).encode()
        return raw, {"X-Mock-Signature": sign(self.secret, raw)}

    def verify_webhook(self, headers, raw: bytes) -> Optional[dict]:
        given = headers.get("X-Mock-Signature", "")
        if not hmac.compare_digest(given, sign(self.secret, raw)):
            return None
        try:
            data = json.loads(raw)
        except ValueError:
            return None
        ref = data.get("ref") if isinstance(data, dict) else None
        return {"ref": ref} if isinstance(ref, str) and ref else None

    # -- payouts (idempotent by payment id)
    def send_payout(self, payment: Doc) -> dict:
        path = f"mock_payouts/{payment['id']}"
        existing = self.store.read(path)
        if existing is not None:  # asked twice: same answer, no second transfer
            return {"ref": existing["ref"], "status": existing["status"], **({"reason": existing["reason"]} if existing.get("reason") else {})}
        acct = str(payment.get("destination", {}).get("accountNumber", ""))
        status, reason = ("failed", "Bank rejected the account.") if acct.endswith("0000") else (("pending", "") if acct.endswith("9999") else ("success", ""))
        out = {"ref": f"mockpo_{secrets.token_hex(8)}", "status": status, "reason": reason, "provider": self.id, "amount": payment["amount"]}

        def fn(txn):
            cur = txn.get(path)  # re-check inside the transaction: two callers, one transfer
            if cur is None:
                txn.set(path, out)
                return out
            return cur

        final = self.store.run(fn)
        return {"ref": final["ref"], "status": final["status"], **({"reason": final["reason"]} if final.get("reason") else {})}

    def fetch_payout(self, payment: Doc) -> dict:
        p = self.store.read(f"mock_payouts/{payment['id']}")
        return {"status": p["status"] if p else "unknown", "ref": p["ref"] if p else None}

    def settle_pending_payout(self, payment_id: str) -> None:
        """The bank finally settles a pending transfer (the mock does it when staff press Sync)."""

        def fn(txn):
            p = txn.get(f"mock_payouts/{payment_id}")
            if p is not None and p["status"] == "pending":
                txn.set(f"mock_payouts/{payment_id}", {**p, "status": "success"})

        self.store.run(fn)


def build_providers(store: Store, cfg: Config) -> dict[str, Provider]:
    if cfg.payments_mode != "mock":
        raise RuntimeError(
            "PAYMENTS_MODE is not 'mock' but no real gateway is wired in yet. "
            "Add a Provider class for each gateway in providers.py and register it here."
        )
    s = cfg.webhook_secret
    return {
        p.id: p
        for p in (
            MockProvider("paystack", "Paystack", store, s),
            MockProvider("flutterwave", "Flutterwave", store, s),
            MockProvider("stripe", "Card (Stripe)", store, s),
            MockProvider("apple_pay", "Apple Pay", store, s, payout=False),
            MockProvider("google_pay", "Google Pay", store, s, payout=False),
        )
    }
