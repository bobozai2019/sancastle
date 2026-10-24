extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(Routes.FORMAL.test1_geometry).instantiate();scene.playing=false;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("geometry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:observations.error=String(scene.last_error);await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	var menu=scene.get_node("Interface/EditPanel/Margin/Controls/SceneSwitcher")
	check("two_routes_and_menu",Routes.KEYS==["main","test1_geometry"] and menu.targets.item_count==2 and menu.targets.selected==1)
	for key in ["test1_capture","test1_backwash"]:
		check("removed_target_rejected_"+key,not root.get_node("BeachScenes").request_switch(key) and Routes.scene_path("formal",key).is_empty())
	var path:=output+"/initial.sandue"
	check("initial_saved",(await scene.save_gpu_checkpoint(path)).is_empty())
	var saved:=Codec.load(path,scene.configuration)
	check("initial_valid",saved.error.is_empty())
	var state:=FileAccess.get_file_as_bytes("res://assets/test1_geometry/initial_state.f32").to_float32_array()
	var sand: PackedFloat32Array=saved.checkpoint.native.fields.sand.to_float32_array()
	var water: PackedFloat32Array=saved.checkpoint.native.fields.water.to_float32_array()
	var exact:=true
	for i in 65536:exact=exact and sand[i]==state[i*5] and water[i]==state[i*5+1]
	check("gpu_initial_state_matches_authored_channels",exact)
	for point in [Vector2(7,-5.3),Vector2(7,-2.7),Vector2(6,4.9)]:
		var i:=floori((point.y+16)/.125)*256+floori((point.x+16)/.125)
		check("inland_channel_has_shallow_water_"+str(point),water[i]>.10 and water[i]<.35)
	scene.hide_hud=true
	await _capture("initial")
	scene.playing=true
	start=Time.get_ticks_msec()
	while scene.runtime.current.advanced_time_s<10.0 and scene.last_error.is_empty() and Time.get_ticks_msec()-start<180000:
		await process_frame
		if scene.runtime.current.advanced_time_s>=4.5 and not observations.has("high_water"):
			observations.high_water=scene.runtime.current.advanced_time_s
			await _capture("runup")
	scene.playing=false;await _idle()
	check("runup_and_recession_advanced",scene.runtime.current.advanced_time_s>=10.0 and scene.last_error.is_empty())
	await _capture("recession")
	var before: int=scene.runtime.current.completed_state_seq
	check("channel_edit_admitted",scene.input.begin(&"place_sand",Vector2(4.1,0),{},.1,3,.25).accepted)
	scene.input.finish();await _idle()
	check("channel_edit_applied",scene.runtime.current.completed_state_seq>before and scene.input.terminal[-1].outcome==L.Outcome.APPLIED)
	check("restore_authored_checkpoint",(await scene.restore_gpu_checkpoint(path)).is_empty())
	await _idle()
	start=Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting or not scene.runtime.retired.is_empty()) and Time.get_ticks_msec()-start<30000:await process_frame
	var restored_path:=output+"/restored.sandue"
	var save_error: StringName=await scene.save_gpu_checkpoint(restored_path)
	observations.restore_save_error=String(save_error)
	check("restored_saved",save_error.is_empty())
	var restored:=Codec.load(restored_path,scene.configuration)
	check("restored_sand_and_water_exact",restored.error.is_empty() and restored.checkpoint.native.fields.sand==saved.checkpoint.native.fields.sand and restored.checkpoint.native.fields.water==saved.checkpoint.native.fields.water)
	await _close()

func _capture(label: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	check(label+"_image",root.get_texture().get_image().save_png(output+"/"+label+".png")==OK)
