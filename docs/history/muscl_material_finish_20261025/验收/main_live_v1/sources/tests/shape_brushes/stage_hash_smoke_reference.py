import argparse
import json
from stage_log_reference import load_trace,verify_hash_calibration

if __name__=='__main__':
    from pathlib import Path
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    identity,rows=load_trace(args.output.parent/'stage_log_smoke');audit=verify_hash_calibration(identity)
    args.output.mkdir(parents=True,exist_ok=True)
    result={'pass':audit['pass'],'checks':[{'name':'gpu_tile_hash_matches_independent_cpu_raw','pass':audit['pass'],'detail':audit}], 'scope':'Five tick logger calibration only, no physics or compatibility gate.'}
    (args.output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('STAGE_HASH_CALIBRATION',result['pass']);raise SystemExit(0 if result['pass'] else 1)
