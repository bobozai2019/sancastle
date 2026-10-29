extends "res://tests/water_material_natural/rdc_main_smoke.gd"

const BrushProtocol = preload("res://scripts/simulation/brushes/brush_protocol.gd")

func record_state(tag: String, state: Dictionary) -> Dictionary:
	var index := {}
	for field in FIELDS:
		var path := output.path_join(tag + "_" + field + ".bin")
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(state[field]); file.close()
		index[field] = {"bytes":state[field].size(),"sha256":FileAccess.get_sha256(path),"path":path}
	return index

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var backend_script: Script = load("res://scripts/simulation/brushes/brush_gpu.gd")
	if backend_script == null or not backend_script.can_instantiate():
		_check("backend_script_compile",false); _finish(); quit(1); return
	var scene: PackedScene = load("res://tests/shape_brushes/brush_lab.tscn")
	if scene == null:
		_check("lab_scene_load",false); _finish(); quit(1); return
	preview = scene.instantiate()
	if preview.get_script() == null or not "ready_for_ticks" in preview:
		_check("lab_script_inheritance",false)
		preview.free(); _finish(); quit(1); return
	root.add_child(preview)
	var deadline := Time.get_ticks_msec() + 90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	_check("lab_ready", preview.ready_for_ticks and preview.last_error.is_empty(), preview.last_error)
	if not preview.ready_for_ticks: _finish(); quit(1); return
	var before := await _snapshot()
	var raw_before := record_state("before", before)
	_check("dry_fixture_gpu_upload", before.sand == preview.shadow_domain.sand.to_byte_array() and before.rock == preview.shadow_domain.rock.to_byte_array() and before.water == preview.shadow_domain.water.to_byte_array())
	var command := BrushProtocol.make_command(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},Vector2.ZERO,Vector2(1,0),preview.domain.domain_id,preview.generation,1,1,0,0,1)
	_check("missing_baseline_cannot_admit",preview.shape_backend_ready and preview.input_scheduler.submit(command)==&"invalid_baseline" and preview.command_queue.pending.is_empty() and preview.command_queue.last_command_id==0)
	var after := await _snapshot()
	var raw_rejected := record_state("rejected", after)
	var equal := true
	for field in FIELDS: equal = equal and before[field] == after[field]
	_check("rejection_keeps_all_fields",equal)
	var legacy := {"domain_id":preview.domain.domain_id,"generation":preview.generation,"sim_tick":0,"command_id":1,"kind":&"place_sand","shape":&"circle","transform":{"position_m":Vector3.ZERO},"radius_m":0.3,"strength":1.0,"amount_m3":0.1,"seed":101}
	var error: StringName = preview.input_scheduler.submit(legacy)
	await preview.input_scheduler.drain_due()
	_check("legacy_route_uses_real_gpu",error.is_empty() and preview.input_scheduler.terminal[-1].result.get("status")==1,preview.input_scheduler.terminal[-1])
	_check("legacy_source_once",absf(preview.shadow_domain.sand_source_m3-0.1)<1e-6 and preview.shadow_domain.tool_inventory_m3==0.0)
	var raw_legacy := record_state("legacy", await _snapshot())
	root.get_texture().get_image().save_png(output.path_join("lab.png"))
	var evidence := FileAccess.open(output.path_join("effective_state.json"),FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"before":raw_before,"rejected":raw_rejected,"legacy":raw_legacy,"source_signature":preview.source_signature,"adapter":RenderingServer.get_video_adapter_name(),"vsync":DisplayServer.window_get_vsync_mode(),"viewport":root.size,"tick":preview.completed_ticks,"generation":preview.generation,"legacy_receipt":preview.input_scheduler.terminal[-1],"new_backend_ready":preview.shape_backend_ready,"scope":"lab/resource route and legacy GPU edit; new candidate acceptance is in gpu_framework_probe"},"\t")); evidence.close()
	await preview.shutdown()
	_check("lab_release",preview.gpu_release_done)
	_finish()
	var passed := true
	for row in checks: passed = passed and row.pass
	quit(0 if passed else 1)
