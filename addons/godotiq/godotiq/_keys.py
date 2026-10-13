"""Ed25519 public verifier set for signed receipts.

Consumed by :mod:`godotiq.receipt` (section 07). Each entry maps a
``kid`` to a 32-byte raw Ed25519 public key. The release process
updates this mapping to bundle new public keys at rotation time
(see ``docs/runbooks/signing-key-rotation.md`` from section 13).

Accepted risk: an attacker with write access to site-packages can
replace this module with their own pubkeys and forge matching
receipts. This is out of scope for 0.5.0 because filesystem write to
site-packages implies full code execution already (see
``claude-plan.md`` §3.2 and §10).
"""

from __future__ import annotations


KID_TO_PUBKEY: dict[str, bytes] = {
    # Current Ed25519 verifier key for Worker-signed receipts.
    # Generated during AC-4b and must stay in raw 32-byte literal form
    # so cross-runtime tests can parse the shipped map directly.
    "k1-2026-04": b"\xcd\xaf\x20\xb2\x2f\x5f\x6a\xaa\x99\xc0\xab\x59\x98\xa3\xb3\xbf\x12\x72\xc2\xf6\x11\x90\x4d\xf4\x1b\x30\x09\x3e\x73\x7b\x77\x87",
}
