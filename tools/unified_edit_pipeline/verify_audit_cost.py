"""Validate paired real GPU timestamps and native auditor results, then summarize."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import struct

import numpy as np


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Fresh output required")
    args.output.mkdir(parents=True)
    manifest = json.loads((args.run/"run-manifest.json").read_text(encoding="utf-8-sig"))
    evidence = json.loads(Path(manifest["result"]).read_text())
    checks, statistics_rows = [], []

    def check(name, passed, detail=None):
        checks.append({"name": name, "pass": bool(passed), "detail": detail})

    check("run_and_cleanup_pass", manifest["pass"] and evidence["pass"] and not manifest["drift"])
    check("result_identity", sha(manifest["result"]) == manifest["result_sha256"].lower())
    check("six_fixtures", len(evidence["rows"]) == 6)
    pairs, ordered_frames = {}, []
    for frame in evidence["timestamp_frames"]:
        ordered_frames.append(frame["frame"])
        serials = set()
        for span in frame["spans"]:
            match = re.fullmatch(r"audit_cost_(\d+)_([01])", span["label"])
            check("timestamp_label_"+span["label"], match is not None)
            if not match:
                continue
            serial, variant = map(int, match.groups())
            serials.add(serial)
            check("unique_timestamp_"+span["label"], variant not in pairs.get(serial, {}))
            pairs.setdefault(serial, {})[variant] = (span["gpu_ns"], frame["frame"])
        check("one_pair_per_frame_"+str(frame["frame"]), len(serials) == 1 and len(frame["spans"]) == 2)
        serial = next(iter(serials))
        check("alternating_order_"+str(serial), [int(s["label"].split("_")[-1]) for s in frame["spans"]] == ([0, 1] if serial % 2 == 0 else [1, 0]))
    check("unique_capture_frames", len(set(ordered_frames)) == len(ordered_frames) == 168)
    check("complete_serials", set(pairs) == set(range(1, 169)))
    record = {(r["serial"], r["variant"]): r["cpu_record_us"] for r in evidence["record_times"]}
    check("complete_record_times", len(record) == len(evidence["record_times"]) == 336)
    for row in evidence["rows"]:
        label = row["case"]
        check(label+"_native_fixture_identity", all(sha(m["path"]) == m["sha256"] and Path(m["path"]).stat().st_size == m["bytes"] for m in row["fixtures"].values()))
        old = np.frombuffer(bytes.fromhex(row["old_receipt_hex"]), dtype="<u4")
        new = np.frombuffer(bytes.fromhex(row["new_decision_hex"]), dtype="<u4")
        of, nf = old.view("<f4"), new.view("<f4")
        check(label+"_both_accept", old[3] == 1 and old[20] == 0 and new[8] == 0)
        inputs = np.fromfile(row["fixtures"]["water_input"]["path"], dtype="<f4").reshape(-1, 8)
        candidate = np.fromfile(row["fixtures"]["water_candidate"]["path"], dtype="<f4").reshape(-1, 4)
        cells = np.fromfile(row["fixtures"]["cells"]["path"], dtype="<u4").reshape(-1, 16)
        old_fields = np.concatenate((inputs[:, 2:4], inputs[:, 4:6]), axis=1)
        touched = (inputs[:, 2] > np.float32(.001)) | np.any(old_fields != candidate, axis=1) | ((cells[:, 15] & 1) != 0)
        count = int(touched.sum())
        for component in (0, 1):
            delta = candidate[:, component].astype(float)-old_fields[:, component].astype(float)
            error = math.fsum(delta)*.015625
            absolute = math.fsum(abs(delta))*.015625
            maximum = np.maximum(abs(old_fields[:, component]), abs(candidate[:, component])).astype(float)
            ulps = np.where(maximum < 2**-126, 2**-149, np.exp2(np.floor(np.log2(np.maximum(maximum, 2**-126)))-23))
            budget = max(1e-7, math.fsum(2*ulps[touched])*.015625+max(1e-8, (8*2**-24+2*(count+256)*2**-48)*absolute))
            check(label+f"_independent_conservation_{component}", abs(error) <= budget)
            check(label+f"_new_error_{component}", abs(float(nf[16+component*2])-error) <= max(1e-10, 16*2**-24*absolute))
            check(label+f"_new_budget_{component}", abs(float(nf[17+component*2])-budget) <= max(1e-12, 32*2**-24*budget))
            if component == 0:
                check(label+"_old_error_and_budget", abs(float(of[42])-error) <= max(1e-10, 16*2**-24*absolute) and abs(float(of[47])-budget) <= max(1e-12, 32*2**-24*budget))
        check(label+"_actual_union_still_matches", new[9] == row["original_result"]["changed_cells"] and new[12] == row["original_result"]["touched_cells"])
        selected = list(range(row["first_serial"]+row["warmup_pairs"], row["last_serial"]+1))
        check(label+"_24_same_frame_pairs", len(selected) == 24 and all(set(pairs[s]) == {0, 1} and pairs[s][0][1] == pairs[s][1][1] and min(pairs[s][0][0], pairs[s][1][0]) > 0 for s in selected))
        old_ms = [pairs[s][0][0]/1e6 for s in selected]
        new_ms = [pairs[s][1][0]/1e6 for s in selected]
        ratios = [n/o for o, n in zip(old_ms, new_ms)]
        check(label+"_consistent_gpu_stage_gain", max(ratios) < 1)
        statistics_rows.append({"case": label, "pairs": len(selected), "old_gpu_median_ms": statistics.median(old_ms), "new_gpu_median_ms": statistics.median(new_ms), "paired_ratio_median": statistics.median(ratios), "paired_ratio_max": max(ratios), "old_gpu_range_ms": [min(old_ms), max(old_ms)], "new_gpu_range_ms": [min(new_ms), max(new_ms)], "old_cpu_record_median_us": statistics.median(record[s, 0] for s in selected), "new_cpu_record_median_us": statistics.median(record[s, 1] for s in selected), "p99": "not estimated from 24 samples"})
    report = {"pass": all(c["pass"] for c in checks), "checks": checks, "statistics": statistics_rows, "runtime": evidence["runtime"], "run_manifest_sha256": sha(args.run/"run-manifest.json"), "tool_sha256": sha(__file__), "scope": "Common water audit mode2/3 vs stock full-grid serial water_merge only; 144 measured alternating same-frame pairs after 24 warmup pairs. Existing numerical budgets verified independently; common stage also produces union metadata. Visible paused main full rendering, no end-to-end speedup/FPS/P99/final T08 claim."}
    (args.output/"result.json").write_text(json.dumps(report, indent=2))
    print(json.dumps({"pass": report["pass"], "checks": len(checks), "failures": [c["name"] for c in checks if not c["pass"]], "statistics": statistics_rows}))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
