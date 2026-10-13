extends "res://tests/edit_validation/water_transaction_probe.gd"

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("collision_batch_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"40 dirty-neighbor chunks, deferred batch with new GPU revisions; no performance"},"\t"))

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_interaction_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.water_policy=0;lab.collision_proxy.observe_bindings=true
	var first:=_command(1,0.2);first.shape=&"swept_segment";first.radius_m=4.0
	first.transform.position_m=Vector3(-12,0,-0.0625);first.transform.end_position_m=Vector3(12,0,-0.0625)
	var r: Dictionary=await lab.apply_gpu_command(first)
	var second:=_command(2,0.01)
	second.transform.position_m=Vector3(0,0,10)
	var s: Dictionary=await lab.apply_gpu_command(second)
	var deadline:=Time.get_ticks_msec()+3000
	while (not lab.collision_proxy.pending_revisions.is_empty() or lab.collision_proxy.staging_texture.is_valid()) and Time.get_ticks_msec()<deadline: await process_frame
	await physics_frame;await physics_frame
	var state: Dictionary=await _snapshot("final")
	var sand: PackedFloat32Array=state.sand.to_float32_array();var rock: PackedFloat32Array=state.rock.to_float32_array()
	var error:=0.0
	for chunk in lab.collision_proxy.shapes:
		var values: PackedFloat32Array=lab.collision_proxy.shapes[chunk].shape.map_data
		for z in 33:
			for x in 33:
				var i: int=mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)
				error=maxf(error,absf(values[z*33+x]-sand[i]-rock[i]))
	var tagged:=true;var advanced:=false
	for record in lab.collision_proxy.binding_history:
		tagged=tagged and record.captured_revision>=record.requested_revision and not record.receipt_pending and not record.publication_pending
		for requested in record.requested_by_chunk: advanced=advanced or record.captured_revision>requested
	var ok: bool=r.get("status")==1 and s.get("status")==1 and error<=1e-6 and tagged and advanced and lab.collision_proxy.binding_history.size()>=3 and lab.collision_proxy.invalid_readbacks==0 and lab.last_error.is_empty()
	rows.append({"pass":ok,"shape_error_m":error,"actual_revision_tags":tagged,"late_batch_newer_revision":advanced,"bindings":lab.collision_proxy.binding_history,"applied":lab.collision_proxy.applied_history})
	_write(ok);await lab.shutdown();lab.queue_free();finished=true;print("COLLISION_BATCH_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)
