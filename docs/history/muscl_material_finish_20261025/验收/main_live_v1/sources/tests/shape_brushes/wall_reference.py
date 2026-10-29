"""Independent double geometry oracle for actual native GPU wall fields.

Closed-form capsule distance is evaluated as separate interior/perpendicular
and endpoint regions, rather than reproducing the shader projection code.
Accounting always uses the actual binary32 before/after fields, not the analytic
continuous volume. Geometry tolerance is fixed here before running the GPU.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from check_contract import numeric_cross_section_integrals

U = 2.0 ** -24
CELL = 0.125
GRID = 256


def raw(index, field, channels=1):
    item = index[field]
    data = Path(item["path"]).read_bytes()
    assert len(data) == item["bytes"]
    assert hashlib.sha256(data).hexdigest() == item["sha256"]
    return np.frombuffer(data, dtype="<f4").astype(np.float64).reshape(GRID, GRID, channels).squeeze()


def capsule_distance(x, z, start, end):
    ax, az = start
    bx, bz = end
    dx, dz = bx - ax, bz - az
    length = math.hypot(dx, dz)
    if length == 0:
        return np.full_like(x, np.inf)
    along = ((x-ax)*dx+(z-az)*dz)/length
    perpendicular = np.abs((x-ax)*dz-(z-az)*dx)/length
    return np.where(along < 0, np.hypot(x-ax,z-az),
                    np.where(along > length, np.hypot(x-bx,z-bz), perpendicular))


def profile(distance, bottom, top):
    outer, inner = bottom/2, top/2
    if outer == inner:
        return np.where(distance <= inner, 1.0, 0.0)
    return np.where(distance <= inner, 1.0, np.clip((outer-distance)/(outer-inner),0.0,1.0))


def analytic_volume(length, width, top, height):
    return height*((width+top)*length/2+math.pi*(width*width+width*top+top*top)/12)


def geometry_bound(sand, rock, params):
    # Conservative binary32 forward-error allowance for height arithmetic and
    # distance evaluation, including cancellation at endpoints. Endpoint
    # coordinate magnitudes are <=16m. The narrowest nonzero shoulder is .25m
    # in the frozen test presets. Equal-width discontinuity is checked by the
    # exact classification separately and gets no spatial boundary allowance.
    width = (params["bottom_width_m"]-params["top_width_m"])/2
    slope = params["height_m"]/width if width > 0 else 0.0
    return 8*U*(np.maximum(1.0,np.abs(sand))+np.abs(rock)+params["height_m"])+32*U*16*slope


def run(evidence, output):
    checks, rows = [], []
    def check(name, passed, detail=None):
        checks.append({"name":name,"pass":bool(passed),"detail":detail})

    coords = (np.arange(GRID)+0.5-GRID/2)*CELL
    x,z = np.meshgrid(coords,coords)
    compare = []
    for case in evidence["cases"]:
        name = case["name"]
        sand0,rock = raw(case["before"],"sand"),raw(case["before"],"rock")
        actual = raw(case["after"],"sand")
        base_source = case.get("baseline_source",case["before"])
        base = (raw(base_source,"sand")+raw(base_source,"rock")).astype("<f4").astype(np.float64)
        check(name+"_baseline",np.array_equal(raw(case["after"],"baseline"),base))
        check(name+"_rock_unchanged",np.array_equal(rock,raw(case["after"],"rock")))
        check(name+"_published",np.array_equal(actual,raw(case["after"],"published_sand")))
        target = np.full_like(x,-np.inf)
        height_profile = np.zeros_like(x)
        for command in case["commands"]:
            params = command["params"]
            d = capsule_distance(x,z,command["start"],command["end"])
            f = profile(d,params["bottom_width_m"],params["top_width_m"])
            height_profile = np.maximum(height_profile,params["height_m"]*f)
            target = np.maximum(target,np.where(f>0,base+params["height_m"]*f,-np.inf))
        expected = np.maximum(sand0,target-rock)
        bound = geometry_bound(expected,rock,case["params"])
        errors = np.abs(actual-expected)
        changed = actual != sand0
        # Outside analytic support allow only the fixed forward distance error
        # already represented by the per-cell height bound, never an arbitrary
        # cell of extra support. Empty/stationary requests must be exact.
        check(name+"_double_geometry",np.all(errors<=bound),{"max_error_m":float(errors.max()),"max_bound_m":float(bound.max())})
        check(name+"_only_adds",np.all(actual>=sand0))
        check(name+"_no_corner_overheight",np.all(actual-sand0<=height_profile+bound))
        cv = raw(case["after"],"coverage",2)
        expected_coverage = np.isfinite(target)
        check(name+"_coverage_mask",np.array_equal(cv[:,:,1]>0,expected_coverage))
        if expected_coverage.any():
            check(name+"_coverage_target",np.all(np.abs(cv[:,:,0][expected_coverage]-target[expected_coverage])<=bound[expected_coverage]))
        volume = math.fsum((actual-sand0).ravel())*CELL*CELL
        source = case["source_after"]-case["source_before"]
        receipt_volume = math.fsum(c["result"]["added_m3"] for c in case["commands"])
        eps = math.fsum(c["result"]["eps_sand_m3"] for c in case["commands"])
        check(name+"_actual_volume_receipt_source",abs(volume-receipt_volume)<=eps+1e-12 and abs(source-receipt_volume)<=1e-12,{"actual_volume":volume,"receipt":receipt_volume,"source":source,"eps":eps})
        if not case["commands"]:
            check(name+"_stationary_exact",np.array_equal(actual,sand0) and volume==0 and source==0)
        row = {"name":name,"max_error_m":float(errors.max()),"changed_cells":int(changed.sum()),"double_discrete_volume_m3":math.fsum((expected-sand0).ravel())*CELL*CELL,"actual_volume_m3":volume,"receipt_volume_m3":receipt_volume,"eps_sum_m3":eps,"command_count":len(case["commands"])}
        if case.get("heap_after_begin"):
            high = sand0 > base-rock+case["params"]["height_m"]
            check(name+"_higher_heap_preserved",high.any() and np.array_equal(actual[high],sand0[high]))
        if name=="invalid_subpath_gap":
            gap=(x>0.5)&(x<1.5)&(np.abs(z-6)<0.4)
            check(name+"_gap_unedited",gap.any() and np.array_equal(actual[gap],sand0[gap]))
        if len(case["commands"])==1:
            c=case["commands"][0]
            length=math.dist(c["start"],c["end"])
            row["analytic_continuous_volume_m3"]=analytic_volume(length,case["params"]["bottom_width_m"],case["params"]["top_width_m"],case["params"]["height_m"])
            integrated,_=numeric_cross_section_integrals(length,case["params"]["bottom_width_m"],case["params"]["top_width_m"],case["params"]["height_m"],0.5,0.15)
            row["numeric_continuous_integral_m3"]=integrated
            check(name+"_continuous_independent_quadrature",abs(integrated-row["analytic_continuous_volume_m3"])<1e-8)
        rows.append(row)
        np.asarray(expected,dtype="<f4").tofile(output/(name+"_reference_sand.bin"))
        if case["comparison"]=="same_path": compare.append((case,actual,volume,eps))
    for case,actual,volume,eps in compare[1:]:
        first,reference,v0,e0 = compare[0]
        tolerance=geometry_bound(reference,np.zeros_like(reference),case["params"])
        check(case["name"]+"_event_density_geometry",np.all(np.abs(actual-reference)<=tolerance))
        # Event-density equivalence uses actual field quantization plus geometry
        # error only on differing cells, not a whole-domain blanket volume bound.
        diff=actual-reference
        density_eps=(np.abs(diff[diff!=0]).sum()*CELL*CELL)
        check(case["name"]+"_event_density_volume",abs(volume-v0)<=eps+e0+1e-12,{"volume_difference":volume-v0,"receipt_eps":eps+e0,"field_difference_volume":float(density_eps)})
    observation=evidence["retention_observation"]
    before=raw(observation["before"],"sand")+raw(observation["before"],"rock")
    after=raw(observation["after"],"sand")+raw(observation["after"],"rock")
    roi=(x>=-7)&(x<=-3)&(z>=-1.5)&(z<=1.5)
    cutoff=float(before[roi].max())*0.1
    a=(before>cutoff)&roi; b=(after>cutoff)&roi
    retention={"roi_xz_m":[-7,-3,-1.5,1.5],"before_peak_m":float(before[roi].max()),"after_peak_m":float(after[roi].max()),"peak_ratio":float(after[roi].max()/before[roi].max()),"height_cutoff_m":cutoff,"iou":float((a&b).sum()/(a|b).sum()),"ticks":observation["ticks"],"seconds":observation["ticks"]*observation["simulation_delta_s"],"scope":"five-tick ordinary maximum-wall observation only; no 30s molded retention claim"}
    with (output/"wall_metrics.csv").open("w",newline="",encoding="utf-8") as file:
        writer=csv.DictWriter(file,fieldnames=sorted(set().union(*(r.keys() for r in rows))))
        writer.writeheader(); writer.writerows(rows)
    # Export the frozen exact cross section, independently of the GPU samples.
    with (output/"default_cross_section.csv").open("w",newline="",encoding="utf-8") as file:
        writer=csv.writer(file); writer.writerow(["distance_m","height_m"])
        for d in np.linspace(-0.75,0.75,301): writer.writerow([float(d),float(0.3*profile(np.asarray(abs(d)),1.0,0.5))])
    result={"pass":all(c["pass"] for c in checks),"checks":checks,"metrics":rows,"retention_observation":retention,"geometry_tolerance":"8u*(max(1,abs(sand))+abs(rock)+h)+32u*16*h/shoulder; exact mask classification; u=2^-24","scope":"independent double discrete target vs GPU raw; continuous volumes reported separately"}
    (output/"result.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    return result["pass"]


if __name__=="__main__":
    parser=argparse.ArgumentParser(); parser.add_argument("--output",type=Path,required=True); parser.add_argument("--evidence",type=Path)
    args=parser.parse_args(); args.output.mkdir(parents=True,exist_ok=True)
    source=args.evidence or args.output.parent/"wall_gpu"/"wall_evidence.json"
    passed=run(json.loads(source.read_text(encoding="utf-8")),args.output)
    print("WALL_REFERENCE",passed)
    raise SystemExit(0 if passed else 1)
