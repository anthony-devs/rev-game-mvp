"""Delete a player's account: all stored data, then the sign in itself."""
from __future__ import annotations

from typing import Callable

from .store import Store


def firebase_account_deleter() -> Callable[[str], None]:
    from firebase_admin import auth

    def delete(uid: str) -> None:
        try:
            auth.delete_user(uid)
        except auth.UserNotFoundError:
            pass

    return delete


class AccountService:
    def __init__(self, store: Store, delete_auth_user: Callable[[str], None]):
        self.store, self._delete_auth = store, delete_auth_user

    def delete(self, uid: str) -> None:
        self.store.delete_user(uid)
        self._delete_auth(uid)
