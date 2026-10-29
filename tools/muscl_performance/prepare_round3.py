"""Create immutable, reconstructible round-three isolated candidates."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import shutil
from context import add_arguments, resolve, ROOT

parser = argparse.ArgumentParser(description=__doc__)
add_arguments(parser)
parser.add_argument('--base', type=Path, required=True)
parser.add_argument('--name', required=True)
parser.add_argument('--candidate', choices=('common', 'p1', 'p2', 'p3', 'p4'), required=True)
args = parser.parse_args()
task, temporary = resolve(args)
target = temporary / 'projects' / args.name
evidence = task / '验收' / args.name
evidence.mkdir(parents=True, exist_ok=False)
shutil.copytree(args.base, target)
for relative in ('tests/integration/water_execution_exact_probe.gd',
                 'tools/muscl_performance/first_order_support.gd',
                 'tools/muscl_performance/restart_probe.gd',
                 'tools/wave_propagation/native_restart_probe.gd'):
    shutil.copy2(ROOT / relative, target / relative)


def edit(relative, before, after):
    path = target / relative
    text = path.read_text(encoding='utf-8')
    assert before in text, (relative, before)
    path.write_text(text.replace(before, after), encoding='utf-8')


coupled = 'scripts/simulation/unified_edit/coupled.gd'
muscl = 'scripts/simulation/unified_edit/water_muscl.gd'
if args.candidate == 'common':
    for relative in ['scripts/simulation/unified_edit/'+n for n in ('water.gd','water_muscl.gd','coupled.gd')] + ['tools/muscl_performance/'+n for n in ('variant_states.gd','fixture_upload.gd')]:
        shutil.copy2(ROOT / relative, target / relative)
elif args.candidate == 'p1':
    edit(muscl, '["drain0","drain1","exchange_sediment"]', '["drain0","drain1"]')
    edit(coupled, '\tif stage_transport:\n\t\timages.exchange_sediment=water.muscl.images.exchange_sediment\n\t\tif not water._compile("sediment_copy_normalize",COPY_SOURCE):last_error=water.last_error;return false\n', '')
    edit(coupled, 'images.exchange_sediment,images.dirty', 'images.dirty')
    edit(coupled, '\n\t\t\tsets.sediment_copy.append(water._make_binding(water.kernels.sediment_copy_normalize.shader,0,[images.exchange_sediment,state.textures.sediment[live]],[]))', '')
    edit(coupled, '\n\t\tif stage_transport:passes.append(Recorder.RecordingPass.new(water.kernels.sediment_copy_normalize.pipeline,sets.sediment_copy[live],water.kernels.sediment_copy_normalize.decision_set))', '')
    # Water's dynamic declaration is read-only by default. This exchange owns
    # the former copy side effect, so it explicitly declares writable decision.
    edit(coupled, '\tif not stage_transport:sediment_replacements["params.delta_s"]=dt', '\tif stage_transport:\n\t\tsediment_replacements["#version 450"]="#version 450\\nlayout(set=1,binding=0,std430) buffer AsyncDecision {uint async_d[];};"\n\t\tsediment_replacements["void main() {"]=fraction+" if(async_d[4]==2u)return; if(all(equal(gl_GlobalInvocationID.xy,uvec2(0))))async_d[5]=0u;"\n\telse:sediment_replacements["params.delta_s"]=dt')
    # Remove the generic read-only declaration only for this private variant.
    edit(coupled, '\tif not water._compile("sediment",EXCHANGE_SOURCE if stage_transport else SOURCES[1],sediment_replacements)', '\tif stage_transport:sediment_replacements["#version 450"]="#version 450"\n\tif not water._compile("sediment",EXCHANGE_SOURCE if stage_transport else SOURCES[1],sediment_replacements)')
    # Use an explicit private source with its declaration; generic compiler
    # declaration is suppressed by its existing use_decision argument.
    edit(coupled, 'EXCHANGE_SOURCE if stage_transport else SOURCES[1],sediment_replacements)', 'EXCHANGE_SOURCE if stage_transport else SOURCES[1],sediment_replacements,[],not stage_transport)')
    edit(coupled, '\tif not water._compile("material_step"', '\tif stage_transport:water.kernels.sediment.decision_set=water._make_binding(water.kernels.sediment.shader,1,[],[water.decision])\n\tif not water._compile("material_step"')
    shader = 'shaders/simulation/erosion/sediment_exchange.glsl'
    edit(shader, '#version 450', '#version 450\nlayout(set=1,binding=0,std430) buffer AsyncDecision {uint async_d[];};')
    edit(shader, 'uniform restrict readonly image2D sediment_in;', 'uniform restrict image2D sediment_in;')
    edit(shader, 'layout(set=0,binding=7,r32f) uniform restrict writeonly image2D sediment_out;\n', '')
    edit(shader, 'binding=8,r32ui', 'binding=7,r32ui')
    edit(shader, 'imageStore(sediment_out,p', 'imageStore(sediment_in,p')
elif args.candidate == 'p2':
    edit(coupled, 'fraction+" if(async_d[4]==2u)return;', 'fraction+" if(all(equal(gl_GlobalInvocationID.xy,uvec2(0))))has_tagged_sand=0u; if(async_d[4]==2u)return;')
    edit(coupled, 'sediment_replacements,[],not stage_transport)', 'sediment_replacements,[],not stage_transport)')
    edit(coupled, '[water.decision])', '[water.decision,buffers.flags])')
    edit(coupled, '\n\t\t\tRecorder.RecordingPass.new(kernels.support.pipeline,sets.support,RID(),PackedInt32Array([256,live,2,0]).to_byte_array()),', '')
    edit(coupled, '\t\tpasses.append_array([', '\t\tif not stage_transport:passes.append(Recorder.RecordingPass.new(kernels.support.pipeline,sets.support,RID(),PackedInt32Array([256,live,2,0]).to_byte_array()))\n\t\tpasses.append_array([')
    edit('shaders/simulation/erosion/sediment_exchange.glsl', 'buffer AsyncDecision {uint async_d[];};', 'buffer AsyncDecision {uint async_d[];};\nlayout(set=1,binding=1,std430) buffer Active {uint has_tagged_sand;};')
elif args.candidate == 'p3':
    shader = 'shaders/simulation/material/material_finish.glsl'
    (target / shader).write_text('''#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,std430) readonly buffer StagedSlope {uvec2 result_bits[];};
layout(r16f,set=0,binding=1) uniform restrict readonly image2D wetness_src;
layout(r16f,set=0,binding=2) uniform restrict readonly image2D compaction_src;
layout(r16f,set=0,binding=3) uniform restrict writeonly image2D wetness_dst;
layout(r16f,set=0,binding=4) uniform restrict writeonly image2D compaction_dst;
layout(r32f,set=0,binding=5) uniform restrict writeonly image2D sand0;
layout(r32f,set=0,binding=6) uniform restrict writeonly image2D sand1;
void main(){
 ivec2 p=ivec2(gl_GlobalInvocationID.xy),extent=imageSize(wetness_src);
 if(p.x>=extent.x||p.y>=extent.y)return;
 float value=uintBitsToFloat(result_bits[uint(p.y*extent.x+p.x)].y);
 vec4 sand=vec4(max(value,0.0),0.0,0.0,1.0);
 imageStore(sand0,p,sand);imageStore(sand1,p,sand);
 imageStore(wetness_dst,p,vec4(imageLoad(wetness_src,p).r,0.0,0.0,1.0));
 imageStore(compaction_dst,p,vec4(imageLoad(compaction_src,p).r,0.0,0.0,1.0));
}
''',encoding='utf-8')
    edit(coupled, 'EXCHANGE_SOURCE,COPY_SOURCE]', 'EXCHANGE_SOURCE,COPY_SOURCE,"res://'+shader+'"]')
    edit(coupled, '[["consume",SOURCES[5]],["commit",SOURCES[6]],["support",SOURCES[7]]]', '[["finish","res://'+shader+'"],["support",SOURCES[7]]]')
    edit(coupled, '"material_molded","consume","commit"]:sets', '"material_molded","finish"]:sets')
    edit(coupled, '\t\tsets.consume.append(binding("consume",{0:buffers.slope},{1:state.textures.sand[spare]}))\n\t\tsets.commit.append(binding("commit",{},{0:state.textures.wetness[spare],1:state.textures.compaction[spare],2:state.textures.sand[spare],3:state.textures.wetness[live],4:state.textures.compaction[live],5:state.textures.sand[live]}))', '\t\tsets.finish.append(binding("finish",{0:buffers.slope},{1:state.textures.wetness[spare],2:state.textures.compaction[spare],3:state.textures.wetness[live],4:state.textures.compaction[live],5:state.textures.sand[0],6:state.textures.sand[1]}))')
    edit(coupled, '\t\t\tRecorder.RecordingPass.new(kernels.consume.pipeline,sets.consume[live]),\n\t\t\tRecorder.RecordingPass.new(kernels.commit.pipeline,sets.commit[live]),', '\t\t\tRecorder.RecordingPass.new(kernels.finish.pipeline,sets.finish[live]),')
    edit(coupled, 'for name in ["consume","commit"]:', 'for name in ["finish"]:')
elif args.candidate == 'p4':
    shader = 'shaders/simulation/material/material_finish.glsl'
    edit(shader, 'void main(){', '''layout(set=0,binding=7,std430) readonly buffer SupportResult {vec2 support_result[];};
layout(set=0,binding=8,std430) readonly buffer Active {uint has_tagged_sand;};
layout(rg32f,set=0,binding=9) uniform restrict writeonly image2D support0;
layout(rg32f,set=0,binding=10) uniform restrict writeonly image2D support1;
void main(){''')
    edit(shader, ' imageStore(sand0,p,sand);', ' vec2 support=has_tagged_sand==0u?vec2(0):support_result[uint(p.y*extent.x+p.x)];\n imageStore(support0,p,vec4(support,0,0));imageStore(support1,p,vec4(support,0,0));\n imageStore(sand0,p,sand);')
    edit(coupled, 'binding("finish",{0:buffers.slope},{', 'binding("finish",{0:buffers.slope,7:buffers.support,8:buffers.flags},{')
    edit(coupled, '6:state.textures.sand[1]}))', '6:state.textures.sand[1],9:state.textures.mold_support[0],10:state.textures.mold_support[1]}))')
    edit(coupled, '\t\t\tRecorder.RecordingPass.new(kernels.finish.pipeline,sets.finish[live]),\n\t\t\tRecorder.RecordingPass.new(kernels.support.pipeline,sets.support,RID(),PackedInt32Array([256,live,1,0]).to_byte_array())])', '\t\t\tRecorder.RecordingPass.new(kernels.finish.pipeline,sets.finish[live])])')

changes = {}
diffs = []
for path in target.rglob('*'):
    if not path.is_file() or '.godot' in path.parts:continue
    rel = path.relative_to(target)
    original = args.base / rel
    if original.is_file() and original.read_bytes() == path.read_bytes():continue
    destination = evidence / 'sources' / rel
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, destination)
    changes[rel.as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    if path.suffix in ('.gd','.glsl'):
        diffs.extend(difflib.unified_diff(original.read_text(encoding='utf-8').splitlines(True) if original.is_file() else [], path.read_text(encoding='utf-8').splitlines(True), fromfile='a/'+rel.as_posix(), tofile='b/'+rel.as_posix()))
(evidence/'changes.diff').write_text(''.join(diffs),encoding='utf-8')
(evidence/'identity.json').write_text(json.dumps({'base':str(args.base.resolve()),'candidate':args.candidate,'changes':changes},indent=2),encoding='utf-8')
print(target)
