"""Compare retained host evidence; never infer GPU consumption from host equality."""
import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare(left, right):
    mismatches = [i for i in range(min(len(left), len(right))) if left[i] != right[i]]
    return {"equal": left == right, "active_count": len(left), "worker_count": len(right),
            "mismatch_indices": mismatches, "first_mismatch": None if not mismatches else {
                "index": mismatches[0], "active": left[mismatches[0]], "worker": right[mismatches[0]]}}


parser = argparse.ArgumentParser()
parser.add_argument("evidence", type=Path)
args = parser.parse_args()
source = args.evidence / "parameter_evidence.json"
data = json.loads(source.read_text(encoding="utf-8-sig"))
sections = {key: compare(data["active"][key], data["worker"][key]) for key in
            ("substeps", "material_pushes", "compiled_shader_sha256")}
manifest = json.loads((args.evidence / "manifest.json").read_text(encoding="utf-8-sig"))
changed = [item["path"] for item in manifest if not Path(item["path"]).is_file()
           or digest(Path(item["path"])) != item["sha256"]]
result = {"source": source.name, "sha256": digest(source), "sections": sections,
          "all_host_evidence_equal": all(item["equal"] for item in sections.values()),
          "strict_native_replay": data["strict_native_replay"], "changed_manifest_sources": changed,
          "scope": data["scope"], "conclusion": "Host equality does not prove native DXIL identity, resource inputs, or GPU consumption."}
(args.evidence / "parameter_analysis.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps(result, indent=2))
