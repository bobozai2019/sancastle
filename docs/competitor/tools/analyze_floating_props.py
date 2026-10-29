"""Read-only census of packaged Buoyancy/physics resources; no game methods.

Reuses historical raw files only after source-range and hash verification.
Fresh UnityPy trees cover engine physics types, never custom business tails.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import platform
import re
import struct
import sys


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def identity(path):
    with path.open("rb") as stream:
        sha = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    root, out = args.root.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {"schema_version": 1, "date": "2026-10-18",
              "scope": "sharedassets0.assets Buoyancy census, engine physics trees and source-range validation; no game methods, live trajectories or model/texture payload export",
              "command": sys.argv, "python": platform.python_version(),
              "tool": identity(Path(__file__).resolve()), "sources": [],
              "historical_artifacts": [], "objects": [], "props": [], "errors": []}
    try:
        historical = root / "test_output/competitor_transport_20261012"
        inventory = read(root / "docs/competitor/transport_evidence_inventory.json")
        names = {"sharedassets0.assets", "globalgamemanagers.assets", "GameAssembly.dll", "global-metadata.dat"}
        for expected in inventory["sources"]:
            path = Path(expected["path"])
            if path.name not in names:
                continue
            actual = identity(path)
            report["sources"].append(actual)
            assert actual["sha256"] == expected["sha256"] and actual["bytes"] == expected["bytes"], path
        for suffix in ("physical_objects.json", "raw_index.json", "technical_fields.json", "buoyancy_config.json"):
            expected = next(x for x in inventory["current_evidence"] if x["path"].endswith(suffix))
            actual = identity(Path(expected["path"]))
            report["historical_artifacts"].append(actual)
            assert actual["sha256"] == expected["sha256"] and actual["bytes"] == expected["bytes"], suffix
        sys.path.insert(0, str(root / "tests/investigation/brush_hit_competitor/deps"))
        import UnityPy
        report["unitypy"] = UnityPy.__version__
        source = root / "sandcastlegame/Sandcastle_Data/sharedassets0.assets"
        source_bytes = source.read_bytes()
        env = UnityPy.load(str(source))
        live = {str(x.path_id): x for x in env.objects if x.assets_file.name == source.name}
        all_old = read(historical / "package_v4/physical_objects.json")
        old = {x["path_id"]: x for x in all_old if Path(x["source"]).name == source.name}
        indices = {Path(x["path"]).name: x for x in read(historical / "package_v4/raw_index.json")}
        configs = read(historical / "analysis_v4/buoyancy_config.json")
        verified = {}

        def check(pid):
            pid = str(pid)
            if pid in verified:
                return verified[pid]
            old_obj, obj = old[pid], live[pid]
            path = Path(old_obj["raw_path"])
            raw = path.read_bytes()
            index = indices[path.name]
            offset = int(index["offset"])
            assert Path(index["source"]) == source
            assert offset == obj.byte_start and len(raw) == index["bytes"] == obj.byte_size
            assert hashlib.sha256(raw).hexdigest() == index["sha256"]
            assert raw == source_bytes[offset:offset + len(raw)] == obj.get_raw_data()
            assert obj.type.name == old_obj["type"]
            if obj.type.name == "MonoBehaviour":
                assert old_obj["script_class"] == "Buoyancy"
                tree = old_obj["tree"]  # Only header; tail re-decoded below.
            else:
                tree = obj.read_typetree()
                assert tree == old_obj["tree"], (pid, "fresh tree differs")
            report["objects"].append({"path_id": pid, "type": obj.type.name,
                                      "source": str(source), "offset": offset,
                                      "bytes": len(raw), "raw_path": str(path),
                                      "sha256": index["sha256"], "matches_source_range": True,
                                      "tree_check": "header_only_tail_decoded_separately" if obj.type.name == "MonoBehaviour" else "fresh_UnityPy_matches_history"})
            verified[pid] = (tree, raw)
            return tree, raw

        script = next(x for x in all_old if x["type"] == "MonoScript" and x["tree"].get("m_ClassName") == "Buoyancy")
        first = live[configs[0]["path_id"]]
        script_ref = struct.unpack_from("<iq", first.get_raw_data(), 16)
        script_live = first.read(check_read=False).m_Script.deref()
        assert script_live.assets_file.name == Path(script["source"]).name
        assert str(script_live.path_id) == script["path_id"] and script_live.read_typetree() == script["tree"]
        script_raw = Path(script["raw_path"]).read_bytes()
        script_index = indices[Path(script["raw_path"]).name]
        with Path(script["source"]).open("rb") as stream:
            stream.seek(int(script_index["offset"]))
            assert stream.read(script_index["bytes"]) == script_raw == script_live.get_raw_data()
        assert hashlib.sha256(script_raw).hexdigest() == script_index["sha256"]
        report["objects"].append({"path_id": script["path_id"], "type": "MonoScript", "source": script["source"],
                                  "offset": int(script_index["offset"]), "bytes": len(script_raw),
                                  "raw_path": script["raw_path"], "sha256": script_index["sha256"],
                                  "matches_source_range": True, "tree_check": "fresh_UnityPy_matches_history"})
        # Check only engine header pointers for all MonoBehaviours; do not read other custom tails.
        ids = sorted(str(o.path_id) for o in live.values() if o.type.name == "MonoBehaviour"
                     and struct.unpack_from("<iq", o.get_raw_data(), 16) == script_ref)
        assert ids == sorted(x["path_id"] for x in configs)
        report["census"] = {"container": str(source), "unity_version": str(first.assets_file.unity_version),
                            "script_container": script["source"], "script_reference": script_ref,
                            "buoyancy_script_path_id": script["path_id"], "buoyancy_path_ids": ids,
                            "count": len(ids), "unique_root_names": len({x["game_object"] for x in configs})}
        for config in sorted(configs, key=lambda x: x["game_object"]):
            header, raw = check(config["path_id"])
            go_id = config["game_object_path_id"]
            assert struct.unpack_from("<iq", raw, 0) == (0, int(go_id))
            assert struct.unpack_from("<i", raw, 28)[0] == 0
            rb_file, rb_id = struct.unpack_from("<iq", raw, 32)
            count = struct.unpack_from("<i", raw, 44)[0]
            assert 0 < count < 32 and len(raw) == 52 + 12 * count
            refs = [struct.unpack_from("<iq", raw, 48 + 12 * i) for i in range(count)]
            threshold = struct.unpack_from("<f", raw, 48 + 12 * count)[0]
            assert (rb_file, rb_id) == (0, int(config["rigidbody_path_id"]))
            assert refs == [(p["file_id"], p["path_id"]) for p in config["points"]]
            assert threshold == config["buried_threshold"]
            rb, rb_raw = check(rb_id)
            assert rb == config["rigidbody"] and rb["m_GameObject"] == {"m_FileID": 0, "m_PathID": int(go_id)}
            assert list(struct.unpack_from("<6f", rb_raw, 12)) == [rb["m_Mass"], rb["m_LinearDamping"], rb["m_AngularDamping"], *[rb["m_CenterOfMass"][k] for k in "xyz"]]
            nodes, colliders = [], []

            def visit(gid, parent_path="", ancestors=()):
                assert str(gid) not in ancestors, "hierarchy cycle"
                go, _ = check(gid)
                node_path = parent_path + "/" + go["m_Name"]
                components = [old.get(str(p["component"]["m_PathID"])) for p in go["m_Component"] if p["component"]["m_FileID"] == 0]
                transform = next(x for x in components if x and x["type"] == "Transform")
                tree, _ = check(transform["path_id"])
                nodes.append({"path": node_path, "game_object_path_id": str(gid),
                              "transform_path_id": transform["path_id"], "active_self": go["m_IsActive"],
                              "position": tree["m_LocalPosition"], "scale": tree["m_LocalScale"], "rotation": tree["m_LocalRotation"]})
                for component in components:
                    if component and component["type"].endswith("Collider"):
                        ct, _ = check(component["path_id"])
                        colliders.append({"node_path": node_path, "path_id": component["path_id"], "type": component["type"], "tree": ct})
                for child in tree["m_Children"]:
                    assert child["m_FileID"] == 0
                    child_tree, _ = check(child["m_PathID"])
                    assert child_tree["m_Father"]["m_PathID"] == int(transform["path_id"])
                    visit(child_tree["m_GameObject"]["m_PathID"], node_path, (*ancestors, str(gid)))

            visit(go_id)
            for point in config["points"]:
                tree, _ = check(point["path_id"])
                assert point["position"] == tree["m_LocalPosition"] and point["scale"] == tree["m_LocalScale"]
                assert point["rotation"] == tree["m_LocalRotation"] and point["parent"] == tree["m_Father"]
            report["props"].append({"name": config["game_object"], "game_object_path_id": go_id,
                                    "buoyancy_path_id": config["path_id"], "rigidbody_path_id": str(rb_id),
                                    "point_count": count, "points": config["points"], "buried_threshold": threshold,
                                    "rigidbody": rb, "nodes": nodes, "colliders": colliders,
                                    "numbered_model_nodes": [n["path"] for n in nodes if re.fullmatch(r"Model_\d+", n["path"].split("/")[-1])],
                                    "selectors": {"buoyancy": config["field_selectors"], "rigidbody_mass_damping_com": [12, 36]},
                                    "runtime_behavior": "unknown; component presence does not establish surface flotation"})
        report["summary"] = {"props": len(report["props"]), "raw_objects": len(report["objects"]),
                              "sampling_points": sum(x["point_count"] for x in report["props"]),
                              "point_count_histogram": dict(Counter(x["point_count"] for x in report["props"])),
                              "solid_collider_types": dict(Counter(c["type"] for x in report["props"] for c in x["colliders"] if not c["tree"]["m_IsTrigger"]))}
        report["source_after"] = [identity(Path(x["path"])) for x in report["sources"]]
        assert report["source_after"] == report["sources"]
    except Exception as exc:
        report["errors"].append(type(exc).__name__ + ": " + str(exc))
    report["result"] = "PASS" if not report["errors"] and len(report["props"]) == 29 else "FAIL"
    (out / "catalog.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / Path(__file__).name).write_bytes(Path(__file__).read_bytes())
    print(json.dumps({"result": report["result"], "summary": report.get("summary"), "errors": report["errors"]}))
    return report["result"] != "PASS"


if __name__ == "__main__":
    raise SystemExit(main())
