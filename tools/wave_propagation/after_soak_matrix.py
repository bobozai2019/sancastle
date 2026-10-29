"""Wait for the exact live matrix process, then run formal smoke and full soak serially."""
import argparse,ctypes,hashlib,json,subprocess,sys,time
from ctypes import wintypes
from pathlib import Path
from run_lifecycle_case import ENGINE

def main():
 p=argparse.ArgumentParser();p.add_argument('--matrix',type=Path,required=True);p.add_argument('--parent-pid',type=int,required=True);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);(out/'coordinator.py').write_bytes(Path(__file__).read_bytes());state={'outcome':'waiting_matrix','matrix':str(a.matrix.resolve()),'matrix_parent_pid':a.parent_pid,'runtime':str(a.runtime.resolve()),'completed':[],'started_wall_s':time.time()};source_names=['run_formal_soak.py','formal_soak_probe.gd','audit_formal_soak_native.gd','audit_source_restore.gd','analyze_formal_soak.py'];pins={n:hashlib.sha256((root/'tools/wave_propagation'/n).read_bytes()).hexdigest() for n in source_names};state['source_pins']=pins
 def write(): (out/'state.json').write_text(json.dumps(state,indent=2))
 def unchanged():
  for n,h in pins.items():
   if hashlib.sha256((root/'tools/wave_propagation'/n).read_bytes()).hexdigest()!=h:raise RuntimeError('Coordinator source changed: '+n)
 write();kernel=ctypes.WinDLL('kernel32',use_last_error=True);kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];kernel.OpenProcess.restype=wintypes.HANDLE;kernel.WaitForSingleObject.argtypes=[wintypes.HANDLE,wintypes.DWORD];kernel.WaitForSingleObject.restype=wintypes.DWORD;kernel.CloseHandle.argtypes=[wintypes.HANDLE];handle=kernel.OpenProcess(0x100000,False,a.parent_pid)
 try:
  if handle:
   while True:
    status=kernel.WaitForSingleObject(handle,5000)
    if status==0:break
    if status!=258:raise OSError('Matrix process observation failed: '+str(status))
  matrix=json.loads((a.matrix/'state.json').read_text());expected=['lake_flat','lake_slope','lake_step','lake_shore','lake_obstacle','erosion','molded_edit']
  if matrix.get('outcome')!='pass' or matrix.get('completed')!=expected:raise RuntimeError('Matrix did not complete all seven cases: '+repr(matrix))
  state['matrix_terminal_outcome']='pass';write()
  for seconds,name in [(2,'g6_formal_soak_smoke_01'),(300,'g6_formal_soak_01')]:
   unchanged();folder=root/'test_output/wave_propagation'/name;state['outcome']='running_formal';state['current_run']=name;write();print('FORMAL_START',name,flush=True)
   subprocess.run([sys.executable,str(root/'tools/wave_propagation/run_formal_soak.py'),'--runtime',str(a.runtime.resolve()),'--output',str(folder),'--seconds',str(seconds)],check=True)
   unchanged()
   with (folder/'native_audit_stdout.txt').open('w',encoding='utf-8') as log:subprocess.run([ENGINE,'--headless','--path',str(root),'--script','res://tools/wave_propagation/audit_formal_soak_native.gd','--',str(folder)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
   cmd=[sys.executable,str(root/'tools/wave_propagation/analyze_formal_soak.py'),str(folder)]
   if seconds==300:cmd.append('--full')
   subprocess.run(cmd,check=True);state['completed'].append(name);write();print('FORMAL_TERMINAL',name,flush=True)
  state['outcome']='pass';state['current_run']=None
 except Exception as e:state['outcome']='fail';state['error']=repr(e);raise
 finally:
  if handle:kernel.CloseHandle(handle)
  state['finished_wall_s']=time.time();write()
if __name__=='__main__':main()
