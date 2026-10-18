"""Build/check the two static GPU-clock variants without changing original assets."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[2]
    folder = project / "assets/water_material_natural_candidate"
    expression = "visual_time_s >= 0.0 ? visual_time_s : TIME"
    replacement = (
        "use_async_clock ? textureLod(async_clock, vec2(0.5), 0.0).r : "
        "(visual_time_s >= 0.0 ? visual_time_s : TIME)"
    )
    marker = "uniform float visual_time_s = -1.0;"
    declaration = marker + (
        "\nuniform bool use_async_clock = false;"
        "\nuniform sampler2D async_clock : filter_nearest, repeat_disable;"
    )
    outputs = {}
    rows = []
    for material, stem, sites in [("water", "rdc_water", 3), ("bed", "rdc_bed", 1)]:
        source = folder / (stem + ".gdshader")
        generated = folder / ("async_" + stem + ".gdshader")
        original = source.read_bytes()
        text = original.decode("utf-8").replace("\r\n", "\n")
        if text.count(expression) != sites or text.count(marker) != 1:
            raise RuntimeError(f"Unexpected clock interface: {source}")
        data = text.replace(marker, declaration).replace(expression, replacement).encode("utf-8")
        outputs[generated] = data
        rows.append({
            "material": material,
            "source": "res://" + source.relative_to(project).as_posix(),
            "source_sha256": hashlib.sha256(original).hexdigest(),
            "generated": "res://" + generated.relative_to(project).as_posix(),
            "generated_sha256": hashlib.sha256(data).hexdigest(),
            "time_sites": sites,
        })
    manifest = {"schema_version": 1, "transform": "completed_gpu_clock_v1", "variants": rows}
    outputs[folder / "async_clock_variants_v1.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    for path, data in outputs.items():
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise RuntimeError(f"Clock artifact differs from exact source transform: {path}")
        else:
            path.write_bytes(data)
    print(json.dumps({"pass": True, "mode": "check" if args.check else "build", "artifacts": len(outputs)}))


if __name__ == "__main__":
    main()
