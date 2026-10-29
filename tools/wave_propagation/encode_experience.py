"""Encode unchanged captured frames at their 0.1 simulated-second interval."""
import argparse,hashlib,json,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--run',type=Path,required=True);p.add_argument('--encoder',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False);r=json.loads((a.run/'diagnosis.json').read_text());records=[]
 for case in r['cases']:
  frames=sorted((a.run/case['id']).glob('frame_*.png'))
  if not frames:continue
  first=int(frames[0].stem.split('_')[1]);last=int(frames[-1].stem.split('_')[1]);assert [int(f.stem.split('_')[1]) for f in frames]==list(range(first,last+1))
  file=a.output/(case['id']+'.mp4');cmd=[str(a.encoder.resolve()),'-hide_banner','-loglevel','error','-framerate','10','-start_number',str(first),'-i',str((a.run/case['id']/'frame_%03d.png').resolve()),'-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(file.resolve())];subprocess.run(cmd,check=True,timeout=120)
  records.append({'case_id':case['id'],'simulated_start_s':first*.1,'simulated_end_s':last*.1,'displayed_frame_duration_s':.1,'frames':[{'path':str(f.resolve()),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in frames],'output':str(file.resolve()),'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'command':cmd})
 (a.output/'index.json').write_text(json.dumps({'schema':1,'scope':'Completed-time diagnostic replay, 10 frames/s. Does not represent measured realtime throughput. Captured source frames unchanged.','encoder':str(a.encoder.resolve()),'encoder_sha256':hashlib.sha256(a.encoder.read_bytes()).hexdigest(),'records':records},indent=2));print(a.output)
if __name__=='__main__':main()
