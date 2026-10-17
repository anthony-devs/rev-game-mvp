"""The Live Money Agreement: what a player accepts before playing with real money.

The text lives on the server so it can be corrected without shipping a new app. When the wording
changes in a way that needs fresh consent, raise ``LIVE_AGREEMENT_VERSION``: everyone is asked again
before their next live session. Have a lawyer in your licensing country review this text before launch.
"""
from __future__ import annotations

TITLE = "Live Money Agreement"

INTRO = (
    "Live play uses your own money. Please read this carefully. It explains how real-money play, "
    "deposits and withdrawals work on REV GAMES, and what we ask of you."
)

SECTIONS = [
    {
        "title": "Who can play",
        "body": "You must be at least 18 years old, or the legal gambling age where you live if that is higher. "
        "You must be allowed to gamble where you are. If real-money gambling is not legal where you live, do not use live play. "
        "You may hold one account. The details you give us must be true and your own.",
    },
    {
        "title": "Risk",
        "body": "Gambling is a form of entertainment, not a way to earn money. You can lose all the money you put in. "
        "No result can be predicted and no system guarantees a win. Only play with money you can afford to lose, "
        "and never with money meant for rent, food, bills, school fees or debts.",
    },
    {
        "title": "Your live balance",
        "body": "Your live balance is kept separate from demo credits. Demo credits have no cash value and cannot be withdrawn. "
        "Wins and losses in live mode are real. Your live balance is shown in your wallet and every payment has a record you can see.",
    },
    {
        "title": "Rounds and extra rounds",
        "body": "Playing uses rounds, and rounds are shared by all games. Every account gets {free} free rounds. They come back {hours} hours after the first round of each period. "
        "When you run out you can wait for them to refresh, or buy extra rounds from your live balance. Extra rounds cost {price} each and are sold in packs. "
        "A round you play uses one round whether you win or lose. The price of a round is a fee to play and is not a bet, so it never counts toward your winnings or losses. "
        "Extra rounds do not expire, but a purchase cannot be refunded once it is made. This fee helps pay for the servers and storage that keep the games running. "
        "The number of free rounds, the refresh time and the price can change. We always show the current ones before you buy.",
    },
    {
        "title": "Deposits",
        "body": "Deposit only from payment methods that belong to you. Payments from other people's accounts, cards or wallets may be refused or returned. "
        "Your balance is credited when the payment provider confirms the payment. Providers and networks may charge their own fees. "
        "For USDT and PayPal, the amount you pay is converted at the rate shown to you before you confirm. For USDT, send only the asset and network we show you: money sent on the wrong network cannot be recovered.",
    },
    {
        "title": "Withdrawals",
        "body": "You can withdraw your live balance to an account or wallet in your own name. Every withdrawal is checked by our team before it is sent, "
        "and we may ask you to verify your identity first. Funds are held from the moment you ask. "
        "Usual processing time is shown for each method, but banks, networks and providers can be slower. "
        "A withdrawal can be returned to your balance if it cannot be paid. Check the account or wallet details carefully: we cannot reverse a payment sent to the details you gave us.",
    },
    {
        "title": "Fair play",
        "body": "Game results are decided by our server using random numbers that you can verify. "
        "You can check any round from your history. You agree not to use bots, scripts, exploits, several accounts, or help from other players to gain an unfair advantage. "
        "If we find this, or find a mistake or fault in a game, we may void the affected rounds and correct your balance.",
    },
    {
        "title": "Playing responsibly",
        "body": "You can set deposit, loss and time limits at any time in Settings, take a break, or close your account. "
        "If gambling stops being fun, or you are worried about your play, stop and talk to someone you trust. "
        "Free, confidential help is available in many countries from local problem-gambling services. We may limit or suspend an account if we think you are at risk.",
    },
    {
        "title": "Security and checks",
        "body": "To keep players and the service safe we may check payments, ask for identification, limit or suspend accounts, and report suspicious activity "
        "to the authorities as the law requires. Keep your sign-in details private. You are responsible for activity on your account.",
    },
    {
        "title": "Taxes",
        "body": "You are responsible for any tax that applies to your winnings where you live.",
    },
    {
        "title": "Changes and questions",
        "body": "If this agreement changes in an important way, we will ask you to accept the new version before your next live session. "
        "You can reach us any time from Help, Contact support.",
    },
]

# What the player ticks. The server requires every id.
CONFIRMATIONS = [
    {"id": "age", "text": "I am 18 or older."},
    {"id": "legal", "text": "Real-money gambling is legal where I live."},
    {"id": "risk", "text": "I understand I can lose the money I deposit."},
    {"id": "agree", "text": "I have read and accept the Live Money Agreement."},
]


def document(version: str, cfg=None) -> dict:
    """The agreement with the live round numbers filled in, so the text always matches the settings."""
    values = {"free": 14, "hours": 6, "price": "50"}
    if cfg is not None:
        hours = cfg.rounds_window_hours
        values = {"free": cfg.rounds_free_live, "hours": int(hours) if float(hours).is_integer() else hours,
                  "price": f"{cfg.live_currency} {cfg.round_price_live:g}"}
    sections = [{**s, "body": s["body"].format(**values) if "{" in s["body"] else s["body"]} for s in SECTIONS]
    return {"version": version, "title": TITLE, "intro": INTRO, "sections": sections, "confirmations": CONFIRMATIONS}


def required_ids() -> set[str]:
    return {c["id"] for c in CONFIRMATIONS}
