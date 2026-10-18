"""Independent native checkpoint/readback/physics/continuation byte audit."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
EPOCH = 9007199254740994
CASES = ["restore_native", "restore_distinct", "restore_cohesion", "restore_hold", "restore_cancel", "restore_registration", "restore_corrupt", "restore_unknown"]
FAILURES = {"restore_cancel": "initialization_cancelled", "restore_registration": "restore_readback_registration", "restore_corrupt": "restore_readback_mismatch", "restore_unknown": "restore_readback_registration"}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cases", nargs="+", choices=CASES)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh audit required")
    checks = []

    def check(label, value):
        checks.append({"name": label, "pass": bool(value)})

    def raw(meta, label):
        data = Path(meta["path"]).read_bytes()
        check(label+"_raw_identity", len(data) == meta["bytes"] and sha(data) == meta["sha256"].lower())
        return data

    manifest_path = args.run/"run-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    check("run_pass_without_drift", manifest["pass"] and not manifest["drift"])
    selected = args.cases if args.cases is not None else CASES
    check("requested_restore_matrix", [r["case"] for r in manifest["runs"]] == selected)
    for relative, expected in manifest["sources"].items():
        check("source_"+relative, sha((ROOT/relative).read_bytes()) == expected.lower())
    for run in manifest["runs"]:
        case = run["case"]
        probe_data = Path(run["result"]).read_bytes()
        check(case+"_probe_identity", sha(probe_data) == run["result_sha256"].lower())
        probe = json.loads(probe_data)
        check(case+"_probe_pass", run["pass"] and run["exit_code"] == 0 and probe["pass"] and all(c["pass"] for c in probe["checks"]))
        obs = probe["observations"]
        cohesion = obs["cohesion"]
        ordinary = .025 if case == "restore_cohesion" else 0.0
        check(case+"_ordinary_cohesion_metadata", all(cohesion[key] == ordinary for key in ("environment", "checkpoint", "source_state", "candidate_state")))
        source_push = bytes.fromhex(cohesion["source_push_hex"])
        candidate_push = bytes.fromhex(cohesion["candidate_push_hex"])
        check(case+"_actual_cohesion_push_constants", len(source_push) == 48 and source_push == candidate_push and source_push[28:32] == struct.pack("<f", ordinary) and source_push[32:36] == struct.pack("<f", .9))
        check(case+"_late_callbacks_do_not_recomplete", obs["late_callbacks"]["before"] == obs["late_callbacks"]["after"] and obs["late_callbacks"]["after"]["pending"] == 0)
        source = {k: raw(v, case+"_source_"+k) for k, v in obs["source"].items()}
        active = {k: raw(v, case+"_active_"+k) for k, v in obs["active_after_candidate"].items()}
        check(case+"_original_domain_not_replaced_or_mutated", source == active)
        fixture = {k: raw(v, case+"_fixture_"+k) for k, v in obs["native_fixture"].items()}
        control = bytearray(fixture["control"])
        check(case+"_original_int64_generation", struct.unpack_from("<q", control, 8)[0] == 9007199254740993)
        check(case+"_captured_actual_state_clock", struct.unpack_from("<q", control, 16)[0] == 2 and struct.unpack_from("<q", control, 24)[0] == 1 and struct.unpack_from("<f", control, 32)[0] > 0)
        changed = {"field/wetness", "field/compaction", "spare/wetness", "spare/compaction", "spare/momentum_x", "spare/momentum_z", "spare/flux"} if case == "restore_distinct" else set()
        for key, data in fixture.items():
            if key not in changed:
                check(case+"_fixture_from_real_gpu_"+key, data == source[key])
        if case == "restore_distinct":
            codes = np.concatenate([np.arange(0x3c01, dtype="<u2"), np.array([0x8000], dtype="<u2")])
            for prefix in ("field/", "spare/"):
                for field in ("wetness", "compaction"):
                    indices = np.arange(65536)
                    if field == "compaction":
                        indices = indices[::-1]
                    check(case+"_all_native_half_codes_"+prefix+field, fixture[prefix+field] == codes[indices % codes.size].tobytes())
            for field in ("momentum_x", "momentum_z", "flux"):
                data = fixture["spare/"+field]
                check(case+"_distinct_spare_"+field, data != fixture["field/"+field] and struct.unpack_from("<II", data) == (0x80000000, 1))
        container = Path(obs["container"]["path"]).read_bytes()
        check(case+"_container_identity", sha(container) == obs["container"]["sha256"])
        check(case+"_real_container_checksum", container[:8] == b"SANDUE06" and struct.unpack_from("<I", container, 8)[0] == 1 and struct.unpack_from("<I", container, 12)[0] == len(container)-48 and sha(container[48:]) == container[16:48].hex())
        check(case+"_container_contains_native_payloads", all(data in container[48:] for data in fixture.values()))
        struct.pack_into("<q", control, 8, EPOCH)
        expected = {k: v for k, v in fixture.items()}
        expected["control"] = bytes(control)
        expected["publication_stamp"] = struct.pack("<qqqq", EPOCH, struct.unpack_from("<q", control, 16)[0], struct.unpack_from("<q", control, 40)[0], struct.unpack_from("<q", control, 24)[0])
        expected["clock"] = bytes(control[32:36])
        expected["executor_stroke"] = expected["view_stroke"] = bytes(64)
        for field in ("sand", "water"):
            expected["published/"+field] = fixture["field/"+field]
        for field in ("sediment", "momentum_x", "momentum_z", "wetness", "compaction", "mold_support", "flux", "baseline"):
            expected["view/"+field] = fixture["material/0"] if field == "mold_support" else bytes(65536*4) if field == "baseline" else fixture["field/"+field]
        check(case+"_complete_35_readbacks", len(expected) == 35)
        verification = obs["verification"]
        captured = {k: raw(v, case+"_verified_"+k) for k, v in verification["captured"].items()}
        missing = set(expected)-set(captured)
        mismatch = set()
        for key, data in captured.items():
            record = verification["records"][key]
            equal = data == expected[key]
            check(case+"_record_matches_raw_"+key, record["bytes"] == len(data) and record["actual_sha256"] == sha(data) and record["expected_sha256"] == sha(expected[key]) and record["matched"] == equal)
            if not equal:
                mismatch.add(key)
        if case in ("restore_registration", "restore_unknown"):
            check(case+"_actual_missing_registration", missing == {"field/rock"} and not mismatch and not verification["passed"] and verification["error"] == "restore_readback_registration")
        elif case == "restore_corrupt":
            check(case+"_one_corrupt_callback", not missing and len(mismatch) == 1 and not verification["passed"] and verification["error"] == "restore_readback_mismatch")
        else:
            check(case+"_all_native_bytes_exact", not missing and not mismatch and verification["passed"] and verification["error"] == "")
        if case in ("restore_hold", "restore_cancel"):
            held = obs["held"]
            check(case+"_pending_cannot_become_ready", held["count"] == 35 and held["pending"] == 35 and not held["initialized"] and not held["ready"] and all(v > 0 for v in held["owners"].values()))
            check(case+"_duplicates_cannot_release_pending_reads", obs["duplicate_held"]["before"] == obs["duplicate_held"]["after"] and obs["duplicate_held"]["after"]["pending"] == 35)
        if case == "restore_unknown":
            unknown = obs["unknown"]
            check(case+"_unknown_retains_every_owner", unknown["owners"] == unknown["original_owners"] and all(v > 0 for v in unknown["owners"].values()) and not unknown["released"] and unknown["unknown"])
        check(case+"_all_owners_finally_zero", len(obs["final_ownership"]) == 8 and all(v == 0 for v in obs["final_ownership"].values()))
        check(case+"_final_fault", obs["final_fault"] == FAILURES.get(case, ""))
        cleanup = obs["cleanup"]
        check(case+"_cleanup_no_unacknowledged_owner", not cleanup["pending"] and not cleanup["unknown"] and not cleanup["idle_pending"] and cleanup["verifier_pending"] == 0 and not cleanup["has_owned_work"] and cleanup["height_active"] == 0)
        if case in FAILURES:
            check(case+"_actual_terminal_idle_receipt", bytes.fromhex(cleanup["idle_receipt_hex"]) == struct.pack("<IIq", 0x31464c49, 0, 1) and cleanup["idle_serial"] == 1 and "unexpected_cleanup" not in obs)
        if case not in FAILURES:
            maps = np.frombuffer(raw(obs["physics"]["maps"], case+"_physics"), dtype="<f4").reshape(64, 33, 33)
            bed = np.frombuffer(fixture["field/rock"], dtype="<f4").reshape(256, 256)+np.frombuffer(fixture["field/sand"], dtype="<f4").reshape(256, 256)
            for chunk in range(64):
                z = np.minimum(255, chunk//8*32+np.arange(33))
                x = np.minimum(255, chunk%8*32+np.arange(33))
                check(case+f"_actual_physics_chunk_{chunk}", maps[chunk].tobytes() == bed[np.ix_(z, x)].tobytes() and obs["physics"]["state_seq"][str(chunk)] == struct.unpack_from("<q", control, 16)[0])
            second = obs["second"]
            left = {k: raw(v, case+"_second_source_"+k) for k, v in second["source"].items()}
            right = {k: raw(v, case+"_second_candidate_"+k) for k, v in second["candidate"].items()}
            check(case+"_continuation_gpu_result", second["result"]["generation"] == EPOCH and second["result"]["command_id"] == 43 and second["result"]["outcome"] == 1)
            check(case+"_restored_clock_advances_once", second["tick"] == 2 and second["state_seq"] == 4 and second["time_s"] > struct.unpack_from("<f", control, 32)[0])
            if case != "restore_distinct":
                for key in left:
                    expected_data = bytearray(left[key])
                    if key in ("control", "stamp"):
                        struct.pack_into("<q", expected_data, 8 if key == "control" else 0, EPOCH)
                    check(case+"_identical_uninterrupted_continuation_"+key, bytes(expected_data) == right[key])
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "cases": selected, "full_matrix": selected == CASES, "manifest": str(manifest_path.resolve()), "manifest_sha256": sha(manifest_path.read_bytes()), "auditor_sha256": sha(Path(__file__).read_bytes()), "scope": "Only the explicitly listed cases: actual native container/raw fields, initialized GPU bytes, relevant boundary/physics/continuation and failure ownership checks. No omitted-case, formal atomic domain swap or enabled effects/boundary restore claim."}
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failed": [c["name"] for c in checks if not c["pass"]]}))
    raise SystemExit(0 if report["pass"] else 1)


if __name__ == "__main__":
    main()
