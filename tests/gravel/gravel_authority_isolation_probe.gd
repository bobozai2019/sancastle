extends "res://tests/gravel/gravel_lifecycle_probe.gd"

var baselines := []

func _run() -> void:
	if output.is_empty(): output="res://test_output/gpu_gravel/isolation_"+str(Time.get_unix_time_from_system()).replace(".","_")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for enabled in [false,true]:
		preview=load("res://scenes/main.tscn").instantiate()
		preview.playing=false
		preview.gravel_enabled=enabled
		root.add_child(preview)
		var deadline := Time.get_ticks_msec()+120000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
		_check("isolation_ready_"+str(enabled),preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks: _finish();quit(1);return
		await _ticks(4)
		await _settle()
		for kind in [&"place_sand",&"remove_sand"]:
			var command: Dictionary={"domain_id":preview.shadow_domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":preview.command_queue.last_command_id+1,"kind":kind,"shape":&"circle","transform":{"position_m":Vector3(-2,0,0),"end_position_m":Vector3(-2,0,0)},"radius_m":0.3,"strength":1.0,"amount_m3":0.01,"seed":101}
			var error: StringName=preview.input_scheduler.submit(command)
			await preview.input_scheduler.drain_due()
			await _settle()
			_check("edit_"+str(enabled)+"_"+String(kind),error.is_empty() and preview.last_error.is_empty())
		await _ticks(4)
		await _settle()
		var path := output.path_join("checkpoint_"+str(enabled)+".bin")
		var save_error: StringName=await preview.save_gpu_checkpoint(path)
		_check("isolation_save_"+str(enabled),save_error.is_empty(),String(save_error))
		baselines.append(Store.load(path).checkpoint)
		_check("disabled_resources_"+str(enabled),(preview.gravel_field!=null)==enabled and ((preview.gravel_layer.layers&4)!=0)==enabled)
		await preview.shutdown()
		preview.queue_free()
		await _frames()
	var equal := true
	var rows := []
	for group in ["fields","spare","foam","material"]:
		var left: Dictionary=baselines[0].gpu_beach_native.get(group,{})
		var right: Dictionary=baselines[1].gpu_beach_native.get(group,{})
		for key in left:
			var same: bool=left[key]==right[key]
			equal=equal and same
			rows.append({"group":group,"field":key,"equal":same,"bytes":left[key].size() if left[key] is PackedByteArray else null})
	_check("all_native_authority_spare_foam_material_exact",equal,rows)
	_check("source_sink_and_sand_ledger_exact",baselines[0].gpu_beach_edit.ledger==baselines[1].gpu_beach_edit.ledger)
	_check("commands_and_revision_exact",baselines[0].gpu_beach_edit.prefix==baselines[1].gpu_beach_edit.prefix and baselines[0].tick==baselines[1].tick and baselines[0].revision==baselines[1].revision)
	_finish()
	print("GRAVEL_ISOLATION_OUTPUT ",output)
	var passed := true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)
