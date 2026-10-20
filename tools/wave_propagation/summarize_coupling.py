"""Aggregate the fixed G3 matrix and actual external-source receipts."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--first-order',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    a.output.mkdir(parents=True,exist_ok=False);failures=[];rows=[];inputs={}
    def load(p):
        inputs[str(p.resolve())]=hashlib.sha256(p.read_bytes()).hexdigest();return json.loads(p.read_text(encoding='utf-8'))
    def require(ok,reason):
        if not ok:failures.append(reason)
    for suite_root,expected in [(a.candidate,{'erosion','deposition','transport_forward','transport_backward','constant_001_off','constant_005_off','reversal','near_dry','obstacle','boundary','support','molded_edit'}),(a.first_order,{'erosion','deposition','boundary','support'})]:
        suite=load(suite_root/'result.json');require(suite['outcome']=='pass' and not suite['source_drift'],'suite '+str(suite_root));require({r['id'] for r in suite['rows']}==expected,'fixed matrix '+str(suite_root))
        for entry in suite['rows']:
            directory=suite_root/entry['id'];analysis=load(directory/'analysis.json');raw=load(directory/'result.json');manifest=load(directory/'manifest.json')
            require(analysis['outcome']=='pass' and raw['outcome']=='pass' and manifest['exit_code']==0 and manifest['outcome']=='pass',str(directory)+' run checks')
            for snap in raw['snapshots']:
                for name,item in snap['fields'].items():
                    path=Path(item['path']);require(path.stat().st_size==item['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'],str(directory)+'/'+snap['label']+'/'+name)
            rs=analysis['rows'];row={'solver':raw['solver_id'],'case_id':raw['case_id'],'water_relative_error':max(r['water_relative_error'] for r in rs),'solid_relative_error':max(r['solid_relative_error'] for r in rs),'advanced_time_s':rs[-1]['time_s'],'accepted_substeps':sum(r.get('accepted_substeps',0) for r in rs),
                                    'cpu_max_field_error':max(max(r.get('cpu_max_errors_h_qx_qz_s',[0])) for r in rs),'cpu_max_sand_error_m':max(r.get('cpu_max_sand_error_m',0) for r in rs),'once_exchange_error_m':max(r.get('once_exchange_scalar_error_m',0) for r in rs),'constant_concentration_error':max(r.get('concentration_error',0) for r in rs)}
            ledger=raw['final_ledger']['values'];require(ledger['tool_inventory_m3']==0 and ledger['sand_sink_m3']==0,'unexpected bank/sink '+str(directory))
            if raw['case_id']=='molded_edit':
                initial,edited=raw['snapshots'][:2];receipt=raw['setup_result']
                def stock(snap,fields):return sum(np.fromfile(snap['fields'][field]['path'],dtype='<f4').astype(float).sum() for field in fields)*.125**2
                solid_delta=stock(edited,['sand','sediment'])-stock(initial,['sand','sediment']);water_delta=stock(edited,['water'])-stock(initial,['water'])
                require(abs(solid_delta-receipt['source_m3']+receipt['sink_m3'])<=receipt['eps_sand_m3'],'castle receipt stock')
                require(abs(water_delta)<=receipt['eps_water_m3'],'castle displaced water closure')
                require(ledger['sand_source_m3']==receipt['source_m3'],'castle exact external source ledger')
                row['external_source_audit']={'solid_delta_m3':solid_delta,'receipt_source_m3':receipt['source_m3'],'ledger_source_m3':ledger['sand_source_m3'],'water_delta_m3':water_delta,'sand_tolerance_m3':receipt['eps_sand_m3'],'water_tolerance_m3':receipt['eps_water_m3']}
            else:require(ledger['sand_source_m3']==0,'exchange must not book external sand '+str(directory))
            rows.append(row)
    stage=load(a.candidate/'reversal/stage_transport_analysis.json');require(stage['outcome']=='pass','raw stage reconstruction')
    report={'schema':1,'outcome':'fail' if failures else 'pass','failures':failures,'rows':rows,'stage_transport':stage,'input_hashes':inputs,'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'G3 short coupling only; no G4 recovery, G5 gameplay, G6 stability/performance conclusion'}
    (a.output/Path(__file__).name).write_bytes(Path(__file__).read_bytes());(a.output/'result.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps({'outcome':report['outcome'],'failures':failures,'cases':len(rows)},indent=2));raise SystemExit(bool(failures))


if __name__=='__main__':main()
