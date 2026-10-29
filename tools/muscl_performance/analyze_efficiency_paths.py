"""Split sampled phase-zero edge spans using a direct pre-edge cache snapshot."""
from collections import defaultdict
import json
from pathlib import Path
import struct
import sys
from analyze_diagnostic import analyze, stats

def main(directory):
    raw=json.loads((directory/'capture.json').read_text(encoding='utf-8'))
    analysis_path=directory/'diagnostic_analysis.json'
    analysis=json.loads(analysis_path.read_text(encoding='utf-8')) if analysis_path.exists() else analyze(directory)
    original={r['sample_id']:r for r in raw['diagnostic']['samples']}
    groups=defaultdict(list); rows=[]; errors=[]
    for sample in analysis['samples']:
        source=original[sample['sample_id']]
        encoded=source.get('retry_before_edge_hex','')
        if not source.get('retry_copy_ok') or len(encoded)!=32:
            errors.append({'sample':sample['sample_id'],'reason':'missing_pre_edge_snapshot'});continue
        valid,enabled,hits,misses=struct.unpack('<4I',bytes.fromhex(encoded))
        path='no_work' if sample['class']=='invalid' else 'cache_hit' if valid and enabled else 'full'
        spans=[s for s in sample['spans'] if s['stage']=='edge_p0']
        if len(spans)!=1:
            errors.append({'sample':sample['sample_id'],'reason':'edge_span_count'});continue
        span=spans[0];groups[sample['class']+'/'+path].append(span['ms'])
        rows.append({'sample':sample['sample_id'],'slot':sample['slot'],'sim_tick':sample['sim_tick'],
                     'class':sample['class'],'path':path,'cache_before':[valid,enabled,hits,misses],
                     'timestamp_frame':span['timestamp_frame'],'start_ns':span['start_ns'],'end_ns':span['end_ns'],'ms':span['ms']})
    manifest=json.loads((directory/'manifest.json').read_text(encoding='utf-8'))
    good=bool(rows) and not errors and not manifest.get('engine_errors') and not manifest.get('source_drift') and manifest.get('validated_exit_code',manifest['exit_code'])==0
    result={'pass':good,'errors':errors,'gpu_ms':{k:stats(v) for k,v in groups.items()},'rows':rows,
            'limits':['Only selected-slot phase0 edge paths; phase1 is separate in diagnostic_analysis.',
                      'No-work is determined from the matched actual audit, not from cache flags.',
                      'Sparse timestamps include scheduling; extra staging copy adds diagnostic overhead.',
                      'No SM counters or queue-idle attribution are inferred.']}
    output=directory/'edge_path_analysis.json'
    with output.open('x',encoding='utf-8') as f:json.dump(result,f,indent=2)
    print(json.dumps({k:v for k,v in result.items() if k not in ('rows','limits')}))
    return good

if __name__=='__main__':raise SystemExit(not main(Path(sys.argv[1])))
