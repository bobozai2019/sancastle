"""Recheck saved GPU fields/control without trusting probe PASS labels."""
import argparse
import hashlib
import json
import pathlib
import struct


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh audit output required")
    manifest = json.loads((args.run / "run-manifest.json").read_text(encoding="utf-8-sig"))
    records, failures = [], []
    expected_flags = {"fatal": 8, "counter": 32, "tick_counter": 48, "revision_counter": 32, "bad_cfl": 16}
    for run in manifest["runs"]:
        case = run["case"]
        result_bytes = pathlib.Path(run["result"]).read_bytes()
        if hashlib.sha256(result_bytes).hexdigest().lower() != run["result_sha256"].lower():
            failures.append(case + ":result_digest")
        data = json.loads(result_bytes.decode("utf-8-sig"))
        fields = data.get("raw_fields", {})
        for field, meta in fields.items():
            payload = pathlib.Path(meta["path"]).read_bytes()
            if len(payload) != meta["bytes"] or hashlib.sha256(payload).hexdigest() != meta["sha256"]:
                failures.append(case + ":" + field)
        typed = data["typed_evidence"]
        if hashlib.sha256(pathlib.Path(typed["path"]).read_bytes()).hexdigest() != typed["sha256"]:
            failures.append(case + ":typed")
        control = pathlib.Path(fields["control"]["path"]).read_bytes()
        value = {"case": case, "raw_fields": len(fields), "error_flags": struct.unpack_from("<I", control, 4)[0]}
        for key, offset in [("generation", 8), ("state_seq", 16), ("sim_tick", 24), ("revision", 40)]:
            value[key] = str(struct.unpack_from("<q", control, offset)[0])
        value["time"] = struct.unpack_from("<f", control, 32)[0]
        if value["generation"] != "9007199254740993" or value["error_flags"] != expected_flags.get(case, 0):
            failures.append(case + ":control_identity_or_flags")
        if case.startswith("water_"):
            for field, ref in [("water", "ref_water"), ("qx", "ref_qx")]:
                if pathlib.Path(fields[field]["path"]).read_bytes() != pathlib.Path(fields[ref]["path"]).read_bytes():
                    failures.append(case + ":reference_" + field)
        records.append(value)
    report = {"role": "independent SHA256/size/int64 and direct-reference-byte audit", "run": str(args.run.resolve()), "tool_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(), "pass": manifest["pass"] and not failures, "failures": failures, "records": records, "scope": "Saved observations only. Normal field capture predates later scheduling/64-command tests, as stated in typed evidence."}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"GPU_RAW_AUDIT {report['pass']} cases={len(records)}")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
