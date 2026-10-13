extends "res://tests/water_material_natural/foam_sequence_probe.gd"

const Store:=preload("res://scripts/simulation/checkpoint_store.gd")

func _actual_clocks() -> Dictionary:
	return {"completed_tick":preview.completed_ticks,"visual_time_s":preview.visual_time_s,"water":preview.water_material.get_shader_parameter("visual_time_s"),"bed":preview.terrain_material.get_shader_parameter("visual_time_s")}

func _lighting_sweep(_before: Dictionary) -> void:
	preview.playing=false;preview.replay_target_tick=-1;preview.set_fixture_camera(&"close")
	var start_tick:int=preview.completed_ticks
	var before:=await _hash_state();var clocks:=_actual_clocks()
	for i in range(30):await process_frame;await RenderingServer.frame_post_draw
	var held:=await _hash_state();var held_clocks:=_actual_clocks()
	if before!=held or clocks!=held_clocks:_fail("compiled pause drift");return
	root.get_texture().get_image().save_png(output+"/before_save.png")
	var saved_identity:Dictionary=preview.effective_compilation.duplicate(true)
	var path:=output+"/ordinary.sandcp"
	var requested: StringName=preview.request_checkpoint_save(path)
	if not requested.is_empty():_fail("compiled ordinary save busy: "+String(requested));return
	var deadline:=Time.get_ticks_msec()+30000
	while preview.checkpoint_capture_pending or not preview.pending_save_path.is_empty():
		await process_frame
		if Time.get_ticks_msec()>deadline or not preview.last_error.is_empty():_fail("compiled ordinary save timeout/error");return
	if not preview.last_save_error.is_empty() or preview.last_save_path!=path:_fail("compiled ordinary save failed");return
	var loaded:=Store.load(path)
	if not String(loaded.error).is_empty():_fail("ordinary checksum/load failed");return
	var original_profile:Dictionary=loaded.checkpoint.render_profile.duplicate(true)
	var after_save:=await _hash_state()
	if before!=after_save:_fail("compiled save changed authority");return
	preview.queue_free()
	for i in range(10):await process_frame
	preview=load(scene_path).instantiate()
	preview.replay_checkpoint=loaded.checkpoint
	preview.replay_prefix_commands.assign(loaded.prefix_commands)
	preview.enable_erosion=loaded.enable_erosion
	preview.generation=int(loaded.checkpoint.shadow.generation)+1
	preview.replay_target_tick=start_tick
	root.add_child(preview)
	deadline=Time.get_ticks_msec()+180000
	while not preview.replay_ready:
		await process_frame
		if Time.get_ticks_msec()>deadline or not preview.last_error.is_empty():_fail("compiled cold restore failed: "+preview.last_error);return
	preview.set_fixture_camera(&"close")
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/restored.png")
	var restored:=await _hash_state();var restored_clocks:=_actual_clocks()
	var restored_identity:Dictionary=preview.effective_compilation.duplicate(true)
	var profile_unchanged:bool=preview.replay_checkpoint.render_profile==original_profile
	preview.replay_target_tick=start_tick+120;preview.replay_ready=false
	while not preview.replay_ready:
		await process_frame
		if Time.get_ticks_msec()>deadline or not preview.last_error.is_empty():_fail("compiled restored continuation failed: "+preview.last_error);return
	var continued_clocks:=_actual_clocks()
	root.get_texture().get_image().save_png(output+"/continued.png")
	var file:=FileAccess.open(output+"/ordinary_restore.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checkpoint":path,"checkpoint_sha256":FileAccess.get_sha256(path),"saved_render_profile":original_profile,"render_profile_unmodified":profile_unchanged,"pause":{"before":before,"held":held,"clocks_before":clocks,"clocks_held":held_clocks},"after_save":after_save,"restored":restored,"clocks_restored":restored_clocks,"clocks_continued":continued_clocks,"saved_compilation":saved_identity,"restored_compilation":restored_identity,"continued_compilation":preview.effective_compilation,"scope":"Candidate ordinary save/load without profile metadata substitution, held clocks and 120tick continuation. Not formal/edit/rollback or strict legacy cold-restore fix."},"\t"));file.close()
	if not profile_unchanged:_fail("ordinary profile metadata was modified")
