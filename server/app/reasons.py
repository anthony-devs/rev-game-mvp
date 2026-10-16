"""Canned reasons for moderation. Staff pick one; free text is only allowed with "other".

Each entry is (code, label, message). ``label`` is the short reason the player sees,
``message`` is the sentence that explains it. Both are written here so every player
hears the same wording for the same thing.
"""
from __future__ import annotations

from .errors import bad_request

OTHER = "other"
MIN_CUSTOM, MAX_CUSTOM = 10, 300

_COMMON = [
    ("tos", "Terms of service violation", "Activity on this account broke our terms of service."),
    ("multi_account", "Multiple or linked accounts", "We found other accounts linked to this one. Each person may only have one."),
]

APPLY: dict[str, list[tuple[str, str, str]]] = {
    "ban": [
        ("exploit", "Exploiting a bug or cheating", "This account used a bug or an outside tool to get an unfair result."),
        ("fraud", "Fraud or payment abuse", "We found fraud or payment abuse on this account."),
        ("harassment", "Abuse or harassment", "This account was abusive towards our staff or other players."),
        ("underage", "Age requirement not met", "We could not confirm this account meets the minimum age."),
        *_COMMON,
        (OTHER, "Other", ""),
    ],
    "suspension": [
        ("suspicious_activity", "Suspicious activity", "We saw unusual activity on this account and paused it while we look into it."),
        ("bonus_abuse", "Bonus or credit abuse", "This account collected free credits in a way that breaks the rules."),
        ("chargeback", "Payment dispute", "A payment tied to this account is being disputed."),
        ("conduct", "Conduct warning", "This is a short break after a conduct warning."),
        *_COMMON,
        (OTHER, "Other", ""),
    ],
    "payout_restriction": [
        ("verify_identity", "Identity check needed", "We need to verify who owns this account before credits can move."),
        ("unusual_winnings", "Unusual winnings under review", "A run of results on this account is being reviewed."),
        ("bonus_abuse", "Bonus or credit abuse", "This account collected free credits in a way that breaks the rules."),
        ("chargeback", "Payment dispute", "A payment tied to this account is being disputed."),
        (OTHER, "Other", ""),
    ],
    "investigation": [
        ("fair_play", "Fair play review", "We are reviewing this account's rounds for fair play."),
        ("fraud_check", "Fraud check", "We are checking this account for fraud."),
        ("report", "Player report", "Another player or staff member raised a concern about this account."),
        ("security", "Possible account takeover", "We saw signs someone else may be using this account."),
        (OTHER, "Other", ""),
    ],
}

LIFT = [
    ("appeal_ok", "Appeal approved", "Lifted after reviewing the player's appeal."),
    ("error", "Issued in error", "This action should not have been applied."),
    ("cleared", "Review cleared the account", "The review found nothing wrong."),
    ("served", "Time served", "The player has served enough of the penalty."),
    ("verified", "Identity verified", "The player passed the identity check."),
    (OTHER, "Other", ""),
]

APPEAL_APPROVE = [
    ("evidence_ok", "Evidence accepted", "Thanks for the details. We reviewed them and lifted the restriction."),
    ("mistake", "Our mistake", "We made a mistake and have lifted the restriction. Sorry about that."),
    ("verified", "Identity confirmed", "Thanks for confirming who you are. The restriction is lifted."),
    (OTHER, "Other", ""),
]

APPEAL_REJECT = [
    ("insufficient", "Not enough evidence", "We reviewed your appeal but it does not change our decision."),
    ("confirmed", "Violation confirmed", "Our review confirmed the violation, so the action stays."),
    ("repeat", "Repeat violation", "This is not the first time, so we are keeping the action in place."),
    ("unrelated", "Appeal does not address the reason", "Your message did not address the reason for the action. You can send a new appeal with more detail."),
    (OTHER, "Other", ""),
]

CATALOG = {
    "apply": APPLY,
    "lift": LIFT,
    "appeal_approve": APPEAL_APPROVE,
    "appeal_reject": APPEAL_REJECT,
}


def public_catalog() -> dict:
    def rows(items):
        return [{"code": c, "label": l, "custom": c == OTHER} for c, l, _m in items]

    return {
        "apply": {t: rows(v) for t, v in APPLY.items()},
        "lift": rows(LIFT),
        "appealApprove": rows(APPEAL_APPROVE),
        "appealReject": rows(APPEAL_REJECT),
        "other": OTHER,
        "customMin": MIN_CUSTOM,
        "customMax": MAX_CUSTOM,
    }


def resolve(items, code, custom: str | None = None, *, field: str = "reason") -> tuple[str, str, bool]:
    """Turn a picked code (and the typed text, only for "other") into (label, message, is_custom).

    Raises 400 when the code is unknown, when text is typed for a listed reason,
    or when "other" has no text.
    """
    table = {c: (l, m) for c, l, m in items}
    if not isinstance(code, str) or code not in table:
        raise bad_request("invalid_reason_code", f"Pick a {field} from the list.")
    custom = (custom or "").strip()
    label, message = table[code]
    if code != OTHER:
        if custom:
            raise bad_request("custom_text_not_allowed", 'Typing your own text is only allowed when you pick "Other".')
        return label, message, False
    if not (MIN_CUSTOM <= len(custom) <= MAX_CUSTOM):
        raise bad_request("custom_text_required", f"Describe it in {MIN_CUSTOM} to {MAX_CUSTOM} characters.")
    return custom, custom, True
