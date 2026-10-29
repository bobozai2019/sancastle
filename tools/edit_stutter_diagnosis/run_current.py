"""Run a visible current-main diagnostic; preserve source and process identity."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/unified_edit_pipeline"))
from analyze_shovel_latency import analyze


def processes():
    command = (
        "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'godot' } | "
        "Select-Object ProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Compress"
    )
    result = subprocess.run(
        ["powershell", "-NoProfile", "-Command", command],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", choices=["dig", "fill"], required=True)
    parser.add_argument("--wet", action="store_true")
    parser.add_argument("--water-only", action="store_true")
    parser.add_argument("--hold-height", action="store_true")
    parser.add_argument("--deferred-retirement-reference", action="store_true")
    parser.add_argument("--policy", type=int)
    parser.add_argument("--samples", type=int, default=160)
    parser.add_argument("--godot", default="D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe")
    args = parser.parse_args()
    output = args.output.resolve()
    if any(output.with_suffix(s).exists() for s in [".json", ".log", ".analysis.json", ".trace.json", ".manifest.json"]):
        parser.error("Output exists; choose a fresh filename")
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [args.godot, "--path", str(ROOT), "--rendering-driver", "d3d12",
               "--script", "res://tools/edit_stutter_diagnosis/current_probe.gd",
               "--log-file", str(output.with_suffix(".log")), "--",
               "--output=" + str(output), "--case=" + args.case, "--samples=" + str(args.samples)]
    for flag in ["wet", "water_only", "hold_height", "deferred_retirement_reference"]:
        if getattr(args, flag):
            command.append("--" + flag.replace("_", "-"))
    if args.policy is not None:
        command.append("--policy=" + str(args.policy))
    manifest = {
        "command": command, "cwd": str(ROOT), "started_unix_s": time.time(),
        "godot_sha256": hashlib.sha256(Path(args.godot).read_bytes()).hexdigest(),
        "background_processes_before": processes(),
    }
    output.with_suffix(".manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Running", args.case, output, flush=True)
    child = subprocess.Popen(command, cwd=ROOT)
    try:
        code = child.wait(timeout=240)
    except subprocess.TimeoutExpired:
        child.terminate()
        code = child.wait(timeout=15)
        manifest["timeout"] = True
    manifest.update(returncode=code, ended_unix_s=time.time(), background_processes_after=processes())
    output.with_suffix(".manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    if output.exists():
        analyze(output)
    raise SystemExit(code)


if __name__ == "__main__":
    main()
