"""Audit exact sequence coverage and held frames; report temporal metrics, not subjective PASS."""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

p = Path(sys.argv[1]).resolve()
d = json.loads((p / 'style_sequence.json').read_text())
r = json.loads((p / 'process_result.json').read_text())
assert r['exit_code'] == 0 and r['engine_error_free'] and r['sources_unchanged_during_run']
frames = d['frames']
ticks = [f['tick'] for f in frames]
assert ticks == list(range(ticks[0], ticks[0] + 1801, 3))
assert abs(frames[-1]['time_s'] - frames[0]['time_s'] - 60) < 1e-5
assert all(abs(f['time_s'] - f['tick'] / 30) < 1e-5 for f in frames)
rois = {
    'oblique': {'shallow': [450,420,155,80], 'deep': [285,500,160,110], 'contact': [755,495,110,120], 'front': [655,315,120,95]},
    'close': {'shallow': [30,580,215,110], 'deep': [250,495,190,80], 'contact': [845,545,135,110], 'front': [510,337,155,60]},
    'grazing': {'shallow': [850,625,240,85], 'deep': [330,550,270,70], 'contact': [900,405,260,95], 'front': [665,380,235,80]},
}
held = {}
for tick, c in d['checkpoints'].items():
    if 'held' in c:
        h = c['held']
        a = np.asarray(Image.open(h['first']).convert('RGB')).astype(int)
        b = np.asarray(Image.open(h['repeat']).convert('RGB')).astype(int)
        held[tick] = {'max_rgb_delta': int(np.abs(a-b).max()), 'authority_unchanged': h['authority_unchanged']}
        assert held[tick]['max_rgb_delta'] <= 1 and h['authority_unchanged']
rows = {}
for cam, regions in rois.items():
    stats = {name: [] for name in regions}
    previous = None
    board = Image.new('RGB', (1920, 8*210), (24,24,24))
    draw = ImageDraw.Draw(board)
    selected = set(np.rint(np.linspace(0, len(frames)-1, 32)).astype(int))
    thumbnails = []
    slot = 0
    for i, f in enumerate(frames):
        im = Image.open(f['images'][cam]['path']).convert('RGB')
        a = np.asarray(im).astype(np.int16)
        assert a.shape == (720,1280,3)
        if previous is not None:
            delta = np.abs(a-previous).max(2)
            for name, (x,y,w,h) in regions.items():
                v = delta[y:y+h,x:x+w]
                stats[name].append({'tick': f['tick'], 'mean_max_channel_delta': float(v.mean()),
                    'p95_max_channel_delta': float(np.percentile(v,95)), 'changed_fraction_over_one_bit': float((v>1).mean())})
        previous = a
        if i in selected:
            x, y = slot%4*480, slot//4*210
            board.paste(im.resize((320,180)), (x,y+25))
            draw.text((x+5,y+5), f'{cam} t={f["time_s"]:.1f}s tick={f["tick"]}', fill='white')
            slot += 1
        # All 601 samples retained in each preview, duration 100ms = exact sampled time spacing.
        thumbnails.append(im.resize((640,360)).quantize(colors=128))
    board.save(p / f'sequence_keyframes_{cam}.png')
    thumbnails[0].save(p / f'sequence_{cam}.gif', save_all=True, append_images=thumbnails[1:], duration=100, loop=0)
    rows[cam] = {'roi_coordinates': regions, 'temporal_metrics': stats,
        'largest_mean_delta_ticks': {name: sorted(values,key=lambda v:v['mean_max_channel_delta'],reverse=True)[:10] for name,values in stats.items()}}
result = {'sample_count_per_camera': len(frames), 'duration_simulated_s': 60,
    'cameras': rows, 'held_completed_states': held, 'effective_style': d['effective_style'],
    'workload': d['workload'], 'wave_request_count': d['wave_request_count'],
    'coverage_and_held_checks_pass': True,
    'limits': 'Offline 10fps completed-state sequence. ROI labels are visual labels, not physical depth groups. Metrics do not independently prove absence of shimmer, nor realtime cost or pause/checkpoint compatibility.'}
(p/'sequence_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'samples':len(frames),'duration_simulated_s':60,'held':held,'coverage_and_held_checks_pass':True}))
