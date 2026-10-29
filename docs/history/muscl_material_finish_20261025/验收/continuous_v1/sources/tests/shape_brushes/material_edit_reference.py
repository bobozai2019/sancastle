"""Independent float32/float16 audit of actual material edit transactions."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np


def run(output):
    evidence = json.loads((output.parent/'material_edit/material_edit_evidence.json').read_text())
    checks = []
    def check(name, passed, detail=None):
        checks.append({'name': name, 'pass': bool(passed), 'detail': detail})
    def raw(sample, name, dtype='<f4'):
        item = sample['fields'][name]; data = Path(item['path']).read_bytes()
        assert len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256']
        return np.frombuffer(data, dtype=dtype)
    cases = {c['name']: c for c in evidence['cases']}
    check('required_material_cases', set(cases) == {'formed', 'candidate_rejected', 'legacy_cut', 'legacy_transport', 'transport', 'identity'})
    for case in cases.values():
        for stage in ['before', 'after']:
            check(case['name']+'_'+stage+'_27_fields', len(case[stage]['fields']) == 27)
            for name in case[stage]['fields']:
                raw(case[stage], name, 'u1')
    for name in ['formed', 'legacy_cut']:
        case = cases[name]; a, b = case['before'], case['after']
        old, sand = raw(a, 'sand'), raw(b, 'sand')
        old_tag = raw(a, 'mold_support_0').reshape(-1, 2)[:, 0]
        tag = np.clip(old_tag - np.maximum(old-sand, np.float32(0)), np.float32(0), sand)
        if name == 'formed': tag = np.clip(tag + np.maximum(sand-old, np.float32(0)), np.float32(0), sand)
        expected = np.column_stack([tag, np.where(tag > 0, sand, np.float32(0))]).astype('<f4')
        for slot in [0, 1]:
            actual = raw(b, 'mold_support_'+str(slot)).reshape(-1, 2)
            check(name+'_support_'+str(slot)+'_exact', actual.tobytes() == expected.tobytes())
        check(name+'_legal_tag', np.isfinite(expected).all() and (tag >= 0).all() and (tag <= sand).all())
        changed = sand != old
        for slot in ['compaction', 'spare_compaction']:
            compact = raw(a, slot, '<f2').copy()
            if name == 'formed': compact[changed] = np.maximum(compact[changed].astype('<f4'), np.float32(.95)).astype('<f2')
            check(name+'_'+slot+'_exact', compact.tobytes() == raw(b, slot, '<f2').tobytes())
        allowed = {'sand', 'spare_sand', 'published_sand', 'mold_support_0', 'mold_support_1'}
        if name == 'formed': allowed |= {'compaction', 'spare_compaction'}
        unexpected = [n for n in a['fields'] if n not in allowed and a['fields'][n]['sha256'] != b['fields'][n]['sha256']]
        check(name+'_unrelated_fields_exact', not unexpected, unexpected)
        check(name+'_sand_current_spare_public_exact', raw(b,'sand').tobytes() == raw(b,'spare_sand').tobytes() == raw(b,'published_sand').tobytes())
    for name in ['candidate_rejected', 'legacy_transport', 'transport', 'identity']:
        case = cases[name]
        bad = [n for n in case['before']['fields'] if case['before']['fields'][n]['sha256'] != case['after']['fields'][n]['sha256']]
        check(name+'_all_fields_exact', not bad, bad)
    for name in ['transport', 'identity']:
        case = cases[name]
        candidate = case['candidate']
        for item in candidate.values():
            data=Path(item['path']).read_bytes()
            assert len(data)==item['bytes'] and hashlib.sha256(data).hexdigest()==item['sha256']
        receipt=np.fromfile(candidate['candidate_receipt']['path'],dtype='<u4')
        support=np.fromfile(candidate['candidate_support']['path'],dtype='<f4').reshape(-1,2)
        check(name+'_validated_positive_material_candidate',receipt[3]==1 and np.count_nonzero(support[:,0])>0)
        check(name+'_distinct_support_preimages', case['before']['fields']['mold_support_0']['sha256'] != case['before']['fields']['mold_support_1']['sha256'])
        check(name+'_distinct_compact_preimages', case['before']['fields']['compaction']['sha256'] != case['before']['fields']['spare_compaction']['sha256'])
        check(name+'_no_source_or_sink', case['metadata']['source'] == case['metadata']['sink'] == 0)
    source = cases['formed']['metadata']['source']
    check('formed_source_matches_receipt', source == cases['formed']['result']['added_m3'])
    check('rejected_no_additional_source', cases['candidate_rejected']['metadata']['source'] == source)
    check('cut_no_additional_source', cases['legacy_cut']['metadata']['source'] == source)
    check('cut_sink_matches_receipt', cases['legacy_cut']['metadata']['sink'] == cases['legacy_cut']['result']['actual_sand_m3'])
    check('cut_without_physics_tick', cases['legacy_cut']['metadata']['tick'] == 0)
    result = {'pass': all(c['pass'] for c in checks), 'checks': checks,
              'scope': 'Actual molded edit, rejected candidate, independent-slot rollback and paused legacy cut. Damage retention/native format/30s gate still pending.'}
    (output/'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result['pass']


if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--output',type=Path,required=True); args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True); passed=run(args.output)
    print('MATERIAL_EDIT_REFERENCE',passed); raise SystemExit(0 if passed else 1)
