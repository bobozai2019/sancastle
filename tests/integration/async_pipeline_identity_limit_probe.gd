extends "res://tests/integration/async_pipeline_main_probe.gd"

const Pool=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_slots.gd")

func _run() -> void:
	var pool:=Pool.new(1)
	pool.batch_seq=9223372036854775807
	check("identity_batch_limit_no_wrap",pool.acquire().error=="identity_exhausted" and pool.active_count()==0 and pool.batch_seq==9223372036854775807)
	pool=Pool.new(1);pool.lease_seq=9223372036854775807
	check("identity_lease_limit_no_wrap",pool.acquire().error=="identity_exhausted" and pool.active_count()==0 and pool.lease_seq==9223372036854775807)
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("identity_limit_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		preview.async_controller.slots.batch_seq=9223372036854775807
		check("identity_limit_admit",preview.input_scheduler.submit(command(3500)).is_empty())
		end=Time.get_ticks_msec()+15000
		while preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
		check("identity_limit_fails_explicitly",preview.async_controller.fault_reason=="identity_exhausted" and not preview.input_scheduler.accepting)
		check("identity_limit_no_recorded_work",preview.async_controller.records.is_empty() and preview.async_controller.slots.active_count()==0 and preview.async_controller.submitted_edits==0 and preview.async_controller.state_seq==0 and preview.domain.sand_source_m3==0.0)
		check("identity_limit_cancelled_not_gpu_success",preview.input_scheduler.terminal.size()==1 and preview.input_scheduler.terminal[0].result.get("cancelled",false) and not preview.input_scheduler.terminal[0].result.has("gpu_complete"))
		hardware={"configuration":preview.source_signature,"loaded_scripts":loaded_code()}
	await preview.shutdown()
	check("identity_limit_close_finishes",preview.gpu_release_done and preview.solver.rd==null and preview.async_controller.slots.can_release())
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var errors:=[]
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):errors.append(line.strip_edges())
	check("identity_limit_only_expected_error",errors==["ERROR: GPU pipeline fatal: identity_exhausted"] and not log_text.contains("SCRIPT ERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":hardware},"\t"));file.close()
	quit(1 if failed else 0)
