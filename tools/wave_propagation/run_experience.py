"""Dense C03 paired field capture; serial GPU, immutable consumed source archive."""
import argparse,hashlib,json,subprocess,time,zipfile,msvcrt
from pathlib import Path
from run_lifecycle_case import ENGINE

def main():
 p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--bodies',action='store_true');p.add_argument('--detail-off',action='store_true');p.add_argument('--mode',choices=['flat','main'],required=True);p.add_argument('--solver',choices=['rusanov_first_order_v1','muscl_mc_ssprk2_v1'],required=True);a=p.parse_args();out=a.output.resolve();runtime=a.runtime.resolve();lock_path=Path(__file__).resolve().parents[2]/'test_output/wave_propagation/experience_gpu.lock';lock_path.parent.mkdir(parents=True,exist_ok=True);lock_handle=lock_path.open('a+b');lock_handle.seek(0);
 if lock_path.stat().st_size==0:lock_handle.write(b'0');lock_handle.flush()
 lock_handle.seek(0)
 try:msvcrt.locking(lock_handle.fileno(),msvcrt.LK_NBLCK,1)
 except OSError:raise SystemExit('Another experience GPU process is active; refused before launch')
 out.mkdir(parents=True,exist_ok=False)
 script_name='experience_display_probe.gd' if a.detail_off else ('experience_body_probe.gd' if a.bodies else 'experience_probe.gd');script=runtime/'tools/wave_propagation'/script_name;(out/'probe.gd').write_bytes(script.read_bytes());(out/'runner.py').write_bytes(Path(__file__).read_bytes())
 cmd=[ENGINE,'--path',str(runtime),'--rendering-driver','d3d12','--script','res://tools/wave_propagation/'+script_name,'--','--output='+str(out),'--mode='+a.mode,'--solver='+a.solver]
 row={'command':cmd,'outcome':'running','probe_sha256':hashlib.sha256(script.read_bytes()).hexdigest(),'body_fixture':a.bodies,'detail_normals_off':a.detail_off,'scope':'Dense physical paired diagnostics; main authored props user-paused, not body experience acceptance. No performance measurement.'};start=time.time()
 with (out/'stdout.txt').open('w',encoding='utf-8') as log:
  child=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT);row['pid']=child.pid;(out/'manifest.json').write_text(json.dumps(row,indent=2))
  try:row['exit_code']=child.wait(timeout=900)
  except subprocess.TimeoutExpired:child.terminate();row['exit_code']=child.wait();row['timeout']=True
 if a.detail_off:row['display_treatment']='use_detail_normals=false only; unchanged physical fields must be independently verified'
 if a.bodies:row['scope']='Actual main, existing near/far props, common completed-time manual pacing, real Jolt and original force model; no performance measurement.'
 row['elapsed_wall_s']=time.time()-start;row['outcome']='incomplete'
 f=out/'diagnosis.json'
 if f.exists():
  r=json.loads(f.read_text());row['outcome']='pass' if r['pass'] and len(r['cases'])==2 and all(c['pass'] for c in r['checks']) else 'fail';drift=[]
  with zipfile.ZipFile(out/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
   for source,h in r['source_hashes'].items():
    raw=(runtime/source.removeprefix('res://')).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=h:drift.append(source)
    z.writestr(source.removeprefix('res://'),raw)
  row['source_drift']=drift
  if drift:row['outcome']='fail'
 if row['exit_code']:row['outcome']='fail'
 (out/'manifest.json').write_text(json.dumps(row,indent=2));print(json.dumps(row,indent=2));print((out/'stdout.txt').read_text(encoding='utf-8',errors='replace')[-2200:]);raise SystemExit(row['outcome']!='pass')
if __name__=='__main__':main()
