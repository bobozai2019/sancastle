"""Explicit snapshot adaptation: redirect original structured UAV reads to readonly t2, preserve arithmetic."""
import argparse
import ctypes
import json
import re
import shutil
import struct
from pathlib import Path
from evidence_contract import identity
from probe_dxbc_rebuild import chunks, rebuild, blob_bytes


def token_rows(payload):
    words=list(struct.unpack('<%dI'%(len(payload)//4),payload))
    if words[1]!=len(words):raise ValueError('TOKEN_LENGTH')
    result=[];position=2
    while position<len(words):
        length=(words[position]>>24)&127
        if not length or position+length>len(words):raise ValueError('UNSUPPORTED_TOKEN_LENGTH')
        result.append(words[position:position+length]);position+=length
    return words[:2],result


def sections(data,assembly):
    parts=chunks(data);index=next(i for i,(tag,_) in enumerate(parts) if tag in [b'SHEX',b'SHDR'])
    header,rows=token_rows(parts[index][1])
    group=[i for i,row in enumerate(rows) if len(row)==4 and row[1:]==[32,32,1]]
    if len(group)!=1:raise ValueError('THREAD_LAYOUT')
    declarations=re.findall(r'^\s*(dcl_[^\r\n]+)',assembly,re.M)
    executable=re.findall(r'^\s*(\d+):\s+([^\r\n]+)',assembly,re.M)
    cut=group[0]+1
    if len(declarations)!=cut or len(executable)!=len(rows)-cut:raise ValueError('ASM_TOKEN_PAIRING')
    return parts,index,header,rows[:cut],rows[cut:],declarations,executable


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--exact',required=True,type=Path)
    ap.add_argument('--hash-helper',required=True,type=Path);ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    helper=json.loads((args.hash_helper/'hash_probe.json').read_text())
    if helper['verification_status']!='passed' or identity(helper['helper']['path'])['sha256']!=helper['helper']['sha256']:raise ValueError('HASH_HELPER_CHANGED')
    lib=ctypes.CDLL(helper['helper']['path']);hash_fn=lib.container_hash;hash_fn.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_void_p]
    def seal(data):
        payload=ctypes.create_string_buffer(data[20:]);digest=ctypes.create_string_buffer(16);hash_fn(payload,len(data)-20,digest)
        return data[:4]+digest.raw+data[20:]
    template=(args.exact/'e1484.dxbc').read_bytes();asm=(args.exact/'e1484_exact.asm').read_text()
    _,_,_,decls,_,names,_=sections(template,asm)
    resource=decls[names.index('dcl_resource_structured t0, 16')]
    if len(resource)!=4 or resource[2:]!=[0,16]:raise ValueError('SRV_DECLARATION_TEMPLATE')
    srv_type=(resource[1]>>12)&255
    d3d=ctypes.WinDLL('d3dcompiler_47.dll');dis=d3d.D3DDisassemble
    dis.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];dis.restype=ctypes.c_long
    programs=[]
    for event in [1484,1490,1495,1500,1537,1543]:
        source=args.exact/('e%d.dxbc'%event);source_asm=args.exact/('e%d_exact.asm'%event)
        data=source.read_bytes();parts,part_index,header,prefix,code,decl_names,numbered=sections(data,source_asm.read_text())
        if any(re.search(r'\bt2\b',s) for s in decl_names):raise ValueError('T2_ALREADY_USED')
        new_code=[];changes=[]
        for i,(row,(_,text)) in enumerate(zip(code,numbered)):
            changed=list(row)
            if text.startswith('ld_structured_indexable') and re.search(r', u0\.[xyzw]+$',text.strip()):
                if row[-1]!=0 or ((row[-2]>>12)&255)!=30:raise ValueError('UAV_READ_OPERAND_TEMPLATE')
                changed[-2]=(row[-2]&~(255<<12))|(srv_type<<12);changed[-1]=2
                changes.append(dict(instruction=i,original=text.strip(),original_words=row,adapted_words=changed))
            new_code.append(changed)
        if not changes:raise ValueError('NO_READS_REDIRECTED')
        declaration=list(resource);declaration[2]=2
        cb_position=next(i for i,s in enumerate(decl_names) if s.startswith('dcl_constantbuffer'))
        new_prefix=prefix[:cb_position+1]+[declaration]+prefix[cb_position+1:]
        words=header+[w for row in new_prefix+new_code for w in row];words[1]=len(words)
        new_parts=list(parts);new_parts[part_index]=(parts[part_index][0],struct.pack('<%dI'%len(words),*words))
        adapted=seal(rebuild(data,new_parts));file=out/('e%d_snapshot.dxbc'%event);file.write_bytes(adapted)
        buf=ctypes.create_string_buffer(adapted);blob=ctypes.c_void_p();hr=dis(buf,len(adapted),0x84,None,ctypes.byref(blob))
        if hr<0:raise ValueError('ADAPTED_DISASSEMBLY_FAILED')
        output_asm=blob_bytes(blob).rstrip(b'\0').decode('ascii');(out/('e%d_snapshot.asm'%event)).write_text(output_asm,encoding='ascii')
        observed=re.findall(r'^\s*(\d+):\s+([^\r\n]+)',output_asm,re.M)
        expected=[(n,re.sub(r', u0\.',', t2.',t) if any(c['instruction']==int(n) for c in changes) else t) for n,t in numbered]
        if observed!=expected:raise ValueError('NON_READ_INSTRUCTION_CHANGED')
        if len(re.findall(r'dcl_resource_structured t2, 16',output_asm))!=1 or re.search(r'ld_structured_indexable[^\r\n]*, u0\.',output_asm):raise ValueError('SNAPSHOT_READ_COVERAGE')
        programs.append(dict(event=event,original=identity(source),original_asm=identity(source_asm),adapted=identity(file),
            adapted_asm=identity(out/('e%d_snapshot.asm'%event)),read_changes=changes,arithmetic_instruction_text_exactly_preserved=True,
            instruction_count=len(numbered),mode='explicit_readonly_snapshot_adaptation',binding='Original water reads now t2 structured stride16; u0 destination only. Original CB/SRVs and indices/byte offsets/swizzles unchanged.'))
    for name in ['make_snapshot_dxbc.py','probe_dxbc_rebuild.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    report=dict(operation_status='complete',verification_status='passed',scope='Bytecode transformation audit only, not GPU/math or original in-place equivalence',
        hash_helper=identity(args.hash_helper/'hash_probe.json'),programs=programs)
    (out/'adaptation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='passed',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(programs=len(programs),redirected_reads=[len(p['read_changes']) for p in programs])))


if __name__=='__main__':main()
