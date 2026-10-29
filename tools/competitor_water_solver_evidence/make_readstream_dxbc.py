"""Record frozen water-kernel UAV loads, or replay their post-swizzle bits.

Instrumented/adapted program, not unmodified original execution. Original arithmetic,
thread geometry, u0 alias and stores remain. Added u1 stores can perturb scheduling.
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
from probe_dxbc_rebuild import rebuild,blob_bytes
from lower_dxbc_glsl import split_args,destination,LANES,audit_defined_lanes


def mov(reg,lane,source):return [((3+len(source))<<24)|0x36,0x00100002|(1<<(4+LANES.index(lane))),reg,*source]
def imm(value):return [0x00004001,value]
def temp(reg,lane):return [0x0010000a|(LANES.index(lane)<<4),reg]
def add_index(reg,offset):return [0x0700001e,0x00100022,reg,*temp(reg,'x'),*imm(offset)]
def store(index_reg,value_reg):return [0x090000a8,0x0011e0f2,1,*temp(index_reg,'y'),*imm(0),0x00100e46,value_reg]
def zero(reg):return [0x08000036,0x001000f2,reg,0x00004002,0,0,0,0]


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['exact','hash-helper','output']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--event',type=int,choices=[1484,1490,1495,1500,1537,1543],default=1490)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    event=args.event;source=args.exact/f'e{event}.dxbc';asm=args.exact/f'e{event}_exact.asm';data=source.read_bytes();text=asm.read_text();audit_defined_lanes(text)
    export=json.loads((args.exact/'manifest.json').read_text())
    for name in {f'e{event}.dxbc',f'e{event}_exact.asm','e1484.dxbc','e1484_exact.asm'}:
        expected=next(a for a in export['artifacts'] if Path(a['path']).name==name)
        actual=identity(args.exact/name)
        if actual['sha256']!=expected['sha256'] or actual['size_bytes']!=expected['size_bytes']:raise ValueError('SOURCE_EXPORT_IDENTITY_CHANGED:'+name)
    parts,part_index,header,prefix,code,decls,numbered=sections(data,text)
    expected_instructions={1484:97,1490:163,1495:125,1500:100,1537:131,1543:93}
    if len(code)!=expected_instructions[event]:raise ValueError('FROZEN_PROGRAM_LAYOUT')
    count=int(re.search(r'dcl_temps (\d+)',text)[1]);index_reg=count;value_reg=count+1;reads=[]
    for row,(n,line) in zip(code,numbered):
        if not line.startswith('ld_structured'):continue
        operands=split_args(line.split(') ',1)[1]);reg,mask=destination(operands[0])
        if not operands[3].startswith('u0.'):continue
        if len(row)!=11 or row[7]!=0x4001:raise ValueError('LOAD_LAYOUT')
        reads.append(dict(instruction=int(n),destination=reg,mask=mask,mask_bits=sum(1<<LANES.index(c) for c in mask),index=operands[1],offset=row[8],
            original=line,original_words=row,slot=len(reads)))
    read_count=1 if event in [1484,1537] else 5
    if len(reads)!=read_count:raise ValueError('FROZEN_WATER_READ_COUNT')
    floor=(args.exact/'e1484.dxbc').read_bytes();_,_,_,floor_prefix,floor_code,floor_decls,_=sections(floor,(args.exact/'e1484_exact.asm').read_text())
    linear=list(floor_code[0]);linear[2]=index_reg
    if linear[3:]!=[0x2001a,0x20800a,0,155,0x2000a]:raise ValueError('LINEAR_INDEX_TEMPLATE')
    srv=list(floor_prefix[floor_decls.index('dcl_resource_structured t0, 16')]);srv[2]=2
    libmeta=json.loads((args.hash_helper/'hash_probe.json').read_text())
    if libmeta['verification_status']!='passed' or identity(libmeta['helper']['path'])['sha256']!=libmeta['helper']['sha256']:raise ValueError('HASH_HELPER_CHANGED')
    lib=ctypes.CDLL(libmeta['helper']['path']);fn=lib.container_hash;fn.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_void_p]
    dis=ctypes.WinDLL('d3dcompiler_47.dll').D3DDisassemble;dis.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];dis.restype=ctypes.c_long
    programs=[]
    for mode in ['capture','replay']:
        declarations=[list(r) for r in prefix];declarations[decls.index('dcl_temps '+str(count))][1]=count+2
        uav_pos=decls.index('dcl_uav_structured u0, 16');uav=list(prefix[uav_pos]);uav[2]=1
        declarations.insert(uav_pos+1,uav)
        if mode=='replay':declarations.insert(next(i for i,d in enumerate(decls) if d.startswith('dcl_constantbuffer'))+1,srv)
        # r9.x is the first uint4 record for this invocation; ten uint4s per cell.
        base=[0x09000023,0x00100012,index_reg,*temp(index_reg,'x'),*imm(read_count*2),*imm(0)]
        new=[linear,base];positions=[];patches=[]
        for row,(n,line) in zip(code,numbered):
            read=next((r for r in reads if r['instruction']==int(n)),None)
            changed=list(row)
            if read:
                # Save the index before the load can overwrite its original register.
                new.extend([mov(value_reg,'x',row[5:7]),mov(value_reg,'y',imm(read['offset'])),mov(value_reg,'z',imm(read['mask_bits'])),mov(value_reg,'w',imm(int(n))),add_index(index_reg,read['slot']*2),store(index_reg,value_reg)])
                if mode=='replay':
                    new.append(add_index(index_reg,read['slot']*2+1))
                    changed[5:7]=temp(index_reg,'y');changed[7:9]=imm(0)
                    changed[-2]=(changed[-2]&~0x000fffff)|0x00007e46;changed[-1]=2
                    patches.append(dict(instruction=int(n),original=row,adapted=changed))
            positions.append(len(new));new.append(changed)
            if read:
                new.extend([zero(value_reg),[0x05000036,0x00100002|(read['mask_bits']<<4),value_reg,0x00100e46,int(read['destination'][1:])]])
                if mode=='capture':new.append(add_index(index_reg,read['slot']*2+1))
                new.append(store(index_reg,value_reg))
        for i,(row,(n,line)) in enumerate(zip(code,numbered)):
            if mode=='capture' or not any(p['instruction']==int(n) for p in patches):
                if new[positions[i]]!=row:raise ValueError('ORIGINAL_EXECUTABLE_TOKEN_CHANGED')
        words=header+[w for r in declarations+new for w in r];words[1]=len(words);new_parts=list(parts);new_parts[part_index]=(parts[part_index][0],struct.pack('<%dI'%len(words),*words))
        result=rebuild(data,new_parts);payload=ctypes.create_string_buffer(result[20:]);digest=ctypes.create_string_buffer(16);fn(payload,len(result)-20,digest);result=result[:4]+digest.raw+result[20:]
        target=out/f'e{event}_{mode}.dxbc';target.write_bytes(result);buf=ctypes.create_string_buffer(result);blob=ctypes.c_void_p()
        if dis(buf,len(result),0x84,None,ctypes.byref(blob))<0:raise ValueError('INSTRUMENTED_DISASSEMBLY_FAILED')
        result_asm=blob_bytes(blob).rstrip(b'\0').decode('ascii');asm_target=out/f'e{event}_{mode}.asm';asm_target.write_text(result_asm)
        observed=re.findall(r'^\s*(\d+):\s+([^\r\n]+)',result_asm,re.M)
        for pos,(original_number,line) in zip(positions,numbered):
            if mode=='capture' or not any(p['instruction']==int(original_number) for p in patches):
                if observed[pos][1]!=line:raise ValueError('ORIGINAL_TEXT_SUBSEQUENCE_CHANGED')
        if mode=='replay':
            loads=[t for _,t in observed if t.startswith('ld_structured') and ', t2.' in t]
            if len(loads)!=read_count or any(not t.endswith('t2.xyzw') for t in loads):raise ValueError('REPLAY_LOAD_LAYOUT')
        programs.append(dict(mode=mode,program=identity(target),assembly=identity(asm_target),original_positions=positions,changed_loads=patches,instructions=len(new),original_arithmetic_and_store_words_preserved=True,
            original_u0_reads_preserved=mode=='capture',scope='Instrumented original u0 alias' if mode=='capture' else 'Fixed post-swizzle stream substitution with metadata recording'))
    report=dict(operation_status='complete',verification_status='passed',event=event,parent=identity(source),parent_asm=identity(asm),programs=programs,reads=reads,read_count=read_count,stream_bytes=131072*read_count*2*16,
        layout='Per linear cell: read_count ordered pairs of uint4. Pair0=(original computed index, byte offset, valid destination-lane mask, original instruction). Pair1=post-swizzle loaded destination bits with unused lanes zero.',
        criterion='Diagnostic must replay each captured normal output and all metadata exactly. Not a universal schedule bound; no G02/G5 claim from container audit.',
        perturbation='Additional u1 writes, two temporaries, changed register allocation and scheduling; refactoringAllowed retained.')
    (out/'adaptation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    for name in ['make_readstream_dxbc.py','make_snapshot_dxbc.py','probe_dxbc_rebuild.py','lower_dxbc_glsl.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='passed',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(event=event,programs=2,reads=read_count,stream_bytes=report['stream_bytes'])))


if __name__=='__main__':main()
