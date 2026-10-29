"""Guard the single UI definition without loading the simulation."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
BASE = 'res://scenes/components/beach_ui.tscn'
for key in ('main', 'test1_geometry'):
    path = ROOT / f'scenes/unified_edit/presentation/{key}.tscn'
    text = path.read_text(encoding='utf-8')
    assert text.count(f'path="{BASE}"') == 1, path
    assert '[node name="Interface"' not in text, path
    assert 'parent="Interface' not in text, path
    assert 'from="Interface/' not in text, path
for rel in ('scenes/main.tscn', 'scenes/playable/test1_geometry.tscn',
            'scenes/unified_edit/playable/main.tscn', 'scenes/unified_edit/playable/test1_geometry.tscn'):
    text = (ROOT / rel).read_text(encoding='utf-8')
    assert 'parent="Interface' not in text, rel
    assert 'from="Interface/' not in text, rel
text = (ROOT / BASE.removeprefix('res://')).read_text(encoding='utf-8')
for name in ('Interface', 'UIVisibility', 'UIDrag', 'ShapeBrushPanel', 'FloatingPropsPanel'):
    assert len(re.findall(r'^\[node name="'+name+'"', text, re.M)) == 1, name
for method in ('_on_tool_changed', '_on_prop_mode_changed', '_on_trigger_wave_pressed', '_toggle_pause', '_toggle_camera'):
    assert text.count(f'method="{method}"') == 1, method
print('SHARED_UI_STRUCTURE PASS')
