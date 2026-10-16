extends "res://tests/water_material_natural/rdc_main_smoke.gd"

const GravelCodec = preload("res://scripts/visual/gravel_checkpoint_codec.gd")
const Store = preload("res://scripts/simulation/checkpoint_store.gd")
var gravel_data := {}
var saved_meta := {}

func _frames(count := 4) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw

func _settle() -> void:
	var deadline := Time.get_ticks_msec()+30000
	while preview.busy or preview.input_running or preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty() or preview.collision_proxy.has_prepare_in_flight():
		await process_frame
		if Time.get_ticks_msec()>deadline: _check("settle_timeout",false);return

func _read_gravel() -> void:
	preview.gravel_field.capture_async(_gravel_received,9000)

func _gravel_received(bytes: PackedByteArray, key: String, identity: Dictionary) -> void:
	_gravel_ready.call_deferred(bytes,key,identity)

func _gravel_ready(bytes: PackedByteArray, key: String, identity: Dictionary) -> void:
	gravel_data[key]=bytes
	saved_meta=identity

func _gravel() -> Dictionary:
	gravel_data.clear()
	RenderingServer.call_on_render_thread(_read_gravel)
	var deadline := Time.get_ticks_msec()+15000
	while gravel_data.size()<2 and Time.get_ticks_msec()<deadline: await process_frame
	var result := gravel_data.duplicate(true)
	result.current_index=preview.gravel_field.current_index
	result.tick=preview.gravel_field.completed_tick
	result.revision=preview.gravel_field.revision
	return result

func _same(a: Dictionary,b: Dictionary) -> bool:
	return a.state_0==b.state_0 and a.state_1==b.state_1 and a.current_index==b.current_index

func _publish_again() -> void:
	preview._publish_textures()

func _run() -> void:
	if output.is_empty(): output="res://test_output/gpu_gravel/lifecycle_"+str(Time.get_unix_time_from_system()).replace(".","_")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	preview=load("res://scenes/main.tscn").instantiate()
	preview.playing=false
	root.add_child(preview)
	var deadline := Time.get_ticks_msec()+120000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("main_gravel_ready",preview.ready_for_ticks and preview.gravel_field!=null,preview.last_error)
	if not preview.ready_for_ticks: _finish();quit(1);return
	await _ticks(3)
	await _settle()
	var before := await _gravel()
	await create_timer(2.0).timeout
	var after := await _gravel()
	_check("paused_two_seconds_exact",_same(before,after))
	RenderingServer.call_on_render_thread(_publish_again)
	await _frames()
	after=await _gravel()
	_check("duplicate_publish_exact",_same(before,after))
	var values: PackedFloat32Array=before["state_%d" % before.current_index].to_float32_array()
	var command: Dictionary={"domain_id":preview.shadow_domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":preview.command_queue.last_command_id+1,"kind":&"place_sand","shape":&"circle","transform":{"position_m":Vector3(values[0],0,values[2]),"end_position_m":Vector3(values[0],0,values[2])},"radius_m":0.3,"strength":1.0,"amount_m3":0.01,"seed":101}
	var submit: StringName=preview.input_scheduler.submit(command)
	await preview.input_scheduler.drain_due()
	await _settle()
	after=await _gravel()
	var edited: PackedFloat32Array=after["state_%d" % after.current_index].to_float32_array()
	var xz_equal := true
	for id in 512: xz_equal=xz_equal and values[id*4]==edited[id*4] and values[id*4+2]==edited[id*4+2]
	_check("paused_edit_reprojects_without_xz",submit.is_empty() and xz_equal and edited[1]>values[1] and after.tick==before.tick,{"before_y":values[1],"after_y":edited[1]})
	var path := output.path_join("checkpoint.bin")
	var save_error: StringName=await preview.save_gpu_checkpoint(path)
	_check("save_extension",save_error.is_empty(),String(save_error))
	if not save_error.is_empty(): await preview.shutdown();_finish();quit(1);return
	var checkpoint: Dictionary=Store.load(path).checkpoint
	_check("native_counts_unchanged",preview.capture_raw.size()==preview._native_capture_raw_count() and checkpoint.visual_extensions.gravel_v1.count==512,{"native_raw_count":preview.capture_raw.size(),"gravel_callbacks":preview.gravel_capture_callbacks})
	before=await _gravel()
	var authority_before:=await _snapshot()
	await _ticks(2)
	await _settle()
	var continued := await _gravel()
	var old_generation: int=preview.generation
	var restore_error: StringName=await preview.restore_gpu_checkpoint_data(checkpoint)
	_check("restore",restore_error.is_empty(),String(restore_error))
	after=await _gravel()
	_check("both_states_exact_after_restore",_same(before,after) and after.tick==checkpoint.tick and after.revision==checkpoint.revision and preview.generation>old_generation)
	var authority_after:=await _snapshot()
	var equal := true
	for field in FIELDS: equal=equal and authority_before[field]==authority_after[field]
	_check("restore_authority_exact",equal)
	await _ticks(2)
	await _settle()
	after=await _gravel()
	_check("continued_trajectory_exact",_same(continued,after))
	before=after
	var corruptions := ["version","length","nan","wet","domain","profile","profile_hash","tick","current_index"]
	for kind in corruptions:
		var bad := checkpoint.duplicate(true)
		var ext: Dictionary=bad.visual_extensions.gravel_v1
		match kind:
			"version": ext.version=99
			"length": ext.state_1=PackedByteArray([1])
			"nan": ext.state_0.encode_float(0,NAN)
			"wet": ext.state_0.encode_float(12,0.5)
			"domain": ext.domain_id="wrong_scene"
			"profile": ext.profile_values.h_epsilon_m=0.0
			"profile_hash": ext.profile_sha256="bad"
			"tick": ext.tick+=1
			"current_index": ext.current_index=2
		var generation_before: int=preview.generation
		var error: StringName=await preview.restore_gpu_checkpoint_data(bad)
		var observed:=await _gravel()
		_check("reject_"+kind,not error.is_empty() and preview.generation==generation_before and _same(before,observed),String(error))
	preview.inject_beach_restore_failure=true
	var candidate_error: StringName=await preview.restore_gpu_checkpoint_data(checkpoint)
	after=await _gravel()
	_check("candidate_failure_keeps_active",candidate_error==&"candidate_injected_failure" and _same(before,after) and preview.beach_restore_candidate==null,String(candidate_error))
	var pending_before: int=preview.gravel_capture_callbacks
	var rid_before: RID=preview.gravel_wrapper.texture_rd_rid
	preview._gravel_capture_received(PackedByteArray(),"state_0",{"generation":old_generation,"request_id":-1,"tick":0,"revision":0})
	_check("old_callback_does_not_touch_active",preview.gravel_capture_callbacks==pending_before and preview.gravel_wrapper.texture_rd_rid==rid_before)
	var legacy := checkpoint.duplicate(true)
	legacy.erase("visual_extensions")
	var legacy_error: StringName=await preview.restore_gpu_checkpoint_data(legacy)
	_check("missing_extension_seeds",legacy_error.is_empty() and preview.gravel_field!=null,String(legacy_error))
	var pre_gravel: Dictionary=Store.load("res://test_output/gpu_gravel/baseline_20261015/main_checkpoint.bin").checkpoint
	var historic_error: StringName=await preview.restore_gpu_checkpoint_data(pre_gravel)
	_check("known_pre_gravel_checkpoint",historic_error.is_empty(),String(historic_error))
	await preview.shutdown()
	_check("shutdown_frees_gravel",preview.gpu_release_done and preview.gravel_field==null and preview.gravel_capture_callbacks==0)
	_finish()
	print("GRAVEL_LIFECYCLE_OUTPUT ",output)
	var passed := true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)
