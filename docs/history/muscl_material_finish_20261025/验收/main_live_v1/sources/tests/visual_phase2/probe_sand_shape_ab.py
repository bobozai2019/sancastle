"""S01 vectorized mirror of slope_relax.glsl for equal-volume shape A/B."""

import json
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "task" / "sandcastle_visual_reconstruction_phase2" / "验收"
N = 256
CELL = 0.125
TICKS = (0, 30, 90, 300)
RELAX_BLEND = 0.5  # min(15/s / 30 Hz, 1)
yy, xx = np.mgrid[:N, :N]


def initial_tower(center_x: int) -> np.ndarray:
    dx = xx - center_x
    dz = yy - 128
    tower = np.where((abs(dx) <= 8) & (abs(dz) <= 8), 1.8, 0.0)
    # A visible top notch and narrow groove. Both A/B start from identical mass.
    notch = (dx >= 5) & (dz >= 3) & (abs(dx) <= 8) & (abs(dz) <= 8)
    tower[notch] = 1.55
    groove = (abs(dx) <= 1) & (dz >= -1) & (dz <= 1)
    tower[groove] = 1.5
    return tower.astype(np.float64)


def step(sand: np.ndarray, compact: np.ndarray, wet: np.ndarray,
         cohesion_m: float) -> np.ndarray:
    delta = np.zeros_like(sand)
    for axis in (0, 1):
        a_slice = (slice(None, -1), slice(None)) if axis == 0 else (slice(None), slice(None, -1))
        b_slice = (slice(1, None), slice(None)) if axis == 0 else (slice(None), slice(1, None))
        a = sand[a_slice]
        b = sand[b_slice]
        ca = compact[a_slice]
        cb = compact[b_slice]
        wa = wet[a_slice]
        wb = wet[b_slice]
        donor_a = a >= b
        donor_stock = np.where(donor_a, a, b)
        donor_comp = np.where(donor_a, ca, cb)
        donor_wet = np.where(donor_a, wa, wb)
        edge_wet = 0.5 * (wa + wb)
        edge_comp = 0.5 * (ca + cb)
        repose = CELL * (0.674 + (1.0 - 0.674) * edge_wet + 0.3 * edge_comp)
        # A bounded yield height from the uphill cell's compaction. Collapse
        # can remove it by reducing that cell's compaction; both edge cells
        # derive exactly the same donor and threshold.
        def smoothstep(low, high, value):
            t = np.clip((value - low) / (high - low), 0, 1)
            return t * t * (3 - 2 * t)
        moisture_factor = (0.8 + 0.2 * smoothstep(0.05, 0.35, donor_wet)
                           - 0.6 * smoothstep(0.65, 1.0, donor_wet))
        yield_height = cohesion_m * np.clip((donor_comp - 0.6) / 0.35, 0, 1) * moisture_factor
        excess = np.maximum(np.abs(a - b) - repose - yield_height, 0)
        flux = np.minimum(excess * 0.5 * RELAX_BLEND, donor_stock * 0.25)
        signed = np.where(donor_a, -flux, flux)
        delta[a_slice] += signed
        delta[b_slice] -= signed
    next_sand = sand + delta
    if next_sand.min() < -1e-10:
        raise AssertionError(f"negative sand: {next_sand.min()}")
    return next_sand


def measure(sand: np.ndarray, initial: np.ndarray, center_x: int) -> dict:
    crop = (slice(120, 137), slice(center_x - 8, center_x + 9))
    base_mask = initial[crop] > 0.0
    current_mask = sand[crop] > 0.9
    intersection = np.count_nonzero(base_mask & current_mask)
    union = np.count_nonzero(base_mask | current_mask)
    return {
        "peak_height_m": float(sand[crop].max()),
        "peak_retained_fraction": float(sand[crop].max() / initial[crop].max()),
        "high_shape_iou": intersection / union,
        "total_sand_m3": float(sand.sum() * CELL * CELL),
        "nonnegative": bool(sand.min() >= 0),
    }


def run() -> None:
    initial = initial_tower(128)
    base_width_m = 17 * CELL
    packed = np.where(initial > 0, 0.95, 0.1)
    loose = np.where(initial > 0, 0.1, 0.1)
    packed_wet = np.where(initial > 0, 0.35, 0.05)
    loose_wet = np.full_like(initial, 0.05)
    cases = {
        "current_packed": (packed, packed_wet, 0.0),
        "prototype_packed": (packed, packed_wet, 2.0),
        "current_loose": (loose, loose_wet, 0.0),
        "prototype_loose": (loose, loose_wet, 2.0),
    }
    output = {
        "cell_size_m": CELL,
        "grid_size": N,
        "initial_peak_m": float(initial.max()),
        "base_width_m": base_width_m,
        "initial_height_base_ratio": float(initial.max() / base_width_m),
        "initial_volume_m3": float(initial.sum() * CELL * CELL),
        "fixture_details": "17x17-cell tower, 0.25 m top notch, 0.30 m groove; equal initial sand volume for all cases",
        "method": "NumPy edge-pair mirror of T05 slope_relax.glsl, 30 Hz, fixed flat rock, no water/erosion",
        "cases": {},
    }
    for name, (compaction, wetness, cohesion) in cases.items():
        sand = initial.copy()
        samples = {}
        for tick in range(TICKS[-1] + 1):
            if tick in TICKS:
                samples[str(tick)] = measure(sand, initial, 128)
            if tick < TICKS[-1]:
                sand = step(sand, compaction, wetness, cohesion)
        output["cases"][name] = {
            "compaction_top": float(compaction[128, 128]),
            "wetness_top": float(wetness[128, 128]),
            "cohesion_height_max_m": cohesion,
            "samples": samples,
        }
    path = OUT / "S01_sand_shape_ab.json"
    path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"initial_height_base_ratio": output["initial_height_base_ratio"],
                      "tick300": {name: data["samples"]["300"]
                                  for name, data in output["cases"].items()}},
                     ensure_ascii=False))


if __name__ == "__main__":
    run()
