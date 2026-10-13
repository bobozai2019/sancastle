extends "res://tests/edit_validation/beach_recovery_entry.gd"
var sand_copy_trace=preload("res://scripts/simulation/edit_validation/beach_sand_copy_trace.gd").new()
var initial_trace_taken := false

func _mark_ready(token: int) -> void:
	super._mark_ready(token)
	if ready_for_ticks and not initial_trace_taken and "--beach-copy-native-early" in OS.get_cmdline_user_args():
		initial_trace_taken=true;RenderingServer.call_on_render_thread(_copy_initial_native)

func _copy_initial_native() -> void: sand_copy_trace.capture_native(self,completed_ticks)

func _tick_finished(substeps: int, source_m3: float, sink_m3: float, token: int) -> void:
	super._tick_finished(substeps,source_m3,sink_m3,token)
	if "--beach-copy-sand-trace" in OS.get_cmdline_user_args(): RenderingServer.call_on_render_thread(_copy_sand_tick.bind(completed_ticks))

func _copy_sand_tick(tick: int) -> void:
	sand_copy_trace.capture(solver,tick)
	if ("--beach-copy-native-boundary" in OS.get_cmdline_user_args() and tick in [7,8]) or ("--beach-copy-native-early" in OS.get_cmdline_user_args() and tick<=8): sand_copy_trace.capture_native(self,tick)
func _sand_trace_record(bytes: PackedByteArray, key: Variant) -> void: sand_copy_trace.record_data(bytes,key)
func _read_sand_trace() -> void: sand_copy_trace.read(self,solver)

func collect_sand_trace() -> Dictionary:
	RenderingServer.call_on_render_thread(_read_sand_trace)
	await get_tree().process_frame
	while sand_copy_trace.pending>0 or sand_copy_trace.data.size()<sand_copy_trace.records.size(): await get_tree().process_frame
	return sand_copy_trace.data.duplicate(true)

func _render_release() -> void:
	if solver!=null and solver.rd!=null and sand_copy_trace.pending==0: sand_copy_trace.release(solver)
	super._render_release()

func replay_item(item: Dictionary) -> Dictionary:
	if busy or shutdown_requested or not command_queue.pending.is_empty() or completed_ticks!=item.get("execution_tick",-1) or shadow_domain.tool_inventory_m3!=item.get("stock_before"): return {"error":"replay_input_mismatch"}
	var command: Dictionary=item.command.duplicate(true)
	if command.domain_id!=shadow_domain.domain_id: return {"error":"replay_domain_mismatch"}
	command.generation=generation
	water_policy=item.policy;signed_speed_m_s=item.speed
	command_queue.pending.append(command)
	command_queue.last_command_id=maxi(command_queue.last_command_id,int(command.command_id))
	var receipt: Dictionary=await execute_admitted_gpu_command(command,item.available_m3)
	for key in ["status","actual_sand_m3","nominal_sand_m3","edited_cells","clamp_count","capacity_status","displaced_water_m3","retained_water_m3","impulse_x_m4_s","impulse_z_m4_s","invalid_flags","error_code","dirty_mask","dirty_rect"]:
		if receipt.get(key)!=item.result.get(key): return {"error":"replay_receipt_mismatch","field":key}
	# Actual work used this worker's generation; canonical archived identities
	# stay historical after the receipt has independently matched.
	gpu_prefix[-1]=item.duplicate(true)
	if receipt.status==1: command_queue.applied_log[-1]=item.command.duplicate(true)
	return {"error":""}

func capture_complete_data() -> Dictionary:
	gpu_save_running=true;_start_checkpoint_capture()
	while checkpoint_capture_pending and last_error.is_empty(): await get_tree().process_frame
	while pending_beach_native_readbacks>0: await get_tree().process_frame
	gpu_save_running=false
	if not last_error.is_empty() or checkpoints.is_empty():
		checkpoint_capture_pending=false;checkpoint_capture.clear();return {}
	return checkpoints[-1].duplicate(true)
