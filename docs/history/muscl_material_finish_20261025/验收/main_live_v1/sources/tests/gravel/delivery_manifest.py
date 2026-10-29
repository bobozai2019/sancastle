"""Build the final gravel delivery index without changing runtime assets."""
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

root = Path.cwd()
output = root / "test_output/gpu_gravel/delivery_20261015"
output.mkdir(parents=True, exist_ok=True)
runtime = [
    "scripts/visual/gpu_gravel_field.gd", "scripts/visual/gravel_checkpoint_codec.gd",
    "scripts/beach/gravel_playable_entry.gd", "shaders/simulation/visual_gravel_step.glsl",
    "shaders/visual/gpu_gravel.gdshader", "scripts/simulation/checkpoint_store.gd",
    "scripts/simulation/edit_validation/beach_restore_bundle.gd", "scripts/beach/beach_scene_service.gd",
    "tests/visual_water_alignment/prototypes/reference_preview.gd", "scenes/main.tscn",
    "scenes/playable/test1_capture.tscn", "scenes/playable/test1_backwash.tscn",
    "scenes/components/gravel_layer.tscn",
]
runtime += [p.as_posix() for p in Path("assets/gravel").glob("*") if p.suffix in (".bin", ".tres")]
runtime += [p.as_posix() for p in Path("tests/gravel").glob("*") if p.suffix in (".gd", ".gdshader", ".tscn", ".py")]
sources = []
for relative in sorted(set(runtime)):
    source = root / relative
    data = source.read_bytes()
    target = output / "source_snapshot" / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    sources.append({"path": relative, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})

reports = [
    ("baseline_20261015/main_smoke.json", True),
    ("texture_probe_1792022154_831/result.json", True),
    ("transport_1792039002_966/result.json", True),
    ("visual_1792039007_425/main_smoke.json", True),
    ("lifecycle_1792037874_911/main_smoke.json", True),
    ("switch_1792037934_188/main_smoke.json", True),
    ("shutdown_1792038893_926/main_smoke.json", True),
    ("isolation_1792038286_199/main_smoke.json", True),
    ("backwash_movie_20261015/main_smoke.json", True),
    ("integration_1792038365_278/main_smoke.json", True),
    ("cost_1792038628_326/main_smoke.json", True),
    ("pick_scoped_final_20261015/result.json", True),
    ("delivery_20261015/header_probe.json", True),
    ("pick_final_20261015/result.json", False),
    ("pick_camera_off_control_v2_20261015/result.json", False),
]
evidence = []
for relative, required in reports:
    path = root / "test_output/gpu_gravel" / relative
    data = path.read_bytes()
    report = json.loads(data)
    passed = report.get("pass", report.get("numeric_pass"))
    evidence.append({"path": path.relative_to(root).as_posix(), "sha256": hashlib.sha256(data).hexdigest(), "pass": passed, "required_gate_evidence": required, "failed_checks": [r["name"] for r in report.get("checks", []) if not r["pass"]]})
    if required and not passed:
        raise SystemExit(f"Required evidence did not pass: {relative}")
manifest = {
    "schema_version": 1, "date": "2026-10-15", "task": "task/sandcastle_gpu_gravel",
    "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "source_files": sources, "reports": evidence,
    "default_count": 512, "capacity": 1024, "seed": 57849,
    "engine": "4.7.1.stable.official.a13da4feb", "driver": "d3d12", "gpu": "NVIDIA GeForce GTX 1050",
    "entry_points": ["res://scenes/main.tscn", "res://scenes/playable/test1_capture.tscn", "res://scenes/playable/test1_backwash.tscn"],
    "commands": {"launch_prefix": "D:/godot/Godot_v4.7.1-stable/Godot_v4.7.1-stable_win64_console.exe --path D:/godot/project/sandcastle --rendering-driver d3d12", "numeric": "--script res://tests/gravel/gravel_transport_probe.gd", "visual": "--script res://tests/gravel/gravel_visual_probe.gd", "lifecycle": "--script res://tests/gravel/gravel_lifecycle_probe.gd", "switch": "--script res://tests/gravel/gravel_scene_switch_probe.gd", "shutdown": "--script res://tests/gravel/gravel_shutdown_probe.gd", "isolation": "--script res://tests/gravel/gravel_authority_isolation_probe.gd", "stability": "--script res://tests/gravel/gravel_integration_probe.gd -- --stability", "cost": "--script res://tests/gravel/gravel_cost_probe.gd", "scoped_pick": "--script res://tests/gravel/gravel_pick_regression.gd -- --output=<fresh absolute directory> --skip-camera"},
    "source_revision_notes": "Cost/stability/movie each preserve hash-checked consumed source snapshots. Final owner additionally waits for candidate abort during shutdown and guards malformed legacy headers; shutdown/header probes verify these paths. Final main.tscn only has trailing whitespace removed after those runs; render/tick content is unchanged.",
    "limits": ["Gravel draw-only GPU time unknown; paired viewport and whole-frame differences are estimates.", "No formal whole-project performance budget.", "Legacy camera/focus checks fail identically with gravel disabled and are retained separately.", "Early raw terminal logs remain in tool outputs; machine JSON/JSONL reports and source snapshots are retained."],
}
(output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"source_count": len(sources), "reports": len(evidence), "required_all_pass": True, "path": str(output / "manifest.json")}, ensure_ascii=False))
