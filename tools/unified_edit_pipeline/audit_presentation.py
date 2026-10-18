"""Audit sealed extraction/publication evidence, without treating screenshots as algorithm proof."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

from PIL import Image, ImageChops, ImageStat


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(folder: Path) -> dict:
    report = json.loads((folder / "report.json").read_text(encoding="utf-8"))
    checks: list[dict] = []

    def check(name: str, passed: bool) -> None:
        checks.append({"name": name, "pass": passed})

    check("runner_pass", report.get("pass") is True)
    archive_path = Path(report["source_zip"])
    check("archive_identity", sha(archive_path) == report["source_zip_sha256"])
    with zipfile.ZipFile(archive_path) as archive:
        check("archive_crc", archive.testzip() is None)
        index = json.loads(archive.read("evidence/source-index.json"))
        check("archive_index", index == report["sources"])
        for path, digest in index.items():
            check("source:" + path, hashlib.sha256(archive.read(path.removeprefix("res://"))).hexdigest() == digest)
    observations = {}
    for scene in sorted({run["scene"] for run in report["runs"]}):
        bake_dir, runtime_dir = folder / (scene + "_bake"), folder / (scene + "_runtime")
        bake = json.loads((bake_dir / "bake.json").read_text(encoding="utf-8"))
        probe = json.loads((runtime_dir / "probe.json").read_text(encoding="utf-8"))
        check(scene + ":probe", probe["pass"] is True and all(c["pass"] is True for c in probe["checks"]))
        check(scene + ":bake", bake["pass"] is True and all(c["pass"] is True for c in bake["checks"]))
        for phase in (bake_dir, runtime_dir):
            for name in ("stdout.txt", "probe.log"):
                text = (phase / name).read_text(encoding="utf-8", errors="replace")
                check(scene + ":" + phase.name + ":" + name,
                      re.search(r"ERROR:|SCRIPT ERROR:|\bleaked\b|Stray Node:|resources still in use", text, re.I) is None)
        metadata = bake["metadata"]
        packed_path = Path(metadata["scene"]["path"])
        text = packed_path.read_text(encoding="utf-8")
        check(scene + ":fully_flattened", re.search(r"^\[node.*\binstance=", text, re.M) is None)
        check(scene + ":no_live_world_resource", 'type="World3D"' not in text)
        check(scene + ":no_dynamic_rid_resource", 'type="Texture2DRD"' not in text)
        for key in ("scene", "seed", "original_png"):
            item = metadata[key]
            check(scene + ":artifact:" + key, sha(Path(item["path"])) == item["sha256"])
        check(scene + ":sampler_count_retained", probe["observations"]["boot_sampler_count"] == probe["observations"]["restore_sampler_count"] > 0)
        metrics = {}
        original = Image.open(bake_dir / "original.png").convert("RGB")
        for name in ("unified", "unified_tick", "unified_restored"):
            target = runtime_dir / (name + ".png")
            image = Image.open(target).convert("RGB")
            check(scene + ":image:" + name, image.size == original.size == (1280, 720) and len(image.getcolors(1024) or []) == 0)
            metrics[name] = {"sha256": sha(target), "mean_absolute_rgb_difference": ImageStat.Stat(ImageChops.difference(original, image)).mean}
        observations[scene] = {"materials": probe["observations"]["materials"],
                               "bound_materials": probe["observations"]["bound_materials"],
                               "samplers": probe["observations"]["boot_sampler_count"], "images": metrics}
    return {"pass": all(row["pass"] for row in checks), "checks": checks,
            "observations": observations, "source_count": len(report["sources"]),
            "runner_report_sha256": sha(folder / "report.json"),
            "auditor_sha256": sha(Path(__file__)),
            "image_scope": "Same initial domain/camera/1280x720. RGB differences are diagnostic only: frame timing and temporal rendering are not frozen; no similarity acceptance claim."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    result = audit(args.folder.resolve())
    target = args.folder / "audit.json"
    if target.exists():
        raise FileExistsError(target)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"pass": result["pass"], "checks": len(result["checks"]), "source_count": result["source_count"]}))
    raise SystemExit(0 if result["pass"] else 1)
