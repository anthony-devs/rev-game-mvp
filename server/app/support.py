"""Customer support tickets.

Layout (Firestore):
    users/{uid}/tickets/{tid}                 what the player sees (the app listens to this)
    users/{uid}/tickets/{tid}/messages/{mid}  the conversation (player + rep replies only)
    tickets/{tid}                             the staff view: assignee, priority, who wrote what
    tickets/{tid}/notes/{nid}                 internal notes. Server only, the player never gets these

Status: open (waiting on us) -> pending (waiting on the player) -> solved -> closed.
A reply from the player re-opens anything except a closed ticket.
"""
from __future__ import annotations

import uuid
from datetime import timedelta

from .config import Config
from .errors import ApiError, bad_request
from .store import Store, Txn
from .uploads import UploadService
from .util import Clock, as_utc, utcnow

CATEGORIES = {
    "account": "Account & sign-in",
    "credits": "Credits & balance",
    "gameplay": "A game or round",
    "fairness": "Fairness & results",
    "restriction": "Ban, suspension or restriction",
    "technical": "Bug or technical problem",
    "other": "Something else",
}
STATUSES = ("open", "pending", "solved", "closed")
PRIORITIES = ("normal", "high", "urgent")
PRIORITY_RANK = {"urgent": 0, "high": 1, "normal": 2}
MAX_TEXT = 2000
MAX_MESSAGES = 200

CANNED = [
    {"id": "hello", "title": "Greeting", "text": "Hi {name}, thanks for getting in touch. I'm looking into this now."},
    {"id": "more_info", "title": "Ask for details", "text": "Could you tell me a bit more about what happened, when it happened, and which game you were in? A screenshot helps a lot."},
    {"id": "balance", "title": "Balance question", "text": "Your balance is always the server's number. If the app shows something different, close and reopen it and it will refresh. If it still looks wrong, send me a screenshot of the History page."},
    {"id": "fair", "title": "Fairness check", "text": "Every round can be verified. Open Fairness in the app, rotate your seed, then tap a round to check its proof. If a result doesn't verify, tell me the round time and game and I'll escalate it."},
    {"id": "appeal", "title": "How to appeal", "text": "You can appeal from the account screen. Explain what happened in your own words and attach anything that helps (screenshots, a video, a PDF). Our team reviews every appeal."},
    {"id": "credits", "title": "Free credits paused", "text": "Free credits are paused while an account is restricted or on probation after a restriction ends. They come back automatically when probation finishes."},
    {"id": "closing", "title": "Closing", "text": "I'm marking this as solved. If anything is still wrong, reply here and it will reopen automatically."},
]


class SupportService:
    def __init__(self, store: Store, cfg: Config, uploads: UploadService, clock: Clock = utcnow):
        self.store, self.cfg, self.uploads, self.clock = store, cfg, uploads, clock

    # ---------------------------------------------------------------- helpers
    @staticmethod
    def _preview(text: str, atts: list) -> str:
        t = " ".join((text or "").split())
        if not t and atts:
            t = f"[{len(atts)} attachment{'s' if len(atts) != 1 else ''}]"
        return t[:120]

    def _text(self, text) -> str:
        text = (text or "").strip() if isinstance(text, str) else ""
        if len(text) > MAX_TEXT:
            raise bad_request("message_too_long", f"Keep messages under {MAX_TEXT} characters.")
        return text

    @staticmethod
    def _user_view(t: dict) -> dict:
        return {
            "id": t["id"],
            "subject": t["subject"],
            "category": t["category"],
            "status": t["status"],
            "createdAt": t["createdAt"],
            "updatedAt": t["updatedAt"],
            "lastFrom": t["lastFrom"],
            "lastPreview": t["lastPreview"],
            "unread": t["unreadUser"],
            "messageCount": t["messageCount"],
        }

    def _save(self, txn: Txn, t: dict) -> None:
        txn.set(f"tickets/{t['id']}", t)
        user = {**self._user_view(t), "unread": t["unreadUser"]}
        txn.set(f"users/{t['uid']}/tickets/{t['id']}", user)

    def _add_message(self, txn: Txn, t: dict, sender: str, author: str, text: str, atts: list, now) -> dict:
        mid = uuid.uuid4().hex
        msg = {"id": mid, "from": sender, "author": author, "text": text, "attachments": atts, "createdAt": now}
        txn.set(f"users/{t['uid']}/tickets/{t['id']}/messages/{mid}", msg)
        t["messageCount"] = int(t.get("messageCount", 0)) + 1
        if t["messageCount"] > MAX_MESSAGES:
            raise ApiError(429, "ticket_full", "This conversation is full. Please open a new ticket.")
        t["lastFrom"], t["lastPreview"] = sender, self._preview(text, atts)
        t["updatedAt"] = t["lastMessageAt"] = now
        return msg

    def _get(self, txn_or_store, tid: str) -> dict:
        t = txn_or_store.get(f"tickets/{tid}") if isinstance(txn_or_store, Txn) else txn_or_store.read(f"tickets/{tid}")
        if t is None:
            raise ApiError(404, "ticket_not_found", "Ticket not found.")
        return t

    # ------------------------------------------------------------------ player
    def create(self, uid: str, profile: dict, subject, category, text, attachment_ids) -> dict:
        subject = (subject or "").strip() if isinstance(subject, str) else ""
        if not (3 <= len(subject) <= 80):
            raise bad_request("invalid_subject", "Give the ticket a short title (3 to 80 characters).")
        if category not in CATEGORIES:
            raise bad_request("invalid_category", "Pick a category.")
        text = self._text(text)
        atts = self.uploads.resolve(uid, attachment_ids)
        if not text and not atts:
            raise bad_request("empty_message", "Tell us what's going on.")
        if text and len(text) < 5:
            raise bad_request("empty_message", "Tell us a bit more.")
        open_now = [d for _i, d in self.store.list(f"users/{uid}/tickets", 200) if d["status"] != "closed"]
        if len(open_now) >= self.cfg.max_open_tickets:
            raise ApiError(429, "too_many_tickets", f"You have {len(open_now)} open tickets. Close one or wait for a reply first.")
        tid = uuid.uuid4().hex

        def fn(txn: Txn):
            now = self.clock()
            t = {
                "id": tid, "uid": uid, "subject": subject, "category": category, "status": "open", "priority": "normal",
                "assignee": None, "assigneeName": None, "createdAt": now, "updatedAt": now, "lastMessageAt": now,
                "lastFrom": "user", "lastPreview": "", "unreadUser": False, "unreadStaff": True, "messageCount": 0,
                "playerName": profile.get("displayName") or "Player", "playerEmail": profile.get("email"),
            }
            self._add_message(txn, t, "user", t["playerName"], text, atts, now)
            self._save(txn, t)
            return t

        return self._user_view(self.store.run(fn))

    def list_for_user(self, uid: str) -> list[dict]:
        rows = [d for _i, d in self.store.list(f"users/{uid}/tickets", 200)]
        rows.sort(key=lambda d: as_utc(d["updatedAt"]), reverse=True)
        return [self._json(d) for d in rows]

    def get_for_user(self, uid: str, tid: str) -> dict:
        t = self._owned(uid, tid)
        msgs = self.messages(uid, tid)
        return {"ticket": self._json(self._user_view(t)), "messages": msgs}

    def _owned(self, uid: str, tid: str) -> dict:
        t = self.store.read(f"tickets/{tid}")
        if t is None or t["uid"] != uid:
            raise ApiError(404, "ticket_not_found", "Ticket not found.")
        return t

    def messages(self, uid: str, tid: str) -> list[dict]:
        rows = [d for _i, d in self.store.list(f"users/{uid}/tickets/{tid}/messages", 400)]
        rows.sort(key=lambda d: as_utc(d["createdAt"]))
        return [self._msg_json(m) for m in rows]

    def user_reply(self, uid: str, tid: str, text, attachment_ids) -> dict:
        self._owned(uid, tid)
        text = self._text(text)
        atts = self.uploads.resolve(uid, attachment_ids)
        if not text and not atts:
            raise bad_request("empty_message", "Write a message first.")

        def fn(txn: Txn):
            t = self._get(txn, tid)
            if t["uid"] != uid:
                raise ApiError(404, "ticket_not_found", "Ticket not found.")
            if t["status"] == "closed":
                raise ApiError(409, "ticket_closed", "This ticket is closed. Open a new one if you still need help.")
            now = self.clock()
            msg = self._add_message(txn, t, "user", t["playerName"], text, atts, now)
            t["status"], t["unreadStaff"], t["unreadUser"] = "open", True, False
            self._save(txn, t)
            return msg

        return self._msg_json(self.store.run(fn))

    def user_close(self, uid: str, tid: str) -> dict:
        self._owned(uid, tid)

        def fn(txn: Txn):
            t = self._get(txn, tid)
            t["status"], t["updatedAt"], t["unreadUser"] = "closed", self.clock(), False
            self._save(txn, t)
            return t

        return self._json(self._user_view(self.store.run(fn)))

    def user_mark_read(self, uid: str, tid: str) -> None:
        self._owned(uid, tid)

        def fn(txn: Txn):
            t = self._get(txn, tid)
            if t["unreadUser"]:
                t["unreadUser"] = False
                self._save(txn, t)

        self.store.run(fn)

    # ------------------------------------------------------------------- staff
    def staff_list(self, *, status=None, assignee=None, q=None, category=None, me: str = "") -> dict:
        rows = [d for _i, d in self.store.list("tickets", 1000)]
        counts = {s: 0 for s in STATUSES}
        for d in rows:
            counts[d["status"]] += 1
        q = (q or "").strip().lower()
        out = []
        for d in rows:
            if status and status != "all" and d["status"] != status:
                continue
            if not status and d["status"] in ("solved", "closed"):
                continue
            if assignee == "me" and d.get("assignee") != me:
                continue
            if assignee == "none" and d.get("assignee"):
                continue
            if category and d["category"] != category:
                continue
            if q and q not in " ".join(str(d.get(k) or "") for k in ("subject", "playerName", "playerEmail", "uid", "id", "lastPreview")).lower():
                continue
            out.append(d)
        out.sort(key=lambda d: (PRIORITY_RANK.get(d.get("priority", "normal"), 2), as_utc(d["lastMessageAt"]).timestamp() * -1))
        return {"tickets": [self._staff_json(d) for d in out[:200]], "counts": counts}

    def staff_get(self, tid: str) -> dict:
        t = self._get(self.store, tid)
        notes = [d for _i, d in self.store.list(f"tickets/{tid}/notes", 200)]
        notes.sort(key=lambda d: as_utc(d["createdAt"]))

        def fn(txn: Txn):  # opening it clears the "new" dot for staff
            cur = self._get(txn, tid)
            if cur["unreadStaff"]:
                cur["unreadStaff"] = False
                txn.set(f"tickets/{tid}", cur)

        self.store.run(fn)
        return {
            "ticket": self._staff_json({**t, "unreadStaff": False}),
            "messages": self.messages(t["uid"], tid),
            "notes": [{"id": n["id"], "author": n["author"], "text": n["text"], "createdAt": self._iso(n["createdAt"])} for n in notes],
        }

    def staff_reply(self, tid: str, staff: dict, text, attachment_ids, *, solve: bool = False) -> dict:
        t0 = self._get(self.store, tid)
        text = self._text(text)
        atts = self.uploads.resolve(t0["uid"], attachment_ids)
        if not text and not atts:
            raise bad_request("empty_message", "Write a reply first.")

        def fn(txn: Txn):
            t = self._get(txn, tid)
            if t["status"] == "closed":
                raise ApiError(409, "ticket_closed", "This ticket is closed.")
            now = self.clock()
            msg = self._add_message(txn, t, "agent", staff.get("name") or "Support", text, atts, now)
            t["status"] = "solved" if solve else "pending"
            t["unreadUser"], t["unreadStaff"] = True, False
            if not t.get("assignee"):
                t["assignee"], t["assigneeName"] = staff["username"], staff.get("name")
            self._save(txn, t)
            return msg

        return self._msg_json(self.store.run(fn))

    def staff_note(self, tid: str, staff: dict, text) -> dict:
        self._get(self.store, tid)
        text = self._text(text)
        if not text:
            raise bad_request("empty_message", "Write the note first.")
        nid = uuid.uuid4().hex
        note = {"id": nid, "author": staff.get("name") or staff["username"], "text": text, "createdAt": self.clock()}
        self.store.run(lambda txn: txn.set(f"tickets/{tid}/notes/{nid}", note))
        return {"id": nid, "author": note["author"], "text": text, "createdAt": self._iso(note["createdAt"])}

    def staff_update(self, tid: str, staff: dict, *, status=None, priority=None, assignee=None, assign_set: bool = False) -> dict:
        if status is not None and status not in STATUSES:
            raise bad_request("invalid_status", "Unknown status.")
        if priority is not None and priority not in PRIORITIES:
            raise bad_request("invalid_priority", "Unknown priority.")

        def fn(txn: Txn):
            t = self._get(txn, tid)
            if status is not None and status != t["status"]:
                t["status"] = status
                t["unreadUser"] = t["unreadUser"] or status in ("solved", "closed")
            if priority is not None:
                t["priority"] = priority
            if assign_set:
                if assignee == "me":
                    t["assignee"], t["assigneeName"] = staff["username"], staff.get("name")
                elif assignee in (None, ""):
                    t["assignee"], t["assigneeName"] = None, None
                else:
                    raise bad_request("invalid_assignee", "You can only assign a ticket to yourself or no one.")
            t["updatedAt"] = self.clock()
            self._save(txn, t)
            return t

        return self._staff_json(self.store.run(fn))

    def staff_bulk(self, staff: dict, ids, op: str, value=None) -> dict:
        if not isinstance(ids, list) or not ids or len(ids) > 100 or not all(isinstance(i, str) for i in ids):
            raise bad_request("invalid_ids", "Pick between 1 and 100 tickets.")
        ops = {
            "assign_me": lambda i: self.staff_update(i, staff, assignee="me", assign_set=True),
            "unassign": lambda i: self.staff_update(i, staff, assignee=None, assign_set=True),
            "status": lambda i: self.staff_update(i, staff, status=value),
            "priority": lambda i: self.staff_update(i, staff, priority=value),
        }
        if op not in ops:
            raise bad_request("invalid_op", "Unknown bulk action.")
        results = []
        for i in dict.fromkeys(ids):
            try:
                ops[op](i)
                results.append({"id": i, "ok": True})
            except ApiError as e:
                results.append({"id": i, "ok": False, "error": e.message})
        return {"results": results, "done": sum(r["ok"] for r in results), "failed": sum(not r["ok"] for r in results)}

    # -------------------------------------------------------------------- json
    @staticmethod
    def _iso(v):
        v = as_utc(v)
        return v.isoformat() if v else None

    def _json(self, d: dict) -> dict:
        return {
            "id": d["id"], "subject": d["subject"], "category": d["category"], "categoryLabel": CATEGORIES.get(d["category"], ""),
            "status": d["status"], "createdAt": self._iso(d["createdAt"]), "updatedAt": self._iso(d["updatedAt"]),
            "lastFrom": d["lastFrom"], "lastPreview": d["lastPreview"], "unread": bool(d.get("unread", d.get("unreadUser"))),
            "messageCount": d["messageCount"],
        }

    def _staff_json(self, d: dict) -> dict:
        return {
            "id": d["id"], "uid": d["uid"], "subject": d["subject"], "category": d["category"], "categoryLabel": CATEGORIES.get(d["category"], ""),
            "status": d["status"], "priority": d.get("priority", "normal"), "assignee": d.get("assignee"), "assigneeName": d.get("assigneeName"),
            "createdAt": self._iso(d["createdAt"]), "updatedAt": self._iso(d["updatedAt"]), "lastMessageAt": self._iso(d["lastMessageAt"]),
            "lastFrom": d["lastFrom"], "lastPreview": d["lastPreview"], "unread": bool(d["unreadStaff"]), "messageCount": d["messageCount"],
            "playerName": d.get("playerName"), "playerEmail": d.get("playerEmail"),
        }

    def _msg_json(self, m: dict) -> dict:
        return {"id": m["id"], "from": m["from"], "author": m["author"], "text": m["text"], "attachments": m.get("attachments", []), "createdAt": self._iso(m["createdAt"])}
