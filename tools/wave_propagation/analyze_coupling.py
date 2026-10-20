"""Audit actual GPU coupling fields; replay accepted dt without fitting rates."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import numpy as np
from coupled_reference import CoupledReference, EROSION_RATE, DEPOSITION_RATE


def analyze(root, source_root):
    root=Path(root).resolve();source_root=Path(source_root).resolve()
    destination=root/'analysis.json'
    if destination.exists():raise FileExistsError(destination)
    result=json.loads((root/'result.json').read_text(encoding='utf-8'))
    failures=[];rows=[];sources=result['configuration']['sources']
    def require(condition,reason):
        if not condition:failures.append(reason)
    archive_path=root/'consumed_sources.zip'
    with zipfile.ZipFile(archive_path,'r' if archive_path.exists() else 'x',zipfile.ZIP_DEFLATED) as archive:
        for name,expected in sources.items():
            raw=(source_root/name.removeprefix('res://')).read_bytes()
            require(hashlib.sha256(raw).hexdigest()==expected,'source identity: '+name)
            if archive.mode=='r':require(archive.read(name.removeprefix('res://'))==raw,'archive identity: '+name)
            else:archive.writestr(name.removeprefix('res://'),raw)
    def read(snap,name,channels=1,dtype='<f4',shape=(256,256)):
        raw=Path(snap['fields'][name]['path']).read_bytes()
        item=snap['fields'][name]
        require(len(raw)==item['bytes'] and hashlib.sha256(raw).hexdigest()==item['sha256'],snap['label']+'/'+name+' raw identity')
        return np.frombuffer(raw,dtype=dtype).reshape((*shape,channels) if channels>1 else shape)
    def physical(snap):return np.stack([read(snap,n).astype(float) for n in ['water','momentum_x','momentum_z','sediment']])
    snaps=result['snapshots'];initial=snaps[0];case=result['case_id'];enabled=result['coupling_enabled'];mc=result['transport_in_rk']
    base=next((s for s in snaps if s['label']=='edited'),initial)
    start=physical(base);sand0=read(base,'sand').astype(float);obstacle=read(initial,'obstacle',dtype='u1')>=128;free=~obstacle
    model=CoupledReference(read(base,'rock'),sand0,read(base,'wetness',dtype='<f2'),read(base,'compaction',dtype='<f2'),read(base,'mold_support',2),obstacle,enabled=enabled,boundary=case=='boundary')
    state=start.copy();area=.125**2;water0=float(start[0,free].sum()*area);solid0=float((sand0+start[3]).sum()*area)
    c0=read(base,'control',dtype='<f4',shape=(-1,));previous_comp=read(base,'compaction',dtype='<f2').astype(float)
    clock=0.;all_dts=[];last_prior=None;last_dt=None
    for snap in snaps:
        for name,item in snap['fields'].items():
            raw=Path(item['path']).read_bytes()
            require(hashlib.sha256(raw).hexdigest()==item['sha256'] and len(raw)==item['bytes'],snap['label']+'/'+name+' identity')
        if snap is initial and base is not initial:continue
        label=snap['label'];current=physical(snap);sand=read(snap,'sand').astype(float)
        wet=read(snap,'wetness',dtype='<f2').astype(float);compact=read(snap,'compaction',dtype='<f2').astype(float);support=read(snap,'mold_support',2)
        require(np.isfinite(current).all() and np.isfinite(sand).all() and current[[0,3]].min()>=0 and sand.min()>=0,label+' physical validity')
        require(np.isfinite(wet).all() and np.isfinite(compact).all() and wet.min()>=0 and wet.max()<=1 and compact.min()>=0 and compact.max()<=1,label+' material bounds')
        require(np.all(compact>=previous_comp),label+' compaction monotonic');previous_comp=compact
        require(np.isfinite(support).all() and np.all((support[:,:,0]>=0)&(support[:,:,0]<=sand)),label+' support bounds')
        tagged=support[:,:,0]>0
        require(np.array_equal(support[:,:,1][tagged],sand[tagged].astype(np.float32)) and np.all(support[~tagged].view('<u4')==0),label+' support final bed reference')
        if enabled:
            for name in ['wetness','compaction','mold_support','sand']:
                require(snap['fields'][name]['sha256']==snap['fields'][name+'_spare']['sha256'],label+'/'+name+' spare coherence')
        if mc:require(snap['fields']['sediment']['sha256']==snap['fields']['sediment_spare']['sha256'],label+' sediment spare coherence')
        control=read(snap,'control',dtype='<f4',shape=(-1,))
        water_source=float(control[22]-c0[22]);water_sink=float(control[23]-c0[23])
        water_error=float(current[0,free].sum()*area-water0-water_source+water_sink)
        solid_error=float((sand+current[3]).sum()*area-solid0)
        row={'label':label,'time_s':snap['advanced_time_s'],'water_error_m3':water_error,'solid_error_m3':solid_error,'water_source_m3':water_source,'water_sink_m3':water_sink,
             'water_relative_error':abs(water_error)/water0,'solid_relative_error':abs(solid_error)/solid0,'minimum_h_m':float(current[0].min()),'minimum_s_m':float(current[3].min())}
        require(abs(water_error)<=max(water0*1e-5,1e-8),label+' water closure')
        require(abs(solid_error)<=max(solid0*1e-5,1e-9),label+' solid closure')
        if not enabled:
            sediment0=float(start[3].sum()*area);err=float((current[3]-start[3]).sum()*area)
            row['sediment_relative_error']=abs(err)/sediment0
            require(abs(err)<=sediment0*1e-5,label+' transport sediment closure')
            require(np.array_equal(sand,sand0),label+' disabled exchange bed')
        if label.startswith('tick_'):
            decision=read(snap,'decision',dtype='<u4',shape=(-1,))
            require(decision[4]!=2,label+' numerical status')
            if mc:
                audit=read(snap,'audit',dtype='<u4',shape=(64,8));dts=audit[audit[:,2]==1,1].copy().view('<f4').astype(float)
                actual=float(decision[3:4].copy().view('<f4')[0])
                require(len(dts)==int(decision[1]) and np.all(dts>0) and abs(dts.sum()-actual)<2e-7,label+' accepted dt audit')
                clock=float(np.float32(np.float32(clock)+np.float32(actual)));require(abs(clock-snap['advanced_time_s'])<1e-7,label+' actual clock')
                row.update(accepted_substeps=len(dts),rejected_trials=int(decision[10]),accepted_dt_s=dts.tolist())
                all_dts.extend(dts.tolist())
                if case!='molded_edit':
                    state=model.apply_boundary(state)
                    for dt in dts:
                        last_prior=state.copy();last_dt=float(dt);state,transported,_=model.step(state,float(dt))
                    errors=np.max(abs(state-current),axis=(1,2));sand_error=float(abs(model.sand-sand).max())
                    row['cpu_max_errors_h_qx_qz_s']=errors.tolist();row['cpu_max_sand_error_m']=sand_error
                    limits=np.array([2e-5,1e-4,1e-4,2e-6]) if case=='near_dry' else np.array([2e-6,2e-5,2e-5,2e-6])
                    require(np.all(errors<=limits) and sand_error<=2e-6,label+' CPU transport/exchange mismatch')
                    if enabled and case!='near_dry':
                        we=float(abs(wet-model.wetness).max());ce=float(abs(compact-model.compaction).max())
                        row.update(wetness_error=we,compaction_error=ce,wetness_bound=float(model.wetness_bound),compaction_bound=float(model.compaction_bound))
                        require(we<=model.wetness_bound and ce<=model.compaction_bound,label+' once material recurrence')
                    if case=='support':require(abs(model.support-support).max()<=2e-6,label+' support erosion remap')
                flux=read(snap,'flux',4)
                require(not np.any((flux[:,:-1,1]>0)&(flux[:,1:,0]>0)) and not np.any((flux[:-1,:,3]>0)&(flux[1:,:,2]>0)),label+' unique net water donor')
                if enabled and 'exchange_sediment' in snap['fields']:
                    require(np.array_equal(read(snap,'exchange_sediment'),current[3].astype(np.float32)),label+' final exchange sediment copy')
            if enabled:
                dirty=read(snap,'coupled_dirty',dtype='<u4',shape=(8,8));changed=abs(sand-sand0).reshape(8,32,8,32).max(axis=(1,3))>0
                require(np.all(dirty[changed]>0),label+' dirty covers changed bed')
        if case.startswith('constant_'):
            concentration=.01 if case=='constant_001_off' else .05;mask=current[0]>=.01
            error=float(abs(current[3,mask]/current[0,mask]-concentration).max());row['concentration_error']=error
            require(error<=1e-5,label+' constant concentration')
        if case in ('erosion','deposition') and label.startswith('tick_'):
            center=np.s_[120:136,120:136];t=snap['advanced_time_s']
            expected=.0003*(-np.expm1(-EROSION_RATE*t)) if case=='erosion' else .001*np.exp(-DEPOSITION_RATE*t)
            error=float(abs(current[3][center]-expected).max());row['once_exchange_scalar_error_m']=error
            require(error<=1e-8,label+' once physical exchange')
        rows.append(row)
    if case=='reversal':
        snap=snaps[-1];u1=read(snap,'u1',4).transpose(2,0,1).astype(float);u2=read(snap,'u2',4).transpose(2,0,1).astype(float)
        require(len(all_dts)==1,'reversal fixture must have one accepted step')
        exact=[];shortcut=[];reverse_count=0
        for axis,suffix in [(1,'x'),(0,'z')]:
            raw0=read(snap,'edge0_'+suffix,4)[:,:,0].astype(float);raw1=read(snap,'edge1_'+suffix,4)[:,:,0].astype(float)
            drain0=read(snap,'drain0').astype(float);drain1=read(snap,'drain1').astype(float)
            f0=raw0*np.where(raw0>=0,drain0,np.roll(drain0,-1,axis));f1=raw1*np.where(raw1>=0,drain1,np.roll(drain1,-1,axis))
            c0s=np.divide(start[3],start[0],out=np.zeros_like(start[0]),where=start[0]>0);c1s=np.divide(u1[3],u1[0],out=np.zeros_like(u1[0]),where=u1[0]>0)
            exact.append(.5*(f0*np.where(f0>=0,c0s,np.roll(c0s,-1,axis))+f1*np.where(f1>=0,c1s,np.roll(c1s,-1,axis))))
            net=.5*(f0+f1);shortcut.append(net*np.where(net>=0,c0s,np.roll(c0s,-1,axis)))
            reverse_count+=int(((f0*f1)<0).sum())
        true=start[3].copy();wrong=true.copy()
        for axis,f,g in zip((1,0),exact,shortcut):
            true+=all_dts[0]/.125*(np.roll(f,1,axis)-f);wrong+=all_dts[0]/.125*(np.roll(g,1,axis)-g)
        final=physical(snap);error=float(abs(true-final[3]).max());wrong_error=float(abs(wrong-final[3]).max())
        require(reverse_count>0 and error<=2e-6 and wrong_error>2e-6,'reversal actual stage donor discriminator')
        reversal={'reversed_edges':reverse_count,'actual_stage_sediment_error_m':error,'net_shortcut_error_m':wrong_error}
    else:reversal=None
    require(result['outcome']=='pass' and not result['source_drift'] and all(c['pass'] for c in result['checks']),'native probe checks')
    report={'schema':1,'suite':'coupling','case_id':case,'solver_id':result['solver_id'],'outcome':'fail' if failures else 'pass','failures':failures,'rows':rows,'reversal':reversal,
            'source_hashes':sources,'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'reference_sha256':hashlib.sha256(Path(__file__).with_name('coupled_reference.py').read_bytes()).hexdigest(),
            'scope':'GPU raw identity, accepted-time 2D replay, stock/material/support; no long-stability or performance acceptance'}
    destination.write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in report.items() if k not in ('rows','source_hashes')},indent=2),flush=True)
    return not failures


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('--source-root',type=Path,required=True);a=p.parse_args()
    raise SystemExit(not analyze(a.directory,a.source_root))
