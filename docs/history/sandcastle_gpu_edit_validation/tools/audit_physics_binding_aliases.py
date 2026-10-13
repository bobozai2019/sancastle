"""Check source-declared image roles against captured per-stream binding aliases."""
import argparse
import hashlib
import json
from pathlib import Path
import re

parser=argparse.ArgumentParser()
parser.add_argument("comparison",type=Path)
args=parser.parse_args()
project=Path("D:/godot/project/sandcastle")
files=["shallow_edge_flux","shallow_drain_scale","shallow_update_state","erosion/sediment_step",
       "material/material_step","material/slope_relax","material/material_commit"]
programs=[]
for file in files:
    path=project/"shaders/simulation"/(file+".glsl")
    source=path.read_text(encoding="utf-8-sig")
    roles={name:("read" if "readonly" in qualifiers else "write" if "writeonly" in qualifiers else "atomic_or_rw")
           for qualifiers,name in re.findall(r"uniform\s+([^;{}]+image2D)\s+(\w+)\s*;",source)}
    assert roles
    programs.append({"source":str(path),"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"roles":roles})
comparison=json.loads(args.comparison.read_text())
assert comparison["group"]=="physics" and comparison["alignment_complete"]
rows=[]
for row in comparison["rows"]:
    candidates=[p for p in programs if set(p["roles"])==set(row["names"])]
    assert len(candidates)==1
    program=candidates[0]
    sides={}
    for side in ("active","worker"):
        graph={name:alias for name,alias,_,_ in row[side+"_binding_graph"]}
        reads={graph[name] for name,role in program["roles"].items() if role=="read"}
        writes={graph[name] for name,role in program["roles"].items() if role=="write"}
        atomics={graph[name] for name,role in program["roles"].items() if role=="atomic_or_rw"}
        sides[side]={"read_write_aliases":sorted(reads & writes),"atomic_aliases_other_images":sorted(atomics & (reads|writes)),
                     "atomic_images":[name for name,role in program["roles"].items() if role=="atomic_or_rw"]}
    rows.append({"ordinal":row["ordinal"],"active_event":row["active_event"],"worker_event":row["worker_event"],"source":program["source"],"sides":sides})
result={"pass":all(not d["read_write_aliases"] and not d["atomic_aliases_other_images"] for row in rows for d in row["sides"].values()),
        "programs":programs,"rows":rows,"scope":"Source image qualifiers and capture-local bindings for this frame only. dirty_max atomic access is retained. No claim about inter-pass synchronization, runtime initial inputs, or all frames."}
(args.comparison.parent/"physics_binding_alias_audit.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
print(json.dumps({"pass":result["pass"],"paired_dispatches":len(rows),"scope":result["scope"]},indent=2))
