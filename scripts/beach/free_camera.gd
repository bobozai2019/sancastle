extends Camera3D

signal look_started
@export var move_speed_m_s := 5.0
@export var fast_multiplier := 3.0
@export var mouse_sensitivity := 0.003
var look_active := false

func _unhandled_input(event: InputEvent) -> void:
	if current and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		look_active=true
		# Remove look_at roll before mouse-controlled yaw/pitch.
		rotation.z=0.0
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		get_viewport().gui_release_focus()
		look_started.emit()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not current:
		_release_mouse()
		return
	if not look_active: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed:
		_release_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		_release_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		# Captured mouse movement should not depend on viewport stretch/DPI.
		var motion := event.screen_relative
		if motion.is_zero_approx(): motion = event.relative
		rotation.y-=motion.x*mouse_sensitivity
		rotation.x=clampf(rotation.x-motion.y*mouse_sensitivity,deg_to_rad(-89.0),deg_to_rad(89.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not current: _release_mouse();return
	var focused:=get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit or focused is SpinBox: return
	var direction:=Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): direction-=global_basis.z
	if Input.is_physical_key_pressed(KEY_S): direction+=global_basis.z
	if Input.is_physical_key_pressed(KEY_A): direction-=global_basis.x
	if Input.is_physical_key_pressed(KEY_D): direction+=global_basis.x
	if Input.is_physical_key_pressed(KEY_Q): direction-=Vector3.UP
	if Input.is_physical_key_pressed(KEY_E): direction+=Vector3.UP
	var speed:=move_speed_m_s*(fast_multiplier if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	global_position+=direction.normalized()*speed*delta

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT: _release_mouse()

func _release_mouse() -> void:
	if look_active: Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	look_active=false

func _exit_tree() -> void:
	_release_mouse()
