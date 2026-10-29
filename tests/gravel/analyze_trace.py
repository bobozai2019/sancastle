"""Export one tracked ID and exact dry-position checks from GPU probe JSONL."""
import argparse
import csv
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("run", type=Path)
parser.add_argument("--id", type=int, default=325)
parser.add_argument("--scene", default="test1_backwash")
args = parser.parse_args()
rows = []
with (args.run / "trace.jsonl").open(encoding="utf-8") as stream:
    for line in stream:
        row = json.loads(line)
        if row["id"] == args.id and row["scene"] == args.scene:
            rows.append(row)
target = args.run / f"particle_{args.id}.csv"
with target.open("w", newline="", encoding="utf-8") as stream:
    writer = csv.writer(stream)
    writer.writerow(["tick", "sim_s", "render_frame", "x_m", "y_m", "z_m", "wet", "depth_m", "local_u_x_m_s"])
    for row in rows:
        writer.writerow([row["tick"], row["simulation_seconds"], row["render_frame"], *row["p"], row["wet"], row["local_h"], row["local_u"][0]])
dry_pairs = [
    (a["tick"], b["tick"])
    for a, b in zip(rows, rows[1:])
    if a["wet"] == b["wet"] == 0
    and a["p"][0] == b["p"][0]
    and a["p"][2] == b["p"][2]
]
summary = {"id": args.id, "scene": args.scene, "sample_count": len(rows), "exact_dry_horizontal_pairs": dry_pairs, "local_sampling": "at completed-state destination; not pre-step field", "source": str(args.run / "trace.jsonl")}
(args.run / f"particle_{args.id}_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
print(target)
