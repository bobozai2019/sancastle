"""Write the reviewed T09 water profile and source digests for T10 reuse."""

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "task" / "sandcastle_visual_reconstruction_phase2" / "验收"
SOURCES = [
    "scenes/water_visual_fixture.tscn",
    "scripts/scenarios/water_visual_fixture.gd",
    "scripts/demo/gpu_water_preview.gd",
    "scripts/simulation/gpu_shallow_solver.gd",
    "scripts/visual/bed_display_sampler.gd",
    "scripts/visual/gpu_foam_field.gd",
    "shaders/visual/gpu_water.gdshader",
    "shaders/visual/gpu_terrain.gdshader",
    "shaders/simulation/shallow_tide_boundary.glsl",
    "shaders/simulation/visual_foam_step.glsl",
    "scripts/simulation/checkpoint_store.gd",
]
digests = {
    path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
    for path in SOURCES
}
checks = {
    '"water_surface_bias_m", 0.003': ROOT / "scripts/demo/gpu_water_preview.gd",
    "render_subdivision = 2": ROOT / "scenes/water_visual_fixture.tscn",
    "enable_erosion = false": ROOT / "scenes/water_visual_fixture.tscn",
    "enable_structures = false": ROOT / "scenes/water_visual_fixture.tscn",
    "phase2_extinction_m = 0.11": ROOT / "shaders/visual/gpu_water.gdshader",
    "solver.cell_size_m, 1.8, 25.0": ROOT / "scripts/visual/gpu_foam_field.gd",
}
for literal, path in checks.items():
    if literal not in path.read_text(encoding="utf-8"):
        raise SystemExit(f"frozen profile value missing: {literal} in {path}")

profile = {
    "profile_id": "water_v1",
    "fixture_id": "water_v1",
    "seed": 41021,
    "grid_size": 256,
    "cell_size_m": 0.125,
    "sim_hz": 30,
    "fixed_bed": True,
    "render_subdivision": 2,
    "water_surface_bias_m": 0.003,
    "phase2_optics": {
        "extinction_depth_m": 0.11,
        "shallow_tint": [0.04, 0.72, 0.69],
        "deep_tint": [0.02, 0.29, 0.37],
        "detail_normals": True,
        "specular": True,
        "caustics": True,
    },
    "wave_profiles": {
        "small_packet": {"amplitude_max_m": 0.06, "duration_s": [0.5, 3.0]},
        "test_packet": {"amplitude_max_m": 0.20, "duration_s": [0.5, 6.0]},
        "overlap_height_cap_m": 0.25,
    },
    "foam": {
        "history_format": "RG32F",
        "lifetime_s": 1.8,
        "source_gain": 25.0,
        "dry_reset_depth_m": 0.0015,
        "checkpoint_field": "foam_history",
    },
    "bed_sampling": "SandcastleBedDisplaySampler.sample_bed/sample_world",
    "wave_request": "gpu_water_preview.request_wave",
    "effect_switches": {"enable_erosion": False,
                        "enable_material": False,
                        "enable_structures": False},
    "source_sha256": digests,
}
path = OUT / "water_profile_v1.json"
path.write_text(json.dumps(profile, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"PASS: frozen water profile {path} sources={len(digests)}")
