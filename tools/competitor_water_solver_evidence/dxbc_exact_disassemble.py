"""Disassemble frozen six original DXBC programs with SDK hex literals, never rounded floats."""
import argparse
import ctypes
import ctypes.wintypes as wt
import json
import re
import shutil
import sys
from pathlib import Path
from evidence_contract import identity


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[3]
    source = root / 'docs/competitor/evidence/water_solver_reconstruction/t03_six_kernel_20261025_v4'
    manifest = json.loads((source / 'manifest.json').read_text())
    compiler = ctypes.WinDLL('d3dcompiler_47.dll')
    get_path = ctypes.WinDLL('kernel32').GetModuleFileNameW
    get_path.argtypes = [wt.HMODULE, wt.LPWSTR, wt.DWORD]
    get_path.restype = wt.DWORD
    path_buffer = ctypes.create_unicode_buffer(32768)
    get_path(compiler._handle, path_buffer, len(path_buffer))
    dll = Path(path_buffer.value)
    header = Path('C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um/d3dcompiler.h')
    header_text = header.read_text()
    flags = {}
    for name in ['D3D_DISASM_ENABLE_INSTRUCTION_NUMBERING', 'D3D_DISASM_PRINT_HEX_LITERALS']:
        flags[name] = int(re.search(r'#define\s+' + name + r'\s+(0x[0-9a-fA-F]+)', header_text)[1], 16)
    disassemble = compiler.D3DDisassemble
    disassemble.argtypes = [ctypes.c_void_p, ctypes.c_size_t, wt.UINT, ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    disassemble.restype = ctypes.c_long
    rows, errors = [], []
    for event in [1484, 1490, 1495, 1500, 1537, 1543]:
        program = source / ('sources/e' + str(event) + '/program.dxbc')
        expected = next(a for a in manifest['artifacts'] if a['path'] == program.as_posix())
        if identity(program)['sha256'] != expected['sha256']:
            raise ValueError('Frozen program changed')
        data = program.read_bytes()
        blob = ctypes.c_void_p()
        buffer = ctypes.create_string_buffer(data)
        result = disassemble(buffer, len(data), flags['D3D_DISASM_ENABLE_INSTRUCTION_NUMBERING'] | flags['D3D_DISASM_PRINT_HEX_LITERALS'], None, ctypes.byref(blob))
        if result < 0 or not blob.value:
            errors.append(dict(event=event, hresult=result))
            continue
        vtable = ctypes.cast(blob, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
        get_buffer = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(vtable[3])
        get_size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(vtable[4])
        release = ctypes.WINFUNCTYPE(wt.ULONG, ctypes.c_void_p)(vtable[2])
        try:
            text = ctypes.string_at(get_buffer(blob), get_size(blob)).rstrip(b'\0').decode('ascii')
        finally:
            release(blob)
        filename = out / ('e' + str(event) + '_exact.asm')
        filename.write_text(text, encoding='ascii')
        shutil.copyfile(program, out / ('e' + str(event) + '.dxbc'))
        instructions = re.findall(r'^\s*\d+:\s+(\S+)', text, re.M)
        literals = re.findall(r'\bl\(([^)]+)\)', text)
        if any(any(not re.fullmatch(r'0x[0-9a-fA-F]{8}', part.strip()) for part in literal.split(',')) for literal in literals):
            errors.append(dict(event=event, error='NON_HEX_LITERAL'))
        rows.append(dict(event_id_in_original_fixture=event, source=expected, output=identity(filename),
                         instruction_count=len(instructions), opcodes=sorted(set(instructions)), literal_count=len(literals),
                         literal_semantics='Raw 32-bit immediate values; float interpretation requires asfloat, not numeric conversion of hex integers'))
    shutil.copyfile(Path(__file__), out / Path(__file__).name)
    shutil.copyfile(Path(__file__).with_name('evidence_contract.py'), out / 'evidence_contract.py')
    report = dict(operation_status='complete', verification_status='passed' if len(rows) == 6 and not errors else 'failed',
                  scope='Exact original DXBC disassembly only, not original HLSL or Godot equivalence',
                  python=sys.version, compiler=identity(dll), sdk_header=identity(header), flags=flags,
                  source_manifest=identity(source / 'manifest.json'), programs=rows, errors=errors)
    (out / 'disassembly.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status='complete', verification_status=report['verification_status'], errors=errors, artifacts=[identity(p) for p in out.iterdir() if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps(dict(status=report['verification_status'], errors=errors, instructions=[r['instruction_count'] for r in rows], opcodes=sorted({o for r in rows for o in r['opcodes']}))))
    raise SystemExit(bool(errors))


if __name__ == '__main__':
    main()
