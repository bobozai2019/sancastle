from pathlib import Path
s = '''[gd_scene load_steps=8 format=3]
[ext_resource type="Script" path="res://tests/water_momentum_lab/lab_entry.gd" id="1"]
[ext_resource type="Shader" path="res://tests/water_momentum_lab/shaders/view.gdshader" id="2"]
[sub_resource type="PlaneMesh" id="Plane"]
size = Vector2(32,32)
subdivide_width = 255
subdivide_depth = 255
[sub_resource type="ShaderMaterial" id="SandMat"]
resource_local_to_scene = true
shader = ExtResource("2")
[sub_resource type="ShaderMaterial" id="WaterMat"]
resource_local_to_scene = true
shader = ExtResource("2")
shader_parameter/water_layer = true
[sub_resource type="Environment" id="Env"]
background_mode = 1
background_color = Color(0.025,0.045,0.065,1)
[sub_resource type="BoxMesh" id="Base"]
size = Vector3(32,0.2,32)
[node name="WaterMomentumLab" type="Node3D"]
script = ExtResource("1")
[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env")
[node name="Camera" type="Camera3D" parent="."]
position = Vector3(-9.5,36,24)
rotation_degrees = Vector3(-56.3099,0,0)
projection = 1
size = 34.0
current = true
[node name="Light" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-60,-30,0)
[node name="Base" type="MeshInstance3D" parent="."]
position = Vector3(0,-0.15,0)
mesh = SubResource("Base")
[node name="Sand" type="MeshInstance3D" parent="."]
mesh = SubResource("Plane")
material_override = SubResource("SandMat")
custom_aabb = AABB(-16,-1,-16,32,8,32)
[node name="Water" type="MeshInstance3D" parent="."]
mesh = SubResource("Plane")
material_override = SubResource("WaterMat")
sorting_offset = 0.01
custom_aabb = AABB(-16,-1,-16,32,8,32)
[node name="Interface" type="CanvasLayer" parent="."]
[node name="Panel" type="PanelContainer" parent="Interface"]
offset_left = 12.0
offset_top = 12.0
offset_right = 342.0
offset_bottom = 620.0
[node name="Rows" type="VBoxContainer" parent="Interface/Panel"]
theme_override_constants/separation = 6
'''
controls = [
 ("Title","Label",'text = "Water momentum lab / independent GPU"'),
 ("Status","Label",'text = "Initializing..."\ncustom_minimum_size = Vector2(330,84)\nautowrap_mode = 3'),
 ("Mode","OptionButton",'item_count = 3\nselected = 2\npopup/item_0/text = "A0 / natural response"\npopup/item_0/id = 0\npopup/item_1/text = "A1 / raised-bed formula"\npopup/item_1/id = 1\npopup/item_2/text = "B / signed local impulse"\npopup/item_2/id = 2'),
 ("Fixture","OptionButton",'item_count = 7\nselected = 0\n'+"\n".join(f'popup/item_{i}/text = "{v}"\npopup/item_{i}/id = {i}' for i,v in enumerate(["Flat lake","Thin / wet-dry","Islands","Wall","20cm platform","80cm platform","Controlled initial wave"]))),
 ("Operation","OptionButton",'item_count = 3\nselected = 0\npopup/item_0/text = "Dig / left drag"\npopup/item_0/id = 0\npopup/item_1/text = "Fill / right drag"\npopup/item_1/id = 1\npopup/item_2/text = "Shovel / balanced shoulders"\npopup/item_2/id = 2'),
 ("View","OptionButton",'item_count = 4\nselected = 0\n'+"\n".join(f'popup/item_{i}/text = "{v}"\npopup/item_{i}/id = {i}' for i,v in enumerate(["Water and sand","Depth","Speed","Bed"]))),
 ("Arrows","CheckButton",'text = "Flow arrows"\nbutton_pressed = true'),
 ("GainLabel","Label",'text = "Impulse gain (m/s)"'),
 ("Gain","SpinBox",'max_value = 4.0\nstep = 0.01\ncustom_arrow_step = 0.25\nvalue = 1.0'),
 ("RadiusLabel","Label",'text = "Brush radius (m)"'),
 ("Radius","SpinBox",'min_value = 0.25\nmax_value = 2.0\nstep = 0.001\ncustom_arrow_step = 0.125\nvalue = 0.75'),
 ("Pause","Button",'text = "Pause / resume [Space]"'),
 ("Step","Button",'text = "One CFL step [N]"'),
 ("Reset","Button",'text = "Reset [R]"'),
 ("Replay","Button",'text = "Replay fixed 4m stroke"'),
 ("Export","Button",'text = "Export fields / metrics / screenshot"'),
 ("Hint","Label",'text = "Left: selected tool. Right: fill.\\nPicking plane y=0.5m."\nautowrap_mode = 3')]
for name,typ,props in controls:
 s+=f'[node name="{name}" type="{typ}" parent="Interface/Panel/Rows"]\n{props}\n'
for name,signal,method in [("Mode","item_selected","mode"),("Fixture","item_selected","fixture"),("View","item_selected","view"),("Arrows","toggled","arrows"),("Gain","value_changed","gain"),("Radius","value_changed","radius")]+[(n,"pressed",n.lower()) for n in ["Pause","Step","Reset","Replay","Export"]]:
 s+=f'[connection signal="{signal}" from="Interface/Panel/Rows/{name}" to="." method="_on_{method}"]\n'
Path("scenes/experiments/water_momentum_lab.tscn").write_text(s)
