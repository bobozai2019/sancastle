"""Locate the retained swept-template precision failure in raw f32/f64 pairs."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("run", type=Path)
args = parser.parse_args()
rows = []
for size in (64, 256):
    prefix = f"{size}_swept_0.5"
    paths = [args.run / (prefix + suffix) for suffix in (
        "_after_momentum_x.bin", "_after_momentum_z.bin",
        "_oracle_f64_qx.bin", "_oracle_f64_qz.bin")]
    gx, gz = [np.fromfile(p, dtype="<f4").astype(np.float64) for p in paths[:2]]
    ex, ez = [np.fromfile(p, dtype="<f8") for p in paths[2:]]
    error = np.maximum(np.abs(gx - ex), np.abs(gz - ez))
    indices = np.flatnonzero(error > 2e-7)
    rows.append({"grid": size, "maximum_error_m2_s": float(error.max()),
        "over_2e7_floor_cells": [{"index": int(i), "x": int(i % size), "z": int(i // size),
            "gpu_q": [float(gx[i]), float(gz[i])], "oracle_q": [float(ex[i]), float(ez[i])],
            "error_m2_s": float(error[i])} for i in indices],
        "sources": [{"path": p.name, "bytes": p.stat().st_size,
            "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]})
report = {"scope": "forensic locations; original matrix retains the full ULP pass/fail", "rows": rows,
    "numpy_version": np.__version__, "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(args.run / "swept_precision_forensics.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps({"grids": len(rows), "over_floor_cells": sum(len(r["over_2e7_floor_cells"]) for r in rows)}))
