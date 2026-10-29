extends "res://tests/integration/async_pipeline_fault_probe.gd"

var switch_evidence:={}

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("switch_fault_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		var loaded:=loaded_code()
		check("switch_fault_edit_admitted",preview.input_scheduler.submit(command(7100)).is_empty())
		check("switch_fault_edit_settled",await idle())
		var before: PackedByteArray=await read("sand")
		var service=get_root().get_node("BeachScenes")
		service.attach(preview);current_scene=preview
		service.session_directory=output.get_basename()+"_sessions"
		DirAccess.make_dir_recursive_absolute(service.session_directory)
		var identity: int=preview.get_instance_id()
		var solver=preview.solver
		preview.async_terminal.inject_unavailable=true
		check("switch_fault_request",service.request_switch("test1_backwash"))
		end=Time.get_ticks_msec()+30000
		while service.busy and Time.get_ticks_msec()<end:await process_frame
		check("switch_fault_terminates",not service.busy and not service.last_error.is_empty())
		check("switch_fault_restores_scene_identity",service.active_scene==preview and current_scene==preview and is_instance_id_valid(identity) and preview.is_inside_tree())
		check("switch_fault_retains_live_resources",preview.solver==solver and solver.rd!=null and preview.async_controller.water.rd!=null and not preview.gpu_release_done and preview.async_shutdown_error==&"ownership_unconfirmed")
		check("switch_fault_no_target_created",not root.get_children().any(func(node):return node!=preview and "scene_key" in node and node.scene_key=="test1_backwash"))
		check("switch_fault_release_record",service.release_records.size()==1 and not service.release_records[0].gpu_released and not service.release_records[0].node_freed)
		var saved: Dictionary=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd").load(service.saved.main.path,preview.source_signature)
		check("switch_fault_progress_saved",saved.error.is_empty() and saved.checkpoint.native.fields.sand==before and saved.checkpoint.state_seq==preview.async_controller.state_seq)
		check("switch_fault_pipeline_stopped",not preview.ready_for_ticks and not preview.input_scheduler.accepting and not preview.last_error.is_empty())
		end=Time.get_ticks_msec()+10000
		while preview.async_fault_probe_running or preview.async_terminal.pending:await process_frame
		preview.async_terminal.inject_unavailable=false
		check("switch_fault_recover_only_proof",await preview.retry_async_terminal_proof() and not preview.ready_for_ticks and not preview.async_terminal.confirmed)
		switch_evidence={"configuration":preview.source_signature,"loaded_scripts":loaded,"error":service.last_error,"release_records":service.release_records.duplicate(true),"saved_path":service.saved.main.path,"physical_device_loss":false}
	await preview.shutdown()
	check("switch_fault_final_release",preview.gpu_release_done and preview.solver.rd==null and preview.async_terminal.rd==null and preview.async_terminal.confirmed)
	switch_evidence.terminal_events=preview.async_terminal.events.duplicate(true)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var errors:=[]
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):errors.append(line.strip_edges())
	check("switch_fault_exact_error",errors==["ERROR: GPU pipeline fatal: final stream ownership unavailable"] and not log_text.contains("SCRIPT ERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":switch_evidence},"\t"));file.close()
	quit(1 if failed else 0)
