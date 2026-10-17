"""Stops the same request running twice.

A slow response makes people click again, and phones retry on a bad network. For anything that
changes data, an identical request (same person, same address, same body) that arrives while the
first is still running, or just after it succeeded, is refused with 409 instead of running again.

* While running: always refused (nobody sends the same change twice at the same moment on purpose).
* Just after success: refused for ``cooloff`` seconds (back-office only; players can repeat a bet).
* After a failure: allowed straight away, so fixing a typo and resending works.

It lives in memory of one server, which is where a double click lands.
"""
from __future__ import annotations

import hashlib
import threading
import time


class RequestGuard:
    def __init__(self, max_running: float = 60.0):
        self._lock = threading.Lock()
        self._seen: dict[str, tuple[float, float | None]] = {}  # key -> (started, finished_ok_at)
        self._max_running = max_running
        self._last_purge = 0.0

    def enter(self, key: str, cooloff: float) -> bool:
        now = time.monotonic()
        with self._lock:
            if now - self._last_purge > 30:
                self._last_purge = now
                for k, (start, done) in list(self._seen.items()):
                    if (done is not None and now - done > 30) or (done is None and now - start > self._max_running):
                        del self._seen[k]
            hit = self._seen.get(key)
            if hit is not None:
                start, done = hit
                if done is None and now - start < self._max_running:
                    return False  # still running
                if done is not None and now - done < cooloff:
                    return False  # just succeeded
            self._seen[key] = (now, None)
            return True

    def leave(self, key: str, ok: bool) -> None:
        with self._lock:
            hit = self._seen.get(key)
            if hit is None:
                return
            if ok:
                self._seen[key] = (hit[0], time.monotonic())
            else:
                del self._seen[key]


def request_key(who: str, method: str, path: str, content_type: str, content_length: int | None, body: bytes | None) -> str:
    h = hashlib.sha256()
    for part in (who, method, path):
        h.update(part.encode())
        h.update(b"\0")
    if content_type.startswith("multipart/"):
        h.update(f"multipart:{content_length}".encode())  # an upload: don't read the whole file just to compare
    else:
        h.update(body or b"")
    return h.hexdigest()
