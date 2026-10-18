"""Terminal candidate guards must not allocate any RID or reopen admission."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh output required")
    manifest_path = args.run/"run-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    checks = []

    def check(label, passed):
        checks.append({"name": label, "pass": bool(passed)})

    check("manifest_pass", manifest["pass"] and not manifest["drift"])
    check("complete_early_matrix", [r["case"] for r in manifest["runs"]] == ["early_cancel", "early_release", "early_release_unconfigured"])
    for path, expected in manifest["sources"].items():
        check("source_"+path, sha(ROOT/path) == expected.lower())
    for run in manifest["runs"]:
        case = run["case"]
        path = Path(run["result"])
        check(case+"_report_identity", sha(path) == run["result_sha256"].lower())
        probe = json.loads(path.read_text(encoding="utf-8-sig"))
        check(case+"_probe_pass", run["pass"] and run["exit_code"] == 0 and probe["pass"] and all(c["pass"] for c in probe["checks"]))
        sample = probe["observations"]["sample"]
        check(case+"_eight_owner_groups_zero", len(sample["owners"]) == 8 and all(v == 0 for v in sample["owners"].values()))
        check(case+"_released_never_ready", sample["released"] and not sample["ready"])
        check(case+"_no_fake_gpu_proof", sample["idle_serial"] == 0 and sample["idle_receipt_hex"] == "")
        check(case+"_terminal_flags", (sample["initialized"] and sample["initialization_started"] and sample["fault"] == "initialization_cancelled") if case == "early_cancel" else (not sample["initialized"] and not sample["initialization_started"] and sample["fault"] == ""))
        for name in ("stdout.txt", "probe.log"):
            log = (path.parent/name).read_text(encoding="utf-8-sig")
            check(case+"_clean_"+name, "SCRIPT ERROR:" not in log and "\nERROR:" not in log and "were leaked" not in log and "was leaked" not in log)
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "manifest": str(manifest_path.resolve()), "manifest_sha256": sha(manifest_path), "auditor_sha256": sha(Path(__file__)), "scope": "Early cancellation/release terminal flags, eight zero RID owners and no late reallocation; no formal scene shutdown claim."}
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failed": [c["name"] for c in checks if not c["pass"]]}))
    raise SystemExit(0 if report["pass"] else 1)


if __name__ == "__main__":
    main()
