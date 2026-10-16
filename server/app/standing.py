"""Account standing: bans, suspensions, payout restrictions and investigations.

Every action lives in ``users/{uid}/standing_actions/{id}``. The app listens to
one small summary, ``users/{uid}/account/standing``, which lists the actions that
are active right now. Only the server writes either of them.

What each type does
-------------------
=================  ==========  ==================  =========================
type               plays?      credits (daily,     ends
                               top-up, reset)?
=================  ==========  ==================  =========================
ban                blocked     blocked             never, unless an appeal
                                                   is approved or staff lift it
suspension         blocked     blocked             on its date, or lifted
payout_restriction blocked*    blocked             on its date, or lifted
investigation      blocked     blocked             when staff close it
=================  ==========  ==================  =========================
* ``blocksPlay`` can be switched off for a payout restriction when it is created.

When a suspension or restriction ends the player is on **probation** for
``probation_hours`` (default 72h): they can play, but with a bet cap and no
free credits. That is the "restricted in the past 3 days" check.

Enforcement is on the server: every route that starts a round or hands out
credits goes through ``enforce``. The app's screens are only a courtesy.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Optional

from .config import Config
from .errors import ApiError, bad_request
from .store import Doc, Store, Txn, action_path, appeal_path, log_path, standing_path
from .util import Clock, as_utc, utcnow

TYPES = ("ban", "suspension", "payout_restriction", "investigation")
SEVERITY = {"ban": 4, "suspension": 3, "investigation": 2, "payout_restriction": 1}
STATE_NAME = {
    "ban": "banned",
    "suspension": "suspended",
    "investigation": "under_review",
    "payout_restriction": "restricted",
}
# Types that always block play. A payout restriction decides at creation time.
ALWAYS_BLOCK_PLAY = {"ban", "suspension", "investigation"}
# Types that get a probation period once they end (investigations only when staff say so).
PROBATION_AFTER = {"suspension", "payout_restriction", "ban"}

MAX_REASON = 300
MAX_NOTE = 1000


def _iso(value) -> Optional[str]:
    value = as_utc(value)
    return value.isoformat() if value else None


def _human(value) -> Optional[str]:
    """"3 Jan 2026, 14:05 UTC" for messages the player reads."""
    if isinstance(value, str):
        value = datetime.fromisoformat(value)
    value = as_utc(value)
    return value.strftime("%-d %b %Y, %H:%M UTC") if value else None


class StandingService:
    def __init__(self, store: Store, cfg: Config, clock: Clock = utcnow):
        self.store, self.cfg, self.clock = store, cfg, clock

    # ------------------------------------------------------------------ reading

    @staticmethod
    def _empty() -> Doc:
        return {"active": [], "probationUntil": None, "updatedAt": None}

    def _expired(self, entry: Doc, now: datetime) -> bool:
        exp = as_utc(entry.get("expiresAt"))
        return exp is not None and exp <= now

    def summary(self, uid: str) -> Doc:
        """The player's standing, with finished actions settled first."""
        now = self.clock()
        doc = self.store.read(standing_path(uid)) or self._empty()
        if any(self._expired(e, now) for e in doc.get("active", [])):
            doc = self.refresh(uid)
        return doc

    def refresh(self, uid: str) -> Doc:
        """Close actions whose end date has passed, start probation, write the summary."""

        def fn(txn: Txn):
            now = self.clock()
            doc = txn.get(standing_path(uid)) or self._empty()
            keep, ended = [], []
            for e in doc.get("active", []):
                (ended if self._expired(e, now) else keep).append(e)
            if not ended:
                return doc
            for e in ended:
                self._end(txn, uid, e, now, status="expired", actor="system", note="Reached its end date.", outcome="expired")
                if e["type"] in PROBATION_AFTER and self.cfg.probation_hours > 0:
                    exp = as_utc(e["expiresAt"])
                    doc["probationUntil"] = self._later(doc.get("probationUntil"), exp + timedelta(hours=self.cfg.probation_hours))
            doc["active"] = keep
            doc["updatedAt"] = now
            txn.set(standing_path(uid), doc)
            return doc

        return self.store.run(fn)

    @staticmethod
    def _later(a, b):
        a = as_utc(a)
        return b if a is None or b > a else a

    def probation_until(self, doc: Doc, now: datetime) -> Optional[datetime]:
        until = as_utc(doc.get("probationUntil"))
        return until if until is not None and until > now else None

    def public(self, doc: Doc) -> dict:
        """The summary as JSON for the app and the dashboard."""
        now = self.clock()
        active = [e for e in doc.get("active", []) if not self._expired(e, now)]
        top = max(active, key=lambda e: SEVERITY[e["type"]], default=None)
        prob = self.probation_until(doc, now)
        return {
            "state": STATE_NAME[top["type"]] if top else ("probation" if prob else "good"),
            "blocksPlay": any(e.get("blocksPlay") for e in active),
            "blocksCredits": bool(active) or prob is not None,
            "probationUntil": _iso(prob),
            "probationMaxBet": self.cfg.probation_max_bet if prob else None,
            "active": [self._entry_json(e) for e in active],
        }

    @staticmethod
    def _entry_json(e: Doc) -> dict:
        return {
            "id": e["id"],
            "type": e["type"],
            "reason": e.get("reason", ""),
            "publicNote": e.get("publicNote", ""),
            "startsAt": _iso(e.get("startsAt")),
            "expiresAt": _iso(e.get("expiresAt")),
            "blocksPlay": bool(e.get("blocksPlay")),
            "appealAllowed": bool(e.get("appealAllowed", True)),
            "appealStatus": e.get("appealStatus", "none"),
            "appealResponse": e.get("appealResponse"),
            "appealRetryAt": _iso(e.get("appealRetryAt")),
        }

    # -------------------------------------------------------------- enforcement

    def enforce(self, uid: str, kind: str, bet: float | None = None, endpoint: str = "") -> None:
        """Raise a 403 if this player may not do ``kind`` (play | credits | delete) right now."""
        now = self.clock()
        doc = self.summary(uid)
        active = [e for e in doc.get("active", []) if not self._expired(e, now)]
        pub = self.public(doc)

        if kind == "play":
            blocking = [e for e in active if e.get("blocksPlay")]
            if blocking:
                raise self._blocked(max(blocking, key=lambda e: SEVERITY[e["type"]]), pub)
            if bet is not None and pub["probationMaxBet"] is not None and bet > pub["probationMaxBet"]:
                raise ApiError(
                    403,
                    "probation_bet_cap",
                    f"Your account is on probation until {_human(pub['probationUntil'])}. Bets are capped at {int(pub['probationMaxBet'])}.",
                    standing=pub,
                )
        elif kind == "credits":
            if active:
                raise self._blocked(max(active, key=lambda e: SEVERITY[e["type"]]), pub, credits=True)
            if pub["probationUntil"]:
                raise ApiError(
                    403,
                    "credits_restricted",
                    f"Free credits are paused until {_human(pub['probationUntil'])} while your account is on probation.",
                    standing=pub,
                )
        elif kind == "delete":
            if active or pub["probationUntil"]:
                raise ApiError(
                    403,
                    "account_locked",
                    "You can't delete this account while it has an open moderation action or probation.",
                    standing=pub,
                )

    @staticmethod
    def _blocked(entry: Doc, pub: dict, credits: bool = False) -> ApiError:
        t = entry["type"]
        until = _human(entry.get("expiresAt"))
        if t == "ban":
            code, msg = "account_banned", "Your account has been banned. You can appeal from the account screen."
        elif t == "suspension":
            code, msg = "account_suspended", f"Your account is suspended until {until}." if until else "Your account is suspended."
        elif t == "investigation":
            code, msg = "account_under_review", "Your account is under review. Play is paused until it is finished."
        else:
            code = "credits_restricted" if credits else "account_restricted"
            msg = "Your account has a payout restriction." + (f" It ends {until}." if until else "")
        return ApiError(403, code, msg, standing=pub)

    # ----------------------------------------------------------------- actions

    def apply(
        self,
        uid: str,
        type_: str,
        reason: str,
        *,
        actor: str,
        public_note: str = "",
        internal_note: str = "",
        duration_hours: float | None = None,
        blocks_play: bool | None = None,
        appeal_allowed: bool = True,
    ) -> Doc:
        if type_ not in TYPES:
            raise bad_request("invalid_type", f"Type must be one of {', '.join(TYPES)}.")
        reason = (reason or "").strip()
        if not reason or len(reason) > MAX_REASON:
            raise bad_request("invalid_reason", f"Give a reason (1 to {MAX_REASON} characters).")
        public_note = (public_note or "").strip()[:MAX_NOTE]
        internal_note = (internal_note or "").strip()[:MAX_NOTE]
        if duration_hours is not None:
            try:
                duration_hours = float(duration_hours)
            except (TypeError, ValueError):
                raise bad_request("invalid_duration", "Duration must be a number of hours.")
            if not (0 < duration_hours <= 24 * 365):
                raise bad_request("invalid_duration", "Duration must be between 1 hour and one year.")
        if type_ == "suspension" and duration_hours is None:
            raise bad_request("duration_required", "A suspension needs a duration.")
        if type_ == "ban":
            duration_hours = None  # bans are permanent until lifted
        plays_blocked = True if type_ in ALWAYS_BLOCK_PLAY else (True if blocks_play is None else bool(blocks_play))

        action_id = uuid.uuid4().hex

        def fn(txn: Txn):
            now = self.clock()
            doc = txn.get(standing_path(uid)) or self._empty()
            if any(e["type"] == type_ and not self._expired(e, now) for e in doc.get("active", [])):
                raise ApiError(409, "already_active", f"This player already has an active {type_.replace('_', ' ')}.")
            expires = now + timedelta(hours=duration_hours) if duration_hours else None
            action = {
                "id": action_id,
                "uid": uid,
                "type": type_,
                "reason": reason,
                "publicNote": public_note,
                "internalNote": internal_note,
                "createdAt": now,
                "createdBy": actor,
                "startsAt": now,
                "expiresAt": expires,
                "blocksPlay": plays_blocked,
                "appealAllowed": bool(appeal_allowed),
                "status": "active",
            }
            txn.set(action_path(uid, action_id), action)
            entry = {k: action[k] for k in ("id", "type", "reason", "publicNote", "startsAt", "expiresAt", "blocksPlay", "appealAllowed")}
            entry["appealStatus"] = "none"
            doc["active"] = [*doc.get("active", []), entry]
            doc["updatedAt"] = now
            txn.set(standing_path(uid), doc)
            self._log(txn, uid, action_id, "created", type_, actor, reason, now)
            return action

        return self.store.run(fn)

    def lift(self, uid: str, action_id: str, *, actor: str, note: str = "", probation_hours: float | None = None, outcome: str = "lifted") -> Doc:
        def fn(txn: Txn):
            now = self.clock()
            doc = txn.get(standing_path(uid)) or self._empty()
            return self._lift_in_txn(txn, uid, doc, action_id, actor, note, probation_hours, outcome, now)

        return self.store.run(fn)

    def _lift_in_txn(self, txn, uid, doc, action_id, actor, note, probation_hours, outcome, now):
        entry = next((e for e in doc.get("active", []) if e["id"] == action_id), None)
        if entry is None:
            raise ApiError(404, "action_not_active", "That action is not active.")
        self._end(txn, uid, entry, now, status="lifted", actor=actor, note=note, outcome=outcome)
        doc["active"] = [e for e in doc["active"] if e["id"] != action_id]
        hours = probation_hours
        if hours is None:
            hours = self.cfg.probation_hours if entry["type"] in PROBATION_AFTER else 0
        if hours and hours > 0:
            doc["probationUntil"] = self._later(doc.get("probationUntil"), now + timedelta(hours=float(hours)))
        doc["updatedAt"] = now
        txn.set(standing_path(uid), doc)
        return doc

    def _end(self, txn, uid, entry, now, *, status, actor, note, outcome):
        path = action_path(uid, entry["id"])
        action = txn.get(path) or dict(entry)
        action.update({"status": status, "endedAt": now, "endedBy": actor, "endNote": note, "outcome": outcome})
        txn.set(path, action)
        self._log(txn, uid, entry["id"], status, entry["type"], actor, note, now)

    @staticmethod
    def _log(txn, uid, action_id, event, type_, actor, note, now):
        log_id = uuid.uuid4().hex
        txn.set(
            log_path(log_id),
            {"id": log_id, "uid": uid, "actionId": action_id, "event": event, "type": type_, "actor": actor, "note": note, "at": now},
        )

    # ----------------------------------------------------------------- appeals

    def appeal(self, uid: str, action_id: str, message: str, attachments: list | None = None) -> dict:
        message = (message or "").strip()
        if not (20 <= len(message) <= 1000):
            raise bad_request("invalid_appeal", "Explain what happened in 20 to 1000 characters.")
        appeal_id = uuid.uuid4().hex

        def fn(txn: Txn):
            now = self.clock()
            doc = txn.get(standing_path(uid)) or self._empty()
            entry = next((e for e in doc.get("active", []) if e["id"] == action_id and not self._expired(e, now)), None)
            if entry is None:
                raise ApiError(404, "action_not_active", "That action is not active.")
            if not entry.get("appealAllowed", True):
                raise ApiError(403, "appeal_not_allowed", "This action can't be appealed.")
            if entry.get("appealStatus") == "pending":
                raise ApiError(409, "appeal_pending", "Your appeal is already being reviewed.")
            retry = as_utc(entry.get("appealRetryAt"))
            if retry is not None and now < retry:
                raise ApiError(429, "appeal_cooldown", "You can appeal again later.", retryAt=_iso(retry))
            txn.set(
                appeal_path(uid, appeal_id),
                {
                    "id": appeal_id,
                    "uid": uid,
                    "actionId": action_id,
                    "actionType": entry["type"],
                    "actionReason": entry.get("reason", ""),
                    "message": message,
                    "attachments": list(attachments or []),
                    "status": "pending",
                    "createdAt": now,
                },
            )
            entry.update({"appealStatus": "pending", "appealId": appeal_id, "appealResponse": None, "appealRetryAt": None})
            doc["updatedAt"] = now
            txn.set(standing_path(uid), doc)
            self._log(txn, uid, action_id, "appeal_created", entry["type"], "player", message[:200], now)
            return {"id": appeal_id, "status": "pending"}

        return self.store.run(fn)

    def decide_appeal(self, uid: str, appeal_id: str, decision: str, response: str, *, actor: str, probation_hours: float | None = None) -> dict:
        if decision not in ("approve", "reject"):
            raise bad_request("invalid_decision", "Decision must be approve or reject.")
        response = (response or "").strip()[:MAX_NOTE]
        if decision == "reject" and not response:
            raise bad_request("response_required", "Tell the player why the appeal was rejected.")

        def fn(txn: Txn):
            now = self.clock()
            appeal = txn.get(appeal_path(uid, appeal_id))
            if appeal is None:
                raise ApiError(404, "appeal_not_found", "Appeal not found.")
            if appeal["status"] != "pending":
                raise ApiError(409, "appeal_decided", "This appeal was already decided.")
            doc = txn.get(standing_path(uid)) or self._empty()
            appeal.update({"status": "approved" if decision == "approve" else "rejected", "response": response, "decidedAt": now, "decidedBy": actor})
            txn.set(appeal_path(uid, appeal_id), appeal)
            if decision == "approve":
                if any(e["id"] == appeal["actionId"] for e in doc.get("active", [])):
                    self._lift_in_txn(txn, uid, doc, appeal["actionId"], actor, response or "Appeal approved.", probation_hours, "appeal_approved", now)
                self._log(txn, uid, appeal["actionId"], "appeal_approved", appeal["actionType"], actor, response, now)
            else:
                for e in doc.get("active", []):
                    if e["id"] == appeal["actionId"]:
                        e.update(
                            {
                                "appealStatus": "rejected",
                                "appealResponse": response,
                                "appealRetryAt": now + timedelta(hours=self.cfg.appeal_cooldown_hours),
                            }
                        )
                doc["updatedAt"] = now
                txn.set(standing_path(uid), doc)
                self._log(txn, uid, appeal["actionId"], "appeal_rejected", appeal["actionType"], actor, response, now)
            return appeal

        return self.store.run(fn)

    # -------------------------------------------------------------------- risk

    def actions(self, uid: str) -> list[Doc]:
        rows = [doc for _id, doc in self.store.list(f"users/{uid}/standing_actions", 500)]
        rows.sort(key=lambda a: as_utc(a["createdAt"]), reverse=True)
        return rows

    def appeals(self, uid: str) -> list[Doc]:
        rows = [doc for _id, doc in self.store.list(f"users/{uid}/appeals", 200)]
        rows.sort(key=lambda a: as_utc(a["createdAt"]), reverse=True)
        return rows

    def risk(self, uid: str, days: int | None = None) -> dict:
        """The checks staff look at: restricted in the past N days, repeat offender, probation..."""
        days = days or self.cfg.risk_window_days
        now = self.clock()
        window = now - timedelta(days=days)
        month = now - timedelta(days=30)
        actions = self.actions(uid)
        doc = self.summary(uid)

        def in_window(a, since):
            started = as_utc(a["createdAt"])
            ended = as_utc(a.get("endedAt"))
            return a["status"] == "active" or started >= since or (ended is not None and ended >= since)

        recent = [a for a in actions if in_window(a, window)]
        last_30 = [a for a in actions if as_utc(a["createdAt"]) >= month]
        prob = self.probation_until(doc, now)
        return {
            "windowDays": days,
            "restrictedInWindow": bool(recent),
            "typesInWindow": sorted({a["type"] for a in recent}),
            "activeNow": [a["id"] for a in actions if a["status"] == "active" and not self._expired(a, now)],
            "onProbation": prob is not None,
            "probationUntil": _iso(prob),
            "actionsLast30d": len(last_30),
            "suspensionsLast30d": sum(1 for a in last_30 if a["type"] == "suspension"),
            "bansEver": sum(1 for a in actions if a["type"] == "ban"),
            "totalActions": len(actions),
            "repeatOffender": len(last_30) >= 3,
            "openAppeals": sum(1 for a in self.appeals(uid) if a["status"] == "pending"),
            "lastActionAt": _iso(actions[0]["createdAt"]) if actions else None,
        }

    def recent_events(self, days: int, limit: int = 500) -> list[Doc]:
        since = self.clock() - timedelta(days=days)
        rows = [d for _id, d in self.store.list("moderation_log", limit) if as_utc(d["at"]) >= since]
        rows.sort(key=lambda d: as_utc(d["at"]), reverse=True)
        return rows

    # ------------------------------------------------------------- JSON shapes

    def action_json(self, a: Doc) -> dict:
        return {
            "id": a["id"],
            "type": a["type"],
            "status": a["status"],
            "reason": a.get("reason", ""),
            "publicNote": a.get("publicNote", ""),
            "internalNote": a.get("internalNote", ""),
            "createdAt": _iso(a.get("createdAt")),
            "createdBy": a.get("createdBy"),
            "expiresAt": _iso(a.get("expiresAt")),
            "blocksPlay": bool(a.get("blocksPlay")),
            "appealAllowed": bool(a.get("appealAllowed", True)),
            "endedAt": _iso(a.get("endedAt")),
            "endedBy": a.get("endedBy"),
            "endNote": a.get("endNote"),
            "outcome": a.get("outcome"),
        }

    @staticmethod
    def appeal_json(a: Doc) -> dict:
        return {
            "id": a["id"],
            "actionId": a["actionId"],
            "actionType": a.get("actionType"),
            "actionReason": a.get("actionReason"),
            "message": a.get("message"),
            "attachments": a.get("attachments", []),
            "status": a["status"],
            "response": a.get("response"),
            "createdAt": _iso(a.get("createdAt")),
            "decidedAt": _iso(a.get("decidedAt")),
            "decidedBy": a.get("decidedBy"),
        }

    @staticmethod
    def log_json(d: Doc) -> dict:
        return {k: (_iso(v) if k == "at" else v) for k, v in d.items()}
