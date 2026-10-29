"""Independent CPU check of the real main-scene fill/dig GPU readbacks."""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

project = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1])


def field(index, name):
    return np.fromfile(output / f"snapshot_{index}_{name}.bin", dtype="<f4").astype(np.float64)


x, z = np.meshgrid((np.arange(256) + .5 - 128) * .125,
                   (np.arange(256) + .5 - 128) * .125)
radial = np.stack([x.ravel(), z.ravel()], axis=1)
distance = np.linalg.norm(radial, axis=1)[:, None]
direction = np.divide(radial, distance, out=np.zeros_like(radial), where=distance > 0)
checks = []
for index, edit in enumerate(["fill", "dig"]):
    h = field(index, "water")
    db = field(index + 1, "sand") - field(index, "sand")
    q = np.stack([field(index, "momentum_x"), field(index, "momentum_z")], axis=1)
    actual = np.stack([field(index + 1, "momentum_x"), field(index + 1, "momentum_z")], axis=1)
    expected = q + h[:, None] * direction * (db[:, None] / .2)
    speed = np.linalg.norm(expected, axis=1) / np.maximum(h, .001)
    expected *= np.minimum(1, 4 / np.maximum(speed, 1e-30))[:, None]
    expected[h <= .001] = q[h <= .001]
    error = float(np.max(np.abs(expected - actual)))
    changed = int(np.count_nonzero(np.any(q != actual, axis=1)))
    checks.append(dict(edit=edit, changed_momentum_cells=changed,
                       max_abs_q_error=error, passed=error < 2e-6 and changed > 0))
probe = json.loads((output / "probe.json").read_text(encoding="utf-8"))
sources = probe["observations"]["sources"]
production_paths = ["scripts/simulation/unified_edit/water_response.gd",
                    "scripts/simulation/unified_edit/water_response.glsl",
                    "scripts/beach/unified_playable_entry.gd"]
pinned = all(sources.get("res://" + path) == hashlib.sha256((project / path).read_bytes()).hexdigest()
             for path in production_paths)
report = dict(cpu_reference=checks, production_sources_pinned=pinned,
              passed=pinned and probe["pass"] and all(check["passed"] for check in checks))
(output / "cpu_reference.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report))
sys.exit(0 if report["passed"] else 1)
