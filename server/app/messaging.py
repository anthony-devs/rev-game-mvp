"""Email from the founder dashboard: one person or a whole audience.

Safe by design: the founder must type SEND, every send has a one-time key (a double click
can't email everyone twice), one campaign per minute, plain text only, players who opted
out are skipped, and each campaign leaves a record. Without SMTP settings it runs in mock
mode: nothing leaves the server, the campaign is recorded as "mock".
"""
from __future__ import annotations

import logging
import re
import smtplib
import threading
import time
from datetime import timedelta
from email.message import EmailMessage

from .config import Config
from .errors import ApiError, bad_request
from .store import Store
from .util import Clock, as_utc, utcnow

log = logging.getLogger("mail")
EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,255}\.[^@\s]{2,}$")
FOOTER = "\n\n--\nYou are receiving this because you have a REV Games account. Reply to this email if you want to stop hearing from us."


class MockMailer:
    mode = "mock"

    def __init__(self):
        self.sent: list[dict] = []

    def send(self, to: str, subject: str, text: str) -> None:
        self.sent.append({"to": to, "subject": subject, "text": text})
        log.info("mock email to %s: %s", to, subject)


class SmtpMailer:
    mode = "smtp"

    def __init__(self, cfg: Config):
        self.cfg = cfg

    def send(self, to: str, subject: str, text: str) -> None:
        msg = EmailMessage()
        msg["From"], msg["To"], msg["Subject"] = self.cfg.mail_from, to, subject.replace("\n", " ")
        msg.set_content(text)
        with smtplib.SMTP(self.cfg.smtp_host, self.cfg.smtp_port, timeout=20) as s:
            s.starttls()
            if self.cfg.smtp_user:
                s.login(self.cfg.smtp_user, self.cfg.smtp_password)
            s.send_message(msg)


def build_mailer(cfg: Config):
    return SmtpMailer(cfg) if cfg.smtp_host else MockMailer()


class MessagingService:
    def __init__(self, store: Store, cfg: Config, mailer=None, clock: Clock = utcnow, background: bool = True, pause: float = 0.2):
        self.store, self.cfg, self.mailer, self.clock = store, cfg, mailer or MockMailer(), clock
        self.background, self.pause = background, pause
        self._last_send = 0.0
        self._lock = threading.Lock()
        self.campaigns = store.watch_list("campaigns", 30, order_by="createdAt")

    # ------------------------------------------------------------- audiences

    def _cutoff(self):
        return self.clock() - timedelta(days=self.cfg.active_days)

    def count(self, audience: str) -> int:
        """How many players an audience is (cheap: counted by the database, not read)."""
        cutoff = self._cutoff()
        if audience == "all":
            return self.store.count("users")
        if audience == "active":
            return self.store.count("users", ("lastSeenAt", ">=", cutoff))
        if audience == "inactive":
            return max(0, self.store.count("users") - self.store.count("users", ("lastSeenAt", ">=", cutoff)))
        if audience.startswith("user:"):
            return 1
        raise bad_request("bad_audience", "Pick all, active, inactive or one player.")

    def _recipients(self, audience: str) -> tuple[list[dict], int]:
        """(people to email, how many were skipped)."""
        if audience.startswith("user:"):
            token = audience[5:].strip()
            doc = self.store.read(f"users/{token}")
            if doc is None:
                for uid, d in self.store.list("users", self.cfg.campaign_max_recipients):
                    if str(d.get("email") or "").lower() == token.lower():
                        doc, token = d, uid
                        break
            if doc is None:
                raise ApiError(404, "user_not_found", "No player with that id or email.")
            return [{"uid": token, **doc}], 0
        cutoff = self._cutoff()
        rows = self.store.list("users", self.cfg.campaign_max_recipients)
        out, skipped = [], 0
        for uid, d in rows:
            seen = as_utc(d.get("lastSeenAt") or d.get("lastLoginAt"))
            is_active = seen is not None and seen >= cutoff
            if (audience == "active" and not is_active) or (audience == "inactive" and is_active):
                continue
            if d.get("emailOptOut") or not EMAIL_RE.match(str(d.get("email") or "")):
                skipped += 1
                continue
            out.append({"uid": uid, **d})
        return out, skipped

    # ------------------------------------------------------------------ send

    def send(self, actor: str, audience: str, subject: str, body: str, key: str, confirm: str) -> dict:
        subject, body, key = (subject or "").strip(), (body or "").strip(), (key or "").strip()
        if confirm != "SEND":
            raise bad_request("confirm_required", "Type SEND to confirm.")
        if not (3 <= len(subject) <= 150):
            raise bad_request("bad_subject", "The subject needs 3 to 150 characters.")
        if not (10 <= len(body) <= 5000):
            raise bad_request("bad_body", "The message needs 10 to 5,000 characters.")
        if not re.fullmatch(r"[A-Za-z0-9_-]{8,64}", key):
            raise bad_request("bad_key", "Missing send key.")
        audience = (audience or "").strip()
        self.count(audience)  # validates it
        with self._lock:
            if time.monotonic() - self._last_send < 60:
                raise ApiError(429, "slow_down", "One campaign per minute. Wait a moment.")
            self._last_send = time.monotonic()

        def make(txn):
            if txn.get(f"campaigns/{key}") is not None:
                raise ApiError(409, "already_sent", "That send was already started. It won't run twice.")
            doc = {"id": key, "audience": audience, "subject": subject, "body": body, "by": actor, "status": "queued", "mode": self.mailer.mode,
                   "createdAt": self.clock(), "sent": 0, "failed": 0, "skipped": 0, "total": 0}
            txn.set(f"campaigns/{key}", doc)
            return doc

        doc = self.store.run(make)
        if self.background:
            threading.Thread(target=self._run, args=(key,), daemon=True, name=f"campaign-{key[:8]}").start()
        else:
            self._run(key)
        return self.public(self.store.read(f"campaigns/{key}") or doc)

    def _run(self, key: str) -> None:
        c = self.store.read(f"campaigns/{key}")
        if c is None or c["status"] != "queued":
            return
        try:
            people, skipped = self._recipients(c["audience"])
        except Exception as e:
            self.store.merge(f"campaigns/{key}", {"status": "failed", "error": str(e)[:200]})
            return
        self.store.merge(f"campaigns/{key}", {"status": "sending", "total": len(people), "skipped": skipped})
        sent = failed = 0
        for p in people:
            name = str(p.get("displayName") or "there").split(" ")[0][:40]
            try:
                self.mailer.send(p["email"], c["subject"], c["body"].replace("{name}", name) + FOOTER)
                sent += 1
            except Exception:
                log.exception("email to %s failed", p.get("uid"))
                failed += 1
            if (sent + failed) % 10 == 0:
                self.store.merge(f"campaigns/{key}", {"sent": sent, "failed": failed})
            if self.pause:
                time.sleep(self.pause)
        self.store.merge(f"campaigns/{key}", {"status": "done" if not failed else "done_with_errors", "sent": sent, "failed": failed, "finishedAt": self.clock()})

    @staticmethod
    def public(c: dict) -> dict:
        iso = lambda v: v.isoformat() if v else None
        return {k: (iso(v) if k in ("createdAt", "finishedAt") else v) for k, v in c.items() if k != "body"} | {"preview": (c.get("body") or "")[:160]}

    def recent(self) -> list[dict]:
        return [self.public(d) for _i, d in self.campaigns.rows()]
