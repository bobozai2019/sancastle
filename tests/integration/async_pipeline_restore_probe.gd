extends "res://tests/integration/async_pipeline_main_probe.gd"

const Snapshot=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd")
var baseline:={}
var evidence:={}

func restored_tools() -> void:
	check("restored_shape_begin",(await preview.begin_shape_stroke(801)).is_empty())
	var brush:=Brush.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-3,-0.25),Vector2(-3,0.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,801,0,preview.completed_ticks,preview.shape_baseline_token)
	brush.material_profile_id=&"molded_v1"
	check("restored_shape_admission",preview.input_scheduler.submit(brush).is_empty())
	preview.input_running=true;preview.call_deferred("_drain_input")
	check("restored_shape_complete",await idle())
	check("restored_shape_success",preview.input_scheduler.terminal[-1].result.get("status")==1)
	check("restored_shape_end",(await preview.end_shape_stroke()).is_empty())
	var cpu:=command(1100,Vector3(-3,0,0));cpu.kind=&"compact";cpu.strength=0.25
	check("restored_compact",(await preview.apply_legacy_command(cpu)).get("results",[]).size()==1)
	var suspended:=command(1101,Vector3(-8,0,0));suspended.sand_destination="suspended_v1"
	check("restored_suspended_admission",preview.input_scheduler.submit(suspended).is_empty())
	check("restored_suspended_complete",await idle() and preview.input_scheduler.terminal[-1].result.get("status")==1)
	var count: int=preview.gravel_field.active_count
	check("restored_gravel_drop",(await preview.drop_gravel(Vector2(1,1),2)).get("active_count")==count+2)

func capture(label: String) -> Dictionary:
	var value: Dictionary=await preview.capture_async_checkpoint_data()
	check(label,value.error.is_empty())
	return value.get("checkpoint",{})

func same_native(label: String, a: Dictionary, b: Dictionary, new_generation: bool=false) -> void:
	for key in ["fields","spare","material","foam","histories"]:check(label+"_"+key,a.native[key]==b.native[key])
	var control: PackedByteArray=a.native.control.duplicate()
	if new_generation:control.encode_u64(8,b.generation)
	check(label+"_control",control==b.native.control)
	check(label+"_gravel_states",a.visual_extensions.gravel_v1.state_0==b.visual_extensions.gravel_v1.state_0 and a.visual_extensions.gravel_v1.state_1==b.visual_extensions.gravel_v1.state_1 and a.visual_extensions.gravel_v1.active_count==b.visual_extensions.gravel_v1.active_count)
	for key in ["ledger","advanced_time_s","state_seq","sim_tick","revision","selection","highwater_id","ticket_id","nominal_upper_supply","initial_sand_total_m3","simulation","wave_start_times"]:check(label+"_"+key,a[key]==b[key])

func collision_matches(value: Dictionary) -> bool:
	var bed: PackedFloat32Array=value.native.fields.rock.to_float32_array()
	var sand: PackedFloat32Array=value.native.fields.sand.to_float32_array()
	for i in bed.size():bed[i]+=sand[i]
	if preview.async_controller.collision.applied_state_seq.size()!=64:return false
	for chunk in 64:
		var data: PackedFloat32Array=preview.collision_proxy.shapes[chunk].shape.map_data
		for z in 33:
			for x in 33:
				if data[z*33+x]!=bed[mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)]:return false
		if preview.async_controller.collision.applied_state_seq[chunk]!=value.state_seq:return false
	return true

func _run() -> void:
	preview=load(scene_path).instantiate()
	preview.async_pipeline_enabled=true;preview.playing=false
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("restore_main_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		await tools()
		preview._start_tick()
		check("restore_baseline_tick",await idle())
		preview.domain.sand_source_m3+=10.0
		preview._apply_brush_selection({"tool":"wall_v1","parameters":{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},"dig_amount_m3":0.03,"fill_amount_m3":0.04})
		baseline=await capture("restore_capture_baseline")
		if not baseline.is_empty():
			var path:=output.get_basename()+".sandgp"
			check("restore_save_container",Snapshot.save(path,baseline).is_empty())
			check("restore_mutate_admission",preview.input_scheduler.submit(command(1001)).is_empty())
			preview._start_tick()
			check("restore_mutate_complete",await idle())
			preview._apply_brush_selection({"tool":"remove_sand","parameters":{},"dig_amount_m3":0.1,"fill_amount_m3":0.1})
			var changed:=await capture("restore_capture_changed")
			check("restore_changed_state",changed.state_seq>baseline.state_seq and changed.native.fields.sand!=baseline.native.fields.sand)
			var old_solver=preview.solver
			var old_controller=preview.async_controller
			var old_generation: int=preview.generation
			var invalid:=baseline.duplicate(true)
			invalid.native.spare.water.encode_float(0,NAN)
			check("restore_invalid_rejected",not (await preview.restore_gpu_checkpoint_data(invalid)).is_empty())
			check("restore_invalid_keeps_owners",preview.solver==old_solver and preview.async_controller==old_controller and preview.generation==old_generation and preview.ready_for_ticks and preview.input_scheduler.accepting)
			var after_invalid:=await capture("restore_capture_after_invalid")
			same_native("invalid_keeps_state",changed,after_invalid)
			preview.inject_beach_restore_failure=true
			var injected: StringName=await preview.restore_gpu_checkpoint_data(baseline)
			check("restore_candidate_failure_reported",injected==&"candidate_injected_failure")
			check("restore_candidate_discarded",preview.beach_restore_candidate==null and preview.solver==old_solver and preview.async_controller==old_controller and old_solver.rd!=null and preview.ready_for_ticks and preview.input_scheduler.accepting)
			var after_failure:=await capture("restore_capture_after_candidate_failure")
			same_native("candidate_failure_keeps_state",changed,after_failure)
			var restored: StringName=await preview.restore_gpu_checkpoint(path)
			check("restore_public_api",restored.is_empty())
			if not restored.is_empty():print("RESTORE_ERROR ",restored)
			if restored.is_empty():
				check("restore_new_generation",preview.generation>old_generation and preview.solver.owner_generation==preview.generation and preview.async_controller.slots.generation==preview.generation)
				check("restore_old_resources_released",old_solver.rd==null and old_controller.water.rd==null and old_controller.collision.rd==null)
				check("restore_fresh_pool",preview.async_controller.slots.active_count()==0 and preview.async_controller.records.is_empty() and preview.gpu_prefix.is_empty() and preview.command_queue.applied_log.is_empty())
				var after_restore:=await capture("restore_capture_completed")
				same_native("restore_exact",baseline,after_restore,true)
				check("restore_collision_actual_heights",collision_matches(baseline))
				check("restore_clock_bound",preview.async_clock_wrapper.texture_rd_rid==preview.solver.async_transport.clock_texture and (await read("clock")).decode_float(0)==baseline.advanced_time_s)
				check("restore_local_front_bound",preview.local_front_texture.texture_rd_rid==preview.local_front_field.texture)
				check("restore_gravel_generation",preview.gravel_field.generation==preview.generation and preview.gravel_field.active_count==514)
				check("restore_brush_parameters",preview._capture_brush_selection()==baseline.selection.brush and preview.ui_tool==&"wall_v1")
				check("restore_continued_edit",preview.input_scheduler.submit(command(1002)).is_empty())
				preview._start_tick()
				check("restore_continued_water",await idle() and preview.completed_ticks==baseline.sim_tick+1 and preview.async_controller.state_seq>baseline.state_seq)
				await restored_tools()
				check("restore_tools_usable",preview.last_error.is_empty() and await idle())
			evidence={"source_configuration":preview.source_signature,"baseline_state_seq":baseline.state_seq,"baseline_tick":baseline.sim_tick,"baseline_actual_time":baseline.advanced_time_s,"verifications":preview.beach_restore_verifications.duplicate(true),"restore_events":preview.beach_restore_events.duplicate(true),"runtime_error":preview.last_error}
	check("restore_runtime_healthy",preview.last_error.is_empty())
	await preview.shutdown()
	check("restore_shutdown_released",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("restore_no_engine_errors",not log_text.is_empty() and not log_text.contains("SCRIPT ERROR:") and not log_text.contains("\nERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":evidence},"\t"));file.close()
	quit(1 if failed else 0)
