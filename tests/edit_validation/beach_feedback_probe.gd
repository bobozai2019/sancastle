extends "res://tests/edit_validation/beach_gpu_probe.gd"

var feedback_rows := []
var water_receipt_bytes := PackedByteArray()
var timestamp_frames := []
var seen_timestamp_frame := -1
var collect_timestamps := false

func _process(_delta: float) -> bool:
	if collect_timestamps and preview!=null and preview.solver!=null and not preview.closing:
		RenderingServer.call_on_render_thread(_collect_timestamps)
	return false

func _collect_timestamps() -> void:
	if preview==null or preview.solver==null or preview.solver.rd==null: return
	var rd: RenderingDevice=preview.solver.rd
	var frame := rd.get_captured_timestamps_frame()
	if frame==seen_timestamp_frame: return
	seen_timestamp_frame=frame
	var marks := []
	for i in rd.get_captured_timestamps_count():
		var name := rd.get_captured_timestamp_name(i)
		if name.begins_with("edit_"):
			marks.append({"name":name,"gpu_ns":rd.get_captured_timestamp_gpu_time(i),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
	if not marks.is_empty(): call_deferred("_record_timestamps",frame,marks)

func _record_timestamps(frame: int, marks: Array) -> void:
	timestamp_frames.append({"frame":frame,"marks":marks})

func _write() -> void:
	var file := FileAccess.open(output.path_join("beach_feedback_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"rows":feedback_rows,"timestamp_frames":timestamp_frames,
		"collision_candidate":{"reuse":preview.collision_proxy.reuse_chunk_shapes,"allocations":preview.collision_proxy.shape_allocations,"reuses":preview.collision_proxy.shape_reuses},"scope":"1080p full beach rendering; paused transaction phases, original coupled ticks between commands; collision feedback, not first-visible or continuous cost acceptance"}, "\t"))

func _run() -> void:
	root.size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview = load("res://tests/edit_validation/edit_beach_interaction_lab.tscn").instantiate()
	preview.playing = false
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty():
		_error(preview.last_error); _write(); finished=true; quit(1); return
	await _ticks(15)
	while preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty(): await process_frame
	await physics_frame; await physics_frame
	var initial: Dictionary = await _snapshot("initial")
	var sand: PackedFloat32Array = initial.sand.to_float32_array()
	var rock: PackedFloat32Array = initial.rock.to_float32_array()
	var water: PackedFloat32Array = initial.water.to_float32_array()
	var screen := Vector2.ZERO
	var chosen := -1
	for z in range(32,224,4):
		for x in range(32,224,4):
			var index: int = z*256+x
			if sand[index]<0.1 or water[index]<0.005: continue
			var point := Vector3((x+0.5)*0.125-16,rock[index]+sand[index],(z+0.5)*0.125-16)
			var projected: Vector2 = preview.get_viewport().get_camera_3d().unproject_position(point)
			if not preview.get_viewport().get_visible_rect().has_point(projected): continue
			var hit: Dictionary = preview.pick(projected)
			if hit.is_empty() or not preview._pick_current(hit): continue
			if Vector2(hit.position.x,hit.position.z).distance_to(Vector2(point.x,point.z))>0.001: continue
			screen=projected; chosen=index; break
		if chosen>=0: break
	if chosen<0:
		_error("no visible current wet sand point"); _write(); await preview.shutdown(); finished=true; quit(1); return
	# Explicit fixture stock, before any edit: permits a cold first placement.
	preview.domain.tool_inventory_m3=0.2
	Input.use_accumulated_input=false
	collect_timestamps="--profile-edit-passes" in OS.get_cmdline_user_args()
	for policy in [1,0,2,3]:
		preview.water_policy=policy
		preview.signed_speed_m_s=0.25 if policy>=2 else 0.0
		var hit: Dictionary = preview.pick(screen)
		if hit.is_empty() or not preview._pick_current(hit): _error("stale test pick"); break
		var before: int = preview.input_results.size()
		var event := InputEventMouseButton.new()
		event.position=preview.get_viewport().get_final_transform()*screen
		event.button_index=MOUSE_BUTTON_RIGHT
		event.pressed=true
		Input.parse_input_event(event)
		var deadline := Time.get_ticks_msec()+10000
		while preview.input_running and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
		event.pressed=false; Input.parse_input_event(event)
		if preview.input_results.size()!=before+1: _error("input transaction missing: "+preview.last_error); break
		var terminal: Dictionary = preview.input_results[-1]
		var input: Dictionary = preview.input_events[-1]
		var receipt: Dictionary = terminal.result
		var latest := 0
		for chunk in preview._gpu_chunks(receipt): latest=maxi(latest,int(preview.collision_proxy.applied_usec.get(chunk,0)))
		var elapsed_ms := float(latest-int(input.input_us))/1000.0
		var row := {"policy":policy,"chosen_cell":chosen,"input":input,"terminal":terminal,
			"collision_feedback_ms":elapsed_ms,"settlement_ms":float(terminal.settle_us-int(input.input_us))/1000.0,
			"publication_ms":float(terminal.publish_us-int(input.input_us))/1000.0,"collision_us":latest,"collision_revisions_current":_receipt_collision_current(receipt),
			"pass":receipt.get("status")==1 and latest>int(input.input_us) and elapsed_ms<=100.0 and _receipt_collision_current(receipt)}
		if policy>0:
			water_receipt_bytes.clear()
			RenderingServer.call_on_render_thread(_read_water_receipt)
			while water_receipt_bytes.is_empty(): await process_frame
			var raw := FileAccess.open(output.path_join("policy_%d_water_receipt.bin" % policy),FileAccess.WRITE)
			raw.store_buffer(water_receipt_bytes)
			row["fast_path_used"]=water_receipt_bytes.decode_u32(108)
			row["water_components"]=water_receipt_bytes.decode_u32(8)
		feedback_rows.append(row)
		_check("policy_%d_collision_feedback" % policy,row.pass,row)
		if policy==3:
			var edited_state: Dictionary = await _snapshot("last_edit")
			_check("last_edit_publication_and_collision",await _published_exact(edited_state) and _chunks_exact(edited_state))
		await _ticks(2)
		while preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty(): await process_frame
		await physics_frame; await physics_frame
	var final_state: Dictionary = await _snapshot("final")
	_check("full_load_and_final_state",preview.completed_ticks==23 and preview.wave_requests.size()==80 and preview.enable_erosion and await _published_exact(final_state))
	for item in checks: failed=failed or not item.pass
	failed=failed or feedback_rows.size()!=4 or not preview.last_error.is_empty()
	collect_timestamps=false
	await preview.shutdown(); _write(); preview.queue_free()
	finished=true; print("BEACH_FEEDBACK_COMPLETE pass=%s" % str(not failed)); quit(1 if failed else 0)

func _receipt_collision_current(receipt: Dictionary) -> bool:
	for chunk in preview._gpu_chunks(receipt):
		if int(preview.collision_proxy.applied_revisions.get(chunk,-1))<int(receipt.output_revision): return false
	return true

func _read_water_receipt() -> void:
	preview.solver.rd.buffer_get_data_async(preview.solver.water_receipt,_water_receipt_callback)

func _water_receipt_callback(bytes: PackedByteArray) -> void:
	call_deferred("_record_water_receipt",bytes)

func _record_water_receipt(bytes: PackedByteArray) -> void:
	water_receipt_bytes=bytes
