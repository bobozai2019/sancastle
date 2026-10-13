extends Node3D
class_name Test1WaterMotionTrial

signal trial_ready
signal tick_completed(tick: int)
signal snapshot_saved(path: String)

const WIDTH := 512
const HEIGHT := 256
const CLOCK_DELTA := 0.025
const CAPTURE_LEVEL := 1.6163164377212524
const STATE_PATH := "res://assets/test1_water_motion/capture_state.rgba32f"
const AUX_PATH := "res://assets/test1_water_motion/capture_aux.rgba32f"
const COMPUTE := preload("res://shaders/simulation/test1_water_motion.glsl")
const Presentation := preload("res://scripts/visual/test1_main_presentation.gd")
@export_enum("release", "hold", "repeat") var motion_mode := "release"
@export var paused := false
var completed_ticks := 0
var ready_for_ticks := false
var tick_pending := false
var snapshot_pending := false
var last_error := ""
var accumulator := 0.0
var phase_index := 0
var rd: RenderingDevice
var textures: Array[RID] = []
var aux_texture := RID()
var shader := RID()
var pipeline := RID()
var sets: Array[RID] = []
var display := Texture2DRD.new()
var initial_bytes := PackedByteArray()
var closing := false
var pending_mode := ""
var presentation = Presentation.new()
var render_fields := {}
var flow_enabled := false
@onready var contact_material: ShaderMaterial = $ShoreContact.material_override
@onready var fine_material: ShaderMaterial = $FineFoam.material_override
@onready var flow_material: ShaderMaterial = $FlowOverlay.material_override
@onready var bed_material: ShaderMaterial = $Sand.material_override
@onready var water_material: ShaderMaterial = $Water.material_override
@onready var status: Label = $Interface/Panel/Margin/Controls/Status

func _ready() -> void:
	initial_bytes = FileAccess.get_file_as_bytes(STATE_PATH)
	var aux_bytes := FileAccess.get_file_as_bytes(AUX_PATH)
	if initial_bytes.size() != WIDTH * HEIGHT * 16 or aux_bytes.size() != initial_bytes.size():
		_fail("capture fields are missing or incomplete")
		return
	flow_material.set_shader_parameter("water_field", display)
	flow_material.set_shader_parameter("debug_flow", true)
	$ReflectionViewport.world_3d = get_viewport().world_3d
	var reflection: Texture2D = $ReflectionViewport.get_texture()
	water_material.set_shader_parameter("natural_planar_reflection_srgb", reflection)
	water_material.set_shader_parameter("prototype_planar_reflection", reflection)
	_update_reflection()
	RenderingServer.call_on_render_thread(_initialize_gpu.bind(aux_bytes))
	_update_status()

func _initialize_gpu(aux_bytes: PackedByteArray) -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		call_deferred("_fail", "Forward+/Mobile RenderingDevice required")
		return
	var format := RDTextureFormat.new()
	format.width = WIDTH
	format.height = HEIGHT
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	for i in 2:
		textures.append(rd.texture_create(format, RDTextureView.new(), [initial_bytes]))
	aux_texture = rd.texture_create(format, RDTextureView.new(), [aux_bytes])
	shader = rd.shader_create_from_spirv(COMPUTE.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)
	for i in 2:
		var uniforms: Array[RDUniform] = []
		var ids := [textures[i], textures[1 - i], aux_texture]
		for binding in 3:
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform.binding = binding
			uniform.add_id(ids[binding])
			uniforms.append(uniform)
		sets.append(rd.uniform_set_create(uniforms, shader, 0))
	if not presentation.initialize(rd, textures):
		call_deferred("_fail", "main presentation initialization failed")
		return
	call_deferred("_initialized", textures[0])

func _initialized(texture: RID) -> void:
	display.texture_rd_rid = texture
	_publish_presentation()
	ready_for_ticks = true
	_update_status()
	trial_ready.emit()

func _publish_presentation() -> void:
	var published: Dictionary = presentation.published()
	for name in published:
		if not render_fields.has(name):
			render_fields[name] = Texture2DRD.new()
		render_fields[name].texture_rd_rid = published[name]
	for material in [water_material, bed_material, contact_material, fine_material]:
		for uniform in material.shader.get_shader_uniform_list():
			var name: String = uniform.name
			var field := name.trim_suffix("_state")
			if render_fields.has(field):
				material.set_shader_parameter(name, render_fields[field])
			elif render_fields.has(name):
				material.set_shader_parameter(name, render_fields[name])
		material.set_shader_parameter("visual_time_s", float(completed_ticks) * CLOCK_DELTA)
	bed_material.set_shader_parameter("rdc_momentum_x", render_fields.momentum_x)
	bed_material.set_shader_parameter("rdc_momentum_z", render_fields.momentum_z)
	flow_material.set_shader_parameter("visual_clock", 90.16482543945312 + float(completed_ticks) * CLOCK_DELTA)
	fine_material.set_shader_parameter("viewport_height_px", float(get_viewport().get_visible_rect().size.y))
	_update_reflection()

func _update_reflection() -> void:
	var camera: Camera3D = $CaptureCamera
	var reflection: Camera3D = $ReflectionViewport/ReflectionCamera
	reflection.fov = camera.fov
	reflection.near = camera.near
	reflection.far = camera.far
	var position := camera.global_position
	position.y = -position.y
	var forward := -camera.global_basis.z
	forward.y = -forward.y
	var up := camera.global_basis.y
	up.y = -up.y
	reflection.global_position = position
	reflection.look_at(position + forward, up)
	water_material.set_shader_parameter("prototype_planar_view_projection", reflection.get_camera_projection() * Projection(reflection.global_transform.affine_inverse()))

func level_override(tick: int) -> float:
	var seconds := float(tick) * CLOCK_DELTA
	if motion_mode == "hold":
		return CAPTURE_LEVEL
	if motion_mode == "repeat":
		return CAPTURE_LEVEL * (0.5 + 0.5 * cos(TAU * seconds / 16.0))
	var u := clampf((seconds - 2.0) / 4.0, 0.0, 1.0)
	return CAPTURE_LEVEL * (1.0 - u * u * (3.0 - 2.0 * u))

func _process(delta: float) -> void:
	if not pending_mode.is_empty() and ready_for_ticks and not tick_pending and not snapshot_pending:
		var requested_mode := pending_mode
		pending_mode = ""
		_set_mode(requested_mode)
		return
	if not ready_for_ticks or closing or paused or not last_error.is_empty():
		return
	accumulator = minf(accumulator + delta, 0.1)
	if tick_pending or snapshot_pending or accumulator < CLOCK_DELTA:
		return
	accumulator -= CLOCK_DELTA
	tick_pending = true
	RenderingServer.call_on_render_thread(_dispatch_tick.bind(completed_ticks + 1, level_override(completed_ticks + 1)))

func _dispatch_phase(phase: float, clock: float, override_value: float) -> void:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, sets[phase_index], 0)
	var push := PackedFloat32Array([phase, clock, override_value, 0.0]).to_byte_array()
	rd.compute_list_set_push_constant(list, push, push.size())
	rd.compute_list_dispatch(list, WIDTH / 8, HEIGHT / 8, 1)
	rd.compute_list_end()
	phase_index = 1 - phase_index

func _dispatch_tick(tick: int, override_value: float) -> void:
	if closing:
		return
	var clock := 284.71783447265625 + float(tick) * CLOCK_DELTA
	for substep in 3:
		for phase in 3:
			_dispatch_phase(float(phase), clock, override_value)
	_dispatch_phase(3.0, clock, override_value)
	if not presentation.dispatch(phase_index, tick, CLOCK_DELTA):
		call_deferred("_fail", "main presentation tick failed")
		return
	call_deferred("_tick_finished", tick, textures[phase_index])

func _tick_finished(tick: int, texture: RID) -> void:
	if closing:
		return
	display.texture_rd_rid = texture
	completed_ticks = tick
	tick_pending = false
	_publish_presentation()
	_update_status()
	tick_completed.emit(tick)

func request_snapshot(path: String) -> bool:
	if not ready_for_ticks or tick_pending or snapshot_pending:
		return false
	snapshot_pending = true
	RenderingServer.call_on_render_thread(_read_snapshot.bind(path))
	return true

func _read_snapshot(path: String) -> void:
	var error := rd.texture_get_data_async(textures[phase_index], 0, _gpu_snapshot.bind(path))
	if error != OK:
		call_deferred("_fail", "snapshot read failed: " + str(error))

func _gpu_snapshot(bytes: PackedByteArray, path: String) -> void:
	call_deferred("_save_snapshot", bytes, path)

func _save_snapshot(bytes: PackedByteArray, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null or bytes.size() != initial_bytes.size():
		_fail("snapshot size/file error")
		return
	file.store_buffer(bytes)
	snapshot_pending = false
	snapshot_saved.emit(path)

func _set_mode(mode: String) -> void:
	if tick_pending or snapshot_pending or not ready_for_ticks:
		pending_mode = mode
		paused = true
		return
	motion_mode = mode
	ready_for_ticks = false
	completed_ticks = 0
	accumulator = 0.0
	paused = false
	# Detach RenderingServer aliases before releasing/rebuilding history textures.
	for name in ["foam_state", "foam_previous_state", "local_front_state"]:
		render_fields[name].texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_reset_gpu)

func _reset_gpu() -> void:
	for texture in textures:
		rd.texture_update(texture, 0, initial_bytes)
	phase_index = 0
	if not presentation.reset():
		call_deferred("_fail", "main presentation reset failed")
		return
	call_deferred("_initialized", textures[0])

func _on_release_pressed() -> void:
	_set_mode("release")

func _on_hold_pressed() -> void:
	_set_mode("hold")

func _on_repeat_pressed() -> void:
	_set_mode("repeat")

func _on_reset_pressed() -> void:
	_set_mode(motion_mode)

func _on_pause_pressed() -> void:
	paused = not paused
	_update_status()

func _on_flow_toggled(enabled: bool) -> void:
	flow_enabled = enabled
	$FlowOverlay.visible = enabled
	$Water.visible = not enabled
	$ShoreContact.visible = not enabled
	$FineFoam.visible = not enabled

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_on_pause_pressed()
		elif event.keycode == KEY_R:
			_on_reset_pressed()

func _update_status() -> void:
	if status == null:
		return
	var name := {"release": "水位下降 / 退水实验", "hold": "保持捕帧输入 / 对照", "repeat": "周期输入 / Godot适配"}
	var offset := level_override(completed_ticks)
	var visible_level := 0.95 + offset if offset > 0.0 else 0.95 + sin(284.71783447265625 + float(completed_ticks) * CLOCK_DELTA) * 0.049701884388923645
	status.text = "%s | %.2f s | Tick %d | %s\n可见海侧目标 %.3f 场景单位；沙床固定" % [name[motion_mode], float(completed_ticks) * CLOCK_DELTA, completed_ticks, "暂停" if paused else "运行", visible_level]

func _fail(message: String) -> void:
	last_error = message
	paused = true
	push_error(message)

func _exit_tree() -> void:
	closing = true
	display.texture_rd_rid = RID()
	for wrapper in render_fields.values():
		wrapper.texture_rd_rid = RID()
	if rd != null:
		var device := rd
		var resources := sets + textures + [aux_texture, pipeline, shader]
		RenderingServer.call_on_render_thread(func() -> void:
			presentation.release()
			for resource in resources:
				if resource.is_valid():
					device.free_rid(resource))
