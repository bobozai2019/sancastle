import hashlib,json,os,struct,traceback
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle'); SOURCE=ROOT/'sandcastlegame/test41.rdc'
OUT=ROOT/'test_output/water_momentum_lab/g0_replay_20261019_v2';OUT.mkdir(exist_ok=False,parents=True)
def ident(p):return dict(path=str(p),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
report={'source':ident(SOURCE),'script':ident(ROOT/'tools/water_momentum_lab/export_water_paint.py'),'exports':[],'events':[],'pass':False}
def export(name,raw,selector):
 p=OUT/name;p.write_bytes(bytes(raw));r=dict(ident(p),selector=selector);report['exports'].append(r);return r
try:
 import renderdoc as rd
 report['version']=rd.GetVersionString()
 assert report['source']['sha256']=='f1794a7235a79f7a73bd6f4085bef7ecbb3a7dc39ce8a8a7aac955ee5beb3c0d'
 for event,tag in [(878,'mode2'),(1210,'mode6'),(1210,'mode6_negative')]:
  cap=rd.OpenCaptureFile();cap.OpenFile(str(SOURCE),'',None);status,ctl=cap.OpenCapture(rd.ReplayOptions(),None)
  try:
   assert ctl is not None,str(status)
   ctl.SetFrameEvent(event,True);pipe=ctl.GetPipelineState();stage=rd.ShaderStage.Compute;refl=pipe.GetShaderReflection(stage)
   row={'event':event,'tag':tag,'bindings':[],'constants':[]};report['events'].append(row)
   row['shader']=export(tag+'_paint.dxbc',refl.rawBytes,f'E{event} CS rawBytes')
   export(tag+'_paint.asm',ctl.DisassembleShader(pipe.GetComputePipelineObject(),refl,'').encode(),f'E{event} disassembly')
   for i,b in enumerate(refl.constantBlocks):
    d=pipe.GetConstantBlock(stage,i,0).descriptor
    raw=bytes(ctl.GetBufferData(d.resource,d.byteOffset,min(d.byteSize,b.byteSize)))
    row['constants'].append(export(f'{tag}_cb{i}.bin',raw,f'E{event} cb{i} resource={d.resource} offset={d.byteOffset}'))
   tex={t.resourceId:t for t in ctl.GetTextures()}
   for label,resources in [('read',pipe.GetReadOnlyResources(stage)),('write',pipe.GetReadWriteResources(stage))]:
    for used in resources:
     d=used.descriptor;item=dict(access=label,index=used.access.index,resource=str(d.resource),offset=d.byteOffset,bytes=d.byteSize);row['bindings'].append(item)
     name=f'{tag}_{label}_{used.access.index}'
     if d.resource in tex:
      t=tex[d.resource];item.update(width=t.width,height=t.height,format=t.format.Name())
      if t.width*t.height<=256*256:item['raw']=export(name+'.texels',ctl.GetTextureData(d.resource,rd.Subresource()),f'E{event} {d.resource} mip0/slice0/sample0')
     elif 0<d.byteSize<=4*1024*1024:item['raw']=export(name+'.bin',ctl.GetBufferData(d.resource,d.byteOffset,d.byteSize),f'E{event} {d.resource} offset={d.byteOffset} bytes={d.byteSize}')
  finally:
   if ctl:ctl.Shutdown()
   cap.Shutdown()
 report['source_after']=ident(SOURCE);report['pass']=report['source_after']==report['source']
except Exception:report['error']=traceback.format_exc()
(OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
os._exit(0 if report['pass'] else 1)

