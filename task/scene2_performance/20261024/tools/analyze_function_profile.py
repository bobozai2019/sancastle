"""Decode Godot servers profiler messages; times on the wire are seconds."""
import argparse
import collections
import csv
import json
from pathlib import Path


def analyze(directory: Path):
    messages = json.loads((directory / "messages.json").read_text(encoding="utf-8"))
    signatures = {}
    phase = ""
    totals = {}
    native_frames = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0.0]))
    frame_counts = collections.Counter()
    errors = []
    for name, thread, data in messages:
        if name == "servers:function_signature":
            signatures[data[1]] = data[0]
        elif name == "function_probe:begin":
            phase = data[0]
        elif name == "error":
            errors.append(data)
        elif name in ("servers:profile_frame", "servers:profile_total"):
            index = 7
            for _ in range(data[6]):
                index += 2 + data[index + 1]
            size = data[index]
            index += 1
            assert size % 5 == 0 and index + size == len(data)
            rows = []
            for offset in range(index, index + size, 5):
                sig, calls, own, total, internal = data[offset:offset + 5]
                signature = signatures[sig]
                row = dict(name=signature, calls=calls, self_ms=own * 1000,
                           total_ms=total * 1000, internal_ms=internal * 1000)
                rows.append(row)
                # Native entries have line 0. Aggregate per-frame data, rather
                # than interpreting final native entries as interval counters.
                if name == "servers:profile_frame" and "::0::" in signature:
                    aggregate = native_frames[phase][signature.split("::")[-1]]
                    aggregate[0] += calls
                    aggregate[1] += total * 1000
            if name == "servers:profile_total":
                totals[phase] = rows
            else:
                frame_counts[phase] += 1
    result = dict(functions=totals, profile_frames=dict(frame_counts), errors=errors,
                  native_frame_aggregates={key: dict(value) for key, value in native_frames.items()})
    (directory / "functions.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    with (directory / "functions.csv").open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=["phase", "name", "calls", "self_ms", "total_ms", "internal_ms"])
        writer.writeheader()
        for key, rows in totals.items():
            for row in sorted(rows, key=lambda value: value["self_ms"], reverse=True):
                if row["calls"] and "::0::" not in row["name"]:
                    writer.writerow(dict(phase=key, **row))
    for key, rows in totals.items():
        print(key, "profile frames:", frame_counts[key])
        for row in sorted(rows, key=lambda value: value["self_ms"], reverse=True)[:10]:
            print(row["name"], row["calls"], round(row["self_ms"], 3), round(row["total_ms"], 3))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    analyze(parser.parse_args().directory)
