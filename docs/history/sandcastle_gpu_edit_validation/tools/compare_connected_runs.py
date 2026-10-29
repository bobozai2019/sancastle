"""Compare native topology probe outputs; only private water path word27 differs."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("baseline", type=Path)
p.add_argument("candidate", type=Path)
a = p.parse_args()
left = {f.name: f for f in a.baseline.glob("*.bin")}
right = {f.name: f for f in a.candidate.glob("*.bin")}
rows = []
for name in sorted(left.keys() | right.keys()):
    if name not in left or name not in right:
        rows.append({"file": name, "pass": False, "reason": "missing"})
        continue
    x, y = left[name].read_bytes(), right[name].read_bytes()
    path_flag = None
    if name.endswith("_water_receipt.bin") and len(x) == len(y) == 128:
        flags = [int.from_bytes(b[108:112], "little") for b in (x, y)]
        if all(f in (0, 1) for f in flags):
            path_flag = flags
            x, y = x[:108] + bytes(4) + x[112:], y[:108] + bytes(4) + y[112:]
    rows.append({"file": name, "pass": x == y, "private_path_flags": path_flag,
                 "semantic_state": not name.endswith("_before_water_receipt.bin"),
                 "baseline_sha256": hashlib.sha256(left[name].read_bytes()).hexdigest(),
                 "candidate_sha256": hashlib.sha256(right[name].read_bytes()).hexdigest()})
report = {"pass": bool(rows) and all(r["pass"] for r in rows if r.get("semantic_state", True)),
          "raw_pass": bool(rows) and all(r["pass"] for r in rows), "pairs": len(rows),
          "semantic_pairs": sum(r.get("semantic_state", True) for r in rows),
          "scope": "native fields/bridges/oracles and completed receipts; water receipt private word27 normalized; allocated pre-command scratch receipts reported separately, no float tolerance",
          "baseline": str(a.baseline.resolve()), "candidate": str(a.candidate.resolve()), "rows": rows}
out = a.candidate / "connected_runs_binary_comparison.json"
out.write_text(json.dumps(report, indent=2), encoding="utf-8")
index = {"tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
         "result_sha256": hashlib.sha256(out.read_bytes()).hexdigest()}
(a.candidate / "connected_runs_comparison_index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
print(json.dumps({"pass": report["pass"], "raw_pass": report["raw_pass"], "pairs": len(rows),
                  "semantic_pairs": report["semantic_pairs"],
                  "failed": [r["file"] for r in rows if not r["pass"] and r.get("semantic_state", True)],
                  "scratch_before_differences": [r["file"] for r in rows if not r["pass"] and not r.get("semantic_state", True)]}))
