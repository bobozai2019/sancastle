extends "res://tests/integration/unified_edit_playable_probe.gd"

# Capture a restorable, pre-props formal source before touching runtime code.
func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("formal_main_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	observations.configuration=scene.configuration.duplicate(true)
	observations.engine=Engine.get_version_info()
	observations.hardware=RenderingServer.get_video_adapter_name()
	observations.driver=RenderingServer.get_current_rendering_driver_name()
	check("baseline_save",(await scene.save_gpu_checkpoint(output+"/baseline.sandue")).is_empty())
	var saved:=Codec.load(output+"/baseline.sandue",scene.configuration)
	check("baseline_codec_valid",saved.error.is_empty())
	check("baseline_restore",(await scene.restore_gpu_checkpoint(output+"/baseline.sandue")).is_empty())
	await RenderingServer.frame_post_draw
	check("baseline_image",root.get_texture().get_image().save_png(output+"/baseline.png")==OK)
	await _close()
