"""Load the server's .env files before anything reads the environment.

Order (first one to set a variable wins; real environment variables always win):
    1. variables already in the environment (Cloud Run, CI, your shell)
    2. .env.<APP_ENV>      e.g. .env.local, .env.production   (APP_ENV defaults to "local")
    3. .env                shared defaults

Only the *.example files are committed. See .env.example.
"""
from __future__ import annotations

import os
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]


def load_env(base: Path = BASE) -> list[str]:
    """Returns the names of the files that were loaded."""
    try:
        from dotenv import load_dotenv
    except ImportError:  # python-dotenv is optional: production sets real variables
        return []

    loaded = []
    env = os.environ.get("APP_ENV", "local")
    for name in (f".env.{env}", ".env"):
        path = base / name
        if path.is_file():
            load_dotenv(path, override=False)
            loaded.append(name)

    # A relative key path in a .env file is relative to the server folder, and ~ works.
    cred = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if cred:
        resolved = Path(cred).expanduser()
        if not resolved.is_absolute():
            resolved = base / resolved
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(resolved)
    return loaded
