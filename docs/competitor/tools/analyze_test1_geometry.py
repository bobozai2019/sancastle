"""Verify and plot captured geometry; derived analysis, never original artwork."""
import argparse
import ctypes
import hashlib
import json
import struct
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap, LightSource
from matplotlib.font_manager import FontProperties


def identity(path):
    return {'path': str(path.resolve()), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def hex_disassemble(raw):
    dll = ctypes.WinDLL('d3dcompiler_47.dll')
    fn = dll.D3DDisassemble
    fn.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint, ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    fn.restype = ctypes.c_long
    blob = ctypes.c_void_p()
    src = ctypes.create_string_buffer(raw)
    hr = fn(src, len(raw), 0x80 | 0x20, None, ctypes.byref(blob))
    if hr < 0:
        raise RuntimeError(hr)
    vt = ctypes.cast(blob, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    ptr = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(vt[3])
    size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(vt[4])
    release = ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(vt[2])
    try:
        return ctypes.string_at(ptr(blob), size(blob)).rstrip(b'\0').decode()
    finally:
        release(blob)


def stats(a):
    return dict(zip(['min', 'p10', 'p25', 'median', 'p75', 'p90', 'p99', 'max'],
                    np.percentile(a, [0, 10, 25, 50, 75, 90, 99, 100]).tolist()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--replay', required=True)
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    cap, out = Path(args.replay).resolve(), Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=False)
    manifest = json.loads((cap / 'manifest.json').read_text())
    assert manifest['pass']
    verified = []
    for row in manifest['exports']:
        got = identity(Path(row['path']))
        assert got['bytes'] == row['bytes'] and got['sha256'] == row['sha256'], row['path']
        verified.append(got)
    for stem in ('e5006_vs', 'e6083_vs', 'e6083_ps'):
        (out / (stem + '_hex.txt')).write_text(hex_disassemble((cap / (stem + '.dxbc')).read_bytes()), encoding='utf-8')
    asm = (out / 'e5006_vs_hex.txt').read_text()
    # Check exact immediate instead of using rounded RenderDoc decimal printing.
    assert '0x3521999b' in asm or '0x3521999a' in asm
    scale_bits = 0x3521999b if '0x3521999b' in asm else 0x3521999a
    scale = np.float32(struct.unpack('<f', struct.pack('<I', scale_bits))[0])
    ground = np.fromfile(cap / 'e5006_vs_buffer0.bin', dtype='<u4').reshape(512, 1024, 4)
    heights = (((ground[:, :, 2] >> 12) | (ground[:, :, 3] << 20)) & 0xffffff).astype(np.float32) * scale
    water = np.fromfile(cap / 'e5006_vs_buffer1.bin', dtype='<u4').reshape(256, 512, 4)
    amount = (water[:, :, 2] & 0xffffff).astype(np.float32) * scale
    floor = (((water[:, :, 2] >> 24) | (water[:, :, 3] << 8)) & 0xffffff).astype(np.float32) * scale
    depth = np.maximum(amount - np.float32(.05), np.float32(0))
    assert np.isfinite(heights).all() and np.isfinite(depth).all()
    cb = np.fromfile(cap / 'e5006_vs_cb0.bin', dtype='<f4').reshape(-1, 4)
    ci = cb.view('<i4')
    assert cb[116, 0] == 30 and cb[116, 2] == 15
    assert list(ci[139, :2]) == [1024, 512]
    x = (np.arange(1024) + .5) * 30 / 1024 - 15
    z = (np.arange(512) + .5) * 15 / 512 - 7.5
    comparisons = []
    for event in (5006, 5018, 5030):
        v = np.fromfile(cap / ('e%d_vsout.bin' % event), dtype='<f4').reshape(-1, 22)[:, 4:7]
        ix = np.clip((np.clip(v[:, 0] / 30 + .5, 0, 1) * 1024 - .5), 0, 1023).astype(int)
        iz = np.clip((np.clip(v[:, 2] / 15 + .5, 0, 1) * 512 - .5), 0, 511).astype(int)
        comparisons.append({'event': event, 'bounds_min': v.min(0).tolist(), 'bounds_max': v.max(0).tolist(),
                            'against_e5006_buffer_max_abs_error': float(np.abs(heights[iz, ix] - v[:, 1]).max())})
    assert comparisons[0]['against_e5006_buffer_max_abs_error'] <= 1e-6
    heights.astype('<f4').tofile(out / 'sand_surface_1024x512.f32')
    depth.astype('<f4').tofile(out / 'water_depth_512x256.f32')
    bands = []
    for left in range(-15, 15, 5):
        mask = (x >= left) & (x < left + 5)
        bands.append({'x_range': [left, left+5], 'height': stats(heights[:, mask])})
    report = {'source': manifest['source'], 'replay_manifest': identity(cap / 'manifest.json'),
              'tool': identity(Path(__file__)), 'python_command': 'python docs/competitor/tools/analyze_test1_geometry.py --replay ' + str(cap) + ' --out ' + str(out),
              'versions': {'numpy': np.__version__, 'matplotlib': matplotlib.__version__},
              'verified_exports': verified, 'dimensions': [1024, 512], 'domain_xz': [[-15, 15], [-7.5, 7.5]],
              'grid_pitch': 30 / 1024, 'height_scale_bits': hex(scale_bits), 'height_scale': float(scale),
              'height_decode': '(((uint2 >> 12) | (uint3 << 20)) & 0xffffff) * float32(scale)',
              'surface_height': stats(heights), 'water_depth': stats(depth), 'bands': bands,
              'vsout_comparisons': comparisons,
              'sample_area': {str(t): {'dry_fraction': float(np.mean(depth <= t)), 'wet_fraction': float(np.mean(depth > t)),
                                     'dry_area_scene_units_squared': float(np.mean(depth <= t) * 450)} for t in (1e-5, .005, .02)},
              'limits': ['Scene units, physical meter scale unknown.',
                         'Height above origin is not proof of excavatable material thickness or rock/sand split.',
                         'Wet mask is sampled water field, not exact rasterized coastline or permanent boundary.',
                         'Other-event VSOut differences include replay/state effects; not all attributed to float precision.',
                         'Plot excludes independently drawn objects, but ground deformation caused by them remains.',
                         '3D plot uses strided visualization only; full resolution data retained.'],
              'derivatives': []}
    font = FontProperties(fname='C:/Windows/Fonts/msyh.ttc')
    plt.rcParams['font.family'] = font.get_name()
    plt.rcParams['axes.unicode_minus'] = False
    plt.rcParams['font.size'] = 10
    cmap = LinearSegmentedColormap.from_list('sand_height', ['#73583b', '#c7a96b', '#e5ce96', '#fff3cb'])
    fig = plt.figure(figsize=(16, 9), facecolor='#f7f5ef', layout='constrained')
    grid = fig.add_gridspec(2, 2, width_ratios=[1.1, 1], height_ratios=[1, .9])
    ax = fig.add_subplot(grid[0, 0])
    im = ax.imshow(heights, extent=(-15, 15, -7.5, 7.5), origin='lower', cmap=cmap, vmin=0, vmax=3)
    ax.contour(depth, levels=[.005], extent=(-15, 15, -7.5, 7.5), origin='lower', colors=['#0b9ba6'], linewidths=.9)
    ax.set(title='完整沙面俯视图 · 蓝线为本帧水深 0.005 的采样边界', xlabel='X（场景单位，右侧向海）', ylabel='Z（场景单位）')
    fig.colorbar(im, ax=ax, shrink=.78, label='沙面高度 Y（色标在 3 处截顶）')
    ax3 = fig.add_subplot(grid[:, 1], projection='3d')
    xx, zz = np.meshgrid(x[::4], z[::4])
    yy = heights[::4, ::4]
    colors = LightSource(azdeg=300, altdeg=45).shade(yy, cmap=cmap, vert_exag=1, dx=30/256, dy=15/128, blend_mode='soft')
    ax3.plot_surface(xx, zz, yy, facecolors=colors, rstride=1, cstride=1, linewidth=0, antialiased=False, shade=False)
    ax3.set(xlabel='X', ylabel='Z', zlabel='Y', title='直接由沙面缓冲重建的形状\n仅沙地；示意光照与机位，不是原游戏渲染', xlim=(-15,15), ylim=(-7.5,7.5), zlim=(0,7))
    ax3.set_box_aspect((30,15,7))
    ax3.view_init(elev=37, azim=-65)
    ax3.set_facecolor('#f7f5ef')
    section = fig.add_subplot(grid[1, 0])
    for target, color in [(-4, '#b38543'), (0, '#247b89'), (3, '#934c32')]:
        row = int(np.argmin(abs(z-target)))
        section.plot(x, heights[row], color=color, label='Z≈%g 剖面' % target)
    section.axhline(0, color='#555555', linewidth=.8)
    section.set(xlim=(-15,15), ylim=(0,7), xlabel='X（场景单位）', ylabel='沙面高度 Y', title='陆侧 → 海侧的高度剖面：基础坡面叠加局部堆沙')
    section.grid(alpha=.2)
    section.legend(frameon=False, loc='upper left')
    fig.suptitle('test1 几何核对  |  30 × 15  |  1024 × 512 沙格  |  最高约 6.64', fontsize=18, fontweight='bold')
    fig.supxlabel('2026-10-18 · 单帧实际缓冲的派生图；未标定现实米制；高度不直接等于可挖沙厚度', fontsize=11)
    fig.savefig(out / 'geometry_overview.png', dpi=120)
    plt.close(fig)
    for path in out.iterdir():
        if path.is_file():
            report['derivatives'].append(identity(path))
    (out / 'analysis.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({k: report[k] for k in ('surface_height', 'sample_area', 'vsout_comparisons')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
