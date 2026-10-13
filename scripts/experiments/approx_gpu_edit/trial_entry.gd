extends "res://scripts/experiments/approx_gpu_edit/trial_lifecycle.gd"

const TrialSolver = preload("res://scripts/experiments/approx_gpu_edit/trial_solver.gd")
@export var trial_profile: Resource
@export_enum("none", "amount_template", "amount_velocity_template") var trial_water_mode := 2
@export var reference_height_m := 0.0
var nominal_stock_m3 := 0.0
var trial_queue: Array[Dictionary] = []
var trial_events: Array[Dictionary] = []
var trial_highwater := 0
var trial_busy := false
var trial_drag := false
var trial_last := Vector2.ZERO
var trial_kind := "dig"
var brush_spirv: RDShaderSPIRV
var trial_frame_rows: Array = []
var trial_gpu_rows: Array = []
var trial_gpu_frames := {}
var trial_shutdown := false
var trial_close_requested := false
var trial_tick_due := false
var trial_post_draw_pending := -1
var dig_amount_m3 := 0.015
var fill_amount_m3 := 0.015
var radius_m := 0.3
var exact_edit_spirvs: Array[RDShaderSPIRV] = []
var exact_water_spirvs: Array[RDShaderSPIRV] = []
var trial_admission_error := ""

func _ready() -> void:
	generation = int(get_tree().get_meta("approx_gpu_edit_epoch",0))+1
	get_tree().set_meta("approx_gpu_edit_epoch",generation)
	if trial_profile != null:
		reference_height_m = trial_profile.reference_height_m
		trial_water_mode = trial_profile.water_mode
		dig_amount_m3 = trial_profile.dig_amount_m3
		fill_amount_m3 = trial_profile.fill_amount_m3
		radius_m = trial_profile.radius_m
	if not is_finite(reference_height_m) or not is_finite(radius_m) or radius_m < 0.125 or radius_m > 1.0 or not is_finite(dig_amount_m3) or not is_finite(fill_amount_m3) or dig_amount_m3 <= 0.0 or fill_amount_m3 <= 0.0 or dig_amount_m3 > 0.06 or fill_amount_m3 > 0.06 or trial_water_mode not in [0,1,2]:
		_fail("invalid trial profile"); return
	get_tree().auto_accept_quit = false
	RenderingServer.frame_post_draw.connect(_trial_post_draw)
	if trial_profile != null and trial_profile.exact_backend:
		for group in [["sand_prepare","sand_reduce","sand_apply","sand_commit","sand_publish"],["water_prepare","water_displace_compensated","water_merge_receipt","water_commit","water_publish","water_velocity_apply","water_velocity_prefetch","water_packed_cached"]]:
			for name in group:
				var exact_file: RDShaderFile = load("res://shaders/simulation/edit_validation/"+name+".glsl")
				if name.begins_with("sand"): exact_edit_spirvs.append(exact_file.get_spirv())
				else: exact_water_spirvs.append(exact_file.get_spirv())
	var file: RDShaderFile = load("res://shaders/experiments/approx_gpu_edit/brush.glsl")
	if file == null: _fail("trial brush import missing"); return
	brush_spirv = file.get_spirv()
	if not brush_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():
		_fail("trial brush compile failed"); return
	prefetch_sand_on_hover = false
	super._ready()
	aim_player_camera(Vector3(-6,6,10),Vector3.ZERO)
	set_player_camera(true)
	$Interface/TrialPanel/WaterMode.select(trial_water_mode)
	$Interface/TrialPanel/DigAmount.value = dig_amount_m3
	$Interface/TrialPanel/FillAmount.value = fill_amount_m3

func _create_solver() -> SandcastleGpuShallowSolver:
	if trial_profile != null and trial_profile.exact_backend:
		var exact := preload("res://scripts/experiments/approx_gpu_edit/exact_trial_solver.gd").new()
		exact.edit_spirvs = exact_edit_spirvs
		exact.water_spirvs = exact_water_spirvs
		exact.local_dispatch = true
		exact.fast_full_wet = true
		exact.connected_runs = true
		exact.diagnostics = trial_profile.diagnostics
		exact.trial_exact_policy = trial_profile.exact_water_policy
		return exact
	var candidate := TrialSolver.new()
	candidate.brush_spirv = brush_spirv
	candidate.diagnostics = trial_profile != null and trial_profile.diagnostics
	return candidate

func _create_material_coupler() -> SandcastleGpuMaterialCoupler:
	return preload("res://scripts/simulation/edit_validation/staged_slope_coupler.gd").new()

func _make_grid_mesh(_subdivision: int = 1) -> ArrayMesh:
	return preload("res://assets/approx_gpu_edit/grid_mesh.res")

func _publish_textures() -> void:
	if solver.brush_sets.is_empty() and not solver.setup_brush():
		call_deferred("_fail", "trial brush setup failed"); return
	if not solver.publish_trial(): call_deferred("_fail", "trial publication failed"); return
	super._publish_textures()
	sand_texture.texture_rd_rid = solver.stable_fields.sand
	water_texture.texture_rd_rid = solver.stable_fields.water
	momentum_x_texture.texture_rd_rid = solver.stable_fields.momentum_x
	momentum_z_texture.texture_rd_rid = solver.stable_fields.momentum_z

func submit_brush(request: Dictionary) -> Dictionary:
	if closing or trial_shutdown: return _trial_rejection(request,"closing")
	if typeof(request.get("command_id")) != TYPE_INT or typeof(request.get("generation")) != TYPE_INT or typeof(request.get("requested_tick")) != TYPE_INT or typeof(request.get("nominal_amount_m3")) not in [TYPE_FLOAT,TYPE_INT] or typeof(request.get("radius_m")) not in [TYPE_FLOAT,TYPE_INT]:
		return _trial_rejection(request,"invalid_request")
	var error := ""
	var id: int = request.get("command_id", -1)
	var amount: float = request.get("nominal_amount_m3", NAN)
	var radius: float = request.get("radius_m", NAN)
	var a: Variant = request.get("start_xz_m")
	var b: Variant = request.get("end_xz_m")
	if closing or trial_shutdown: error = "closing"
	elif request.get("generation", -1) != generation: error = "stale_generation"
	elif id <= trial_highwater: error = "duplicate_id"
	elif not a is Vector2 or not b is Vector2: error = "invalid_request"
	elif not a.is_finite() or not b.is_finite() or not is_finite(amount) or not is_finite(radius) or amount <= 0.0 or amount > 0.06 or radius < 0.125 or radius > 1.0 or request.get("kind") not in ["dig", "fill"]: error = "invalid_request"
	elif request.get("seed",101) != 101 or request.get("strength",1.0) != 1.0 or request.get("requested_tick",-1) < 0 or request.get("shape","circle" if a == b else "swept_segment") not in ["circle","swept_segment"]: error = "invalid_request"
	elif not inside_domain(a) or not inside_domain(b): error = "out_of_domain"
	elif trial_queue.size() >= 64: error = "queue_full"
	elif request.get("shape","circle" if a == b else "swept_segment") == "circle" and a != b: error = "invalid_request"
	elif request.kind == "fill" and amount > nominal_stock_m3: error = "insufficient_nominal_stock"
	if not error.is_empty(): return _trial_rejection(request,error)
	var command := request.duplicate(true)
	command["admission_us"] = Time.get_ticks_usec()
	command["input_us"] = request.get("input_us",command.admission_us)
	command["shape"] = request.get("shape","circle" if a == b else "swept_segment")
	command["strength"] = 1.0
	command["seed"] = 101
	trial_queue.append(command)
	trial_highwater = id
	nominal_stock_m3 += amount if request.kind == "dig" else -amount
	trial_admission_error = ""
	trial_events.append({"phase":"queued","command_id":id,"generation":generation,"at_us":command.admission_us,"stock":nominal_stock_m3,"queue":trial_queue.size()})
	return {"accepted":true,"error":"","command_id":id,"generation":generation,"nominal_stock_m3":nominal_stock_m3}

func _trial_rejection(request: Dictionary,error: String) -> Dictionary:
	trial_admission_error = error
	return {"accepted":false,"error":error,"command_id":request.get("command_id",-1),"generation":request.get("generation",-1),"nominal_stock_m3":nominal_stock_m3}

func inside_domain(xz: Vector2) -> bool:
	return xz.x >= -16.0 and xz.y >= -16.0 and xz.x < 16.0 and xz.y < 16.0

func plane_hit(origin: Vector3, direction: Vector3):
	if not origin.is_finite() or not direction.is_finite() or absf(direction.y) < 1e-6: return null
	var distance := (reference_height_m-origin.y)/direction.y
	if distance < 0.0: return null
	var p := origin+direction*distance
	return p if inside_domain(Vector2(p.x,p.z)) else null

func _brush_hit():
	var cursor := get_viewport().get_mouse_position()
	return plane_hit(player_camera.project_ray_origin(cursor),player_camera.project_ray_normal(cursor))

func _update_brush_indicator() -> void:
	var hit = _brush_hit()
	if hit == null: brush_indicator.hide_indicator(); return
	brush_indicator.scale = Vector3(radius_m/0.38,1.0,radius_m/0.38)
	brush_indicator.aim(hit,reference_height_m,&"remove_sand" if trial_kind == "dig" else &"place_sand")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		trial_drag = false

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_ticks or closing or trial_shutdown: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit = _brush_hit()
		if hit != null:
			trial_last = Vector2(hit.x,hit.z)
			trial_drag = true
			_submit_trial(trial_last,trial_last,dig_amount_m3 if trial_kind == "dig" else fill_amount_m3)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_trial_pause()

func _submit_trial(a: Vector2,b: Vector2,amount: float) -> void:
	submit_brush({"generation":generation,"command_id":trial_highwater+1,"kind":trial_kind,"start_xz_m":a,"end_xz_m":b,"radius_m":radius_m,"nominal_amount_m3":amount,"input_us":Time.get_ticks_usec(),"requested_tick":completed_ticks,"seed":101})

func _process(delta: float) -> void:
	trial_frame_rows.append([Time.get_ticks_usec(),delta,completed_ticks,trial_queue.size(),int(trial_busy)])
	if not ready_for_ticks or closing: return
	_update_reflection_camera()
	if solver.diagnostics: RenderingServer.call_on_render_thread(_collect_trial_gpu)
	_update_brush_indicator()
	if trial_drag and (not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or get_viewport().gui_get_hovered_control() != null):
		trial_drag = false
	if trial_drag and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().gui_get_hovered_control() == null:
		var hit = _brush_hit()
		if hit == null: trial_drag = false
		if hit != null:
			var next := Vector2(hit.x,hit.z)
			var distance := next.distance_to(trial_last)
			if distance >= 0.075:
				var amount := dig_amount_m3 if trial_kind == "dig" else fill_amount_m3
				_submit_trial(trial_last,next,minf(0.06,amount*distance/0.75))
				trial_last = next
	_update_status()
	if playing: accumulator = minf(accumulator+delta,SIM_DELTA*4.0)
	if tick_pending or trial_busy: return
	if playing and trial_tick_due and accumulator >= SIM_DELTA:
		trial_tick_due = false
		accumulator -= SIM_DELTA
		_start_tick()
	elif not trial_queue.is_empty():
		var batch: Array[Dictionary] = []
		var batch_limit := 1 if solver.diagnostics and trial_profile.exact_backend else 8
		for index in mini(batch_limit,trial_queue.size()): batch.append(trial_queue.pop_front())
		trial_busy = true
		RenderingServer.call_on_render_thread(_render_trial_batch.bind(batch,generation))
	elif playing and accumulator >= SIM_DELTA:
		accumulator -= SIM_DELTA
		_start_tick()

func _render_trial_batch(batch: Array[Dictionary],token: int) -> void:
	if closing or token != generation: return
	var batch_mark := "trial_batch_%d_%d_%d" % [token,batch.front().command_id,batch.back().command_id]
	if solver.diagnostics: solver.rd.capture_timestamp(batch_mark+"_start")
	var rows: Array[Dictionary] = []
	for command in batch:
		if not solver.dispatch_brush(command,trial_water_mode): call_deferred("_fail","trial dispatch failed"); return
		rows.append({"phase":"dispatched","command_id":command.command_id,"at_us":Time.get_ticks_usec(),"generation":token,"revision":solver.state_revision,"input_us":command.get("input_us",0)})
	_publish_textures()
	if solver.diagnostics: solver.rd.capture_timestamp(batch_mark+"_end")
	rows.append({"phase":"publication_requested","at_us":Time.get_ticks_usec(),"generation":token,"revision":solver.state_revision,"last_command":batch.back().command_id})
	call_deferred("_trial_batch_published",rows,token)

func _trial_batch_published(rows: Array[Dictionary],token: int) -> void:
	if closing or token != generation: return
	trial_events.append_array(rows)
	trial_busy = false
	trial_tick_due = true
	trial_post_draw_pending = int(rows.back().last_command)

func _update_status() -> void:
	if status_label == null: return
	var admission_message: String = {"insufficient_nominal_stock":"估算库存不足","queue_full":"编辑队列已满"}.get(trial_admission_error,"")
	status_label.text = "近似 GPU 编辑实验 · 固定高度平面定位\n估算库存 %.4f m³ · tick %d · 队列 %d\n%s\n%s" % [nominal_stock_m3,completed_ticks,trial_queue.size(),"运行" if playing else "暂停（仍可编辑）",last_error if not last_error.is_empty() else admission_message]

func _select_dig() -> void: trial_kind = "dig"
func _select_fill() -> void: trial_kind = "fill"
func _toggle_trial_pause() -> void:
	if not trial_shutdown: playing = not playing
func _reset_trial() -> void:
	if trial_shutdown or closing: return
	trial_drag = false
	trial_shutdown = true
	playing = false
	while trial_busy or tick_pending or not trial_queue.is_empty(): await get_tree().process_frame
	if trial_close_requested: return
	get_tree().reload_current_scene()
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _close_trial()
func _close_trial() -> void:
	if trial_close_requested or closing: return
	trial_close_requested = true
	trial_shutdown = true
	trial_drag = false
	playing = false
	while trial_busy or tick_pending or not trial_queue.is_empty(): await get_tree().process_frame
	get_tree().quit()
func _trial_post_draw() -> void:
	if trial_post_draw_pending < 0: return
	trial_events.append({"phase":"post_draw_after_publication_request","last_command":trial_post_draw_pending,"at_us":Time.get_ticks_usec(),"generation":generation})
	trial_post_draw_pending = -1
func _collect_trial_gpu() -> void:
	var frame: int = solver.rd.get_captured_timestamps_frame()
	var rows: Array = []
	for index in solver.rd.get_captured_timestamps_count():
		var name: String = solver.rd.get_captured_timestamp_name(index)
		var key := str(frame)+":"+name
		if (name.begins_with("trial_") or name.begins_with("edit_water_") or name.begins_with("edit_sand_")) and not trial_gpu_frames.has(key):
			trial_gpu_frames[key] = true
			var gpu_ns: int = solver.rd.get_captured_timestamp_gpu_time(index)
			rows.append({"frame":frame,"name":name,"gpu_ns":gpu_ns,"gpu_ns_string":str(gpu_ns),"cpu_us":solver.rd.get_captured_timestamp_cpu_time(index)})
	call_deferred("_append_trial_gpu",rows)
func _append_trial_gpu(rows: Array) -> void: trial_gpu_rows.append_array(rows)
func _dig_amount_changed(value: float) -> void: dig_amount_m3 = value
func _fill_amount_changed(value: float) -> void: fill_amount_m3 = value
func _water_mode_changed(index: int) -> void: trial_water_mode = index
func request_checkpoint_save(_path: String) -> StringName: return &"trial_checkpoint_unsupported"
func _start_checkpoint_capture() -> void: pass
func _request_full_collision_render(_token: int) -> void: pass
