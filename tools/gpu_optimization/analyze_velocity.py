import argparse
import json
import statistics
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--after", type=int, default=24)
    parser.add_argument("--expected-pairs", type=int, default=16)
    arguments = parser.parse_args()
    data = json.loads(arguments.input.read_text(encoding="utf-8-sig"))
    rows = {row["pair_serial"]: row for row in data["rows"]}
    pairs = []
    for frame in data["timestamp_frames"]:
        by_pair = {}
        for span in frame["spans"]:
            parts = span["label"].split("_")
            serial, variant = int(parts[-2]), int(parts[-1])
            by_pair.setdefault(serial, {})[variant] = span["ns"]
        for serial, durations in by_pair.items():
            if {0, 1}.issubset(durations) and serial > arguments.after:
                pairs.append({"pair_serial": serial, "frame": frame["frame"], "parent_ns": durations[0], "candidate_ns": durations[1], "correctness_pass": rows[serial]["pass"]})
    result = {
        "pass": data["pass"] and len(pairs) == arguments.expected_pairs and all(pair["correctness_pass"] for pair in pairs),
        "pairs": pairs,
        "parent_median_ns": statistics.median(pair["parent_ns"] for pair in pairs) if pairs else None,
        "candidate_median_ns": statistics.median(pair["candidate_ns"] for pair in pairs) if pairs else None,
        "all_paired_stages_faster": bool(pairs) and all(pair["candidate_ns"] < pair["parent_ns"] for pair in pairs),
        "scope": "stage-local paired timings, alternating order, same frame and raw input; does not establish whole-frame improvement",
    }
    arguments.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
