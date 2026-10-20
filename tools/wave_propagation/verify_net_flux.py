"""Check last accepted RK water step directly from GPU private/public fields."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np


def main():
    ap=argparse.ArgumentParser();ap.add_argument('suite',type=Path);ap.add_argument('output',type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    suite=json.loads((args.suite/'result.json').read_text());rows=[]
    for entry in suite['rows']:
        case=Path(entry['analysis']).parent;result=json.loads((case/'result.json').read_text(encoding='utf-8'));snap=result['snapshots'][-1]
        def data(name,channels=1):
            item=snap['fields'][name];raw=Path(item['path']).read_bytes()
            assert len(raw)==item['bytes'] and hashlib.sha256(raw).hexdigest()==item['sha256']
            return np.frombuffer(raw,dtype='<f4').astype(float).reshape((256,256,channels) if channels>1 else (256,256))
        audit=np.fromfile(snap['fields']['audit']['path'],dtype='<u4').reshape(64,8)
        accepted=audit[audit[:,2]==1];assert len(accepted)>0
        dt=float(accepted[-1,1:2].copy().view('<f4')[0]);h=data('water');u2=data('u2',4);flux=data('flux',4)
        # U2 is retained from the last accepted stage even after inactive trials.
        # Recover U0 from the actual RK convex combination; no CPU solution used.
        h0=2*h-u2[:,:,0]
        incoming=np.zeros_like(h)
        incoming[:,1:]+=flux[:,:-1,1];incoming[:,:-1]+=flux[:,1:,0]
        incoming[1:,:]+=flux[:-1,:,3];incoming[:-1,:]+=flux[1:,:,2]
        reconstructed=h0+dt/.125**2*(incoming-flux.sum(axis=2))
        error=float(abs(reconstructed-h).max())
        coherent=int(accepted[-1,0])==int(audit[audit[:,1]!=0][-1,0])
        direct_error=None;direct_bound_pass=None
        if coherent:
            theta=[data('drain0'),data('drain1')];net=[];bounds=[]
            for axis,name in [(1,'x'),(0,'z')]:
                scaled=[]
                for stage in (0,1):
                    f=data(f'edge{stage}_{name}',4)[:,:,0]
                    scale=np.where(f>=0,theta[stage],np.roll(theta[stage],-1,axis=axis));scaled.append(f*scale)
                net.append(.5*(scaled[0]+scaled[1])*.125)
                bounds.append(8*np.finfo(np.float32).eps*(abs(scaled[0])+abs(scaled[1]))*.125)
            expected=np.zeros_like(flux);bound=np.zeros_like(flux)
            expected[:,1:,0]=np.maximum(-net[0][:,:-1],0);expected[:,:-1,1]=np.maximum(net[0][:,:-1],0)
            expected[1:,:,2]=np.maximum(-net[1][:-1,:],0);expected[:-1,:,3]=np.maximum(net[1][:-1,:],0)
            bound[:,1:,0]=bounds[0][:,:-1];bound[:,:-1,1]=bounds[0][:,:-1]
            bound[1:,:,2]=bounds[1][:-1,:];bound[:-1,:,3]=bounds[1][:-1,:]
            direct_error=float(abs(expected-flux).max());direct_bound_pass=bool(np.all(abs(expected-flux)<=bound))
        okay=error<=2e-6 and direct_bound_pass is not False
        rows.append({'case_id':entry['id'],'last_accepted_dt_s':dt,'water_depth_reconstruction_max_error_m':error,
                     'stage_fields_correspond_to_last_accepted':coherent,'direct_stage_net_flux_max_error_m3_s':direct_error,
                     'direct_stage_net_flux_within_roundoff_bound':direct_bound_pass,'pass':okay})
    result={'outcome':'pass' if all(r['pass'] for r in rows) else 'fail','rows':rows,
            'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'scope':'Last accepted step water reconstruction and signed stage-net ABI; not tick-total flux'}
    (out/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');(out/Path(__file__).name).write_bytes(Path(__file__).read_bytes())
    print(json.dumps(result,indent=2));raise SystemExit(result['outcome']!='pass')


if __name__=='__main__':main()
