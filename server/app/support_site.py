"""The customer service site: /support (page) and /support/api (reps only).

Reps can read and answer tickets, add private notes, assign, change status and priority,
and see the player's standing and appeals read-only. They can't ban, lift, or touch
credits, and they never see the admin dashboard.
"""
from __future__ import annotations

from pathlib import Path

from flask import Blueprint, g, jsonify, request

from .errors import ApiError, bad_request
from .staff import StaffService, html_page
from .standing import StandingService
from .store import Store
from .support import CANNED, CATEGORIES, PRIORITIES, STATUSES, SupportService
from .uploads import UploadService, file_response

UI_DIR = Path(__file__).parent / "support_ui"


def make_support_site(store: Store, support: SupportService, standing: StandingService, uploads: UploadService, staff: StaffService) -> Blueprint:
    bp = Blueprint("support_site", __name__)
    rep = staff.require("agent")

    def body() -> dict:
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            raise bad_request("invalid_body", "Send a JSON object.")
        return data

    @bp.get("/support")
    def page():
        return html_page(UI_DIR / "index.html")

    @bp.get("/support/api/meta")
    @rep
    def meta():
        return jsonify(
            {
                "me": {"username": g.staff["username"], "name": g.staff.get("name", ""), "mustChangePassword": bool(g.staff.get("mustChange"))},
                "categories": CATEGORIES,
                "statuses": list(STATUSES),
                "priorities": list(PRIORITIES),
                "canned": CANNED,
                "maxFiles": uploads.cfg.upload_max_files,
                "maxMb": uploads.cfg.upload_max_mb,
            }
        )

    @bp.get("/support/api/tickets")
    @rep
    def tickets():
        a = request.args
        return jsonify(
            support.staff_list(status=a.get("status") or None, assignee=a.get("assignee") or None, q=a.get("q"), category=a.get("category") or None, me=g.staff["username"])
        )

    @bp.get("/support/api/tickets/<tid>")
    @rep
    def ticket(tid: str):
        out = support.staff_get(tid)
        uid = out["ticket"]["uid"]
        user = store.read(f"users/{uid}") or {}
        pub = standing.public(standing.summary(uid))
        out["player"] = {
            "uid": uid,
            "displayName": user.get("displayName"),
            "email": user.get("email"),
            "isAnonymous": bool(user.get("isAnonymous")),
            "state": pub["state"],
            "blocksPlay": pub["blocksPlay"],
            "probationUntil": pub["probationUntil"],
            "active": [{"type": e["type"], "reason": e["reason"], "expiresAt": e["expiresAt"], "appealStatus": e["appealStatus"]} for e in pub["active"]],
            "appeals": [
                {"id": ap["id"], "actionType": ap["actionType"], "status": ap["status"], "message": ap["message"], "attachments": ap["attachments"], "createdAt": ap["createdAt"]}
                for ap in (standing.appeal_json(x) for x in standing.appeals(uid)[:5])
            ],
        }
        return jsonify(out)

    @bp.post("/support/api/tickets/<tid>/reply")
    @rep
    def reply(tid: str):
        d = body()
        return jsonify(support.staff_reply(tid, g.staff, d.get("text"), d.get("attachments"), solve=bool(d.get("solve")))), 201

    @bp.post("/support/api/tickets/<tid>/note")
    @rep
    def note(tid: str):
        return jsonify(support.staff_note(tid, g.staff, body().get("text"))), 201

    @bp.post("/support/api/tickets/<tid>/update")
    @rep
    def update(tid: str):
        d = body()
        return jsonify(
            support.staff_update(tid, g.staff, status=d.get("status"), priority=d.get("priority"), assignee=d.get("assignee"), assign_set="assignee" in d)
        )

    @bp.post("/support/api/bulk")
    @rep
    def bulk():
        d = body()
        return jsonify(support.staff_bulk(g.staff, d.get("ids"), d.get("op"), d.get("value")))

    @bp.post("/support/api/tickets/<tid>/uploads")
    @rep
    def upload(tid: str):
        t = support._get(store, tid)
        f = request.files.get("file")
        if f is None:
            raise bad_request("no_file", "Attach a file.")
        return jsonify(uploads.save(t["uid"], f.filename or "file", f.read())), 201

    @bp.get("/support/api/files/<uid>/<fid>")
    @rep
    def files(uid: str, fid: str):
        meta, data = uploads.read(uid, fid)
        return file_response(meta, data, download=request.args.get("download") == "1")

    return bp
