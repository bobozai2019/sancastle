"""Verify solid-face flux, preserved obstacle stock and a reflected real wave."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import numpy as np
from reference import Reference


def main():
    ap=argparse.ArgumentParser();ap.add_argument('directory',type=Path);ap.add_argument('--source-root',type=Path,required=True)
    args=ap.parse_args();root=args.directory.resolve();output=root/'analysis.json'
    if output.exists():raise FileExistsError(output)
    result=json.loads((root/'result.json').read_text(encoding='utf-8'));failures=[];rows=[]
    with zipfile.ZipFile(root/'consumed_sources.zip','x',zipfile.ZIP_DEFLATED) as z:
        for source,expected in result['configuration']['sources'].items():
            raw=(args.source_root/source.removeprefix('res://')).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=expected:failures.append('source drift:'+source)
            z.writestr(source.removeprefix('res://'),raw)
    def fields(snap):
        data={}
        for name,item in snap['fields'].items():
            raw=Path(item['path']).read_bytes()
            if len(raw)!=item['bytes'] or hashlib.sha256(raw).hexdigest()!=item['sha256']:failures.append(snap['label']+'/'+name+': raw identity')
            if name in ('rock','sand','water','momentum_x','momentum_z','sediment','public_water'):data[name]=np.frombuffer(raw,dtype='<f4').astype(float).reshape(256,256)
            if name=='obstacle':data[name]=np.frombuffer(raw,dtype='u1').reshape(256,256)>=128
            if name=='flux':data[name]=np.frombuffer(raw,dtype='<f4').reshape(256,256,4)
            if name=='audit':data[name]=np.frombuffer(raw,dtype='<u4').reshape(64,8)
        return data
    initial=fields(result['snapshots'][0]);mask=initial['obstacle'];bed=initial['rock']+initial['sand']
    state=np.stack([initial[k] for k in ['water','momentum_x','momentum_z','sediment']]);solver=Reference(bed,.125,obstacle=mask)
    x=(np.arange(256)+.5-128)*.125;X,Z=np.meshgrid(x,x);band=(X>-1.3)&(X<-.25)&(abs(Z)<.5)
    initial_mass=float(initial['water'][~mask].sum()*.125**2)
    for index,snap in enumerate(result['snapshots']):
        data=fields(snap);current=np.stack([data[k] for k in ['water','momentum_x','momentum_z','sediment']])
        if index:
            accepted=data['audit'][data['audit'][:,2]==1]
            for bits in accepted[:,1]:
                dt=float(np.array([bits],dtype='<u4').view('<f4')[0]);a=solver.euler(state,dt);b=solver.euler(a.state,dt);state=.5*(state+b.state);solver.limit_momentum(state)
        error=np.max(abs(state-current),axis=(1,2))
        flux=data['flux'];xm=mask[:,:-1]|mask[:,1:];zm=mask[:-1,:]|mask[1:,:]
        blocked_flux=max(float(flux[:,:-1,1][xm].max(initial=0)),float(flux[:,1:,0][xm].max(initial=0)),float(flux[:-1,:,3][zm].max(initial=0)),float(flux[1:,:,2][zm].max(initial=0)))
        row={'time_s':snap['advanced_time_s'],'minimum_upstream_qx':float(current[1,band].min()),'blocked_face_flux_m3_s':blocked_flux,
             'cpu_max_errors_h_qx_qz_s':error.tolist(),'water_relative_error':float((current[0,~mask].sum()*.125**2-initial_mass)/initial_mass)}
        if not np.isfinite(current).all() or np.min(current[[0,3]])<0 or blocked_flux!=0:failures.append(snap['label']+': invalid state/solid flux')
        if not np.array_equal(data['obstacle'],mask) or not np.array_equal(current[0,mask],initial['water'][mask]):failures.append(snap['label']+': obstacle changed or swallowed water')
        if not np.array_equal(data['water'],data['public_water']):failures.append(snap['label']+': unpublished field')
        if abs(row['water_relative_error'])>1e-5:failures.append(snap['label']+': water closure')
        if snap['advanced_time_s']<=.100001 and np.any(error>np.array([2e-5,1e-4,1e-4,2e-6])):failures.append(snap['label']+': short CPU comparison')
        rows.append(row);print(snap['label'],row['minimum_upstream_qx'],error.max(),flush=True)
    if rows[0]['minimum_upstream_qx']<0 or rows[-1]['minimum_upstream_qx']>=-1e-5:failures.append('no measurable reflected momentum')
    if result['outcome']!='pass' or result['source_drift']:failures.append('probe failed')
    output.write_text(json.dumps({'outcome':'fail' if failures else 'pass','rows':rows,'failures':failures,
        'scope':'Fixed-bed real water reflection with solid mask; short CPU error gate and retained later field comparison',
        'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'reference_sha256':hashlib.sha256(Path(__file__).with_name('reference.py').read_bytes()).hexdigest()},indent=2),encoding='utf-8')
    raise SystemExit(bool(failures))


if __name__=='__main__':main()
