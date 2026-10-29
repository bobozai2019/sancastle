"""Pinned serial five-minute numerical matrix; stops on any failed case."""
import argparse,hashlib,json,subprocess,sys,time
from pathlib import Path
CASES=['lake_flat','lake_slope','lake_step','lake_shore','lake_obstacle','erosion','molded_edit']
def main():
 p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);analyzer=Path(__file__).with_name('analyze_soak.py');(out/'analyze_soak.py').write_bytes(analyzer.read_bytes());(out/'matrix.py').write_bytes(Path(__file__).read_bytes());fixture={'schema':1,'cases':CASES,'duration_s':300,'solver_id':'muscl_mc_ssprk2_v1','runtime':str(a.runtime.resolve()),'scope':'Read-only monitor + five-minute numerical correctness, not performance'};(out/'fixture.json').write_text(json.dumps(fixture,indent=2));state={'outcome':'running','current_case':None,'completed':[],'started_wall_s':time.time()};(out/'state.json').write_text(json.dumps(state,indent=2))
 try:
  for case in CASES:
   state['current_case']=case;(out/'state.json').write_text(json.dumps(state,indent=2));print('SOAK_START',case,flush=True);folder=out/case;cmd=[sys.executable,str(root/'tools/wave_propagation/run_soak.py'),'--runtime',str(a.runtime.resolve()),'--output',str(folder),'--case',case,'--duration','300'];subprocess.run(cmd,check=True);subprocess.run([sys.executable,str(out/'analyze_soak.py'),str(folder),'--full'],check=True);state['completed'].append(case);(out/'state.json').write_text(json.dumps(state,indent=2));print('SOAK_TERMINAL',case,flush=True)
  state['outcome']='pass';state['current_case']=None
 except Exception as e:
  state['outcome']='fail';state['error']=repr(e);raise
 finally:
  state['finished_wall_s']=time.time();(out/'state.json').write_text(json.dumps(state,indent=2))
if __name__=='__main__':main()
