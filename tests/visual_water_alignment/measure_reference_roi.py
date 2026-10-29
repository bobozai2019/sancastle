"""Measure fixed local image features for the W07 visual target board.

This is diagnostic image evidence, not an automatic visual PASS decision.
ROIs are 0-based [left, top, right, bottom] pixels in each saved PNG.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"D:/godot/project/sandcastle")
REF = ROOT / "tests/fixtures/visual_water_alignment"
PROTO = ROOT / "tests/fixtures/visual_water_alignment/reference_prototype_20261007"
OUT = ROOT / "test_output/sandcastle_water_render_alignment/验收/W07_roi_metrics.json"
CASES = {
    "test35": (REF / "test35-frame20641_replayed_0.png", {
        "shallow": (720, 620, 1080, 860), "deep": (1660, 510, 1810, 770)}),
    "test1": (REF / "test1_replayed_0.png", {
        "shallow": (750, 575, 980, 730), "deep": (1500, 570, 1710, 770)}),
    "reference_fixed_initial": (PROTO / "wr_w07_reference_input_20261007_water_oblique.png", {
        "shallow": (600, 465, 780, 635), "deep": (125, 380, 340, 550)}),
    "reference_coupled_initial": (PROTO / "wr_w07_reference_input_20261007_coupled_oblique.png", {
        "shallow": (600, 465, 780, 635), "deep": (125, 380, 340, 550)}),
}
WEIGHTS = np.array([0.2126, 0.7152, 0.0722])
report = {"method": "median 8-bit sRGB luma proxy with Rec.709 weights; no linearization; descriptive only",
          "cases": {}}
for name, (path, rois) in CASES.items():
    image = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    case = {"path": str(path), "size": [int(image.shape[1]), int(image.shape[0])], "rois": {}}
    for key, (left, top, right, bottom) in rois.items():
        region = image[top:bottom, left:right]
        case["rois"][key] = {"xyxy": [left, top, right, bottom],
                              "median_rgb": np.median(region.reshape(-1, 3), axis=0).tolist(),
                              "median_luma_proxy": float(np.median(region @ WEIGHTS))}
    case["deep_to_shallow_median_luma"] = (case["rois"]["deep"]["median_luma_proxy"] /
                                            case["rois"]["shallow"]["median_luma_proxy"])
    report["cases"][name] = case

test1 = np.asarray(Image.open(REF / "test1_replayed_0.png").convert("RGB"), dtype=np.float64)
line = test1[600, 1180:1290] @ WEIGHTS
bright = line > 230.0
runs = []
start = None
for index, value in enumerate(bright):
    if value and start is None:
        start = index
    elif not value and start is not None:
        runs.append([1180 + start, 1180 + index, index - start])
        start = None
if start is not None:
    runs.append([1180 + start, 1290, len(bright) - start])
report["test1_wave_line"] = {"y": 600, "x_range": [1180, 1290], "bright_luma_threshold": 230,
                             "bright_runs_xy_width": runs}
OUT.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
