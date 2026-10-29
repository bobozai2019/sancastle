"""Compare row-run connectivity with independent cell BFS on native fixture input."""
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import numpy as np

p = argparse.ArgumentParser()
p.add_argument("run", type=Path)
p.add_argument("--prefix", default="initial")
a = p.parse_args()
water_path = a.run / f"{a.prefix}_water.bin"
obstacle_path = a.run / f"{a.prefix}_obstacle.bin"
water = np.fromfile(water_path, dtype="<f4")
n = int(np.sqrt(water.size))
assert n * n == water.size
obstacle = np.fromfile(obstacle_path, dtype="u1").reshape(n, n)
wet = (water.reshape(n, n) > np.float32(.001)) & (obstacle < 128)
segments, rows, parents = [], [], []
for z, row in enumerate(wet):
    starts = np.flatnonzero(row & ~np.r_[False, row[:-1]])
    ends = np.flatnonzero(row & ~np.r_[row[1:], False])
    nodes = []
    for x0, x1 in zip(starts, ends):
        node = len(parents)
        nodes.append(node)
        parents.append(node)
        segments.append((z, int(x0), int(x1)))
    rows.append(nodes)

def root(node):
    while parents[node] != node:
        node = parents[node]
    return node

for z in range(1, n):
    for node in rows[z]:
        for prev in rows[z - 1]:
            if max(segments[node][1], segments[prev][1]) <= min(segments[node][2], segments[prev][2]):
                x, y = root(node), root(prev)
                parents[max(x, y)] = min(x, y)
roots = sorted({root(i) for i in range(len(parents))})
ranks = {r: i for i, r in enumerate(roots)}
run_labels = np.full((n, n), -1, dtype="<i4")
for node, (z, x0, x1) in enumerate(segments):
    run_labels[z, x0:x1 + 1] = ranks[root(node)]
bfs_labels = np.full((n, n), -1, dtype="<i4")
components = []
for z in range(n):
    for x in range(n):
        if not wet[z, x] or bfs_labels[z, x] >= 0:
            continue
        label = len(components)
        queue = deque([(z, x)])
        bfs_labels[z, x] = label
        count = 0
        while queue:
            zz, xx = queue.popleft()
            count += 1
            for rz, rx in ((zz - 1, xx), (zz + 1, xx), (zz, xx - 1), (zz, xx + 1)):
                if 0 <= rz < n and 0 <= rx < n and wet[rz, rx] and bfs_labels[rz, rx] < 0:
                    bfs_labels[rz, rx] = label
                    queue.append((rz, rx))
        components.append({"first_cell": z * n + x, "cells": count})
run_labels.tofile(a.run / "wet_run_labels.bin")
bfs_labels.tofile(a.run / "wet_bfs_labels.bin")
report = {"pass": bool(np.array_equal(run_labels, bfs_labels)), "grid": n,
          "wet_cells": int(wet.sum()), "segments": len(parents),
          "max_runs_per_row": max(map(len, rows)), "components": components,
          "scope": "CPU connectivity cross-check on native input; does not prove GPU DSU execution",
          "sources": [{"file": f.name, "sha256": hashlib.sha256(f.read_bytes()).hexdigest()} for f in (water_path, obstacle_path)],
          "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(a.run / "wet_run_graph.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps({k: report[k] for k in ("pass", "wet_cells", "segments", "max_runs_per_row", "components")}))
