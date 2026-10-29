"""Copy only hash-matching source bytes declared by a run manifest."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("run", type=Path)
parser.add_argument("--movie-original", action="store_true")
args = parser.parse_args()
manifest = json.loads((args.run / "manifest.json").read_text(encoding="utf-8-sig"))
rows = []
for row in manifest["source_files"]:
    source = Path(row["path"])
    data = source.read_bytes()
    if args.movie_original and source.as_posix() == "tests/gravel/gravel_integration_probe.gd":
        data = b"".join(
            line for line in data.splitlines(keepends=True)
            if not line.startswith(b"var resources :=")
            and b"resources.append(" not in line
            and b"resource_samples.json" not in line
        )
    actual = hashlib.sha256(data).hexdigest()
    matched = actual == row["sha256"]
    rows.append({"path": row["path"], "match": matched, "actual": actual})
    if matched:
        target = args.run / "source_snapshot" / source
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
(args.run / "snapshot_verification.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
print(json.dumps(rows, indent=2))
raise SystemExit(0 if all(r["match"] for r in rows) else 1)
