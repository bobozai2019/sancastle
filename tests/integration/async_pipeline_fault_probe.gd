extends "res://tests/integration/async_pipeline_main_probe.gd"

var fault_case:="truncate"
var configured:=false
var render_result:=false
var render_done:=false
var dispose_done:=false
var dispose_result:=true
var setup_identity:={}
var fault_evidence:={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):fault_case=arg.trim_prefix("--case=")
	super._initialize()

func _configure_render() -> void:
	var transport=preview.solver.async_transport
	if fault_case=="upload":transport.inject_upload_failure_once=true
	elif fault_case in ["register","unknown"]:transport.inject_readback_failure_once=true
	else:transport.inject_completion_fault_once=fault_case
	transport.inject_fence_unavailable=fault_case=="unknown"
	call_deferred("_configured")

func _configured() -> void:configured=true

func _attempt_release_render() -> void:
	var ok: bool=preview.async_controller.release_render()
	call_deferred("_release_result",ok)

func _release_result(ok: bool) -> void:render_result=ok;render_done=true

func _recover_fence_render() -> void:
	preview.solver.async_transport.inject_fence_unavailable=false
	call_deferred("_retry_cleanup")

func _retry_cleanup() -> void:preview.async_controller.retry_fault_cleanup()

func _dispose_task() -> void:
	dispose_result=await get_root().get_node("BeachScenes")._dispose_scene(preview)
	dispose_done=true

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("fault_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		RenderingServer.call_on_render_thread(_configure_render)
		while not configured:await process_frame
		for i in 2:check("fault_admit_%d"%i,preview.input_scheduler.submit(command(3000+i)).is_empty())
		end=Time.get_ticks_msec()+20000
		while preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
		check("fault_reported",preview.last_error.begins_with("GPU pipeline fatal:") and not preview.async_controller.fault_reason.is_empty())
		check("fault_stops_admission",not preview.input_scheduler.accepting and not preview.async_controller.slots.accepting and not preview.ready_for_ticks and preview.input_scheduler.submit(command(3100))!=&"")
		check("fault_no_authority_ack",preview.async_controller.state_seq==0 and preview.completed_ticks==0 and preview.async_controller.accepted_commands==0 and preview.async_controller.rejected_commands==0)
		var expected_source:=0.0 if fault_case=="upload" else 0.03
		check("fault_nominal_booked_once",absf(preview.domain.sand_source_m3-expected_source)<0.0000001)
		check("fault_save_rejected",not (await preview.save_gpu_checkpoint(output.get_basename()+"_invalid.sandgp")).is_empty() and not FileAccess.file_exists(output.get_basename()+"_invalid.sandgp"))
		if fault_case=="unknown":
			end=Time.get_ticks_msec()+15000
			while not preview.async_controller.unconfirmed_ownership and Time.get_ticks_msec()<end:await process_frame
			check("fault_unknown_lease_retained",preview.async_controller.unconfirmed_ownership and preview.async_controller.records.size()==1 and preview.async_controller.slots.active_count()==1 and preview.solver.async_transport.has_owned())
			RenderingServer.call_on_render_thread(_attempt_release_render)
			while not render_done:await process_frame
			check("fault_no_partial_release",not render_result and preview.async_controller.water.rd!=null and preview.async_controller.collision.rd!=null and preview.solver.rd!=null)
			var identity: int=preview.get_instance_id()
			call_deferred("_dispose_task")
			end=Time.get_ticks_msec()+15000
			while not dispose_done and Time.get_ticks_msec()<end:await process_frame
			check("fault_unknown_close_bounded",dispose_done and not dispose_result and preview.async_shutdown_error==&"ownership_unconfirmed" and not preview.gpu_release_done)
			check("fault_node_kept_for_callbacks",is_instance_id_valid(identity) and preview.is_inside_tree() and preview.solver.rd!=null)
			RenderingServer.call_on_render_thread(_recover_fence_render)
		end=Time.get_ticks_msec()+20000
		while not preview.async_controller.records.is_empty() and Time.get_ticks_msec()<end:await process_frame
		check("fault_error_abort_completed",preview.async_controller.records.is_empty() and preview.async_controller.slots.active_count()==0 and preview.async_controller.aborted_units==(0 if fault_case=="upload" else 1) and preview.async_controller.unrecorded_units==(1 if fault_case=="upload" else 0) and not preview.async_controller.unconfirmed_ownership)
		check("fault_result_is_abort",preview.input_scheduler.terminal.size()==2 and preview.input_scheduler.terminal.all(func(row):return row.result.get("aborted",false) and not row.result.has("gpu_complete") and not row.result.has("state_seq")))
		check("fault_no_replay",preview.async_controller.submitted_edits==1 and preview.async_controller.submitted_water==0 and absf(preview.domain.sand_source_m3-expected_source)<0.0000001 and preview.input_scheduler.policies.is_empty() and preview.input_scheduler.reservations.is_empty())
		var events: Array=preview.async_controller.events
		var proof:=-1;var abort:=-1
		for i in events.size():
			if events[i].event=="terminal_proof":proof=i
			if events[i].event=="error_abort":abort=i
		check("fault_terminal_proof_before_reclaim",(proof==-1 and abort==-1 if fault_case=="upload" else proof>=0 and abort>proof) and not events.any(func(row):return row.event=="cpu_consume"))
		check("fault_fence_used_when_needed",preview.solver.async_transport.terminal_fences>0 if fault_case in ["register","unknown"] else preview.solver.async_transport.terminal_fences==0)
		fault_evidence={"case":fault_case,"error":preview.last_error,"fault_reason":preview.async_controller.fault_reason,"events":events.duplicate(true),"slots":preview.async_controller.slots.events.duplicate(true),"terminal_fences":preview.solver.async_transport.terminal_fences,"configuration":preview.source_signature,"loaded_scripts":loaded_code(),"physical_device_loss":false,"injection_scope":"registration/completion boundary only"}
	await preview.shutdown()
	check("fault_shutdown_releases_after_proof",preview.gpu_release_done and preview.solver.rd==null and preview.async_controller.water.rd==null and preview.async_controller.slots.can_release())
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var unexpected:=[];var fatal_lines:=0
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):
			if line.begins_with("ERROR: GPU pipeline fatal:"):fatal_lines+=1
			else:unexpected.append(line)
	check("fault_exact_expected_error",fatal_lines==1 and unexpected.is_empty() and not log_text.contains("SCRIPT ERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":fault_evidence},"\t"));file.close()
	quit(1 if failed else 0)
