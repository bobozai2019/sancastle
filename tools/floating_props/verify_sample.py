"""Independent byte-level sentinel/numeric verification (no Godot decoder)."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('run', type=Path)
    args = parser.parse_args()
    raw = (args.run/'linear32_result.bin').read_bytes()
    req = (args.run/'linear32_request.bin').read_bytes()
    report = json.loads((args.run/'probe.json').read_text('utf-8-sig'))
    checks = []

    def check(name, passed):
        checks.append(dict(name=name, **{'pass': bool(passed)}))

    check('fixed_lengths', len(raw) == 3200 and len(req) == 1152)
    check('schema_error', struct.unpack_from('<II', raw) == (2, 0))
    check('identity_and_int64_sentinels', struct.unpack_from('<4q', raw, 8) == (1, 9007199254740995, 9007199254740993, 1))
    check('complete_initial_identity', struct.unpack_from('<3qfI', raw, 40) == (0, 0, 0, 0.0, 32))
    check('domain_hash_and_reserved', raw[96:128] == hashlib.sha256(b'main_beach').digest() and raw[80:88] == bytes(8))
    for i in range(32):
        base = 128+i*64
        body, point, x, y, z, bed, h, eta, ux, uz, valid = struct.unpack_from('<qq8fI', raw, base)
        expected_position = struct.unpack_from('<3f', req, 128+i*32+16)
        check(f'point_{i}_identity_position_padding', (body, point) == (9223372036854775807, 9007199254740993+i)
              and (x, y, z) == expected_position and raw[base+52:base+64] == bytes(12) and valid == 1)
        cx, cz = min(15.9375, max(-15.9375, x)), min(15.9375, max(-15.9375, z))
        eb, eh = 0.2+0.003*cx+0.002*cz, 0.3+0.001*cx
        eu, ev = (0.2+0.002*cz)/eh, (-0.1+0.001*cx)/eh
        if report['case'] == 'constant':
            eb, eh, eu, ev = 0.2, 0.3, 0.4, -0.2
        elif report['case'] == 'thin':
            eb, eh, eu, ev = 0.2, 0.003, 0.6, -0.3
            if i == 0:
                eh, eu, ev = 0.0005, 0, 0
        elif i == 0:
            eh, eu, ev = 0, 0, 0
        check(f'point_{i}_analytic_values', abs(bed-eb) < 2e-6 and abs(h-eh) < 2e-6
              and abs(eta-eb-eh) < 2e-6 and abs(ux-eu) < 2e-5 and abs(uz-ev) < 2e-5
              and all(map(math.isfinite, (bed, h, eta, ux, uz))))
    check('chunk_mask_all64', struct.unpack_from('<II', raw, 72) == (0xffffffff, 0xffffffff))
    check('all64_chunk_records', all(struct.unpack_from('<IIq', raw, 2176+i*16) == (i, 0, 0) for i in range(64)))
    result = dict(checks=checks, raw_sha256=hashlib.sha256(raw).hexdigest(), **{'pass': all(c['pass'] for c in checks)})
    path = args.run/'independent_bytes.json'
    if path.exists():
        raise SystemExit('Do not overwrite evidence')
    path.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print('SAMPLE_BYTES', result['pass'], len(checks))
    raise SystemExit(0 if result['pass'] else 1)


if __name__ == '__main__':
    main()
