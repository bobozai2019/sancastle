extends "res://tests/edit_validation/water_transaction_probe.gd"

var close_started := false
var close_done := false
var close_us := -1
var pending_at_close := false

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("collision_exit_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"actual collision staging in-flight, closed epoch and release after callback"},"\t"))

func _close_at_pack() -> void:
	if close_started: return
	close_started=true;close_us=Time.get_ticks_usec()
	pending_at_close=lab.collision_proxy.staging_texture.is_valid()
	await lab.shutdown()
	close_done=true

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_interaction_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.water_policy=0;lab.collision_proxy.observe_bindings=true
	lab.collision_proxy.pack_submitted.connect(_close_at_pack)
	var proxy=lab.collision_proxy
	var stock: float=lab.domain.tool_inventory_m3
	var c:=_command(1,0.2);c.shape=&"swept_segment";c.radius_m=4.0
	c.transform.position_m=Vector3(-12,0,-0.0625);c.transform.end_position_m=Vector3(12,0,-0.0625)
	var result: Dictionary=await lab.apply_gpu_command(c)
	while not close_done: await process_frame
	var owned: bool=proxy.readback_callback_us>close_us and lab.release_record_us>=proxy.readback_callback_us and lab.release_wait_count>0 and proxy.rd==null and not proxy.staging_texture.is_valid()
	var settled: bool=result.get("status")==1 and lab.command_queue.applied_log.size()==1 and lab.domain.tool_inventory_m3==stock-result.actual_sand_m3
	var ok: bool=pending_at_close and owned and settled and proxy.applied_history.is_empty() and proxy.pending_revisions.is_empty() and lab.last_error.is_empty()
	rows.append({"pass":ok,"pending_at_close":pending_at_close,"owner_returned":owned,"settled_outcome_preserved":settled,"close_us":close_us,"readback_us":proxy.readback_callback_us,"release_us":lab.release_record_us,"wait_count":lab.release_wait_count,"applied_after_close":proxy.applied_history,"receipt":result})
	_write(ok);lab.queue_free();finished=true;print("COLLISION_EXIT_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)
