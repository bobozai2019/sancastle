"""Independently decode saved containers and audit producer/ledger boundaries."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

import numpy as np

from native_variant import VariantReader

ROOT = Path(__file__).resolve().parents[2]
CASES = ["checkpoint_queued", "checkpoint_recorded", "checkpoint_completed", "checkpoint_physics", "checkpoint_capacity", "checkpoint_held", "checkpoint_registration", "checkpoint_unknown", "checkpoint_truncate", "checkpoint_corrupt", "checkpoint_cancel", "checkpoint_cancel_read", "checkpoint_close", "checkpoint_existing", "checkpoint_identity", "checkpoint_upload", "checkpoint_readback", "checkpoint_receiver", "checkpoint_quantized"]
SUCCESS = set(CASES[:6]+["checkpoint_receiver", "checkpoint_quantized"])
ERRORS = {"checkpoint_registration": "checkpoint_readback_registration", "checkpoint_unknown": "checkpoint_readback_registration", "checkpoint_truncate": "checkpoint_readback_size", "checkpoint_corrupt": "checkpoint_immutable_field_mismatch", "checkpoint_cancel": "checkpoint_cancelled", "checkpoint_cancel_read": "checkpoint_cancelled", "checkpoint_close": "checkpoint_cancelled", "checkpoint_identity": "identity_exhausted", "checkpoint_upload": "upload_failed", "checkpoint_readback": "readback_submit_failed"}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cases", nargs="+", choices=CASES, help="Explicit affected subset; omission requires the full production matrix")
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh audit required")
    checks = []
    decoded_headers = []

    def check(name, passed):
        checks.append({"name": name, "pass": bool(passed)})

    def raw(meta, label):
        data = Path(meta["path"]).read_bytes()
        check(label+"_identity", len(data) == meta["bytes"] and sha(data) == meta["sha256"].lower())
        return data

    manifest_path = args.run/"run-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    check("manifest_pass_without_drift", manifest["pass"] and not manifest["drift"])
    check("explicit_production_matrix", [r["case"] for r in manifest["runs"]] == (args.cases or CASES))
    for path, expected in manifest["sources"].items():
        check("current_source_"+path, sha((ROOT/path).read_bytes()) == expected.lower())
    for run in manifest["runs"]:
        case = run["case"]
        path = Path(run["result"])
        check(case+"_report_identity", sha(path.read_bytes()) == run["result_sha256"].lower())
        report = json.loads(path.read_text(encoding="utf-8-sig"))
        check(case+"_probe_pass", run["pass"] and run["exit_code"] == 0 and report["pass"] and all(c["pass"] for c in report["checks"]))
        obs = report["observations"]
        exact = VariantReader(raw(report["exact_accounting"], case+"_exact_accounting")).document()
        # Godot's JSON diagnostic output rounds f64 values. All arithmetic and
        # receipt comparisons below use the original typed Variant values.
        for key in ("header", "recorded", "second_header", "continued", "ledger"):
            if exact[key]:obs[key] = exact[key]
        obs["results"] = {str(k): v for k, v in exact["results"].items()}
        check(case+"_all_eight_owners_zero", len(obs["final_ownership"]) == 8 and all(n == 0 for n in obs["final_ownership"].values()))
        for name in ("probe.log", "stdout.txt"):
            log = (path.parent/name).read_text(encoding="utf-8-sig")
            check(case+"_clean_"+name, "SCRIPT ERROR:" not in log and "\nERROR:" not in log and "were leaked" not in log and "was leaked" not in log)
        if case == "checkpoint_existing":
            before = {k: raw(v, case+"_before_"+k) for k, v in obs["before_refusal"].items()}
            after = {k: raw(v, case+"_after_"+k) for k, v in obs["after_refusal"].items()}
            check(case+"_no_gpu_side_effect", before == after and struct.unpack_from("<I", after["stroke"])[0] == 1)
            sentinel = path.parent/"production.sandue"
            check(case+"_existing_bytes_not_overwritten", sentinel.read_bytes() == b"sentinel" and sha(sentinel.read_bytes()) == obs["existing"]["sha256"])
            continue
        after = {k: raw(v, case+"_after_"+k) for k, v in obs["after"].items()}
        info = obs["info"]
        check(case+"_callback_once", obs["callbacks"] == (0 if case == "checkpoint_receiver" else 1))
        if case in ("checkpoint_held", "checkpoint_cancel_read", "checkpoint_close", "checkpoint_receiver"):
            check(case+"_26_borrowers_before_delivery", obs["held"]["status"]["pending"] == 26 and obs["held"]["callbacks"] == 0 and all(n > 0 for n in obs["held"]["owners"].values()))
        if case == "checkpoint_unknown":
            unknown = obs["unknown"]
            check(case+"_unknown_retains_all_owners", unknown["status"]["unknown"] and unknown["status"]["pending"] == 0 and unknown["callbacks"] == 0 and not unknown["released"] and all(n > 0 for n in unknown["owners"].values()))
        if case not in SUCCESS:
            check(case+"_failure_does_not_create_file", obs["failure"]["error"] == ERRORS[case] and not (path.parent/"production.sandue").exists())
            if case in ("checkpoint_registration", "checkpoint_unknown", "checkpoint_truncate", "checkpoint_cancel_read", "checkpoint_close"):
                check(case+"_ordered_lifetime_proof", bytes.fromhex(obs["failure"]["idle_receipt_hex"]) == struct.pack("<IIq", 0x31464c49, 0, 1) and obs["failure"]["idle_serial"] == 1)
            if case == "checkpoint_registration" or case == "checkpoint_unknown":
                check(case+"_exact_missing_reader", info["registered"] == 25 and set(after)-set(info["records"]) == {"field/rock"})
            if case == "checkpoint_corrupt":
                expected = bytearray(after["field/rock"]);expected[0] ^= 1
                check(case+"_actual_immutable_byte_corruption", info["records"]["field/rock"]["sha256"] == sha(expected) and info["registered"] == 26)
            if case == "checkpoint_truncate":
                check(case+"_one_short_readback", sum(r["bytes"] == 1 for r in info["records"].values()) == 1 and info["registered"] == 26)
            if case == "checkpoint_identity":
                before = {k: raw(v, case+"_before_"+k) for k, v in obs["before_refusal"].items()}
                check(case+"_no_identity_wrap_or_gpu_end", before == after and struct.unpack_from("<I", after["stroke"])[0] == 1 and info["highwater_id"] == 2**63-1 and info["registered"] == 0)
            if case == "checkpoint_cancel":
                check(case+"_queued_cancel_keeps_original_stroke", info["registered"] == 0 and info["end_id"] == 0 and struct.unpack_from("<I", after["stroke"])[0] == 1)
            if case in ("checkpoint_upload", "checkpoint_readback"):
                check(case+"_no_snapshot_from_work_fault", info["registered"] == 0 and obs["ledger"]["values"]["sand_source_m3"] == (0 if case == "checkpoint_upload" else .1))
                if case == "checkpoint_upload":
                    check(case+"_known_unrecorded_have_terminal_status", all(obs["results"][str(i)]["cancelled"] and not obs["results"][str(i)]["submitted"] for i in (1, 2, 3)))
                else:
                    check(case+"_unknown_does_not_fabricate_gpu_results", all(str(i) not in obs["results"] for i in (1, 2, 3)))
            continue

        container = Path(obs["container"]["path"]).read_bytes()
        check(case+"_container_identity", sha(container) == obs["container"]["sha256"])
        check(case+"_real_complete_container", container[:8] == b"SANDUE06" and struct.unpack_from("<II", container, 8) == (1, len(container)-48) and sha(container[48:]) == container[16:48].hex())
        value = VariantReader(container[48:]).document()
        control = bytes(value["native"]["control"])
        for offset, key in [(8, "generation"), (16, "state_seq"), (24, "sim_tick"), (40, "revision")]:
            check(case+"_gpu_counter_"+key, value[key] == struct.unpack_from("<q", after["control"], offset)[0] and control == after["control"])
        check(case+"_actual_f32_clock", value["advanced_time_s"] == struct.unpack_from("<f", control, 32)[0] and after["clock"] == control[32:36])
        check(case+"_actual_published_stamp", after["stamp"] == struct.pack("<qqqq", value["generation"], value["state_seq"], value["revision"], value["sim_tick"]))
        for group, prefix in (("fields", "field/"), ("spare", "spare/")):
            for field, data in value["native"][group].items():
                check(case+"_container_exact_"+prefix+field, data == after[prefix+field])
        for i, name in enumerate(("current_support", "spare_support")):
            check(case+"_actual_material_"+name, value["native"]["material"][name] == after[f"material/{i}"])
        check(case+"_only_closed_stroke_saved", struct.unpack_from("<I", after["stroke"])[0] == 0)
        for key, record in info["records"].items():
            check(case+"_readback_record_"+key, record["bytes"] == len(after[key]) and record["sha256"] == sha(after[key]))
        check(case+"_all_26_readbacks", info["registered"] == 26 and set(info["records"]) == set(after))
        highwater = 513 if case == "checkpoint_capacity" else 9
        check(case+"_internal_end_no_result_reservation", value["highwater_id"] == highwater and info["end_id"] == highwater and str(highwater) not in obs["results"] and obs["reservations"] == len(obs["results"]) == (512 if case == "checkpoint_capacity" else 8))
        end = info["end_result"]
        check(case+"_end_is_a_real_common_gpu_result", end["command_id"] == highwater and end["state_seq"] == value["state_seq"] and end["outcome"] == 2 and end["ledger"] == 3 and end["source_m3"] == end["sink_m3"] == 0)
        target = float(obs["results"]["2" if case == "checkpoint_capacity" else "8"]["source_m3"])
        nominal = (0.01*.7+.05) if case == "checkpoint_quantized" else .1
        expected_source = target+(0 if case == "checkpoint_capacity" else nominal)
        expected_sink = 0 if case == "checkpoint_capacity" else .04
        check(case+"_mixed_ledger_semantics", value["ledger"]["sand_source_m3"] == expected_source and value["ledger"]["sand_sink_m3"] == expected_sink and value["ledger"]["tool_inventory_m3"] == 0)
        if case == "checkpoint_quantized":
            gpu = np.float32(np.float32(.01)*np.float32(.7))
            old = np.float32(.01*.7)
            check(case+"_real_f32_parameter_product", gpu.tobytes() != old.tobytes() and obs["results"]["1"]["source_m3"] == float(gpu))
            rounded_history = float(gpu)+float(np.float32(.05))+target
            check(case+"_f64_history_not_replaced_by_gpu_rounding", expected_source != rounded_history and value["ledger"]["sand_source_m3"] == expected_source)
        check(case+"_f64_water_history_exact", value["ledger"]["water_source_m3"] == .123456789012345 and value["ledger"]["water_sink_m3"] == .023456789012345)
        check(case+"_rejected_and_cancelled_are_distinct", case == "checkpoint_capacity" or (obs["results"]["2"]["outcome"] == 3 and obs["results"]["4"]["cancelled"]))
        check(case+"_selection_was_frozen", value["selection"]["brush"]["fill_amount_m3"] == .05)
        initial = {k: raw(v, case+"_initial_"+k) for k, v in obs["initial"].items()}
        total = sum(float(x) for x in np.frombuffer(initial["sand"], dtype="<f4"))+sum(float(x) for x in np.frombuffer(initial["sediment"], dtype="<f4"))
        check(case+"_initial_sand_total", value["initial_sand_total_m3"] == total*.015625)
        bed_seed = np.frombuffer(initial["rock"], dtype="<f4")+np.frombuffer(initial["sand"], dtype="<f4")
        foam = value["native"]["foam"]
        check(case+"_disabled_history_is_preserved_cpu_seed", bytes(foam["foam_0"]) == bytes(foam["foam_1"]) == bytes(65536*8) and foam["bed_0"] == foam["bed_1"] == bed_seed.tobytes())
        restored = {k: raw(v, case+"_restored_"+k) for k, v in obs["restored"]["native"].items()}
        for key, data in after.items():
            expected = bytearray(data)
            if key in ("control", "stamp"):
                struct.pack_into("<q", expected, 8 if key == "control" else 0, 9007199254740994)
            if key == "stroke":
                check(case+"_restored_stroke_inactive", struct.unpack_from("<I", restored[key])[0] == 0)
            else:
                check(case+"_restored_native_exact_"+key, restored[key] == bytes(expected))
        check(case+"_35_real_restore_verifications", len(obs["restored"]["records"]) == 35 and all(r["matched"] for r in obs["restored"]["records"].values()))
        maps = np.frombuffer(raw(obs["physics"]["maps"], case+"_physics"), dtype="<f4").reshape(64, 33, 33)
        bed = np.frombuffer(value["native"]["fields"]["rock"], dtype="<f4").reshape(256, 256)+np.frombuffer(value["native"]["fields"]["sand"], dtype="<f4").reshape(256, 256)
        for chunk in range(64):
            z = np.minimum(255, chunk//8*32+np.arange(33));x = np.minimum(255, chunk%8*32+np.arange(33))
            check(case+f"_actual_physics_chunk_{chunk}", maps[chunk].tobytes() == bed[np.ix_(z, x)].tobytes())
        continued = obs["continued"]
        left = {k: raw(v, case+"_continue_source_"+k) for k, v in continued["source"].items()}
        right = {k: raw(v, case+"_continue_candidate_"+k) for k, v in continued["candidate"].items()}
        for key, data in left.items():
            expected = bytearray(data)
            if key in ("control", "stamp"):
                struct.pack_into("<q", expected, 8 if key == "control" else 0, 9007199254740994)
            if key != "stroke":check(case+"_continuation_exact_"+key, bytes(expected) == right[key])
        check(case+"_ledger_after_restore_continues_once", continued["source_ledger"]["values"] == continued["candidate_ledger"]["values"] and continued["candidate_ledger"]["values"]["sand_source_m3"] == expected_source+.02)
        check(case+"_second_snapshot_not_replayed", obs["second_header"]["state_seq"] == value["state_seq"]+2 and obs["second_header"]["tick"] == value["sim_tick"]+1 and obs["second_header"]["highwater"] == highwater+1 and obs["second_header"]["ledger"] == continued["candidate_ledger"]["values"])
        if case == "checkpoint_recorded":check(case+"_known_recording_is_not_cpu_completion", obs["recorded"]["active"] == 3 and obs["recorded"]["completed_state_seq"] == 0 and obs["recorded"]["ledger"]["values"]["sand_source_m3"] == .1)
        decoded_headers.append({"case": case, "generation": value["generation"], "state_seq": value["state_seq"], "sim_tick": value["sim_tick"], "highwater_id": value["highwater_id"], "ledger": value["ledger"]})
    result = {"pass": all(c["pass"] for c in checks), "checks": checks, "decoded_headers": decoded_headers, "manifest": str(manifest_path.resolve()), "manifest_sha256": sha(manifest_path.read_bytes()), "auditor_sha256": sha(Path(__file__).read_bytes()), "variant_decoder_sha256": sha((Path(__file__).parent/"native_variant.py").read_bytes()), "scope": "Independent data-only Variant container decode, exact GPU payloads, common END/result capacity, f64/f32 ledger distinction, restored physics/continuation and capture lifetime/error boundaries. No formal main-scene handoff or enabled effects/boundary claim."}
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({"pass": result["pass"], "checks": len(checks), "failed": [c["name"] for c in checks if not c["pass"]]}))
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":
    main()
