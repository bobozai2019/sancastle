"""Audit candidate failure lifecycle reports, actual GPU receipts and exit logs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
STAGES = ["transport", "state", "executor", "water", "coupled", "height", "views"]
CASES = ["init_"+s for s in STAGES]+["init_bad_field", "init_bad_domain", "init_null_domain", "init_compile", "init_unknown"]
OWNERS = set(STAGES+["water_response"])


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh output required")
    checks = []

    def check(name, passed):
        checks.append({"name": name, "pass": bool(passed)})

    manifest_path = args.run/"run-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    check("manifest_pass_without_drift", manifest["pass"] and not manifest["drift"])
    check("complete_failure_matrix", [r["case"] for r in manifest["runs"]] == CASES)
    for relative, expected in manifest["sources"].items():
        check("source_"+relative, sha(ROOT/relative) == expected.lower())
    source_sets = []
    for run in manifest["runs"]:
        case = run["case"]
        path = Path(run["result"])
        check(case+"_identity", sha(path) == run["result_sha256"].lower())
        probe = json.loads(path.read_text(encoding="utf-8-sig"))
        check(case+"_probe_pass", run["pass"] and run["exit_code"] == 0 and probe["pass"] and all(c["pass"] for c in probe["checks"]))
        source_sets.append(probe["source_hashes"])
        for log_name in ("stdout.txt", "probe.log"):
            log = (path.parent/log_name).read_text(encoding="utf-8-sig")
            check(case+"_clean_"+log_name, "SCRIPT ERROR:" not in log and "\nERROR:" not in log and not re.search(r"RID[s]? of type .* (was|were) leaked", log))
        observation = probe["observations"]
        failure = observation["failure"]
        expected_error = ("state/initial_field_size" if case == "init_bad_field" else "initial_domain_mismatch" if case in ("init_bad_domain", "init_null_domain") else "views/query:" if case == "init_compile" else "injected_initialization/"+("views" if case == "init_unknown" else case.removeprefix("init_")))
        check(case+"_original_fault", failure["error"].startswith(expected_error) and probe["fault"].startswith(expected_error))
        before = failure["ownership_at_failure"]
        final = observation["final"]
        check(case+"_all_nested_owners_included", set(before) == OWNERS and set(final["counts"]) == OWNERS)
        check(case+"_released_owners_zero", all(v == 0 for v in final["counts"].values()) and not final["has_owned_work"] and not final["idle_pending"])
        check(case+"_duplicate_init_stays_zero", observation["duplicate_init"] == final)
        if case in ("init_bad_domain", "init_null_domain"):
            check(case+"_no_allocation_before_domain_validation", all(v == 0 for v in before.values()) and final["idle_serial"] == 0 and final["idle_receipt_hex"] == "")
        else:
            receipt = bytes.fromhex(final["idle_receipt_hex"])
            check(case+"_actual_gpu_idle_receipt", len(receipt) == 16 and struct.unpack("<IIq", receipt) == (0x31464c49, 0, 1) and final["idle_serial"] == 1)
            check(case+"_real_transport_resources_allocated", before["transport"] > 0)
        if case.removeprefix("init_") in STAGES:
            at = STAGES.index(case.removeprefix("init_"))
            check(case+"_staged_allocation_prefix", all((before[owner] > 0) == (i <= at) for i, owner in enumerate(STAGES)))
            check(case+"_nested_response_allocation", (before["water_response"] > 0) == (at >= STAGES.index("executor")))
        if case == "init_bad_field":
            check(case+"_genuine_partial_state_allocation", before["state"] > 0 and before["executor"] == 0)
        if case == "init_compile":
            check(case+"_real_glsl_rejection", "deliberately_invalid_token" in observation["compiler_source"] and "deliberately_invalid_token" in observation["compiler_error"] and len(observation["compiler_error"]) > 40 and before["views"] > 0)
        if case == "init_unknown":
            for phase in ("unknown", "after_blocked_release"):
                sample = observation[phase]
                check(case+"_"+phase+"_retains_every_owner", sample["counts"] == before and all(v > 0 for v in before.values()) and sample["idle_serial"] == 0 and sample["idle_receipt_hex"] == "" and not sample["has_owned_work"])
            check(case+"_reports_unknown_without_fake_release", failure["unknown"] and not failure["released"] and not failure["pending"])
        else:
            check(case+"_known_cleaned_before_reporting_failure", failure["released"] and not failure["unknown"] and not failure["pending"])
    common = set.intersection(*(set(s) for s in source_sets))
    check("all_cases_common_runtime_identity", all(len({s[path] for s in source_sets}) == 1 for path in common))
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "manifest": str(manifest_path.resolve()), "manifest_sha256": sha(manifest_path), "auditor_sha256": sha(Path(__file__)), "common_source_count": len(common), "scope": "All eight nested RID owners, seven real allocation stages, partial field input failure, actual GLSL compile rejection, GPU idle receipts, unknown retention/retry and clean owned process exit. No formal entry, atomic domain swap or full restore claim."}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "common_sources": len(common), "failed": [c["name"] for c in checks if not c["pass"]]}))
    raise SystemExit(0 if report["pass"] else 1)


if __name__ == "__main__":
    main()
