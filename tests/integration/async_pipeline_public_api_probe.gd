extends "res://tests/integration/async_pipeline_fault_probe.gd"

var public_evidence:={}
var public_done:=false
var public_result:={}

func _apply_task(value: Dictionary) -> void:
	public_result=await preview.apply_gpu_command(value)
	public_done=true

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("public_api_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		var healthy:=fault_case in ["realtime","suspended"]
		var changed_field: String="sediment" if fault_case=="suspended" else "sand"
		var before: PackedByteArray=await read(changed_field)
		if not healthy:
			RenderingServer.call_on_render_thread(_configure_render)
			while not configured:await process_frame
		var input:=command(7500,Vector3(-8,0,0) if fault_case=="suspended" else Vector3(-2,0,0))
		if fault_case=="suspended":input.sand_destination="suspended_v1"
		if fault_case=="realtime":preview.playing=true
		call_deferred("_apply_task",input)
		end=Time.get_ticks_msec()+20000
		while not public_done and Time.get_ticks_msec()<end:await process_frame
		check("public_api_result_bounded",public_done)
		if healthy:
			check("public_api_no_runtime_failure",preview.last_error.is_empty() and not public_result.has("error"))
			if fault_case=="realtime":
				check("public_api_realtime_own_completion",public_result.get("gpu_complete",false) and public_result.get("submitted",false) and public_result.get("ledger_precision")=="approximate" and preview.playing and preview.input_scheduler.terminal.any(func(row):return row.command.command_id==input.command_id and row.result==public_result))
			else:
				check("public_api_suspended_pipeline_completion",public_result.get("gpu_complete",false) and public_result.get("submitted",false) and not preview.async_legacy_running and not preview.async_controller.legacy and not preview.async_controller.transitioning)
			preview.playing=false
			check("public_api_healthy_settles",await idle())
			check("public_api_real_gpu_change",before!=await read(changed_field))
			check("public_api_nominal_booked_once",absf(preview.domain.sand_source_m3-0.015)<0.000001)
		else:
			check("public_api_failure_not_fake_completion",public_result.get("error")==&"backend_failed" and not public_result.has("gpu_complete") and not public_result.has("state_seq"))
			check("public_api_failure_stops_admission",not preview.ready_for_ticks and not preview.input_scheduler.accepting and not preview.last_error.is_empty())
			if fault_case=="unknown":
				end=Time.get_ticks_msec()+15000
				while not preview._async_ownership_unconfirmed() and Time.get_ticks_msec()<end:await process_frame
				call_deferred("_dispose_task")
				end=Time.get_ticks_msec()+15000
				while not dispose_done and Time.get_ticks_msec()<end:await process_frame
				check("public_api_unknown_owner_retained",dispose_done and not dispose_result and not preview.gpu_release_done and preview.async_controller.records.size()==1 and preview.solver.rd!=null)
				RenderingServer.call_on_render_thread(_recover_fence_render)
			end=Time.get_ticks_msec()+20000
			while not preview.async_controller.records.is_empty() and Time.get_ticks_msec()<end:await process_frame
			check("public_api_failure_drained_without_replay",preview.async_controller.records.is_empty() and preview.async_controller.slots.active_count()==0 and preview.async_controller.submitted_edits==1 and preview.input_scheduler.terminal.size()==1 and preview.input_scheduler.terminal[0].result.get("aborted",false))
			check("public_api_failed_nominal_once",absf(preview.domain.sand_source_m3-(0.0 if fault_case=="upload" else 0.015))<0.000001)
		public_evidence={"case":fault_case,"result":public_result,"error":preview.last_error,"configuration":preview.source_signature,"loaded_scripts":loaded_code(),"physical_device_loss":false}
	await preview.shutdown()
	check("public_api_safe_shutdown",preview.gpu_release_done and preview.solver.rd==null and preview.async_terminal.rd==null)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var errors:=[]
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):errors.append(line.strip_edges())
	check("public_api_only_expected_errors",errors.size()==(0 if fault_case in ["realtime","suspended"] else 1) and errors.all(func(line):return line.begins_with("ERROR: GPU pipeline fatal:")) and not log_text.contains("SCRIPT ERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":public_evidence},"\t"));file.close()
	quit(1 if failed else 0)
