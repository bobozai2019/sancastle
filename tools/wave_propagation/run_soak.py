"""Serial visible-GPU correctness soak; no performance measurement."""
import argparse,hashlib,json,subprocess,time,zipfile,msvcrt
from pathlib import Path
from run_lifecycle_case import ENGINE
CASES=['lake_flat','lake_slope','lake_step','lake_shore','lake_obstacle','erosion','molded_edit']
def main():
 p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--case',choices=CASES,required=True);p.add_argument('--duration',type=float,default=300);p.add_argument('--detector-negative',action='store_true');a=p.parse_args()
 if not 0<a.duration<=300:p.error('invalid duration')
 runtime=a.runtime.resolve();out=a.output.resolve();lock_path=Path(__file__).resolve().parents[2]/'test_output/wave_propagation/experience_gpu.lock';lock=lock_path.open('a+b');lock.seek(0)
 if lock_path.stat().st_size==0:lock.write(b'0');lock.flush()
 lock.seek(0)
 try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
 except OSError:raise SystemExit('GPU test already active')
 out.mkdir(parents=True,exist_ok=False);script=runtime/'tools/wave_propagation/soak_probe.gd';(out/'probe.gd').write_bytes(script.read_bytes());(out/'runner.py').write_bytes(Path(__file__).read_bytes())
 cmd=[ENGINE,'--path',str(runtime),'--rendering-driver','d3d12','--script','res://tools/wave_propagation/soak_probe.gd','--','--output='+str(out),'--case='+a.case,'--duration='+str(a.duration),'--solver=muscl_mc_ssprk2_v1']
 if a.detector_negative:cmd.append('--detector-negative')
 row={'command':cmd,'outcome':'running','expected_detector_failure':a.detector_negative,'probe_sha256':hashlib.sha256(script.read_bytes()).hexdigest(),'scope':'Functional five-minute GPU correctness; monitor overhead, no timing/cost claim'};start=time.time()
 with (out/'stdout.txt').open('w',encoding='utf-8') as log:
  child=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT);row['pid']=child.pid;(out/'manifest.json').write_text(json.dumps(row,indent=2))
  try:row['exit_code']=child.wait(timeout=7200)
  except subprocess.TimeoutExpired:child.terminate();row['exit_code']=child.wait();row['timeout']=True
 row['elapsed_wall_s']=time.time()-start;row['outcome']='incomplete';f=out/'result.json'
 if f.exists():
  r=json.loads(f.read_text());failed=[c['label'] for c in r['checks'] if not c['pass']];row['failed_checks']=failed;row['outcome']='pass' if r['outcome']=='pass' and not row['exit_code'] and not failed else 'fail';drift=[]
  with zipfile.ZipFile(out/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
   for name,h in r['configuration']['sources'].items():
    raw=(runtime/name.removeprefix('res://')).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=h:drift.append(name)
    z.writestr(name.removeprefix('res://'),raw)
  row['source_drift']=drift
  if a.detector_negative:row['outcome']='pass_expected_rejection' if failed==['all_tick_h_drift'] and row['exit_code']==1 and not drift else 'fail'
  if drift:row['outcome']='fail'
 (out/'manifest.json').write_text(json.dumps(row,indent=2));print(json.dumps(row,indent=2));print((out/'stdout.txt').read_text(encoding='utf-8',errors='replace')[-2200:]);raise SystemExit(row['outcome'] not in ['pass','pass_expected_rejection'])
if __name__=='__main__':main()
