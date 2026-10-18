"""Launch one owned, visible Godot diagnostic and analyze its saved trace."""
import argparse
from datetime import datetime
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="D:/game/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--manual", action="store_true")
    parser.add_argument("--long", action="store_true", help="Repeated strokes, timed release tail, and paused control")
    parser.add_argument("--sweep-area", action="store_true", help="Long probe: one held stroke across adjacent 8m tracks")
    parser.add_argument("--fallback-witness", action="store_true", help="Capture first fallback input on GPU; requires --long --water-only")
    parser.add_argument("--duration", type=float, default=30)
    parser.add_argument("--wet", action="store_true")
    parser.add_argument("--sampling", action="store_true")
    parser.add_argument("--water-only", action="store_true")
    parser.add_argument("--reference-packed", action="store_true", help="Probe-only original kernel; requires --water-only")
    parser.add_argument("--packed-phases", action="store_true", help="Time candidate internal phases; requires --water-only")
    parser.add_argument("--hold-height", action="store_true")
    args = parser.parse_args()
    if (args.reference_packed or args.packed_phases) and not args.water_only:
        parser.error("Packed comparison options require --water-only")
    if args.sweep_area and not args.long:
        parser.error("--sweep-area requires --long")
    if args.fallback_witness and not (args.long and args.water_only):
        parser.error("--fallback-witness requires --long --water-only")
    if not Path(args.godot).is_file():
        parser.error("Godot executable not found; provide --godot PATH")
    output = (args.output or ROOT / "test_output" / ("shovel_trace_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f")) / "capture.json").resolve()
    if any(output.with_suffix(s).exists() for s in (".json", ".log", ".analysis.json", ".trace.json")):
        parser.error("Output already exists; choose a new filename")
    output.parent.mkdir(parents=True, exist_ok=True)
    script = "diagnose_shovel_fallback.gd" if args.fallback_witness else ("diagnose_shovel_long.gd" if args.long else "diagnose_shovel_latency.gd")
    command = [args.godot, "--path", str(ROOT), "--rendering-driver", "d3d12",
               "--script", "res://tools/unified_edit_pipeline/"+script,
               "--log-file", str(output.with_suffix(".log")), "--", "--output="+str(output),
               "--duration="+str(args.duration)]
    for option in ("manual", "wet", "sampling", "water_only", "hold_height", "reference_packed", "packed_phases", "sweep_area"):
        if getattr(args, option):
            command.append("--"+option.replace("_", "-"))
    print("Capture:", output, flush=True)
    # This is the actual visible game, not a hidden background helper.
    child = subprocess.Popen(command, cwd=ROOT)
    try:
        result = child.wait()
    except KeyboardInterrupt:
        child.terminate()
        child.wait()
        raise
    if not output.exists():
        raise SystemExit("Capture did not finish; inspect " + str(output.with_suffix(".log")))
    from analyze_shovel_latency import analyze
    analyze(output)
    import json
    valid = json.loads(output.with_suffix(".analysis.json").read_text(encoding="utf-8"))["measurement_valid"]
    print("Analysis:", output.with_suffix(".analysis.json"))
    print("CPU timeline:", output.with_suffix(".trace.json"))
    raise SystemExit(result or (0 if valid else 1))


if __name__ == "__main__":
    main()
