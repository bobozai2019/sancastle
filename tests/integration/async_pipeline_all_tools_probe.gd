extends "res://tests/integration/async_pipeline_main_probe.gd"

var evidence:={}
var readbacks_before:=0

func receipt(id: int) -> Dictionary:
	for row in preview.input_scheduler.terminal:
		if row.command.command_id==id:return row.result
	return {}

func shape_command(brush: StringName, sample: int=0, budget: bool=true) -> Dictionary:
	var parameters:={}
	var a:=Vector2(3,-0.5);var b:=Vector2(3,0.5)
	if brush==&"wall_v1":parameters={"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5}
	elif brush==&"shovel_v1":parameters={"trench_width_m":0.5,"depth_m":0.05,"shoulder_width_m":0.5}
	else:parameters={"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0};a=Vector2(2,3);b=a
	var value:=Brush.make_command(brush,parameters,a,b,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,preview.shape_stroke_id,sample,preview.completed_ticks,preview.shape_baseline_token)
	value.material_profile_id=&"plain_sand_v1" if brush==&"shovel_v1" else &"molded_v1"
	if not budget:value.add_budget_m3=0.0
	return value

func capture(label: String) -> Dictionary:
	var result: Dictionary=await preview.capture_async_checkpoint_data()
	check(label+"_capture",result.error.is_empty())
	return result.get("checkpoint",{})

func paired_smooth() -> void:
	var before:=await capture("smooth_before")
	if before.is_empty():return
	var cpu=preview.async_controller.owner.AsyncRestore.domain_from(before,preview.generation)
	var value:=command(301,Vector3(3,0,0))
	value.kind=&"smooth";value.strength=0.4;value.radius_m=0.75
	var reference:=value.duplicate(true)
	reference.position_m=value.transform.position_m
	check("smooth_cpu_reference_applied",cpu.apply_tool(reference).status==&"applied")
	var result: Dictionary=await preview.apply_legacy_command(value)
	check("smooth_gpu_applied",result.get("receipt",{}).get("status")==1)
	check("smooth_drains",await idle())
	var after:=await capture("smooth_after")
	if after.is_empty():return
	var error:=0.0;var mass:=0.0
	var actual: PackedFloat32Array=after.native.fields.sand.to_float32_array()
	var original: PackedFloat32Array=before.native.fields.sand.to_float32_array()
	var support: PackedFloat32Array=after.native.material.current_support.to_float32_array()
	var material_valid:=true
	for i in actual.size():
		error=maxf(error,absf(actual[i]-cpu.sand[i]))
		mass+=(actual[i]-original[i])*0.015625
		if support[i*2]<0 or support[i*2]>actual[i] or (support[i*2+1]!=actual[i] if support[i*2]>0 else support[i*2+1]!=0):material_valid=false
	check("smooth_cpu_gpu_within_float32",error<0.000002)
	check("smooth_conserves_sand",absf(mass)<0.000001)
	check("smooth_support_valid",material_valid and after.native.material.current_support==after.native.material.spare_support)
	check("smooth_ledgers_unchanged",before.ledger==after.ledger)
	evidence.smooth={"max_cell_error_m":error,"mass_delta_m3":mass}
	value=command(302,Vector3(3,0,0));value.kind=&"compact";value.strength=0.3
	var compact_reference=preview.async_controller.owner.AsyncRestore.domain_from(after,preview.generation)
	var compact_command:=value.duplicate(true);compact_command.position_m=value.transform.position_m
	check("compact_cpu_reference_applied",compact_reference.apply_tool(compact_command).status==&"applied")
	result=await preview.apply_legacy_command(value)
	check("compact_gpu_applied",result.get("receipt",{}).get("status")==1)
	check("compact_drains",await idle())
	var compacted:=await capture("compact_after")
	if compacted.is_empty():return
	check("compact_keeps_sand_water",compacted.native.fields.sand==after.native.fields.sand and compacted.native.fields.water==after.native.fields.water)
	check("compact_changes_material",compacted.native.fields.compaction!=after.native.fields.compaction)
	check("compact_keeps_ledgers",compacted.ledger==after.ledger)
	var compact_error:=0.0
	for i in 65536:compact_error=maxf(compact_error,absf(compacted.native.fields.compaction.decode_half(i*2)-compact_reference.compaction[i]))
	check("compact_cpu_gpu_within_half_storage",compact_error<=0.00048828125)
	evidence.compact={"max_cell_error":compact_error,"storage":"R16F; at most one half ULP at [0.5,1]"}

func paused_tools() -> void:
	var before:=await capture("initial")
	check("wall_begin",(await preview.begin_shape_stroke(101)).is_empty())
	var wall:=shape_command(&"wall_v1")
	var result: Dictionary=await preview.apply_gpu_command(wall)
	check("wall_gpu_applied",result.get("status")==1 and result.get("gpu_complete",false))
	check("wall_receipt_actual_revision",result.get("output_revision",0)==result.get("input_revision",0)+1)
	wall=shape_command(&"wall_v1",1)
	var repeated: Dictionary=await preview.apply_gpu_command(wall)
	check("wall_repeat_no_extra_sand",repeated.get("status")==2 and repeated.get("external_source_delta_m3",-1)==0.0)
	check("wall_end",(await preview.end_shape_stroke()).is_empty())
	check("wall_drains",await idle())
	check("wall_keeps_new_mode",not preview.async_controller.legacy and not preview.async_controller.transitioning)
	var source: float=preview.domain.sand_source_m3;var sink: float=preview.domain.sand_sink_m3
	var mass: float=await total_sand()
	check("shovel_begin",(await preview.begin_shape_stroke(102)).is_empty())
	result=await preview.apply_gpu_command(shape_command(&"shovel_v1"))
	check("shovel_gpu_applied",result.get("status")==1)
	check("shovel_balanced_receivers",absf(result.get("removed_m3",0)-result.get("left_received_m3",0)-result.get("right_received_m3",0))<=result.get("eps_transfer_m3",0))
	check("shovel_end",(await preview.end_shape_stroke()).is_empty())
	check("shovel_drains",await idle())
	check("shovel_mass_and_ledgers",absf((await total_sand())-mass)<0.000001 and source==preview.domain.sand_source_m3 and sink==preview.domain.sand_sink_m3)
	check("castle_begin",(await preview.begin_shape_stroke(103)).is_empty())
	result=await preview.apply_gpu_command(shape_command(&"castle_v1"))
	check("castle_gpu_applied_or_already_high",result.get("status") in [1,2])
	check("castle_end",(await preview.end_shape_stroke()).is_empty())
	check("castle_drains",await idle())
	var rejected_before:=await capture("reject_before")
	check("budget_begin",(await preview.begin_shape_stroke(104)).is_empty())
	var rejected:=shape_command(&"wall_v1",0,false)
	rejected.start_xz_m=Vector2(5,-0.5);rejected.end_xz_m=Vector2(5,0.5)
	result=await preview.apply_gpu_command(rejected)
	check("budget_rejected",result.get("status")==3 and result.get("error_code")==9)
	check("budget_end",(await preview.end_shape_stroke()).is_empty())
	check("budget_drains",await idle())
	var rejected_after:=await capture("reject_after")
	if not rejected_before.is_empty() and not rejected_after.is_empty():
		for field in rejected_before.native.fields:check("rejection_atomic_"+field,rejected_before.native.fields[field]==rejected_after.native.fields[field])
		check("rejection_atomic_support",rejected_before.native.material==rejected_after.native.material)
	await paired_smooth()
	var bed: PackedByteArray=await read("sand")
	var sediment: PackedByteArray=await read("sediment")
	var suspended:=command(401,Vector3(-8,0,0));suspended.sand_destination="suspended_v1";suspended.amount_m3=0.02
	check("suspended_admitted",preview.input_scheduler.submit(suspended).is_empty())
	check("suspended_new_pipeline_drains",await idle())
	check("suspended_keeps_bed",bed==await read("sand"))
	check("suspended_changes_sediment",sediment!=await read("sediment"))
	var rejected_count: int=preview.async_controller.rejected_commands
	var accepted_count: int=preview.async_controller.accepted_commands
	var dry:=command(402,Vector3(12,0,0));dry.sand_destination="suspended_v1"
	check("dry_suspended_admitted_for_gpu_rejection",preview.input_scheduler.submit(dry).is_empty())
	check("bed_fill_after_suspended_admitted",preview.input_scheduler.submit(command(403,Vector3(3,0,0))).is_empty())
	check("mixed_suspended_bed_batch_drains",await idle())
	check("dry_reject_does_not_stop_following_fill",preview.async_controller.rejected_commands==rejected_count+1 and preview.async_controller.accepted_commands==accepted_count+1 and preview.last_error.is_empty())
	var count: int=preview.gravel_field.active_count
	var drop: Dictionary=await preview.drop_gravel(Vector2(1,1),3)
	check("gravel_new_pipeline",drop.get("ok",false) and drop.active_count==count+3)
	check("gravel_drains",await idle())
	var final:=await capture("paused_final")
	if not final.is_empty():check("paused_tools_keep_clock",before.advanced_time_s==final.advanced_time_s and final.advanced_time_s==0.0)
	check("no_shadow_handoff",preview.async_shadow_jobs.is_empty() and preview.async_last_shadow_drain.is_empty())
	check("no_legacy_prefix",preview.gpu_prefix.is_empty())

func realtime_wall() -> void:
	preview.playing=true
	var start_tick: int=preview.completed_ticks
	var start_time: float=preview.async_controller.actual_time
	check("realtime_begin",(await preview.begin_shape_stroke(201)).is_empty())
	var admitted:=0
	var deadline:=Time.get_ticks_msec()+2500
	var sample:=0
	while Time.get_ticks_msec()<deadline and preview.last_error.is_empty():
		var start:=Vector2(5,-1+float(sample%8)*0.2)
		var value:=Brush.make_command(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},start,start+Vector2(0,0.2),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,preview.shape_stroke_id,sample,preview.completed_ticks,preview.shape_baseline_token)
		value.material_profile_id=&"molded_v1"
		var error: StringName=preview.input_scheduler.submit(value)
		if error.is_empty():admitted+=1;sample+=1
		elif error!=&"queue_full":check("realtime_admission_"+String(error),false);break
		check("realtime_stays_playing_%d"%sample,preview.playing and not preview.async_controller.legacy and not preview.async_controller.transitioning)
		await process_frame
	check("realtime_water_during_open_stroke",preview.completed_ticks>start_tick and preview.async_controller.actual_time>start_time and preview.shape_stroke_id==201)
	check("realtime_end",(await preview.end_shape_stroke()).is_empty())
	preview.playing=false
	check("realtime_drains",await idle())
	evidence.realtime={"admitted":admitted,"start_tick":start_tick,"end_tick":preview.completed_ticks,"start_time_s":start_time,"end_time_s":preview.async_controller.actual_time}

func save_restore() -> void:
	var before:=await capture("save_before")
	if before.is_empty():return
	var path:=output.get_basename()+".sandgp"
	check("save_new_tools",(await preview.save_gpu_checkpoint(path)).is_empty())
	check("mutation_admitted",preview.input_scheduler.submit(command(601)).is_empty())
	check("mutation_drains",await idle())
	check("restore_new_tools",(await preview.restore_gpu_checkpoint(path)).is_empty())
	var after:=await capture("restored")
	if not after.is_empty():
		for field in before.native.fields:check("restore_exact_"+field,before.native.fields[field]==after.native.fields[field])
		check("restore_exact_support",before.native.material==after.native.material)
		var old_gravel: Dictionary=before.visual_extensions.gravel_v1.duplicate(true)
		var new_gravel: Dictionary=after.visual_extensions.gravel_v1.duplicate(true)
		old_gravel.erase("source_generation");new_gravel.erase("source_generation")
		check("restore_exact_gravel",old_gravel==new_gravel and after.visual_extensions.gravel_v1.source_generation==preview.generation)
	check("restored_tools_bound",preview.async_controller.tools.shape==preview.shape_gpu and preview.async_controller.tools.gravel==preview.gravel_field)
	check("restored_stroke_begin",(await preview.begin_shape_stroke(301)).is_empty())
	check("restored_stroke_result",(await preview.apply_gpu_command(shape_command(&"wall_v1"))).get("status") in [1,2])
	check("restored_stroke_end",(await preview.end_shape_stroke()).is_empty())
	check("restored_tools_drain",await idle())

func _run() -> void:
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("all_tools_ready",preview.ready_for_ticks and preview.last_error.is_empty() and preview.async_controller.tools!=null)
	if not failed:await paused_tools()
	if not failed:await realtime_wall()
	if not failed:await save_restore()
	evidence.engine=Engine.get_version_info();evidence.gpu=RenderingServer.get_video_adapter_name();evidence.driver=RenderingServer.get_current_rendering_driver_name();evidence.window=DisplayServer.window_get_size()
	evidence.runtime_error=preview.last_error;evidence.configuration=preview.source_signature
	var controller=preview.async_controller
	await preview.shutdown()
	check("all_tools_shutdown",preview.gpu_release_done and preview.solver.rd==null and controller.tools==null)
	preview.queue_free();await process_frame
	var log:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("all_tools_no_engine_errors",not log.contains("SCRIPT ERROR:") and not log.contains("\nERROR:"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":evidence},"\t"))
	quit(1 if failed else 0)
