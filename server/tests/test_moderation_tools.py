"""Reason lists ("other" is the only free text) and bulk actions."""
from .conftest import FixedRng, auth, staff_headers
from .test_standing import play, users  # noqa: F401  (users fixture seeds alice and bob)


def post(c, h, uid, **body):
    return c.post(f"/admin/api/users/{uid}/actions", json=body, headers=h)


def test_catalog_is_served(make_client):
    c = make_client()
    cat = c.get("/admin/api/ping", headers=staff_headers(c)).get_json()["reasons"]
    assert {r["code"] for r in cat["apply"]["ban"]} >= {"fraud", "other"}
    assert [r["code"] for r in cat["apply"]["ban"] if r["custom"]] == ["other"]


def test_listed_reason_fills_in_the_wording_and_blocks_typing(make_client):
    c = make_client()
    h = staff_headers(c)
    r = post(c, h, "alice", type="ban", reasonCode="fraud")
    j = r.get_json()
    assert r.status_code == 201 and j["reason"] == "Fraud or payment abuse" and "fraud" in j["publicNote"].lower()
    s = c.get("/v1/account/standing", headers=auth()).get_json()["active"][0]
    assert s["reason"] == "Fraud or payment abuse" and s["publicNote"] == j["publicNote"]
    r = post(c, h, "bob", type="ban", reasonCode="fraud", customReason="made up words")
    assert r.get_json()["error"] == "custom_text_not_allowed"
    r = post(c, h, "bob", type="ban", reasonCode="fraud", publicNote="made up words")
    assert r.get_json()["error"] == "custom_text_not_allowed"


def test_other_requires_and_uses_typed_text(make_client):
    c = make_client()
    h = staff_headers(c)
    assert post(c, h, "alice", type="ban", reasonCode="other").get_json()["error"] == "custom_text_required"
    assert post(c, h, "alice", type="ban", reasonCode="other", customReason="short").status_code == 400
    r = post(c, h, "alice", type="ban", reasonCode="other", customReason="Sold the account on a forum", publicNote="We found the listing.")
    j = r.get_json()
    assert r.status_code == 201 and j["reason"] == "Sold the account on a forum" and j["publicNote"] == "We found the listing."


def test_unknown_and_missing_codes_and_old_free_text_field_are_refused(make_client):
    c = make_client()
    h = staff_headers(c)
    assert post(c, h, "alice", type="ban", reasonCode="nope").status_code == 400
    assert post(c, h, "alice", type="ban").status_code == 400
    assert post(c, h, "alice", type="ban", reason="free text").status_code == 400  # the old field does nothing now
    assert post(c, h, "alice", type="suspension", reasonCode="fraud", durationHours=5).status_code == 400  # not on that type's list
    assert c.get("/v1/account/standing", headers=auth()).get_json()["state"] == "good"


def test_lift_and_appeal_decisions_use_lists_too(make_client, standing):
    c = make_client()
    h = staff_headers(c)
    a = post(c, h, "alice", type="suspension", reasonCode="conduct", durationHours=24).get_json()
    standing.appeal("alice", a["id"], "I think this was a mistake because I was away.")
    ap = c.get("/admin/api/users/alice", headers=h).get_json()["appeals"][0]
    path = f"/admin/api/users/alice/appeals/{ap['id']}/decide"
    assert c.post(path, json={"decision": "reject"}, headers=h).status_code == 400
    assert c.post(path, json={"decision": "reject", "reasonCode": "evidence_ok"}, headers=h).status_code == 400  # an approve reason
    assert c.post(path, json={"decision": "reject", "reasonCode": "other", "customReason": "x"}, headers=h).status_code == 400
    r = c.post(path, json={"decision": "reject", "reasonCode": "insufficient"}, headers=h).get_json()
    assert r["status"] == "rejected" and "does not change our decision" in r["response"]
    assert c.post(f"/admin/api/users/alice/actions/{a['id']}/lift", json={"note": "free text"}, headers=h).status_code == 400
    assert c.post(f"/admin/api/users/alice/actions/{a['id']}/lift", json={"reasonCode": "error", "probationHours": 0}, headers=h).status_code == 200
    assert play(c).status_code == 200


def test_bulk_apply_reports_each_player(make_client):
    c = make_client()
    h = staff_headers(c)
    r = c.post("/admin/api/bulk", json={"op": "apply", "players": ["alice", "bob@x.com", "ghost", "alice"], "type": "suspension", "reasonCode": "bonus_abuse", "durationHours": 12}, headers=h)
    j = r.get_json()
    assert r.status_code == 200 and j["done"] == 2 and j["failed"] == 1  # alice once (duplicates dropped), bob by email, ghost fails
    assert [x["ok"] for x in j["results"]] == [True, True, False]
    assert c.get("/v1/account/standing", headers=auth("bob")).get_json()["state"] == "suspended"
    again = c.post("/admin/api/bulk", json={"op": "apply", "players": ["alice"], "type": "suspension", "reasonCode": "bonus_abuse", "durationHours": 12}, headers=h).get_json()
    assert again["failed"] == 1 and "already" in again["results"][0]["error"]


def test_bulk_lift_and_validation(make_client):
    c = make_client()
    h = staff_headers(c)
    c.post("/admin/api/bulk", json={"op": "apply", "players": ["alice", "bob"], "type": "ban", "reasonCode": "tos"}, headers=h)
    r = c.post("/admin/api/bulk", json={"op": "lift", "players": ["alice", "bob"], "type": "ban", "reasonCode": "error", "probationHours": 0}, headers=h).get_json()
    assert r["done"] == 2 and play(c).status_code == 200
    r = c.post("/admin/api/bulk", json={"op": "lift", "players": ["alice"], "reasonCode": "error"}, headers=h).get_json()
    assert r["failed"] == 1 and r["results"][0]["error"] == "Nothing active to lift."
    assert c.post("/admin/api/bulk", json={"op": "apply", "players": [], "type": "ban", "reasonCode": "tos"}, headers=h).status_code == 400
    assert c.post("/admin/api/bulk", json={"op": "apply", "players": [f"u{i}" for i in range(201)], "type": "ban", "reasonCode": "tos"}, headers=h).status_code == 400
    assert c.post("/admin/api/bulk", json={"op": "apply", "players": ["alice"], "type": "ban", "reasonCode": "bogus"}, headers=h).status_code == 400
    assert c.post("/admin/api/bulk", json={"op": "nuke", "players": ["alice"]}, headers=h).status_code == 400
    assert c.post("/admin/api/bulk", json={"op": "apply", "players": ["alice"]}).status_code == 401
