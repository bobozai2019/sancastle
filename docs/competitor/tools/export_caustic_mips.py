import hashlib,json,os,traceback
from pathlib import Path
ROOT=Path('D:/godot/project/sandcastle')
OUT=ROOT/'test_output/water_material_rdc/caustic_mips_v1';OUT.mkdir(parents=True,exist_ok=True)
source=ROOT/'sandcastlegame/test1.rdc'
report={'pass':False,'source':{'path':str(source),'bytes':source.stat().st_size,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()},'mips':[]}
capture=controller=None
try:
 import renderdoc as rd
 assert report['source']['sha256']=='761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2'
 script=ROOT/'docs/competitor/tools/export_caustic_mips.py'
 report['tool']={'renderdoc':rd.GetVersionString(),'script_sha256':hashlib.sha256(script.read_bytes()).hexdigest(),'command':'D:/other_software/RenderDoc/qrenderdoc.exe --python '+str(script)}
 capture=rd.OpenCaptureFile();capture.OpenFile(str(source),'',None)
 status,controller=capture.OpenCapture(rd.ReplayOptions(),None);report['replay']=str(status)
 if controller is None:raise RuntimeError(str(status))
 controller.SetFrameEvent(5006,True)
 bound=next(v.descriptor.resource for v in controller.GetPipelineState().GetReadOnlyResources(rd.ShaderStage.Pixel) if v.access.index==4)
 assert str(bound)=='ResourceId::1105'
 texture=next(t for t in controller.GetTextures() if t.resourceId==bound)
 assert texture.format.Name()=='R8_UNORM' and texture.mips==9
 for mip in range(texture.mips):
  sub=rd.Subresource();sub.mip=mip
  data=bytes(controller.GetTextureData(bound,sub));w=max(256>>mip,1);h=w;d=max(64>>mip,1)
  assert len(data)==w*h*d
  path=OUT/('caustic_1105_mip%d.bin'%mip);path.write_bytes(data)
  report['mips'].append({'path':str(path),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'dimensions':[w,h,d],'selector':'E5006 post-event PS t4 R1105 mip%d whole volume'%mip})
 assert report['mips'][0]['sha256']=='e5355399d7e4931291032ebd78d7b50dfe89cb7565dbda422f74e469769d3b0c'
 report['pass']=True
except Exception as error:report['error']=repr(error);report['traceback']=traceback.format_exc()
finally:
 if controller is not None:controller.Shutdown()
 if capture is not None:capture.Shutdown()
 (OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
os._exit(0 if report['pass'] else 1)
