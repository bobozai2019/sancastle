"""Serial full-window normal-main measurement, bounded by the live G6 cost clock."""
import argparse,hashlib,json,msvcrt,subprocess,time,zipfile
from pathlib import Path
from run_lifecycle_case import ENGINE

def main():
 p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--solver',choices=['muscl_mc_ssprk2_v1','rusanov_first_order_v1'],default='muscl_mc_ssprk2_v1');a=p.parse_args();root=Path(__file__).resolve().parents[2];runtime=a.runtime.resolve();out=a.output.resolve();budget=json.loads((root/'test_output/wave_propagation/g6_cost_budget_01/budget.json').read_text())
 remaining=budget['deadline_wall_s']-time.time()
 if budget['status']!='active' or remaining<420:raise SystemExit('Insufficient active cost budget for measurement and reserve')
 lock=(root/'test_output/wave_propagation/experience_gpu.lock').open('a+b');lock.seek(0)
 try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
 except OSError:raise SystemExit('GPU probe still active')
 out.mkdir(parents=True,exist_ok=False);probe=root/'tools/wave_propagation/cost_probe.gd';(runtime/'tools/wave_propagation/cost_probe.gd').write_bytes(probe.read_bytes());(out/'probe.gd').write_bytes(probe.read_bytes());(out/'runner.py').write_bytes(Path(__file__).read_bytes());cmd=[ENGINE,'--path',str(runtime),'--rendering-driver','d3d12','--script','res://tools/wave_propagation/cost_probe.gd','--','--output='+str(out),'--solver='+a.solver];row={'command':cmd,'outcome':'running','started_wall_s':time.time(),'probe_sha256':hashlib.sha256(probe.read_bytes()).hexdigest()}
 with (out/'stdout.txt').open('w',encoding='utf-8') as log:
  child=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT);row['pid']=child.pid;(out/'manifest.json').write_text(json.dumps(row,indent=2))
  try:row['exit_code']=child.wait(timeout=min(300,remaining-300))
  except subprocess.TimeoutExpired:child.terminate();row['exit_code']=child.wait();row['timeout']=True
 row['finished_wall_s']=time.time();row['outcome']='incomplete';file=out/'result.json'
 if file.exists():
  r=json.loads(file.read_text());row['outcome']='measured' if r['outcome']=='measured' and not row['exit_code'] else 'fail';drift=[]
  with zipfile.ZipFile(out/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
   for name,h in r['configuration']['sources'].items():
    raw=(runtime/name.removeprefix('res://')).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=h:drift.append(name)
    z.writestr(name.removeprefix('res://'),raw)
  row['source_drift']=drift
  if drift:row['outcome']='fail'
 if row['exit_code']:row['outcome']='fail'
 (out/'manifest.json').write_text(json.dumps(row,indent=2));print(json.dumps(row,indent=2));print((out/'stdout.txt').read_text(encoding='utf-8',errors='replace')[-1800:]);raise SystemExit(row['outcome']!='measured')
if __name__=='__main__':main()
