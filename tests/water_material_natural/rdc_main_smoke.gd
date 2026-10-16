extends SceneTree

var preview
var checks := []
var output := ""
var readbacks := {}
const FIELDS = ["sand", "water", "momentum_x", "momentum_z", "sediment", "wetness", "compaction", "rock", "obstacle", "flux"]
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("_run")
func _check(name: String, ok: bool, detail: Variant=null) -> void:
	checks.append({"name":name,"pass":ok,"detail":detail})
	print("MAIN_CHECK ",name," ",ok)
func _read() -> void:
	for field in FIELDS: preview.solver.request_data(field,_record.bind(field))
func _record(bytes: PackedByteArray, field: String) -> void:
	call_deferred("_receive",bytes,field)
func _receive(bytes: PackedByteArray, field: String) -> void: readbacks[field]=bytes
func _snapshot() -> Dictionary:
	readbacks.clear();RenderingServer.call_on_render_thread(_read)
	while readbacks.size()<FIELDS.size(): await process_frame
	return readbacks.duplicate(true)
func _ticks(count: int) -> void:
	for i in count:
		var before: int=preview.completed_ticks
		preview._start_tick()
		var deadline:int=Time.get_ticks_msec()+30000
		while preview.completed_ticks==before and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
		if preview.completed_ticks==before and preview.last_error.is_empty():
			_check("tick_wait_timeout",false,{"tick":before,"generation":preview.generation})
			preview._fail("test tick did not complete within 30 seconds")
			return
func _run() -> void:
	var scene: PackedScene=load("res://scenes/main.tscn")
	preview=scene.instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+180000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("main_ready",preview.ready_for_ticks and preview.last_error.is_empty(),preview.last_error)
	if not preview.ready_for_ticks: _finish();quit(1);return
	_check("fixed_v160_e3",preview.water_policy==3 and preview.signed_speed_m_s==0.25 and preview.solver.fast_full_wet and preview.solver.connected_runs)
	_check("full_beach_profile",preview.wave_requests.size()==80 and preview.enable_erosion and preview.requested_render_profile_sha256==FileAccess.get_sha256("res://assets/water_material_natural_candidate/rdc_style_base.json"))
	_check("natural_material_binding",preview._validate_compiled_inputs() and preview.effective_compilation.size()>0,preview.effective_compilation)
	_check("rdc_material_active",preview.style_profile.style_schema_version==4 and preview.water_material.get_shader_parameter("rdc_optics_enabled")==true and preview.water_material.get_shader_parameter("rdc_normal_enabled")==true and preview.terrain_material.get_shader_parameter("rdc_caustics_enabled")==true and preview.water_material.get_shader_parameter("natural_glint_exponent")==1500.0,preview.effective_style)
	await _ticks(2)
	for kind in [&"remove_sand",&"place_sand"]:
		var command: Dictionary={"domain_id":preview.domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":preview.command_queue.last_command_id+1,"kind":kind,"shape":&"circle","transform":{"position_m":Vector3(-2,0,0),"end_position_m":Vector3(-2,0,0)},"radius_m":0.3,"strength":1.0,"amount_m3":0.005,"seed":101}
		var error: StringName=preview.input_scheduler.submit(command)
		await preview.input_scheduler.drain_due()
		_check(String(kind),error.is_empty() and not preview.input_scheduler.terminal.is_empty() and preview.input_scheduler.terminal[-1].result.get("status")==1,preview.input_scheduler.terminal[-1] if not preview.input_scheduler.terminal.is_empty() else String(error))
	var before:=await _snapshot()
	var save_error: StringName=await preview.save_gpu_checkpoint(output.path_join("main_checkpoint.bin"))
	_check("native_save",save_error.is_empty(),String(save_error))
	await _ticks(2)
	var restore_error: StringName=await preview.restore_gpu_checkpoint(output.path_join("main_checkpoint.bin"))
	_check("native_restore",restore_error.is_empty(),String(restore_error))
	var after:=await _snapshot();var equal:=true
	for field in FIELDS: equal=equal and before[field]==after[field]
	_check("restored_10_fields_exact",equal)
	await _ticks(2)
	_check("continue_and_collision",preview.last_error.is_empty() and preview.collision_proxy.applied_revisions.size()==64,preview.last_error)
	await preview.shutdown()
	_check("clean_shutdown",preview.gpu_release_done)
	_finish();quit()
func _finish() -> void:
	var passed:=true
	for row in checks: passed=passed and row.pass
	var file:=FileAccess.open(output.path_join("main_smoke.json"),FileAccess.WRITE)
	var executable:String=OS.get_executable_path()
	file.store_string(JSON.stringify({"pass":passed,"checks":checks,"engine_identity":{"executable":executable,"sha256":FileAccess.get_sha256(executable),"version":Engine.get_version_info()}},"\t"))
	print("MAIN_SMOKE_COMPLETE ",passed)
