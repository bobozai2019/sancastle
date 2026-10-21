"""Full formal-main correctness soak, serialized with every GPU acceptance probe."""
import argparse,hashlib,json,subprocess,time,zipfile,msvcrt
from pathlib import Path
from run_lifecycle_case import ENGINE

def main():
 p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--seconds',type=int,default=300);a=p.parse_args()
 if not 2<=a.seconds<=300:p.error('seconds must be2..300')
 root=Path(__file__).resolve().parents[2];runtime=a.runtime.resolve();out=a.output.resolve();lock=(root/'test_output/wave_propagation/experience_gpu.lock').open('a+b');lock.seek(0)
 try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
 except OSError:raise SystemExit('GPU acceptance test still active; refused before file changes or engine launch')
 out.mkdir(parents=True,exist_ok=False);src=root/'tools/wave_propagation/formal_soak_probe.gd';script=runtime/'tools/wave_propagation/formal_soak_probe.gd';script.write_bytes(src.read_bytes());digest=hashlib.sha256(script.read_bytes()).hexdigest();amendment=runtime/('formal_probe_addition_'+digest[:8]+'.json')
 if not amendment.exists():amendment.write_text(json.dumps({'scope':'New diagnostic entry only; product sources unchanged','path':str(script),'sha256':digest},indent=2))
 (out/'runner.py').write_bytes(Path(__file__).read_bytes());test_sources=['formal_soak_probe.gd','experience_body_probe.gd','experience_probe.gd']
 with zipfile.ZipFile(out/'test_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
  for name in test_sources:z.write(runtime/'tools/wave_propagation'/name,'tools/wave_propagation/'+name)
 cmd=[ENGINE,'--path',str(runtime),'--rendering-driver','d3d12','--script','res://tools/wave_propagation/formal_soak_probe.gd','--','--output='+str(out),'--solver=muscl_mc_ssprk2_v1','--mode=main','--seconds='+str(a.seconds)];row={'command':cmd,'outcome':'running','scope':'Formal-main correctness/Jolt/edit/restore soak; diagnostic pacing and readbacks, no performance claim','probe_sha256':digest};start=time.time()
 with (out/'stdout.txt').open('w',encoding='utf-8') as log:
  child=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT);row['pid']=child.pid;(out/'manifest.json').write_text(json.dumps(row,indent=2))
  try:row['exit_code']=child.wait(timeout=7200)
  except subprocess.TimeoutExpired:child.terminate();row['exit_code']=child.wait();row['timeout']=True
 row['elapsed_wall_s']=time.time()-start;row['outcome']='incomplete';f=out/'diagnosis.json'
 if f.exists():
  r=json.loads(f.read_text());row['failed_checks']=[c['label'] for c in r['checks'] if not c['pass']];row['outcome']='pass' if r['pass'] and len(r['cases'])==1 and r['checks'] and not row['exit_code'] and not row['failed_checks'] else 'fail';drift=[]
  with zipfile.ZipFile(out/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
   for name,h in r['source_hashes'].items():
    raw=(runtime/name.removeprefix('res://')).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=h:drift.append(name)
    z.writestr(name.removeprefix('res://'),raw)
  row['source_drift']=drift
  if drift:row['outcome']='fail'
 if row['exit_code']:row['outcome']='fail'
 (out/'manifest.json').write_text(json.dumps(row,indent=2));print(json.dumps(row,indent=2));print((out/'stdout.txt').read_text(encoding='utf-8',errors='replace')[-3000:]);raise SystemExit(row['outcome']!='pass')
if __name__=='__main__':main()
