extends "res://tests/integration/async_pipeline_all_tools_probe.gd"

# Fixed-world target and repetition baseline, using the production API.
func _run() -> void:
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("castle_baseline_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if not failed:
		await preview.get_node("Interface/PerformancePanel").stop_sampling()
		hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"viewport":root.get_visible_rect().size,"vsync":DisplayServer.window_get_vsync_mode(),"profile":preview._runtime_configuration_signature(),"effective_profile":preview._effective_profile_request(),"loaded_gdscript_sha256":loaded_code()}
		check("castle_baseline_visible",DisplayServer.get_name()!="headless" and root.visible)
		check("castle_baseline_begin",(await preview.begin_shape_stroke(9001)).is_empty())
		var value:=shape_command(&"castle_v1")
		var before:=Time.get_ticks_usec()
		var first: Dictionary=await preview.apply_gpu_command(value)
		var first_notice:=Time.get_ticks_usec()
		var first_wall_us:=first_notice-before
		check("castle_baseline_first_applied",first.get("status")==1)
		check("castle_baseline_first_drained",await idle())
		var fields:={}
		for field in ["sand","water","sediment","momentum_x","momentum_z","wetness","compaction","mold_support"]:
			var bytes: PackedByteArray=await read(field)
			fields[field]=bytes
			FileAccess.open(output.get_basename()+"_first_"+field+".bin",FileAccess.WRITE).store_buffer(bytes)
		var source: float=preview.domain.sand_source_m3
		var sink: float=preview.domain.sand_sink_m3
		value.command_id=preview.command_queue.last_command_id+1
		value.sample_index=1
		before=Time.get_ticks_usec()
		var repeated: Dictionary=await preview.apply_gpu_command(value)
		var repeat_notice:=Time.get_ticks_usec()
		check("castle_baseline_repeat_no_change",repeated.get("status")==2)
		check("castle_baseline_repeat_revision_stable",repeated.get("input_revision")==repeated.get("output_revision"))
		check("castle_baseline_repeat_source_sink_stable",preview.domain.sand_source_m3==source and preview.domain.sand_sink_m3==sink)
		check("castle_baseline_repeat_drained",await idle())
		var hashes:={}
		for field in fields:
			var after: PackedByteArray=await read(field)
			check("castle_baseline_repeat_unchanged_"+field,after==fields[field])
			hashes[field]=digest(after)
		check("castle_baseline_end",(await preview.end_shape_stroke()).is_empty())
		evidence={"first":first,"repeat":repeated,"repeat_command":value,"first_gpu_notice_wall_us":first_wall_us,"repeat_gpu_notice_wall_us":repeat_notice-before,"first_fields_sha256":hashes,"source_after_first":source,"sink_after_first":sink,"scope":"paused production castle first and repeat; notice wall time is not GPU stage time"}
	check("castle_baseline_no_runtime_failure",preview.last_error.is_empty())
	await preview.shutdown()
	check("castle_baseline_released",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame
	var log: String=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("castle_baseline_no_engine_errors",not log.contains("SCRIPT ERROR:") and not log.contains("\nERROR:"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"runtime":hardware,"evidence":evidence},"\t"))
	quit(1 if failed else 0)
