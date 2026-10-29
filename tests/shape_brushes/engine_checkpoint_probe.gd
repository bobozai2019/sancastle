extends "res://tests/shape_brushes/checkpoint_v4_probe.gd"

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	var mode:=OS.get_environment("SANDCASTLE_ENGINE_CHECKPOINT_MODE")
	if mode.is_empty():mode="produce"
	_check("engine_checkpoint_valid_mode",mode in ["produce","consume"])
	if mode not in ["produce","consume"]:_finish();quit(1);return
	preview=load("res://tests/shape_brushes/checkpoint_v4_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("engine_checkpoint_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	var actual_sha:=FileAccess.get_sha256(OS.get_executable_path())
	var evidence:Dictionary={"mode":mode,"engine_sha256":actual_sha,"engine_version":Engine.get_version_info(),"configuration":preview.source_signature.duplicate(true)}
	if mode=="produce":
		var result:=await stamp(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},Vector2.ZERO,Vector2(1,0),9900)
		_check("engine_checkpoint_real_wall",result.get("status")==1)
		var anchor:=await snapshot("engine_source_anchor");var anchor_meta:=metadata()
		var path:String=output.path_join("engine_checkpoint.scp")
		var error:StringName=await preview.save_gpu_checkpoint(path)
		_check("engine_checkpoint_actual_save",error.is_empty(),String(error))
		evidence.checkpoint_path=path;evidence.checkpoint_sha256=FileAccess.get_sha256(path)
		if error.is_empty():
			error=await preview.restore_gpu_checkpoint(path)
			_check("engine_checkpoint_same_binary_restore",error.is_empty(),String(error))
			_check("engine_checkpoint_same_binary_all27",exact(anchor,await snapshot("engine_source_restored")) and metadata()==anchor_meta)
	else:
		var path:=OS.get_environment("SANDCASTLE_ENGINE_CHECKPOINT_SOURCE")
		var source_info_path:=path.get_base_dir().path_join("engine_checkpoint.json")
		_check("engine_checkpoint_source_exists",not path.is_empty() and FileAccess.file_exists(path) and FileAccess.file_exists(source_info_path))
		if not path.is_empty() and FileAccess.file_exists(path) and FileAccess.file_exists(source_info_path):
			var source_info:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_info_path))
			# Store preserves Variant integer types; JSON metadata does not.
			var loaded:Dictionary=preview.Store.load(path)
			_check("engine_checkpoint_source_store_valid",loaded.error.is_empty(),String(loaded.error))
			if not loaded.error.is_empty():await preview.shutdown();_finish();quit(1);return
			var stored_configuration:Dictionary=loaded.checkpoint.gpu_beach_edit.configuration
			_check("engine_checkpoint_same_version",stored_configuration.engine==Engine.get_version_info())
			_check("engine_checkpoint_different_actual_binary",source_info.engine_sha256!=actual_sha)
			var source_configuration:Dictionary=stored_configuration.duplicate(true)
			var target_configuration:Dictionary=preview.source_signature.duplicate(true)
			source_configuration.erase("engine_executable_sha256");target_configuration.erase("engine_executable_sha256")
			_check("engine_checkpoint_only_binary_identity_differs",source_configuration==target_configuration)
			var anchor:=await snapshot("engine_target_anchor");var anchor_meta:=metadata();var generation_before:int=preview.generation
			var error:StringName=await preview.restore_gpu_checkpoint(path)
			_check("engine_checkpoint_rejects_other_binary",error==&"brush_checkpoint_configuration_mismatch",String(error))
			_check("engine_checkpoint_cross_binary_atomic",exact(anchor,await snapshot("engine_target_after")) and metadata()==anchor_meta and preview.generation==generation_before)
			evidence.source_path=path;evidence.source_checkpoint_sha256=FileAccess.get_sha256(path);evidence.restore_error=String(error)
	evidence.raw_index=raw_index
	var file:=FileAccess.open(output.path_join("engine_checkpoint.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"));file.close()
	await preview.shutdown();_check("engine_checkpoint_released",preview.gpu_release_done);preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
