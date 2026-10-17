"""A small local SQLite file: probe history, incidents, sessions, runs and a tamper-evident audit log.

Deliberately not Firestore: the console must keep working (and keep recording) when the thing it
watches is down, and it must not spend a single database read of the game."""
from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
import time
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS probes(id INTEGER PRIMARY KEY, target TEXT, at REAL, ok INTEGER, ms REAL, status INTEGER, detail TEXT);
CREATE INDEX IF NOT EXISTS probes_t ON probes(target, at);
CREATE TABLE IF NOT EXISTS incidents(id INTEGER PRIMARY KEY, target TEXT, started REAL, ended REAL, reason TEXT);
CREATE TABLE IF NOT EXISTS latest(target TEXT PRIMARY KEY, at REAL, diag TEXT, dbcheck TEXT, cert_days REAL);
CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY, user TEXT, csrf TEXT, created REAL, last_seen REAL, ip TEXT);
CREATE TABLE IF NOT EXISTS fails(key TEXT, at REAL);
CREATE INDEX IF NOT EXISTS fails_k ON fails(key, at);
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, action TEXT, target TEXT, actor TEXT, started REAL, ended REAL, status TEXT, output TEXT, params TEXT);
CREATE TABLE IF NOT EXISTS tests(id INTEGER PRIMARY KEY, target TEXT, at REAL, passed INTEGER, failed INTEGER, results TEXT);
CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY, at REAL, actor TEXT, ip TEXT, action TEXT, detail TEXT, prev TEXT, hash TEXT);
"""


class DB:
    def __init__(self, path: str):
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.c = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self.c.row_factory = sqlite3.Row
        self.lock = threading.RLock()
        with self.lock:
            self.c.execute("PRAGMA journal_mode=WAL")
            self.c.executescript(SCHEMA)
        if path != ":memory:":
            try:
                Path(path).chmod(0o600)
            except OSError:
                pass

    def q(self, sql: str, args: tuple = ()) -> list[sqlite3.Row]:
        with self.lock:
            return self.c.execute(sql, args).fetchall()

    def x(self, sql: str, args: tuple = ()) -> int:
        with self.lock:
            return self.c.execute(sql, args).lastrowid

    # -- meta
    def get(self, k: str, default: str = "") -> str:
        r = self.q("SELECT v FROM meta WHERE k=?", (k,))
        return r[0]["v"] if r else default

    def put(self, k: str, v: str) -> None:
        self.x("INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", (k, v))

    # -- audit: every row carries the hash of the one before it, so editing or deleting history is detectable
    def audit(self, actor: str, ip: str, action: str, detail: dict | str = "") -> None:
        detail = detail if isinstance(detail, str) else json.dumps(detail, sort_keys=True, default=str)
        with self.lock:
            last = self.q("SELECT hash FROM audit ORDER BY id DESC LIMIT 1")
            prev = last[0]["hash"] if last else "genesis"
            at = round(time.time(), 3)
            h = hashlib.sha256(f"{prev}|{at}|{actor}|{ip}|{action}|{detail}".encode()).hexdigest()
            self.x("INSERT INTO audit(at,actor,ip,action,detail,prev,hash) VALUES(?,?,?,?,?,?,?)", (at, actor, ip, action, detail[:2000], prev, h))

    def audit_ok(self) -> bool:
        prev = "genesis"
        for r in self.q("SELECT * FROM audit ORDER BY id"):
            h = hashlib.sha256(f"{prev}|{r['at']}|{r['actor']}|{r['ip']}|{r['action']}|{r['detail']}".encode()).hexdigest()
            if r["prev"] != prev or r["hash"] != h:
                return False
            prev = h
        return True
