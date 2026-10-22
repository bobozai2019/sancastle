"""One-time, idempotent extraction of parameter controls from formal scenes.

Preserves meshes/materials, removes only the listed UI subtrees, and refreshes
the presentation scene fingerprint after this explicit layout transformation.
"""
from pathlib import Path
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[2]
EDIT="Interface/EditPanel/Margin/Controls"
SHAPE="Interface/ShapeBrushPanel/Margin/Controls"
REMOVED=["Interface/PerformancePanel"]+[EDIT+"/"+x for x in ["Tools","DigLabel","DigAmount","FillLabel","FillAmount","WaveLabel","WaveAmount","WaveSettings","Help"]]+[SHAPE+"/"+x for x in ["OrdinaryParams","GravelParams","CastleParams","WallParams","ShovelParams","ConnectedDrainage","DrainageHint","MomentumGainLabel","MomentumGain","WaveSettings"]]


def removed(path):
    return any(path==prefix or path.startswith(prefix+"/") for prefix in REMOVED)


def transform(path):
    source=path.read_text(encoding="utf-8")
    parts=re.split(r'(?=^\[(?:node|connection) )',source,flags=re.M)
    retained=[parts[0]]
    for part in parts[1:]:
        header=part.splitlines()[0]
        if header.startswith('[node '):
            name=re.search(r'name="([^"]+)"',header).group(1)
            parent=re.search(r'parent="([^"]+)"',header)
            node_path=(parent.group(1)+"/" if parent and parent.group(1)!="." else "")+name
            if removed(node_path):continue
        else:
            origin=re.search(r'from="([^"]+)"',header).group(1)
            if removed(origin) or 'method="_on_parameters_changed"' in header:continue
        retained.append(part)
    source="".join(retained)
    if "/presentation/" in path.as_posix():
        source=source.replace("沙量 · 波浪 · 视角","场景操作").replace("参数窗口 ▾","参数窗口")
    if "/presentation/" in path.as_posix() and '[node name="ParameterWindows"' not in source:
        source+='''
[node name="ParameterWindows" type="MenuButton" parent="Interface/EditPanel/Margin/Controls"]
layout_mode = 2
text = "参数窗口"
focus_mode = 0
item_count = 6
popup/item_0/text = "工具参数"
popup/item_0/id = 0
popup/item_1/text = "水参数"
popup/item_1/id = 1
popup/item_2/text = "沙参数"
popup/item_2/id = 2
popup/item_3/text = "道具参数"
popup/item_3/id = 3
popup/item_4/text = "环境与显示"
popup/item_4/id = 4
popup/item_5/text = "性能与诊断"
popup/item_5/id = 5

[node name="Pause" type="Button" parent="Interface/EditPanel/Margin/Controls"]
layout_mode = 2
focus_mode = 0
text = "暂停／继续"

[node name="Camera" type="Button" parent="Interface/EditPanel/Margin/Controls"]
layout_mode = 2
focus_mode = 0
text = "切换视角"

[node name="Smooth" type="Button" parent="Interface/ShapeBrushPanel/Margin/Controls/Tools"]
layout_mode = 2
focus_mode = 0
toggle_mode = true
text = "平滑"

[node name="Compact" type="Button" parent="Interface/ShapeBrushPanel/Margin/Controls/Tools"]
layout_mode = 2
focus_mode = 0
toggle_mode = true
text = "压实"

[connection signal="pressed" from="Interface/ShapeBrushPanel/Margin/Controls/Tools/Smooth" to="Interface/ShapeBrushPanel" method="_on_tool_pressed" binds=[&"smooth_v1"]]
[connection signal="pressed" from="Interface/ShapeBrushPanel/Margin/Controls/Tools/Compact" to="Interface/ShapeBrushPanel" method="_on_tool_pressed" binds=[&"compact_v1"]]
'''
    path.write_text(source.rstrip()+"\n",encoding="utf-8")


def main():
    paths=list((ROOT/"scenes/unified_edit/presentation").glob("*.tscn"))
    paths+=list((ROOT/"scenes/unified_edit/playable").glob("*.tscn"))
    paths+=list((ROOT/"scenes/playable").glob("test1_*.tscn"))+[ROOT/"scenes/main.tscn",ROOT/"scenes/shape_brushes/brush_playable_candidate.tscn"]
    for path in paths:transform(path)
    for path in (ROOT/"assets/unified_edit/presentation").glob("*.json"):
        document=json.loads(path.read_text(encoding="utf-8"));meta=document['metadata']
        scene=ROOT/meta['scene']['path'].removeprefix('res://')
        meta['scene']['sha256']=hashlib.sha256(scene.read_bytes()).hexdigest()
        meta['nodes']=[node for node in meta.get('nodes',[]) if not removed(node['path'])]
        for node_name,cls,parent in [("ParameterWindows","MenuButton",EDIT),("Pause","Button",EDIT),("Camera","Button",EDIT),("Smooth","Button",SHAPE+"/Tools"),("Compact","Button",SHAPE+"/Tools")]:
            key=parent+"/"+node_name
            if not any(n['path']==key for n in meta['nodes']):meta['nodes'].append({'path':key,'class':cls,'script':''})
        path.write_text(json.dumps(document,ensure_ascii=False,indent='\t')+'\n',encoding='utf-8')


if __name__=='__main__':main()
