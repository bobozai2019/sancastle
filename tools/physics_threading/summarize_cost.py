"""Stream raw evidence; never fill unmeasured worker stages with zero."""
import json
import math
import sys
from pathlib import Path

def stats(values):
    values=sorted(values)
    if not values:return {"n":0}
    result={"n":len(values),"max":values[-1]}
    for name,p in [("p50",.5),("p95",.95),("p99",.99),("p999",.999)]:
        result[name]=values[max(0,math.ceil(len(values)*p)-1)]
    return result

def summarize(folder):
    folder=Path(folder)
    trace=json.loads((folder/"trace.json").read_text(encoding="utf-8"))
    frames={};collisions={};phases={};input_calls={}
    with (folder/"trace.jsonl").open(encoding="utf-8") as stream:
        for line in stream:
            row=json.loads(line);name=row["case"]
            if row["type"]=="frame":frames.setdefault(name,[]).append(row)
            elif row["type"]=="collision":collisions.setdefault(name,[]).append(row)
            elif row["type"]=="input_call":input_calls.setdefault(name,[]).append(row)
            elif row["type"]=="phase":
                value=row["value"]
                phases.setdefault(name,{}).setdefault(value["command_id"],{})[value["phase"]]=value
    output=[]
    for case in trace["cases"]:
        name=case["name"]
        intervals=[r["interval_us"]/1000 for r in frames.get(name,[]) if r["us"]<case["stop_us"]]
        batches=collisions.get(name,[])
        feedback=[];ack=[];terminal=[]
        accepted=[r for r in case["inputs"] if not r.get("admission_error")]
        by_terminal={r["command"]["command_id"]:r for r in case["terminals"]}
        for admission in accepted:
            cid=admission["command"]["command_id"];start=admission["input_us"]
            marks=phases.get(name,{}).get(cid,{})
            if "collision_ready" in marks:ack.append((marks["collision_ready"]["at_us"]-start)/1000)
            if "physics_two" in marks:feedback.append((marks["physics_two"]["at_us"]-start)/1000)
            if cid in by_terminal:terminal.append((by_terminal[cid]["at_us"]-start)/1000)
        prepare=[]
        for row in batches:
            seg=row["segments"]
            if all(k in seg for k in ["decode_us","finite_us","slice_us"]):
                prepare.append(sum(seg[k] for k in ["decode_us","finite_us","slice_us"]))
            elif all(k in seg for k in ["admission_us","poll_cpu_us"]):
                prepare.append(seg["admission_us"]+seg["poll_cpu_us"])
        duration=(case["stop_us"]-case["start_us"])/1e6
        output.append({"name":name,"window_s":duration,"tick_rate":(case["stop_tick"]-case["begin_tick"])/duration,
            "frame_ms":stats(intervals),"stalls":{str(b):sum(v>b for v in intervals) for b in [100,250,500]},
            "main_prepare_us":stats(prepare),"apply_ms":stats([r["apply_ms"] for r in batches]),
            "submit_ms":stats([r["replace_ms"] for r in batches]),"readback_ms":stats([r["readback_ms"] for r in batches]),
            "admission_to_collision_ack_ms":stats(ack),"admission_to_physics_two_ms":stats(feedback),
            "admission_to_terminal_ms":stats(terminal),"accepted":len(accepted),"terminals":len(case["terminals"]),
            "input_calls":len(input_calls.get(name,[])),"acceptance_rate":len(accepted)/len(input_calls[name]) if input_calls.get(name) else None,"error":case["error"],
            "mode_counts":{mode:sum(r["mode"]==mode for r in batches) for mode in sorted({r["mode"] for r in batches})},
            "by_chunks":{str(n):{"n":sum(r["chunks"]==n for r in batches)} for n in sorted({r["chunks"] for r in batches})}})
    result={"configuration":trace["configuration"],"released":trace["released"],"cases":output,
        "limits":["post_draw is submission observation, not display scanout","GPU timestamps sampled at 100ms, not complete per-frame GPU costs",
                  "main preparation excludes physical shape submission; worker CPU sum contains snapshot/admission/collection",
                  "raw stream includes each bounded collision sample; no coalescing to last batch per process frame"]}
    (folder/"summary.json").write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding="utf-8")
    print([(c["name"],c["tick_rate"],c["frame_ms"].get("p99"),c["main_prepare_us"].get("p95")) for c in output])
    return result

if __name__=="__main__":
    for folder in sys.argv[1:]:summarize(folder)
