"""Disassemble only Godot functions present in the verified offline unwind."""
import argparse
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('unwind', type=Path)
p.add_argument('--wheel-dir', type=Path, required=True)
p.add_argument('--extra-rva', action='append', default=[], type=lambda value:int(value,0))
a = p.parse_args()
wheel = a.wheel_dir/'capstone-5.0.9-py3-none-win_amd64.whl'
assert hashlib.sha256(wheel.read_bytes()).hexdigest()=='732cedbbb56d42e723f14d7af6387f1454194a820b4b96b56d1e53f865ef85d0'
runtime = a.wheel_dir/'runtime'
runtime.mkdir(exist_ok=True)
with zipfile.ZipFile(wheel) as archive:
    for member in archive.namelist():
        target=(runtime/member).resolve()
        assert target.is_relative_to(runtime.resolve())
    archive.extractall(runtime)
sys.path.insert(0,str(runtime.resolve()))
import capstone
from capstone.x86 import X86_OP_MEM,X86_OP_IMM,X86_REG_RIP

record=json.loads(a.unwind.read_text(encoding='utf-8'))
module=next(row for row in record['modules'] if Path(row['path']).name=='godot.windows.opt.tools.64.exe')
b=Path(module['path']).read_bytes()
assert hashlib.sha256(b).hexdigest()==module['sha256'] and module['verified']
u32=lambda o:struct.unpack_from('<I',b,o)[0]
u64=lambda o:struct.unpack_from('<Q',b,o)[0]
pe=u32(0x3c);opt=pe+24;image_base=u64(opt+24)
section_at=opt+struct.unpack_from('<H',b,pe+20)[0]
sections=[(u32(section_at+i*40+12),u32(section_at+i*40+16),u32(section_at+i*40+20))
          for i in range(struct.unpack_from('<H',b,pe+6)[0])]
def offset(rva):
    if 0<=rva<u32(opt+60):return rva
    return next((raw+rva-va for va,size,raw in sections if va<=rva<va+size),None)
def string(rva):
    off=offset(rva)
    if off is None:return None
    value=b[off:off+256].split(b'\0',1)[0]
    if len(value)>=6 and all(32<=x<127 or x in [9,10,13] for x in value):return value.decode('ascii')
    return None
iat={}
imports=u32(opt+112+8)
at=offset(imports)
if at is not None:
    while any(b[at:at+20]):
        lookup=u32(at) or u32(at+16)
        dll=string(u32(at+12));first=u32(at+16)
        index=0
        while u64(offset(lookup)+index*8):
            entry=u64(offset(lookup)+index*8)
            name=('#%d'%(entry&0xffff)) if entry>>63 else string(entry+2)
            iat[first+index*8]=(dll or '?')+'.'+(name or '?')
            index+=1
        at+=20
md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64);md.detail=True
functions={}
selected=list(record['frames'])
if a.extra_rva:
    exception_rva,exception_size=struct.unpack_from('<II',b,opt+112+3*8)
    entries=list(struct.iter_unpack('<III',b[offset(exception_rva):offset(exception_rva)+exception_size]))
    for rva in a.extra_rva:
        entry=next((entry for entry in entries if entry[0]<=rva<entry[1]),None)
        assert entry is not None and entry[1]-entry[0]<=4096
        selected.append({'module':'godot.windows.opt.tools.64.exe','runtime_function':[hex(x) for x in entry]})
for frame in selected:
    if frame['module']!='godot.windows.opt.tools.64.exe' or not frame['runtime_function']:continue
    begin,end,unwind=[int(x,16) for x in frame['runtime_function']]
    if begin in functions:continue
    assert end-begin<=65536
    off=offset(begin);assert off is not None
    rows=[]
    for ins in md.disasm(b[off:off+end-begin],begin):
        notes=[]
        for operand in ins.operands:
            if operand.type==X86_OP_MEM and operand.mem.base==X86_REG_RIP:
                target=ins.address+ins.size+operand.mem.disp
                if target in iat:notes.append({'import':iat[target],'iat_rva':hex(target)})
                text=string(target)
                if text:notes.append({'ascii_reference':text,'rva':hex(target)})
                target_off=offset(target)
                if target_off is not None and target_off+8<=len(b):
                    address=u64(target_off)
                    text=string(address-image_base)
                    if text:notes.append({'pointer_ascii_reference':text,'rva':hex(address-image_base)})
            elif operand.type==X86_OP_IMM and ins.mnemonic in ['call','jmp']:
                notes.append({'direct_target_rva':hex(operand.imm)})
        rows.append({'rva':hex(ins.address),'bytes':ins.bytes.hex(),'mnemonic':ins.mnemonic,
                     'operands':ins.op_str,'notes':notes})
    functions[begin]={'begin':hex(begin),'end':hex(end),'unwind_rva':hex(unwind),'instructions':rows}
out=a.unwind.with_name('native_frame_disassembly.json')
result={'source':str(a.unwind.resolve()),'exe':module['path'],'exe_sha256':module['sha256'],
        'capstone_version':capstone.__version__,'wheel_sha256':hashlib.sha256(wheel.read_bytes()).hexdigest(),
        'functions':list(functions.values()),'extra_target_rvas':[hex(x) for x in a.extra_rva],
        'scope':'actual unwound Godot functions and explicit bounded return-link targets only; imports/ASCII references, no inferred private names'}
out.write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'output':str(out),'function_count':len(functions),'ranges':[(v['begin'],v['end']) for v in functions.values()]}))
