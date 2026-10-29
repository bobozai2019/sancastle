"""Negative controls for round-four representation and comparison tooling."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import zipfile
from compare_variant_states import compare
from layout_contract import pack, split, normalize, differences, SCALAR_BYTES


def main(output):
    output.mkdir(parents=True, exist_ok=False)
    checks = {}
    x = struct.pack('<8I', 0, 0x80000000, 0x3f800000, 0xbf800000,
                    1, 0x7f7fffff, 0x7fc12345, 0x7f800000) * (SCALAR_BYTES // 32)
    z = x[4:] + x[:4]
    packed = pack(x, z)
    checks['bit_roundtrip'] = split(packed) == (x, z)
    checks['spare_independent'] = pack(z, x) != packed
    for name, function in [('short_x', lambda: pack(x[:-1], z)), ('short_z', lambda: pack(x, z[:-1])),
                           ('short_packed', lambda: split(packed[:-1])), ('long_packed', lambda: split(packed+b'0'))]:
        try:
            function(); checks[name] = False
        except ValueError:
            checks[name] = True
    scalar = {'fixture/00/momentum_x_0.bin': x, 'fixture/00/momentum_z_0.bin': z,
              'fixture/00/momentum_x_1.bin': z, 'fixture/00/momentum_z_1.bin': x,
              'fixture/00/control.bin': bytes(128)}
    rg = {'fixture/00/momentum_0.bin': packed, 'fixture/00/momentum_1.bin': pack(z,x),
          'fixture/00/control.bin': bytes(128)}
    checks['scalar_packed_equivalent'] = normalize(scalar)[0] == normalize(rg)[0]
    swapped = dict(rg); swapped['fixture/00/momentum_0.bin'] = pack(z,x)
    checks['channel_swap_detected'] = bool(differences(normalize(scalar)[0],normalize(swapped)[0]))
    missing = dict(scalar); del missing['fixture/00/momentum_z_1.bin']
    try:
        normalize(missing); checks['missing_component_detected'] = False
    except ValueError:
        checks['missing_component_detected'] = True
    checks['new_member_detected'] = bool(differences(scalar,scalar|{'new.bin':b'x'}))
    checks['removed_member_detected'] = bool(differences(scalar,{'new.bin':b'x'}))

    def fixture(directory, members):
        directory.mkdir()
        with zipfile.ZipFile(directory/'states.zip','w') as archive:
            for name,raw in members.items(): archive.writestr(name,raw)
        (directory/'variant.json').write_text(json.dumps({'pass':True,'observations':[{'capture':0,'fields':{}}],'injections':[]}),'utf-8')
        (directory/'run.log').write_text('','utf-8')
        (directory/'manifest.json').write_text(json.dumps({'exit_code':0,'validated_exit_code':0,'source_drift':[],'user_unchanged':True}),'utf-8')
    a,b = output/'scalar',output/'packed'
    fixture(a,scalar);fixture(b,rg)
    checks['full_comparator_accepts_layout'] = compare(a,b)['pass']
    (b/'run.log').write_text('SCRIPT ERROR: intentional negative fixture\n','utf-8')
    checks['engine_error_detected'] = not compare(a,b)['pass']
    (b/'run.log').write_text('','utf-8')
    manifest=json.loads((b/'manifest.json').read_text('utf-8'));manifest['validated_exit_code']=1
    (b/'manifest.json').write_text(json.dumps(manifest),'utf-8')
    checks['invalid_manifest_detected'] = not compare(a,b)['pass']
    # Run the real ABBA analyzer against synthetic complete captures, not a
    # second implementation of its metrics. Missing GPU is never zero.
    task=output/'synthetic_task'; evidence=task/'验收'; evidence.mkdir(parents=True)
    for name in ('a1','b1','b2','a2'):
        d=evidence/f'fixture_scene_{name}';d.mkdir()
        metadata={'configuration':{},'intervals':[{'phase':'live','start_us':0,'end_us':1000000,'start_sim_s':0,'end_sim_s':1}],
                  'engine':'fixture','adapter':'fixture','driver':'fixture','window':'1280x720','vsync':1,'camera':'fixed','source_drift':[],'last_error':''}
        frames=[{'phase':'live','frame_ms':16,'focused':True,'sim_s':i/10,'render_cpu_ms':1} for i in range(11)]
        (d/'capture.json').write_text(json.dumps({'metadata':metadata,'frames':frames}),'utf-8')
        (d/'manifest.json').write_text(json.dumps({'exit_code':0,'source_drift':[],'user_unchanged':True,'parameter_initial_sha256':'fixture','source_hashes':{'a.gd':'same',**({'new.gd':'new'} if name.startswith('b') else {})}}),'utf-8')
    command=[sys.executable,'-X','utf8',str(Path(__file__).with_name('compare_abba.py')),'--task-root',str(task.resolve()),'--temp-root',str((output/'unused').resolve()),'--prefix','fixture','--mode','scene']
    run=subprocess.run(command,capture_output=True,text=True)
    (output/'abba_stdout.txt').write_text(run.stdout,'utf-8');(output/'abba_stderr.txt').write_text(run.stderr,'utf-8')
    if run.returncode == 0:
        report=json.loads((evidence/'fixture_scene_comparison.json').read_text('utf-8'))
        checks['missing_gpu_unknown'] = report['metrics']['viewport_gpu_ms']['status']=='unknown'
        checks['new_source_union_detected'] = report['source_differences']==['new.gd']
    else:
        checks['abba_analyzer_runs']=False
    report={'pass':all(checks.values()),'checks':checks,'synthetic_abba_command':command,
            'synthetic_abba_exit':run.returncode,'note':'Synthetic fixtures are negative controls, not numerical or performance evidence.'}
    (output/'result.json').write_text(json.dumps(report,indent=2),'utf-8')
    print(json.dumps(report,indent=2))
    return not report['pass']


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True)
    raise SystemExit(main(p.parse_args().output.resolve()))
