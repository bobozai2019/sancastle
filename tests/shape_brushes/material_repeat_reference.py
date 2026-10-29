"""Audit original solver repeatability without attributing failure to a candidate."""
import argparse
import hashlib
import json
from pathlib import Path


def run(output):
    root = output.parent
    records = [json.loads((root / name / "retention_evidence.json").read_text())
               for name in ["original_a", "original_b"]]
    a, b = records
    checks = []
    def check(name, passed, detail=None):
        checks.append({"name": name, "pass": bool(passed), "detail": detail})
    check("both_900_ticks", a["completed_ticks"] == b["completed_ticks"] == 900)
    check("sample_ticks_equal", [s["tick"] for s in a["samples"]] == [s["tick"] for s in b["samples"]])
    for record in records:
        for sample in record["samples"]:
            for field in sample["fields"].values():
                data = Path(field["path"]).read_bytes()
                assert len(data) == field["bytes"]
                assert hashlib.sha256(data).hexdigest() == field["sha256"]
    differences = []
    for x, y in zip(a["samples"], b["samples"]):
        bad = [name for name in x["fields"] if x["fields"][name]["sha256"] != y["fields"][name]["sha256"]]
        check("old_25_exact_tick_" + str(x["tick"]), not bad, bad)
        if bad:
            differences.append({"tick": x["tick"], "fields": bad})
    traces = {}
    for key in ["substeps", "cfl_inputs"]:
        bad = [{"index": i, "a": x, "b": y} for i, (x, y) in enumerate(zip(a[key], b[key])) if x != y]
        traces[key] = {"length_a": len(a[key]), "length_b": len(b[key]), "first_difference": bad[0] if bad else None}
        check(key + "_exact", a[key] == b[key], traces[key])
    result = {"pass": all(c["pass"] for c in checks), "checks": checks,
              "raw_differences": differences, "trace_comparison": traces,
              "scope": "Original solver repeatability diagnosis only; no material acceptance or cause attribution."}
    (output / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result["pass"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    passed = run(args.output)
    print("ORIGINAL_MATERIAL_REPEAT", passed)
    raise SystemExit(0 if passed else 1)
