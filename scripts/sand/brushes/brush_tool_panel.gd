extends PanelContainer

signal tool_changed(tool: StringName)
signal parameters_changed

var selected_tool: StringName = &"remove_sand"
@onready var groups := {&"remove_sand": %OrdinaryParams, &"place_sand": %OrdinaryParams, &"suspended_sand": %OrdinaryParams, &"gravel_drop": %GravelParams, &"castle_v1": %CastleParams, &"wall_v1": %WallParams, &"shovel_v1": %ShovelParams}

func _ready() -> void:
	_update_groups()

func _on_tool_pressed(tool: StringName) -> void:
	selected_tool=tool;get_viewport().gui_release_focus();_update_groups();tool_changed.emit(tool)

func _update_groups() -> void:
	for node in [%OrdinaryParams,%CastleParams,%WallParams,%ShovelParams,%GravelParams]:node.visible=groups[selected_tool]==node
	%Help.text="固定标高，低处补沙，高处保留\n[ / ] 旋转15°" if selected_tool==&"castle_v1" else ("按住左键拖动\n红色挖沟，青色两侧接收" if selected_tool==&"shovel_v1" else "按住左键拖动\n右键转向，WASD移动")
	if selected_tool == &"place_sand":
		%Help.text = "左键填高沙床，可在水下使用\n按住拖动连续填沙"
	elif selected_tool == &"suspended_sand":
		%Help.text = "左键向水中投放悬沙\n随水流移动，逐渐沉降；需有水"
	elif selected_tool == &"gravel_drop":
		%Help.text = "左键投碎石，拖动连续投放\n流水搬运，干地停留；最多1024颗"

func parameters() -> Dictionary:
	match selected_tool:
		&"gravel_drop":return {"count":int(%GravelCount.value)}
		&"castle_v1":return {"scale_xz":%CastleScale.value,"height_m":%CastleHeight.value,"yaw_rad":wrapf(deg_to_rad(%CastleYaw.value),-PI,PI)}
		&"wall_v1":return {"height_m":%WallHeight.value,"bottom_width_m":%WallBottom.value,"top_width_m":%WallTop.value}
		&"shovel_v1":return {"trench_width_m":%ShovelWidth.value,"depth_m":%ShovelDepth.value,"shoulder_width_m":%ShovelShoulder.value}
	return {}

func _on_value_changed(_value: float) -> void:
	parameters_changed.emit()

func rotate_castle(delta_degrees: float) -> void:
	%CastleYaw.value=wrapf(%CastleYaw.value+delta_degrees,-180.0,180.0)

func show_status(text: String, state: StringName = &"ready") -> void:
	%BrushStatus.text=text
	%BrushStatus.modulate=Color(1,0.4,0.3) if state==&"invalid" else (Color(1,0.8,0.3) if state==&"waiting" else Color(0.6,1,0.75))

func dig_amount() -> float:return %DigAmount.value
func fill_amount() -> float:return %FillAmount.value

func apply_selection(selection:Dictionary) -> void:
	var controls:Dictionary={"dig_amount_m3":%DigAmount,"fill_amount_m3":%FillAmount}
	var params:Dictionary=selection.parameters
	match StringName(selection.tool):
		&"gravel_drop":controls.merge({"count":%GravelCount})
		&"castle_v1":controls.merge({"scale_xz":%CastleScale,"height_m":%CastleHeight,"yaw_rad":%CastleYaw})
		&"wall_v1":controls.merge({"height_m":%WallHeight,"bottom_width_m":%WallBottom,"top_width_m":%WallTop})
		&"shovel_v1":controls.merge({"trench_width_m":%ShovelWidth,"depth_m":%ShovelDepth,"shoulder_width_m":%ShovelShoulder})
	for key in controls:
		var control:SpinBox=controls[key];control.set_block_signals(true)
		var value:float=selection[key] if key in ["dig_amount_m3","fill_amount_m3"] else params[key]
		control.value=rad_to_deg(value) if key=="yaw_rad" else value;control.set_block_signals(false)
	selected_tool=StringName(selection.tool)
	var buttons:Dictionary={&"remove_sand":%Dig,&"place_sand":%Fill,&"suspended_sand":%SuspendedSand,&"gravel_drop":%GravelDrop,&"castle_v1":%Castle,&"wall_v1":%Wall,&"shovel_v1":%Shovel}
	buttons[selected_tool].set_pressed_no_signal(true);_update_groups()
