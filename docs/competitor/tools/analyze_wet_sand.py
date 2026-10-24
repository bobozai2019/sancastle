"""Verify selected exports and reconstruct the captured wet-color transfer."""
import ctypes, hashlib, json, struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'docs/competitor/evidence/wet_sand_20261024'
PKG=OUT/'package';RDC=OUT/'rdc'
def ident(p):return dict(path=p.as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
def floatbits(bits):return struct.unpack('<f',struct.pack('<I',bits))[0]
def hex_disassemble(raw):
 dll=ctypes.WinDLL('d3dcompiler_47.dll');fn=dll.D3DDisassemble
 fn.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];fn.restype=ctypes.c_long
 src=ctypes.create_string_buffer(raw);blob=ctypes.c_void_p();assert fn(src,len(raw),0x80|0x20,None,ctypes.byref(blob))>=0
 vt=ctypes.cast(blob,ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
 ptr=ctypes.WINFUNCTYPE(ctypes.c_void_p,ctypes.c_void_p)(vt[3]);size=ctypes.WINFUNCTYPE(ctypes.c_size_t,ctypes.c_void_p)(vt[4]);release=ctypes.WINFUNCTYPE(ctypes.c_ulong,ctypes.c_void_p)(vt[2])
 try:return ctypes.string_at(ptr(blob),size(blob)).rstrip(b'\0').decode()
 finally:release(blob)
pm=json.loads((PKG/'manifest.json').read_text());rm=json.loads((RDC/'manifest.json').read_text())
assert pm['pass'] and rm['pass_']
verified=[]
for row in pm['artifacts']+rm['exports']:
 p=Path(row['path']);assert ident(p)['sha256']==row['sha256'] and p.stat().st_size==row['bytes'];verified.append(row['path'])
for m in [pm,rm]:assert ident(Path(m['source']['path']))==m['source']==m['source_after']
events={e['event']:e for e in rm['events']}
report=dict(tool=ident(Path(__file__)),command='python docs/competitor/tools/analyze_wet_sand.py',package_manifest=ident(PKG/'manifest.json'),rdc_manifest=ident(RDC/'manifest.json'),verified_artifacts=len(verified),matches=[],constants={},water_states={},derived=[],scope='Instruction and captured-data facts. No calibrated original elapsed seconds or before/after dynamics claim.')
report['disassembler']=ident(Path('C:/Windows/System32/d3dcompiler_47.dll'))
for eid,label in [(5006,'vs'),(5006,'ps'),(1537,'cs'),(6083,'vs'),(6083,'ps')]:
 sr=events[eid]['stages'][label];matches=[p for p in pm['programs'] if p['bytecode']['sha256']==sr['bytecode']['sha256']]
 if eid in [5006,1537]:assert matches
 report['matches'].append(dict(event=eid,stage=label,shader=sr['bytecode'],package_programs=[p['name'] for p in matches]))
 dest=RDC/f'e{eid}_{label}_hex.asm';dest.write_text(hex_disassemble(Path(sr['bytecode']['path']).read_bytes()),encoding='utf8');report['derived'].append(dict(**ident(dest),selector=f'D3DDisassemble flags 0xa0 from E{eid} {label} rawBytes'))
ps=next(p for p in pm['programs'] if p['bytecode']['sha256']==events[5006]['stages']['ps']['bytecode']['sha256'])
names={i:n for n,i in ps['name_indices']}
raw=(RDC/'e5006_ps_cb0.bin').read_bytes()
for block in ps['parameters']['m_ConstantBuffers']:
 for v in block['m_VectorParams']:
  name=names[v['m_NameIndex']]
  if name in ['sandColor','wetSandColor','sedimentColor']:
   report['constants'][name]=dict(offset=v['m_Index'],value=list(struct.unpack_from('<3f',raw,v['m_Index'])))
water_program=next(p for p in pm['programs'] if p['name']=='Water_UpdateAmount_0')
raw=(RDC/'e1537_cs_cb0.bin').read_bytes()
report['water_update_constants']={v['name']:list(struct.unpack_from('<'+('i' if v['type']==1 else 'f')*v['colCount'],raw,v['offset'])) for b in water_program['constants'] for v in b['params']}
# Exact rounded IEEE-754 literals from the exported hexadecimal disassembly.
scale=floatbits(0x3521999b);offset=floatbits(0x3d4ccccd)
report['formula']=dict(amount_decode={'word':2,'mask':'0x00ffffff','scale_bits':'0x3521999b','scale':scale},visible_depth='max(A - 0.05, 0); water PS discards depth < 0.00001',wet_weight='t=clamp((clamp(A,0,1)-0.001)*52.63158,0,1); W=t*t*(3-2*t)',base_color='lerp(sandColor,wetSandColor,W), then sediment color and grain modulation',sand_instruction_locations={'vs_water_amount':'54-105','ps_wet_color':'40-49','ps_sediment_color':'50-52'},evaporation='A_before_other_terms = A - dt * 0.001 * sunColor.r * evaporationFactor * exp2(-0.721348 * air_term); other source/boundary/clamp/quantization terms follow')
for eid in [1537,5006,6083]:
 raw=np.fromfile(RDC/f'e{eid}_buffer_139573.bin',dtype='<u4').reshape(256,512,4)
 amount=(raw[:,:,2]&0xffffff).astype(np.float32)*np.float32(scale)
 depth=np.maximum(amount-np.float32(offset),0)
 weight=np.clip((np.clip(amount,0,1)-np.float32(.001))*np.float32(52.63158),0,1);weight=weight*weight*(3-2*weight)
 hidden=depth<np.float32(.00001)
 report['water_states'][str(eid)]=dict(raw=ident(RDC/f'e{eid}_buffer_139573.bin'),shape=[256,512],amount_minmax=[float(amount.min()),float(amount.max())],zero_display_depth=int((depth==0).sum()),under_water_discard_threshold=int(hidden.sum()),wet_weight_minmax=[float(weight.min()),float(weight.max())],fully_wet_with_zero_display_depth=int(((weight==1)&(depth==0)).sum()),note='Native cell sample classification, not raster pixel coverage; sand VS bilinear interpolation and water mesh interpolation differ.')
 if eid==5006:
  # Actual data mask: visible-water threshold overlaid with fully-wet residual state.
  import matplotlib
  matplotlib.use('Agg')
  import matplotlib.pyplot as plt
  from matplotlib.colors import ListedColormap
  fig,axes=plt.subplots(1,2,figsize=(11,4.1),layout='constrained')
  cls=np.where(depth>0,2,np.where(weight==1,1,0))
  axes[0].imshow(cls,origin='lower',extent=(-15,15,-7.5,7.5),cmap=ListedColormap(['#dfc98f','#9b6c3f','#4b9faa']),vmin=0,vmax=2,interpolation='nearest')
  axes[0].set(title='test1 E5006 native water cells',xlabel='X (scene units)',ylabel='Z (scene units)')
  from matplotlib.patches import Patch
  axes[0].legend(handles=[Patch(color='#9b6c3f',label='Fully wet color; zero display depth'),Patch(color='#4b9faa',label='Positive display depth')],loc='upper left',fontsize=7)
  x=np.linspace(0,.07,700);t=np.clip((x-.001)/.019,0,1)
  axes[1].plot(x,t*t*(3-2*t),color='#9b6c3f',label='Wet-sand color weight')
  axes[1].axvline(.05,color='#4b9faa',label='Display depth starts at A = 0.05')
  axes[1].axvspan(.02,.05,color='#9b6c3f',alpha=.12)
  axes[1].set(title='Reconstructed shader transfer',xlabel='Internal water amount A (not meters)',ylabel='Wet-color weight',ylim=(-.03,1.08))
  axes[1].legend(fontsize=8,loc='lower right');axes[1].grid(alpha=.15)
  dest=OUT/'wet_color_mechanism.png';fig.savefig(dest,dpi=150);plt.close(fig);report['derived'].append(dict(**ident(dest),selector='E5006 raw cells + PS/VS reconstructed transfer; schematic, not screenshot'))
dry=np.array(report['constants']['sandColor']['value']);wet=np.array(report['constants']['wetSandColor']['value'])
report['wet_to_dry_linear_rgb_ratio']=(wet/dry).tolist()
report['replay_water_bytes_identical_across_selected_events']=len({r['raw']['sha256'] for r in report['water_states'].values()})==1
baseline=np.fromfile(RDC/'e5006_buffer_139573.bin',dtype='<u4').reshape(-1,4)
report['independent_replay_differences']={}
for eid in [1537,6083]:
 other=np.fromfile(RDC/f'e{eid}_buffer_139573.bin',dtype='<u4').reshape(-1,4)
 report['independent_replay_differences'][str(eid)]=dict(different_words_by_channel=(baseline!=other).sum(axis=0).tolist(),different_amount_words=int(((baseline[:,2]&0xffffff)!=(other[:,2]&0xffffff)).sum()))
report['limits']=['No independent wetness texture read by this selected sand VS/PS; no claim about all game stages or other materials.','All captured water cells have A > 0.02 and therefore full wet-color weight; this frame does not exhibit the dry-to-wet color transition.','Evaporation code and captured deltaTime do not establish actual wall-clock drying duration; no original 20-30 s claim.','A has an internal offset and is not interchangeable with Godot true water depth.']
report['limits'].append('Full buffers differ between independent event replays, including some amount words. Do not interpret their subtraction as one deterministic update or a temporal derivative; reported threshold classes are unchanged.')
(OUT/'analysis.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print(json.dumps({k:report[k] for k in ['verified_artifacts','constants','water_states','wet_to_dry_linear_rgb_ratio','limits']},indent=2))
