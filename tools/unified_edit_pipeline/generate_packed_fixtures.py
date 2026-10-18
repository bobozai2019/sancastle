"""Generate deterministic, private old/new water-kernel comparison inputs."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    z, x = np.indices((256, 256))
    rng = np.random.default_rng(18205)
    cases = []
    for name in ["full", "slope", "noise", "split", "islands", "shallow", "zero_demand",
                 "dry", "capacity", "sealed", "32_components", "33_components", "nine_runs", "negative", "nan"]:
        a = np.zeros((256, 256, 8), dtype="<f4")
        a[:, :, 0] = .4
        a[:, :, 2:6] = [.15, .03, .03, -.01]
        if name in ["slope", "noise", "split", "islands", "shallow"]:
            a[:, :, 0] = .25+x*.0008+z*.0003+rng.random((256, 256))*.001
            a[:, :, 2] = rng.uniform(.0011, .3, (256, 256))
            a[:, :, 3] = rng.uniform(0, .05, (256, 256))
            a[:, :, 4:6] = rng.uniform(-.1, .1, (256, 256, 2))
        if name == "shallow":
            a[:, :, 2] = rng.uniform(.00101, .007, (256, 256))
        if name == "split":
            a[:, 128, 6] = 1
        if name == "islands":
            a[60:65, :, 6] = 1
            a[180:185, :, 6] = 1
            a[:, 128:130, 6] = 1
        if name == "dry":
            a[:, :, 2:6] = 0
        if name in ["capacity", "sealed"]:
            a[:, :, 2:6] = 0
            mask = ((x >= 120) & (x < 136) & (z >= 120) & (z < 136)) if name == "capacity" else ((x == 128) & (z == 128))
            a[mask, 2:5] = [.005, .002, .001]
        if name in ["32_components", "33_components"]:
            mask = (z % 4 == 0) & (z//4 < int(name[:2]))
            a[~mask, 2:6] = 0
        if name == "nine_runs":
            a[x % 4 >= 2, 2:6] = 0
        a[:, :, 1] = a[:, :, 0]
        mask = (abs(x-128) < 6) & (abs(z-128) < 8)
        if "components" in name:
            mask = x < 12
        a[mask, 1] += np.float32(.09)
        a[(x > 120) & (x < 128) & (z > 120) & (z < 135), 1] -= np.float32(.04)
        if name == "zero_demand":
            a[:, :, 1] = a[:, :, 0]-.01
        if name in ["negative", "nan"]:
            a[3, 4, 2] = -.1 if name == "negative" else np.nan
        path = args.output/(name+".bin")
        a.tofile(path)
        cases.append({"name": name, "file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    (args.output/"manifest.json").write_text(json.dumps({"seed": 18205, "cases": cases}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
