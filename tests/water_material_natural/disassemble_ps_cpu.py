"""Disassemble the confirmed visual PS bytecode with Windows' CPU-only compiler API."""
import ctypes
import hashlib
import json
from pathlib import Path
from ctypes import wintypes

ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'test_output/water_material_natural/t00_normal_recovery/event_6083_pixel_shader.bin'
out=ROOT/'test_output/water_material_natural/t03_optics_source'
out.mkdir(exist_ok=True)
data=source.read_bytes()
expected='6b7870c1b83924ba8a7319d3bae374933ecff0873caa5109f3c2e7d8338e9961'
assert hashlib.sha256(data).hexdigest()==expected
dll_path=Path('C:/Windows/System32/d3dcompiler_47.dll')
dll=ctypes.WinDLL(str(dll_path))
function=dll.D3DDisassemble
function.restype=ctypes.c_long
function.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint32,ctypes.c_char_p,ctypes.POINTER(ctypes.c_void_p)]
buffer=ctypes.create_string_buffer(data)
blob=ctypes.c_void_p()
status=function(buffer,len(data),0,None,ctypes.byref(blob))
report={'status_hresult':status,'source_shader':{'path':str(source),'bytes':len(data),'sha256':expected},
        'capture_sha256':'761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2',
        'selector':'E6083 PS ResourceId::3410; recovered in t00_normal_recovery',
        'tool_dll':{'path':str(dll_path),'bytes':dll_path.stat().st_size,'sha256':hashlib.sha256(dll_path.read_bytes()).hexdigest()},
        'command':'python D:/godot/project/sandcastle/tests/water_material_natural/disassemble_ps_cpu.py',
        'api':'D3DDisassemble flags0; no GPU replay or business code',
        'documentation':'https://learn.microsoft.com/en-us/windows/win32/api/d3dcompiler/nf-d3dcompiler-d3ddisassemble',
        'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'limitations':['Disassembly is derived visual shader instructions, not original HLSL.',
                       'Runtime constant bytes/units remain unconfirmed until separately recovered.']}
if status>=0 and blob:
    table=ctypes.cast(blob,ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    pointer=ctypes.WINFUNCTYPE(ctypes.c_void_p,ctypes.c_void_p)(table[3])(blob)
    size=ctypes.WINFUNCTYPE(ctypes.c_size_t,ctypes.c_void_p)(table[4])(blob)
    text=ctypes.string_at(pointer,size).rstrip(b'\0')
    target=out/'event_6083_pixel_disassembly.txt'
    target.write_bytes(text)
    report['export']={'path':str(target),'bytes':len(text),'sha256':hashlib.sha256(text).hexdigest()}
    ctypes.WINFUNCTYPE(ctypes.c_ulong,ctypes.c_void_p)(table[2])(blob)
    report['pass']=True
else:report['pass']=False
(out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
