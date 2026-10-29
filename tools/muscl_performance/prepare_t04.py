"""Build a GPU-owned first-stage retry cache in an isolated baseline project."""
from pathlib import Path
import difflib
import hashlib
import json
import re
import shutil

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'test_output/muscl_performance_round2/projects/diagnostic_final'
TARGET=ROOT/'test_output/muscl_performance_round2/projects/t04_retry_v1'
EVIDENCE=ROOT/'task/muscl_performance_round2/验收/t04_prototype'
shutil.copytree(BASE,TARGET)
EVIDENCE.mkdir(parents=True,exist_ok=False)

def change(relative,before,after):
    p=TARGET/relative
    text=p.read_text(encoding='utf-8')
    if text.count(before)!=1:raise RuntimeError((relative,'anchor count',text.count(before)))
    p.write_text(text.replace(before,after),encoding='utf-8',newline='\n')

recorder='scripts/simulation/unified_edit/water_muscl.gd'
spatial='shaders/simulation/muscl/muscl_spatial.glslinc'
edge='shaders/simulation/muscl/rk_edge.glsl'
decision='shaders/simulation/muscl/rk_decide.glsl'
change(recorder,'_append_decision(0,1 if water.boundary_enabled else 0,requested_dt)',
 '''# The private initializer index packs boundary in bit 0 and cache policy in
\t# bit 1. GPU mode 0 owns reset; custom/wrapped callbacks never reuse input.
\tvar cache_policy:=2 if _standard_coupling or not water.coupled_recorder.is_valid() else 0
\t_append_decision(0,(1 if water.boundary_enabled else 0)|cache_policy,requested_dt)''')
change(recorder,'images.speed_tiles=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,32,32)',
 '''images.speed_tiles=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,32,32)
\t# First-stage values survive phase 1 and are disposable on accepted/new ticks.
\timages.retry_correction=_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
\timages.retry_bed_source=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
\timages.retry_speed_tiles=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,32,32)''')
change(recorder,'[["trial",128],["safety",128],["audit",2048],["trial_indirect",768]]',
 '[["trial",128],["safety",128],["audit",2048],["trial_indirect",768],["retry_cache",16]]')
change(recorder,'images.correction,images.bed_source,images["drain%d"%phase],images.speed_tiles]',
 '(images.retry_correction if phase==0 else images.correction),(images.retry_bed_source if phase==0 else images.bed_source),images["drain%d"%phase],(images.retry_speed_tiles if phase==0 else images.speed_tiles)]')
change(recorder,'water.kernels[name].shader,0,images_for_phase,spatial_buffers)',
 'water.kernels[name].shader,0,images_for_phase,spatial_buffers+[buffers.retry_cache])')
change(recorder,'[images.speed_tiles],[water.decision,buffers.trial,buffers.safety,buffers.audit,buffers.trial_indirect,water.indirect,water.solver.async_transport.control])',
 '[images.speed_tiles,images.retry_speed_tiles],[water.decision,buffers.trial,buffers.safety,buffers.audit,buffers.trial_indirect,water.indirect,water.solver.async_transport.control,buffers.retry_cache])')
change(spatial,'layout(push_constant,std430)',
 'layout(set=0,binding=18,std430) buffer RetryCache {uint retry_cache[];};\nlayout(push_constant,std430)')
change(edge,'void main(){', '''void main(){
 // Uniform dispatch-wide predicate. Validity is written only by decision
 // passes, never by one workgroup racing other groups in this dispatch.
 if(p.phase==0u&&retry_cache[1]!=0u&&retry_cache[0]!=0u){
  if(all(equal(gl_GlobalInvocationID,uvec3(0))))tr[15]=1u;
  return;
 }''')
p=TARGET/decision
text=p.read_text(encoding='utf-8')
text=re.sub(r'layout\(set=0,binding=([1-7]),std430\)',lambda m:'layout(set=0,binding='+str(int(m[1])+1)+',std430)',text)
p.write_text(text,encoding='utf-8',newline='\n')
change(decision,'layout(push_constant,std430)',
 'layout(set=0,binding=1,rg32f) uniform readonly image2D first_speed_tiles;\nlayout(set=0,binding=9,std430) buffer RetryCache {uint retry_cache[];};\nlayout(push_constant,std430)')
change(decision,'void fatal(uint flags){','void fatal(uint flags){\n retry_cache[0]=0u;')
change(decision,'vec2 a=imageLoad(speed_tiles,ivec2(j%uint(size.x),j/uint(size.x))).xy;',
 'ivec2 q=ivec2(j%uint(size.x),j/uint(size.x));vec2 a=(p.mode==3u?imageLoad(speed_tiles,q):imageLoad(first_speed_tiles,q)).xy;')
change(decision,'if(p.mode==0u){','if(p.mode==0u){\n  retry_cache[0]=0u;retry_cache[1]=(p.index>>1u)&1u;retry_cache[2]=0u;retry_cache[3]=0u;')
change(decision,'tr[12]=p.index;','tr[12]=p.index&1u;')
change(decision,'if(control[1]!=0u||tr[14]!=0u)d[4]=2u;',
 'if(control[1]!=0u||tr[14]!=0u){d[4]=2u;retry_cache[0]=0u;}')
change(decision,'if(tr[7]==0u||control[1]!=0u)return;',
 'if(tr[7]==0u||control[1]!=0u)return;\n  retry_cache[0]=0u;')
change(decision,'tr[8]=floatBitsToUint(sum_speed);',
 '''tr[8]=floatBitsToUint(sum_speed);
  if(retry_cache[1]!=0u&&retry_cache[0]!=0u)retry_cache[2]++;else retry_cache[3]++;
  retry_cache[0]=retry_cache[1];''')
diff=[];identity={}
for relative in [recorder,spatial,edge,decision]:
    dest=EVIDENCE/'sources'/relative;dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(TARGET/relative,dest)
    identity[relative]=hashlib.sha256((TARGET/relative).read_bytes()).hexdigest()
    diff.extend(difflib.unified_diff((BASE/relative).read_text(encoding='utf-8').splitlines(True),
        (TARGET/relative).read_text(encoding='utf-8').splitlines(True),fromfile='a/'+relative,tofile='b/'+relative))
(EVIDENCE/'candidate.diff').write_text(''.join(diff),encoding='utf-8')
(EVIDENCE/'identity.json').write_text(json.dumps({'base':str(BASE),'candidate':str(TARGET),'source_hashes':identity,
 'extra_texture_payload_bytes':1581056,'extra_buffer_payload_bytes':16,
 'scope':'Private per-phase first-stage fields; GPU reset on new tick/accept/fault; disabled for custom callbacks; unchanged math and original authority buffers'},indent=2),encoding='utf-8')
print(TARGET)
