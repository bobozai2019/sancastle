extends "res://tests/shape_brushes/gpu_framework_probe.gd"

var paired_states := {}
var paired_metadata := {}
var pair_fields := FIELDS.size()+SPARES.size()+7
var failed_shape_candidate
var branch_records := []

func retain_candidate() -> void:
	failed_shape_candidate=preview._restore_shape_candidate

func read_all() -> void:
	for field in FIELDS: preview.solver.request_data(field,_record.bind(field))
	for field in SPARES: preview.solver.rd.texture_get_data_async(preview.solver.textures[field][1-preview.solver.current_index],0,_record.bind("spare_"+field))
	for item in [["published_sand",preview.solver.published_sand],["published_water",preview.solver.published_water],["foam0",preview.foam_field.textures[0]],["foam1",preview.foam_field.textures[1]],["bed0",preview.foam_field.bed_textures[0]],["bed1",preview.foam_field.bed_textures[1]],["local_front",preview.local_front_field.texture]]:
		preview.solver.rd.texture_get_data_async(item[1],0,_record.bind(item[0]))

func snapshot(tag: String) -> Dictionary:
	readbacks.clear(); RenderingServer.call_on_render_thread(read_all)
	var deadline := Time.get_ticks_msec()+30000
	while readbacks.size()<pair_fields and Time.get_ticks_msec()<deadline: await process_frame
	_check(tag+"_native_readbacks",readbacks.size()==pair_fields)
	var state := readbacks.duplicate(true)
	var index := {}
	for name in state:
		var path := output.path_join(tag+"_"+name+".bin")
		var file := FileAccess.open(path,FileAccess.WRITE); file.store_buffer(state[name]); file.close()
		index[name]={"path":path,"bytes":state[name].size(),"sha256":FileAccess.get_sha256(path)}
	raw_index.append({"tag":tag,"fields":index,"generation":preview.generation,"revision":preview.solver.state_revision,"tick":preview.completed_ticks})
	return state

func metadata() -> Dictionary:
	return {"revision":preview.solver.state_revision,"tick":preview.completed_ticks,"source":preview.domain.sand_source_m3,"sink":preview.domain.sand_sink_m3,"inventory":preview.domain.tool_inventory_m3,"prefix":preview.gpu_prefix.duplicate(true),"highwater":preview.command_queue.last_command_id,"visual_time":preview.visual_time_s}

func legacy_command(id: int, kind: StringName, future: bool=false) -> Dictionary:
	return {"domain_id":preview.domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks+(100 if future else 0),"command_id":id,"kind":kind,"shape":&"swept_segment","transform":{"position_m":Vector3.ZERO,"end_position_m":Vector3(0.25,0,0)},"radius_m":0.3,"strength":1.0,"amount_m3":0.005,"seed":101}

func capture_pair(fixture: String, branch: String, stage: String) -> void:
	var tag := fixture+"_"+branch+"_"+stage
	var value := await snapshot(tag)
	var info := metadata()
	var key := fixture+"_"+stage
	if branch=="legacy": paired_states[key]=value; paired_metadata[key]=info
	else:
		_check(key+"_authoritative_spare_history_exact",exact(paired_states[key],value))
		_check(key+"_metadata_exact",paired_metadata[key]==info,{"reference":paired_metadata[key],"brush":info})

func branch_run(fixture: String, branch: String) -> void:
	preview=load("res://tests/shape_brushes/"+("legacy_lab" if branch=="legacy" else "brush_lab")+".tscn").instantiate()
	preview.brush_fixture=fixture; preview.playing=false; preview.visual_time_s=0.0
	preview.staging_wave_workload=&"none"
	root.add_child(preview)
	var deadline := Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check(fixture+"_"+branch+"_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks: return
	branch_records.append({"fixture":fixture,"branch":branch,"source_signature":preview.source_signature,"render_profile_sha256":preview.requested_render_profile_sha256,"effective_compilation":preview.effective_compilation,"camera_position":preview.player_camera_position,"camera_target":preview.player_camera_target,"wave_workload":preview.staging_wave_workload,"playing":preview.playing,"seed":101,"adapter":RenderingServer.get_video_adapter_name(),"vsync":DisplayServer.window_get_vsync_mode(),"viewport":root.size})
	await capture_pair(fixture,branch,"initial")
	await _ticks(2)
	await capture_pair(fixture,branch,"unbrushed_ticks")
	# Exercise original 64-command admission/backpressure without executing a
	# future command or introducing the new stroke sampler into old amount rules.
	var queue_ok := true
	for id in range(1,65): queue_ok=preview.input_scheduler.submit(legacy_command(id,&"place_sand",true)).is_empty() and queue_ok
	_check(branch+"_legacy_queue64",queue_ok and preview.command_queue.pending.size()==64 and preview.input_scheduler.submit(legacy_command(65,&"place_sand",true))==&"backend_unavailable" and preview.command_queue.last_command_id==64)
	preview.input_scheduler.cancel_pending("pair_future_cancel")
	_check(branch+"_legacy_cancel_clears_reservations",preview.command_queue.pending.is_empty() and preview.input_scheduler.reserved_total()==0.0 and preview.input_scheduler.policies.is_empty())
	for kind in [&"remove_sand",&"place_sand"]:
		var error: StringName=preview.input_scheduler.submit(legacy_command(preview.command_queue.last_command_id+1,kind))
		await settle()
		_check(branch+"_legacy_"+String(kind),error.is_empty() and preview.input_scheduler.terminal[-1].result.get("status")==1,preview.input_scheduler.terminal[-1].result)
	await capture_pair(fixture,branch,"legacy_edits")
	var anchor := await snapshot(fixture+"_"+branch+"_anchor")
	var path := output.path_join(fixture+"_"+branch+".scp")
	var saved: StringName=await preview.save_gpu_checkpoint(path)
	_check(branch+"_legacy_native_save",saved.is_empty(),String(saved))
	if not saved.is_empty(): await preview.shutdown(); preview.queue_free(); return
	var generation_before: int=preview.generation
	var old_helper=preview.shape_gpu if branch=="brush" else null
	await _ticks(2)
	if branch=="brush":
		var pre_failure := await snapshot(fixture+"_brush_before_failed_restore")
		preview.inject_beach_restore_failure=true; preview.observe_beach_restore=true
		preview.beach_restore_submitted.connect(retain_candidate,CONNECT_ONE_SHOT)
		var failed: StringName=await preview.restore_gpu_checkpoint(path)
		preview.observe_beach_restore=false
		var after_failure := await snapshot(fixture+"_brush_after_failed_restore")
		_check("failed_restore_preserves_active_brush_bundle",failed==&"candidate_injected_failure" and preview.shape_gpu==old_helper and preview.generation==generation_before and exact(pre_failure,after_failure))
		_check("failed_restore_releases_candidate_brush_pool",failed_shape_candidate!=null and failed_shape_candidate.rd==null and failed_shape_candidate.owned.is_empty() and preview._restore_shape_candidate==null)
	var restored: StringName=await preview.restore_gpu_checkpoint(path)
	_check(branch+"_legacy_native_restore",restored.is_empty() and preview.generation==generation_before+1,String(restored))
	var restore_state := await snapshot(fixture+"_"+branch+"_restored")
	_check(branch+"_legacy_restore_25_exact",exact(anchor,restore_state))
	if branch=="brush":
		_check("restore_swaps_and_releases_brush_helper",preview.shape_gpu!=old_helper and old_helper.rd==null and old_helper.owned.is_empty() and preview.shape_gpu.solver==preview.solver and preview.shape_gpu.generation==preview.generation and preview.shape_gpu.owned.size()==37 and preview.shape_gpu.images.castle_template.is_valid() and preview.shape_gpu.bytes_allocated==6570496+67600+128)
	var stale := legacy_command(preview.command_queue.last_command_id+1,&"place_sand"); stale.generation=generation_before
	var denied: StringName=preview.input_scheduler.submit(stale)
	_check(branch+"_old_generation_rejected",not denied.is_empty() and preview.command_queue.pending.is_empty())
	await _ticks(1)
	await capture_pair(fixture,branch,"restored_continuation")
	if branch=="brush":
		var begin_error: StringName=await preview.begin_shape_stroke(200)
		_check("restored_generation_baseline_works",begin_error.is_empty() and preview.shape_gpu.generation==preview.generation)
		var loaded: Dictionary=preview.Store.load(path)
		var conflict: StringName=await preview.restore_gpu_checkpoint_data(loaded.checkpoint)
		_check("active_stroke_restore_refused",conflict==&"brush_stroke_active")
		_check("restored_generation_stroke_end",(await preview.end_shape_stroke()).is_empty())
	await preview.shutdown()
	_check(branch+"_shutdown",preview.gpu_release_done and preview.last_error.is_empty(),preview.last_error)
	preview.queue_free(); preview=null
	for i in 4: await process_frame

func _run() -> void:
	root.size=Vector2i(1280,720)
	for fixture in ["dry_slope","shallow_water"]:
		for branch in ["legacy","brush"]: await branch_run(fixture,branch)
	var file := FileAccess.open(output.path_join("legacy_pair_evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"raw_index":raw_index,"branches":branch_records,"fixtures":["dry_slope","shallow_water"],"reference_entry":"beach_playable_entry","candidate_entry":"shape_brush_entry","scope":"zero new edits; same seed/profile/camera/ticks; 25 native fields, old queue and restore continuation"},"\t")); file.close()
	_finish(); var ok := true
	for row in checks: ok=ok and row.pass
	quit(0 if ok else 1)
