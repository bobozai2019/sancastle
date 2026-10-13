"""Signed receipt envelope for GodotIQ Pro entitlement.

Verifies Ed25519-signed receipts issued by the GodotIQ Worker. Defeats
local tampering (unsigned cache file) and clock rollback (high-water mark
seeded only from Worker-signed iat values).

Storage: single envelope file receipt.json = {"payload": {...}, "sig": "<b64>"}
Atomic writes via temp+rename, 0600 perms on POSIX.

Canonicalization is byte-identical to the Worker's canonicalize(payload)
(worker/src/sign.ts). A cross-runtime regression test on both sides
locks this contract in.
"""

from __future__ import annotations

import base64
import json
import os
import re
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path

from cryptography.exceptions import InvalidSignature as _CryptoInvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey


class ReceiptError(Exception):
    """Base class for receipt verification failures."""


class InvalidSignature(ReceiptError):
    """Ed25519 signature verification failed."""


class UnknownKid(ReceiptError):
    """The payload's kid is not present in the pubkey set."""


class NotYetValid(ReceiptError):
    """Current time is before the receipt's nbf."""


class Expired(ReceiptError):
    """Current time is after the receipt's exp."""


class MalformedReceipt(ReceiptError):
    """Receipt JSON is not parseable, not a dict, or missing required fields."""


_REQUIRED_FIELDS = (
    "kid",
    "iat",
    "nbf",
    "exp",
    "grace_until",
    "key_hash",
    "activation_id",
    "install_id",
)

_INT_FIELDS = ("iat", "nbf", "exp", "grace_until")
_STR_FIELDS = ("kid", "key_hash", "activation_id", "install_id")
_KEY_HASH_RE = re.compile(r"^[0-9a-f]{64}$")
_ED25519_SIG_LEN = 64


@dataclass(frozen=True)
class Receipt:
    """Immutable verified-receipt payload."""

    kid: str
    iat: int
    nbf: int
    exp: int
    grace_until: int
    key_hash: str
    activation_id: str
    install_id: str


def canonicalize_payload(payload: dict) -> bytes:
    """Return the canonical byte encoding used for signing.

    MUST be byte-identical to worker/src/sign.ts::canonicalize. Uses
    json.dumps with sort_keys=True and compact separators (',', ':')
    so both runtimes produce the same bytes for the same payload.

    Input MUST be ASCII-clean. The Worker's canonicalStringify
    (sign.ts:40-48) raises on non-ASCII bytes; this function silently
    escapes them to \\u00XX via ensure_ascii=True, producing bytes the
    Worker would never sign. Callers must not put non-ASCII data into
    receipt payloads.
    """
    return json.dumps(
        payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")


def verify_receipt(
    receipt_json: bytes,
    sig: bytes,
    kid_to_pubkey: dict[str, bytes],
    now: int,
) -> Receipt:
    """Parse and verify a signed receipt.

    Raises:
      MalformedReceipt: JSON parse error, non-dict root, missing field,
        non-int time field, or any other shape violation.
      UnknownKid: kid not present in kid_to_pubkey.
      InvalidSignature: Ed25519 signature verification failure.
      NotYetValid: now < nbf.
      Expired: now > exp.
    """
    try:
        parsed = json.loads(receipt_json)
    except (ValueError, TypeError) as exc:
        raise MalformedReceipt(f"receipt_json is not valid JSON: {exc}") from exc

    if not isinstance(parsed, dict):
        raise MalformedReceipt(
            f"receipt root must be an object, got {type(parsed).__name__}"
        )

    for field_name in _REQUIRED_FIELDS:
        if field_name not in parsed:
            raise MalformedReceipt(f"missing required field: {field_name}")

    for field_name in _INT_FIELDS:
        value = parsed[field_name]
        if not isinstance(value, int) or isinstance(value, bool):
            raise MalformedReceipt(
                f"field {field_name} must be int, got {type(value).__name__}"
            )

    for field_name in _STR_FIELDS:
        value = parsed[field_name]
        if not isinstance(value, str):
            raise MalformedReceipt(
                f"field {field_name} must be str, got {type(value).__name__}"
            )
        if not value:
            raise MalformedReceipt(f"field {field_name} must not be empty")

    if not _KEY_HASH_RE.match(parsed["key_hash"]):
        raise MalformedReceipt(
            "key_hash must be a 64-char lowercase hex sha256 digest"
        )

    kid = parsed["kid"]
    pubkey = kid_to_pubkey.get(kid)
    if pubkey is None:
        raise UnknownKid(f"unknown kid: {kid!r}")

    canonical = canonicalize_payload(parsed)
    try:
        Ed25519PublicKey.from_public_bytes(pubkey).verify(sig, canonical)
    except _CryptoInvalidSignature as exc:
        raise InvalidSignature("Ed25519 signature verification failed") from exc

    if now < parsed["nbf"]:
        raise NotYetValid(f"now ({now}) < nbf ({parsed['nbf']})")
    if now > parsed["exp"]:
        raise Expired(f"now ({now}) > exp ({parsed['exp']})")

    return Receipt(
        kid=parsed["kid"],
        iat=parsed["iat"],
        nbf=parsed["nbf"],
        exp=parsed["exp"],
        grace_until=parsed["grace_until"],
        key_hash=parsed["key_hash"],
        activation_id=parsed["activation_id"],
        install_id=parsed["install_id"],
    )


def is_within_grace(receipt: Receipt, now: int) -> bool:
    """True iff receipt.exp < now <= receipt.grace_until."""
    return receipt.exp < now <= receipt.grace_until


def _atomic_write_bytes(path: Path, data: bytes) -> None:
    """Write *data* to *path* atomically with 0600 perms on POSIX."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=path.name + ".tmp-", dir=str(path.parent)
    )
    fd_owned_by_fdopen = False
    try:
        try:
            if os.name == "posix":
                os.fchmod(fd, 0o600)
            fp = os.fdopen(fd, "wb")
            fd_owned_by_fdopen = True
            try:
                fp.write(data)
                fp.flush()
                os.fsync(fp.fileno())
            finally:
                fp.close()
        except BaseException:
            # fdopen takes ownership of fd on success and closes it on
            # its own close/exit. Only close ourselves if fdopen never
            # got the fd.
            if not fd_owned_by_fdopen:
                try:
                    os.close(fd)
                except OSError:
                    pass
            raise
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def read_receipt_from_disk(path: Path) -> tuple[bytes, bytes] | None:
    """Return (payload_json_bytes, sig_bytes) or None.

    None is returned if the file is missing, unreadable, not valid JSON,
    missing payload or sig keys, or sig is not valid base64.
    payload_json_bytes is re-serialized via canonicalize_payload so the
    returned bytes are guaranteed to match what verify_receipt will
    re-canonicalize.
    """
    try:
        raw = path.read_bytes()
    except (FileNotFoundError, IsADirectoryError, PermissionError, OSError):
        return None

    try:
        envelope = json.loads(raw)
    except (ValueError, TypeError):
        return None

    if not isinstance(envelope, dict):
        return None
    if "payload" not in envelope or "sig" not in envelope:
        return None

    payload = envelope["payload"]
    sig_b64 = envelope["sig"]
    if not isinstance(payload, dict) or not isinstance(sig_b64, str):
        return None

    try:
        sig_bytes = base64.b64decode(sig_b64, validate=True)
    except (ValueError, base64.binascii.Error):
        return None

    if len(sig_bytes) != _ED25519_SIG_LEN:
        return None

    payload_bytes = canonicalize_payload(payload)
    return payload_bytes, sig_bytes


def write_receipt_to_disk(path: Path, receipt_json: bytes, sig: bytes) -> None:
    """Atomically write the envelope {"payload": ..., "sig": b64} to path."""
    payload = json.loads(receipt_json)
    envelope = {
        "payload": payload,
        "sig": base64.b64encode(sig).decode("ascii"),
    }
    data = json.dumps(
        envelope, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")
    _atomic_write_bytes(path, data)


def get_or_create_install_id(path: Path) -> str:
    """Return the per-install uuid v4 string, creating it if absent."""
    try:
        existing = path.read_text(encoding="utf-8").strip()
    except (FileNotFoundError, IsADirectoryError, PermissionError, OSError):
        existing = ""

    if existing:
        try:
            parsed = uuid.UUID(existing)
        except ValueError:
            parsed = None
        if parsed is not None and parsed.version == 4:
            return str(parsed)

    new_id = str(uuid.uuid4())
    _atomic_write_bytes(path, new_id.encode("utf-8"))
    return new_id


def read_high_water_mark(path: Path) -> int:
    """Return the last verified Worker-signed iat, or 0 if missing/malformed."""
    try:
        raw = path.read_text(encoding="utf-8").strip()
    except (FileNotFoundError, IsADirectoryError, PermissionError, OSError):
        return 0
    if not raw:
        return 0
    try:
        value = int(raw)
    except ValueError:
        return 0
    if value < 0:
        return 0
    return value


def write_high_water_mark(path: Path, server_time: int) -> None:
    """Atomically write max(current, server_time) as the new high-water mark.

    Monotonic: if the on-disk value is already greater than server_time,
    leave it alone (no write).
    """
    current = read_high_water_mark(path)
    if server_time <= current and path.exists():
        return
    _atomic_write_bytes(path, str(server_time).encode("utf-8"))
