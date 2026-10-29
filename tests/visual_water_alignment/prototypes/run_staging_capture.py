"""Run and verify fresh W08 staging captures on a real 1080p renderer."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time


PROJECT = Path(__file__).resolve().parents[3]
DEFAULT_PROFILE_RES = "res://tests/visual_water_alignment/prototypes/water_render_staging_v1.json"
CAPTURE_RES = "res://tests/visual_water_alignment/prototypes/capture_reference.gd"
CASES = {"water": "water_render_demo_v2", "coupled": "water_render_coupled_v2"}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inside(path: Path, directory: Path) -> bool:
    return path.resolve().is_relative_to(directory.resolve())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def check_artifact(path_string: str, directory: Path, run_id: str, started_ns: int) -> Path:
    path = Path(path_string)
    require(inside(path, directory), f"artifact outside output: {path}")
    require(path.name.startswith(run_id + "_"), f"artifact lacks run_id: {path}")
    require(path.is_file() and path.stat().st_size > 0, f"artifact missing/empty: {path}")
    require(path.stat().st_mtime_ns >= started_ns - 1_000_000_000,
            f"artifact not fresh: {path}")
    return path


def verify_manifest(path: Path, directory: Path, run_id: str, case: str,
                    tick: int, started_ns: int, profile: dict,
                    profile_sha: str, profile_res: str, wave_workload_id: str) -> dict:
    check_artifact(str(path), directory, run_id, started_ns)
    manifest = json.loads(path.read_text(encoding="utf-8"))
    require(manifest.get("run_id") == run_id and manifest.get("case") == case,
            f"manifest identity: {path}")
    require(manifest.get("role") == "w08_staging_profile_capture" and
            manifest.get("rendering_driver") == "d3d12",
            f"manifest role/driver: {path}")
    require(manifest.get("fixture_id") == CASES[case] and
            manifest.get("tick") == tick and
            manifest.get("visual_time_s") == tick / 30,
            f"manifest fixture/tick/time: {path}")
    require(manifest.get("viewport_px") == [1920, 1080] and
            manifest.get("sim_hz") == 30 and manifest.get("grid_size") == 256,
            f"manifest viewport/domain: {path}")
    require(manifest.get("requested_profile") == profile_res and
            manifest.get("requested_profile_sha256") == profile_sha and
            manifest.get("profile_id") == profile["profile_id"] and
            manifest.get("schema_version") == profile["schema_version"],
            f"manifest requested profile: {path}")
    effective = manifest.get("effective_profile", {})
    expected = {
        "profile_id": profile["profile_id"],
        "schema_version": profile["schema_version"],
        "phase": "staging",
        "fixture_id": CASES[case],
        "water_shader": profile["resources"]["water_shader"],
        "terrain_shader": profile["resources"][
            "terrain_fixed_shader" if case == "water" else "terrain_coupled_shader"],
        "render_subdivision": profile["render_subdivision"],
        "depth_write": profile["visual"]["depth_write"],
        "screen_optics": profile["capabilities"]["screen_optics"]["enabled"],
        "screen_world_glint": False,
        "face_normal": profile["visual"]["face_normal"],
        "screen_abs_fresnel": profile["visual"]["face_normal"],
        "eta_normals": profile["capabilities"]["eta_normals"]["enabled"],
        "main_foam": profile["capabilities"]["main_foam"]["enabled"],
        "crest_broken_core": False,
        "fold_caustics": profile["capabilities"]["fold_caustics"]["enabled"],
        "local_front": profile["capabilities"]["local_front"]["enabled"],
        "crest_height_m": profile["visual"]["crest_height_m"],
        "shallow_extinction_m": profile["visual"]["shallow_extinction_m"],
        "refraction_scale": profile["visual"]["refraction_scale"],
        "caustic_pattern": profile["resources"]["caustic_pattern"],
        "caustic_pattern_width": 1024,
        "caustic_pattern_height": 1024,
        "surface_bias_m": profile["surface_bias_m"],
        "visual_time_s": tick / 30,
    }
    if profile["schema_version"] >= 2:
        expected["offshore_core"] = profile["visual"]["offshore_core"]
        expected["offshore_core_broken"] = profile["visual"]["offshore_core_broken"]
    if profile["schema_version"] >= 3:
        expected["offshore_core_crown"] = profile["visual"]["offshore_core_crown"]
    if profile["schema_version"] >= 4:
        expected["reference_bed"] = profile["reference_bed"]
    require(effective == expected and
            re.fullmatch(r"[0-9a-f]{64}", manifest.get("effective_profile_sha256", "")),
            f"manifest effective profile: {path}")
    require(manifest.get("runtime_capabilities", {}).get("valid") is True and
            manifest.get("shader_probe", {}).get("red_samples", 0) > 0 and
            manifest.get("shader_probe", {}).get("blue_samples", 0) > 0,
            f"runtime consumption/probe: {path}")
    waves = manifest.get("wave_requests", [])
    expected_waves = 0 if wave_workload_id == "none" else (
        1 if wave_workload_id == "single_packet_v1" else 80)
    require(manifest.get("wave_workload_id") == wave_workload_id and
            len(waves) == expected_waves and
            all(wave.get("start_tick") == 8 + i * 180 and
                wave.get("seed") == 31 + i * 17 and
                wave.get("amplitude_m") == 0.18
                for i, wave in enumerate(waves)),
            f"wave workload: {path}")
    require(manifest.get("foam_summary", {}).get("coverage_05", 0) > 100,
            f"inactive foam at tick {tick}: {path}")
    artifacts = manifest.get("artifacts", [])
    require(len(artifacts) == 3 and set(manifest.get("camera", {})) ==
            {"oblique", "close", "grazing"}, f"camera artifacts: {path}")
    checked = [check_artifact(item, directory, run_id, started_ns) for item in artifacts]
    water = check_artifact(manifest.get("water_field_artifact", ""),
                           directory, run_id, started_ns)
    require(water.stat().st_size == 256 * 256 * 4,
            f"water F32 size: {water}")
    foam = check_artifact(manifest.get("foam_field_artifact", ""),
                          directory, run_id, started_ns)
    return {
        "manifest": str(path), "manifest_sha256": sha(path),
        "effective_profile_sha256": manifest["effective_profile_sha256"],
        "foam_coverage_05": manifest["foam_summary"]["coverage_05"],
        "camera_images": {item.stem.split("_")[-1]: sha(item) for item in checked},
        "water_field_sha256": sha(water), "foam_field_sha256": sha(foam),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--tick", type=int, default=240)
    parser.add_argument("--profile-res", default=DEFAULT_PROFILE_RES)
    parser.add_argument("--wave-workload", default="single_packet_v1",
                        choices=("none", "single_packet_v1", "continuous_packets_v1"))
    parser.add_argument("--protected-file", type=Path, action="append", default=[])
    args = parser.parse_args()
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{2,80}", args.run_id) is not None,
            "invalid run_id")
    require(args.godot.is_file() and args.output.is_dir() and args.tick >= 1,
            "Godot/output/tick invalid")
    require(args.profile_res.startswith("res://") and ".." not in args.profile_res,
            "profile resource path invalid")
    require(not list(args.output.glob(args.run_id + "_*")),
            "stale run_id artifacts already exist; refusing to reuse them")
    protected_before = {str(path.resolve()): sha(path) for path in args.protected_file}
    profile_path = PROJECT / args.profile_res.removeprefix("res://")
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    profile_sha = sha(profile_path)
    start_utc = datetime.now(timezone.utc).isoformat()
    checks = {}
    for case in CASES:
        started_ns = time.time_ns()
        command = [str(args.godot), "--path", str(PROJECT),
                   "--rendering-driver", "d3d12", "--fullscreen",
                   "--resolution", "1920x1080", "--disable-vsync",
                   "--script", CAPTURE_RES, "--", f"--case={case}",
                   f"--output={args.output.resolve()}", f"--run-id={args.run_id}",
                   f"--tick={args.tick}", f"--profile={args.profile_res}",
                   f"--wave-workload={args.wave_workload}",
                   "--require-1080p", "--capability-probe", "--wave",
                   "--readback-foam", "--write-water-field"]
        result = subprocess.run(command, cwd=PROJECT, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True,
                                encoding="utf-8", errors="replace", check=False)
        log_path = args.output / f"{args.run_id}_{case}.log"
        log_path.write_text(result.stdout, encoding="utf-8")
        require(result.returncode == 0 and
                f"PASS: WR reference prototype {case} tick={args.tick}" in result.stdout and
                not re.search(r"SCRIPT ERROR|SHADER ERROR|(^|\n)ERROR:|FAIL:",
                              result.stdout, re.IGNORECASE),
                f"Godot failed or logged an error: {log_path}")
        manifest_path = args.output / f"{args.run_id}_{case}_manifest.json"
        checks[case] = verify_manifest(manifest_path, args.output, args.run_id,
                                       case, args.tick, started_ns,
                                       profile, profile_sha, args.profile_res,
                                       args.wave_workload)
        checks[case]["log"] = str(log_path)
        checks[case]["log_sha256"] = sha(log_path)
    protected_after = {str(path.resolve()): sha(path) for path in args.protected_file}
    require(protected_after == protected_before, "protected evidence was modified")
    verification = {
        "role": "w08_staging_capture_freshness_verifier",
        "run_id": args.run_id, "tick": args.tick,
        "wave_workload_id": args.wave_workload,
        "started_utc": start_utc,
        "finished_utc": datetime.now(timezone.utc).isoformat(),
        "profile_sha256": profile_sha,
        "capture_script_sha256": sha(PROJECT / CAPTURE_RES.removeprefix("res://")),
        "protected_files_sha256_before": protected_before,
        "protected_files_sha256_after": protected_after,
        "protected_files_unchanged": True,
        "runner_script_sha256": sha(Path(__file__)),
        "cases": checks,
    }
    path = args.output / f"{args.run_id}_verification.json"
    path.write_text(json.dumps(verification, ensure_ascii=False, indent=2),
                    encoding="utf-8")
    print(f"PASS: W08 fresh staging evidence {args.run_id} tick={args.tick}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: W08 fresh staging evidence {exc}", file=sys.stderr)
        sys.exit(1)
