"""Analyze one real full-window run; completion validity and target attainment stay separate."""
import argparse,hashlib,json,math,zipfile
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('folder',type=Path);a=p.parse_args();folder=a.folder.resolve();target=folder/'analysis.json'
 if target.exists():raise FileExistsError(target)
 r=json.loads((folder/'result.json').read_text());errors=[]
 if r['outcome']!='measured' or not r['checks'] or not all(x['pass'] for x in r['checks']):errors.append('runtime checks')
 with zipfile.ZipFile(folder/'consumed_sources.zip') as z:
  for name,h in r['configuration']['sources'].items():
   if hashlib.sha256(z.read(name.removeprefix('res://'))).hexdigest()!=h:errors.append('source:'+name)
 frames=r['frames'];durations=sorted(x['frame_interval_us']/1000 for x in frames);start=r['start'];end=r['finish'];wall=(end['at_us']-start['at_us'])/1e6;advanced=end['advanced_time_s']-start['advanced_time_s'];ticks=int(end['tick'])-int(start['tick'])
 if not durations or min(durations)<=0 or wall<60 or ticks<=0:errors.append('invalid window')
 def percentile(p):return durations[max(0,math.ceil(p*len(durations))-1)]
 pending=max(x['pending'] for x in frames);active=max(x['active'] for x in frames)
 if pending>64 or active>3:errors.append('queue capacity')
 if any(x['props_error'] or x['gravel_visible']!=512 for x in frames):errors.append('consumer workload/fault')
 if any(not e['begin'].get('accepted') or not e['move'].get('accepted') or not e['end'].get('accepted') for e in r['edits']):errors.append('input admission')
 physical=[x for x in r['terminals_observed_at_window_end'] if x.get('profile_version',0)>0]
 if len(physical)<len(r['edits']) or any(x.get('error_code',0)!=0 or x.get('outcome') not in [1,2] for x in physical):errors.append('physical edit outcomes')
 thresholds={'p99_le_50ms':percentile(.99)<=50,'advanced_per_wall_ge_0_80':advanced/wall>=.8}
 report={'schema':1,'outcome':'invalid' if errors else 'measured','failures':errors,'performance_targets_met':all(thresholds.values()),'targets':thresholds,'solver_id':r['solver_id'],'window_wall_s':wall,'completed_advanced_s':advanced,'completed_ticks':ticks,'advance_per_wall':advanced/wall,'completed_time_per_requested_tick':advanced/(ticks/30),'frame_count':len(frames),'frame_ms':{'p50':percentile(.5),'p95':percentile(.95),'p99':percentile(.99),'max':max(durations),'mean':sum(durations)/len(durations)},'focused_frame_fraction':sum(bool(x['focused']) for x in frames)/len(frames),'queue_max':{'pending':pending,'active':active},'edit_strokes':len(r['edits']),'terminals_at_window_end':len(r['terminals_observed_at_window_end']),'memory':r['memory_after_window'],'hardware':r['hardware'],'endpoint_quantization':{'start':start,'end':end,'note':'CPU-observed completed timestamps at matching monotonic process-frame endpoints; receipt delivery is quantized. No claim that CPU notifications equal GPU execution time.'},'limitations':r['limitations'],'analyzer_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()};target.write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ['hardware','endpoint_quantization']},indent=2));raise SystemExit(bool(errors))
if __name__=='__main__':main()
