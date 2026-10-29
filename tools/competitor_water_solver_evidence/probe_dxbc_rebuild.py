"""CPU-only container-edit compatibility probe; edited blobs are explicit adaptations, never originals."""
import argparse
import ctypes
import ctypes.wintypes as wt
import json
import re
import shutil
import struct
from pathlib import Path
from evidence_contract import identity


def blob_bytes(blob):
    table=ctypes.cast(blob,ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    pointer=ctypes.WINFUNCTYPE(ctypes.c_void_p,ctypes.c_void_p)(table[3])
    size=ctypes.WINFUNCTYPE(ctypes.c_size_t,ctypes.c_void_p)(table[4])
    release=ctypes.WINFUNCTYPE(wt.ULONG,ctypes.c_void_p)(table[2])
    try:return ctypes.string_at(pointer(blob),size(blob))
    finally:release(blob)


def chunks(data):
    if data[:4]!=b'DXBC' or struct.unpack_from('<I',data,24)[0]!=len(data):raise ValueError('CONTAINER_HEADER')
    count=struct.unpack_from('<I',data,28)[0];result=[]
    for index in range(count):
        offset=struct.unpack_from('<I',data,32+index*4)[0]
        size=struct.unpack_from('<I',data,offset+4)[0]
        if offset+8+size>len(data):raise ValueError('CHUNK_EXTENT')
        result.append((data[offset:offset+4],data[offset+8:offset+8+size]))
    return result


def rebuild(original,parts):
    result=bytearray(original[:32+len(parts)*4]);result[4:20]=bytes(16)
    for index,(tag,payload) in enumerate(parts):
        struct.pack_into('<I',result,32+index*4,len(result))
        result+=tag+struct.pack('<I',len(payload))+payload
    struct.pack_into('<I',result,24,len(result))
    return bytes(result)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',required=True,type=Path)
    ap.add_argument('--hash-helper',type=Path,help='Previously validated Microsoft checksum helper directory')
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    base=out.parent;source=base/'t06_exact_programs_20261025_v1/e1484.dxbc';original=source.read_bytes()
    asm=(base/'t06_exact_programs_20261025_v1/e1484_exact.asm').read_text()
    parts=chunks(original);code_index=next(i for i,(tag,_) in enumerate(parts) if tag in [b'SHEX',b'SHDR'])
    code=parts[code_index][1];words=list(struct.unpack('<%dI'%(len(code)//4),code))
    if words[1]!=len(words):raise ValueError('TOKEN_LENGTH')
    instructions=[];position=2
    while position<len(words):
        length=(words[position]>>24)&127
        if not length or position+length>len(words):raise ValueError('UNSUPPORTED_TOKEN_LENGTH')
        instructions.append((position,length,words[position:position+length]));position+=length
    groups=[i for i,(_,length,values) in enumerate(instructions) if length==4 and values[1:]==[32,32,1]]
    if len(groups)!=1:raise ValueError('THREAD_DECLARATION_NOT_UNIQUE')
    executable=instructions[groups[0]+1:]
    numbered=re.findall(r'^\s*(\d+):\s+([^\r\n]+)',asm,re.M)
    if len(executable)!=len(numbered):raise ValueError('TOKEN_DISASSEMBLY_PAIRING')
    target=next(int(n) for n,text in numbered if re.fullmatch(r'mov r\d+\.[xyzw], l\(0x00000000\)',text.strip()))
    offset,length,values=executable[target]
    changed=words[:offset+length]+values+words[offset+length:];changed[1]=len(changed)
    edited_parts=list(parts);edited_parts[code_index]=(parts[code_index][0],struct.pack('<%dI'%len(changed),*changed))
    edited=rebuild(original,edited_parts)
    header=Path('C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um/d3dcompiler.h')
    h=header.read_text();enum=h[h.index('typedef enum D3D_BLOB_PART'):];enum=enum[:enum.index('} D3D_BLOB_PART')]
    names=re.findall(r'^\s*(D3D_BLOB_\w+)',enum,re.M);part_id=names.index('D3D_BLOB_PRIVATE_DATA')
    dll=ctypes.WinDLL('d3dcompiler_47.dll');set_part=dll.D3DSetBlobPart
    set_part.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_int,wt.UINT,ctypes.c_void_p,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)];set_part.restype=ctypes.c_long
    disassemble=dll.D3DDisassemble;disassemble.argtypes=[ctypes.c_void_p,ctypes.c_size_t,wt.UINT,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];disassemble.restype=ctypes.c_long
    rows=[]
    seal=None
    if args.hash_helper:
        helper=json.loads((args.hash_helper/'hash_probe.json').read_text())
        if helper['verification_status']!='passed' or identity(helper['helper']['path'])['sha256']!=helper['helper']['sha256']:
            raise ValueError('HASH_HELPER_NOT_VERIFIED')
        hash_dll=ctypes.CDLL(helper['helper']['path']);hash_fn=hash_dll.container_hash
        hash_fn.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_void_p];hash_fn.restype=None
        def seal(data):
            payload=ctypes.create_string_buffer(data[20:]);digest=ctypes.create_string_buffer(16)
            hash_fn(payload,len(data)-20,digest)
            return data[:4]+digest.raw+data[20:]
    for name,data in [('metadata_only',original),('checksum_only',rebuild(original,parts)),('duplicate_idempotent_mov',edited)]:
        (out/(name+'_unsealed.dxbc')).write_bytes(data)
        unsealed=identity(out/(name+'_unsealed.dxbc'))
        if seal:
            data=seal(data);(out/(name+'_sealed.dxbc')).write_bytes(data)
        source_buffer=ctypes.create_string_buffer(data);private=ctypes.create_string_buffer(b'EXPLICIT_ADAPTATION_NOT_ORIGINAL');blob=ctypes.c_void_p()
        result=set_part(source_buffer,len(data),part_id,0,private,len(private.raw),ctypes.byref(blob))
        row=dict(case=name,unsealed=unsealed,input=identity(out/(name+('_sealed' if seal else '_unsealed')+'.dxbc')),hresult=result)
        if result>=0 and blob.value:
            rebuilt=blob_bytes(blob);file=out/(name+'.dxbc');file.write_bytes(rebuilt)
            payloads=[p for tag,p in chunks(rebuilt) if tag in [b'SHEX',b'SHDR']]
            row.update(output=identity(file),shader_code_preserved=payloads==[code if name!='duplicate_idempotent_mov' else edited_parts[code_index][1]],checksum_hex=rebuilt[4:20].hex())
            buf=ctypes.create_string_buffer(rebuilt);dis=ctypes.c_void_p();hr=disassemble(buf,len(rebuilt),0x84,None,ctypes.byref(dis));row['disassemble_hresult']=hr
            if hr>=0 and dis.value:
                text=blob_bytes(dis).rstrip(b'\0').decode('ascii');(out/(name+'.asm')).write_text(text,encoding='ascii');row['instructions']=len(re.findall(r'^\s*\d+:',text,re.M))
        rows.append(row)
    for name in ['probe_dxbc_rebuild.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    errors=[]
    if not all(r.get('shader_code_preserved') and r.get('disassemble_hresult')==0 for r in rows):errors.append('CONTAINER_REBUILD_UNCONFIRMED')
    if rows[-1].get('instructions')!=len(numbered)+1:errors.append('IDEMPOTENT_INSERT_NOT_CONFIRMED')
    report=dict(operation_status='complete',verification_status='passed' if not errors else 'failed',
        scope='CPU container-edit/disassembly compatibility only. No GPU pipeline, arithmetic or Godot validation. Derived blobs must never be called unmodified original DXBC.',
        source=identity(source),sdk_header=identity(header),hash_helper=identity(args.hash_helper/'hash_probe.json') if args.hash_helper else None,private_data_part=part_id,duplicated_original_instruction=numbered[target],cases=rows,errors=errors)
    (out/'probe.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],errors=errors,artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'],cases=[dict(case=r['case'],hresult=r['hresult'],instructions=r.get('instructions')) for r in rows],errors=errors)))
    raise SystemExit(bool(errors))


if __name__=='__main__':main()
