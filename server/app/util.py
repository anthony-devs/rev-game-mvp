"""Small helpers shared by every module."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Callable

Clock = Callable[[], datetime]


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def money(value: float) -> float:
    """Credits have 2 decimals."""
    return round(float(value) + 0.0, 2)


def as_utc(value) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value
