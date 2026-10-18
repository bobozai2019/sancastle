extends "res://tests/integration/async_pipeline_capture_fault_probe.gd"

var candidate_evidence:={}

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("candidate_fault_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		var base: Dictionary=await preview.capture_async_checkpoint_data()
		check("candidate_fault_valid_checkpoint",base.error.is_empty())
		check("candidate_fault_mutation_admitted",preview.input_scheduler.submit(command(6000)).is_empty())
		preview._start_tick()
		check("candidate_fault_mutation_settled",await idle())
		var changed: Dictionary=await preview.capture_async_checkpoint_data()
		check("candidate_fault_distinct_state",changed.error.is_empty() and changed.checkpoint.native.fields.sand!=base.checkpoint.native.fields.sand)
		var old_solver=preview.solver
		var old_controller=preview.async_controller
		var epoch: int=preview.generation
		var state: int=preview.async_controller.state_seq
		var unknown:=fault_case in ["candidate-unknown","candidate-build-unknown"]
		var build_failure:=fault_case in ["candidate-build","candidate-build-unknown"]
		if build_failure:preview.inject_async_candidate_build_failure_phase="authority_restore"
		else:preview.inject_async_candidate_registration_failures=999 if fault_case=="candidate-all" else 1
		preview.inject_async_candidate_terminal_unavailable=unknown
		var restore_error: StringName=await preview.restore_gpu_checkpoint_data(base.checkpoint)
		check("candidate_fault_restore_rejected",not restore_error.is_empty())
		check("candidate_fault_live_owners_preserved",preview.solver==old_solver and preview.async_controller==old_controller and preview.generation==epoch and preview.async_controller.state_seq==state and old_solver.rd!=null)
		check("candidate_fault_no_metadata_commit",preview.completed_ticks==changed.checkpoint.sim_tick and preview._capture_brush_selection()==changed.checkpoint.selection.brush and not preview.beach_restore_running)
		check("candidate_fault_no_gpu_overwrite",await read("sand")==changed.checkpoint.native.fields.sand and await read("water")==changed.checkpoint.native.fields.water)
		if unknown:
			var candidate=preview.beach_restore_candidate
			check("candidate_unknown_retains_both_owners",restore_error==&"candidate_ownership_unconfirmed" and candidate!=null and candidate.unconfirmed_ownership and candidate.solver.rd!=null and not candidate.released and preview._async_ownership_unconfirmed())
			check("candidate_unknown_stops_live_pipeline",not preview.ready_for_ticks and not preview.input_scheduler.accepting and not preview.last_error.is_empty())
			RenderingServer.call_on_render_thread(_attempt_release_render)
			while not render_done:await process_frame
			check("candidate_unknown_no_partial_release",not render_result and old_controller.water.rd!=null and old_solver.rd!=null and candidate.solver.rd!=null)
			call_deferred("_dispose_task")
			end=Time.get_ticks_msec()+15000
			while not dispose_done and Time.get_ticks_msec()<end:await process_frame
			check("candidate_unknown_dispose_bounded",dispose_done and not dispose_result and not preview.gpu_release_done and preview.async_shutdown_error==&"ownership_unconfirmed" and preview.is_inside_tree())
			candidate.inject_terminal_unavailable=false
			check("candidate_recovered_discard",await preview.retry_async_candidate_cleanup())
			check("candidate_cleanup_proof_no_rebuild",candidate.released and candidate.solver.rd==null and candidate.pending==0 and candidate.terminal_proofs==1 and preview.beach_restore_candidate==null and preview.solver==old_solver and not preview.ready_for_ticks and not preview.last_error.is_empty())
			candidate_evidence.discard={"phase":candidate.build_phase,"expected":candidate.expected.size(),"observed":candidate.observed.size(),"pending":candidate.pending,"last_callback_us":candidate.last_callback_us,"release_us":candidate.release_us,"terminal_proofs":candidate.terminal_proofs}
		else:
			check("candidate_failure_fenced_and_released",preview.beach_restore_candidate==null and preview.solver.async_transport.terminal_fences==1)
			check("candidate_failure_admission_preserved",preview.ready_for_ticks and preview.input_scheduler.accepting and preview.last_error.is_empty())
			var retry: StringName=await preview.restore_gpu_checkpoint_data(base.checkpoint)
			check("candidate_failure_normal_restore_retry",retry.is_empty() and preview.generation==epoch+1 and old_solver.rd==null and preview.ready_for_ticks)
			var actual: Dictionary=await preview.capture_async_checkpoint_data()
			check("candidate_retry_authority_exact",actual.error.is_empty() and actual.checkpoint.native.fields==base.checkpoint.native.fields and actual.checkpoint.native.spare==base.checkpoint.native.spare)
			check("candidate_retry_continued_edit",preview.input_scheduler.submit(command(6001)).is_empty())
			preview._start_tick()
			check("candidate_retry_continued_water",await idle() and preview.completed_ticks==base.checkpoint.sim_tick+1)
		candidate_evidence.merge({"case":fault_case,"error":String(restore_error),"configuration":preview.source_signature,"loaded_scripts":loaded_code(),"physical_device_loss":false})
	await preview.shutdown()
	check("candidate_fault_safe_shutdown",preview.gpu_release_done and preview.solver.rd==null and preview.beach_restore_candidate==null)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var expected_errors:=1 if fault_case in ["candidate-unknown","candidate-build-unknown"] else 0
	var fatal_lines:=0;var unexpected:=[]
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):
			if line.begins_with("ERROR: GPU pipeline fatal:"):fatal_lines+=1
			else:unexpected.append(line)
	check("candidate_fault_only_expected_errors",fatal_lines==expected_errors and unexpected.is_empty() and not log_text.contains("SCRIPT ERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":candidate_evidence},"\t"));file.close()
	quit(1 if failed else 0)
