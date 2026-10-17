"""Storage. Two implementations behind one small interface:

* FirestoreStore  - production (Cloud Run + Firebase Admin SDK)
* MemoryStore     - tests and local runs without Firebase

Everything that changes money goes through ``store.run(fn)``. ``fn`` gets a
transaction object, reads what it needs, and queues writes. The writes are
applied together, so a wallet can never be spent twice by two fast requests.

Firestore layout (matches the Flutter app):
    users/{uid}                       profile, settings, limits   (player edits)
    users/{uid}/wallet/current        balance, lastDailyClaimAt
    users/{uid}/progress/current      level, xp, streak, stats
    users/{uid}/rounds/{id}           history of every settled round
    users/{uid}/fairness/current      public: seed hash, client seed, nonce
    users/{uid}/seed_history/{hash}   revealed server seeds (after a rotate)
    fair_secrets/{uid}                server only: the live server seed
    crash_rounds/{id}                 server only: the secret crash point
    blackjack_rounds/{id}             server only: the shuffled deck
    blackjack_active/{uid}            server only: the hand in progress
    users/{uid}/account/standing      moderation summary the app listens to (server writes)
    users/{uid}/standing_actions/{id} bans, suspensions, restrictions, investigations
    users/{uid}/appeals/{id}          the player's appeals
    moderation_log/{id}               server only: audit trail of every moderation event
    users/{uid}/uploads/{id}          server only: attachment details (bytes live in Storage or on disk)
    users/{uid}/tickets/{id}          support ticket as the player sees it (+ /messages/{id})
    tickets/{id}                      support ticket as staff see it (+ /notes/{id}, server only)
    staff/{username}                  customer service reps (server only)
    staff_login/{hash}                failed sign-in counters (server only)
"""
from __future__ import annotations

import copy
import threading
import time
from typing import Any, Callable, Iterable, Optional

Doc = dict


# Live (real money) play uses a second, completely separate player record. Every game
# already works on "a player id", so live play simply uses ``L_<uid>``: its own wallet,
# fairness seeds, history and level. Demo credits and real money can never mix.
LIVE_PREFIX = "L_"


def live_uid(uid: str) -> str:
    return uid if uid.startswith(LIVE_PREFIX) else LIVE_PREFIX + uid


def is_live(uid: str) -> bool:
    return uid.startswith(LIVE_PREFIX)


def payment_path(pid: str) -> str:
    return f"payments/{pid}"  # the ledger (staff view, kept even if the player deletes their account)


def user_payment_path(uid: str, pid: str) -> str:
    return f"users/{uid}/payments/{pid}"  # the same record, for the player's own list


def payment_key_path(kind: str, uid: str, key: str) -> str:
    return f"payment_keys/{kind}_{uid}_{key}"  # one document per idempotency key


def payment_ref_path(provider: str, ref: str) -> str:
    return f"payment_refs/{provider}_{ref}"  # provider reference -> our payment; credited once


def wallet_path(uid: str) -> str:
    return f"users/{uid}/wallet/current"


def progress_path(uid: str) -> str:
    return f"users/{uid}/progress/current"


def round_path(uid: str, round_id: str) -> str:
    return f"users/{uid}/rounds/{round_id}"


def fair_public_path(uid: str) -> str:
    return f"users/{uid}/fairness/current"


def seed_history_path(uid: str, seed_hash: str) -> str:
    return f"users/{uid}/seed_history/{seed_hash}"


def fair_secret_path(uid: str) -> str:
    return f"fair_secrets/{uid}"


def standing_path(uid: str) -> str:
    return f"users/{uid}/account/standing"


def action_path(uid: str, action_id: str) -> str:
    return f"users/{uid}/standing_actions/{action_id}"


def appeal_path(uid: str, appeal_id: str) -> str:
    return f"users/{uid}/appeals/{appeal_id}"


def log_path(log_id: str) -> str:
    return f"moderation_log/{log_id}"


def crash_path(round_id: str) -> str:
    return f"crash_rounds/{round_id}"


def blackjack_path(round_id: str) -> str:
    return f"blackjack_rounds/{round_id}"


def blackjack_active_path(uid: str) -> str:
    return f"blackjack_active/{uid}"


class Txn:
    """What a transaction function can do. Reads are immediate, writes are queued."""

    def get(self, path: str) -> Optional[Doc]:
        raise NotImplementedError

    def set(self, path: str, data: Doc) -> None:
        raise NotImplementedError

    def delete(self, path: str) -> None:
        raise NotImplementedError

    def preload(self, *paths: str) -> None:
        """Read several documents in one round trip (Firestore) so the ``get`` calls
        that follow are free. Optional: ``get`` works without it, just slower."""

    def preload_player(self, uid: str) -> None:
        self.preload(wallet_path(uid), progress_path(uid), fair_public_path(uid), fair_secret_path(uid))

    # Named helpers so the game code reads clearly.
    def get_wallet(self, uid): return self.get(wallet_path(uid))
    def set_wallet(self, uid, data): self.set(wallet_path(uid), data)
    def get_progress(self, uid): return self.get(progress_path(uid))
    def set_progress(self, uid, data): self.set(progress_path(uid), data)
    def get_crash(self, round_id): return self.get(crash_path(round_id))
    def set_crash(self, round_id, data): self.set(crash_path(round_id), data)
    def add_round(self, uid, round_id, data): self.set(round_path(uid, round_id), data)


class WatchedList:
    """Plain version: reads every time (the in-memory store is free to read)."""

    def __init__(self, loader: Callable[[], list]):
        self._loader = loader

    def rows(self) -> list[tuple[str, Doc]]:
        return self._loader()


class _ListenerList(WatchedList):
    """Rows kept current by a Firestore snapshot listener."""

    RETRY_AFTER = 60.0

    def __init__(self, query, loader: Callable[[], list]):
        super().__init__(loader)
        self._query = query
        self._rows: list | None = None
        self._ready = threading.Event()
        self._lock = threading.Lock()
        self._unsub = None
        self._failed_at = 0.0

    def _on_snapshot(self, docs, _changes, _read_time):
        self._rows = [(d.id, d.to_dict()) for d in docs]  # the library only bills the changed ones
        self._ready.set()

    def _on_error(self, *_a):
        self._failed_at = time.monotonic()
        self._unsub = None

    def _start(self):
        self._failed_at = 0.0
        self._unsub = self._query.on_snapshot(self._on_snapshot)

    def rows(self) -> list[tuple[str, Doc]]:
        with self._lock:
            if self._unsub is not None and not getattr(self._unsub, "is_active", True):
                self._on_error()  # the listener closed itself (quota, network): restart it later
            if self._unsub is None and (self._rows is None or time.monotonic() - self._failed_at > self.RETRY_AFTER):
                try:
                    self._start()
                except Exception:
                    self._failed_at = time.monotonic()
        if self._rows is None:
            if not self._ready.wait(10):  # first fill: wait for the listener, else one plain read
                return self._loader()
        return copy.deepcopy(self._rows or [])


class Store:
    def run(self, fn: Callable[[Txn], Any]) -> Any:
        raise NotImplementedError

    def read(self, path: str) -> Optional[Doc]:
        """Plain read outside a transaction."""
        raise NotImplementedError

    def list(self, collection: str, limit: int = 200, order_by: str | None = None) -> list[tuple[str, Doc]]:
        """Documents directly inside a collection path. Not transactional."""
        raise NotImplementedError

    def merge(self, path: str, data: Doc) -> None:
        """Set only these fields (create the document if missing). Not transactional."""
        raise NotImplementedError

    def incr(self, path: str, deltas: dict) -> None:
        """Add numbers to (possibly nested) counters, atomically and safely from many servers.
        ``{"live": {"dice": {"bets": 3}}}`` adds 3 to ``live.dice.bets``."""
        raise NotImplementedError

    def count(self, collection: str, where: tuple | None = None) -> int:
        """How many documents match ``(field, op, value)``. Billed as ONE read per 1,000 matches."""
        raise NotImplementedError

    def watch_list(self, collection: str, limit: int = 200, order_by: str | None = None) -> "WatchedList":
        """A list that keeps itself current. Same rows as :meth:`list`, but on Firestore it is
        fed by a snapshot listener: billed once when it starts, then only for documents that
        change, instead of a full read every time it is asked for."""
        return WatchedList(lambda: self.list(collection, limit, order_by))

    def delete_user(self, uid: str) -> None:
        """Remove everything stored for this player."""
        raise NotImplementedError

    # Convenience used by the crash event stream.
    def read_crash(self, round_id): return self.read(crash_path(round_id))
    def read_wallet(self, uid): return self.read(wallet_path(uid))


# --------------------------------------------------------------------------- memory

class _MemTxn(Txn):
    def __init__(self, store: "MemoryStore"):
        self._s = store
        self._writes: list[tuple[str, Optional[Doc]]] = []
        self._pending: dict[str, Optional[Doc]] = {}

    def get(self, path):
        if path in self._pending:  # read your own writes
            d = self._pending[path]
        else:
            d = self._s.docs.get(path)
        return copy.deepcopy(d) if d is not None else None

    def set(self, path, data):
        self._writes.append((path, copy.deepcopy(data)))
        self._pending[path] = copy.deepcopy(data)

    def delete(self, path):
        self._writes.append((path, None))
        self._pending[path] = None

    def flush(self):
        for path, data in self._writes:
            if data is None:
                self._s.docs.pop(path, None)
            else:
                self._s.docs[path] = data


class _Section:
    """A live, dict-like view over part of the memory store (used by tests)."""

    def __init__(self, store: "MemoryStore", key: Callable[[str], str], match: Callable[[str], bool]):
        self._s, self._key, self._match = store, key, match

    def __getitem__(self, k):
        return self._s.docs[self._key(k)]

    def get(self, k, default=None):
        return self._s.docs.get(self._key(k), default)

    def __len__(self):
        return sum(1 for p in self._s.docs if self._match(p))

    def __iter__(self) -> Iterable[str]:
        return iter([p for p in self._s.docs if self._match(p)])


class MemoryStore(Store):
    def __init__(self):
        self.docs: dict[str, Doc] = {}
        self._lock = threading.RLock()
        self.wallets = _Section(self, lambda uid: wallet_path(uid), lambda p: p.endswith("/wallet/current"))
        self.crash = _Section(self, lambda rid: crash_path(rid), lambda p: p.startswith("crash_rounds/"))
        self.rounds = _Section(
            self, lambda k: round_path(*k), lambda p: p.startswith("users/") and "/rounds/" in p
        )
        self.progress = _Section(self, lambda uid: progress_path(uid), lambda p: p.endswith("/progress/current"))

    def run(self, fn):
        with self._lock:
            txn = _MemTxn(self)
            result = fn(txn)
            txn.flush()
            return result

    def read(self, path):
        with self._lock:
            d = self.docs.get(path)
            return copy.deepcopy(d) if d is not None else None

    def merge(self, path, data):
        with self._lock:
            self.docs[path] = {**self.docs.get(path, {}), **copy.deepcopy(data)}

    def incr(self, path, deltas):
        def add(dst, src):
            for k, v in src.items():
                if isinstance(v, dict):
                    add(dst.setdefault(k, {}), v)
                else:
                    dst[k] = dst.get(k, 0) + v

        with self._lock:
            doc = self.docs.setdefault(path, {})
            add(doc, deltas)

    def count(self, collection, where=None):
        import operator

        ops = {"==": operator.eq, ">=": operator.ge, ">": operator.gt, "<": operator.lt, "<=": operator.le, "!=": operator.ne}
        prefix = collection.rstrip("/") + "/"
        n = 0
        with self._lock:
            for path, doc in self.docs.items():
                if not path.startswith(prefix) or "/" in path[len(prefix):]:
                    continue
                if where is not None:
                    f, op, v = where
                    cur = doc.get(f)
                    if cur is None:
                        continue
                    try:
                        if not ops[op](cur, v):
                            continue
                    except TypeError:
                        continue
                n += 1
        return n

    def list(self, collection, limit=200, order_by=None):
        prefix = collection.rstrip("/") + "/"
        with self._lock:
            out = [
                (path[len(prefix):], copy.deepcopy(doc))
                for path, doc in self.docs.items()
                if path.startswith(prefix) and "/" not in path[len(prefix):]
            ]
        if order_by:
            out.sort(key=lambda r: str(r[1].get(order_by) or ""), reverse=True)
        return out[:limit]

    def delete_user(self, uid):
        with self._lock:
            for path in list(self.docs):
                doc = self.docs[path]
                if path.startswith(f"users/{uid}/") or path in (
                    f"users/{uid}",
                    fair_secret_path(uid),
                    blackjack_active_path(uid),
                ):
                    del self.docs[path]
                elif path.startswith(("crash_rounds/", "blackjack_rounds/")) and doc.get("uid") == uid:
                    del self.docs[path]
            gone = {p.split("/")[1] for p, d in self.docs.items() if p.startswith("tickets/") and p.count("/") == 1 and d.get("uid") == uid}
            for path in list(self.docs):
                if path.startswith("tickets/") and path.split("/")[1] in gone:
                    del self.docs[path]


# --------------------------------------------------------------------------- firestore

class _FsTxn(Txn):
    def __init__(self, db, transaction):
        self._db = db
        self._t = transaction
        self._pending: dict[str, Optional[Doc]] = {}
        self._loaded: dict[str, Optional[Doc]] = {}

    def preload(self, *paths):
        todo = [p for p in paths if p not in self._pending and p not in self._loaded]
        if not todo:
            return
        refs = [self._db.document(p) for p in todo]
        for p in todo:
            self._loaded[p] = None
        for snap in self._db.get_all(refs, transaction=self._t):
            self._loaded[snap.reference.path] = snap.to_dict() if snap.exists else None

    def get(self, path):
        if path in self._pending:  # read your own writes (Firestore applies them at the end)
            d = self._pending[path]
            return copy.deepcopy(d) if d is not None else None
        if path in self._loaded:
            d = self._loaded[path]
            return copy.deepcopy(d) if d is not None else None
        snap = self._db.document(path).get(transaction=self._t)
        return snap.to_dict() if snap.exists else None

    def set(self, path, data):
        self._pending[path] = copy.deepcopy(data)

    def delete(self, path):
        self._pending[path] = None

    def flush(self):
        # Firestore requires every read to happen before the first write.
        # Only the last value for each document is sent.
        for path, data in self._pending.items():
            ref = self._db.document(path)
            if data is None:
                self._t.delete(ref)
            else:
                self._t.set(ref, data)


class FirestoreStore(Store):
    def __init__(self, db):
        from google.cloud import firestore

        self._db = db
        self._firestore = firestore

    def run(self, fn):
        firestore = self._firestore

        @firestore.transactional
        def attempt(transaction):
            txn = _FsTxn(self._db, transaction)
            result = fn(txn)
            txn.flush()
            return result

        return attempt(self._db.transaction())

    def read(self, path):
        snap = self._db.document(path).get()
        return snap.to_dict() if snap.exists else None

    def list(self, collection, limit=200, order_by=None):
        q = self._db.collection(collection)
        if order_by:  # newest first, and Firestore only reads (and bills) the `limit` documents it returns
            from google.cloud.firestore_v1 import Query

            q = q.order_by(order_by, direction=Query.DESCENDING)
        return [(snap.id, snap.to_dict()) for snap in q.limit(limit).stream()]

    def merge(self, path, data):
        self._db.document(path).set(data, merge=True)

    def incr(self, path, deltas):
        Increment = self._firestore.Increment

        def conv(d):
            return {k: (conv(v) if isinstance(v, dict) else Increment(v)) for k, v in d.items()}

        self._db.document(path).set(conv(deltas), merge=True)

    def count(self, collection, where=None):
        from google.cloud.firestore_v1.base_query import FieldFilter

        q = self._db.collection(collection)
        if where is not None:
            q = q.where(filter=FieldFilter(*where))
        return int(q.count().get()[0][0].value)

    def watch_list(self, collection, limit=200, order_by=None):
        from google.cloud.firestore_v1 import Query

        q = self._db.collection(collection)
        if order_by:
            q = q.order_by(order_by, direction=Query.DESCENDING)
        return _ListenerList(q.limit(limit), lambda: self.list(collection, limit, order_by))

    def delete_user(self, uid):
        from google.cloud.firestore_v1.base_query import FieldFilter

        db = self._db
        db.recursive_delete(db.collection("users").document(uid))
        db.document(fair_secret_path(uid)).delete()
        db.document(blackjack_active_path(uid)).delete()
        for snap in db.collection("tickets").where(filter=FieldFilter("uid", "==", uid)).stream():
            db.recursive_delete(snap.reference)
        for coll in ("crash_rounds", "blackjack_rounds"):
            for snap in db.collection(coll).where(filter=FieldFilter("uid", "==", uid)).stream():
                snap.reference.delete()
