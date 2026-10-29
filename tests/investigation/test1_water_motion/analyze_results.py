"""Verify actual GPU fields and create static review artifacts from measured samples."""
import json,hashlib,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tests/investigation/brush_hit_competitor/runtime_collider/plot_deps'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

BASE=ROOT/'test_output/test1_water_motion';OUT=BASE/'review_v1';OUT.mkdir(exist_ok=True)
floor=np.fromfile(ROOT/'assets/test1_water_motion/capture_state.rgba32f',dtype='<f4').reshape(256,512,4)[:,:,3]
summary={'runs':{},'scope':'Water proxy is sum(max(amount-0.05,0))*captured_cell_size^2, in scene units cubed; no original real-time or metre calibration.'}
for run in ['gpu_release_v3','gpu_hold_v2','gpu_repeat_v1']:
 d=json.loads((BASE/run/'manifest.json').read_text());assert d['operation_complete'] and d['sources_unchanged']
 rows=[];violations=[]
 for sample in d['samples']:
  path=Path(sample['raw_path']);raw=path.read_bytes();assert len(raw)==512*256*16 and hashlib.sha256(raw).hexdigest()==sample['sha256']
  a=np.frombuffer(raw,dtype='<f4').reshape(256,512,4);h=np.maximum(a[:,:,2]-.05,0);wet=h>.005;shore=wet&(floor>1.05)&(floor<2)
  row={'t':sample['adaptation_time'],'tick':sample['tick'],'override':sample['override'],'water_proxy':float(h.sum()*.05859375**2),
   'shore_water_proxy':float(h[floor>1.05].sum()*.05859375**2),'shore_wet_cells':int(shore.sum()),
   'onshore_cells':int((shore&(a[:,:,0]<-.05)).sum()),'return_cells':int((shore&(a[:,:,0]>.05)).sum()),
   'shore_mean_vx':float(a[:,:,0][shore].mean()) if shore.any() else 0,
   'wet_mean_speed':float(np.linalg.norm(a[:,:,:2],axis=-1)[wet].mean()),
   'nonfinite':int((~np.isfinite(a)).sum()),'negative_amount':int((a[:,:,2]<0).sum()),
   'floor_identical':np.array_equal(a[:,:,3],floor)}
  if row['nonfinite'] or row['negative_amount'] or not row['floor_identical']:violations.append(sample['tick'])
  rows.append(row)
 summary['runs'][run]={'rows':rows,'violations':violations,'controls':d['controls'],'sources':d['source_index'],
  'adapter':d['adapter'],'engine':d['engine'],'log_errors':[line for line in (BASE/(run+'.log')).read_text(encoding='utf-8',errors='replace').splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:','SHADER ERROR:'))]}
 assert not violations and not summary['runs'][run]['log_errors'] and all(d['controls'].values())
release=summary['runs']['gpu_release_v3']['rows'];peak=max(release,key=lambda r:r['shore_water_proxy']);end=release[-1]
summary['release']={'peak_t':peak['t'],'peak_proxy':peak['shore_water_proxy'],'first_mean_flow_reverse_t':next(r['t'] for r in release if r['t']>6 and r['shore_mean_vx']>0),
 'at20':next(r for r in release if r['t']==20),'at40':end,'loss_at20_fraction':1-next(r for r in release if r['t']==20)['shore_water_proxy']/peak['shore_water_proxy'],
 'loss_at40_fraction':1-end['shore_water_proxy']/peak['shore_water_proxy']}
stage=json.loads((BASE/'analysis_v1/stage_validation.json').read_text());summary['one_step_stage_metrics']=stage
first=np.load(BASE/'analysis_v1/e1490/decoded.npy');repeat=np.load(BASE/'analysis_v1/e1490_repeat13/decoded.npy');delta=np.abs(first-repeat)
summary['same_event_replay_field_drift']={'max':delta.max(axis=(0,1)).tolist(),'p99':np.percentile(delta,99,axis=(0,1)).tolist()}
for i,name in enumerate(['release','hold','repeat']):
 r=summary['runs'][['gpu_release_v3','gpu_hold_v2','gpu_repeat_v1'][i]]['rows']
 if name=='repeat':
  summary['repeat_extrema']=[{'window':[lo,hi],'min':min((v for v in r if lo<=v['t']<=hi),key=lambda v:v['shore_water_proxy']),
   'max':max((v for v in r if lo<=v['t']<=hi),key=lambda v:v['shore_water_proxy'])} for lo,hi in [(0,16),(16,32)]]

fig,ax=plt.subplots(2,1,figsize=(10,6),sharex=True,layout='constrained')
for name,label,color in [('gpu_release_v3','Release customWave','#1f77b4'),('gpu_hold_v2','Hold captured customWave','#e29522'),('gpu_repeat_v1','Periodic customWave (adaptation)','#598c48')]:
 r=summary['runs'][name]['rows'];t=[x['t'] for x in r]
 ax[0].plot(t,[x['shore_water_proxy'] for x in r],label=label,color=color)
 ax[1].plot(t,[x['shore_mean_vx'] for x in r],color=color)
ax[0].set(ylabel='Water proxy above bed 1.05\n(scene units cubed)');ax[0].legend(fontsize=9)
ax[1].axhline(0,color='#777',lw=.8);ax[1].set(ylabel='Mean shore X velocity\nnegative: inland; positive: sea',xlabel='Experimental time = completed tick / 40 (not original wall time)')
for a in ax:a.grid(alpha=.25)
fig.savefig(OUT/'measured_motion.png',dpi=160);plt.close(fig)

fig,axes=plt.subplots(1,2,figsize=(12,4),layout='constrained')
for ax,tick,label in zip(axes,[240,560],['6 s: incoming flow','14 s: return flow']):
 a=np.fromfile(BASE/'gpu_release_v3'/('state_%04d.rgba32f'%tick),dtype='<f4').reshape(256,512,4);h=np.maximum(a[:,:,2]-.05,0)
 ax.imshow(np.ma.masked_where(h<.005,h),origin='lower',extent=[-15,15,-7.5,7.5],cmap='Blues',vmin=0,vmax=1)
 x=np.linspace(-15+.05859375/2,15-.05859375/2,512);z=np.linspace(-7.5+.05859375/2,7.5-.05859375/2,256)
 ax.contour(x,z,floor,[1.05,1.5,2,4],colors='#888',linewidths=.5)
 zz,xx=np.mgrid[8:256:16,8:512:16];wet=h[zz,xx]>.005;vx=a[zz,xx,0];vz=a[zz,xx,1]
 ax.quiver(x[xx][wet],z[zz][wet],vx[wet],vz[wet],vx[wet],cmap='coolwarm',clim=(-2,2),scale=45,width=.003)
 ax.set(title=label,xlabel='Original scene X (sea to the right)',ylabel='Original scene Z',xlim=(-15,15),ylim=(-7.5,7.5),aspect='equal')
fig.savefig(OUT/'incoming_and_return_vectors.png',dpi=160);plt.close(fig)

font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
canvas=Image.new('RGB',(1920,400),'#e8edf1');draw=ImageDraw.Draw(canvas)
for i,(tick,label) in enumerate([(240,'6秒：水冲上沙滩'),(560,'14秒：水向海侧回流'),(1600,'40秒：岸上水退去')]):
 im=Image.open(BASE/'gpu_release_v3'/('frame_%04d.png'%tick)).convert('RGB').resize((640,360))
 canvas.paste(im,(i*640,40));draw.text((i*640+16,4),label,font=font,fill='#152535')
canvas.save(OUT/'runup_backwash_review.png')
(OUT/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps({'release':summary['release'],'repeat_extrema':summary['repeat_extrema'],'all_checks_pass':True},indent=2))
