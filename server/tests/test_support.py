"""Attachments, appeals with files, tickets from the player and the rep side."""
import io

from .conftest import MP4, PDF, PNG, auth, staff_headers, staff_login
from .test_standing import users  # noqa: F401
from .test_staff import REP_PASS, make_rep


def up(c, data, name="proof.png", user="alice", path="/v1/uploads"):
    return c.post(path, data={"file": (io.BytesIO(data), name)}, headers=auth(user), content_type="multipart/form-data")


def rep_headers(c):
    make_rep(c, staff_headers(c))
    return {"Authorization": "Bearer " + staff_login(c, "amaka.cs", REP_PASS).get_json()["token"]}


# ---- uploads ------------------------------------------------------------------

def test_upload_accepts_real_photos_videos_pdfs(make_client):
    c = make_client()
    for data, name, mime, kind in ((PNG, "a.png", "image/png", "image"), (MP4, "clip.mov", "video/mp4", "video"), (PDF, "r.pdf", "application/pdf", "pdf")):
        r = up(c, data, name)
        j = r.get_json()
        assert r.status_code == 201 and j["mime"] == mime and j["kind"] == kind and "key" not in j
    assert up(c, PNG, "../../etc/passwd.png").get_json()["name"] == "passwd.png"


def test_upload_trusts_bytes_not_names(make_client):
    c = make_client()
    r = up(c, b"<html><script>alert(1)</script></html>", "evil.png")
    assert r.status_code == 400 and r.get_json()["error"] == "file_type_not_allowed"
    assert up(c, b"MZ\x90\x00" + b"\x00" * 50, "setup.pdf").status_code == 400
    assert up(c, b"", "empty.png").status_code == 400
    assert up(c, PNG, "x.exe").get_json()["name"].endswith(".png")  # the name always matches the real type
    assert c.post("/v1/uploads", headers=auth()).status_code == 400
    assert c.post("/v1/uploads", data={"file": (io.BytesIO(PNG), "a.png")}, content_type="multipart/form-data").status_code == 401


def test_upload_size_and_daily_limits(make_client, cfg):
    c = make_client()
    assert up(c, PNG + b"\x00" * (26 * 1024 * 1024)).status_code == 413
    for _ in range(cfg.upload_daily_limit):
        assert up(c, PNG).status_code == 201
    assert up(c, PNG).status_code == 429


def test_players_only_read_their_own_files(make_client):
    c = make_client()
    fid = up(c, PNG).get_json()["id"]
    r = c.get(f"/v1/uploads/{fid}", headers=auth())
    assert r.status_code == 200 and r.data == PNG and r.headers["X-Content-Type-Options"] == "nosniff" and "sandbox" in r.headers["Content-Security-Policy"]
    assert c.get(f"/v1/uploads/{fid}", headers=auth("bob")).status_code == 404
    assert c.get("/v1/uploads/not-a-real-id", headers=auth()).status_code == 404


# ---- appeals with attachments ---------------------------------------------------

def test_appeal_with_attachments_visible_to_admin_only(make_client, standing):
    c = make_client()
    a = standing.apply("alice", "ban", "Fraud", actor="t")
    f1, f2 = up(c, PNG).get_json()["id"], up(c, PDF, "receipt.pdf").get_json()["id"]
    msg = "I did not do this, here is my receipt and a screenshot."
    r = c.post("/v1/account/appeal", json={"actionId": a["id"], "message": msg, "attachments": [f1, f2]}, headers=auth())
    assert r.status_code == 201
    h = staff_headers(c)
    ap = c.get("/admin/api/users/alice", headers=h).get_json()["appeals"][0]
    assert [x["name"] for x in ap["attachments"]] == ["proof.png", "receipt.pdf"]
    got = c.get(f"/admin/api/files/alice/{f1}", headers=h)
    assert got.status_code == 200 and got.data == PNG
    assert c.get(f"/admin/api/files/alice/{f1}").status_code == 401
    assert c.get(f"/admin/api/files/alice/{f2}", headers=h).headers["Content-Disposition"].startswith("attachment")


def test_appeal_attachment_rules(make_client, standing):
    c = make_client()
    a = standing.apply("alice", "ban", "Fraud", actor="t")
    msg = "I did not do this, please look again at the details."
    bobs = up(c, PNG, user="bob").get_json()["id"]
    body = lambda ids: {"actionId": a["id"], "message": msg, "attachments": ids}
    assert c.post("/v1/account/appeal", json=body([bobs]), headers=auth()).status_code == 400  # someone else's file
    assert c.post("/v1/account/appeal", json=body(["x" * 32]), headers=auth()).status_code == 400
    mine = up(c, PNG).get_json()["id"]
    assert c.post("/v1/account/appeal", json=body([mine, mine]), headers=auth()).status_code == 400
    ids = [up(c, PNG).get_json()["id"] for _ in range(6)]
    assert c.post("/v1/account/appeal", json=body(ids), headers=auth()).get_json()["error"] == "too_many_files"
    assert c.post("/v1/account/appeal", json=body("nope"), headers=auth()).status_code == 400
    assert c.post("/v1/account/appeal", json=body([]), headers=auth()).status_code == 201  # files are optional


def test_restricted_players_can_still_upload_and_contact_support(make_client, standing):
    c = make_client()
    standing.apply("alice", "ban", "Fraud", actor="t")
    assert up(c, PNG).status_code == 201
    r = c.post("/v1/support/tickets", json={"subject": "My ban", "category": "restriction", "message": "Please explain what happened."}, headers=auth())
    assert r.status_code == 201


# ---- tickets: player side -------------------------------------------------------

def new_ticket(c, user="alice", **over):
    body = {"subject": "Balance looks wrong", "category": "credits", "message": "My balance dropped after a round."}
    body.update(over)
    return c.post("/v1/support/tickets", json=body, headers=auth(user))


def test_create_list_read_reply_close(make_client, store):
    c = make_client()
    t = new_ticket(c).get_json()
    assert t["status"] == "open" and t["messageCount"] == 1 and t["lastFrom"] == "user"
    assert [x["id"] for x in c.get("/v1/support/tickets", headers=auth()).get_json()["tickets"]] == [t["id"]]
    assert c.get("/v1/support/tickets", headers=auth("bob")).get_json()["tickets"] == []
    full = c.get(f"/v1/support/tickets/{t['id']}", headers=auth()).get_json()
    assert [m["from"] for m in full["messages"]] == ["user"] and full["messages"][0]["text"].startswith("My balance")
    assert c.get(f"/v1/support/tickets/{t['id']}", headers=auth("bob")).status_code == 404
    assert c.post(f"/v1/support/tickets/{t['id']}/messages", json={"message": "More info"}, headers=auth("bob")).status_code == 404
    fid = up(c, PNG).get_json()["id"]
    m = c.post(f"/v1/support/tickets/{t['id']}/messages", json={"message": "Screenshot attached", "attachments": [fid]}, headers=auth())
    assert m.status_code == 201 and m.get_json()["attachments"][0]["id"] == fid
    closed = c.post(f"/v1/support/tickets/{t['id']}/close", headers=auth()).get_json()
    assert closed["status"] == "closed"
    assert c.post(f"/v1/support/tickets/{t['id']}/messages", json={"message": "hello?"}, headers=auth()).status_code == 409
    # what the app listens to in Firestore is the mirror, and it carries nothing internal
    mirror = store.docs[f"users/alice/tickets/{t['id']}"]
    assert set(mirror) == {"id", "subject", "category", "status", "createdAt", "updatedAt", "lastFrom", "lastPreview", "unread", "messageCount"}


def test_ticket_validation_and_limits(make_client, cfg):
    c = make_client()
    assert new_ticket(c, subject="x").status_code == 400
    assert new_ticket(c, category="nope").status_code == 400
    assert new_ticket(c, message="").status_code == 400
    assert new_ticket(c, message="y" * 2001).status_code == 400
    assert new_ticket(c, message="", attachments=["a" * 32]).status_code == 400
    for _ in range(cfg.max_open_tickets):
        assert new_ticket(c).status_code == 201
    assert new_ticket(c).get_json()["error"] == "too_many_tickets"
    assert new_ticket(c, user="bob").status_code == 201  # limits are per player
    assert c.get("/v1/support/categories").status_code == 200


# ---- tickets: rep side ----------------------------------------------------------

def test_rep_workflow(make_client, standing):
    c = make_client()
    r = rep_headers(c)
    t = new_ticket(c).get_json()
    q = c.get("/support/api/tickets", headers=r).get_json()
    assert [x["id"] for x in q["tickets"]] == [t["id"]] and q["tickets"][0]["unread"] and q["counts"]["open"] == 1

    detail = c.get(f"/support/api/tickets/{t['id']}", headers=r).get_json()
    assert detail["player"]["uid"] == "alice" and detail["player"]["state"] == "good" and detail["messages"][0]["from"] == "user"
    assert c.get("/support/api/tickets", headers=r).get_json()["tickets"][0]["unread"] is False  # opening it clears the dot

    rep = c.post(f"/support/api/tickets/{t['id']}/reply", json={"text": "Looking into it now."}, headers=r)
    assert rep.status_code == 201 and rep.get_json()["author"] == "Amaka"
    mine = c.get("/v1/support/tickets", headers=auth()).get_json()["tickets"][0]
    assert mine["status"] == "pending" and mine["unread"] is True and mine["lastFrom"] == "agent"
    assert c.get("/support/api/tickets?assignee=me", headers=r).get_json()["tickets"][0]["assignee"] == "amaka.cs"  # replying claims it

    c.post(f"/v1/support/tickets/{t['id']}/read", headers=auth())
    assert c.get("/v1/support/tickets", headers=auth()).get_json()["tickets"][0]["unread"] is False

    c.post(f"/v1/support/tickets/{t['id']}/messages", json={"message": "Thanks, any update?"}, headers=auth())
    assert c.get("/support/api/tickets", headers=r).get_json()["tickets"][0]["status"] == "open"  # a player reply reopens it

    c.post(f"/support/api/tickets/{t['id']}/reply", json={"text": "Fixed. Marking solved.", "solve": True}, headers=r)
    assert c.get("/v1/support/tickets", headers=auth()).get_json()["tickets"][0]["status"] == "solved"
    assert c.get("/support/api/tickets", headers=r).get_json()["tickets"] == []  # solved leaves the default queue
    assert len(c.get("/support/api/tickets?status=solved", headers=r).get_json()["tickets"]) == 1


def test_internal_notes_never_reach_the_player(make_client, store):
    c = make_client()
    r = rep_headers(c)
    t = new_ticket(c).get_json()
    assert c.post(f"/support/api/tickets/{t['id']}/note", json={"text": "Looks like a duplicate of #12, be careful."}, headers=r).status_code == 201
    d = c.get(f"/support/api/tickets/{t['id']}", headers=r).get_json()
    assert d["notes"][0]["text"].startswith("Looks like") and d["notes"][0]["author"] == "Amaka"
    mine = str(c.get(f"/v1/support/tickets/{t['id']}", headers=auth()).get_json()) + str([v for k, v in store.docs.items() if k.startswith("users/alice/")])
    assert "duplicate of #12" not in mine and "amaka.cs" not in mine


def test_rep_update_bulk_and_search(make_client):
    c = make_client()
    r = rep_headers(c)
    ids = [new_ticket(c, subject=f"Problem {i}").get_json()["id"] for i in range(3)]
    new_ticket(c, user="bob", subject="Something about roulette")
    assert c.post(f"/support/api/tickets/{ids[0]}/update", json={"priority": "urgent", "status": "pending", "assignee": "me"}, headers=r).get_json()["priority"] == "urgent"
    assert c.get("/support/api/tickets", headers=r).get_json()["tickets"][0]["id"] == ids[0]  # urgent floats to the top
    assert c.post(f"/support/api/tickets/{ids[0]}/update", json={"priority": "mega"}, headers=r).status_code == 400
    assert c.post(f"/support/api/tickets/{ids[0]}/update", json={"assignee": "someone.else"}, headers=r).status_code == 400
    assert [t["subject"] for t in c.get("/support/api/tickets?q=roulette", headers=r).get_json()["tickets"]] == ["Something about roulette"]
    assert len(c.get("/support/api/tickets?assignee=none", headers=r).get_json()["tickets"]) == 3
    out = c.post("/support/api/bulk", json={"ids": ids + ["ghost"], "op": "status", "value": "solved"}, headers=r).get_json()
    assert out["done"] == 3 and out["failed"] == 1
    assert c.post("/support/api/bulk", json={"ids": ids, "op": "assign_me"}, headers=r).get_json()["done"] == 3
    assert c.post("/support/api/bulk", json={"ids": [], "op": "assign_me"}, headers=r).status_code == 400
    assert c.post("/support/api/bulk", json={"ids": ids, "op": "delete_all"}, headers=r).status_code == 400


def test_rep_sees_standing_and_appeal_files_read_only(make_client, standing):
    c = make_client()
    r = rep_headers(c)
    a = standing.apply("alice", "suspension", "Conduct", actor="t", duration_hours=24)
    fid = up(c, PNG).get_json()["id"]
    c.post("/v1/account/appeal", json={"actionId": a["id"], "message": "Please review, I was not even online then.", "attachments": [fid]}, headers=auth())
    t = new_ticket(c, category="restriction").get_json()
    p = c.get(f"/support/api/tickets/{t['id']}", headers=r).get_json()["player"]
    assert p["state"] == "suspended" and p["active"][0]["type"] == "suspension" and p["appeals"][0]["attachments"][0]["id"] == fid
    assert "internalNote" not in str(p)
    assert c.get(f"/support/api/files/alice/{fid}", headers=r).data == PNG
    assert c.post("/admin/api/users/alice/actions", json={"type": "ban", "reasonCode": "tos"}, headers=r).status_code in (401, 403)


def test_rep_can_attach_files_to_a_reply(make_client):
    c = make_client()
    r = rep_headers(c)
    t = new_ticket(c).get_json()
    f = c.post(f"/support/api/tickets/{t['id']}/uploads", data={"file": (io.BytesIO(PDF), "guide.pdf")}, headers=r, content_type="multipart/form-data")
    assert f.status_code == 201
    m = c.post(f"/support/api/tickets/{t['id']}/reply", json={"text": "", "attachments": [f.get_json()["id"]]}, headers=r)
    assert m.status_code == 201
    got = c.get(f"/v1/uploads/{f.get_json()['id']}", headers=auth())
    assert got.status_code == 200 and got.data == PDF  # the player opens it from their own space


def test_deleting_an_account_removes_tickets_and_files(make_client, store, blobs, deleted_auth):
    c = make_client()
    fid = up(c, PNG).get_json()["id"]
    t = new_ticket(c, attachments=[fid]).get_json()
    c.post(f"/support/api/tickets/{t['id']}/note", json={"text": "internal"}, headers=rep_headers(c))
    new_ticket(c, user="bob")
    assert c.delete("/v1/account", headers=auth()).status_code == 200
    assert not [k for k in store.docs if "alice" in k or t["id"] in k]
    assert not [k for k in blobs.data if "alice" in k]
    assert [k for k in store.docs if k.startswith("tickets/")]  # bob's ticket is untouched
