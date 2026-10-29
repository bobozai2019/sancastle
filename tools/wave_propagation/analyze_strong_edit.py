"""Replay the real strong-edit or over-cap momentum case on the 2D reference."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import numpy as np
from reference import Reference, G


def main():
    ap=argparse.ArgumentParser();ap.add_argument('directory',type=Path);ap.add_argument('--source-root',type=Path,required=True)
    args=ap.parse_args();root=args.directory.resolve();output=root/'analysis.json'
    if output.exists():raise FileExistsError(output)
    report=json.loads((root/'result.json').read_text(encoding='utf-8'));failures=[];rows=[]
    with zipfile.ZipFile(root/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
        for source,expected in report['configuration']['sources'].items():
            raw=(args.source_root/source.removeprefix('res://')).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=expected:failures.append('source drift:'+source)
            z.writestr(source.removeprefix('res://'),raw)
    def read(snap,name):
        item=snap['fields'][name];raw=Path(item['path']).read_bytes()
        assert len(raw)==item['bytes'] and hashlib.sha256(raw).hexdigest()==item['sha256']
        return np.frombuffer(raw,dtype='<f4').astype(float).reshape(256,256)
    snapshots=report['snapshots'];start=1 if report['case_id']=='strong_shovel' else 0
    initial=snapshots[start];state=np.stack([read(initial,k) for k in ['water','momentum_x','momentum_z','sediment']])
    bed=read(initial,'rock')+read(initial,'sand');solver=Reference(bed,.125);mass=state[0].sum()*.125**2
    if start:
        before=read(snapshots[0],'water').sum()*.125**2
        if abs(mass-before)>max(1e-8,before*1e-5):failures.append('tool changed water inventory')
    for index,snap in enumerate(snapshots[start:]):
        if index:
            raw=Path(snap['fields']['audit']['path']).read_bytes();assert hashlib.sha256(raw).hexdigest()==snap['fields']['audit']['sha256']
            audit=np.frombuffer(raw,dtype='<u4').reshape(64,8)
            for row in audit[audit[:,2]==1]:
                dt=float(row[1:2].copy().view('<f4')[0]);a=solver.euler(state,dt);b=solver.euler(a.state,dt);state=.5*(state+b.state);solver.limit_momentum(state)
        current=np.stack([read(snap,k) for k in ['water','momentum_x','momentum_z','sediment']])
        error=np.max(abs(current-state),axis=(1,2));relative=float((current[0].sum()*.125**2-mass)/mass)
        row={'label':snap['label'],'time_s':snap['advanced_time_s'],'cpu_max_errors_h_qx_qz_s':error.tolist(),'water_relative_error':relative}
        if not np.isfinite(current).all() or np.min(current[[0,3]])<0 or abs(relative)>1e-5:failures.append(snap['label']+': positivity/finiteness/closure')
        if np.any(error>np.array([2e-5,1e-4,1e-4,2e-6])):failures.append(snap['label']+': strong-field CPU mismatch')
        if index:
            cap=current[0]*np.maximum(1.5,3*np.sqrt(G*current[0]));speed_excess=float((np.hypot(current[1],current[2])-cap).max())
            row['max_momentum_above_cap']=speed_excess
            if speed_excess>1e-6:failures.append(snap['label']+': final speed cap')
        rows.append(row);print(snap['label'],error.max(),relative,flush=True)
    raw=Path(snapshots[-1]['fields']['safety']['path']).read_bytes();assert hashlib.sha256(raw).hexdigest()==snapshots[-1]['fields']['safety']['sha256']
    safety=np.frombuffer(raw,dtype='<u4');cap_count=int(safety[4])+int(safety[5])*2**32
    if report['case_id']=='velocity_cap' and cap_count<=0:failures.append('GPU cap counter not exercised')
    if report['outcome']!='pass' or report['source_drift']:failures.append('probe failed')
    output.write_text(json.dumps({'outcome':'fail' if failures else 'pass','case_id':report['case_id'],'rows':rows,'failures':failures,'epoch_velocity_cap_count':cap_count,
        'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'reference_sha256':hashlib.sha256(Path(__file__).with_name('reference.py').read_bytes()).hexdigest(),
        'scope':'Actual completed strong shovel or velocity clipping, fixed bed after editing; no erosion/consumer acceptance'},indent=2),encoding='utf-8')
    raise SystemExit(bool(failures))


if __name__=='__main__':main()
