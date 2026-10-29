"""Extract explicitly adapted lifecycle methods; production sources stay read-only."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = (root / 'tests/visual_water_alignment/prototypes/reference_preview.gd').read_text(encoding='utf-8')
def method(name):
    start = source.index('func ' + name + '(')
    end = source.find('\nfunc ', start + 1)
    return source[start:end if end >= 0 else None].rstrip() + '\n'

setup = method('_render_setup')
start = setup.index('\tif not collision_proxy.setup_render')
end = setup.index('\t_publish_textures()', start)
setup = setup[:start] + setup[end:]
finish = method('_render_finish_tick')
start = finish.index('\tif enable_erosion:', finish.index('\t_publish_textures()'))
end = finish.index('\tif profile_tick_timing:', start)
finish = finish[:start] + finish[end:]
# Candidate inventory is intentionally nominal. Validate fields, never assert the
# production conservation ledger against this separate experiment.
audit = method('_record_sand_audit')
start = audit.index('\tif closure >')
end = audit.index('\tif revision >', start)
audit = audit[:start] + audit[end:]
target = root / 'scripts/experiments/approx_gpu_edit/trial_lifecycle.gd'
target.write_text('extends "res://assets/water_material_natural_candidate/compiled_worker_entry.gd"\n\n'
    '# Isolated copies of reference_preview lifecycle methods.\n'
    '# No collision setup, dirty-height readback, hover prefetch or exact ledger assertion.\n\n'
    + setup + '\n' + finish + '\n' + audit, encoding='utf-8')

sand_source = (root / 'scripts/simulation/edit_validation/gpu_sand_editor.gd').read_text(encoding='utf-8')
start = sand_source.index('func dispatch_sand_command(')
end = sand_source.index('\nfunc _receipt_ready(',start)
dispatch = sand_source[start:end]
dispatch = dispatch.replace('func dispatch_sand_command(data: PackedByteArray, callback: Callable)', 'func dispatch_without_cpu_receipt(data: PackedByteArray)')
dispatch = dispatch.replace(' or not callback.is_valid()', '')
start = dispatch.index('\tvar error: Error = rd.buffer_get_data_async(')
dispatch = dispatch[:start] + '\treceipt_pending = false\n\tpublication_pending = false\n\tstate_revision += 1\n\treturn true\n'
(root / 'scripts/experiments/approx_gpu_edit/exact_dispatch_adapter.gd').write_text(
    'extends "res://scripts/simulation/edit_validation/gpu_water_editor.gd"\n\n'
    '# Experimental submission revision; GPU control/receipt still checks candidate.\n'
    '# No CPU receipt or exact inventory claim. Read status only at diagnostic boundaries.\n'
    + dispatch, encoding='utf-8')
