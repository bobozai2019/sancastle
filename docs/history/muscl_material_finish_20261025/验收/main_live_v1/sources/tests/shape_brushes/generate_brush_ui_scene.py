"""Author the static, inspectable tool panel; never run from the game."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
lines = ['[gd_scene load_steps=4 format=3]',
         '[ext_resource type="Script" path="res://scripts/sand/brushes/brush_tool_panel.gd" id="1"]',
         '[sub_resource type="ButtonGroup" id="Tools"]',
         '[sub_resource type="StyleBoxFlat" id="Panel"]',
         'bg_color = Color(0.06, 0.09, 0.12, 0.94)',
         'corner_radius_top_left = 10','corner_radius_top_right = 10',
         'corner_radius_bottom_left = 10','corner_radius_bottom_right = 10',
         '[node name="ShapeBrushPanel" type="PanelContainer"]',
         'custom_minimum_size = Vector2(296, 0)', 'script = ExtResource("1")',
         'theme_override_styles/panel = SubResource("Panel")',
         '[node name="Margin" type="MarginContainer" parent="."]', 'layout_mode = 2',
         'theme_override_constants/margin_left = 14','theme_override_constants/margin_right = 14',
         'theme_override_constants/margin_top = 12','theme_override_constants/margin_bottom = 12',
         '[node name="Controls" type="VBoxContainer" parent="Margin"]','layout_mode = 2',
         'theme_override_constants/separation = 7',
         '[node name="Title" type="Label" parent="Margin/Controls"]','layout_mode = 2','text = "沙形工具"',
         'theme_override_font_sizes/font_size = 20',
         '[node name="Tools" type="GridContainer" parent="Margin/Controls"]','layout_mode = 2','columns = 3']
connections = []
for name, text, tool in [('Dig','挖沙','remove_sand'),('Fill','填沙','place_sand'),('Castle','城堡','castle_v1'),('Shovel','铲子','shovel_v1'),('Wall','沙墙','wall_v1')]:
    path='Margin/Controls/Tools/'+name
    lines += [f'[node name="{name}" type="Button" parent="Margin/Controls/Tools"]',
              'unique_name_in_owner = true','layout_mode = 2','size_flags_horizontal = 3',
              'custom_minimum_size = Vector2(80, 36)','focus_mode = 0','toggle_mode = true',
              'button_group = SubResource("Tools")',f'text = "{text}"']
    if name=='Dig':lines += ['button_pressed = true']
    connections += [f'[connection signal="pressed" from="{path}" to="." method="_on_tool_pressed" binds= [ &"{tool}" ]]']
groups = {
    'OrdinaryParams': [('DigAmount','挖沙量 · m³ / 次',.01,1,.01,.1,'m³'),('FillAmount','填沙量 · m³ / 次',.01,1,.01,.1,'m³')],
    'CastleParams': [('CastleScale','城堡尺寸 · 4–6 m',1,1.5,.05,1,'×'),('CastleHeight','城堡最高高度',.5,1,.05,.7,'m'),('CastleYaw','水平旋转',-180,180,15,0,'°')],
    'WallParams': [('WallHeight','墙高',.15,.6,.05,.3,'m'),('WallBottom','底宽',1,2,.125,1,'m'),('WallTop','顶宽 · 不超过底宽',.5,1.5,.125,.5,'m')],
    'ShovelParams': [('ShovelWidth','沟宽',.5,1,.125,.5,'m'),('ShovelDepth','沟深',.05,.3,.05,.15,'m'),('ShovelShoulder','每侧肩部宽度',.5,1,.125,.5,'m')]}
for group, fields in groups.items():
    lines += [f'[node name="{group}" type="VBoxContainer" parent="Margin/Controls"]',
              'unique_name_in_owner = true','layout_mode = 2']
    if group!='OrdinaryParams':lines += ['visible = false']
    for name,label,low,high,step,value,suffix in fields:
        parent='Margin/Controls/'+group
        lines += [f'[node name="{name}Label" type="Label" parent="{parent}"]','layout_mode = 2',f'text = "{label}"',
                  f'[node name="{name}" type="SpinBox" parent="{parent}"]','unique_name_in_owner = true','layout_mode = 2',
                  f'min_value = {low}',f'max_value = {high}',f'step = {step}',f'value = {value}',f'suffix = "{suffix}"']
        connections += [f'[connection signal="value_changed" from="{parent}/{name}" to="." method="_on_value_changed"]']
lines += ['[node name="Help" type="Label" parent="Margin/Controls"]','unique_name_in_owner = true',
          'layout_mode = 2','autowrap_mode = 3','text = "左键使用工具；右键转向"',
          '[node name="BrushStatus" type="Label" parent="Margin/Controls"]','unique_name_in_owner = true',
          'layout_mode = 2','autowrap_mode = 3','text = "等待沙场准备"']
path=ROOT/'scenes/components/brushes/brush_tool_panel.tscn';path.parent.mkdir(parents=True,exist_ok=True)
path.write_text('\n\n'.join(lines+connections)+'\n',encoding='utf-8')
print(path)
