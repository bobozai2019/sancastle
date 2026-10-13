"""Hard gates for the S05 wave/no-wave erosion and local collapse probe."""

import json
from pathlib import Path


root = Path(__file__).resolve().parents[2]
evidence = root / "test_output/sandcastle_visual_reconstruction_phase2/验收"
wave = json.loads((evidence / "S05_coupled_toe_probe.json").read_text(encoding="utf-8"))
control = json.loads((evidence / "S05_coupled_toe_probe_no_wave.json").read_text(encoding="utf-8"))
movie = json.loads((evidence / "S05_sand_coupled_demo.json").read_text(encoding="utf-8"))
wave_samples = wave["samples"]
control_samples = control["samples"]
initial = 2 * 7.9921875 + 51 * 0.18 * 0.125 * 0.125
assert len(movie["tool_commands"]) == 2
assert len(movie["wave_requests"]) == 1
assert len(movie["support_events"]) == 1
assert len(movie["snapshots"]) >= 5
assert movie["end_tick"] >= 1800
assert not control_samples["900"]["support_events"]
assert wave_samples["150"]["support_events"] == []
event = wave_samples["300"]["support_events"]
assert len(event) == 1 and event[0]["cause"] == "erosion_toe_loss"
assert event[0]["affected_cells"] == 102
assert event[0]["toe_initial_m3"] - event[0]["toe_at_trigger_m3"] >= 0.015
assert wave_samples["300"]["packed_m3"] < wave_samples["150"]["packed_m3"] - 0.5
assert control_samples["300"]["packed_m3"] > 7.9
assert wave_samples["900"]["suspended_m3"] > control_samples["900"]["suspended_m3"]
for tick, sample in wave_samples.items():
    assert sample["min_sand_m"] >= -1e-6
    assert sample["collision_error_m"] < 0.02
    assert sample["collision_readback_ms"] + sample["collision_replace_ms"] < 100
    assert abs(sample["total_bed_m3"] + sample["suspended_m3"] - initial) / initial < 0.01
    assert abs(sample["water_closure_m3"]) / wave["initial_water_m3"] < 1e-5
summary = {
    "wave_event_tick": event[0]["tick"],
    "wave_toe_loss_at_trigger_m3": event[0]["toe_initial_m3"] - event[0]["toe_at_trigger_m3"],
    "control_event_count": len(control_samples["900"]["support_events"]),
    "packed_loss_by_tick_300_m3": wave_samples["150"]["packed_m3"] - wave_samples["300"]["packed_m3"],
    "max_sand_closure_fraction": max(
        abs(sample["total_bed_m3"] + sample["suspended_m3"] - initial) / initial
        for sample in wave_samples.values()
    ),
    "max_water_closure_fraction": max(
        abs(sample["water_closure_m3"]) / wave["initial_water_m3"]
        for sample in wave_samples.values()
    ),
    "max_collision_error_m": max(sample["collision_error_m"] for sample in wave_samples.values()),
    "max_sampled_collision_latency_ms": max(
        sample["collision_readback_ms"] + sample["collision_replace_ms"]
        for sample in wave_samples.values()
    ),
    "movie_seconds": movie["end_tick"] / 30,
    "movie_snapshots": len(movie["snapshots"]),
}
(evidence / "S05_coupled_analysis.json").write_text(
    json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
)
print("PASS: S05 coupled analysis " + json.dumps(summary))
