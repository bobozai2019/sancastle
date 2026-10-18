extends "res://tools/unified_edit_pipeline/observed_workload_probe.gd"

# G8 reference-only rendering overlay. The frozen G0 simulation, scheduler,
# authority shaders and original observer remain untouched. Add the same static
# water sides that were introduced in the product after the G0 capture.
var render_overlay: Dictionary={}

func _target() -> bool:
	check("reference_has_no_preexisting_water_sides",not preview.has_node("WaterSides"))
	var sides=load("res://scenes/components/water_boundary_sides.tscn").instantiate()
	sides.name="WaterSides";preview.add_child(sides)
	check("reference_same_water_sides_bound",sides.bind_surface(preview.water_material,preview.terrain_material).is_empty())
	for path in ["res://scenes/components/water_boundary_sides.tscn","res://scripts/visual/water_boundary_sides.gd","res://assets/water_sides/main_boundary.res","res://assets/water_sides/water_sides.gdshader","res://assets/water_sides/geometry_manifest.json"]:render_overlay[path]=FileAccess.get_sha256(path)
	return super._target()

func _fixture(index: int) -> Dictionary:
	var value:=super._fixture(index)
	hardware.reference_render_overlay=render_overlay.duplicate(true)
	hardware.ordinary_request_policy=preview.water_policy
	hardware.ordinary_request_speed_m_s=preview.signed_speed_m_s
	return value

func _observe_workload() -> void:
	super._observe_workload()
	if finalizing or trace.is_empty():return
	trace.back().render_objects=Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	trace.back().render_primitives=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	trace.back().render_draw_calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)


# Same frozen workload loop; observer-only startup allowance.
func _run() -> void:
	var boot_us:=Time.get_ticks_usec()
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+180000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	startup={"load_to_ready_us":Time.get_ticks_usec()-boot_us,"ready_at_us":Time.get_ticks_usec()}
	check("ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if failed:await _finish();return
	check("fixed_full_footprint_target",_target())
	check("known_pattern",path_mode in ["straight","corner","overlap"])
	if failed:await _finish();return
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"viewport":root.get_visible_rect().size,"vsync":DisplayServer.window_get_vsync_mode(),"profile":preview._runtime_configuration_signature(),"effective_profile":preview._effective_profile_request(),"loaded_gdscript_sha256":loaded_code()}
	RenderingServer.call_on_render_thread(_configure_render)
	while not configure_done:await process_frame
	hardware.scope="24 inputs, one offered per process frame; frame-bounded completion/collision observation; no framebuffer visibility claim"
	preview.async_controller.collision.observe=true
	for i in warmup_frames:await process_frame
	check("warmup_drained",await super.idle())
	startup.warmup_frames=warmup_frames
	process_frame.connect(_observe_workload)
	var start_tick: int=preview.completed_ticks
	var start_time: float=preview.async_controller.actual_time
	var start_us:=Time.get_ticks_usec()
	preview.playing=realtime
	for i in input_count:
		var value:=_fixture(i)
		var before:=Time.get_ticks_usec()
		var error: StringName=preview.input_scheduler.submit(value)
		check("admission_%d"%i,error.is_empty())
		if not error.is_empty():break
		outstanding[value.command_id]=before
		submitted.append({"command":value.duplicate(true),"admitted_at_us":before,"admission_return_us":Time.get_ticks_usec(),"index":i})
		await process_frame
	input_open_end={"start_at_us":start_us,"end_at_us":Time.get_ticks_usec(),"start_tick":start_tick,"end_tick":preview.completed_ticks,"start_time_s":start_time,"end_time_s":preview.async_controller.actual_time}
	preview.playing=false
	if case_id in ["wall","shovel"]:check("stroke_end",(await preview.end_shape_stroke()).is_empty())
	tail_start_us=Time.get_ticks_usec()
	check("drained",await super.idle())
	var drained_us:=Time.get_ticks_usec()
	_observe_workload()
	check("all_input_terminals",submitted.size()==input_count and submitted.all(func(row):return seen_terminal.has(row.command.command_id)))
	if realtime:check("water_advances_while_input_open",input_open_end.end_tick>start_tick and input_open_end.end_time_s>start_time)
	var hashes:={}
	for field in ["sand","water","sediment","momentum_x","momentum_z","wetness","compaction","mold_support","clock"]:hashes[field]=digest(await read(field))
	witnesses={"field_sha256":hashes,"drained_at_us":drained_us,"tail_us":drained_us-tail_start_us,"final_tick":preview.completed_ticks,"final_time_s":preview.async_controller.actual_time,"final_state_seq":preview.async_controller.state_seq,"accepted":preview.async_controller.accepted_commands,"rejected":preview.async_controller.rejected_commands,"collision_applied_seq":preview.async_controller.collision.applied_state_seq.duplicate(),"collision_applied_tick":preview.async_controller.collision.applied_sim_tick.duplicate()}
	await _finish()

