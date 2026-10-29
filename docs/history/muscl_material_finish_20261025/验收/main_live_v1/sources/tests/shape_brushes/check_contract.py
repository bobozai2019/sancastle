"""G1A specification audit, analytic references and binary32 budget examples.

This does not claim to exercise an implemented GPU brush. The independently
integrated geometry is the oracle for later GPU sampling comparisons.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
SPEC_PATH = Path(__file__).with_name("contract_v1.json")
SPEC = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
SIZES = {"u32": 4, "i32": 4, "f32": 4, "i64": 8, "sha256": 32, "bytes48": 48}
FORMATS = {"u32": "I", "i32": "i", "f32": "f", "i64": "q"}


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def ulp(value):
    if abs(value) < 2 ** -126:
        return 2 ** -149
    return 2 ** (math.floor(math.log2(abs(value))) - 23)


def volume_budget(before, after, touched=None):
    """Double oracle for the new two-level budget, including unchanged cells."""
    area = SPEC["cell_size_m"] ** 2
    touched = set(range(len(before))) if touched is None else set(touched)
    touched.update(i for i, (a, b) in enumerate(zip(before, after)) if a != b)
    absolute = math.fsum(abs(b - a) * area for a, b in zip(before, after))
    quantization = math.fsum(2 * ulp(max(abs(before[i]), abs(after[i]))) * area for i in touched)
    u = SPEC["numeric"]["unit_roundoff"]
    reduction = max(1e-8, (8 * u + 2 * (len(touched) + 256) * u * u) * absolute)
    total = max(1e-7, quantization + reduction)
    return {"touched": len(touched), "absolute_delta_m3": absolute, "quantization_m3": quantization, "reduction_m3": reduction, "eps_sand_m3": total, "eps_transfer_m3": 2 * total}


def parameters_error(brush_id, params):
    if brush_id not in SPEC["brushes"]:
        return "unknown_brush"
    definition = SPEC["brushes"][brush_id]
    ranges = definition["ranges"]
    if set(params) != set(ranges):
        return "invalid_command"
    for key, value in params.items():
        if type(value) not in (int, float) or not math.isfinite(value):
            return "invalid_command"
        lo, hi = ranges[key]
        if not lo <= value <= hi:
            return "invalid_command"
    if brush_id == "wall_v1" and params["top_width_m"] > params["bottom_width_m"]:
        return "invalid_command"
    return ""


def wire_error(data, layout_name):
    if len(data) != 256:
        return "unsupported_brush_version"
    magic, version, stride, code = struct.unpack_from("<4I", data)
    expected = SPEC["command_magic" if layout_name == "command_layout" else "receipt_magic"]
    if magic != expected or version != 2 or stride != 256:
        return "unsupported_brush_version"
    allowed = SPEC["operation_codes" if layout_name == "command_layout" else "status_codes"].values()
    if code not in allowed:
        return "invalid_command"
    for name, offset, kind in SPEC[layout_name]:
        if kind == "f32" and not math.isfinite(struct.unpack_from("<f", data, offset)[0]):
            return "invalid_command"
        if name in ("flags", "reserved") and any(data[offset:offset + SIZES[kind]]):
            return "invalid_command"
    return ""


def wall_volume(length, width, top, height):
    return height * ((width + top) * length / 2 + math.pi * (width * width + width * top + top * top) / 12)


def shovel_volume(length, width, depth):
    return depth * (2 * width * length / 3 + math.pi * width * width / 8)


def numeric_cross_section_integrals(length, width, top, height, trench_width, depth):
    # Integrate a single symmetric cross section and its disk caps directly,
    # using midpoint quadrature; do not repeat the closed form in the oracle.
    count = 20000
    outer, inner = width / 2, top / 2
    line = 0.0
    disk = 0.0
    donor_line = 0.0
    donor_disk = 0.0
    r = trench_width / 2
    for i in range(count):
        d = outer * (i + 0.5) / count
        profile = 1.0 if d <= inner else (outer - d) / (outer - inner)
        line += 2 * height * profile * outer / count
        disk += 2 * math.pi * d * height * profile * outer / count
        d = r * (i + 0.5) / count
        profile = 1 - (d / r) ** 2
        donor_line += 2 * depth * profile * r / count
        donor_disk += 2 * math.pi * d * depth * profile * r / count
    return line * length + disk, donor_line * length + donor_disk


def water_fill(capacities, weights, requested):
    # Independent high precision allocation reference: cap a common multiplier
    # found by bisection rather than the GPU's fixed-row redistribution passes.
    if any(c < 0 or w < 0 for c, w in zip(capacities, weights)):
        raise ValueError("negative capacity")
    capacity = math.fsum(c for c, w in zip(capacities, weights) if w > 0)
    requested = min(requested, capacity)
    if not requested:
        return [0.0] * len(capacities)
    low, high = 0.0, 1.0
    def allocated(multiplier):
        return math.fsum(min(c, multiplier * w) for c, w in zip(capacities, weights))
    while allocated(high) < requested:
        high *= 2
    for _ in range(100):
        middle = (low + high) / 2
        if allocated(middle) < requested:
            low = middle
        else:
            high = middle
    return [min(c, high * w) for c, w in zip(capacities, weights)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    checks = []
    def check(name, passed, detail=None):
        checks.append({"name": name, "pass": bool(passed), "detail": detail})
    for layout_name in ("command_layout", "receipt_layout"):
        occupancy = [None] * 256
        for name, offset, kind in SPEC[layout_name]:
            check(f"{layout_name}.{name}.alignment", offset % (8 if kind == "i64" else 4) == 0)
            check(f"{layout_name}.{name}.bounds", offset >= 0 and offset + SIZES[kind] <= 256)
            for byte in range(offset, offset + SIZES[kind]):
                if occupancy[byte] is not None:
                    raise AssertionError(f"overlap: {name} / {occupancy[byte]}")
                occupancy[byte] = name
        check(layout_name + ".exact_coverage", all(x is not None for x in occupancy))
        packet = bytearray(256)
        magic = SPEC["command_magic" if layout_name == "command_layout" else "receipt_magic"]
        struct.pack_into("<4I", packet, 0, magic, 2, 256, 1)
        for name, offset, kind in SPEC[layout_name]:
            if kind == "i64":
                value = 9007199254740993 + offset
                struct.pack_into("<q", packet, offset, value)
                check(layout_name + ".int64." + name, struct.unpack_from("<q", packet, offset)[0] == value)
        check(layout_name + ".valid_wire", not wire_error(packet, layout_name))
        for wrong in (packet[:128], packet[:-1], packet + b"\0"):
            check(layout_name + ".wrong_length_rejected", bool(wire_error(wrong, layout_name)))
        for offset, value in ((0, 0), (4, 99), (8, 128), (12, 99), (252, 1)):
            wrong = packet.copy()
            struct.pack_into("<I", wrong, offset, value)
            check(f"{layout_name}.tamper.{offset}", bool(wire_error(wrong, layout_name)))
        for name, offset, kind in SPEC[layout_name]:
            if kind == "f32":
                for value in (math.nan, math.inf, -math.inf):
                    wrong = packet.copy()
                    struct.pack_into("<f", wrong, offset, value)
                    check(layout_name + ".nonfinite." + name, bool(wire_error(wrong, layout_name)))
    check("unknown_brush", parameters_error("place_sand", {}) == "unknown_brush")
    for brush, definition in SPEC["brushes"].items():
        check(brush + ".defaults", not parameters_error(brush, definition["default"]))
        for key, bounds in definition["ranges"].items():
            for value in (bounds[0] - 1e-5, bounds[1] + 1e-5, math.nan, math.inf, True):
                params = dict(definition["default"], **{key: value})
                check(brush + ".invalid." + key, bool(parameters_error(brush, params)))
        check(brush + ".missing", bool(parameters_error(brush, {})))
        check(brush + ".unknown_field", bool(parameters_error(brush, dict(definition["default"], amount_m3=1))))
    check("wall.top_exceeds_bottom", bool(parameters_error("wall_v1", {"height_m":0.3,"bottom_width_m":1,"top_width_m":1.5})))
    analytic = []
    for length, width, top, height in ((2,1,0.5,0.3),(0.125,2,1.5,0.6),(2,1,1,0.15)):
        integrated_wall, integrated_shovel = numeric_cross_section_integrals(length,width,top,height,0.5,0.15)
        expected_wall = wall_volume(length,width,top,height)
        expected_cut = shovel_volume(length,0.5,0.15)
        check("analytic_wall_integral", abs(expected_wall-integrated_wall) < 1e-8)
        check("analytic_shovel_integral", abs(expected_cut-integrated_shovel) < 1e-8)
        analytic.append({"params":[length,width,top,height],"wall_volume_m3":expected_wall,"wall_integral_m3":integrated_wall,"cut_volume_m3":expected_cut,"cut_integral_m3":integrated_shovel})
    for capacities, weights, requested in (([0.01,0.2,0.4],[10,1,2],0.3),([0,0,0],[1,2,3],1),([0.02,0.04],[0,1],0.1)):
        values = water_fill(capacities,weights,requested)
        expected = min(requested,math.fsum(c for c,w in zip(capacities,weights) if w>0))
        check("capacity_weighted_allocation", abs(math.fsum(values)-expected) < 1e-14 and all(0 <= v <= c for v,c in zip(values,capacities)),values)
    budget_examples = []
    for old, delta, count in ((1.0,0.3,128),(8.0,0.00001,128),(1.0,-0.15,256),(0.01,-0.01,32)):
        before = [f32(old)] * count
        after = [f32(old+delta)] * count
        budget = volume_budget(before,after)
        actual = math.fsum((b-a)*0.015625 for a,b in zip(before,after))
        ideal = delta*count*0.015625
        check("binary32_budget_example", abs(actual-ideal) <= budget["eps_sand_m3"])
        budget_examples.append({"before_m":old,"delta_m":delta,"count":count,"actual_delta_m3":actual,"ideal_delta_m3":ideal,**budget})
    # The 48 m3 castle bound includes full foundation fill at the maximum relief.
    castle = SPEC["brushes"]["castle_v1"]
    full_upper = (castle["footprint_m"]*castle["ranges"]["scale_xz"][1])**2*(castle["ranges"]["height_m"][1]+castle["placement_relief_m"])
    check("castle_maximum_geometric_permission", full_upper <= castle["max_add_m3"], full_upper)
    check("four_cell_minimum_detail", 0.5/SPEC["cell_size_m"] >= 4)
    check("shovel_no_external_add_permission", SPEC["brushes"]["shovel_v1"]["max_add_m3"] == 0)
    for set_name in ("set0", "set1"):
        numbers = [binding[0] for binding in SPEC["bindings"][set_name]]
        check(set_name + ".unique_contiguous_bindings", numbers == list(range(len(numbers))))
    check("push_constant_exact_32bytes", len(SPEC["bindings"]["push_constant_u32"]) == 8)
    check("old_wire_not_extended", SPEC["stride"] != 128 and SPEC["schema_version"] == 2)
    plan_path = ROOT / "task/sandcastle_shape_brushes/验证计划.md"
    rows = re.findall(r"^\| ([A-Z]+-\d+) \| (.+?) \| (.+?) \| (.+?) \|$", plan_path.read_text(encoding="utf-8"), re.M)
    ids = [row[0] for row in rows]
    families = {"INPUT":"input","LEGACY":"final","WALL":"wall","CAST":"castle","SHOVEL":"shovel","MAT":"retention","WATER":"integration","TXN":"integration","COLLISION":"integration","UI":"ui","RECOVER":"integration","SCENE":"integration","SOAK":"final"}
    check("case_catalog_unique", len(ids) == len(set(ids)))
    check("case_catalog_all_families", set(x.split("-")[0] for x in ids) == set(families))
    catalog = []
    for identity, scenario, required, tasks in rows:
        group = families[identity.split("-")[0]]
        catalog.append({"id":identity,"scenario":scenario,"required":required,"tasks":tasks,"planned_group":group,"execution_status":"not_implemented_at_G1A","fixture_generator":"res://tests/shape_brushes/fixtures.gd","seed":101,"initial_tick":0,"simulation_for_geometry":"paused","roi":"command_footprint_plus_1m; castle_peaks_per_tower; cutoff_0.1*peak_height","planned_runner":"tests/shape_brushes/run_shape_brushes.ps1 -Group " + group})
    (output/"case_catalog.json").write_text(json.dumps({"cases":catalog,"validation_plan_sha256":hashlib.sha256(plan_path.read_bytes()).hexdigest(),"scope":"frozen execution checklist; future runner groups are not yet available"},ensure_ascii=False,indent=2),encoding="utf-8")
    result = {"pass": all(c["pass"] for c in checks), "checks": checks, "case_count":len(catalog), "analytic_examples": analytic, "budget_examples": budget_examples, "spec_sha256": hashlib.sha256(SPEC_PATH.read_bytes()).hexdigest(), "scope": "specification/CPU reference only; GPU and UI unimplemented"}
    (output/"contract_result.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(f"G1_CONTRACT {'PASS' if result['pass'] else 'FAIL'} checks={len(checks)} output={output}")
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":
    main()
