extends "res://tests/gravel/gravel_lifecycle_probe.gd"

var service
var saved_gravel := {}

func _switch(key: String, fail_target := false) -> void:
	var before: int=preview.generation
	service.inject_target_failure_once=fail_target
	_check("admit_"+key,service.request_switch(key))
	var deadline := Time.get_ticks_msec()+180000
	while service.busy and Time.get_ticks_msec()<deadline: await process_frame
	preview=service.active_scene
	_check("switch_ready_"+key,not service.busy and preview!=null and preview.ready_for_ticks and preview.last_error.is_empty(),service.last_error)
	_check("generation_"+key,preview.generation>before)
	if not fail_target: _check("route_"+key,preview.scene_key==key and service.last_error.is_empty())

func _run() -> void:
	if output.is_empty(): output="res://test_output/gpu_gravel/switch_"+str(Time.get_unix_time_from_system()).replace(".","_")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	service=root.get_node("BeachScenes")
	preview=load("res://scenes/main.tscn").instantiate()
	preview.playing=false
	root.add_child(preview)
	current_scene=preview
	var deadline := Time.get_ticks_msec()+120000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("main_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks: _finish();quit(1);return
	for key in ["main","test1_capture","test1_backwash"]:
		if preview.scene_key!=key: await _switch(key)
		await _ticks(2)
		await _settle()
		saved_gravel[key]=await _gravel()
	for key in ["main","test1_capture","test1_backwash"]:
		await _switch(key)
		var restored:=await _gravel()
		_check("restore_gravel_exact_"+key,_same(saved_gravel[key],restored) and restored.tick==saved_gravel[key].tick)
	preview._start_tick()
	_check("tick_inflight",preview.tick_pending)
	await _switch("main")
	var loaded: Dictionary=Store.load(service.saved.test1_backwash.path).checkpoint
	await _switch("test1_backwash")
	var restored:=await _gravel()
	_check("inflight_tick_gravel_saved",restored.tick==saved_gravel.test1_backwash.tick+1 and _same(loaded.visual_extensions.gravel_v1,restored))
	var rollback:=await _gravel()
	await _switch("test1_capture",true)
	var after:=await _gravel()
	_check("failed_target_rolls_back_gravel",preview.scene_key=="test1_backwash" and not service.last_error.is_empty() and _same(rollback,after))
	var releases_ok := true
	for record in service.release_records: releases_ok=releases_ok and record.gpu_released and record.node_freed
	_check("all_switch_resources_released",releases_ok,service.release_records.duplicate(true))
	await preview.shutdown()
	_check("shutdown",preview.gpu_release_done and preview.gravel_field==null)
	FileAccess.open(output.path_join("release_records.json"),FileAccess.WRITE).store_string(JSON.stringify(service.release_records,"\t"))
	_finish()
	print("GRAVEL_SWITCH_OUTPUT ",output)
	var passed := true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)
