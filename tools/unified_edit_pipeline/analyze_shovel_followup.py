"""Summarize diagnostic evidence, not a performance acceptance gate."""
import argparse,collections,hashlib,json,math,re,statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def stats(values):
 values=sorted(values)
 return {"n":len(values),"p50":statistics.median(values),"p95":values[math.ceil(.95*len(values))-1],"max":values[-1]} if values else {}
def main():
 parser=argparse.ArgumentParser();parser.add_argument("folder",type=Path);args=parser.parse_args();folder=args.folder.resolve()
 results={};evidence={}
 for name,path in [("normal_first",folder.parent/"coarse.json"),("water_stages",folder/"water.json"),("height_held",folder/"hold_height.json"),("normal_repeat",folder/"coarse_repeat.json")]:
  data=json.loads(path.read_text("utf-8"));assert data["pass"],path
  evidence[name]={"path":str(path),"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
  collision=collections.defaultdict(list)
  for call in data["observations"]["collision_calls"]:collision[call["frame"]].append(call)
  phases={}
  for phase in dict.fromkeys(frame["phase"] for frame in data["frames"]):
   frames=[frame for frame in data["frames"] if frame["phase"]==phase]
   phases[phase]={"frame_ms":stats([frame["frame_us"]/1000 for frame in frames]),"collision_ms_by_engine_frame":stats([sum(call["elapsed_us"]/1000 for call in collision[frame["frame_id"]]) for frame in frames]),"max_pending":max(frame["pending"] for frame in frames)}
  water=collections.defaultdict(list)
  for packet in data["gpu_samples"]:
   for span in packet["spans"]:
    match=re.match(r"^shovel_water_\d+_(.*)$",span["label"])
    if match:water[match[1]].append(span["gpu_ns"]/1e6)
  results[name]={"phases":phases,"water_gpu_ms":{key:stats(value) for key,value in water.items()},"height_control":data["observations"].get("height_consumer_control","normal"),"top_collision_frames":[{"frame":frame,"calls":len(calls),"cpu_ms":sum(call["elapsed_us"] for call in calls)/1000} for frame,calls in sorted(collision.items(),key=lambda item:sum(call["elapsed_us"] for call in item[1]),reverse=True)[:5]]}
 sources={}
 for path in (ROOT/"tools/unified_edit_pipeline").glob("*shovel*.gd"):sources[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
 for name in ["scripts/simulation/unified_edit/water_response.gd","scripts/simulation/unified_edit/water_response.glsl","scripts/simulation/unified_edit/height.gd","scripts/simulation/unified_edit/height_surface.gd","shaders/simulation/edit_validation/water_packed_cached.glsl","shaders/simulation/edit_validation/water_velocity_prefetch.glsl"]:sources[name]=hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
 report={"scope":"Main/live/default shovel, starting dry footprint, synthetic fixed XZ path through PlayerInput+preview. User confirmed scene/live state only; tool size and wet location unspecified. First normal / height held / normal repeat are exploratory sequential runs, no identical sim-time field equality claim. Holding physics stops height captures when two slots fill; not a pure shape-call ablation. Detailed timestamps affect cost. Periodically refreshed Performance monitors excluded from per-frame causal claims.","evidence":evidence,"sources":sources,"results":results}
 (folder/"analysis.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n","utf-8")
 print(json.dumps({key:value["phases"].get("playing_drag") for key,value in results.items()},indent=2))
if __name__=="__main__":main()
