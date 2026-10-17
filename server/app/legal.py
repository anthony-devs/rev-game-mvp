"""Terms, Privacy, Refunds and Cookies, plus who runs the service.

Served as JSON for the app (``/v1/legal``) and as plain web pages (``/legal``) so the same text can be
linked from the app stores and from emails. Numbers (rounds, prices) come from the live settings so the
text never disagrees with the product. Business details come from environment variables; a line with no
value is left out rather than shown blank.

Have a lawyer in your licensing country review all of this before launch.
"""
from __future__ import annotations

import hashlib
import hmac
from html import escape

VERSION = "2026-10"
UPDATED = "October 2026"

TITLES = {
    "terms": "Terms of Service",
    "privacy": "Privacy Policy",
    "refunds": "Refund Policy",
    "cookies": "Cookie Policy",
    "about": "Who we are",
}
SUMMARY = {
    "terms": "The rules for using REV GAMES.",
    "privacy": "What we collect, why, and your choices.",
    "refunds": "When money is returned, and when it is not.",
    "cookies": "What our website stores, and what the app does not.",
    "about": "The company behind REV GAMES and how to reach us.",
}


def _vals(cfg) -> dict:
    hours = cfg.rounds_window_hours
    contact = cfg.business_email or "the support page in the app"
    return {
        "name": cfg.business_name or "REV GAMES",
        "contact": contact,
        "free": cfg.rounds_free_live,
        "hours": int(hours) if float(hours).is_integer() else hours,
        "price": f"{cfg.live_currency} {cfg.round_price_live:g}",
        "law": cfg.governing_law or "the laws of Nigeria",
    }


def _terms(v):
    return [
        ("Agreeing to these terms", "By creating an account or using {name} you agree to these terms and to our Privacy Policy and Refund Policy. If you do not agree, do not use the service."),
        ("Who can use it", "You must be at least 18, or the legal gambling age where you live if that is higher, and you must be allowed to gamble where you are. You may hold one account and the details you give must be true and your own. We may ask you to prove your age and identity."),
        ("Demo and live play", "Demo play uses virtual credits that have no cash value and cannot be withdrawn. Live play uses your own money, is kept in a separate balance, and needs you to accept the Live Money Agreement first. Live results are real wins and real losses."),
        ("Rounds", "Playing uses rounds, shared by all games. Every account gets {free} free rounds, which come back {hours} hours after the first round of each period. Extra rounds cost {price} each and are sold in packs. The price of a round is a fee to play and is not a bet. The current numbers are always shown in the app before you buy."),
        ("Fair results", "Results are decided by our server using random numbers and are sealed before you play. You can check any round in your history. Odds and payout tables are shown in each game."),
        ("Your account", "Keep your sign-in details private. You are responsible for what happens on your account. Tell us at once if you think someone else has used it."),
        ("What you must not do", "Do not use bots, scripts or exploits, hold several accounts, play on behalf of someone else, pay from accounts that are not yours, launder money, or try to harm or reverse-engineer the service. Do not abuse support or other players."),
        ("Our right to act", "If we find a breach, a mistake, a fault or suspicious activity we may void affected rounds, correct balances, hold or refuse payments, limit, suspend or close an account. Where we can, we tell you why and how to appeal in the app."),
        ("Responsible play", "You can set deposit, loss and time limits, take a break or close your account at any time. Gambling can be harmful. If it stops being fun, stop and talk to someone you trust or a local problem-gambling service."),
        ("Money", "Deposits, withdrawals and fees are explained in the Live Money Agreement and the Refund Policy. Payment providers may charge their own fees. We may delay or refuse a withdrawal while we complete checks."),
        ("Our responsibility", "The service is provided as it is. We work to keep it available and accurate, but we cannot promise it will never be interrupted or have errors. As far as the law allows, we are not liable for indirect losses or for losses caused by things outside our control. Nothing in these terms limits rights you have by law."),
        ("Changes", "We may update these terms. When a change matters we tell you in the app and ask you to accept it again before you continue."),
        ("Law and disputes", "These terms follow {law}. Please contact us first at {contact} so we can try to put things right."),
    ]


def _privacy(v):
    return [
        ("Who is responsible", "{name} is responsible for your information. You can reach us at {contact}."),
        ("What we collect", "Account details you sign up with (name, email or phone number, sign-in method). Your balance, rounds, wins and losses, limits and settings. Payment details needed to deposit and withdraw, such as bank or wallet details, held by our payment providers and referenced by us. Messages and files you send to support. Basic technical details of the requests your phone makes to our servers, such as time and error information, used to keep the service running and safe."),
        ("What we do not do", "We do not sell your information. The app contains no advertising and no advertising or behaviour-tracking tools."),
        ("Why we use it", "To run your account and the games, to process payments, to check fairness, to prevent fraud and abuse, to keep to the law (including age and anti-money-laundering checks), to answer support and to keep the service working."),
        ("Who we share it with", "Services that run the product for us: Google Firebase (sign-in and database), and the payment providers you choose to deposit or withdraw with. We share with authorities or regulators when the law requires it. We only share what each of them needs."),
        ("How long we keep it", "For as long as you have an account. When you delete your account we delete your profile, balance, rounds, settings, support messages and files. We may keep records of payments and of any investigation for as long as the law requires."),
        ("Your choices and rights", "You can see your information in the app, change your settings and limits, opt out of our emails, and delete your account in your profile (this needs your live balance and payouts to be settled first). You may also ask us for a copy of your information, to correct it, or to object to how we use it. Write to {contact}. You may complain to your data protection authority, for example the Nigeria Data Protection Commission."),
        ("Children", "The service is for people 18 and over. We do not knowingly collect information from anyone younger. If we learn we have, we close the account and delete the information."),
        ("Security", "Information is sent over encrypted connections and stored with access controls. No system is perfectly secure, so keep your sign-in details private."),
        ("Changes", "If we change this policy in an important way we tell you in the app."),
    ]


def _refunds(v):
    return [
        ("Demo credits", "Demo credits are free, have no cash value and are never refunded or paid out."),
        ("Deposits", "A deposit is added to your live balance once the payment provider confirms it. If a payment is taken but not credited, contact us with the payment reference and we will find it and credit it or return it. A payment from an account that is not yours may be returned to its source."),
        ("Extra rounds", "Extra rounds are a fee to play, shown with their price before you buy. Once bought they are used up by playing and are not refundable. If a purchase was charged twice or the rounds did not arrive, tell us and we will correct it."),
        ("Bets and results", "Bets that have been played are final. A win or loss is not refunded. If a game fault affected a round, we correct your balance."),
        ("Withdrawals", "Funds are held from the moment you ask. If a withdrawal cannot be paid, or you cancel it while it is still being reviewed, the amount goes back to your live balance. We cannot reverse a payment sent to the details you gave us."),
        ("Closing your account", "Before an account can be deleted, any live balance must be withdrawn or settled."),
        ("How to ask", "Open Support in the app and tell us what happened, or write to {contact}. We aim to answer within a few days."),
    ]


def _cookies(v):
    return [
        ("The app", "The REV GAMES app does not use cookies and has no advertising or tracking tools."),
        ("Our website", "Our support and legal pages use only what they need to work, such as keeping you signed in on the support page. We do not use advertising, analytics or tracking cookies, so there is nothing to switch off."),
        ("Questions", "Write to {contact}."),
    ]


def _about(cfg, v):
    rows = [
        ("Business name", cfg.business_name),
        ("Registered address", cfg.business_address),
        ("Registration number", cfg.business_reg_no),
        ("Gambling licence", cfg.licence_no),
        ("Regulator", cfg.regulator),
        ("Email", cfg.business_email),
        ("Phone", cfg.business_phone),
    ]
    lines = [f"{k}: {val}" for k, val in rows if val]
    body = "\\n".join(lines) if lines else "REV GAMES. Contact us from Support in the app."
    return [("Company details", body.replace("\\n", "\n")), ("Support", "Open Support in the app any time. You can attach screenshots and follow your tickets there.")]


BUILDERS = {"terms": _terms, "privacy": _privacy, "refunds": _refunds, "cookies": _cookies}


def listing() -> list[dict]:
    return [{"slug": s, "title": TITLES[s], "summary": SUMMARY[s]} for s in TITLES]


def document(slug: str, cfg) -> dict | None:
    if slug not in TITLES:
        return None
    v = _vals(cfg)
    raw = _about(cfg, v) if slug == "about" else BUILDERS[slug](v)
    sections = [{"title": t, "body": b.format(**v) if "{" in b else b} for t, b in raw]
    return {"slug": slug, "title": TITLES[slug], "version": VERSION, "updated": UPDATED, "sections": sections}


def page(slug: str, cfg) -> str | None:
    d = document(slug, cfg)
    if d is None:
        return None
    nav = " · ".join(f'<a href="/legal/{s}">{escape(t)}</a>' for s, t in TITLES.items())
    body = "".join(
        f"<h2>{escape(s['title'])}</h2>" + "".join(f"<p>{escape(p)}</p>" for p in s["body"].split("\n") if p)
        for s in d["sections"]
    )
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{escape(d['title'])} · REV GAMES</title>
<style>
:root{{--bg:#f6f6f8;--fg:#111114;--dim:#55555c;--line:#d9d9de;--link:#0b6b3a}}
@media(prefers-color-scheme:dark){{:root{{--bg:#0b0b0c;--fg:#f2f2f4;--dim:#a6a6ae;--line:#2a2a2e;--link:#5fd391}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:16px/1.65 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}}
main{{max-width:720px;margin:0 auto;padding:32px 20px 64px}}
h1{{font-size:28px;margin:0 0 4px}}h2{{font-size:18px;margin:32px 0 6px}}p{{margin:0 0 10px}}
.meta{{color:var(--dim);font-size:14px;margin-bottom:8px}}nav{{font-size:14px;color:var(--dim);padding-bottom:16px;border-bottom:1px solid var(--line);margin-bottom:20px}}
a{{color:var(--link)}}
.skip{{position:absolute;left:-999px}}.skip:focus{{left:12px;top:12px;background:var(--bg);padding:8px 12px;border:1px solid var(--line)}}
@media print{{nav,.skip{{display:none}}body{{background:#fff;color:#000}}}}
</style></head><body><a class="skip" href="#doc">Skip to content</a><main><nav>{nav}</nav><h1 id="doc">{escape(d['title'])}</h1><div class="meta">Last updated {escape(d['updated'])}</div>{body}</main></body></html>"""


# ---- email unsubscribe ----------------------------------------------------------------

def unsubscribe_token(secret: str, uid: str) -> str:
    return hmac.new((secret or "dev").encode(), f"unsub:{uid}".encode(), hashlib.sha256).hexdigest()[:32]


def unsubscribe_ok(secret: str, uid: str, token: str) -> bool:
    return bool(uid) and hmac.compare_digest(unsubscribe_token(secret, uid), token or "")
