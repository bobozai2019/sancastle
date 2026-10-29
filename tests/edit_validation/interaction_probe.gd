extends "res://tests/edit_validation/water_transaction_probe.gd"

var timestamp_frames := []
var seen_frame := -1
var collect_timestamps := false

func _process(_delta: float) -> bool:
	if collect_timestamps and lab != null and lab.solver != null and not lab.closed:
		RenderingServer.call_on_render_thread(_collect)
	return false

func _collect() -> void:
	if lab == null or lab.solver == null or lab.solver.rd == null: return
	var rd: RenderingDevice = lab.solver.rd
	var frame := rd.get_captured_timestamps_frame()
	if frame == seen_frame: return
	seen_frame = frame
	var marks := []
	for i in rd.get_captured_timestamps_count():
		var name := rd.get_captured_timestamp_name(i)
		if name.begins_with("edit_"):
			marks.append({"name":name,"gpu_ns":rd.get_captured_timestamp_gpu_time(i),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
	if not marks.is_empty(): call_deferred("_record_marks",frame,marks)

func _record_marks(frame: int, marks: Array) -> void: timestamp_frames.append({"frame":frame,"marks":marks})

func _write(ok: bool, error := "") -> void:
	var f := FileAccess.open(output.path_join("interaction_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"timestamp_frames":timestamp_frames,"input":"Input.parse_input_event engine injection; not OS mouse","scope":"256 actual physics ray, circle/swept, GPU dirty collision"},"\t"))

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_interaction_lab.tscn").instantiate()
	lab.local_dispatch = "--local-dispatch" in OS.get_cmdline_user_args()
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	collect_timestamps = "--profile-edit-passes" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--interaction-policy="): lab.water_policy = int(arg.trim_prefix("--interaction-policy="))
	await physics_frame;await physics_frame
	for k in 4:
		var world := Vector3(0.0625 + k * 0.25,0.4,0.0625)
		var screen: Vector2 = lab.get_viewport().get_final_transform()*lab.get_node("Camera").unproject_position(world)
		var event: InputEvent
		if k == 1 or k == 2:
			var motion := InputEventMouseMotion.new();motion.position=screen;motion.button_mask=MOUSE_BUTTON_MASK_RIGHT;event=motion
		else:
			var click := InputEventMouseButton.new();click.position=screen;click.button_index=MOUSE_BUTTON_RIGHT if k==0 else MOUSE_BUTTON_LEFT;click.pressed=true;event=click
		var count: int = lab.input_results.size()
		Input.parse_input_event(event)
		var timeout := Time.get_ticks_msec()+3000
		while lab.input_results.size()==count and lab.last_error.is_empty() and Time.get_ticks_msec()<timeout: await process_frame
		if lab.input_results.size()==count: _write(false,"event completion timeout: "+lab.last_error);finished=true;quit(1);return
		var state: Dictionary = await _snapshot("input%d" % k)
		var sand: PackedFloat32Array = state.sand.to_float32_array()
		var rock: PackedFloat32Array = state.rock.to_float32_array()
		var maximum := 0.0
		for chunk in lab.collision_proxy.shapes:
			var values: PackedFloat32Array = lab.collision_proxy.shapes[chunk].shape.map_data
			for z in 33:
				for x in 33:
					var index: int = mini((chunk / 8)*32+z,255)*256+mini((chunk % 8)*32+x,255)
					maximum=maxf(maximum,absf(values[z*33+x]-sand[index]-rock[index]))
		var result: Dictionary = lab.input_results[-1]
		var ray_error := 0.0
		var ray_misses := 0
		for z in range(127,131):
			for x in range(127,131):
				var wx := (x + 0.5) * 0.125 - 16.0
				var wz := (z + 0.5) * 0.125 - 16.0
				var query := PhysicsRayQueryParameters3D.create(Vector3(wx,10,wz),Vector3(wx,-10,wz))
				var hit: Dictionary = lab.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty(): ray_misses += 1
				else: ray_error=maxf(ray_error,absf(hit.position.y-sand[z*256+x]-rock[z*256+x]))
		var latest := 0
		for chunk in result.collision_chunks: latest=maxi(latest,int(lab.collision_proxy.applied_usec[chunk]))
		var input_us: int = lab.input_events[-1].input_us
		var latency := (latest-input_us)/1000.0
		var ok: bool = maximum<=1e-6 and ray_error<=1e-5 and ray_misses==0 and result.receipt.get("status")==1 and latency<=100.0
		rows.append({"pass":ok,"input_index":k,"shape_error_m":maximum,"physical_ray_error_m":ray_error,"ray_misses":ray_misses,"collision_feedback_ms":latency,"result":result,"event":lab.input_events[-1]})
		_write(false,"running")
	var release := InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;Input.parse_input_event(release)
	var ok := rows.size()==4
	for row in rows: ok=ok and row.pass
	for i in 8: await process_frame
	collect_timestamps=false
	_write(ok);await lab.shutdown();lab.queue_free();finished=true;print("INTERACTION_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)
