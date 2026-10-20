"""Design evidence only: current GPU data vs an idealized 1D candidate model."""
import hashlib
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "test_output/wave_solution_20261020"


def identity(path):
    return {"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def mc_rhs(values, dx, speed):
    left = values - np.roll(values, 1)
    right = np.roll(values, -1) - values
    slope = np.where(left * right > 0, np.sign(left) *
                     np.minimum(np.minimum(2 * abs(left), 2 * abs(right)),
                                abs((left + right) / 2)), 0)
    flux = speed * (values + 0.5 * slope)
    return -(flux - np.roll(flux, 1)) / dx


def candidate(dx, wavelength):
    # One rightgoing characteristic of the linearized constant-depth SWE.
    # Periodic domain; normalized amplitude; no bed, wet/dry, source, cap or GPU.
    speed = math.sqrt(9.81 * 0.1)
    x = (np.arange(round(32 / dx)) + 0.5) * dx
    initial = np.sin(2 * np.pi * x / wavelength)
    values = initial.copy()
    dt = (1 / 30) * (dx / 0.125)  # Hold Courant number fixed.
    rows = []
    coefficient0 = np.mean(initial * np.exp(-2j * np.pi * x / wavelength))
    for step in range(round(4 / dt) + 1):
        if step % round(0.5 / dt) == 0:
            coefficient = np.mean(values * np.exp(-2j * np.pi * x / wavelength))
            expected = coefficient0 * np.exp(-2j * np.pi * speed * step * dt / wavelength)
            rows.append({"time_s": step * dt, "amplitude_ratio": float(abs(coefficient / coefficient0)),
                         "wrapped_phase_error_rad": float(np.angle(coefficient / expected)),
                         "mean_error": float(values.mean() - initial.mean())})
        if step < round(4 / dt):
            first = values + dt * mc_rhs(values, dx, speed)
            values = 0.5 * values + 0.5 * (first + dt * mc_rhs(first, dx, speed))
    return {"scope": "CPU linearized single characteristic; NOT the production candidate",
            "dx_m": dx, "wavelength_m": wavelength, "dt_s": dt, "rows": rows}


def main():
    diagnosis_path = OUT / "current_flat_recheck/diagnosis.json"
    diagnosis = json.loads(diagnosis_path.read_text(encoding="utf-8"))
    assert diagnosis["pass"] and not diagnosis["source_drift"]
    gpu = {}
    checked = 0
    for case in diagnosis["cases"]:
        for snapshot in case["snapshots"]:
            assert snapshot["published_matches"]
            for field in snapshot["fields"].values():
                path = Path(field["path"])
                assert path.stat().st_size == field["bytes"]
                assert hashlib.sha256(path.read_bytes()).hexdigest() == field["sha256"]
                checked += 1
        if not case["id"].startswith("sine"):
            continue
        wavelength = case["initial_condition"]["wavelength_m"]
        x = (np.arange(256) + 0.5 - 128) * 0.125
        mask = abs(x) < 4
        rows = []
        for snapshot in case["snapshots"]:
            h = np.fromfile(snapshot["fields"]["water"]["path"], dtype="<f4").reshape(256, 256)[128, mask].astype(float)
            amplitude = abs(2 * np.mean((h - h.mean()) * np.exp(-2j * np.pi * x[mask] / wavelength)))
            if not rows:
                amplitude0 = amplitude
            courant = math.sqrt(0.981) / 30 / 0.125
            theta = 2 * math.pi * 0.125 / wavelength
            gain = complex(1 - courant * (1 - math.cos(theta)), -courant * math.sin(theta))
            rows.append({"time_s": snapshot["time_s"], "tick": snapshot["tick"],
                         "amplitude_ratio": amplitude / amplitude0,
                         "linear_discrete_prediction": abs(gain) ** snapshot["tick"]})
        gpu[case["id"]] = rows
    report = {
        "scope": "Proposal evidence; no production algorithm change or performance acceptance",
        "script": identity(Path(__file__)), "gpu_diagnosis": identity(diagnosis_path),
        "raw_files_verified": checked, "gpu_measured": gpu,
        "candidate_model": [candidate(dx, wavelength) for dx in [0.125, 0.0625] for wavelength in [0.5, 1, 2, 4]],
        "finite_depth_linear_gravity_wave": [
            {"depth_m": depth, "wavelength_m": wavelength,
             "shallow_speed_m_s": math.sqrt(9.81 * depth),
             "finite_depth_phase_speed_m_s": math.sqrt(9.81 * math.tanh(2 * math.pi * depth / wavelength) / (2 * math.pi / wavelength))}
            for depth in [0.05, 0.1, 0.2] for wavelength in [0.5, 1, 2, 4]],
    }
    (OUT / "model_comparison.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    for name, rows in gpu.items():
        print(name, [(row["tick"], round(row["amplitude_ratio"], 6)) for row in rows if row["tick"] in [30, 60]])
    for row in report["candidate_model"]:
        result = next(value for value in row["rows"] if value["time_s"] == 2)
        print("MODEL ONLY", row["dx_m"], row["wavelength_m"], result["amplitude_ratio"])
    print("Verified raw files:", checked)


if __name__ == "__main__":
    main()
