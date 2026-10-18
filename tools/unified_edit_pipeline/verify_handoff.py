"""Decode native checkpoint bytes and audit real two-slot consumer evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image
from native_variant import VariantReader

ROOT = Path(__file__).resolve().parents[2]
CASES = ['handoff_native', 'handoff_preview', 'handoff_detach', 'handoff_preflight', 'handoff_initialize', 'handoff_cancel', 'handoff_repeat', 'handoff_capacity', 'handoff_unknown', 'handoff_upload']
FAILURES = {'handoff_preflight', 'handoff_initialize', 'handoff_cancel'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cases', nargs='+', choices=CASES+['handoff_visuals', 'handoff_boundary'], help='Explicit component subset; omission requires the established ten-case matrix')
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('Fresh audit required')
    checks = []

    def check(name, passed):
        checks.append({'name': name, 'pass': bool(passed)})

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    def data(meta, name):
        payload = Path(meta['path']).read_bytes()
        check(name+'_sha', sha(payload) == meta['sha256'].lower())
        if 'bytes' in meta:
            check(name+'_size', len(payload) == meta['bytes'])
        return payload

    manifest = json.loads((args.run/'run-manifest.json').read_text(encoding='utf-8-sig'))
    check('manifest_pass', manifest['pass'] and not manifest['drift'])
    check('exact_cases', [r['case'] for r in manifest['runs']] == (args.cases or CASES))
    for path, expected in manifest['sources'].items():
        check('source_'+path, sha((ROOT/path).read_bytes()) == expected.lower())
    for run in manifest['runs']:
        name = run['case']
        payload = Path(run['result']).read_bytes()
        check(name+'_report_identity', sha(payload) == run['result_sha256'].lower())
        report = json.loads(payload)
        obs = report['observations']
        if name in ('handoff_unknown', 'handoff_upload'):
            terminal = obs['fault_terminal']
            check(name+'_no_fabricated_gpu_outcome', 'outcome' not in terminal and terminal['submitted'] == (name == 'handoff_unknown') and terminal['error'] == ('recorded_result_unknown' if name == 'handoff_unknown' else 'aborted_before_recording'))
        check(name+'_gpu_pass', run['pass'] and run['exit_code'] == 0 and report['pass'] and all(c['pass'] for c in report['checks']))
        for log in ['probe.log', 'stdout.txt']:
            text = (Path(run['result']).parent/log).read_text(encoding='utf-8-sig')
            check(name+'_clean_'+log, 'SCRIPT ERROR:' not in text and '\nERROR:' not in text and 'were leaked' not in text and 'was leaked' not in text)
        check(name+'_all_eight_owner_types_zero', all(len(owner) == 8 and all(n == 0 for n in owner.values()) for owner in obs['final_ownership']))
        container = data(obs['container'], name+'_container')
        check(name+'_native_container_header', container[:8] == b'SANDUE06' and struct.unpack_from('<II', container, 8) == (1, len(container)-48) and sha(container[48:]) == container[16:48].hex())
        cp = VariantReader(container[48:]).document()
        check(name+'_saved_identity', cp['generation'] == 9007199254740993 and cp['state_seq'] == 0 and cp['highwater_id'] == 0)
        pixels = {}
        for stage in ['initial', 'edited', 'failure' if name in FAILURES else 'restored']:
            data(obs[stage], name+'_'+stage)
            image = np.asarray(Image.open(obs[stage]['path']).convert('RGBA'))
            check(name+'_'+stage+'_size', image.shape == (16, 48, 4))
            pixels[stage] = image
        check(name+'_render_changed', np.all(pixels['edited'][:, :16, 0] > pixels['initial'][:, :16, 0]))
        check(name+'_render_atomic_result', np.array_equal(pixels['failure'], pixels['edited']) if name in FAILURES else np.array_equal(pixels['restored'], pixels['initial']))
        if name in ('handoff_visuals', 'handoff_boundary'):
            visual = {}
            for stage in ['initial', 'edited', 'restored']:
                data(obs['visual_'+stage], name+'_visual_'+stage)
                visual[stage] = np.asarray(Image.open(obs['visual_'+stage]['path']).convert('RGBA'))
            check(name+'_enabled_material_changed', not np.array_equal(visual['initial'], visual['edited']))
            check(name+'_all_enabled_materials_restored', np.array_equal(visual['initial'], visual['restored']))
        events = obs['events']
        commits = [e for e in events if e['kind'] == 'commit']
        if name in FAILURES:
            check(name+'_only_boot_commit', len(commits) == 1)
            check(name+'_candidate_discarded', any(e['kind'] == 'discarded' for e in events))
        else:
            expected = 12 if name == 'handoff_repeat' else 3
            check(name+'_expected_commit_count', len(commits) == expected)
            check(name+'_monotonic_epochs_lower_saved_sequence', all(e['detail']['generation'] == 9007199254740993+i and e['detail']['state_seq'] == 0 for i, e in enumerate(commits)))
            maps = np.frombuffer(data(obs['physics']['maps'], name+'_maps'), dtype='<f4').reshape(64, 33, 33)
            sand = np.frombuffer(cp['native']['fields']['sand'], dtype='<f4').reshape(256, 256)
            rock = np.frombuffer(cp['native']['fields']['rock'], dtype='<f4').reshape(256, 256)
            bed = sand+rock
            for chunk in range(64):
                xs = np.minimum(255, (chunk % 8)*32+np.arange(33))
                zs = np.minimum(255, (chunk // 8)*32+np.arange(33))
                check(name+'_map_'+str(chunk), np.array_equal(maps[chunk], bed[np.ix_(zs, xs)]))
    result = {'pass': all(c['pass'] for c in checks), 'checks': checks, 'tool_sha256': sha(Path(__file__).read_bytes()), 'scope': 'Only listed two-slot component cases. Raw saved container, real PNGs, all 64 map bytes and released owners. No enabled effects, formal scene, continuous preview or cost claim.'}
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'pass': result['pass'], 'checks': len(checks), 'failures': [c['name'] for c in checks if not c['pass']]}))
    return 0 if result['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
