"""Validate used temporary lanes and actual corruptions of this frozen DXBC subset."""
import argparse
import json
import shutil
from pathlib import Path
from lower_dxbc_glsl import audit_defined_lanes, generate
from evidence_contract import identity


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--exact', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    programs = []
    for event in [1484,1490,1495,1500,1537,1543]:
        source = args.exact / ('e%d_exact.asm' % event)
        programs.append(dict(event=event, source=identity(source), audit=audit_defined_lanes(source.read_text())))
    text = (args.exact / 'e1484_exact.asm').read_text()
    changed = [
        ('undefined_index', text.replace('r1.xyzw, r0.x, l(0x00000000), u0.xyzw', 'r1.xyzw, r0.w, l(0x00000000), u0.xyzw',1)),
        ('rounded_literal', text.replace('l(0x00000000)','l(0.000000)',1)),
        ('wrong_stride', text.replace('dcl_uav_structured u0, 16','dcl_uav_structured u0, 8')),
        ('unmodeled_opcode', text.replace('   0: imad ', '   0: xor ',1)),
    ]
    negatives = []
    for name, source in changed:
        try:
            generate(source, 1484, 'fma', 'separate')
            negatives.append(dict(case=name, rejected=False))
        except ValueError as error:
            negatives.append(dict(case=name, rejected=True, error=str(error)))
    for name in ['audit_lowering_static.py','lower_dxbc_glsl.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).parent / name, out / name)
    report = dict(operation_status='complete', verification_status='passed' if all(n['rejected'] for n in negatives) else 'failed',
                  scope='Static live-lane, exact-operand and fail-closed lowering validation only, not GPU numeric acceptance',
                  programs=programs, negatives=negatives)
    (out/'audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'manifest.json').write_text(json.dumps(dict(operation_status='complete',verification_status=report['verification_status'],artifacts=[identity(p) for p in out.iterdir() if p.is_file()]),indent=2),encoding='utf-8')
    print(json.dumps(dict(reads=[p['audit']['live_register_component_reads'] for p in programs],negatives=negatives)))
    raise SystemExit(report['verification_status']!='passed')


if __name__=='__main__':
    main()
