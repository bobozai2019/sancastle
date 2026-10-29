"""Generate explicit velocity read-stream GLSL and an isolated fixed scene probe."""
import argparse
import json
import shutil
from pathlib import Path
from evidence_contract import identity
from lower_dxbc_glsl import generate,uexpr


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['exact','adaptation','project','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--mode',choices=['read_stream','in_place_record'],default='read_stream')
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    adaptation=json.loads((args.adaptation/'adaptation.json').read_text())
    event=adaptation['event'];read_count=len(adaptation['reads'])
    if event not in [1484,1490,1495,1500,1537,1543] or adaptation['stream_bytes']!=131072*read_count*32:raise ValueError('STREAM_LAYOUT')
    asm=args.exact/f'e{event}_exact.asm'
    if identity(asm)['sha256']!=adaptation['parent_asm']['sha256']:raise ValueError('SOURCE_CHANGED')
    glsl,record=generate(asm.read_text(),event,'fma','separate','in_place','native','precise',(),'advection_dt' if event==1500 else 'none',event==1490,'fma_y' if event==1490 else 'separate')
    if args.mode=='read_stream':glsl=glsl.replace('// Same logical in-place water alias and 32x32 threads. No intra-dispatch barrier added.','// Explicit post-swizzle read-stream replay, separate output. Not original alias execution.')
    declaration=('layout(set=0,binding=4,std430) readonly buffer ReadStream {uvec4 streamCells[];};\n' if args.mode=='read_stream' else '')+'layout(set=0,binding=5,std430) buffer StreamOutput {uvec4 observedStream[];};\n'
    glsl=glsl.replace('void main(){',declaration+'void main(){')
    replacements=[]
    for read in adaptation['reads']:
        n=read['instruction'];start=glsl.index(' // DXBC '+str(n)+':');end=glsl.index(' // DXBC '+str(n+1)+':',start)
        old=glsl[start:end];reg=read['destination'];mask=read['mask'];slot=read['slot']*2
        new=' // DXBC '+str(n)+': '+read['original']+'\n // Explicit stream substitution; original computed address is still recorded.\n'
        new+=' uint streamSlot'+str(n)+'=(vThreadID.y*512u+vThreadID.x)*'+str(read_count*2)+'u+'+str(slot)+'u;\n'
        new+=' observedStream[streamSlot'+str(n)+']=uvec4(('+uexpr(read['index'])+').x,'+str(read['offset'])+'u,'+str(read['mask_bits'])+'u,'+str(n)+'u);\n'
        if args.mode=='read_stream':
            new+=' uvec4 t'+str(n)+'=streamCells[streamSlot'+str(n)+'+1u];\n'
            new+=' '+reg+'.'+mask+'=t'+str(n)+'.'+mask+';\n'
        else:
            new+=old.split('\n',1)[1]
        new+=' uvec4 streamValue'+str(n)+'=uvec4(0u);\n streamValue'+str(n)+'.'+mask+'='+reg+'.'+mask+';\n'
        new+=' observedStream[streamSlot'+str(n)+'+1u]=streamValue'+str(n)+';\n'
        glsl=glsl[:start]+new+glsl[end:];replacements.append(dict(instruction=n,original_block=old,replacement=new))
    if glsl.split('void main(){',1)[1].count('waterCells[')!=(1 if args.mode=='read_stream' else read_count+1):raise ValueError('WATER_ACCESS_LAYOUT')
    suffix='read_stream' if args.mode=='read_stream' else 'inplace_record'
    target=args.project/f'shaders/e{event}_{suffix}.glsl';target.write_text(glsl,encoding='utf-8');shutil.copyfile(target,out/target.name)
    parent=args.project/'kernel_probe.gd';probe=parent.read_text();parent_id=identity(parent)
    probe=probe.replace('const CB_BYTES := {1484:2496,1490:2560,1495:2528,1500:2544,1537:2560,1543:2496}','const CB_BYTES := {1484:2496,1490:2560,1495:2528,1500:2544,1537:2560,1543:2496}\nconst READ_COUNTS := {1484:1,1490:5,1495:5,1500:5,1537:1,1543:5}')
    probe=probe.replace('snapshot','stream_input').replace('SNAPSHOT','READ_STREAM')
    probe=probe.replace('\tvar bytes := FileAccess.get_file_as_bytes(str(artifact["path"]))','\tvar bytes := FileAccess.get_file_as_bytes(str(artifact["path"]))\n\tif bytes.is_empty():\n\t\t_fail("EMPTY_ARTIFACT:" + str(artifact["path"]))\n\t\treturn PackedByteArray()')
    probe=probe.replace('== "stream_input":','== "read_stream":')
    probe=probe.replace('stream_input_seed.size() != WATER_BYTES','stream_input_seed.size() != stream_bytes').replace('storage_buffer_create(WATER_BYTES, stream_input_seed)','storage_buffer_create(stream_bytes, stream_input_seed)')
    probe=probe.replace('\t\t\tstream_input_seed = _checked_bytes(case["stream_input"])','\t\t\tstream_input_seed = _checked_bytes(case["stream_input"])\n\t\t\tif stream_input_seed.is_empty():\n\t\t\t\treturn')
    probe=probe.replace('debug_seed.resize(WATER_BYTES)','debug_seed.resize(stream_bytes)').replace('storage_buffer_create(WATER_BYTES, debug_seed)','storage_buffer_create(stream_bytes, debug_seed)').replace('buffer_update(debug_trace, 0, WATER_BYTES, debug_seed)','buffer_update(debug_trace, 0, stream_bytes, debug_seed)')
    probe=probe.replace('_trace.bin','_stream_output.bin').replace('explicit readonly stream_input plus separate output','explicit fixed post-swizzle stream plus separate output')
    anchor='\t\tvar event := int(case["event_id"])'
    if probe.count(anchor)!=1:raise ValueError('PROBE_MODE_ANCHOR')
    probe=probe.replace(anchor,anchor+'\n\t\tvar read_count := int(case.get("read_count", 0))\n\t\tvar mode := str(case.get("execution_mode", ""))\n\t\tif not READ_COUNTS.has(event) or read_count != int(READ_COUNTS[event]) or not ["read_stream", "in_place_record"].has(mode) or not case.get("register_trace", false):\n\t\t\t_fail("READ_STREAM_PILOT_MODE_REQUIRED")\n\t\t\treturn\n\t\tif mode == "in_place_record" and case.has("stream_input"):\n\t\t\t_fail("UNEXPECTED_STREAM_INPUT_FOR_RECORD")\n\t\t\treturn\n\t\tif mode == "read_stream" and not case.has("stream_input"):\n\t\t\t_fail("STREAM_INPUT_REQUIRED_FOR_REPLAY")\n\t\t\treturn\n\t\tvar stream_bytes := WATER_BYTES * read_count * 2')
    probe=probe.replace('Candidate lowered single kernels only, needs frozen budget comparison','Instrumented alias record and fixed-stream replay; mode-specific exact pairing required')
    probe_path=args.project/'stream_probe.gd';probe_path.write_text(probe,encoding='utf-8');shutil.copyfile(probe_path,out/probe_path.name)
    scene=(args.project/'kernel_probe.tscn').read_text().replace('res://kernel_probe.gd','res://stream_probe.gd').replace('PackedKernelProbe','ReadStreamProbe').replace('Packed single-kernel comparison','Fixed read-stream replay')
    scene_path=args.project/'stream_probe.tscn';scene_path.write_text(scene,encoding='utf-8');shutil.copyfile(scene_path,out/scene_path.name)
    for name in ['make_readstream_glsl.py','lower_dxbc_glsl.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    report=dict(operation_status='complete',verification_status='not_evaluated',event=event,read_count=read_count,stream_bytes=adaptation['stream_bytes'],shader=identity(target),probe=identity(probe_path),scene=identity(scene_path),source=identity(asm),
        adaptation=identity(args.adaptation/'adaptation.json'),parent_probe=parent_id,original_arithmetic_profile=record,replacements=replacements,
        mode='explicit_read_stream_replay' if args.mode=='read_stream' else 'instrumented_godot_in_place_record',scope='Generated instrumented read-stream code only. No shader compile/GPU/numeric acceptance yet.')
    (out/'lowering.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='not_evaluated',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(event=event,mode=args.mode,stream_loads=read_count,stream_bytes=adaptation['stream_bytes'])))


if __name__=='__main__':main()
