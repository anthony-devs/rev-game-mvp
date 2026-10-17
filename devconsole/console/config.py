"""Everything comes from the environment. Secrets are never stored in files or the database."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]


def _bool(name: str, default: bool) -> bool:
    v = os.environ.get(name)
    return default if v is None else v.lower() in ("1", "true", "yes")


@dataclass(frozen=True)
class Target:
    name: str
    url: str
    secret: str  # DEV_API_SECRET of that server, read from the env var named in targets.json

    @property
    def https(self) -> bool:
        return self.url.startswith("https://")


@dataclass(frozen=True)
class Config:
    user: str = os.environ.get("CONSOLE_USER", "")
    password_hash: str = os.environ.get("CONSOLE_PASSWORD_HASH", "")
    totp_secret: str = os.environ.get("CONSOLE_TOTP_SECRET", "")
    db_path: str = os.environ.get("CONSOLE_DB", str(BASE / "data" / "console.db"))
    targets_file: str = os.environ.get("TARGETS_FILE", str(BASE / "targets.json"))
    actions_file: str = os.environ.get("ACTIONS_FILE", str(BASE / "actions.json"))
    server_dir: str = os.environ.get("SERVER_DIR", str(BASE.parent / "server"))
    allowed_ips: tuple = tuple(x.strip() for x in os.environ.get("CONSOLE_ALLOWED_IPS", "").split(",") if x.strip())
    trust_proxy: int = int(os.environ.get("TRUST_PROXY", "0"))  # how many proxies sit in front (Cloud Run = 1)
    cookie_secure: bool = _bool("COOKIE_SECURE", True)  # set COOKIE_SECURE=0 only for http://localhost
    idle_minutes: int = int(os.environ.get("SESSION_IDLE_MINUTES", "30"))
    max_hours: int = int(os.environ.get("SESSION_MAX_HOURS", "8"))
    login_max_fails: int = int(os.environ.get("LOGIN_MAX_FAILS", "5"))
    login_lock_minutes: int = int(os.environ.get("LOGIN_LOCK_MINUTES", "15"))
    probe_seconds: float = float(os.environ.get("PROBE_SECONDS", "30"))
    alert_webhook: str = os.environ.get("ALERT_WEBHOOK_URL", "")
    telegram_token: str = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    telegram_chat: str = os.environ.get("TELEGRAM_CHAT_ID", "")
    run_monitor: bool = _bool("RUN_MONITOR", True)
    targets: tuple = field(default_factory=tuple)

    def with_targets(self) -> "Config":
        from dataclasses import replace

        return replace(self, targets=tuple(load_targets(self.targets_file)))


def load_targets(path: str) -> list[Target]:
    """targets.json: [{"name": "production", "url": "https://...", "secretEnv": "PROD_DEV_API_SECRET"}]"""
    p = Path(path)
    if not p.is_file():
        return []
    out = []
    for t in json.loads(p.read_text()):
        url = str(t["url"]).rstrip("/")
        if not url.startswith(("https://", "http://")):
            raise ValueError(f"target {t.get('name')}: url must start with http(s)://")
        out.append(Target(str(t["name"]), url, os.environ.get(str(t.get("secretEnv", "")), "")))
    return out
