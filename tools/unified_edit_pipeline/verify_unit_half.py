"""Independent raw half-code audit; no call to the runtime codec."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cpu", type=Path, required=True)
    parser.add_argument("--gpu", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh output required")
    checks = []

    def check(name, passed):
        checks.append({"name": name, "pass": bool(passed)})

    def raw(record, label):
        data = Path(record["path"]).read_bytes()
        check(label+"_identity", len(data) == record["bytes"] and digest(data) == record["sha256"].lower())
        return data

    cpu_path = args.cpu/"probe.json"
    cpu = json.loads(cpu_path.read_text(encoding="utf-8-sig"))
    manifest_path = args.gpu/"run-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    check("cpu_probe_pass", cpu["pass"] and all(c["pass"] for c in cpu["checks"]))
    check("gpu_manifest_no_drift", manifest["pass"] and not manifest["drift"])
    sources = {p.replace("\\", "/"): h.lower() for p, h in manifest["sources"].items()}
    for path, expected in sources.items():
        check("current_source_"+path, digest((ROOT/path).read_bytes()) == expected)
    check("cpu_and_gpu_same_codec", cpu["source_sha256"] == sources["scripts/simulation/unified_edit/unit_half.gd"])
    check("cpu_probe_source", cpu["probe_sha256"] == digest((ROOT/"tests/integration/unified_edit_half_probe.gd").read_bytes()))
    artifacts = {k: raw(v, "cpu_"+k) for k, v in cpu["artifacts"].items()}
    codes = np.concatenate([np.arange(0x3c01, dtype="<u2"), np.array([0x8000], dtype="<u2")])
    check("all_legal_codes_15362", codes.size == 15362 and artifacts["native"] == codes.tobytes())
    # NumPy's IEEE decoder is independent of the GDScript arithmetic decoder.
    decoded = codes.view("<f2").astype("<f4")
    check("independent_ieee_decoder_exact_f32_including_signed_zero", artifacts["decoded_f32"] == decoded.tobytes())
    check("all_legal_codes_exact_roundtrip", artifacts["roundtrip"] == codes.tobytes())
    source = np.frombuffer(artifacts["normal_input_f32"], dtype="<f4")
    check("10000_valid_normal_inputs", source.size == 10000 and np.all(np.isfinite(source)) and np.all((source >= 2**-14) & (source <= 1)))
    bits = source.view("<u4")
    # Positive RTZ: exponent rebias and discard low 13 mantissa bits.
    native_rtz = (((((bits >> 23) & 255).astype(np.int32)-127+15) << 10) | ((bits & 0x7fffff) >> 13)).astype("<u2").tobytes()
    check("normal_encoding_independent_positive_rtz", artifacts["new_normal_half"] == native_rtz)
    check("existing_host_normal_encoding_unchanged", artifacts["new_normal_half"] == artifacts["host_normal_half"])
    boundary = np.array([2**-25, 2**-24, 1.5*2**-24, 2**-14-2**-24, 2**-14, 1, -0.0], dtype="<f4")
    check("boundary_inputs", artifacts["boundary_input_f32"] == boundary.tobytes())
    check("boundary_codes", artifacts["boundary_half"] == np.array([0, 1, 1, 1023, 1024, 0x3c00, 0x8000], dtype="<u2").tobytes())
    check("invalid_input_negative_tests", sum(c["name"].startswith("reject_") and c["pass"] for c in cpu["checks"]) == 13)

    run = manifest["runs"][0]
    probe_path = Path(run["result"])
    probe_data = probe_path.read_bytes()
    check("gpu_probe_identity", digest(probe_data) == run["result_sha256"].lower())
    probe = json.loads(probe_data)
    check("gpu_case_pass", run["case"] == "half_native" and run["pass"] and probe["pass"])
    observation = probe["observations"]
    for field, actual_fields in {"wetness": ["wetness0", "wetness1", "view_wetness"], "compaction": ["compact0", "compact1", "view_compaction"]}.items():
        indices = np.arange(65536)
        if field == "compaction":
            indices = indices[::-1]
        expected = codes[indices % codes.size].astype("<u2").tobytes()
        check("gpu_fixture_"+field, raw(observation["expected"][field], "gpu_expected_"+field) == expected)
        for phase in ("initial", "after"):
            for actual in actual_fields:
                check("gpu_native_exact_"+phase+"_"+actual, raw(observation[phase][actual], phase+"_"+actual) == expected)
        for phase in ("before", "after"):
            for actual in actual_fields:
                check("gpu_transaction_exact_"+phase+"_"+actual, raw(probe["cases"][0][phase][actual], "transaction_"+phase+"_"+actual) == expected)
    result = probe["cases"][0]["result"]
    check("legitimate_gpu_nochange_publication", result["outcome"] == 2 and result["state_seq"] == 1 and result["changed_cells"] == 0 and result["output_revision"] == 0 and result["generation"] == 9007199254740993)
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "cpu_report": str(cpu_path.resolve()), "cpu_report_sha256": digest(cpu_path.read_bytes()), "gpu_manifest": str(manifest_path.resolve()), "gpu_manifest_sha256": digest(manifest_path.read_bytes()), "auditor_sha256": digest(Path(__file__).read_bytes()), "scope": "Full 15362 native unit-half representations, signed zero, 10000 normal RTZ compatibility, real dual-authority/upload/read-only view byte equality. No full checkpoint restore or formal main entry claim."}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failed": [c["name"] for c in checks if not c["pass"]]}))
    raise SystemExit(0 if report["pass"] else 1)


if __name__ == "__main__":
    main()
