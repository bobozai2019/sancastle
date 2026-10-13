"""Audit the four wall-clock S06 visible-window stability runs."""

import csv
import json
from pathlib import Path


root = Path(__file__).resolve().parents[2]
evidence = root / "test_output/sandcastle_visual_reconstruction_phase2/验收"
results = {}
for case in ("preset0", "preset1", "preset2", "coupled"):
    stem = f"S06_{case}_soak"
    summary = json.loads((evidence / f"{stem}_summary.json").read_text(encoding="utf-8"))
    with (evidence / f"{stem}.csv").open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    assert summary["sample_seconds"] >= 1800
    assert len(rows) >= 60
    assert summary["tick_rate"] + 1 / summary["sample_seconds"] >= 30
    assert summary["overload_events"] == summary["nan_events"] == 0
    for row in rows:
        for key in ("invalid_water_cells", "negative_water_cells",
                    "invalid_sand_cells", "negative_sand_cells"):
            assert int(row[key]) == 0, (case, row["elapsed_s"], key)
        for key in ("water_m3", "sand_m3", "sediment_m3", "sand_closure_m3"):
            assert float(row[key]) == float(row[key])
        assert float(row["sand_closure_m3"]) < 0.01 * max(float(row["sand_m3"]), 1)
    static = [int(row["static_bytes"]) for row in rows]
    video = [int(row["video_bytes"]) for row in rows]
    result = {
        "sample_seconds": summary["sample_seconds"],
        "rows": len(rows),
        "tick_rate": summary["tick_rate"],
        "max_sand_closure_m3": max(float(row["sand_closure_m3"]) for row in rows),
        "static_first_last_delta_bytes": static[-1] - static[0],
        "static_range_bytes": max(static) - min(static),
        "video_first_last_delta_bytes": video[-1] - video[0],
        "video_range_bytes": max(video) - min(video),
        "support_events": len(summary["support_events"]),
    }
    if case == "coupled":
        assert result["support_events"] == 1
    else:
        assert result["support_events"] == 0
    results[case] = result
frame = json.loads((evidence / "S06_coupled_frame_summary.json").read_text(encoding="utf-8"))
assert frame["sample_seconds"] >= 300
assert frame["viewport_px"] == [1920, 1080]
assert frame["wall_p99_ms"] <= 33.3
assert frame["tick_rate"] + 1 / frame["sample_seconds"] >= 30
results["coupled_1080p_frame"] = {
    "sample_seconds": frame["sample_seconds"],
    "wall_p99_ms": frame["wall_p99_ms"],
    "tick_rate": frame["tick_rate"],
    "frames": frame["frames_or_rows"],
}
(evidence / "S06_final_stability_analysis.json").write_text(
    json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
)
print("PASS: S06 four visible soaks and 1080p frame gate " + json.dumps(results))
