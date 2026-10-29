"""Inspect the exact GPU input captured before the first packed fallback."""
from collections import deque
import hashlib
import json
import math
from pathlib import Path
import struct
import sys


def topology(raw):
    if len(raw) != 65536 * 32:
        raise ValueError("Expected 256 x 256 x 8 float32 input")
    cells = list(struct.iter_unpack("<8f", raw))
    # GLSL compares float32 operands; Python's double literal is slightly smaller.
    wet_threshold = struct.unpack("<f", struct.pack("<f", .001))[0]
    wet = bytearray(c[2] > wet_threshold and c[6] < .5 for c in cells)
    invalid = [i for i, c in enumerate(cells) if not all(math.isfinite(v) for v in c[:7]) or c[2] < 0 or c[3] < 0]
    runs = []
    for z in range(256):
        row = wet[z*256:(z+1)*256]
        runs.append(sum(v and (x == 0 or not row[x-1]) for x, v in enumerate(row)))
    seen = bytearray(65536)
    sizes = []
    for seed in range(65536):
        if not wet[seed] or seen[seed]:
            continue
        seen[seed] = 1
        queue = deque([seed])
        size = 0
        while queue:
            i = queue.popleft()
            size += 1
            neighbors = []
            if i % 256: neighbors.append(i-1)
            if i % 256 < 255: neighbors.append(i+1)
            if i >= 256: neighbors.append(i-256)
            if i < 65280: neighbors.append(i+256)
            for j in neighbors:
                if wet[j] and not seen[j]:
                    seen[j] = 1
                    queue.append(j)
        sizes.append(size)
    return {"invalid_cells": invalid, "wet_cells": sum(wet), "component_count": len(sizes),
            "largest_component": max(sizes, default=0), "component_sizes": sizes,
            "max_runs_per_row": max(runs), "rows_over_eight": [i for i, n in enumerate(runs) if n > 8],
            "runs_per_row": runs,
            "raised_wet_cells": sum(wet[i] and c[1] > c[0] for i, c in enumerate(cells))}


def analyze(path):
    data = path.read_bytes()
    if len(data) != 144 + 65536*32:
        raise ValueError("Unexpected witness layout")
    serial, groups = struct.unpack_from("<2I", data)
    receipt = list(struct.unpack_from("<32I", data, 16))
    if serial == 0:
        result = {"captured": False, "note": "No actual packed fallback observed."}
    else:
        evidence = topology(data[144:])
        reason = "packed_audit_or_other"  # Do not infer a capacity failure without input evidence.
        if evidence["invalid_cells"]: reason = "invalid_input"
        elif not evidence["wet_cells"]: reason = "no_wet_cells"
        elif evidence["rows_over_eight"]: reason = "more_than_eight_runs_in_a_row"
        elif evidence["component_count"] > 32: reason = "more_than_32_components"
        result = {"captured": True, "serial": serial, "indirect_groups": groups,
                  "receipt_words": receipt, "reason": reason, "topology": evidence}
    result.update({"path": str(path), "sha256": hashlib.sha256(data).hexdigest(),
                   "layout": "144-byte header including packed receipt, then 256x256x8 LE float32 input",
                   "scope": "CPU recount of the exact first-fallback GPU input, before generic displacement; not a later texture snapshot."})
    path.with_suffix(".json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ["topology", "receipt_words"]}, indent=2))
    if serial:
        print(json.dumps({k: v for k, v in evidence.items() if k not in ["component_sizes", "runs_per_row", "invalid_cells"]}))


if __name__ == "__main__":
    analyze(Path(sys.argv[1]))
