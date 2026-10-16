"""Attachments for appeals and support tickets.

Files are checked by their first bytes (what they really are), never by the name or
the type the client claims. Only photos, short videos and PDFs are accepted. Each file
belongs to the player who uploaded it; staff read it through an authenticated route.

Bytes go to Firebase Storage when ``FIREBASE_STORAGE_BUCKET`` is set, otherwise to a
folder on disk (fine for local work, not for Cloud Run).
"""
from __future__ import annotations

import os
import re
import uuid
from datetime import timedelta
from pathlib import Path
from typing import Optional

from .config import Config
from .errors import ApiError, bad_request
from .store import Store
from .util import Clock, as_utc, utcnow

KINDS = {
    "image/jpeg": "image", "image/png": "image", "image/gif": "image", "image/webp": "image", "image/heic": "image",
    "video/mp4": "video", "video/quicktime": "video",
    "application/pdf": "pdf",
}
EXT = {"image/jpeg": ".jpg", "image/png": ".png", "image/gif": ".gif", "image/webp": ".webp", "image/heic": ".heic",
       "video/mp4": ".mp4", "video/quicktime": ".mov", "application/pdf": ".pdf"}


def sniff(data: bytes) -> Optional[str]:
    """The real type of a file from its first bytes, or None if we don't accept it."""
    h = data[:16]
    if h.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if h.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if h.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if h[:4] == b"RIFF" and h[8:12] == b"WEBP":
        return "image/webp"
    if h.startswith(b"%PDF-"):
        return "application/pdf"
    if h[4:8] == b"ftyp":
        brand = data[8:12]
        if brand in (b"heic", b"heix", b"hevc", b"mif1", b"msf1", b"heim", b"heis"):
            return "image/heic"
        if brand == b"qt  ":
            return "video/quicktime"
        return "video/mp4"
    return None


def clean_name(name: str, mime: str) -> str:
    name = os.path.basename((name or "").replace("\\", "/"))
    name = re.sub(r"[\x00-\x1f\x7f<>:\"|?*]", "", name).strip(". ")
    stem, ext = os.path.splitext(name)
    stem = stem[:60] or "file"
    return stem + EXT[mime]  # the extension always matches the real type


# ------------------------------------------------------------------ blob stores

class MemoryBlobs:
    def __init__(self):
        self.data: dict[str, bytes] = {}

    def put(self, key, data, mime): self.data[key] = data
    def get(self, key): return self.data.get(key)

    def delete_prefix(self, prefix):
        for k in [k for k in self.data if k.startswith(prefix)]:
            del self.data[k]


class LocalBlobs:
    def __init__(self, root: str):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _p(self, key: str) -> Path:
        p = (self.root / key).resolve()
        if self.root not in p.parents:
            raise ValueError("bad key")
        return p

    def put(self, key, data, mime):
        p = self._p(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)

    def get(self, key):
        p = self._p(key)
        return p.read_bytes() if p.is_file() else None

    def delete_prefix(self, prefix):
        import shutil

        p = self._p(prefix)
        if p.is_dir():
            shutil.rmtree(p, ignore_errors=True)


class GcsBlobs:
    def __init__(self, bucket_name: str):
        from firebase_admin import storage

        self.bucket = storage.bucket(bucket_name)

    def put(self, key, data, mime):
        self.bucket.blob(key).upload_from_string(data, content_type=mime)

    def get(self, key):
        blob = self.bucket.blob(key)
        return blob.download_as_bytes() if blob.exists() else None

    def delete_prefix(self, prefix):
        for blob in self.bucket.list_blobs(prefix=prefix):
            blob.delete()


def make_blobs(cfg: Config):
    if cfg.storage_bucket:
        return GcsBlobs(cfg.storage_bucket)
    return LocalBlobs(cfg.upload_dir or str(Path(__file__).resolve().parents[1] / "data" / "uploads"))


# ---------------------------------------------------------------------- service

class UploadService:
    def __init__(self, store: Store, cfg: Config, blobs=None, clock: Clock = utcnow):
        self.store, self.cfg, self.clock = store, cfg, clock
        self.blobs = blobs if blobs is not None else make_blobs(cfg)

    def save(self, uid: str, filename: str, data: bytes) -> dict:
        if not data:
            raise bad_request("empty_file", "That file is empty.")
        if len(data) > self.cfg.upload_max_mb * 1024 * 1024:
            raise ApiError(413, "file_too_large", f"Files can be up to {self.cfg.upload_max_mb:g} MB.")
        mime = sniff(data)
        if mime is None:
            raise bad_request("file_type_not_allowed", "Only photos, videos and PDFs can be attached.")
        since = self.clock() - timedelta(days=1)
        recent = [d for _i, d in self.store.list(f"users/{uid}/uploads", 300) if as_utc(d["createdAt"]) >= since]
        if len(recent) >= self.cfg.upload_daily_limit:
            raise ApiError(429, "upload_limit", "You've reached today's upload limit. Try again tomorrow.")
        fid = uuid.uuid4().hex
        key = f"uploads/{uid}/{fid}"
        self.blobs.put(key, data, mime)
        meta = {"id": fid, "name": clean_name(filename, mime), "mime": mime, "kind": KINDS[mime], "size": len(data), "key": key, "createdAt": self.clock()}
        self.store.run(lambda txn: txn.set(f"users/{uid}/uploads/{fid}", meta))
        return self.public(meta)

    @staticmethod
    def public(meta: dict) -> dict:
        return {k: meta[k] for k in ("id", "name", "mime", "kind", "size")}

    def resolve(self, uid: str, ids) -> list[dict]:
        """Check the ids belong to this player and return their public details."""
        if ids in (None, ""):
            return []
        if not isinstance(ids, list) or not all(isinstance(i, str) for i in ids):
            raise bad_request("invalid_attachments", "Attachments must be a list of upload ids.")
        if len(set(ids)) != len(ids):
            raise bad_request("invalid_attachments", "The same file was attached twice.")
        if len(ids) > self.cfg.upload_max_files:
            raise bad_request("too_many_files", f"You can attach up to {self.cfg.upload_max_files} files.")
        out = []
        for fid in ids:
            meta = self.store.read(f"users/{uid}/uploads/{fid}") if re.fullmatch(r"[0-9a-f]{32}", fid) else None
            if meta is None:
                raise bad_request("invalid_attachments", "One of the attachments wasn't found. Upload it again.")
            out.append(self.public(meta))
        return out

    def read(self, uid: str, fid: str) -> tuple[dict, bytes]:
        meta = self.store.read(f"users/{uid}/uploads/{fid}") if re.fullmatch(r"[0-9a-f]{32}", fid or "") else None
        data = self.blobs.get(meta["key"]) if meta else None
        if meta is None or data is None:
            raise ApiError(404, "file_not_found", "File not found.")
        return meta, data

    def purge(self, uid: str) -> None:
        self.blobs.delete_prefix(f"uploads/{uid}/")


def file_response(meta: dict, data: bytes, download: bool = False):
    """Serve a file so a browser can't run it: fixed type, no sniffing, sandboxed."""
    from flask import Response

    resp = Response(data, mimetype=meta["mime"])
    disp = "attachment" if download or meta["kind"] == "pdf" else "inline"
    resp.headers["Content-Disposition"] = f'{disp}; filename="{meta["name"]}"'
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Content-Security-Policy"] = "sandbox; default-src 'none'"
    resp.headers["Cache-Control"] = "private, no-store"
    return resp
