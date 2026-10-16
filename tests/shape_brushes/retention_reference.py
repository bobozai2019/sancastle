"""Evaluate material controls without claiming selection of a molded profile."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np


def raw(sample, field):
    item=sample["fields"][field]
    data=Path(item["path"]).read_bytes()
    assert len(data)==item["bytes"] and hashlib.sha256(data).hexdigest()==item["sha256"]
    dtype="<f2" if "wetness" in field or "compaction" in field else "<f4"
    return np.frombuffer(data,dtype=dtype).astype(np.float64).reshape(256,256)


def analyze(record):
    coords=(np.arange(256)+0.5-128)*0.125
    x,z=np.meshgrid(coords,coords)
    initial=record["samples"][0]
    height0=raw(initial,"rock")+raw(initial,"sand")
    metrics=[]; valid=True
    for sample in record["samples"]:
        height=raw(sample,"rock")+raw(sample,"sand")
        sand=raw(sample,"sand"); wet=raw(sample,"wetness"); compact=raw(sample,"compaction")
        valid=valid and np.isfinite(sand).all() and (sand>=0).all() and np.isfinite(wet).all() and ((wet>=0)&(wet<=1)).all() and np.isfinite(compact).all() and ((compact>=0)&(compact<=1)).all()
        for roi in record["rois"]:
            a,b,c,d=roi["bounds"]; mask=(x>=a)&(x<=b)&(z>=c)&(z<=d)
            peak0=float(height0[mask].max()); peak=float(height[mask].max())
            cutoff=0.1*peak0; m0=(height0>=cutoff)&mask; m=(height>=cutoff)&mask
            iou=float((m0&m).sum()/(m0|m).sum())
            metrics.append({"tick":sample["tick"],"roi":roi["id"],"peak_initial_m":peak0,"peak_m":peak,"peak_ratio":peak/peak0,"iou":iou,"height_cutoff_m":cutoff,"compaction_min":float(compact[mask].min()),"compaction_max":float(compact[mask].max()),"wetness_min":float(wet[mask].min()),"wetness_max":float(wet[mask].max()),"mat01_pass":bool(peak/peak0>=0.8 and iou>=0.8)})
    final=[m for m in metrics if m["tick"]==900 and m["roi"]!="ordinary_compacted"]
    return {"mode":record["mode"],"complete_30s":record["completed_ticks"]==900,"finite_legal_fields":bool(valid),"mat01_all_structural_rois":bool(final and all(m["mat01_pass"] for m in final)),"metrics":metrics}


def run(root,output):
    records={name:json.loads((root/name/"retention_evidence.json").read_text(encoding="utf-8")) for name in ["baseline","compact","cohesion"]}
    reports={name:analyze(record) for name,record in records.items()}
    checks=[]
    def check(name,passed): checks.append({"name":name,"pass":bool(passed)})
    for name,report in reports.items():
        check(name+"_complete_30s",report["complete_30s"])
        check(name+"_legal_material_fields",report["finite_legal_fields"])
    b,c,h=[records[name]["samples"][0] for name in ["baseline","compact","cohesion"]]
    for field in ["sand","rock","water","wetness"]:
        check("same_initial_"+field,np.array_equal(raw(b,field),raw(c,field)) and np.array_equal(raw(c,field),raw(h,field)))
    check("cohesion_changes_only_parameter_initial_compaction",np.array_equal(raw(c,"compaction"),raw(h,"compaction")))
    coords=(np.arange(256)+0.5-128)*0.125; x,z=np.meshgrid(coords,coords)
    ordinary=(x>=4)&(x<=8)&(z>=-2)&(z<=2)
    check("ordinary_initial_compaction_same",np.array_equal(raw(b,"compaction")[ordinary],raw(c,"compaction")[ordinary]))
    # A control experiment may correctly refute a proposed material strategy.
    # Experimental completion and candidate acceptance are separate results.
    plain_compact=raw(records["compact"]["samples"][-1],"sand")[ordinary]
    plain_cohesion=raw(records["cohesion"]["samples"][-1],"sand")[ordinary]
    ordinary_equal=np.array_equal(plain_compact,plain_cohesion)
    result={"pass":all(c["pass"] for c in checks),"checks":checks,"controls":reports,"global_cohesion_preserves_ordinary_compacted_heap":bool(ordinary_equal),"ordinary_compacted_max_delta_m":float(np.abs(plain_compact-plain_cohesion).max()),"global_cohesion_candidate_accepted":bool(reports["cohesion"]["mat01_all_structural_rois"] and ordinary_equal),"scope":"30s control experiment completion only; G4 not passed without local strategy, destructibility and lifecycle"}
    (output/"result.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    return result["pass"]


if __name__=="__main__":
    parser=argparse.ArgumentParser(); parser.add_argument("--output",type=Path,required=True); args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    passed=run(args.output.parent,args.output)
    print("RETENTION_CONTROLS_COMPLETE",passed)
    raise SystemExit(0 if passed else 1)
