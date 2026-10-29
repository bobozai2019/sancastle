extends "res://tests/edit_validation/beach_live_restore_probe.gd"

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_replay_original_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"complete initial anchor and original-prefix replay, strict native/ledger and isolated worker ownership"},"\t"));file.close()

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_replay_lab.tscn").instantiate();preview.playing=false
	preview.observe_coupled_parameters="--beach-parameter-trace" in OS.get_cmdline_user_args()
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): _write(false,preview.last_error);finished=true;quit(1);return
	rows.append({"case":"direct_entry_initial_complete_anchor","pass":preview.anchor_bootstrap_complete and not preview.anchor_bootstrap_pending and preview.full_replay_anchor.tick==0 and preview.full_replay_anchor.gpu_beach_edit.prefix.is_empty() and preview.pending_beach_native_readbacks==0 and preview.completed_ticks==0})
	if "--beach-replay-capture" in OS.get_cmdline_user_args():
		var capture_tick: int=preview.replay_capture_tick()
		await _ticks(capture_tick)
		if not await preview.capture_replay_gate("active"):
			_write(false,"capture_gate_failed");await preview.shutdown();finished=true;quit(1);return
		await _ticks(15-capture_tick)
	else: await _ticks(15)
	preview.water_policy=3;preview.signed_speed_m_s=0.25
	var first: Dictionary=await preview.apply_gpu_command(_command(9007199254741103,0.01))
	await _ticks(1)
	preview.water_policy=1;preview.signed_speed_m_s=0.0
	var command:=_command(9007199254741104,0.005);command.kind=&"place_sand"
	var second: Dictionary=await preview.apply_gpu_command(command)
	await _ticks(3)
	var before_path:=output.path_join("before.scp")
	var saved: StringName=await preview.save_gpu_checkpoint(before_path)
	var before: Dictionary=Store.load(before_path).checkpoint
	await _snapshot("before")
	var active=preview.solver;var original_generation: int=preview.generation
	var proof: Dictionary=await preview.prove_replay_current()
	if "--beach-material-stage-trace" in OS.get_cmdline_user_args():
		var active_material: Dictionary=await preview.collect_material_trace()
		var worker_material: Dictionary=proof.get("material_trace",{})
		for label in ["active","worker"]:
			var material: Dictionary=active_material if label=="active" else worker_material
			for key in material.data:
				var stage_file:=FileAccess.open(output.path_join("material_%s_%s.bin"%[label,key]),FileAccess.WRITE)
				stage_file.store_buffer(material.data[key]);stage_file.close()
			var metadata_file:=FileAccess.open(output.path_join("material_%s_metadata.json"%label),FileAccess.WRITE)
			metadata_file.store_string(JSON.stringify(material.metadata,"\t"));metadata_file.close()
	if preview.observe_coupled_parameters:
		var active_parameters: Dictionary=preview.replay_parameter_evidence()
		var worker_parameters: Dictionary=proof.get("parameters",{})
		var evidence: Dictionary={"active":active_parameters,"worker":worker_parameters,"exact":active_parameters==worker_parameters,"strict_native_replay":proof.get("ok",false),"scope":"host substep values, actual submitted material push bytes, SPIR-V identity; no claim about consumed native DXIL or pass inputs"}
		var parameter_file:=FileAccess.open(output.path_join("parameter_evidence.json"),FileAccess.WRITE)
		parameter_file.store_string(JSON.stringify(evidence,"\t"));parameter_file.close()
	if "--beach-copy-sand-trace" in OS.get_cmdline_user_args():
		var actual_trace: Dictionary=await preview.collect_sand_trace()
		for tick in actual_trace:
			for label in ["active","worker"]:
				var bytes: PackedByteArray=actual_trace[tick] if label=="active" else proof.sand_trace[tick]
				var filename: String="trace_%s_tick_%d.bin"%[label,tick] if typeof(tick)==TYPE_INT else "trace_%s_%s.bin"%[label,tick]
				var file:=FileAccess.open(output.path_join(filename),FileAccess.WRITE);file.store_buffer(bytes);file.close()
	var after_path:=output.path_join("after.scp")
	saved=await preview.save_gpu_checkpoint(after_path)
	var after: Dictionary=Store.load(after_path).checkpoint
	if not proof.get("replayed",{}).is_empty(): Store.save(output.path_join("replayed.scp"),proof.replayed,[],true)
	rows.append({"case":"original_two_edit_prefix_strict_native_replay","pass":first.get("status")==1 and second.get("status")==1 and proof.get("ok",false) and proof.get("isolated_materials",false),"error":proof.get("error"),"detail":proof.get("detail"),"isolated_materials":proof.get("isolated_materials")})
	rows.append({"case":"original_replay_keeps_active_authority_unchanged","pass":saved==&"" and preview.solver==active and preview.generation==original_generation and preview.completed_ticks==19 and _native_equal(before,after) and before.revision==after.revision})
	await _snapshot("after")
	var a:=Image.load_from_file(output.path_join("before.png"));var b:=Image.load_from_file(output.path_join("after.png"))
	rows.append({"case":"isolated_worker_does_not_publish_to_active_view","pass":a.get_data()==b.get_data()})
	var released:=true
	for entry in preview.branch_disposals: released=released and entry.released and entry.pending_native==0 and entry.release_us>=entry.last_callback_us
	rows.append({"case":"actual_worker_disposal_after_native_callbacks","pass":released and preview.branch_disposals.size()==1,"disposals":preview.branch_disposals})
	await preview.shutdown()
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok);preview.queue_free();for i in 4: await process_frame
	finished=true;print("BEACH_REPLAY_ORIGINAL_COMPLETE pass=%s"%str(ok));quit(0 if ok else 1)
