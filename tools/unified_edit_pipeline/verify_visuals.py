"""Audit real display history containers, original recorder outputs and pixels."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image
from native_variant import VariantReader

ROOT = Path(__file__).resolve().parents[2]
CASES = ['visual_all', 'visual_foam', 'visual_gravel', 'visual_front', 'visual_wide', 'visual_indices', 'visual_edit', 'visual_fatal', 'visual_bad_cfl', 'visual_init_failure', 'visual_init_unknown', 'visual_capture_unknown', 'visual_restore_failure']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('Fresh audit required')
    checks = []

    def check(name, passed):
        checks.append({'name': name, 'pass': bool(passed)})

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    def raw(meta, label):
        data = Path(meta['path']).read_bytes()
        check(label+'_sha', sha(data) == meta['sha256'].lower())
        if 'bytes' in meta:
            check(label+'_size', len(data) == meta['bytes'])
        return data

    def publication(label, fields, foam_index=0, gravel_index=0):
        for field, source in [('foam', 'foam_'+str(foam_index)), ('local_front', 'local_front'), ('gravel', 'gravel_'+str(gravel_index))]:
            if 'visual_view/'+field in fields:
                check(label+'_complete_'+field, fields['visual_view/'+field]['sha256'] == fields['visual/'+source]['sha256'])

    def pixels(label, meta, fields):
        raw(meta, label+'_png')
        image = np.asarray(Image.open(meta['path']).convert('RGBA'))
        check(label+'_size', image.shape == (16, 48, 4))
        for field, x in [('foam', 8), ('local_front', 24), ('gravel', 40)]:
            key = 'visual_view/'+field
            if key not in fields:
                continue
            values = np.fromfile(fields[key]['path'], dtype='<f4')
            if field == 'gravel':
                sample = values.reshape(1024, 4)[17]
                expected = [float(sample[0])/32+.5, float(sample[2])/32+.5, float(sample[3])]
            else:
                sample = values.reshape(256, 256, 2)[128, 192]
                expected = [float(sample[0])/(32 if field == 'local_front' else 1), float(sample[1]), 0]
            check(label+'_real_material_'+field, np.all(np.abs(image[8, x, :3]/255-np.clip(expected, 0, 1)) <= 1/255+1e-7) and image[8, x, 3] == 255)

    manifest = json.loads((args.run/'run-manifest.json').read_text(encoding='utf-8-sig'))
    check('manifest_pass_and_no_drift', manifest['pass'] and not manifest['drift'])
    check('explicit_cases', [r['case'] for r in manifest['runs']] == CASES)
    for path, expected in manifest['sources'].items():
        check('source_'+path, sha((ROOT/path).read_bytes()) == expected.lower())
    for run in manifest['runs']:
        case = run['case']
        payload = Path(run['result']).read_bytes()
        check(case+'_report_identity', sha(payload) == run['result_sha256'].lower())
        report = json.loads(payload);obs = report['observations']
        check(case+'_gpu_pass', run['pass'] and report['pass'] and all(c['pass'] for c in report['checks']))
        for name in ['probe.log', 'stdout.txt']:
            log = (Path(run['result']).parent/name).read_text(encoding='utf-8-sig')
            check(case+'_clean_'+name, 'SCRIPT ERROR:' not in log and '\nERROR:' not in log and 'were leaked' not in log and 'was leaked' not in log)
        for kind in ['source_ownership']+(['final_ownership'] if 'final_ownership' in obs else []):
            check(case+'_released_'+kind, len(obs[kind]) == 8 and all(n == 0 for n in obs[kind].values()))
        if case in ('visual_init_failure', 'visual_init_unknown'):
            init = obs['initialization']
            check(case+'_real_enabled_resource_allocation', init['owners_before_cleanup']['water'] > 50 and init['owners_before_cleanup']['state'] > 0)
            if case == 'visual_init_unknown':
                check(case+'_unknown_retains_exact_owners', init['cleanup_unknown'] and init['owners_held'] == init['owners_before_cleanup'])
            continue
        snapshots = {}
        for stage in ['initial', 'first', 'restored', 'source_second', 'candidate_second', 'edit_only', 'fatal_before', 'fatal_after', 'unknown_after', 'source_after_failed_restore']:
            if stage not in obs:
                continue
            snapshots[stage] = {key: raw(meta, case+'_'+stage+'_'+key) for key, meta in obs[stage].items()}
        for field, meta in obs['reference'].items():
            value = raw(meta, case+'_reference_'+field)
            key = 'visual/bed_0' if field == 'bed' else 'visual_view/'+field
            check(case+'_original_recorder_exact_'+field, value == snapshots['first'][key])
        pixels(case+'_first', obs['first_render'], obs['first'])
        if case in ('visual_fatal', 'visual_bad_cfl'):
            before, after = snapshots['fatal_before'], snapshots['fatal_after']
            for key in before:
                if key.startswith('visual_view/') or key in ('stamp', 'clock', 'published_sand', 'published_water'):
                    check(case+'_last_complete_preserved_'+key, before[key] == after[key])
            flags = struct.unpack_from('<I', after['control'], 4)[0]
            check(case+'_real_gpu_fatal_flag', flags == (32 if case == 'visual_fatal' else 16))
            if case == 'visual_fatal':
                check(case+'_earlier_edit_changed_private_bed', before['field/sand'] != after['field/sand'])
            else:
                for key in before:
                    if key.startswith('visual/'):
                        check(case+'_bad_cfl_skips_private_history_'+key, before[key] == after[key])
            pixels(case+'_fatal', obs['fatal_render'], obs['fatal_after'])
            continue
        if case == 'visual_capture_unknown':
            unknown = obs['capture_unknown']
            check(case+'_capture_unknown_keeps_owners', unknown['status']['unknown'] and unknown['pending'] == 0 and unknown['registered'] == 35 and unknown['callback_count'] == 0 and unknown['owners']['water'] > 50)
            check(case+'_no_incomplete_container', obs['capture_error']['error'] == 'checkpoint_readback_registration' and not (Path(run['result']).parent/'enabled.sandue').exists())
            for key in snapshots['first']:
                check(case+'_readers_do_not_mutate_'+key, snapshots['first'][key] == snapshots['unknown_after'][key])
            continue
        if case == 'visual_edit':
            for field, meta in obs['edit_reference'].items():
                key = 'visual/bed_0' if field == 'bed' else 'visual_view/'+field
                check(case+'_edit_reproject_reference_'+field, raw(meta, case+'_edit_reference_'+field) == snapshots['edit_only'][key])
            check(case+'_edit_changes_visible_gravel', snapshots['first']['visual_view/gravel'] != snapshots['edit_only']['visual_view/gravel'])
            check(case+'_edit_does_not_advance_clock', snapshots['first']['clock'] == snapshots['edit_only']['clock'])
            pixels(case+'_edit', obs['edit_render'], obs['edit_only'])
        container = raw(obs['container'], case+'_container')
        check(case+'_native_header', container[:8] == b'SANDUE06' and struct.unpack_from('<II', container, 8) == (1, len(container)-48) and sha(container[48:]) == container[16:48].hex())
        cp = VariantReader(container[48:]).document()
        saved = snapshots.get('edit_only', snapshots['first'])
        for key, value in cp['native']['fields'].items():
            check(case+'_saved_field_'+key, value == saved['field/'+key])
        for key, value in cp['native']['spare'].items():
            check(case+'_saved_spare_'+key, value == saved['spare/'+key])
        for key in ['foam_0', 'foam_1', 'bed_0', 'bed_1']:
            if 'visual/'+key in snapshots['first']:
                check(case+'_saved_history_'+key, cp['native']['foam'][key] == saved['visual/'+key])
        if cp['simulation']['local_front_history']:
            check(case+'_saved_front', cp['native']['histories']['local_front'] == saved['visual/local_front'])
        if cp['visual_extensions']['gravel_v1']['enabled']:
            ext = cp['visual_extensions']['gravel_v1']
            for index in range(2):
                check(case+'_saved_gravel_'+str(index), ext['state_'+str(index)] == saved['visual/gravel_'+str(index)])
            values = np.frombuffer(ext['state_0'], dtype='<f4').reshape(1024, 4)
            check(case+'_gravel_active_and_unused', ext['active_count'] == ext['count'] == 512 and np.all(values[512:] == 0) and np.all(np.isin(values[:512, 3], [0, 1])))
        check(case+'_actual_capture_reader_count', len(obs['capture_info']['records']) == 26+sum(k.startswith('visual') for k in snapshots['first']))
        if case == 'visual_restore_failure':
            failed_restore = obs['failed_restore']
            check(case+'_candidate_failure_real_registered_reads', failed_restore['error'] == 'restore_readback_registration' and len(failed_restore['records']) == 44 and failed_restore['owners_before_cleanup']['water'] > 50)
            for key in snapshots['first']:
                check(case+'_current_preserved_'+key, snapshots['first'][key] == snapshots['source_after_failed_restore'][key])
            continue
        check(case+'_actual_restore_reader_count', len(obs['verifier']) == 35+sum(k.startswith('visual') for k in snapshots['first']))
        for key, record in obs['verifier'].items():
            check(case+'_verified_'+key, record['matched'] and record['actual_sha256'] == record['expected_sha256'])
        for stage in ['initial', 'first', 'source_second', 'candidate_second']:
            publication(case+'_'+stage, obs[stage], 1 if case == 'visual_indices' and stage == 'candidate_second' else 0, 1 if case == 'visual_indices' and stage == 'candidate_second' else 0)
        publication(case+'_restored', obs['restored'], int(case == 'visual_indices'), int(case == 'visual_indices'))
        for stage, meta, fields in [('first', obs['first_render'], obs['first']), ('restored', obs['restored_render'], obs['restored']), ('second', obs['second_render'], obs['source_second']), ('candidate_second', obs['candidate_second_render'], obs['candidate_second'])]:
            pixels(case+'_'+stage, meta, fields)
        for key in snapshots['source_second']:
            if key not in ['control', 'stamp']:
                check(case+'_continued_exact_'+key, snapshots['source_second'][key] == snapshots['candidate_second'][key])
        if case == 'visual_indices':
            for key, source in [('foam_0', 'visual/foam_0'), ('bed_0', 'visual/bed_0'), ('gravel_0', 'visual/gravel_0')]:
                check(case+'_distinct_raw_restore_'+key, raw(obs['modified_fixture'][key], case+'_fixture_'+key) == snapshots['restored'][source])
    result = {'pass': all(c['pass'] for c in checks), 'checks': checks, 'tool_sha256': sha(Path(__file__).read_bytes()), 'scope': 'Listed optional display stages only: original recorder comparison, raw native snapshot/restore, read-only material pixels and continued physical/visual bytes. No boundary, formal scene, complete lifetime matrix or cost claim.'}
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'pass': result['pass'], 'checks': len(checks), 'failures': [c['name'] for c in checks if not c['pass']]}))
    return 0 if result['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
