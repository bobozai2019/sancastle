"""Package validated completed-tick JPEGs into standard MJPEG AVI at 30 Hz."""
import argparse, hashlib, json, struct
from pathlib import Path

def chunk(tag, data):
    return tag + struct.pack('<I', len(data)) + data + (b'\0' if len(data) & 1 else b'')

def group(tag, data):
    return chunk(b'LIST', tag + data)

p = argparse.ArgumentParser(); p.add_argument('run', type=Path); a = p.parse_args()
result = json.loads((a.run/'feedback_probe.json').read_text(encoding='utf-8-sig'))
assert result['pass'] and len(result['frames']) == 151
frames = result['frames']; w, h = frames[0]['width'], frames[0]['height']
payload, index, offset, max_size = [], [], 4, 0
for i, frame in enumerate(frames):
    assert frame['tick'] == i and frame['width'] == w and frame['height'] == h
    data = (a.run/frame['file']).read_bytes()
    assert data[:2] == b'\xff\xd8' and data[-2:] == b'\xff\xd9'
    assert hashlib.sha256(data).hexdigest() == frame['sha256']
    encoded = chunk(b'00dc', data); payload.append(encoded)
    index.append(struct.pack('<4sIII', b'00dc', 0x10, offset, len(data)))
    offset += len(encoded); max_size = max(max_size, len(data))
avih = struct.pack('<14I', 33333, max_size*30, 0, 0x10, 151, 0, 1, max_size, w, h, 0, 0, 0, 0)
strh = struct.pack('<4s4sIHH8I4h', b'vids', b'MJPG', 0, 0, 0, 0, 1, 30, 0, 151, max_size, 0xffffffff, 0, 0, 0, w, h)
strf = struct.pack('<IiiHH4sIiiII', 40, w, h, 1, 24, b'MJPG', w*h*3, 0, 0, 0, 0)
hdrl = group(b'hdrl', chunk(b'avih', avih) + group(b'strl', chunk(b'strh', strh) + chunk(b'strf', strf)))
body = b'AVI ' + hdrl + group(b'movi', b''.join(payload)) + chunk(b'idx1', b''.join(index))
name = 'feedback_' + result['rows'][0]['phase'].split('_')[0] + '.avi'
out = a.run/name
out.write_bytes(b'RIFF'+struct.pack('<I', len(body))+body)
assert out.stat().st_size == 8 + len(body)
report = dict(codec='MJPG', fps=30, frames=151, duration_s=151/30, sampled_sim_s=[0,5],
              wall_time_independent=True, resolution=[w,h], indexed_frames=len(index),
              source_manifest_sha256=hashlib.sha256((a.run/'feedback_probe.json').read_bytes()).hexdigest(),
              file=name, sha256=hashlib.sha256(out.read_bytes()).hexdigest(), bytes=out.stat().st_size,
              tool=str(Path(__file__).resolve()), tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
(a.run/'video_index.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report))
