"""Equation reconstruction from captured DXBC; immutable phase inputs are an adaptation."""
import json
from pathlib import Path
import numpy as np
from analyze_capture import decode, CAP, OUT

DX=np.float32(.05859375); DT=np.float32(.00732421875); G=np.float32(16)
OFFSET=np.float32(.05); MAX24=np.float32(16777215)
SCALE_H=np.float32(10.1/16777215); SCALE_V=np.float32(8/16777215)
Z,X=np.mgrid[0:256,0:512]

def quant_h(h):return np.floor(np.clip(h*np.float32(1/10.1),0,1)*MAX24+np.float32(.5))*SCALE_H
def quant_v(v):return np.floor(np.clip((v+np.float32(4))*np.float32(.125),0,1)*MAX24+np.float32(.5))*SCALE_V-np.float32(4)
def neighbor(a,dx=0,dz=0):return a[np.clip(Z+dz,0,255),np.clip(X+dx,0,511)]
def bilinear(a,x,z):
    lo_x=np.floor(x).astype(int);lo_z=np.floor(z).astype(int);fx=(x-lo_x).astype(np.float32);fz=(z-lo_z).astype(np.float32)
    if a.ndim==3:fx=fx[...,None];fz=fz[...,None]
    aa=a[np.clip(lo_z,0,a.shape[0]-1),np.clip(lo_x,0,a.shape[1]-1)]
    ab=a[np.clip(lo_z,0,a.shape[0]-1),np.clip(lo_x+1,0,a.shape[1]-1)]
    ba=a[np.clip(lo_z+1,0,a.shape[0]-1),np.clip(lo_x,0,a.shape[1]-1)]
    bb=a[np.clip(lo_z+1,0,a.shape[0]-1),np.clip(lo_x+1,0,a.shape[1]-1)]
    return (aa+(ab-aa)*fx)+((ba+(bb-ba)*fx)-(aa+(ab-aa)*fx))*fz

def velocity(a,drag=0.0):
    o=a.copy();h=np.maximum(a[:,:,2]-OFFSET,0);eta=a[:,:,3]+h
    r=neighbor(a,dx=1);b=neighbor(a,dz=1)
    v=a[:,:,:2]-G*DT*np.stack([(neighbor(eta,dx=1)-eta)/DX,(neighbor(eta,dz=1)-eta)/DX],axis=-1)
    v*=np.float32(1)-DT*np.float32(drag)
    u=(X+np.float32(.5))/np.float32(512);w=(Z+np.float32(.5))/np.float32(256)
    def ss(t):t=np.clip(t,0,1);return t*t*(3-2*t)
    edge=1-ss(u*20)*ss(w*20)*ss((1-u)*20)*ss((1-w)*20)
    v*= (1-DT*edge)[...,None]
    vr=r[:,:,:2].copy();vb=b[:,:,:2].copy();vr[:,-1]=0;vb[-1]=0
    v=(neighbor(a,dx=-1)[:,:,:2]+neighbor(a,dz=-1)[:,:,:2]+vr+vb+1000*v)/1004
    hr=np.maximum(r[:,:,2]-OFFSET,0);hb=np.maximum(b[:,:,2]-OFFSET,0);eps=DX*np.float32(.0001)
    stop_x=((eta<r[:,:,3])&(hr<=eps))|((r[:,:,3]+hr<a[:,:,3])&(h<=eps))
    stop_z=((eta<b[:,:,3])&(hb<=eps))|((b[:,:,3]+hb<a[:,:,3])&(h<=eps))
    v[:,:,0][stop_x]=0;v[:,:,1][stop_z]=0
    v*=np.minimum(1,2/np.maximum(np.linalg.norm(v,axis=-1),1e-20))[...,None]
    o[:,:,:2]=quant_v(v);return o

def height(a):
    o=a.copy();h=np.maximum(a[:,:,2]-OFFSET,0)
    hl=neighbor(h,dx=-1);hr=neighbor(h,dx=1);ht=neighbor(h,dz=-1);hb=neighbor(h,dz=1)
    vl=neighbor(a,dx=-1)[:,:,0].copy();vt=neighbor(a,dz=-1)[:,:,1].copy();vl[:,0]=0;vt[0]=0
    vx=a[:,:,0];vz=a[:,:,1]
    correction=np.maximum((hl+hr+ht+hb)*np.float32(.25)-2*DX/(DT*G),0)
    fl=vl*(np.where(vl>=0,hl,h)-correction)
    fr=vx*(np.where(vx<=0,hr,h)-correction)
    ft=vt*(np.where(vt>=0,ht,h)-correction)
    fb=vz*(np.where(vz<=0,hb,h)-correction)
    o[:,:,2]=quant_h(np.clip(a[:,:,2]-DT*((fr-fl)+(fb-ft))/DX,0,10));return o

def advection(a):
    o=a.copy();v=a[:,:,:2]
    o[:,:,:2]=quant_v(bilinear(v,X-v[:,:,0]*DT*np.float32(.2)/DX,Z-v[:,:,1]*DT*np.float32(.2)/DX));return o

def forcing(a,flags,air,obstacle,t=284.71783447265625,override=1.6163164377212524):
    o=a.copy();h=np.maximum(a[:,:,2]-OFFSET,0);floor=a[:,:,3];eta=floor+h
    hraw=a[:,:,2]-np.exp(-air*.5)*.0001*np.float32(.025)
    mask=(eta>=obstacle)&(obstacle-eta<.1)&(floor<obstacle)
    hraw+=mask*np.sin(np.float32(t)*8+(Z+.5)/256*np.float32(.0378))*np.float32(.025*.15)
    alpha=flags[:,:,0]/15
    target=np.maximum(np.maximum(np.sin(np.float32(t))*.049701884388923645,-.5)+1-floor,.05)
    hraw+=alpha*(target-hraw)
    if override>0:hraw+=alpha*(1+override-floor-hraw)
    hraw+=(flags[:,:,1]>1.05)*flags[:,:,1]/15*np.float32(.025)
    o[:,:,2]=quant_h(np.clip(hraw,0,10));return o

def load_inputs():
    m=json.loads((CAP/'manifest.json').read_text());row=m['events'][10]
    w=next(b for b in row['bindings'] if b['resource']=='ResourceId::139573')
    packed=np.fromfile(w['raw']['path'],dtype='<u4').reshape(256,512,4)
    flags=np.stack([packed[:,:,3]>>28,(packed[:,:,3]>>24)&15],axis=-1).astype(np.float32)
    obs=next(b for b in row['bindings'] if b['resource']=='ResourceId::139724')
    obstacle=np.fromfile(obs['raw']['path'],dtype='<f2').reshape(256,512,2)[:,:,1].astype(np.float32)
    ar=next(b for b in row['bindings'] if b['resource']=='ResourceId::139590')
    ar=np.fromfile(ar['raw']['path'],dtype='<u4').reshape(16,32,4)
    low=(((ar[:,:,1]>>12)|(ar[:,:,2]<<20))&np.uint32(0x3fffff)).astype(np.float32)*np.float32(5/4194303)
    air=bilinear(low,(X+.5)/512*32-.5,(Z+.5)/256*16-.5)
    return flags,air,obstacle

def stage_check():
    flags,air,obs=load_inputs();results=[]
    pairs=[(1484,1490,velocity),(1490,1495,height),(1495,1500,advection),(1500,1505,velocity),(1505,1510,height),(1510,1515,advection),(1515,1520,velocity),(1520,1525,height),(1525,1530,advection),
           (1530,1537,lambda a:forcing(a,flags,air,obs))]
    for before,after,fn in pairs:
        a=np.load(OUT/('e%d'%before)/'decoded.npy').astype(np.float32);b=np.load(OUT/('e%d'%after)/'decoded.npy').astype(np.float32)
        p=fn(a);d=np.abs(p-b)
        metrics={name:{'mae':float(d[:,:,i].mean()),'p99':float(np.percentile(d[:,:,i],99)),'max':float(d[:,:,i].max())} for i,name in enumerate(['vx','vz','amount','floor'])}
        results.append({'before':before,'after':after,'metrics':metrics})
    (OUT/'stage_validation.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))

if __name__=='__main__':stage_check()
