"""Independent call-site cross-check and identity/memory negative probes."""
import argparse
import hashlib
import json
import struct
import subprocess
import sys
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('run',type=Path);a=p.parse_args()
original=a.run/'native_wait.dmp'
data=original.read_bytes()
unwind=json.loads((a.run/'native_unwound_15016.json').read_text())
disassembly=json.loads((a.run/'native_frame_disassembly.json').read_text())
functions={row['begin']:row for row in disassembly['functions']}
checks=[]
def tail_to(target, expected):
    function=functions.get(target)
    if function is None:return False
    instructions=function['instructions']
    jumps=[row for row in instructions if row['mnemonic'].startswith('j')]
    if len(jumps)!=1 or jumps[0]['mnemonic']!='jmp':return False
    jump=jumps[0]
    if not any(note.get('direct_target_rva')==expected for note in jump['notes']):return False
    before=[row for row in instructions if int(row['rva'],16)<int(jump['rva'],16)]
    if any(row['mnemonic']=='ret' for row in before):return False
    changes=[]
    for row in before:
        if row['operands'].startswith('rsp, ') and row['mnemonic'] in ['add','sub']:
            value=int(row['operands'].split(', ')[1],0)
            changes.append(value if row['mnemonic']=='add' else -value)
    return bool(changes) and sum(changes)==0
for i,frame in enumerate(unwind['frames'][1:],1):
    if frame['module']!='godot.windows.opt.tools.64.exe':continue
    function=functions[frame['runtime_function'][0]]
    pc=int(frame['rva'],16)
    call=next((row for row in function['instructions'] if int(row['rva'],16)+len(bytes.fromhex(row['bytes']))==pc),None)
    previous=unwind['frames'][i-1]
    valid=call is not None and call['mnemonic']=='call' and previous['return']==frame['pc']
    direct=next((note['direct_target_rva'] for note in call['notes'] if 'direct_target_rva' in note),None) if call else None
    if direct:
        valid=valid and (direct==previous['runtime_function'][0] or tail_to(direct,previous['runtime_function'][0]))
    checks.append({'frame':i,'return_rva':frame['rva'],'call':call,'pass':valid})
streams={}
u32=lambda o:struct.unpack_from('<I',data,o)[0]
for i in range(u32(8)):
    kind,size,rva=struct.unpack_from('<III',data,u32(12)+i*12);streams[kind]=(size,rva)
at=streams[4][1]
identity=bytearray(data)
for i in range(u32(at)):
    off=at+4+i*108;name_at=u32(off+20)
    name=data[name_at+4:name_at+4+u32(name_at)].decode('utf-16-le')
    if Path(name).name=='godot.windows.opt.tools.64.exe':
        struct.pack_into('<I',identity,off+16,u32(off+16)^1);break
else:raise AssertionError('Godot module missing')
truncated=bytearray(data)
at=streams[3][1]
for i in range(u32(at)):
    off=at+4+i*48
    if u32(off)==15016:
        stack_base=struct.unpack_from('<Q',data,off+24)[0]
        struct.pack_into('<I',truncated,off+32,16);break
else:raise AssertionError('target thread missing')
if 5 in streams:
    at=streams[5][1]
    for i in range(u32(at)):
        off=at+4+i*16
        if struct.unpack_from('<Q',data,off)[0]==stack_base:struct.pack_into('<I',truncated,off+8,16)
negative=[]
for label,contents in [('identity',identity),('truncated_stack',truncated)]:
    dump=a.run/f'native_negative_{label}.dmp'
    if dump.exists():assert dump.read_bytes()==contents
    else:
        with dump.open('xb') as f:f.write(contents)
    out=a.run/f'native_negative_{label}_unwind.json'
    done=subprocess.run([sys.executable,str(Path(__file__).with_name('unwind_native_dump.py')),str(dump),'--tid','15016','--output',str(out)],capture_output=True,text=True)
    assert done.returncode==0,done.stderr
    record=json.loads(out.read_text())
    if label=='identity':
        valid=not any(row['module']=='godot.windows.opt.tools.64.exe' for row in record['frames']) and any(not m['verified'] for m in record['modules'])
    else:
        valid=len(record['frames'])<len(unwind['frames']) and bool(record['read_failures'])
    negative.append({'case':label,'derived_from_sha256':hashlib.sha256(data).hexdigest(),'derived_sha256':hashlib.sha256(contents).hexdigest(),
                     'frames':len(record['frames']),'stop_reason':record['stop_reason'],'pass':valid})
result={'call_sites':checks,'negative_cases':negative,'pass':bool(checks) and all(row['pass'] for row in checks+negative),
        'scope':'direct/indirect call opcode consistency and fail-closed offline identity/stack coverage; private names are separate source inference'}
(a.run/'native_unwind_verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'call_sites':len(checks),'failed':[row for row in checks if not row['pass']],'negative':negative,'pass':result['pass']}))
raise SystemExit(0 if result['pass'] else 1)
