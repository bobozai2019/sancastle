"""Observe one defined register after one instruction; original arithmetic/output retained.

Explicit instrumented snapshot diagnostic, never original in-place reference.
Final normal output must be checked against uninstrumented snapshot baseline.
"""
import argparse
import ctypes
import json
import re
import shutil
import struct
from pathlib import Path
from evidence_contract import identity
from make_snapshot_dxbc import sections
from probe_dxbc_rebuild import rebuild, blob_bytes
from lower_dxbc_glsl import audit_defined_lanes, generate, split_args, destination, LANES


def defined_at(text, instruction, register):
    audit_defined_lanes(text)
    defined=set()
    for number, tail in re.findall(r'^\s*(\d+):\s+([^\r\n]+)',text,re.M):
        op, operands=tail.split(' ',1) if ' ' in tail else (tail,'')
        # ld_structured opcode has a space inside its type annotation.
        if tail.startswith('ld_structured_indexable'):
            operands=tail.split(') ',1)[1]
        args=split_args(operands) if operands else []
        if op!='ret' and op!='store_structured':
            targets=args[:2] if op=='sincos' else args[:1]
            for target in targets:
                if target!='null':
                    reg, mask=destination(target)
                    if reg==register:defined.update(mask)
        if int(number)==instruction:
            if not defined:raise ValueError('TRACE_REGISTER_UNDEFINED')
            return ''.join(c for c in LANES if c in defined)
    raise ValueError('TRACE_INSTRUCTION_NOT_FOUND')


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--exact',type=Path,required=True)
    ap.add_argument('--adaptation',type=Path,required=True)
    ap.add_argument('--hash-helper',type=Path,required=True)
    ap.add_argument('--project',type=Path,required=True)
    ap.add_argument('--event',type=int,required=True)
    ap.add_argument('--instruction',type=int,required=True)
    ap.add_argument('--register',required=True)
    ap.add_argument('--capture',default='',help='Optional instruction:register.lane:outputlane comma list; same-invocation input/output trace')
    ap.add_argument('--velocity-depth-fold',action='store_true',help='Observe the explicit folded GLSL hypothesis while retaining original native arithmetic')
    ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    source=args.exact/f'e{args.event}_exact.asm';text=source.read_text()
    mask=defined_at(text,args.instruction,args.register)
    captures=[]
    for item in args.capture.split(',') if args.capture else []:
        number,operand,target=item.split(':');reg,lanes=destination(operand)
        if len(lanes)!=1 or len(target)!=1 or target not in LANES or lanes not in defined_at(text,int(number),reg):raise ValueError('INVALID_CAPTURE_LANE')
        captures.append(dict(instruction=int(number),register=reg,source_lane=lanes,target_lane=target))
    if len({c['target_lane'] for c in captures})!=len(captures):raise ValueError('DUPLICATE_CAPTURE_TARGET')
    adapted=json.loads((args.adaptation/'adaptation.json').read_text())
    parent=next(p for p in adapted['programs'] if p['event']==args.event)
    for key in ['adapted','adapted_asm']:
        if identity(parent[key]['path'])['sha256']!=parent[key]['sha256']:raise ValueError('ADAPTER_CHANGED')
    data=Path(parent['adapted']['path']).read_bytes()
    parts,part_index,header,prefix,code,decls,numbered=sections(data,Path(parent['adapted_asm']['path']).read_text())
    count=int(re.search(r'dcl_temps (\d+)',text)[1]);idx=count;capture=count+1
    if not re.fullmatch(r'r\d+',args.register) or int(args.register[1:])>=count:raise ValueError('TRACE_REGISTER_OUTSIDE_DECLARATION')
    temp_position=next(i for i,d in enumerate(decls) if d.startswith('dcl_temps'))
    prefix[temp_position]=[prefix[temp_position][0],count+2]
    uav_position=decls.index('dcl_uav_structured u0, 16')
    uav=list(prefix[uav_position]);uav[2]=1
    prefix=prefix[:uav_position+1]+[uav]+prefix[uav_position+1:]
    # Same independently decoded linear index as original e1484 instruction0.
    floor_data=(args.exact/'e1484.dxbc').read_bytes()
    _,_,_,_,floor_code,_,_=sections(floor_data,(args.exact/'e1484_exact.asm').read_text())
    index=list(floor_code[0]);index[2]=idx
    if len(index)!=8 or index[3:]!=[0x2001a,0x20800a,0,155,0x2000a]:raise ValueError('INDEX_TEMPLATE_CHANGED')
    init=[0x08000036,0x001000f2,capture,0x00004002,0,0,0,0]
    component_bits=sum(1<<LANES.index(c) for c in mask)
    copy=[0x05000036,0x00100002|(component_bits<<4),capture,0x00100e46,int(args.register[1:])]
    copies={args.instruction:[copy]}
    if captures:
        copies={}
        for c in captures:
            row=[0x05000036,0x00100002|(1<<(LANES.index(c['target_lane'])+4)),capture,0x0010000a|(LANES.index(c['source_lane'])<<4),int(c['register'][1:])]
            copies.setdefault(c['instruction'],[]).append(row)
    store=[0x090000a8,0x0011e0f2,1,0x0010000a,idx,0x00004001,0,0x00100e46,capture]
    new_code=[index,init];original_positions=[]
    for i,(row,(n,t)) in enumerate(zip(code,numbered)):
        if t.strip()=='ret':new_code.append(store)
        original_positions.append(len(new_code));new_code.append(row)
        new_code.extend(copies.get(int(n),[]))
    if sum(t.strip()=='ret' for _,t in numbered)!=1:raise ValueError('RET_SHAPE')
    if any(new_code[p]!=row for p,row in zip(original_positions,code)):raise ValueError('ARITHMETIC_CHANGED')
    words=header+[w for row in prefix+new_code for w in row];words[1]=len(words)
    new_parts=list(parts);new_parts[part_index]=(parts[part_index][0],struct.pack('<%dI'%len(words),*words))
    helper=json.loads((args.hash_helper/'hash_probe.json').read_text())
    if helper['verification_status']!='passed' or identity(helper['helper']['path'])['sha256']!=helper['helper']['sha256']:raise ValueError('HASH_HELPER_CHANGED')
    lib=ctypes.CDLL(helper['helper']['path']);fn=lib.container_hash;fn.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_void_p]
    result=rebuild(data,new_parts);payload=ctypes.create_string_buffer(result[20:]);digest=ctypes.create_string_buffer(16)
    fn(payload,len(result)-20,digest);result=result[:4]+digest.raw+result[20:]
    shader=out/f'e{args.event}_register_trace.dxbc';shader.write_bytes(result)
    d3d=ctypes.WinDLL('d3dcompiler_47.dll');dis=d3d.D3DDisassemble
    dis.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];dis.restype=ctypes.c_long
    buf=ctypes.create_string_buffer(result);blob=ctypes.c_void_p()
    if dis(buf,len(result),0x84,None,ctypes.byref(blob))<0:raise ValueError('TRACE_DISASSEMBLY_FAILED')
    assembly=blob_bytes(blob).rstrip(b'\0').decode('ascii');(out/'trace.asm').write_text(assembly)
    observed=re.findall(r'^\s*(\d+):\s+([^\r\n]+)',assembly,re.M)
    if any(observed[p][1]!=original[1] for p,original in zip(original_positions,numbered)):raise ValueError('TEXT_ARITHMETIC_CHANGED')
    glsl,record=generate(text,args.event,'fma','separate','snapshot','native','precise',(), 'none',args.velocity_depth_fold)
    declaration='layout(set=0,binding=5,std430) buffer DebugTrace {uvec4 observedCells[];};\n'
    glsl=glsl.replace('void main(){',declaration+'void main(){\n uvec4 observedRegister=uvec4(0u);')
    next_marker=' // DXBC '+str(args.instruction+1)+':'
    if glsl.count(next_marker)!=1:raise ValueError('GLSL_TRACE_POINT')
    if captures:
        for c in captures:
            marker=' // DXBC '+str(c['instruction']+1)+':'
            if glsl.count(marker)!=1:raise ValueError('GLSL_CAPTURE_POINT')
            glsl=glsl.replace(marker,' observedRegister.'+c['target_lane']+'='+c['register']+'.'+c['source_lane']+';\n'+marker)
    else:
        glsl=glsl.replace(next_marker,' observedRegister.'+mask+'='+args.register+'.'+mask+';\n'+next_marker)
    if glsl.count(' return;')!=1:raise ValueError('GLSL_RET_SHAPE')
    glsl=glsl.replace(' return;',' observedCells[gl_GlobalInvocationID.y*512u+gl_GlobalInvocationID.x]=observedRegister;\n return;')
    target=args.project/'shaders'/f'e{args.event}_snapshot.glsl';target.write_text(glsl,encoding='utf-8');shutil.copyfile(target,out/target.name)
    record.update(source=identity(source),shader=identity(target),trace=dict(instruction=args.instruction,register=args.register,defined_mask=mask,binding=5))
    (out/'lowering.json').write_text(json.dumps(dict(programs=[record]),indent=2),encoding='utf-8')
    report=dict(operation_status='complete',verification_status='passed',event=args.event,instruction=args.instruction,register=args.register,defined_mask=mask,
        parent=parent,program=identity(shader),glsl=identity(target),original_arithmetic_tokens_preserved=True,original_normal_output_store_preserved=True,
        captures=captures,added_instruction_count=3+sum(len(v) for v in copies.values()),original_instruction_count=len(code),traced_instruction_count=len(new_code),
        scope='Instrumented snapshot only; final normal output must match unobserved baseline before trace is interpreted as representative.')
    (out/'trace.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    for name in ['register_trace.py','make_snapshot_dxbc.py','probe_dxbc_rebuild.py','lower_dxbc_glsl.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='passed',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(event=args.event,instruction=args.instruction,mask=mask)))


if __name__=='__main__':main()
