"""Compare command transport and readonly source at matched owned prepare events."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import numpy as np

parser=argparse.ArgumentParser()
parser.add_argument("active",type=Path)
parser.add_argument("worker",type=Path)
args=parser.parse_args()

def load(report_path):
    report=json.loads(report_path.read_text())
    assert report["pass"]
    values={}
    for row in report["rows"]:
        data=(report_path.parent/row["path"]).read_bytes()
        assert hashlib.sha256(data).hexdigest()==row["sha256"]
        values[row["name"]]=data
    return report,values

a,aa=load(args.active);b,bb=load(args.worker)
ac,bc=aa["ByteAddressBuffer0"],bb["ByteAddressBuffer0"]
assert len(ac)==len(bc)==128
identities={name:{"active":struct.unpack_from("<q",ac,offset)[0],"worker":struct.unpack_from("<q",bc,offset)[0]}
            for name,offset in {"ticket_id":0,"command_id":8,"generation":16,"sim_tick":24,"input_revision":32,"seed":96}.items()}
an,bn=bytearray(ac),bytearray(bc)
# Worker identity normalization is prescribed by the replay protocol, never a numerical tolerance.
an[16:24]=bn[16:24]=bytes(8)
sa,sb=aa["sand_in"],bb["sand_in"]
assert len(sa)==len(sb)==256*256*4
x,y=np.frombuffer(sa,dtype="<f4"),np.frombuffer(sb,dtype="<f4")
different=np.flatnonzero(np.frombuffer(sa,dtype="<u4")!=np.frombuffer(sb,dtype="<u4"))
result={"active_report":str(args.active),"worker_report":str(args.worker),"active_event":a["event"],"worker_event":b["event"],
        "command_exact":ac==bc,"command_equal_except_generation":an==bn,"different_command_byte_offsets":[i for i in range(128) if ac[i]!=bc[i]],
        "identities":identities,"sand_byte_equal":sa==sb,"different_sand_cells":len(different),"max_abs_sand":float(np.max(np.abs(x.astype(float)-y.astype(float)))),
        "samples":[{"cell":int(i),"active":float(x[i]),"worker":float(y[i])} for i in different[:12]],
        "scope":"Actual bound command descriptor and bytes; sand source is post-prepare replay-derived, not original live input or first-divergence evidence."}
initial="initial_sand" in aa and "initial_sand" in bb
if initial:
    ia,ib=aa["initial_sand"],bb["initial_sand"]
    assert len(ia)==len(ib)==len(sa)
    xa,xb=np.frombuffer(ia,dtype="<f4"),np.frombuffer(ib,dtype="<f4")
    assert np.isfinite(xa).all() and np.isfinite(xb).all() and xa.max()>0 and xb.max()>0
    changed=np.flatnonzero(np.frombuffer(ia,dtype="<u4")!=np.frombuffer(ib,dtype="<u4"))
    result["frame_initial_source"]={"selection":"same prepare source RID at event0 before frame dispatches","equal":ia==ib,"different_cells":len(changed),
        "max_abs":float(np.max(np.abs(xa.astype(float)-xb.astype(float)))),
        "active_cells_changed_by_frame":int(np.count_nonzero(np.frombuffer(ia,dtype="<u4")!=np.frombuffer(sa,dtype="<u4"))),
        "worker_cells_changed_by_frame":int(np.count_nonzero(np.frombuffer(ib,dtype="<u4")!=np.frombuffer(sb,dtype="<u4"))),
        "samples":[{"cell":int(i),"active":float(xa[i]),"worker":float(xb[i])} for i in changed[:12]]}
out=args.worker.parent.parent/("edit_prepare_input_comparison_initial.json" if initial else "edit_prepare_input_comparison.json")
out.write_text(json.dumps(result,indent=2),encoding="utf-8")
print(json.dumps(result,indent=2))
