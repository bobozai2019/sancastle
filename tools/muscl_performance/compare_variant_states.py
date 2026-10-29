"""Strict byte comparison across independent scalar/packed processes."""
import argparse
import json
from pathlib import Path
import zipfile
from layout_contract import normalize, differences


def compare(a_dir, b_dir):
    a = json.loads((a_dir/'variant.json').read_text('utf-8'))
    b = json.loads((b_dir/'variant.json').read_text('utf-8'))
    layouts = {}; errors = []; states = []
    for label, directory in [('a', a_dir), ('b', b_dir)]:
        with zipfile.ZipFile(directory/'states.zip') as archive:
            names = archive.namelist()
            if len(names) != len(set(names)):
                errors.append(label+':duplicate_zip_member')
            try:
                normalized, layouts[label] = normalize({n: archive.read(n) for n in names})
            except ValueError as error:
                errors.append(label+':'+str(error)); normalized = {}
            states.append(normalized)
    delta = differences(*states)
    def observations(value):
        return [{k:v for k,v in row.items() if k not in ('fields','cache')} for row in value['observations']]
    matched = observations(a) == observations(b)
    # Injection receipts describe physical layout and hashes. Each must verify
    # its actual GPU upload; paired logical input identity is recorded separately.
    injections_match = a.get('injections') == b.get('injections')
    runtime_errors = {str(d): [l for l in (d/'run.log').read_text('utf-8',errors='replace').splitlines()
                             if l.startswith(('ERROR:', 'SCRIPT ERROR:'))] for d in (a_dir,b_dir)}
    invalid_manifests = []
    for directory in (a_dir,b_dir):
        manifest = json.loads((directory/'manifest.json').read_text('utf-8'))
        if manifest.get('validated_exit_code',manifest['exit_code']) or manifest['source_drift'] or not manifest['user_unchanged']:
            invalid_manifests.append(str(directory))
    return {'pass': a['pass'] and b['pass'] and bool(a['observations']) and not delta and not errors and matched and injections_match and not any(runtime_errors.values()) and not invalid_manifests,
            'difference_members': delta, 'layout_errors': errors, 'layouts': layouts,
            'original_observations_equal': matched, 'injections_match': injections_match,
            'runtime_errors': runtime_errors, 'invalid_manifests': invalid_manifests,
            'paired_ticks': len(a['observations']),
            'scope': 'All decompressed members, path union, both authority slots and explicit view publication. Only declared momentum layout is normalized without Float32 conversion; original ZIPs remain unchanged.'}


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--a',type=Path,required=True);p.add_argument('--b',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    result=compare(args.a,args.b)
    args.output.write_text(json.dumps(result,indent=2),'utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='layouts'}))
    raise SystemExit(not result['pass'])
