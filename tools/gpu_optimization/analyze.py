import argparse
import json
import statistics
from pathlib import Path


def distribution(values):
    ordered = sorted(values)
    if not ordered:
        return None
    return {
        "count": len(ordered),
        "mean": statistics.mean(ordered),
        "median": statistics.median(ordered),
        "max": max(ordered),
    }


def summarize(path):
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    groups = {}
    for frame in data.get("gpu_samples", []):
        totals = {}
        for span in frame["spans"]:
            group = span["group"] or "unclassified_detail"
            totals[group] = totals.get(group, 0) + span["gpu_ns"]
        for group, duration in totals.items():
            groups.setdefault(group, []).append(duration)
    return {
        "path": str(path.resolve()),
        "pass": data["pass"],
        "sampling": data["sampling"],
        "case": data["case"],
        "field_sha256": data["witnesses"]["field_sha256"],
        "state_seq": data["witnesses"]["state_seq"],
        "sim_tick": data["witnesses"]["sim_tick"],
        "actual_time": data["witnesses"]["actual_time"],
        "wall_us": distribution([row["wall_us"] for row in data["samples"][2:]]),
        "recording_us": distribution([row["recording_us"] for row in data["samples"][2:] if row["recording_us"] is not None]),
        "frame_us": distribution(data.get("frame_us", [])),
        "viewport_gpu_ms": distribution([row["viewport_gpu_ms"] for row in data["samples"][2:] if row["viewport_gpu_ms"] is not None]),
        "gpu_groups_ns": {key: distribution(values) for key, values in groups.items()},
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    runs = [summarize(path) for path in arguments.inputs]
    raw = [json.loads(path.read_text(encoding="utf-8-sig")) for path in arguments.inputs]
    environment_keys = ["engine", "adapter", "driver", "window", "viewport", "vsync", "effective_profile"]
    environment_equal = all(
        all(item["runtime"].get(key) == raw[0]["runtime"].get(key) for key in environment_keys)
        and item["case"] == raw[0]["case"]
        and len(item["samples"]) == len(raw[0]["samples"])
        and (item["case"] == "water" or item["runtime"].get("input_target") == raw[0]["runtime"].get("input_target"))
        for item in raw
    )
    equal = all(
        run["field_sha256"] == runs[0]["field_sha256"]
        and run["sim_tick"] == runs[0]["sim_tick"]
        and run["state_seq"] == runs[0]["state_seq"]
        and run["actual_time"] == runs[0]["actual_time"]
        for run in runs
    )
    result = {"runs": runs, "identical_fields_and_clock": equal, "same_environment_and_input_shape": environment_equal, "gpu_unit": "ns", "warmup_iterations_excluded_from_cpu_and_wall": 2, "gpu_groups_include_warmup": True, "limitations": ["water_tick includes its child stages; never add parent and child groups", "viewport samples are delayed frame observations, not attributed to a work unit", "completion wall time includes collision and frame scheduling"]}
    arguments.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"pass": all(run["pass"] for run in runs), "identical_fields_and_clock": equal, "same_environment_and_input_shape": environment_equal, "runs": len(runs)}))


if __name__ == "__main__":
    main()
