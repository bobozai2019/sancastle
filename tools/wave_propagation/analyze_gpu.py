"""Audit a GPU run and replay accepted dt on the full 2D CPU operator."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import numpy as np
from reference import Reference, G


def main():
    ap=argparse.ArgumentParser();ap.add_argument('directory',type=Path)
    ap.add_argument('--source-root',type=Path,required=True)
    ap.add_argument('--cpu',action='store_true')
    ap.add_argument('--report-name')
    args=ap.parse_args();root=args.directory.resolve()
    destination=root/(args.report_name or ('analysis_cpu.json' if args.cpu else 'analysis.json'))
    if destination.parent!=root or destination.suffix!='.json':ap.error('invalid report filename')
    if destination.exists():raise FileExistsError(destination)
    result=json.loads((root/'result.json').read_text(encoding='utf-8'))
    if args.cpu and result['solver_id']!='muscl_mc_ssprk2_v1':ap.error('CPU replay currently implements MUSCL only')
    failures=[];rows=[];clock=0.;last_first=None;last_second=None
    sources=result['configuration']['sources']
    archive=root/'consumed_sources.zip'
    if not archive.exists():
        with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as bundle:
            for source,expected in sources.items():
                path=args.source_root/source.removeprefix('res://')
                raw=path.read_bytes()
                if hashlib.sha256(raw).hexdigest()!=expected:failures.append('source changed before archive: '+source)
                bundle.writestr(source.removeprefix('res://'),raw)
    else:
        with zipfile.ZipFile(archive) as bundle:
            for source,expected in sources.items():
                if hashlib.sha256(bundle.read(source.removeprefix('res://'))).hexdigest()!=expected:failures.append('archive mismatch: '+source)

    def read(snap,name,channels=1,dtype='<f4'):
        item=snap['fields'][name];raw=Path(item['path']).read_bytes()
        if len(raw)!=item['bytes'] or hashlib.sha256(raw).hexdigest()!=item['sha256']:failures.append(snap['label']+'/'+name+': raw identity mismatch')
        values=np.frombuffer(raw,dtype=dtype)
        return values.reshape(256,256,channels) if channels>1 else values.reshape(256,256)

    initial=result['snapshots'][0]
    bed=read(initial,'rock').astype(float)+read(initial,'sand').astype(float)
    state=np.stack([read(initial,n).astype(float) for n in ['water','momentum_x','momentum_z','sediment']])
    original=state.copy();solver=Reference(bed,.125)
    initial_mass=state[0].sum()*.125**2;initial_s=state[3].sum()*.125**2
    x=(np.arange(256)+.5-128)*.125;mask=abs(x)<4
    wavelength=float(result['case_id'].split('_')[-1].removesuffix('m')) if result['case_id'].startswith('wave_') and 'diagonal' not in result['case_id'] else None
    for index,snap in enumerate(result['snapshots']):
        for name,item in snap['fields'].items():
            raw=Path(item['path']).read_bytes()
            if len(raw)!=item['bytes'] or hashlib.sha256(raw).hexdigest()!=item['sha256']:failures.append(snap['label']+'/'+name+': raw identity mismatch')
        if not np.array_equal(read(snap,'rock').astype(float)+read(snap,'sand').astype(float),bed):failures.append(snap['label']+': fixed bed changed')
        fields={n:read(snap,n).astype(float) for n in ['water','momentum_x','momentum_z','sediment']}
        current=np.stack(list(fields.values()))
        if not np.isfinite(current).all() or np.min(current[[0,3]])<0:failures.append(snap['label']+': invalid physical values')
        row={'label':snap['label'],'advanced_time_s':snap['advanced_time_s'],
             'minimum_h_m':float(current[0].min()),'water_mass_error_m3':float(current[0].sum()*.125**2-initial_mass),
             'sediment_mass_error_m3':float(current[3].sum()*.125**2-initial_s),
             'water_relative_error':float((current[0].sum()*.125**2-initial_mass)/initial_mass),
             'max_h_change_m':float(abs(current[0]-original[0]).max()),'max_abs_q_m2_s':float(abs(current[1:3]).max())}
        if index>0:
            decision=np.fromfile(snap['fields']['decision']['path'],dtype='<u4')
            audit=np.fromfile(snap['fields']['audit']['path'],dtype='<u4').reshape(64,8) if 'audit' in snap['fields'] else None
            if audit is not None:
                accepted=audit[audit[:,2]==1]
                dts=accepted[:,1].copy().view('<f4').astype(float)
                row.update({'accepted_substeps':int(decision[1]),'rejected_trials':int(decision[10]),'audit_accepted':len(dts),'sum_accepted_dt':float(dts.sum()),'status':int(decision[4])})
                if len(dts)!=int(decision[1]) or not np.all(np.isfinite(dts)&(dts>0)):failures.append(snap['label']+': acceptance audit mismatch')
                actual=float(decision[3:4].copy().view('<f4')[0])
                if abs(dts.sum()-actual)>2e-7:failures.append(snap['label']+': accepted time mismatch')
                clock=float(np.float32(np.float32(clock)+np.float32(actual)))
                if abs(clock-snap['advanced_time_s'])>1e-7:failures.append(snap['label']+': complete clock mismatch')
                if args.cpu:
                    for dt in dts:
                        last_first=solver.euler(state,float(dt));last_second=solver.euler(last_first.state,float(dt))
                        state=.5*(state+last_second.state);solver.limit_momentum(state)
                    errors=np.max(abs(state-current),axis=(1,2))
                    row['cpu_max_errors_h_qx_qz_s']=errors.tolist()
                    strong=result['case_id'] in ['dam_break','near_dry']
                    thresholds=np.array([2e-5,1e-4,1e-4,2e-6]) if strong else np.array([2e-6,2e-5,2e-5,2e-6])
                    if np.any(errors>thresholds):failures.append(snap['label']+': CPU/GPU field mismatch')
            flux=read(snap,'flux',4)
            if np.any((flux[:,:-1,1]>0)&(flux[:,1:,0]>0)) or np.any((flux[:-1,:,3]>0)&(flux[1:,:,2]>0)):
                failures.append(snap['label']+': both donors on a public edge')
            safety=np.fromfile(snap['fields']['safety']['path'],dtype='<u4') if 'safety' in snap['fields'] else None
            if safety is not None:row['epoch_safety_raw']=safety[:8].tolist()
        if wavelength:
            signal=current[0,mask,128] if '_z_' in result['case_id'] else current[0,128,mask]
            coefficient=2*np.mean((signal-signal.mean())*np.exp(-2j*np.pi*x[mask]/wavelength))
            row['amplitude_m']=float(abs(coefficient));row['phase_rad']=float(np.angle(coefficient))
        if result['case_id'].startswith('concentration_'):
            c=.01 if result['case_id']=='concentration_001' else .05
            wet=current[0]>=.01;row['max_concentration_error']=float(abs(current[3,wet]/current[0,wet]-c).max())
            if row['max_concentration_error']>1e-5:failures.append(snap['label']+': concentration mismatch')
        if abs(row['water_relative_error'])>1e-5:failures.append(snap['label']+': water inventory closure')
        if (abs(row['sediment_mass_error_m3'])/initial_s>1e-5 if initial_s>0 else abs(row['sediment_mass_error_m3'])>1e-9):failures.append(snap['label']+': sediment inventory closure')
        rows.append(row)
        print(snap['label'],json.dumps(row,separators=(',',':'))[:320],flush=True)
    summary={'case_id':result['case_id'],'solver_id':result['solver_id'],'rows':rows,'source_hashes':sources,
             'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
             'reference_sha256':hashlib.sha256(Path(__file__).with_name('reference.py').read_bytes()).hexdigest() if args.cpu else None,
             'scope':'Raw identity and numeric audit; individual gates remain separate'}
    if wavelength:
        a0=rows[0]['amplitude_m']
        for row in rows:row['amplitude_ratio']=row['amplitude_m']/a0
        phase_rows=[r for r in rows if r['advanced_time_s']<=1.000001 and r['amplitude_ratio']>.02]
        times=np.array([r['advanced_time_s'] for r in phase_rows]);phase=np.unwrap([r['phase_rad'] for r in phase_rows])
        speed=-np.polyfit(times,phase,1)[0]*wavelength/(2*np.pi)
        summary.update({'amplitude_ratio_final':rows[-1]['amplitude_ratio'],'phase_speed_m_s':float(speed),
                        'relative_phase_speed_error':float(abs(speed/np.sqrt(G*result.get('input',{}).get('mean_depth_m',.1))-1)),
                        'phase_window_s':[float(times[0]),float(times[-1])]})
        if result['requested_time_s']>=2-1e-6 and wavelength in (1.,2.,4.) and result['solver_id']=='muscl_mc_ssprk2_v1' and result.get('input',{}).get('mean_depth_m',.1)==.1 and result.get('input',{}).get('amplitude_m',.0001)==.0001:
            threshold={1.:.25,2.:.85,4.:.95}[wavelength]
            if rows[-1]['amplitude_ratio']<threshold:failures.append('two-second amplitude gate')
            if summary['relative_phase_speed_error']>(.05 if wavelength==1 else .02):failures.append('phase-speed gate')
    if result['outcome']!='pass' or result['source_drift']:failures.append('probe failure/source drift')
    summary.update({'outcome':'fail' if failures else 'pass','failures':failures})
    destination.write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k not in ['rows','source_hashes']},indent=2));raise SystemExit(bool(failures))


if __name__=='__main__':main()
