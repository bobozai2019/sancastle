"""Summarize the completed W06 water-only trend without changing its thresholds."""

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "task" / "sandcastle_visual_reconstruction_phase2" / "验收"
summary = json.loads((OUT / "W06_water_soak_summary.json").read_text(encoding="utf-8"))
if summary["mode"] != "soak" or summary["sample_seconds"] < 1800:
    raise SystemExit("W06 soak is not complete")

with (OUT / "W06_water_soak.csv").open(encoding="utf-8", newline="") as source:
    rows = list(csv.DictReader(source))
if len(rows) < 60:
    raise SystemExit("W06 soak has too few trend samples")

def values(name, cast=float):
    return [cast(row[name]) for row in rows]

elapsed = values("elapsed_s", int)
ticks = values("tick", int)
static_bytes = values("static_bytes", int)
video_bytes = values("video_bytes", int)
audit_water = values("audit_water_m3")
source_m3 = values("source_m3")
sink_m3 = values("sink_m3")
invariant = [a - b + c for a, b, c in zip(audit_water, source_m3, sink_m3)]
interval_rates = [
    (ticks[i] - ticks[i - 1]) / (elapsed[i] - elapsed[i - 1])
    for i in range(1, len(rows))
]
result = {
    "sample_seconds": summary["sample_seconds"],
    "sample_rows": len(rows),
    "tick_rate_hz": summary["tick_rate"],
    "interval_tick_rate_min_hz": min(interval_rates),
    "interval_tick_rate_max_hz": max(interval_rates),
    "invalid_cells_max": max(values("invalid_cells", int)),
    "negative_cells_max": max(values("negative_cells", int)),
    "minimum_depth_m": min(values("min_depth_m")),
    "static_bytes_first": static_bytes[0],
    "static_bytes_last": static_bytes[-1],
    "static_bytes_range": max(static_bytes) - min(static_bytes),
    "video_bytes_first": video_bytes[0],
    "video_bytes_last": video_bytes[-1],
    "video_bytes_range": max(video_bytes) - min(video_bytes),
    "audit_water_m3_min": min(audit_water),
    "audit_water_m3_max": max(audit_water),
    "sampled_water_ledger_invariant_min_m3": min(invariant),
    "sampled_water_ledger_invariant_max_m3": max(invariant),
    "sampled_water_ledger_invariant_range_m3": max(invariant) - min(invariant),
    "note": "Audit and ledger counters can be sampled on adjacent revisions; this is a trend, not an exact closure test.",
}
(OUT / "W06_water_soak_analysis.json").write_text(
    json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
)
print(json.dumps(result, ensure_ascii=False))
