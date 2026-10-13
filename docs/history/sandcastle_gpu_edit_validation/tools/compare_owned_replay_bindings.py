"""Compare matched simulation dispatches from one owned, strictly failed run."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("active", type=Path)
parser.add_argument("worker", type=Path)
parser.add_argument("--group", choices=("all","physics","editor","visual"), default="all")
args = parser.parse_args()


def load(folder):
    name = json.loads((folder / "binding_probe_latest.json").read_text())["report"]
    report = json.loads((folder / name).read_text())
    assert report["pass"]
    assert hashlib.sha256(Path(report["capture"]).read_bytes()).hexdigest() == report["capture_sha256"]
    return name, report


def split(report):
    selected, skipped = [], []
    for row in report["rows"]:
        names = set(row.get("readwrite", []))
        if names == {"dest_buffer"} or names == {"rock_state", "sand_state", "packed_heights"} or names == {"water_state", "momentum_x_state", "momentum_z_state", "tile_max_out"}:
            skipped.append({"event": row["event"], "names": sorted(names)})
        else:
            if any(name.startswith("RWByteAddressBuffer") for name in names) or names == {"h0","h1","s0","s1","x0","x1","z0","z1"}:
                group="editor"
            elif names & {"edge_x_out","drain_scale_out","outgoing_flux_out","dirty_max_um","wetness_out","wetness_src"}:
                group="physics"
            else:
                group="visual"
            if args.group=="all" or args.group==group: selected.append(row)
            else: skipped.append({"event":row["event"],"names":sorted(names),"group":group,"reason":"separate stream comparison"})
    return selected, skipped


def checked(folder, meta):
    data = (folder / meta["path"]).read_bytes()
    assert hashlib.sha256(data).hexdigest() == meta["sha256"]
    return data


def exports(row):
    return {row["readwrite"][binding["reflection_index"]]: binding["export"]
            for binding in row["resource_bindings"] if "export" in binding}


a_name, a = load(args.active)
b_name, b = load(args.worker)
ar, skipped_a = split(a)
br, skipped_b = split(b)
rows = []
alias_a, alias_b = {}, {}


def binding_graph(row, aliases):
    graph = []
    for binding in row["resource_bindings"]:
        resource = binding["resource"]
        if resource not in aliases:
            aliases[resource] = len(aliases)
        graph.append((row["readwrite"][binding["reflection_index"]], aliases[resource], binding["format"], binding["type"]))
    return graph


for ordinal, (x, y) in enumerate(zip(ar, br)):
    signature = (x.get("readwrite"), x.get("readonly"), x["dimensions"]) == (y.get("readwrite"), y.get("readonly"), y["dimensions"])
    constant_equal = [c.get("buffer_hex") for c in x["constants"]] == [c.get("buffer_hex") for c in y["constants"]]
    constant_complete = all("buffer_hex" in c and "binding_error" not in c for row in (x,y) for c in row["constants"])
    assert x["native_shader"]["size"] > 0 and y["native_shader"]["size"] > 0
    shader_equal = checked(args.active, x["native_shader"]) == checked(args.worker, y["native_shader"])
    graph_a, graph_b = binding_graph(x,alias_a), binding_graph(y,alias_b)
    xe, ye = exports(x), exports(y)
    fields = []
    for name in sorted(xe.keys() | ye.keys()):
        if name not in xe or name not in ye:
            fields.append({"name": name, "missing": True, "byte_equal": False})
            continue
        left, right = checked(args.active, xe[name]), checked(args.worker, ye[name])
        la, lb = np.frombuffer(left, dtype="<f4"), np.frombuffer(right, dtype="<f4")
        different = np.flatnonzero(np.frombuffer(left, dtype="<u4") != np.frombuffer(right, dtype="<u4"))
        fields.append({"name": name, "byte_equal": left == right, "different_cells": len(different),
                       "max_abs": float(np.max(np.abs(la.astype(float) - lb.astype(float)))),
                       "samples": [{"cell": int(i), "active": float(la[i]), "worker": float(lb[i])} for i in different[:5]]})
    rows.append({"ordinal": ordinal, "active_event": x["event"], "worker_event": y["event"],
                 "signature_equal": signature, "names": x.get("readwrite"), "constant_bytes_equal": constant_equal,
                 "constant_capture_complete": constant_complete, "binding_graph_equal": graph_a == graph_b,
                 "active_binding_graph": graph_a, "worker_binding_graph": graph_b,
                 "native_shader_equal": shader_equal, "shader_encoding": x["native_shader"]["encoding"], "sand_fields": fields})
result = {"active_report": a_name, "worker_report": b_name, "active_selected": len(ar), "worker_selected": len(br),
          "group":args.group,
          "alignment_complete": len(ar) == len(br) and all(r["signature_equal"] for r in rows),
          "constants_equal": all(r["constant_bytes_equal"] for r in rows),
          "constant_capture_complete": all(r["constant_capture_complete"] for r in rows),
          "binding_graph_equal": all(r["binding_graph_equal"] for r in rows),
          "native_shaders_equal": all(r["native_shader_equal"] for r in rows),
          "skipped_active": skipped_a, "skipped_worker": skipped_b, "rows": rows,
          "scope": "One strictly failed live run; simulation dispatch sequence comparison excludes rendering dest_buffer, collision packed_heights and CFL timing dispatches, with all exclusions retained. Sand exports are post-event replay results, not original live pass snapshots. No first-divergence or full-input equality claim."}
output = args.worker.parent / ("failed_replay_binding_%s_%s%s.json" % (args.active.name,args.worker.name,"" if args.group=="all" else "_"+args.group))
output.write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps({key: value for key, value in result.items() if key not in ("rows", "skipped_active", "skipped_worker")}, indent=2))
print("sand_pairs=", sum(len(r["sand_fields"]) for r in rows), "different_sand_pairs=", sum(not f["byte_equal"] for r in rows for f in r["sand_fields"]))
