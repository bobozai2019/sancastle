"""Read-only AMD64 StackWalk64 using captured memory and matched PE unwind tables.

No process is opened. No guessed stack words, synthetic memory, or private names.
Local image bytes supplement code/unwind metadata only after timestamp/size checks.
"""
import argparse
import bisect
import ctypes as c
from ctypes import wintypes as w
import hashlib
import json
import struct
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('dump', type=Path)
p.add_argument('--tid', type=int, required=True)
p.add_argument('--output', type=Path)
a = p.parse_args()
data = a.dump.read_bytes()
assert data[:4] == b'MDMP'
u32 = lambda b,o: struct.unpack_from('<I',b,o)[0]
u64 = lambda b,o: struct.unpack_from('<Q',b,o)[0]
streams = {}
for i in range(u32(data,8)):
    kind,size,rva = struct.unpack_from('<III',data,u32(data,12)+i*12)
    streams[kind] = (size,rva)
assert struct.unpack_from('<H',data,streams[7][1])[0] == 9
modules = []
at = streams[4][1]
for i in range(u32(data,at)):
    off = at+4+i*108
    name_at = u32(data,off+20)
    name = data[name_at+4:name_at+4+u32(data,name_at)].decode('utf-16-le')
    modules.append({'base':u64(data,off),'size':u32(data,off+8),'checksum':u32(data,off+12),
                    'timestamp':u32(data,off+16),'path':name})
memory = []
context = None
at = streams[3][1]
for i in range(u32(data,at)):
    off = at+4+i*48
    base,size,rva = struct.unpack_from('<QII',data,off+24)
    memory.append((base,data[rva:rva+size]))
    if u32(data,off) == a.tid:
        size,rva = struct.unpack_from('<II',data,off+40)
        context = data[rva:rva+size]
        stack_range = (base,base+len(memory[-1][1]))
if 5 in streams:
    at = streams[5][1]
    for i in range(u32(data,at)):
        base,size,rva = struct.unpack_from('<QII',data,at+4+i*16)
        memory.append((base,data[rva:rva+size]))
assert context is not None and len(context)>=1232, 'full AMD64 context required'

class Address(c.Structure):
    _fields_ = [('Offset',c.c_uint64),('Segment',c.c_ushort),('Mode',c.c_int)]
class KdHelp(c.Structure):
    _fields_ = [('Thread',c.c_uint64),('ThCallbackStack',w.DWORD),('ThCallbackBStore',w.DWORD),
                ('NextCallback',w.DWORD),('FramePointer',w.DWORD),('KiCallUserMode',c.c_uint64),
                ('KeUserCallbackDispatcher',c.c_uint64),('SystemRangeStart',c.c_uint64),
                ('KiUserExceptionDispatcher',c.c_uint64),('StackBase',c.c_uint64),('StackLimit',c.c_uint64),
                ('BuildVersion',w.DWORD),('RetpolineStubFunctionTableSize',w.DWORD),
                ('RetpolineStubFunctionTable',c.c_uint64),('RetpolineStubOffset',w.DWORD),
                ('RetpolineStubSize',w.DWORD),('Reserved0',c.c_uint64*2)]
class Frame(c.Structure):
    _fields_ = [(key,Address) for key in ['AddrPC','AddrReturn','AddrFrame','AddrStack','AddrBStore']]+[
        ('FuncTableEntry',c.c_void_p),('Params',c.c_uint64*4),('Far',w.BOOL),('Virtual',w.BOOL),
        ('Reserved',c.c_uint64*3),('KdHelp',KdHelp)]
assert c.sizeof(Address)==16 and c.sizeof(KdHelp)==112 and c.sizeof(Frame)==264

images, function_buffers, read_failures = {}, {}, []
manifest = json.loads((a.dump.parent/'manifest.json').read_text(encoding='utf-8-sig'))
manifest_hashes = {str(Path(row['path']).resolve()).lower():row['sha256'] for row in manifest}

def module_at(address):
    return next((m for m in modules if m['base']<=address<m['base']+m['size']),None)

def image(m):
    if m['path'] in images:
        return images[m['path']]
    result = {'path':m['path'],'verified':False}
    images[m['path']] = result
    try:
        b = Path(m['path']).read_bytes()
        pe = u32(b,0x3c)
        assert b[:2]==b'MZ' and b[pe:pe+4]==b'PE\0\0'
        opt = pe+24
        assert struct.unpack_from('<H',b,pe+4)[0]==0x8664 and struct.unpack_from('<H',b,opt)[0]==0x20b
        checks = {'timestamp':u32(b,pe+8)==m['timestamp'],'image_size':u32(b,opt+56)==m['size'],
                  'checksum':not m['checksum'] or u32(b,opt+64)==m['checksum']}
        digest = hashlib.sha256(b).hexdigest()
        recorded = manifest_hashes.get(str(Path(m['path']).resolve()).lower())
        if recorded:
            checks['recorded_file_sha256'] = digest==recorded
        result.update(checks=checks,sha256=digest)
        if not all(checks.values()):
            result['error']='module identity mismatch';return result
        sections = []
        section_at = opt+struct.unpack_from('<H',b,pe+20)[0]
        for i in range(struct.unpack_from('<H',b,pe+6)[0]):
            off = section_at+i*40
            sections.append((u32(b,off+12),u32(b,off+16),u32(b,off+20)))
        headers = u32(b,opt+60)
        def bytes_at(rva,size):
            if rva+size<=headers:
                return b[rva:rva+size]
            for va,raw_size,raw in sections:
                if va<=rva and rva+size<=va+raw_size:
                    return b[raw+rva-va:raw+rva-va+size]
            return None
        exception_rva,exception_size = struct.unpack_from('<II',b,opt+112+3*8)
        table = bytes_at(exception_rva,exception_size) if exception_size else b''
        assert table is not None and len(table)%12==0
        entries = list(struct.iter_unpack('<III',table))
        assert all(entries[i][0]<=entries[i+1][0] for i in range(len(entries)-1))
        result.update(verified=True,read=bytes_at,functions=entries,starts=[x[0] for x in entries])
    except (OSError,ValueError,AssertionError,struct.error) as error:
        result['error']=str(error)
    return result

Read = c.WINFUNCTYPE(w.BOOL,w.HANDLE,c.c_uint64,c.c_void_p,w.DWORD,c.POINTER(w.DWORD))
Functions = c.WINFUNCTYPE(c.c_void_p,w.HANDLE,c.c_uint64)
ModuleBase = c.WINFUNCTYPE(c.c_uint64,w.HANDLE,c.c_uint64)

@Read
def read_memory(_handle,address,destination,size,count):
    count[0]=0
    for base,b in memory:
        if base<=address and address+size<=base+len(b):
            value=b[address-base:address-base+size]
            c.memmove(destination,value,size);count[0]=size;return True
    m=module_at(address)
    if m:
        source=image(m)
        if source['verified']:
            value=source['read'](address-m['base'],size)
            if value is not None and len(value)==size:
                c.memmove(destination,value,size);count[0]=size;return True
    read_failures.append({'address':hex(address),'size':size})
    return False

def function_at(address):
    m=module_at(address)
    if not m:return None,None
    source=image(m)
    if not source['verified']:return m,None
    rva=address-m['base']
    index=bisect.bisect_right(source['starts'],rva)-1
    if index>=0 and source['functions'][index][0]<=rva<source['functions'][index][1]:
        return m,source['functions'][index]
    return m,None

@Functions
def functions(_handle,address):
    m,entry=function_at(address)
    if entry is None:return None
    key=(m['path'],entry[0])
    if key not in function_buffers:
        function_buffers[key]=c.create_string_buffer(struct.pack('<III',*entry))
    return c.addressof(function_buffers[key])

@ModuleBase
def module_base(_handle,address):
    m=module_at(address)
    return m['base'] if m else 0

dll_path=Path('C:/Program Files (x86)/Windows Kits/10/Debuggers/x64/dbghelp.dll')
dbg=c.WinDLL(str(dll_path))
dbg.StackWalk64.argtypes=[w.DWORD,w.HANDLE,w.HANDLE,c.POINTER(Frame),c.c_void_p,Read,Functions,ModuleBase,c.c_void_p]
dbg.StackWalk64.restype=w.BOOL
ctx=c.create_string_buffer(context)
frame=Frame()
for key,value in [('AddrPC',u64(context,248)),('AddrStack',u64(context,152)),('AddrFrame',u64(context,160))]:
    getattr(frame,key).Offset=value;getattr(frame,key).Mode=3
frames=[]
seen=set()
reason='frame_limit'
for i in range(64):
    failure_begin=len(read_failures)
    if not dbg.StackWalk64(0x8664,0x53414E44,a.tid,c.byref(frame),ctx,read_memory,functions,module_base,None):
        reason='StackWalk64 returned false';break
    pc,sp=frame.AddrPC.Offset,frame.AddrStack.Offset
    if not pc:
        reason='zero_return';break
    if (pc,sp) in seen:
        reason='cycle';break
    m,entry=function_at(pc)
    if not m or not image(m)['verified']:
        reason='unmapped_or_unverified_module';break
    if not stack_range[0]<=sp<=stack_range[1]:
        reason='outside_captured_thread_stack';break
    frames.append({'pc':hex(pc),'sp':hex(sp),'return':hex(frame.AddrReturn.Offset),
                   'module':Path(m['path']).name,'rva':hex(pc-m['base']),
                   'runtime_function':[hex(x) for x in entry] if entry else None,
                   'memory_read_failures_this_step':read_failures[failure_begin:]})
    seen.add((pc,sp))
    if len(read_failures)>failure_begin:
        reason='memory_missing_during_step';break
result={'dump':str(a.dump.resolve()),'dump_sha256':hashlib.sha256(data).hexdigest(),'tid':a.tid,
        'method':'AMD64 DbgHelp StackWalk64; captured stack and matched local PE code/unwind metadata callbacks',
        'frames':frames,'stop_reason':reason,'read_failures':read_failures,
        'modules':[ {k:v for k,v in info.items() if k not in ['read','functions','starts']} for info in images.values()],
        'dbghelp':{'path':str(dll_path),'sha256':hashlib.sha256(dll_path.read_bytes()).hexdigest()},
        'scope':'unwind frames, no private symbol names; inline calls and uncaptured memory are not reconstructed'}
out=a.output or a.dump.with_name('native_unwound_%d.json'%a.tid)
out.write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({k:result[k] for k in ['tid','frames','stop_reason','read_failures']}))
