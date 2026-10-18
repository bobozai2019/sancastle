extends "res://tests/integration/async_pipeline_all_tools_probe.gd"

var gravel_results:={}
var queued_save:={}
var shutdown_done:=false

func drops(index: int) -> void:
	gravel_results[index]=await preview.drop_gravel(Vector2(1+index*0.6,1),3)

func overlaps() -> void:
	check("overlap_begin",(await preview.begin_shape_stroke(501)).is_empty())
	var before: PackedByteArray=await read("sand")
	var submitted: int=preview.async_controller.submitted_edits
	var source: float=preview.domain.sand_source_m3
	preview.async_controller.hold_completions=true;preview.async_controller.hold_collision=true
	for i in 3:
		var a:=Vector2(-2+i*0.6,2)
		var value:=Brush.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},a,a+Vector2(0,0.5),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,501,i,preview.completed_ticks,preview.shape_baseline_token)
		value.material_profile_id=&"molded_v1"
		check("overlap_admit_%d"%i,preview.input_scheduler.submit(value).is_empty())
	var deadline:=Time.get_ticks_msec()+20000
	while preview.async_controller.submitted_edits<submitted+3 and Time.get_ticks_msec()<deadline:await process_frame
	check("three_shape_units_before_cpu_ack",preview.async_controller.submitted_edits==submitted+3 and preview.async_controller.slots.active_count()==3)
	var changed: PackedByteArray=await read("sand")
	check("shape_gpu_changes_without_cpu_ack",changed!=before and preview.domain.sand_source_m3==source)
	check("shape_publishes_complete_without_cpu_ack",changed==await read("published_sand"))
	check("shape_has_no_legacy_writer_lock",not preview.solver.receipt_pending and not preview.solver.publication_pending and not preview.async_controller.legacy)
	preview.async_controller.hold_completions=false;preview.async_controller.hold_collision=false
	check("overlap_end",(await preview.end_shape_stroke()).is_empty())
	check("overlap_drains",await idle())
	var count: int=preview.gravel_field.active_count
	for i in 3:drops(i)
	check("gravel_three_admitted_without_completion",preview.async_gravel_pending_count==3)
	deadline=Time.get_ticks_msec()+20000
	while gravel_results.size()<3 and Time.get_ticks_msec()<deadline:await process_frame
	check("gravel_three_results",gravel_results.size()==3 and gravel_results.values().all(func(result):return result.get("ok",false)))
	check("gravel_count_no_overwrite",preview.gravel_field.active_count==count+9)
	check("gravel_drained_flags",not preview.gravel_drop_pending and preview.async_gravel_pending_count==0 and await idle())
	var capacity: Dictionary=await preview.drop_gravel(Vector2(1,1),1024)
	check("gravel_invalid_count_rejected",capacity.get("error")==&"out_of_domain")
	var bad:=command(701);bad.kind=&"smooth";bad.strength=NAN
	check("smooth_nonfinite_rejected",(await preview.apply_legacy_command(bad)).has("error"))
	bad=command(702);bad.kind=&"compact";bad.radius_m=0.0
	check("compact_invalid_radius_rejected",(await preview.apply_legacy_command(bad)).has("error"))

func ui_stroke(tool: StringName, identity: int) -> bool:
	preview.ui_tool=tool;preview.brush_panel._on_tool_pressed(tool)
	var params: Dictionary={"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5} if tool==&"wall_v1" else {"trench_width_m":0.5,"depth_m":0.05,"shoulder_width_m":0.5}
	preview.brush_panel.apply_selection({"tool":String(tool),"parameters":params,"dig_amount_m3":preview.brush_panel.dig_amount(),"fill_amount_m3":preview.brush_panel.fill_amount()})
	check("ui_stroke_setup_%d"%identity,preview.stroke_controller.begin_stroke(tool,params,Vector2(3,-2),identity,preview.generation).is_empty())
	preview.ui_stroke_identity=identity;preview.ui_pressed=true;preview.ui_pump_running=true
	preview.stroke_controller.append_path_sample(Vector2(3,0))
	preview.call_deferred("_pump_ui_stroke",preview.generation,identity)
	var deadline:=Time.get_ticks_msec()+15000
	while preview.async_ui_pending.is_empty() and preview.ui_pump_running and Time.get_ticks_msec()<deadline:await process_frame
	check("ui_stroke_has_admitted_segments_%d"%identity,not preview.async_ui_pending.is_empty())
	return not preview.async_ui_pending.is_empty()

func save_during_ui() -> void:
	var start: int=preview.ui_brush_events.size()
	if not await ui_stroke(&"wall_v1",601):return
	var result: Dictionary=await preview.capture_async_checkpoint_data()
	check("capture_during_ui_closes_owned_stroke",result.error.is_empty() and not preview.ui_pump_running and preview.shape_stroke_id==0 and preview.stroke_controller.outstanding==0)
	check("ui_records_own_receipts",preview.ui_brush_events.size()>start and preview.ui_brush_events.slice(start).all(func(row):return row.command.command_id==row.terminal.result.command_id and row.terminal.result.get("gpu_complete",false)))
	check("ui_capture_stays_new_pipeline",preview.async_last_shadow_drain.is_empty() and not preview.async_controller.legacy and not preview.async_controller.transitioning)
	check("ui_save_drains",await idle())
	if not await ui_stroke(&"shovel_v1",602):return
	preview.brush_panel._on_tool_pressed(&"place_sand")
	var deadline:=Time.get_ticks_msec()+20000
	while preview.ui_pump_running and Time.get_ticks_msec()<deadline:await process_frame
	check("tool_switch_cancels_unsent_and_settles_admitted",not preview.ui_pump_running and preview.shape_stroke_id==0 and preview.stroke_controller.outstanding==0 and preview.stroke_controller.buffer_points()==0)
	check("tool_switch_drains",await idle())

func scene_roundtrip() -> void:
	var service=get_root().get_node("BeachScenes")
	service.attach(preview);current_scene=preview
	service.session_directory=output.get_basename()+"_sessions";DirAccess.make_dir_recursive_absolute(service.session_directory)
	for key in ["test1_capture","test1_backwash","main"]:
		var old_controller=preview.async_controller
		check("switch_request_"+key,service.request_switch(key))
		var deadline:=Time.get_ticks_msec()+60000
		while service.busy and Time.get_ticks_msec()<deadline:await process_frame
		check("switch_result_"+key,not service.busy and service.last_error.is_empty())
		evidence["switch_"+key]={"error":service.last_error,"busy":service.busy}
		if service.busy or not service.last_error.is_empty():return
		preview=service.active_scene;preview.playing=false
		check("switch_tools_owner_"+key,preview.async_controller.tools.shape==preview.shape_gpu and preview.async_controller.tools.gravel==preview.gravel_field and old_controller.tools==null and old_controller.water.rd==null)
		check("switch_shape_begin_"+key,(await preview.begin_shape_stroke(701)).is_empty())
		var result: Dictionary=await preview.apply_gpu_command(shape_command(&"wall_v1"))
		check("switch_shape_applies_"+key,result.get("status") in [1,2])
		check("switch_shape_end_"+key,(await preview.end_shape_stroke()).is_empty())
		check("switch_shape_drains_"+key,await idle())

func shutdown_task() -> void:
	await preview.shutdown();shutdown_done=true

func shutdown_inflight() -> void:
	if not await ui_stroke(&"wall_v1",801):return
	call_deferred("shutdown_task")
	var deadline:=Time.get_ticks_msec()+30000
	while not shutdown_done and Time.get_ticks_msec()<deadline:await process_frame
	check("inflight_ui_shutdown_completes",shutdown_done and preview.gpu_release_done and not preview.ui_pump_running and preview.solver.rd==null)

func _run() -> void:
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("boundary_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if not failed:await overlaps()
	if not failed:await save_during_ui()
	if not failed:await scene_roundtrip()
	if not failed:await shutdown_inflight()
	evidence.runtime_error=preview.last_error;evidence.configuration=preview.source_signature
	await preview.shutdown()
	check("boundary_shutdown",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame
	var log:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("boundary_no_engine_errors",not log.contains("SCRIPT ERROR:") and not log.contains("\nERROR:"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":evidence},"\t"))
	quit(1 if failed else 0)
