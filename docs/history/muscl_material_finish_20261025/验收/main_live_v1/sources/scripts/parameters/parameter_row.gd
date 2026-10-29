extends VBoxContainer

@export var parameter_id: String
@onready var service=get_node("/root/Parameters")
@onready var editor=$Line/Value
var updating:=false
var _displayed_number_text:=""

func _ready() -> void:
	service.changed.connect(refresh)
	refresh()

func _color_changed(value: Color) -> void:_changed([value.r,value.g,value.b,1.0])

func _changed(value: Variant) -> void:
	if updating:return
	var error: StringName=service.set_value(parameter_id,value)
	if not error.is_empty():service.message="未修改："+String(error);service.changed.emit()

func pending_number() -> Dictionary:
	if not editor is SpinBox or not editor.editable:return {}
	if editor.get_line_edit().text==_displayed_number_text:return {}
	# Save buttons do not take focus. Commit typed text explicitly, without
	# refreshing other rows until the service has collected all pending values.
	var previous_value: float=editor.value
	updating=true
	editor.apply()
	updating=false
	# Untouched controls may display a rounded value; keep the full-precision
	# service value unless applying the user's text actually changed the control.
	if editor.value==previous_value:return {}
	return {"id":parameter_id,"value":editor.value}

func refresh() -> void:
	visible=service.row_visible(parameter_id)
	var state: Dictionary=service.describe(parameter_id)
	var available: bool=state.get("available",false)
	if editor is SpinBox:editor.editable=available
	else:editor.disabled=not available
	if state.is_empty():$Status.text="等待场景";return
	updating=true
	var value: Variant=state.value
	if editor is SpinBox:
		editor.set_value_no_signal(float(value))
		_displayed_number_text=editor.get_line_edit().text
	elif editor is CheckBox:editor.set_pressed_no_signal(value)
	elif editor is OptionButton:editor.select(int(value))
	elif editor is ColorPickerButton:editor.color=Color(value[0],value[1],value[2],1)
	$Status.text=state.status
	tooltip_text="默认：%s；当前有效：%s"%[str(state.default),str(state.effective)]
	updating=false
