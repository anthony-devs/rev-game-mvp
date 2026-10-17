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


def is_quota(exc: BaseException | None) -> bool:
    """Firestore ran out of daily quota (or is rate limiting), even when the error arrives wrapped."""
    seen = 0
    while exc is not None and seen < 5:
        if type(exc).__name__ in ("ResourceExhausted", "TooManyRequests"):
            return True
        text = str(exc).lower()
        if "quota" in text or "resource_exhausted" in text or "resource exhausted" in text or text.startswith("429"):
            return True
        exc, seen = exc.__cause__ or exc.__context__, seen + 1
    return False


_TRANSIENT = {"DeadlineExceeded", "ServiceUnavailable", "RetryError", "InternalServerError", "Aborted", "Unavailable",
              "ConnectionError", "ConnectTimeout", "ReadTimeout", "Timeout", "TimeoutError", "TransportError", "RefreshError"}


def is_transient(exc: BaseException | None) -> bool:
    """A temporary Firestore/network failure (retry later), as opposed to "database not set up"."""
    seen = 0
    while exc is not None and seen < 5:
        if type(exc).__name__ in _TRANSIENT or isinstance(exc, (TimeoutError, ConnectionError)):
            return True
        t = str(exc).lower()
        if "deadline" in t or "unavailable" in t or "timed out" in t or "temporarily" in t:
            return True
        exc, seen = exc.__cause__ or exc.__context__, seen + 1
    return False
