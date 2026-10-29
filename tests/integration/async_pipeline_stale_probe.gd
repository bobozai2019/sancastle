extends "res://tests/integration/async_pipeline_restore_probe.gd"

const Wire=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_protocol.gd")
var delayed_old_controller
var delayed_old_transport
var delayed_identity:={}
var delayed_bytes:=PackedByteArray()
var stale_render_done:=false

func _stale_render() -> void:
	delayed_old_transport._completed(delayed_bytes,delayed_identity,delayed_old_controller._arrived)
	delayed_old_controller._retire_render(delayed_identity)
	preview.solver.async_transport._completed(delayed_bytes,delayed_identity,preview.async_controller._arrived)
	call_deferred("_stale_done")

func _stale_done() -> void:stale_render_done=true

func wait_completed(count: int) -> bool:
	var end:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<end and preview.last_error.is_empty():
		var complete:=0
		for slot in preview.async_controller.slots.slots:
			if slot.state==preview.async_controller.Slots.State.GPU_COMPLETE:complete+=1
		if complete>=count:return true
		await process_frame
	return false

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("stale_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		preview.async_controller.hold_completions=true
		for i in 4:check("stale_admit_%d"%i,preview.input_scheduler.submit(command(3200+i)).is_empty())
		check("stale_two_real_completions_held",await wait_completed(2))
		var first: Dictionary=preview.async_controller.slots.slots[0]
		delayed_identity=first.identity.duplicate(true)
		delayed_old_controller=preview.async_controller;delayed_old_transport=preview.solver.async_transport
		delayed_bytes.resize(80);delayed_bytes.encode_u32(0,1)
		for pair in [[8,"generation"],[16,"batch_seq"],[32,"lease_id"]]:delayed_bytes.encode_u64(pair[0],delayed_identity[pair[1]])
		delayed_bytes.encode_u32(24,delayed_identity.slot_id)
		delayed_bytes.encode_u64(40,first.completion.state_seq)
		delayed_bytes.encode_u64(48,first.completion.sim_tick)
		delayed_bytes.encode_float(56,first.completion.advanced_time_s)
		delayed_bytes.encode_float(60,first.completion.actual_dt)
		delayed_bytes.encode_u64(64,first.completion.revision)
		delayed_bytes.encode_u32(72,first.completion.accepted_commands)
		delayed_bytes.encode_u32(76,first.completion.rejected_commands)
		preview.async_controller._receive(PackedByteArray(),delayed_identity)
		var wrong:=delayed_identity.duplicate();wrong.lease_id+=100
		preview.async_controller._receive(PackedByteArray(),wrong)
		check("stale_duplicate_does_not_fault_or_release",preview.last_error.is_empty() and preview.async_controller.slots.active_count()==2 and preview.async_controller.state_seq==0)
		preview.async_controller.hold_completions=false
		check("stale_normal_drain",await idle() and preview.async_controller.state_seq==2 and preview.async_controller.accepted_commands+preview.async_controller.rejected_commands==4)
		baseline=await capture("stale_save_boundary")
		check("stale_restore_generation",(await preview.restore_gpu_checkpoint_data(baseline)).is_empty() and preview.generation>delayed_identity.generation)
		check("stale_old_owner_closed",delayed_old_transport.rd==null and delayed_old_controller.slots.can_release())
		preview.async_controller.hold_completions=true
		for i in 2:check("stale_new_admit_%d"%i,preview.input_scheduler.submit(command(3300+i)).is_empty())
		check("stale_new_real_completion_held",await wait_completed(1))
		var new_identity: Dictionary=preview.async_controller.slots.slots[0].identity
		check("stale_real_slot_and_counter_reuse",new_identity.slot_id==delayed_identity.slot_id and new_identity.batch_seq==delayed_identity.batch_seq and new_identity.lease_id==delayed_identity.lease_id and new_identity.generation!=delayed_identity.generation)
		preview.async_controller._receive(delayed_bytes,delayed_identity)
		delayed_old_controller._submission_done(delayed_identity,"readback_submit_failed")
		delayed_old_controller._retire_failed(delayed_identity)
		RenderingServer.call_on_render_thread(_stale_render)
		while not stale_render_done:await process_frame
		check("stale_callbacks_do_not_touch_new_owner",preview.last_error.is_empty() and preview.async_controller.fault_reason.is_empty() and preview.async_controller.slots.active_count()==1 and preview.async_controller.state_seq==baseline.state_seq)
		preview.async_controller.hold_completions=false
		check("stale_new_result_still_consumed",await idle() and preview.async_controller.state_seq==baseline.state_seq+1 and preview.async_controller.accepted_commands+preview.async_controller.rejected_commands==6)
		evidence={"configuration":preview.source_signature,"loaded_scripts":loaded_code(),"old_identity":delayed_identity,"new_identity":new_identity,"events":preview.async_controller.events.duplicate(true),"old_transport_released":delayed_old_transport.rd==null,"real_driver":RenderingServer.get_current_rendering_driver_name()}
	await preview.shutdown()
	check("stale_shutdown_clean",preview.gpu_release_done and preview.solver.rd==null and preview.async_controller.slots.can_release())
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("stale_no_engine_errors",not log_text.is_empty() and not log_text.contains("SCRIPT ERROR:") and not log_text.contains("\nERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":evidence},"\t"));file.close()
	quit(1 if failed else 0)
