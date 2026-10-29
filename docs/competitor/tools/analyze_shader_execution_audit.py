"""Validate captured evidence and count static DXBC instructions, never GPU cycles.

python .../analyze_shader_execution_audit.py INPUT_MANIFEST NEW_OUTPUT_DIRECTORY
"""
import collections
import ctypes
import hashlib
import json
import math
import re
import struct
import sys
from pathlib import Path

MANIFEST = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
assert str(OUT).isascii()
OUT.mkdir(parents=True, exist_ok=False)

def identity(p):
    return dict(path=p.as_posix(), bytes=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest())

def verify(entry):
    found = identity(Path(entry['path']))
    assert found['bytes'] == entry['bytes'] and found['sha256'] == entry['sha256'], entry['path']

source = json.loads(MANIFEST.read_text('utf-8'))
assert source['pass'] and not source['errors']
for entry in [source['source'], source['script'], source['tool']['executable'], source['selection'],
              source['actions'], source['resources'], *source['exports']]:
    verify(entry)

dll_path = Path('C:/Windows/System32/d3dcompiler_47.dll')
dll = ctypes.WinDLL(str(dll_path))
fn = dll.D3DDisassemble
fn.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint, ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
fn.restype = ctypes.c_long

def hex_disassembly(raw):
    src = ctypes.create_string_buffer(raw)
    blob = ctypes.c_void_p()
    status = fn(src, len(raw), 0xa0, None, ctypes.byref(blob))
    assert status >= 0, status
    vt = ctypes.cast(blob, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    ptr = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(vt[3])
    size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(vt[4])
    release = ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(vt[2])
    try:
        return ctypes.string_at(ptr(blob), size(blob)).rstrip(b'\0')
    finally:
        release(blob)

labels = {1472:'Ground.VelocityIntegration',1478:'Ground.HeightIntegration',1484:'Water.UpdateFloor',
          1490:'Water.VelocityIntegration',1495:'Water.HeightIntegration',1500:'Water.Advection',
          1537:'Water.UpdateAmount',1543:'Water.UpdateTangent',1550:'Foam.Update',
          1555:'Secondary surface-particle update (package name not matched)',1561:'Ground/water-driven particle update',
          1566:'Gravel.Update',1571:'Plant.Update (mechanical scope only)',1634:'Foam visibility/indirect lists',
          1640:'Readback.Update',3503:'Unity MipGen2DCS',3861:'Ground packed obstacle-field update',
          3867:'Height-field directional lighting',3872:'Four-neighbor lighting filter',
          5006:'Sand surface',6083:'Water surface',6196:'Foam instances'}

unique = {}
for event in source['events']:
    for stage, s in event['stages'].items():
        digest = s['bytecode']['sha256']
        if digest not in unique:
            asm = Path(s['disassembly']['path']).read_text('utf-8')
            lines = re.findall(r'^\s*\d+:\s+(.+)$', asm, re.M)
            ops = collections.Counter(line.split()[0] for line in lines)
            shared_names = re.findall(r'dcl_tgsm_\w+\s+(\w+)', asm)
            def shared(line):
                return any(re.search(r'\b' + re.escape(n) + r'\b', line) for n in shared_names)
            loads = [x for x in lines if x.startswith('ld')]
            stores = [x for x in lines if x.startswith('store')]
            temps = re.search(r'dcl_temps (\d+)', asm)
            hex_path = OUT / ('e%d_%s.hex.asm' % (event['event'], stage))
            hex_path.write_bytes(hex_disassembly(Path(s['bytecode']['path']).read_bytes()))
            unique[digest] = dict(label=labels.get(event['event'],'Unclassified'),stage=stage,events=[],
                                  bytecode=s['bytecode'],disassembly=s['disassembly'],hex_disassembly=identity(hex_path),
                                  threads=s['threads'],static_instructions=len(lines),virtual_vector_temps=int(temps[1]) if temps else 0,
                                  global_load_sites=sum(not shared(x) for x in loads),shared_load_sites=sum(shared(x) for x in loads),
                                  global_store_sites=sum(not shared(x) for x in stores),shared_store_sites=sum(shared(x) for x in stores),
                                  sample_sites=sum(v for k,v in ops.items() if k.startswith('sample')),
                                  sync_sites=sum(v for k,v in ops.items() if k.startswith('sync')),
                                  atomic_sites=sum(v for k,v in ops.items() if 'atomic' in k),loops=ops['loop'],
                                  group_shared_declarations=[x.strip() for x in asm.splitlines() if 'dcl_tgsm_' in x],
                                  opcode_histogram=dict(ops))
        unique[digest]['events'].append(event['event'])

params = {}
for eid, rows in {3867:[138,139],3503:[0,1],3510:[0,1],1550:[138,152],1555:[138,152],1634:[138],1640:[139,141]}.items():
    if not any(e['event']==eid for e in source['events']):
        continue
    e = next(e for e in source['events'] if e['event']==eid)
    data = Path(e['stages']['cs']['constants'][0]['raw']['path']).read_bytes()
    params[str(eid)] = {}
    for row in rows:
        n = min(4, len(data)//4-row*4)
        ints = struct.unpack_from('<'+'I'*n,data,row*16)
        floats = struct.unpack_from('<'+'f'*n,data,row*16)
        params[str(eid)][str(row)] = dict(offset=row*16, uint=list(ints), float=[v if math.isfinite(v) else str(v) for v in floats])

actions = json.loads(Path(source['actions']['path']).read_text('utf-8'))
cs_events = [e for e in source['events'] if 'cs' in e['stages']]
report = dict(source_manifest=identity(MANIFEST),script=identity(Path(__file__).resolve()),disassembler=identity(dll_path),
              command='python '+str(Path(__file__).resolve())+' '+str(MANIFEST)+' '+str(OUT),
              pass_all_input_hashes=True, unique_shaders=list(unique.values()),runtime_parameters=params,
              counts=dict(action_rows=len(actions),dispatch_actions=sum(a['dispatch'] for a in actions),
                          draw_action_rows=sum(not a['dispatch'] for a in actions),selected_events=len(source['events']),
                          selected_stages=sum(len(e['stages']) for e in source['events']),
                          unique_compute=sum(s['stage']=='cs' for s in unique.values()),
                          unique_graphics=sum(s['stage']!='cs' for s in unique.values()),
                          declared_compute_invocations=sum(math.prod(e['groups'])*math.prod(e['stages']['cs']['threads']) for e in cs_events)),
              limitations=['Static DXBC, not final GPU ISA, cycles, occupancy, or runtime cache traffic.',
                           'Load/store counts are instruction sites, not bytes, texel requests, or executed operations.',
                           'Branches, early returns, dynamic loops, vector widths and texture filtering change executed cost.',
                           'Virtual vector temporaries are not physical GPU registers.',
                           'Draw action rows are not unique meshes/materials and may include indirect parent/child action representation.'])
(OUT/'analysis.json').write_text(json.dumps(report,indent=2,ensure_ascii=False,allow_nan=False),encoding='utf-8')
print(json.dumps(report['counts']))
for s in unique.values():
    print(s['events'],s['stage'],s['static_instructions'],s['global_load_sites'],s['global_store_sites'],s['sample_sites'],s['shared_load_sites'],s['shared_store_sites'],s['sync_sites'],s['loops'])
