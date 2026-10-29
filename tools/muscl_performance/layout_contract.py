"""Strict physical-to-logical momentum mapping; no numeric conversion."""
from pathlib import PurePosixPath

CELLS = 65536
SCALAR_BYTES = CELLS * 4
PACKED_BYTES = CELLS * 8


def pack(x, z):
    if len(x) != SCALAR_BYTES or len(z) != SCALAR_BYTES:
        raise ValueError('momentum_component_size')
    output = bytearray(PACKED_BYTES)
    for byte in range(4):
        output[byte::8] = x[byte::4]
        output[byte + 4::8] = z[byte::4]
    return bytes(output)


def split(raw):
    if len(raw) != PACKED_BYTES:
        raise ValueError('momentum_packed_size')
    x, z = bytearray(SCALAR_BYTES), bytearray(SCALAR_BYTES)
    for byte in range(4):
        x[byte::4] = raw[byte::8]
        z[byte::4] = raw[byte + 4::8]
    return bytes(x), bytes(z)


def normalize(members):
    """Only authority slots and explicit view publication have packed names."""
    output = dict(members)
    layouts = {}
    stems = {'momentum_0': ('momentum_x_0', 'momentum_z_0'),
             'momentum_1': ('momentum_x_1', 'momentum_z_1'),
             'view_momentum': ('view_momentum_x', 'view_momentum_z')}
    for name, raw in members.items():
        path = PurePosixPath(name)
        if path.stem not in stems or path.suffix != '.bin':
            continue
        names = [str(path.with_name(stem + '.bin')) for stem in stems[path.stem]]
        if any(n in output for n in names):
            raise ValueError('ambiguous_momentum_layout:' + name)
        del output[name]
        output.update(zip(names, split(raw)))
        layouts[str(path.parent)] = 'rg32f'
    # Require both components of every scalar pair and exact byte length.
    for name, raw in output.items():
        path = PurePosixPath(name)
        if path.stem.startswith(('momentum_x_', 'momentum_z_', 'view_momentum_x', 'view_momentum_z')):
            counterpart = str(path.with_name(path.name.replace('momentum_x', 'momentum_z')
                                             if 'momentum_x' in path.name else path.name.replace('momentum_z', 'momentum_x')))
            if counterpart not in output or len(raw) != SCALAR_BYTES:
                raise ValueError('incomplete_momentum_components:' + name)
            layouts.setdefault(str(path.parent), 'r32f_pair')
    return output, layouts


def differences(a, b):
    result = []
    for name in sorted(set(a) | set(b)):
        x, y = a.get(name), b.get(name)
        if x == y:
            continue
        offset = next((i for i, (u, v) in enumerate(zip(x, y)) if u != v), min(len(x), len(y))) if x is not None and y is not None else None
        result.append({'member': name, 'a_bytes': len(x) if x is not None else None,
                       'b_bytes': len(y) if y is not None else None, 'first_byte': offset,
                       'a_u32_hex': x[offset // 4 * 4:offset // 4 * 4 + 4].hex() if x is not None and offset is not None else None,
                       'b_u32_hex': y[offset // 4 * 4:offset // 4 * 4 + 4].hex() if y is not None and offset is not None else None})
    return result
