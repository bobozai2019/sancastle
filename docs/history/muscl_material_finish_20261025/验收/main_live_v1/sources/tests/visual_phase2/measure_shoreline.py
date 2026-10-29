"""Measure the fixed close-camera island edge in W02/W03 captures.

The same color classifier and crop are applied to both PNGs. This is a screen
space A/B diagnostic, not a substitute for the GPU wet/dry geometry probe.
"""

from pathlib import Path
import json
import sys

import numpy as np
from PIL import Image


def edge(png: Path, crop: tuple[int, int, int, int]) -> np.ndarray:
    frame = np.asarray(Image.open(png).convert("RGB"), dtype=np.int16)
    result = []
    x0, x1, y0, y1 = crop
    for x in range(x0, x1):
        strip = frame[y0:y1, x]
        sand = (strip[:, 0] > 205) & (strip[:, 0] > strip[:, 1] + 12) & (strip[:, 2] < 185)
        hits = np.flatnonzero(sand)
        result.append(y0 + int(hits[-1]) if len(hits) else -1)
    return np.asarray(result)


def metrics(y: np.ndarray) -> dict:
    valid = y[y >= 0]
    steps = np.abs(np.diff(valid))
    runs = np.split(valid, np.flatnonzero(np.diff(valid) != 0) + 1)
    return {
        "valid_columns": int(len(valid)),
        "mean_abs_first_difference_px": float(np.mean(steps)),
        "mean_abs_second_difference_px": float(np.mean(np.abs(np.diff(valid, 2)))),
        "unchanged_adjacent_columns": int(np.sum(np.diff(valid) == 0)),
        "max_step_px": int(np.max(steps)),
        "p95_step_px": float(np.percentile(steps, 95)),
        "longest_plateau_px": int(max(len(run) for run in runs)),
    }


if __name__ == "__main__":
    evidence = Path(__file__).resolve().parents[2] / "task" / "sandcastle_visual_reconstruction_phase2" / "验收"
    results = {}
    for camera, crop in {"close": (1060, 1280, 180, 450),
                         "oblique": (610, 780, 250, 430)}.items():
        before = metrics(edge(evidence / f"W02_water_{camera}.png", crop))
        candidates = {"W02": before}
        for level in (2, 4):
            png = evidence / f"W03_{level}_water_{camera}.png"
            if png.exists():
                candidates[f"W03_{level}"] = metrics(edge(png, crop))
        radial = evidence / f"W03_radial_2_water_{camera}.png"
        if radial.exists():
            candidates["W03_radial_2"] = metrics(edge(radial, crop))
        for label in ("W02_mask", "W03_mask_2", "W03_mask_4", "W03_midpoint_2"):
            png = evidence / f"{label}_water_{camera}.png"
            if png.exists():
                candidates[label] = metrics(edge(png, crop))
        before_mask = evidence / f"W02_mask_water_{camera}.png"
        after_mask = evidence / f"W03_mask_2_water_{camera}.png"
        if before_mask.exists() and after_mask.exists():
            a = edge(before_mask, crop)
            b = edge(after_mask, crop)
            valid = (a >= 0) & (b >= 0)
            delta = np.abs(a[valid] - b[valid])
            candidates["mask_displacement"] = {
                "max_px": int(np.max(delta)),
                "p95_px": float(np.percentile(delta, 95)),
                "median_px": float(np.median(delta)),
            }
        results[camera] = candidates
        if any(value.get("valid_columns", 100) < 100 for value in candidates.values()):
            sys.exit(f"{camera} classifier found too few columns")
    print(json.dumps(results, ensure_ascii=False, indent=2))
