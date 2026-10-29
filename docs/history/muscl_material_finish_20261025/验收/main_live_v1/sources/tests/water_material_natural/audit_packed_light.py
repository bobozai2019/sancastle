"""Compare every debug/camera against native; retain measured short-window costs."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image

out=Path(sys.argv[1]).resolve()
run=json.loads((out/'process_result.json').read_text())
assert run['exit_code']==0 and not run['concurrent_godot_detected']
assert run['sources_unchanged_during_run']
data=json.loads((out/'packed_comparison.json').read_text())
rows={}
for name,case in data['cases'].items():
    comparisons={}
    for key,img in case['images'].items():
        a=np.asarray(Image.open(img['path']).convert('RGB')).astype(np.int16)
        b=np.asarray(Image.open(data['cases']['native']['images'][key]['path']).convert('RGB')).astype(np.int16)
        delta=np.abs(a-b)
        comparisons[key]={'max_channel_delta':int(delta.max()),'mean_channel_delta':float(delta.mean()),
                          'pixels_over_one_bit':int((delta.max(axis=2)>1).sum())}
    rows[name]={'frame_median_ms':float(np.median(case['frame_ms'])),
                'frame_p95_ms':float(np.percentile(case['frame_ms'],95)),
                'gpu_median_ms':float(np.median(case['gpu_ms'])),
                'comparisons':comparisons,
                'one_bit_equivalent':all(v['pixels_over_one_bit']==0 for v in comparisons.values())}
baseline=json.loads((out.parent/'t00_baseline_v4/manifest.json').read_text())
manifest=json.loads((out/'manifest.json').read_text())
same_fields=all(v['sha256']==baseline['fields'][k]['sha256'] for k,v in manifest['fields'].items())
result={'operation_valid':True,'fields_match_baseline':same_fields,'cases':rows,
        'scope':'Frozen 720p, 5-second GPU attribution; does not decide 1080p complete-load budget.'}
(out/'packed_audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
