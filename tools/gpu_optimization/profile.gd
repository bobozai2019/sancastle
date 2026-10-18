extends "res://tests/integration/async_pipeline_main_probe.gd"

const PerfPanel=preload("res://scripts/beach/performance_panel.gd")
var sampling_enabled:=false
var case_id:="water"
var samples:=[]
var frame_samples:=[]
var seen_capture:=-1
var gpu_samples:=[]
var collected:=false
var collect_pending:=false
var previous_frame_us:=0
var occupancy:=[]
var velocity_source:=""
var configure_done:=false
var source_overrides:={}
var compute_overrides:={}
var wet_target:=false
var input_target:=Vector3(-2,0,0)

func _observe_frame() -> void:
	var now:=Time.get_ticks_usec()
	if previous_frame_us>0:frame_samples.append(now-previous_frame_us)
	previous_frame_us=now
	occupancy.append({"frame":Engine.get_process_frames(),"in_flight":preview.async_controller.slots.active_count(),"pending":preview.command_queue.pending.size(),"at_us":now})
	if sampling_enabled and not collect_pending:
		collect_pending=true
		RenderingServer.call_on_render_thread(_collect_render)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		if argument.begins_with("--case="):case_id=argument.trim_prefix("--case=")
		if argument=="--sampling":sampling_enabled=true
		if argument.begins_with("--velocity-source="):
			velocity_source=argument.trim_prefix("--velocity-source=")
			compute_overrides[6]=velocity_source
		if argument.begins_with("--packed-source="):compute_overrides[7]=argument.trim_prefix("--packed-source=")
		if argument.begins_with("--displace-source="):compute_overrides[1]=argument.trim_prefix("--displace-source=")
		if argument=="--wet":wet_target=true
		if argument.begins_with("--water-source="):source_overrides["res://scripts/simulation/edit_validation/frame_pipeline/async_water.gd"]=argument.trim_prefix("--water-source=")
		if argument.begins_with("--coupled-source="):source_overrides["res://scripts/simulation/edit_validation/frame_pipeline/async_coupled.gd"]=argument.trim_prefix("--coupled-source=")
	for path in source_overrides:
		var script: GDScript=load(path)
		script.source_code=FileAccess.get_file_as_string(source_overrides[path])
		if script.reload()!=OK:failed=true
	call_deferred("_run")

func _configure_render() -> void:
	for index in compute_overrides:
		var source:=RDShaderSource.new()
		source.source_compute=FileAccess.get_file_as_string(compute_overrides[index]).trim_prefix("#[compute]")
		var spirv: RDShaderSPIRV=preview.solver.rd.shader_compile_spirv_from_source(source)
		var error: String=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():call_deferred("_configured",error);return
		for resource in preview.solver.water_sets[index]+[preview.solver.water_pipelines[index],preview.solver.water_shaders[index]]:preview.solver.rd.free_rid(resource)
		var shader: RID=preview.solver.rd.shader_create_from_spirv(spirv)
		preview.solver.water_shaders[index]=shader
		preview.solver.water_pipelines[index]=preview.solver.rd.compute_pipeline_create(shader)
		preview.solver.water_sets[index]=[preview.solver._water_set(index,{0:preview.solver.command_buffer if index==6 else preview.solver.water_input,1:preview.solver.water_candidate,2:preview.solver.water_scratch,3:preview.solver.water_receipt},{})]
	preview.solver.profile_passes=sampling_enabled
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),sampling_enabled)
	call_deferred("_configured","")

func _configured(error: String) -> void:
	check("recorder_configured",error.is_empty())
	configure_done=true

func _read_render(field: String) -> void:
	if field=="decision":preview.solver.rd.buffer_get_data_async(preview.async_controller.water.decision,_read_arrived)
	elif field=="water_receipt":preview.solver.rd.buffer_get_data_async(preview.solver.water_receipt,_read_arrived)
	else:super._read_render(field)

func _collect_render() -> void:
	var device: RenderingDevice=preview.solver.rd
	var frame:=device.get_captured_timestamps_frame()
	if frame!=seen_capture:
		seen_capture=frame
		var starts:={}
		var spans:=[]
		for index in device.get_captured_timestamps_count():
			var label:=device.get_captured_timestamp_name(index)
			if label.ends_with("_start"):starts[label.trim_suffix("_start")]=device.get_captured_timestamp_gpu_time(index)
			elif label.ends_with("_end"):
				var key:=label.trim_suffix("_end")
				if starts.has(key):
					spans.append({"label":key,"group":PerfPanel._stage_for(key),"gpu_ns":device.get_captured_timestamp_gpu_time(index)-int(starts[key])})
					starts.erase(key)
		if not spans.is_empty():gpu_samples.append({"frame":frame,"spans":spans})
	call_deferred("_collected")

func _collected() -> void:
	collected=true
	collect_pending=false

func _run() -> void:
	preview=load(scene_path).instantiate()
	preview.playing=false
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("default_new_pipeline_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	check("fp_water_classified",PerfPanel._stage_for("fp_0_4_water_7_0")=="edit_water")
	check("fp_parent_not_added",PerfPanel._stage_for("fp_0_1_batch").is_empty())
	if wet_target:
		var found:=false
		for index in 65536:
			if preview.shadow_domain.water[index]>0.05 and index%256>10 and index%256<245:
				input_target=Vector3((index%256+0.5)*0.125-16,0,(index/256+0.5)*0.125-16)
				found=true
				break
		check("fixed_wet_target",found)
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"viewport":root.get_visible_rect().size,"vsync":DisplayServer.window_get_vsync_mode(),"profile":preview._runtime_configuration_signature(),"effective_profile":preview._effective_profile_request(),"loaded_gdscript_sha256":loaded_code()}
	RenderingServer.call_on_render_thread(_configure_render)
	while not configure_done:await process_frame
	hardware.velocity_override={"path":velocity_source,"sha256":FileAccess.get_sha256(velocity_source)} if not velocity_source.is_empty() else {}
	hardware.compute_overrides={}
	hardware.input_target=input_target
	for index in compute_overrides:hardware.compute_overrides[index]={"path":compute_overrides[index],"sha256":FileAccess.get_sha256(compute_overrides[index])}
	hardware.source_overrides={}
	for path in source_overrides:hardware.source_overrides[path]={"path":source_overrides[path],"sha256":FileAccess.get_sha256(source_overrides[path])}
	process_frame.connect(_observe_frame)
	if not failed:
		for iteration in 20:
			var started:=Time.get_ticks_usec()
			if case_id=="water":
				var tick_before: int=preview.completed_ticks
				preview._start_tick()
				deadline=Time.get_ticks_msec()+30000
				while preview.completed_ticks==tick_before and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
				check("water_completed_%d"%iteration,preview.completed_ticks==tick_before+1)
			else:
				check("edit_admitted_%d"%iteration,preview.input_scheduler.submit(command(iteration,input_target,case_id=="fill")).is_empty())
			check("drained_%d"%iteration,await idle())
			samples.append({"iteration":iteration,"wall_us":Time.get_ticks_usec()-started,"tick":preview.completed_ticks,"state_seq":preview.async_controller.state_seq,"actual_time":preview.async_controller.actual_time,"recording_us":preview.async_controller.water.last_recording_us if sampling_enabled and case_id=="water" else null,"edit_cpu_spans":preview.solver.receipt_batch_metrics.get("cpu_spans",[]).duplicate(true) if sampling_enabled and case_id!="water" else [],"viewport_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()) if sampling_enabled else null})
			if not preview.last_error.is_empty():break
		for frame in 6:await process_frame
		process_frame.disconnect(_observe_frame)
		while collect_pending:await process_frame
		var hashes:={}
		for field in ["sand","water","sediment","momentum_x","momentum_z","wetness","compaction","clock"]:hashes[field]=digest(await read(field))
		witnesses={"field_sha256":hashes,"state_seq":preview.async_controller.state_seq,"sim_tick":preview.completed_ticks,"actual_time":preview.async_controller.actual_time,"events":preview.async_controller.events.duplicate(true)}
		if case_id=="water":
			var decision: PackedByteArray=await read("decision")
			witnesses.last_decision={"substeps":decision.decode_u32(4),"actual_dt":decision.decode_float(12),"status":decision.decode_u32(16),"raw_hex":decision.hex_encode()}
		else:witnesses.last_water_receipt_hex=(await read("water_receipt")).hex_encode()
	check("no_runtime_failure",preview.last_error.is_empty())
	await preview.shutdown()
	check("released",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free()
	await process_frame
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"runtime":hardware,"case":case_id,"sampling":sampling_enabled,"samples":samples,"frame_us":frame_samples,"occupancy":occupancy,"gpu_samples":gpu_samples,"witnesses":witnesses},"\t"))
	quit(1 if failed else 0)
