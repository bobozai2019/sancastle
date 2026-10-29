"""Independent raw-stage donor and public-net ABI audit on one accepted step."""
import hashlib
import json
from pathlib import Path
import sys
import numpy as np


def main(directory):
    root=Path(directory).resolve();out=root/'stage_transport_analysis.json'
    if out.exists():raise FileExistsError(out)
    r=json.loads((root/'result.json').read_text(encoding='utf-8'));first,last=r['snapshots'][0],r['snapshots'][-1];fail=[]
    def check(ok,reason):
        if not ok:fail.append(reason)
    def read(snap,name,channels=1):
        item=snap['fields'][name];raw=Path(item['path']).read_bytes()
        check(hashlib.sha256(raw).hexdigest()==item['sha256'] and len(raw)==item['bytes'],name+' identity')
        return np.frombuffer(raw,dtype='<f4').reshape((256,256,channels) if channels>1 else (256,256)).astype(float)
    audit=np.fromfile(last['fields']['audit']['path'],dtype='<u4').reshape(64,8);accepted=audit[audit[:,2]==1]
    check(len(accepted)==1 and len(r['snapshots'])==2,'requires one physical step')
    dt=float(accepted[0,1:2].copy().view('<f4')[0]);dx=.125
    start=np.stack([read(first,n) for n in ['water','momentum_x','momentum_z','sediment']]);u1=read(last,'u1',4).transpose(2,0,1);u2=read(last,'u2',4).transpose(2,0,1)
    states=[start,u1];outputs=[u1,u2];fluxes=[[],[]];sedfluxes=[[],[]];rows=[];reversed_edges=0
    for phase in (0,1):
        state=states[phase];expected_h=state[0].copy();expected_s=state[3].copy();drain=read(last,'drain'+str(phase));concentration=np.divide(state[3],state[0],out=np.zeros_like(state[0]),where=state[0]>0)
        for axis,suffix in [(1,'x'),(0,'z')]:
            raw=read(last,'edge%d_%s'%(phase,suffix),4)[:,:,0]
            f=raw*np.where(raw>=0,drain,np.roll(drain,-1,axis));sf=f*np.where(raw>=0,concentration,np.roll(concentration,-1,axis))
            fluxes[phase].append(f);sedfluxes[phase].append(sf)
            expected_h+=dt/dx*(np.roll(f,1,axis)-f);expected_s+=dt/dx*(np.roll(sf,1,axis)-sf)
        h_error=float(abs(expected_h-outputs[phase][0]).max());s_error=float(abs(expected_s-outputs[phase][3]).max())
        rows.append({'phase':phase,'water_error_m':h_error,'sediment_error_m':s_error});check(h_error<=2e-6 and s_error<=2e-6,'stage donor reconstruction '+str(phase))
    true_h=start[0].copy();true_s=start[3].copy();wrong_s=start[3].copy();net=[]
    c=np.divide(start[3],start[0],out=np.zeros_like(start[0]),where=start[0]>0);reverse_flux_difference=0.;reverse_flux_bound=0.
    for i,axis in enumerate((1,0)):
        a,b=fluxes[0][i],fluxes[1][i];f=.5*(a+b);sf=.5*(sedfluxes[0][i]+sedfluxes[1][i]);bad=f*np.where(f>=0,c,np.roll(c,-1,axis))
        reversed_mask=a*b<0
        if reversed_mask.any():
            reverse_flux_difference=max(reverse_flux_difference,float(abs(sf-bad)[reversed_mask].max()))
            reverse_flux_bound=max(reverse_flux_bound,float(8*np.finfo(np.float32).eps*abs(sf[reversed_mask]).max()))
        net.append(f);reversed_edges+=int(reversed_mask.sum());true_h+=dt/dx*(np.roll(f,1,axis)-f);true_s+=dt/dx*(np.roll(sf,1,axis)-sf);wrong_s+=dt/dx*(np.roll(bad,1,axis)-bad)
    final_h=read(last,'water');final_s=read(last,'sediment');public=read(last,'flux',4)
    channels=np.stack((np.maximum(-np.roll(net[0],1,1),0),np.maximum(net[0],0),np.maximum(-np.roll(net[1],1,0),0),np.maximum(net[1],0)),axis=-1)*dx
    channels[:,0,0]=0;channels[0,:,2]=0
    abi_error=float(abs(channels-public).max());abi_bound=float(8*np.finfo(np.float32).eps*float(abs(channels).max()))
    water_error=float(abs(true_h-final_h).max());sediment_error=float(abs(true_s-final_s).max());wrong_error=float(abs(wrong_s-final_s).max())
    check(reversed_edges>0,'fixture has reversed edges');check(water_error<=2e-6 and sediment_error<=2e-6,'weighted RK conservation');check(abi_error<=abi_bound,'public net water ABI');check(wrong_error>2e-6,'net-only shortcut must be distinguishable');check(reverse_flux_difference>reverse_flux_bound,'reversed-edge sediment discriminator')
    report={'outcome':'fail' if fail else 'pass','failures':fail,'accepted_dt_s':dt,'stage_rows':rows,'reversed_edges':reversed_edges,'reversed_edge_sediment_flux_difference_m2_s':reverse_flux_difference,'reversed_edge_roundoff_bound_m2_s':reverse_flux_bound,'final_water_error_m':water_error,'final_sediment_error_m':sediment_error,'wrong_net_shortcut_error_m':wrong_error,'public_net_max_error_m3_s':abi_error,'public_net_bound_m3_s':abi_bound,'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    out.write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report,indent=2));return not fail


if __name__=='__main__':raise SystemExit(not main(sys.argv[1]))
