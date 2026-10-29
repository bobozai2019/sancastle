"""Strict local-material prototype audit against the saved ordinary control."""
import argparse
import json
from pathlib import Path
import numpy as np
from retention_reference import analyze,raw

ROOT=Path(__file__).resolve().parents[2]
CONTROL=ROOT/"test_output/shape_brushes/20261014_035531_retention_0f671c3d/compact/retention_evidence.json"


def support(sample,slot):
    import hashlib
    item=sample["fields"]["mold_support_"+str(slot)]
    data=Path(item["path"]).read_bytes()
    assert len(data)==item["bytes"] and hashlib.sha256(data).hexdigest()==item["sha256"]
    return np.frombuffer(data,dtype="<f4").astype(np.float64).reshape(256,256,2)


def run(root,output):
    zero=json.loads((root/"zero_support/retention_evidence.json").read_text())
    local=json.loads((root/"local/retention_evidence.json").read_text())
    control_path=root/"ordinary_control/retention_evidence.json"
    if not control_path.exists(): control_path=CONTROL
    control=json.loads(control_path.read_text())
    checks=[]; differences=[]
    def check(name,passed,detail=None): checks.append({"name":name,"pass":bool(passed),"detail":detail})
    report=analyze(local)
    check("local_30s_completed",report["complete_30s"])
    check("local_mat01_all_structural_rois",report["mat01_all_structural_rois"])
    check("local_legal_material_fields",report["finite_legal_fields"])
    check("zero_30s_completed",zero["completed_ticks"]==900)
    check("same_sample_ticks",[s["tick"] for s in zero["samples"]]==[s["tick"] for s in control["samples"]])
    for sample,original in zip(zero["samples"],control["samples"]):
        bad=[name for name,item in original["fields"].items() if item["sha256"]!=sample["fields"][name]["sha256"]]
        check("zero_support_old_25_exact_tick_"+str(sample["tick"]),not bad,bad)
        if bad: differences.append({"tick":sample["tick"],"fields":bad})
    for mode,record in [("zero_support",zero),("local",local)]:
        for sample in record["samples"]:
            s0=support(sample,0); s1=support(sample,1); sand=raw(sample,"sand")
            tagged=s0[:,:,0]>0
            good=np.isfinite(s0).all() and (s0[:,:,0]>=0).all() and (s0[:,:,0]<=sand).all() and np.array_equal(s0,s1) and np.array_equal(s0[:,:,1][tagged],sand[tagged]) and np.count_nonzero(s0[:,:,1][~tagged])==0
            check(mode+"_support_invariants_tick_"+str(sample["tick"]),good)
            if mode=="zero_support": check("zero_tag_remains_zero_"+str(sample["tick"]),np.count_nonzero(s0[:,:,0])==0)
    initial=support(local["samples"][0],0)[:,:,0]
    coords=(np.arange(256)+0.5-128)*0.125; x,z=np.meshgrid(coords,coords)
    ordinary=(x>=4)&(x<=8)&(z>=-2)&(z<=2)
    check("ordinary_heap_has_no_initial_tag",np.count_nonzero(initial[ordinary])==0)
    # Local geometry changes water evolution; ordinary-state equality is proved
    # above on the complete zero-support domain, without hiding that coupling.
    historic=json.loads(CONTROL.read_text())
    historical_differences=[{"tick":s["tick"],"fields":[f for f in h["fields"] if h["fields"][f]["sha256"]!=s["fields"][f]["sha256"]]} for s,h in zip(control["samples"],historic["samples"])]
    result={"pass":all(c["pass"] for c in checks),"checks":checks,"local_retention":report,"zero_support_differences":differences,"old_control_path":str(control_path),"historical_control_differences":historical_differences,"scope":"simulation/material prototype only; transactions, damage, native version and full G4 still incomplete"}
    (output/"result.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    return result["pass"]


if __name__=="__main__":
    parser=argparse.ArgumentParser(); parser.add_argument("--output",type=Path,required=True); args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    passed=run(args.output.parent,args.output); print("LOCAL_MATERIAL_PROTOTYPE",passed)
    raise SystemExit(0 if passed else 1)
