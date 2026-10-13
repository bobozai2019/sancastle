"""Freeze the reviewed T10 sand and coupled visual configuration."""

import hashlib
import json
from pathlib import Path


root = Path(__file__).resolve().parents[2]
out = root / "test_output/sandcastle_visual_reconstruction_phase2/验收"
sources = [
    "scenes/sand_visual_fixture.tscn",
    "scenes/sand_coupled_fixture.tscn",
    "scripts/scenarios/sand_visual_fixture.gd",
    "scripts/demo/gpu_water_preview.gd",
    "scripts/simulation/gpu_shallow_solver.gd",
    "scripts/simulation/material/gpu_material_coupler.gd",
    "scripts/simulation/erosion/gpu_sediment_coupler.gd",
    "scripts/simulation/checkpoint_store.gd",
    "scripts/visual/sand_display_sampler.gd",
    "shaders/simulation/material/slope_relax.glsl",
    "shaders/visual/gpu_sand_phase2.gdshader",
    "shaders/visual/gpu_sand_coupled_fast.gdshader",
    "shaders/visual/gpu_water.gdshader",
]
checks = {
    "sand_cohesion_yield_height_m = 2.0": [
        "scenes/sand_visual_fixture.tscn", "scenes/sand_coupled_fixture.tscn"
    ],
    "render_subdivision = 2": [
        "scenes/sand_visual_fixture.tscn", "scenes/sand_coupled_fixture.tscn"
    ],
    "const COURANT := 0.35": ["scripts/simulation/gpu_shallow_solver.gd"],
    "auto_support_toe_initial_m3 - toe_mass >= 0.015": [
        "scripts/demo/gpu_water_preview.gd"
    ],
    '"support_event_schema_version": 2 if fixture_id ==': [
        "scripts/demo/gpu_water_preview.gd"
    ],
    "render_mode unshaded, cull_disabled;": [
        "shaders/visual/gpu_sand_coupled_fast.gdshader"
    ],
    "vec3 grain_uv = sand_world_position * 30.0": [
        "shaders/visual/gpu_sand_phase2.gdshader",
        "shaders/visual/gpu_sand_coupled_fast.gdshader",
    ],
}
for literal, paths in checks.items():
    for path in paths:
        if literal not in (root / path).read_text(encoding="utf-8"):
            raise SystemExit(f"frozen profile value missing: {literal} in {path}")
profile = {
    "profile_id": "sand_phase2_v1",
    "fixture_ids": ["sand_v1", "sand_coupled_v1"],
    "seed": 53021,
    "grid_size": 256,
    "cell_size_m": 0.125,
    "sim_hz": 30,
    "cfl_courant": 0.35,
    "render_subdivision": 2,
    "cohesion_yield_height_m": 2.0,
    "sand_tower": {"height_m": 1.8, "width_m": 2.125,
                   "initial_volume_m3_each": 7.9921875,
                   "compaction": 0.95, "wetness": 0.35},
    "loose_tower": {"same_initial_volume": True,
                    "compaction": 0.10, "wetness": 0.05},
    "coupled_toe": {"cells": 51, "initial_volume_m3": 0.1434375,
                    "trigger_loss_m3": 0.015, "demoted_cells": 102,
                    "event_schema_version": 2},
    "coupled_wave": {"profile_id": "test_packet",
                     "amplitude_m": 0.20, "duration_s": 5.0},
    "sand_material": {"grain_size_m": 1 / 30,
                      "wetness_and_compaction_from_gpu": True,
                      "coupled_fast_unshaded": True},
    "water_profile": "water_profile_v1.json",
    "water_in_coupled": {"phase2_optics": True,
                         "shoreline_reconstruction": True,
                         "foam_history": True},
    "checkpoint": {"support_event_schema_versions": [1, 2],
                   "foam_history": True},
    "source_sha256": {path: hashlib.sha256((root / path).read_bytes()).hexdigest()
                      for path in sources},
}
target = out / "sand_profile_v1.json"
target.write_text(json.dumps(profile, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"PASS: frozen sand profile {target} sources={len(sources)}")
