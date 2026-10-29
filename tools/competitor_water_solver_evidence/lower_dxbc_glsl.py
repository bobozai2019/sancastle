"""Fail-closed lowering of this frozen straight-line DXBC subset to packed-uint Godot GLSL."""
import argparse
import json
import re
import shutil
from pathlib import Path
from evidence_contract import identity


LANES = 'xyzw'
EVENTS = [1484, 1490, 1495, 1500, 1537, 1543]


def split_args(text):
    parts, begin, depth = [], 0, 0
    for index, char in enumerate(text):
        depth += (char == '(') - (char == ')')
        if char == ',' and depth == 0:
            parts.append(text[begin:index].strip())
            begin = index + 1
    parts.append(text[begin:].strip())
    if depth:
        raise ValueError('UNBALANCED_OPERAND')
    return parts


def uexpr(source):
    negative = source.startswith('-')
    if negative:
        source = source[1:]
    if source.startswith('l(') and source.endswith(')'):
        words = [s.strip() for s in source[2:-1].split(',')]
        if len(words) not in [1, 4] or any(not re.fullmatch(r'0x[0-9a-fA-F]{8}', s) for s in words):
            raise ValueError('IMMEDIATE_MUST_BE_EXACT_HEX:' + source)
        expr = 'uvec4(' + ','.join(s + 'u' for s in words) + ')'
    else:
        match = re.fullmatch(r'(r\d+|vThreadID|cb0\[\d+\])(?:\.([xyzw]{1,4}))?', source)
        if not match:
            raise ValueError('UNSUPPORTED_OPERAND:' + source)
        base, swizzle = match.groups()
        if base.startswith('cb0['):
            base = base.replace('cb0[', 'constants[')
        if swizzle and len(swizzle) == 1:
            expr = 'uvec4(' + base + '.' + swizzle + ')'
        elif swizzle and len(swizzle) == 4:
            expr = base + '.' + swizzle
        elif swizzle:
            raise ValueError('UNSUPPORTED_SOURCE_SWIZZLE:' + source)
        else:
            expr = base
    return 'floatBitsToUint(-uintBitsToFloat(' + expr + '))' if negative else expr


def fexpr(source):
    return 'uintBitsToFloat(' + uexpr(source) + ')'


def destination(value):
    match = re.fullmatch(r'(r\d+)\.([xyzw]{1,4})', value)
    if not match:
        raise ValueError('UNSUPPORTED_DESTINATION:' + value)
    return match.groups()


def audit_defined_lanes(text):
    count = int(re.search(r'dcl_temps (\d+)', text)[1])
    cb_count = int(re.search(r'dcl_constantbuffer CB0\[(\d+)\]', text)[1])
    defined = {'r'+str(i):set() for i in range(count)}
    defined['vThreadID'] = set(re.search(r'dcl_input vThreadID\.([xyzw]+)', text)[1])
    reads = 0

    def read(source, positions, instruction):
        nonlocal reads
        source = source.lstrip('-')
        if source.startswith('l('):
            return
        match = re.fullmatch(r'(r\d+|vThreadID|cb0\[\d+\])(?:\.([xyzw]{1,4}))?', source)
        if not match:
            raise ValueError('READ_OPERAND_UNSUPPORTED:'+source)
        base, swizzle = match.groups()
        swizzle = swizzle or LANES
        if len(swizzle) == 1:
            swizzle *= 4
        if len(swizzle) != 4:
            raise ValueError('READ_SWIZZLE_UNSUPPORTED:'+source)
        if base.startswith('cb0['):
            if int(base[4:-1]) >= cb_count:
                raise ValueError('CB_OUTSIDE_DECLARATION')
            return
        for position in positions:
            lane = swizzle[position]
            reads += 1
            if base not in defined or lane not in defined[base]:
                raise ValueError('UNDEFINED_LIVE_LANE:'+str(instruction)+':'+base+'.'+lane)

    for number, instruction in re.findall(r'^\s*(\d+):\s+([^\n\r]+)', text, re.M):
        match = re.fullmatch(r'(ld_structured_indexable\(structured_buffer, stride=16\)\(mixed,mixed,mixed,mixed\)|\S+)\s*(.*)', instruction.strip())
        op, tail = match.groups()
        args = split_args(tail) if tail else []
        if op == 'ret':
            continue
        writes = []
        if op == 'store_structured':
            read(args[1], [0], number)
            read(args[2], [0], number)
            read(args[3], [LANES.index(x) for x in args[0].split('.')[1]], number)
        elif op.startswith('ld_structured_indexable'):
            read(args[1], [0], number)
            read(args[2], [0], number)
            writes = [destination(args[0])]
        elif op.startswith('ld_indexable(texture2d)'):
            read(args[1], [0,1,3], number)
            writes = [destination(args[0])]
        elif op == 'sincos':
            writes = [destination(a) for a in args[:2] if a != 'null']
            positions = sorted({LANES.index(lane) for _, mask in writes for lane in mask})
            read(args[2], positions, number)
        else:
            reg, mask = destination(args[0])
            positions = list(range(int(op[-1]))) if op in ['dp2','dp3'] else [LANES.index(x) for x in mask]
            for source in args[1:]:
                read(source, positions, number)
            writes = [(reg, mask)]
        for reg, mask in writes:
            defined[reg].update(mask)
    return dict(status='passed', live_register_component_reads=reads,
                meaning='All actually consumed lanes are defined earlier in this straight-line program; zero-filled unused lanes do not supply live values. CB accesses fit executable declaration.')


def generate(text, event, mad_mode, dot_mode, mode='in_place', division='native', fp_order='precise', separate_mad=(), uniform_fold='none', velocity_depth_fold=False, velocity_dot='separate'):
    lane_audit = audit_defined_lanes(text)
    if fp_order=='refactoring_allowed' and 'dcl_globalFlags refactoringAllowed' not in text:
        raise ValueError('ORIGINAL_REFACTORING_PERMISSION_ABSENT')
    if re.search(r'dcl_thread_group\s+32, 32, 1', text) is None:
        raise ValueError('THREAD_LAYOUT_CHANGED')
    if re.search(r'dcl_uav_structured u0, 16', text) is None:
        raise ValueError('UAV_LAYOUT_CHANGED')
    count = int(re.search(r'dcl_temps (\d+)', text)[1])
    cb_count = int(re.search(r'dcl_constantbuffer CB0\[(\d+)\]', text)[1])
    header = '''#[compute]
#version 450
// Mechanical packed-uint lowering of frozen original DXBC, not original HLSL.
// Same logical in-place water alias and 32x32 threads. No intra-dispatch barrier added.
layout(local_size_x=32,local_size_y=32,local_size_z=1) in;
layout(set=0,binding=0,std430) buffer Water {uvec4 waterCells[];};
layout(set=0,binding=1,std430) readonly buffer Constants {uvec4 constants[];};
'''
    if event in [1484, 1537]:
        header += 'layout(set=0,binding=2,std430) readonly buffer Auxiliary {uvec4 auxiliaryCells[];};\n'
    if event == 1537:
        header += 'layout(set=0,binding=3,rg16f) readonly uniform image2D sourceTexture;\n'
    if mode == 'snapshot':
        header = header.replace('// Same logical in-place water alias and 32x32 threads. No intra-dispatch barrier added.', '// Explicit readonly snapshot adaptation with separate output, 32x32 threads; not original in-place.')
        header += 'layout(set=0,binding=4,std430) readonly buffer Snapshot {uvec4 readCells[];};\n'
    elif mode != 'in_place':
        raise ValueError('UNSUPPORTED_EXECUTION_MODE')
    header += '''float dx_dp2(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float sum=m0+m1;return sum;}
float dx_dp3(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float m2=a.z*b.z;precise float sum=m0+m1;precise float total=sum+m2;return total;}
'''
    if dot_mode == 'fma':
        header += '#define dx_dp2(a,b) fma((a).x,(b).x,(a).y*(b).y)\n#define dx_dp3(a,b) fma((a).z,(b).z,fma((a).y,(b).y,(a).x*(b).x))\n'
    header += 'void main(){\n uvec4 vThreadID=uvec4(gl_GlobalInvocationID,0u);\n'
    for index in range(count):
        header += ' uvec4 r' + str(index) + '=uvec4(0u);\n'
    lines, records = [header], []
    for number, instruction in re.findall(r'^\s*(\d+):\s+([^\n\r]+)', text, re.M):
        match = re.fullmatch(r'(ld_structured_indexable\(structured_buffer, stride=16\)\(mixed,mixed,mixed,mixed\)|\S+)\s*(.*)', instruction.strip())
        if not match:
            raise ValueError('INSTRUCTION_PARSE:' + instruction)
        opcode, tail = match.groups()
        args = split_args(tail) if tail else []
        lines.append(' // DXBC ' + number + ': ' + instruction.strip())
        temp = 't' + number
        if opcode == 'ret':
            lines.append(' return;')
        elif opcode == 'store_structured':
            if args[0] != 'u0.xyzw':
                raise ValueError('PARTIAL_STORE_NOT_MODELED')
            lines.append(' uvec4 ' + temp + '=' + uexpr(args[3]) + ';')
            if args[2] != 'l(0x00000000)':
                raise ValueError('NONZERO_STRUCT_STORE_OFFSET')
            lines.append(' waterCells[(' + uexpr(args[1]) + ').x]=' + temp + ';')
        elif opcode.startswith('ld_structured_indexable'):
            reg, mask = destination(args[0])
            resource, swizzle = args[3].split('.')
            if resource not in (['u0', 't0'] if event == 1484 else ['u0', 't1'] if event == 1537 else ['u0']):
                raise ValueError('UNMODELED_RESOURCE:' + resource)
            buffer = ('readCells' if mode == 'snapshot' else 'waterCells') if resource == 'u0' else 'auxiliaryCells'
            offset_match = re.fullmatch(r'l\((0x[0-9a-fA-F]{8})\)', args[2])
            if not offset_match:
                raise ValueError('EXACT_BYTE_OFFSET_LITERAL_REQUIRED')
            offset = int(offset_match[1], 16)
            if offset % 4:
                raise ValueError('UNALIGNED_STRUCTURED_OFFSET')
            lines.append(' uvec4 cell' + number + '=' + buffer + '[(' + uexpr(args[1]) + ').x];')
            lines.append(' uvec4 ' + temp + '=uvec4(0u);')
            for lane in mask:
                component = offset // 4 + LANES.index(swizzle[LANES.index(lane)])
                if component >= 4:
                    raise ValueError('CROSS_ELEMENT_STRUCTURED_LOAD')
                lines.append(' ' + temp + '.' + lane + '=cell' + number + '.' + LANES[component] + ';')
            lines.append(' ' + reg + '.' + mask + '=' + temp + '.' + mask + ';')
        elif opcode.startswith('ld_indexable(texture2d)'):
            if event != 1537:
                raise ValueError('UNEXPECTED_TEXTURE')
            reg, mask = destination(args[0])
            resource, swizzle = args[2].split('.')
            if resource != 't0':
                raise ValueError('UNEXPECTED_TEXTURE_SLOT')
            lines.append(' ivec4 coord' + number + '=ivec4(' + uexpr(args[1]) + ');')
            lines.append(' vec4 tex' + number + '=vec4(0);')
            lines.append(' if(all(greaterThanEqual(coord' + number + '.xy,ivec2(0)))&&all(lessThan(coord' + number + '.xy,imageSize(sourceTexture)))&&coord' + number + '.w==0){tex' + number + '=vec4(imageLoad(sourceTexture,coord' + number + '.xy).rg,0.0,1.0);}')
            lines.append(' uvec4 ' + temp + '=floatBitsToUint(tex' + number + '.' + swizzle + ');')
            lines.append(' ' + reg + '.' + mask + '=' + temp + '.' + mask + ';')
        elif opcode == 'sincos':
            lines.append(' precise vec4 f' + number + '=' + fexpr(args[2]) + ';')
            for target, func in zip(args[:2], ['sin', 'cos']):
                if target != 'null':
                    reg, mask = destination(target)
                    lines.append(' ' + reg + '.' + mask + '=floatBitsToUint(' + func + '(f' + number + ')).' + mask + ';')
        else:
            reg, mask = destination(args[0])
            src = args[1:]
            u = [uexpr(s) for s in src]
            f = [fexpr(s) for s in src]
            is_float = False
            if opcode in ['add', 'mul', 'div', 'mul_sat', 'div_sat']:
                symbol = {'add':'+','mul':'*','div':'/','mul_sat':'*','div_sat':'/'}[opcode]
                if opcode.startswith('div') and division=='rcp_mul':
                    lines.append(' precise vec4 inv' + number + '=vec4(1.0)/' + f[1] + ';')
                    expr = '(' + f[0] + '*inv' + number + ')'
                else:
                    expr = '(' + f[0] + symbol + f[1] + ')'
                if opcode.endswith('_sat'):
                    expr = 'clamp(' + expr + ',vec4(0),vec4(1))'
                is_float = True
            elif opcode == 'mad':
                expr = 'fma(' + ','.join(f) + ')' if mad_mode == 'fma' and int(number) not in separate_mad else '(' + f[0] + '*' + f[1] + '+' + f[2] + ')'
                if uniform_fold == 'advection_dt' and event == 1500 and int(number) == 16:
                    expected = 'mad r0.yz, -r0.yyzy, cb0[157].zzzz, r2.zzwz'
                    if instruction.strip() != expected or mad_mode != 'fma' or separate_mad:
                        raise ValueError('UNIFORM_FOLD_TEMPLATE_CHANGED')
                    # Counterfactual expression model of permitted cross-instruction refactoring.
                    # t9 contains the pre-scale division; both factors are uniform CB values.
                    lines.append(' precise vec4 foldedAdvectionDt=uintBitsToFloat(constants[158]).zzzz*uintBitsToFloat(constants[157]).zzzz;')
                    expr = 'fma(-uintBitsToFloat(t9),foldedAdvectionDt,' + f[2] + ')'
                if velocity_depth_fold and event == 1490 and int(number) == 118:
                    expected = 'mad r2.yz, -r5.xxyx, cb0[157].zzzz, r2.yyzy'
                    if instruction.strip() != expected or mad_mode != 'fma' or separate_mad:
                        raise ValueError('VELOCITY_DEPTH_FOLD_TEMPLATE_CHANGED')
                    lines.append(' precise vec4 foldedDepthDt=uintBitsToFloat(r0).zzzz*uintBitsToFloat(constants[157]).zzzz;')
                    expr = 'fma(' + f[2] + ',-foldedDepthDt,' + f[2] + ')'
                is_float = True
            elif opcode in ['min', 'max']:
                expr = opcode + '(' + ','.join(f) + ')'
                is_float = True
            elif opcode in ['sqrt', 'rsq', 'exp', 'round_ni', 'frc']:
                expr = {'sqrt':'sqrt','rsq':'inversesqrt','exp':'exp2','round_ni':'floor','frc':'fract'}[opcode] + '(' + f[0] + ')'
                is_float = True
            elif opcode in ['dp2', 'dp3']:
                expr = 'vec4(dx_' + opcode + '(' + ','.join(f) + '))'
                if velocity_dot == 'fma_y' and event == 1490 and int(number) == 134:
                    if instruction.strip() != 'dp2 r0.z, r5.xyxx, r5.xyxx':
                        raise ValueError('VELOCITY_DOT_TEMPLATE_CHANGED')
                    lines.append(' precise float dot134m0=(' + f[0] + ').x*(' + f[1] + ').x;')
                    expr = 'vec4(fma((' + f[0] + ').y,(' + f[1] + ').y,dot134m0))'
                is_float = True
            elif opcode in ['itof', 'utof']:
                expr = 'vec4(' + ('ivec4(' + u[0] + ')' if opcode == 'itof' else u[0]) + ')'
                is_float = True
            elif opcode in ['ftoi', 'ftou']:
                expr = 'uvec4(' + ('ivec4(' + f[0] + ')' if opcode == 'ftoi' else f[0]) + ')'
            elif opcode == 'mov':
                expr = u[0]
            elif opcode in ['iadd', 'imad', 'and', 'or', 'ushr', 'ishl']:
                expr = {'iadd':lambda:'('+u[0]+'+'+u[1]+')', 'imad':lambda:'('+u[0]+'*'+u[1]+'+'+u[2]+')',
                        'and':lambda:'('+u[0]+'&'+u[1]+')', 'or':lambda:'('+u[0]+'|'+u[1]+')',
                        'ushr':lambda:'('+u[0]+'>>('+u[1]+'&uvec4(31u)))', 'ishl':lambda:'('+u[0]+'<<('+u[1]+'&uvec4(31u)))'}[opcode]()
            elif opcode in ['imin', 'imax']:
                expr = 'uvec4(' + opcode[1:] + '(' + ','.join('ivec4('+x+')' for x in u) + '))'
            elif opcode in ['ge', 'lt', 'ige']:
                comp = 'lessThan' if opcode == 'lt' else 'greaterThanEqual'
                operands = ['ivec4('+x+')' for x in u] if opcode == 'ige' else f
                expr = 'mix(uvec4(0u),uvec4(0xffffffffu),' + comp + '(' + ','.join(operands) + '))'
            elif opcode == 'movc':
                expr = 'mix(' + u[2] + ',' + u[1] + ',notEqual(' + u[0] + ',uvec4(0u)))'
            elif opcode in ['bfi', 'ubfe']:
                pieces = []
                for lane in LANES:
                    component = lambda x:'('+x+').'+lane
                    width, offset = component(u[0]), component(u[1])
                    if opcode == 'bfi':
                        pieces.append('bitfieldInsert('+component(u[3])+','+component(u[2])+',int('+offset+'),int('+width+'))')
                    else:
                        pieces.append('bitfieldExtract('+component(u[2])+',int('+offset+'),int('+width+'))')
                expr = 'uvec4(' + ','.join(pieces) + ')'
            else:
                raise ValueError('UNMODELED_OPCODE:' + opcode)
            if is_float:
                lines.append(' precise vec4 f' + number + '=' + expr + ';')
                expr = 'floatBitsToUint(f' + number + ')'
            lines.append(' uvec4 ' + temp + '=' + expr + ';')
            lines.append(' ' + reg + '.' + mask + '=' + temp + '.' + mask + ';')
        records.append(dict(instruction=int(number), opcode=opcode, original=instruction.strip()))
    lines.append('}')
    output='\n'.join(lines)+'\n'
    if uniform_fold != 'none' or velocity_depth_fold or velocity_dot != 'separate':
        output=output.replace('// Mechanical packed-uint lowering of frozen original DXBC, not original HLSL.', '// Packed-uint DXBC lowering with explicit recorded arithmetic expression models, not original HLSL.')
    if fp_order=='refactoring_allowed':
        output=output.replace('precise ','')
    return output, dict(event=event, instructions=records, cb_bytes=cb_count*16,
                                             mad_mode=mad_mode, dot_mode=dot_mode,
                                             execution_mode=mode,
                                             division_model=division,
                                             fp_order=fp_order,
                                             separate_mad_instructions=list(separate_mad),
                                             uniform_product_fold=uniform_fold if event == 1500 else 'none',
                                             velocity_depth_product_fold=velocity_depth_fold if event == 1490 else False,
                                             velocity_dot_model=velocity_dot if event == 1490 else 'unchanged',
                                             lowering_kind='literal_instructions_with_explicit_arithmetic_models' if (uniform_fold != 'none' or velocity_depth_fold or velocity_dot != 'separate') else 'literal_instruction_lowering',
                                             live_lane_audit=lane_audit,
                                             undefined_unused_temp_initialization='Only unused lanes initialized zero; static live-lane audit passed',
                                             alias=('Explicit separate readonly snapshot and output SSBOs; not original in-place' if mode=='snapshot' else 'Single uvec4 waterCells SSBO read/write with stride16 and full element stores; no in-dispatch synchronization'))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--exact', required=True, type=Path)
    ap.add_argument('--project', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--mad', choices=['fma', 'separate'], default='fma')
    ap.add_argument('--dot', choices=['fma', 'separate'], default='separate')
    ap.add_argument('--mode', choices=['in_place','snapshot'], default='in_place')
    ap.add_argument('--division', choices=['native','rcp_mul'], default='native')
    ap.add_argument('--fp-order', choices=['precise','refactoring_allowed'], default='precise')
    ap.add_argument('--separate-mad', default='', help='Explicit event:instruction comma pairs for observed rounding diagnostics')
    ap.add_argument('--uniform-fold', choices=['none','advection_dt'], default='none', help='Explicit algebraic model, not literal instruction lowering')
    ap.add_argument('--velocity-depth-fold', action='store_true', help='Explicit reassociation of depth, dt and velocity product at e1490 instruction118')
    ap.add_argument('--velocity-dot',choices=['separate','fma_y'],default='separate',help='Explicit e1490 DP2 implementation model')
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    manifest = json.loads((args.exact / 'manifest.json').read_text())
    for item in manifest['artifacts']:
        if identity(item['path'])['sha256'] != item['sha256']:
            raise ValueError('Exact export changed')
    rows = []
    overrides = {}
    for pair in args.separate_mad.split(',') if args.separate_mad else []:
        event, number = map(int, pair.split(':'))
        if event not in EVENTS:
            raise ValueError('UNKNOWN_MAD_OVERRIDE_EVENT')
        overrides.setdefault(event, []).append(number)
    for event in EVENTS:
        source = args.exact / ('e' + str(event) + '_exact.asm')
        original_text = source.read_text()
        for number in overrides.get(event, []):
            if not re.search(r'^\s*'+str(number)+r':\s+mad\s', original_text, re.M):
                raise ValueError('MAD_OVERRIDE_NOT_MAD')
        text, record = generate(original_text, event, args.mad, args.dot, args.mode, args.division,args.fp_order,overrides.get(event, []),args.uniform_fold,args.velocity_depth_fold,args.velocity_dot)
        target = args.project / 'shaders' / ('e' + str(event) + ('_snapshot' if args.mode=='snapshot' else '_inplace') + '.glsl')
        target.write_text(text, encoding='utf-8')
        shutil.copyfile(target, out / target.name)
        record.update(source=identity(source), shader=identity(target))
        rows.append(record)
    for name in ['lower_dxbc_glsl.py','evidence_contract.py']:
        shutil.copyfile(Path(__file__).parent / name, out / name)
    report = dict(operation_status='complete', verification_status='not_evaluated',
                  scope='Candidate GLSL lowering only, not shader compilation, numeric or G5 acceptance',
                  exact_source=identity(args.exact / 'manifest.json'), programs=rows)
    (out / 'lowering.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(dict(operation_status='complete', verification_status='not_evaluated', artifacts=[identity(p) for p in out.iterdir() if p.is_file()]), indent=2), encoding='utf-8')
    print(json.dumps(dict(programs=len(rows), instructions=sum(len(r['instructions']) for r in rows))))


if __name__ == '__main__':
    main()
