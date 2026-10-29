"""Locate differences in the explicitly instrumented split-list execution."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("evidence", type=Path)
args = parser.parse_args()
stage_order = {"before": 0, "step": 1, "slope": 2, "commit": 3}


def order(path):
    parts = path.stem.split("_")
    return int(parts[3]), stage_order[parts[4]], parts[5]


rows = []
for path in sorted(args.evidence.glob("material_active_substep_*.bin"), key=order):
    worker = path.with_name(path.name.replace("material_active_", "material_worker_", 1))
    left, right = path.read_bytes(), worker.read_bytes()
    field = path.stem.split("_")[-1]
    dtype = "u1" if field == "obstacle" else "<f2" if field in ("wetness", "compaction") else "<f4"
    a, b = np.frombuffer(left, dtype=dtype), np.frombuffer(right, dtype=dtype)
    width = np.dtype(dtype).itemsize
    unequal = np.flatnonzero(np.any(np.frombuffer(left, dtype="u1").reshape(-1, width) !=
                                   np.frombuffer(right, dtype="u1").reshape(-1, width), axis=1))
    rows.append({"key": path.stem.removeprefix("material_active_"), "equal": left == right,
                 "active_sha256": hashlib.sha256(left).hexdigest(), "worker_sha256": hashlib.sha256(right).hexdigest(),
                 "different_components": len(unequal), "max_abs": float(np.max(np.abs(a.astype(float)-b.astype(float)))),
                 "samples": [{"cell": int(i), "active": float(a[i]), "worker": float(b[i])} for i in unequal[:8]]})
metadata = [json.loads((args.evidence / f"material_{label}_metadata.json").read_text(encoding="utf-8"))
            for label in ("active", "worker")]
result = {"pairs": len(rows), "equal_pairs": sum(row["equal"] for row in rows),
          "metadata_equal": metadata[0] == metadata[1], "first_difference": next((row for row in rows if not row["equal"]), None),
          "rows": rows, "scope": "Default-off split-list GPU copies; not default first-divergence evidence."}
(args.evidence / "material_stage_analysis.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps({key: value for key, value in result.items() if key != "rows"}, indent=2))
