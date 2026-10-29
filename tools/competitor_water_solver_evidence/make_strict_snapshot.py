"""Explicit counterfactual: disable DXBC refactoring permission, retaining snapshot math/access tokens."""
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


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['adaptation','header','hash-helper','output']:ap.add_argument('--'+name,required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    header=args.header.read_text()
    if not re.search(r'#define D3D10_SB_GLOBAL_FLAG_REFACTORING_ALLOWED\s+\(1<<11\)',header):raise ValueError('UNVERIFIED_FLAG_DEFINITION')
    helper=json.loads((args.hash_helper/'hash_probe.json').read_text())
    if helper['verification_status']!='passed' or identity(helper['helper']['path'])['sha256']!=helper['helper']['sha256']:raise ValueError('HASH_HELPER_CHANGED')
    lib=ctypes.CDLL(helper['helper']['path']);fn=lib.container_hash;fn.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_void_p]
    d3d=ctypes.WinDLL('d3dcompiler_47.dll');dis=d3d.D3DDisassemble
    dis.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)];dis.restype=ctypes.c_long
    parent=json.loads((args.adaptation/'adaptation.json').read_text());programs=[]
    for p in parent['programs']:
        for key in ['adapted','adapted_asm']:
            if identity(p[key]['path'])['sha256']!=p[key]['sha256']:raise ValueError('SNAPSHOT_PARENT_CHANGED')
        data=Path(p['adapted']['path']).read_bytes();assembly=Path(p['adapted_asm']['path']).read_text()
        parts,pi,head,prefix,code,decls,numbered=sections(data,assembly)
        position=decls.index('dcl_globalFlags refactoringAllowed');row=prefix[position]
        if row!=[0x0100086a]:raise ValueError('GLOBAL_FLAGS_TEMPLATE_CHANGED')
        changed=[row[0]&~(1<<11)];prefix[position]=changed
        words=head+[w for r in prefix+code for w in r];words[1]=len(words)
        replacement=list(parts);replacement[pi]=(parts[pi][0],struct.pack('<%dI'%len(words),*words))
        new=rebuild(data,replacement);payload=ctypes.create_string_buffer(new[20:]);digest=ctypes.create_string_buffer(16);fn(payload,len(new)-20,digest)
        new=new[:4]+digest.raw+new[20:];target=out/f'e{p["event"]}_snapshot.dxbc';target.write_bytes(new)
        buf=ctypes.create_string_buffer(new);blob=ctypes.c_void_p()
        if dis(buf,len(new),0x84,None,ctypes.byref(blob))<0:raise ValueError('STRICT_DISASSEMBLY_FAILED')
        new_asm=blob_bytes(blob).rstrip(b'\0').decode('ascii');asm_target=out/f'e{p["event"]}_snapshot.asm';asm_target.write_text(new_asm)
        if re.findall(r'^\s*(\d+):\s+([^\r\n]+)',new_asm,re.M)!=numbered:raise ValueError('EXECUTABLE_INSTRUCTION_CHANGED')
        if 'refactoringAllowed' in new_asm:raise ValueError('FLAG_NOT_CLEARED')
        record=dict(p);record.update(snapshot_parent=p['adapted'],snapshot_parent_asm=p['adapted_asm'],adapted=identity(target),adapted_asm=identity(asm_target),
            mode='explicit_readonly_snapshot_no_refactoring_counterfactual',global_flag_change=dict(before=hex(row[0]),after=hex(changed[0]),mask=hex(1<<11)),
            scope='Only global refactoringAllowed declaration cleared; all executable instruction words preserved. Not original compiler policy or in-place behavior.')
        programs.append(record)
    for name in ['make_strict_snapshot.py','make_snapshot_dxbc.py','probe_dxbc_rebuild.py','evidence_contract.py']:shutil.copyfile(Path(__file__).parent/name,out/name)
    shutil.copyfile(args.header,out/args.header.name)
    report=dict(operation_status='complete',verification_status='passed',parent=identity(args.adaptation/'adaptation.json'),header_source=identity(args.header),programs=programs,
        scope='CPU editing integrity only. Explicit stricter policy diagnostic; no math/GPU/original claim.')
    (out/'adaptation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status='passed',artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(programs=len(programs),executable_tokens_preserved=True)))


if __name__=='__main__':main()
