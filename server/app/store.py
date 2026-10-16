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
"""
from __future__ import annotations

import copy
import threading
from typing import Any, Callable, Iterable, Optional

Doc = dict


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

    # Named helpers so the game code reads clearly.
    def get_wallet(self, uid): return self.get(wallet_path(uid))
    def set_wallet(self, uid, data): self.set(wallet_path(uid), data)
    def get_progress(self, uid): return self.get(progress_path(uid))
    def set_progress(self, uid, data): self.set(progress_path(uid), data)
    def get_crash(self, round_id): return self.get(crash_path(round_id))
    def set_crash(self, round_id, data): self.set(crash_path(round_id), data)
    def add_round(self, uid, round_id, data): self.set(round_path(uid, round_id), data)


class Store:
    def run(self, fn: Callable[[Txn], Any]) -> Any:
        raise NotImplementedError

    def read(self, path: str) -> Optional[Doc]:
        """Plain read outside a transaction."""
        raise NotImplementedError

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


# --------------------------------------------------------------------------- firestore

class _FsTxn(Txn):
    def __init__(self, db, transaction):
        self._db = db
        self._t = transaction
        self._pending: dict[str, Optional[Doc]] = {}

    def get(self, path):
        if path in self._pending:  # read your own writes (Firestore applies them at the end)
            d = self._pending[path]
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

    def delete_user(self, uid):
        from google.cloud.firestore_v1.base_query import FieldFilter

        db = self._db
        db.recursive_delete(db.collection("users").document(uid))
        db.document(fair_secret_path(uid)).delete()
        db.document(blackjack_active_path(uid)).delete()
        for coll in ("crash_rounds", "blackjack_rounds"):
            for snap in db.collection(coll).where(filter=FieldFilter("uid", "==", uid)).stream():
                snap.reference.delete()
