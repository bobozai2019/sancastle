"""Compare fixed inputs and authoritative outputs of two separately run probes."""
import argparse
import hashlib
import json
from pathlib import Path

OUTPUTS = ["sand0", "sand1", "support0", "support1", "compact0", "compact1", "baseline", "coverage", "published"]
INITIAL = ["rock", "sand0", "sand1", "water", "obstacle", "support0", "support1", "compact0", "compact1", "published"]
RECEIPTS = ["outcome", "error_code", "input_revision", "output_revision", "changed_fields", "changed_cells", "touched_cells", "dirty_low", "dirty_high", "coverage_changed", "added_m3", "removed_m3", "transferred_m3", "left_received_m3", "right_received_m3", "source_m3", "sink_m3", "sand_error_m3", "eps_sand_m3", "eps_transfer_m3"]


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(meta):
    data = Path(meta["path"]).read_bytes()
    value = hashlib.sha256(data).hexdigest()
    if len(data) != meta["bytes"] or value != meta["sha256"]:
        raise ValueError("Raw evidence changed: "+meta["path"])
    return value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--left", type=Path, required=True)
    parser.add_argument("--right", type=Path, required=True)
    parser.add_argument("--case", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh output required")
    args.output.mkdir(parents=True)
    left, right = load(args.left/"run-manifest.json"), load(args.right/"run-manifest.json")
    left_run, = [r for r in left["runs"] if r["case"] == args.case]
    right_run, = [r for r in right["runs"] if r["case"] == args.case]
    a, b = load(Path(left_run["result"])), load(Path(right_run["result"]))
    checks = []

    def check(name, passed):
        checks.append({"name": name, "pass": bool(passed)})

    normalize = lambda sources: {k.replace("\\", "/"): v.lower() for k, v in sources.items()}
    check("same_all_pinned_sources", normalize(left["sources"]) == normalize(right["sources"]))
    check("both_gpu_runs_pass", left["pass"] and right["pass"] and a["pass"] and b["pass"])
    check("same_case_count", len(a["cases"]) == len(b["cases"]))
    for name in INITIAL:
        check("same_initial_"+name, digest(a["cases"][0]["before"][name]) == digest(b["cases"][0]["before"][name]))
    for ca, cb in zip(a["cases"], b["cases"]):
        label = ca["label"]
        check(label+"_same_wire", label == cb["label"] and ca["wire"] == cb["wire"])
        check(label+"_same_public_semantics", all(ca["result"][k] == cb["result"][k] for k in RECEIPTS))
        for field in OUTPUTS:
            check(label+"_same_"+field, digest(ca["after"][field]) == digest(cb["after"][field]))
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "case": args.case, "left": str(args.left), "right": str(args.right), "pinned_source_count": len(left["sources"]), "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Same pinned sources, actual initial physical fields, profile wire and ordered commands across two separately initialized GPU runs. Actual physical/publication/coverage/baseline bytes and public quantities; volatile slot/lease metadata excluded."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks)}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
