"""Read original GPU frames/native fields; audit tagged display and common lifetime."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import zipfile

from native_variant import VariantReader


def digest(data):return hashlib.sha256(data).hexdigest()
def sha(path):return digest(path.read_bytes())


def audit(folder):
    report = json.loads((folder / "report.json").read_text("utf-8"))
    checks = []

    def check(name, value):checks.append({"name": name, "pass": bool(value)})

    def raw(item, label):
        data = Path(item["path"]).read_bytes()
        check(label + ":size", len(data) == item["bytes"])
        check(label + ":sha", digest(data) == item["sha256"])
        return data

    check("runner_pass", report["pass"] is True)
    archive_path = Path(report["source_zip"])
    check("archive_identity", sha(archive_path) == report["source_zip_sha256"])
    with zipfile.ZipFile(archive_path) as archive:
        check("archive_crc", archive.testzip() is None)
        check("archive_index", json.loads(archive.read("evidence/source-index.json")) == report["sources"])
        for name, expected in report["sources"].items():check("source:" + name, digest(archive.read(name.removeprefix("res://"))) == expected)
    total = 0
    details = {}
    for run in report["runs"]:
        case = run["case"];path = Path(run["evidence"])
        data = json.loads(path.read_text("utf-8"));o = data.get("observations", {})
        total += len(data["checks"])
        check(case + ":report_identity", sha(path) == run["evidence_sha256"])
        check(case + ":checks", data["pass"] is True and all(row["pass"] for row in data["checks"]))
        for name in ["stdout.txt", "probe.log"]:
            check(case + ":" + name, re.search(r"ERROR:|SCRIPT ERROR:|\bleaked\b|Stray Node:|resources still in use", (path.parent / name).read_text("utf-8", errors="replace"), re.I) is None)
        if case.startswith("entry_"):
            initial, final = o["initial_count"], o["final_count"]
            check(case + ":restored_population", final == initial + (34 if case == "entry_main" else 17))
            check(case + ":failed_old_root_retires", any(event["kind"] == "retired" for event in o["events"]))
            continue
        if not case.startswith("display_") or case == "display_disabled":continue
        if case == "display_core":
            before, emitted = o["initial"], o["emitted_held"]
            for field, item in before.items():
                if field in ["control", "stamp", "display_active_count"] or field.startswith("visual"):continue
                check("core:authority:" + field, raw(item, "initial:" + field) == raw(emitted[field], "emitted:" + field))
            control = raw(emitted["control"], "emitted_control")
            check("core:actual_state_seq", struct.unpack_from("<q", control, 16)[0] == 2)
            check("core:physical_tick_revision_clock_unchanged", struct.unpack_from("<q", control, 24)[0] == 0 and struct.unpack_from("<q", control, 40)[0] == 0 and struct.unpack_from("<f", control, 32)[0] == 0)
            check("core:physical_reserved_control_unchanged", not any(control[48:72]) and not any(control[104:]))
            check("core:gpu_count_46", struct.unpack("<I", raw(emitted["display_active_count"], "count"))[0] == 46)
            domain = hashlib.sha256(b"main_beach").digest()
            for index, (count, active) in enumerate([(17, 17), (29, 46)]):
                frame = raw(emitted[f"frame_{index}"], f"frame_{index}")
                body = frame[96:]
                check(f"frame{index}:sizes", len(frame) == 480 and len(body) == 384)
                check(f"frame{index}:namespace", struct.unpack_from("<I", body)[0] == 0x31524455)
                check(f"frame{index}:command64", struct.unpack_from("<q", body, 16)[0] == 9007199254740995 + index)
                check(f"frame{index}:generation64", struct.unpack_from("<q", body, 24)[0] == 9007199254740993)
                check(f"frame{index}:actual_population", struct.unpack_from("<II", body, 120) == (count, active))
                check(f"frame{index}:no_physical_change", struct.unpack_from("<qq", body, 48) == (0, 0) and not any(body[128:208]) and not any(body[272:288]))
                check(f"frame{index}:actual_gpu_phase", struct.unpack_from("<I", body, 108)[0] == 1)
                check(f"frame{index}:domain", body[208:240] == domain)
                check(f"frame{index}:state_seq", struct.unpack_from("<q", body, 72)[0] == index + 1)
            for label, source in [("reference_emitted", emitted), ("reference_tick", o["after_tick"])]:
                check("original:" + label, raw(o[label]["gravel"], label) == raw(source["visual/gravel_0"], label + ":candidate"))
            container = (path.parent / "display.sandue").read_bytes()
            check("native:container_identity", container[:8] == b"SANDUE06" and struct.unpack_from("<II", container, 8) == (1, len(container) - 48) and container[16:48] == hashlib.sha256(container[48:]).digest())
            native = VariantReader(container[48:]).document()
            check("native:actual_count", native["visual_extensions"]["gravel_v1"]["active_count"] == 46)
            check("native:reserved_control", not any(native["native"]["control"][48:72]))
            check("native:gravel_payload", bytes(native["visual_extensions"]["gravel_v1"]["state_0"]) == raw(o["after_tick"]["visual/gravel_0"], "native_gravel"))
            check("native:restored_count_gpu_read", o["restore_verification"]["display_active_count"]["matched"])
            for key, item in o["source_continued"].items():
                if key in ["control", "stamp"]:continue
                check("continued:" + key, raw(item, "source:" + key) == raw(o["candidate_continued"][key], "candidate:" + key))
            details[case] = {"native_count": 46, "continued_count": 49, "generation": native["generation"]}
        elif case == "display_mixed":
            source, physical = o["ahead"], o["physical_only"]
            for key, item in source.items():
                if key in ["control", "stamp", "display_active_count"] or key.startswith("visual"):continue
                check("mixed:physical:" + key, raw(item, "mixed:source:" + key) == raw(physical[key], "mixed:reference:" + key))
            check("mixed:original_particle_bytes", raw(source["visual/gravel_0"], "mixed:gravel") == raw(o["reference"]["gravel"], "mixed:original"))
            for label, fields, seq in [("source", source, 3), ("reference", physical, 2)]:
                control = raw(fields["control"], "mixed:" + label + ":control")
                check("mixed:" + label + ":tick", struct.unpack_from("<q", control, 24)[0] == 1)
                check("mixed:" + label + ":revision", struct.unpack_from("<q", control, 40)[0] == 2)
                check("mixed:" + label + ":state_seq", struct.unpack_from("<q", control, 16)[0] == seq)
                check("mixed:" + label + ":clock", abs(struct.unpack_from("<f", control, 32)[0] - 0.001) < 1e-9)
            display, edit = o["results"]
            check("mixed:display_no_authority", display["authority_changed"] is False and display["input_revision"] == display["output_revision"] == 0 and display["source_m3"] == display["sink_m3"] == 0)
            check("mixed:physical_edit_revision", edit["input_revision"] == 0 and edit["output_revision"] == 1 and edit["added_m3"] > 0)
        elif case in ["display_capacity", "display_cancel"]:
            count = struct.unpack("<I", raw(o["after"]["display_active_count"], case + ":count"))[0]
            check(case + ":capacity1024", count == 1024)
            particle_bytes = raw(o["after"]["visual/gravel_0"], case + ":state")
            check(case + ":original_dense_fifo", particle_bytes == raw(o["reference"]["gravel"], case + ":original"))
            check(case + ":eight_actual_results", len(o["results"]) == 8 and all(row["display_count"] == 128 and row["outcome"] == 1 for row in o["results"]))
            particles = struct.iter_unpack("<ffff", particle_bytes)
            for index, particle in enumerate(particles):check(f"{case}:particle:{index}", all(math.isfinite(v) for v in particle) and abs(particle[1] - 0.3) < 1e-6 and particle[3] == 1.0)
            if case == "display_cancel":check("cancel:no_fake_gpu_outcome", o["cancelled"]["cancelled"] is True and "outcome" not in o["cancelled"])
        elif case in ["display_upload", "display_unknown", "display_fatal"]:
            for key, item in o["before"].items():
                if key in ["control", "stamp", "display_active_count"] or key.startswith("visual"):continue
                check(case + ":authority:" + key, raw(item, case + ":before:" + key) == raw(o["after"][key], case + ":after:" + key))
            if case != "display_unknown":
                check(case + ":published_unchanged", raw(o["before"]["visual_view/gravel"], case + ":old_view") == raw(o["after"]["visual_view/gravel"], case + ":new_view"))
            else:check("unknown:actual_gpu_count17", struct.unpack("<I", raw(o["after"]["display_active_count"], "unknown:count"))[0] == 17)
            if case != "display_upload":check(case + ":no_fabricated_outcome", all(row["unknown"] and row["submitted"] and "outcome" not in row for row in o["closed_results"].values()))
    return {"pass": all(c["pass"] for c in checks), "checks": checks, "direct_checks": total,
            "details": details, "source_count": len(report["sources"]), "auditor_sha256": sha(Path(__file__)),
            "variant_decoder_sha256": sha(Path(__file__).with_name("native_variant.py")),
            "scope": "Actual tagged GPU frames, original mode3/step byte comparisons, physical invariants, count proof/native continuation, capacity/cancel and lifetime evidence; not formal cutover/cost."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser();parser.add_argument("folder", type=Path);args = parser.parse_args()
    folder = args.folder.resolve();target = folder / "audit.json"
    if target.exists():raise FileExistsError(target)
    result = audit(folder);target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"pass": result["pass"], "checks": len(result["checks"]), "direct": result["direct_checks"], "sources": result["source_count"]}))
    raise SystemExit(0 if result["pass"] else 1)
