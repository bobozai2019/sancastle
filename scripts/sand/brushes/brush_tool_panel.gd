extends PanelContainer

signal tool_changed(tool: StringName)
signal parameters_changed
var selected_tool: StringName=&"remove_sand"

func _on_tool_pressed(tool: StringName) -> void:
	selected_tool=tool;get_viewport().gui_release_focus();_update_groups();tool_changed.emit(tool)

func _ready() -> void:_update_groups()

func _update_groups() -> void:
	%Help.text="固定标高；[ / ] 旋转15°" if selected_tool==&"castle_v1" else "左键使用工具；参数从独立窗口调整"

func parameters() -> Dictionary:
	var service=get_node("/root/Parameters")
	return service.scene.tool_parameters() if is_instance_valid(service.scene) else {}

func apply_selection(selection: Dictionary) -> void:
	selected_tool=StringName(selection.tool)
	for button in $Margin/Controls/Tools.get_children():
		if button is Button:button.set_pressed_no_signal(StringName(button.get_meta("tool",_tool_for_button(button.name)))==selected_tool)
	_update_groups()

func _tool_for_button(button: StringName) -> StringName:
	return {&"Dig":&"remove_sand",&"Fill":&"place_sand",&"Castle":&"castle_v1",&"Wall":&"wall_v1",&"Shovel":&"shovel_v1",&"SuspendedSand":&"suspended_sand",&"GravelDrop":&"gravel_drop",&"Smooth":&"smooth_v1",&"Compact":&"compact_v1"}.get(button,&"")

func show_status(text: String, state: StringName=&"ready") -> void:
	%BrushStatus.text=text
	%BrushStatus.modulate=Color(1,.4,.3) if state==&"invalid" else (Color(1,.8,.3) if state==&"waiting" else Color(.6,1,.75))
