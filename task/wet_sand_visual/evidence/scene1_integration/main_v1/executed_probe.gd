extends "res://tests/integration/unified_edit_playable_probe.gd"

var read_done:=false
var history:=PackedByteArray()

func _read_history() -> void:
	var p=scene.runtime.current
	var bytes: PackedByteArray=p.state.rd.texture_get_data(p.state.surface_wetness,0) if p.state.surface_wetness.is_valid() else PackedByteArray()
	call_deferred("_received_history",bytes)

func _received_history(bytes: PackedByteArray) -> void:history=bytes;read_done=true

func _snapshot(label: String) -> void:
	read_done=false;RenderingServer.call_on_render_thread(_read_history)
	while not read_done:await process_frame
	FileAccess.open(output+"/"+label+".bin",FileAccess.WRITE).store_buffer(history)

func _capture(label: String) -> void:
	for frame in 6:
		await process_frame;await RenderingServer.frame_post_draw
	check("capture_"+label,root.get_texture().get_image().save_png(output+"/"+label+".png")==OK)

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn" if scene_key=="main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing=false;scene.generation=2001;root.add_child(scene)
	var started:=Time.get_ticks_msec()
	var last_report:=started
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-started<90000:
		await process_frame
		if Time.get_ticks_msec()-last_report>10000:
			last_report=Time.get_ticks_msec()
			print("WET_BOOT ",scene.runtime.phase," ready=",scene.ready_for_ticks," booting=",scene._booting," events=",scene.runtime.events)
	check("formal_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:observations.error=String(scene.last_error);await _close();return
	var wet_enabled: bool=scene_key in ["main","test1_geometry"]
	var p=scene.runtime.current
	observations.configuration=scene.configuration.duplicate(true)
	observations.sources=scene.configuration.sources.duplicate(true)
	observations.device={"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"size":str(DisplayServer.window_get_size())}
	check("scene_specific_allocation",p.state.surface_wetness.is_valid()==wet_enabled)
	var material: ShaderMaterial=scene.get_node("GpuSandTerrain").material_override
	check("scene_specific_material",(material.get_shader_parameter("use_surface_wetness")==true)==wet_enabled)
	if wet_enabled:check("formal_material_binding",material.get_shader_parameter("surface_wetness_state").texture_rd_rid==p.state.surface_wetness)
	scene.hide_hud=true
	scene._on_trigger_wave_pressed()
	for target in ([6,16,24] if wet_enabled else [1]):
		scene.playing=true;started=Time.get_ticks_msec()
		while p.advanced_time_s<float(target) and scene.last_error.is_empty() and Time.get_ticks_msec()-started<90000:await process_frame
		scene.playing=false;await _idle()
		check("advanced_"+str(target),p.advanced_time_s>=float(target) and scene.last_error.is_empty())
		if wet_enabled:await _snapshot("t"+str(target))
		await _capture("t"+str(target))
	if wet_enabled:
		var paused:=history.duplicate();await create_timer(2.0).timeout;await _snapshot("paused")
		check("paused_history_exact",history==paused)
		var peak:=0.0;var valid:=true
		for value in history.to_float32_array():peak=maxf(peak,value);valid=valid and is_finite(value) and value>=0.0 and value<=1.0
		check("finite_active_history",valid and peak>0.4)
	var path:=output+"/saved.sandue"
	check("save",(await scene.save_gpu_checkpoint(path)).is_empty())
	var saved:=Codec.load(path,scene.configuration)
	check("saved_codec",saved.error.is_empty())
	if not saved.error.is_empty():observations.error=String(saved.error);await _close();return
	check("container_version",saved.checkpoint.version==(7 if wet_enabled else 6))
	if wet_enabled:
		check("save_history_exact",saved.checkpoint.visual_extensions.wet_sand_v1.state==history)
		var bad: Dictionary=saved.checkpoint.duplicate(true)
		bad.visual_extensions.wet_sand_v1.state=PackedByteArray([0])
		check("reject_truncated_history",Codec.validate(bad,scene.configuration)==&"invalid_surface_wetness_size")
		bad=saved.checkpoint.duplicate(true);bad.visual_extensions.wet_sand_v1.state.encode_float(0,NAN)
		check("reject_nan_history",Codec.validate(bad,scene.configuration)==&"invalid_surface_wetness_value")
		bad=saved.checkpoint.duplicate(true);bad.visual_extensions.wet_sand_v1.tick+=1
		check("reject_wrong_identity",Codec.validate(bad,scene.configuration)==&"surface_wetness_identity_mismatch")
		bad=saved.checkpoint.duplicate(true);bad.visual_extensions.wet_sand_v1.unexpected=1
		check("reject_unknown_key",Codec.validate(bad,scene.configuration)==&"invalid_surface_wetness_state")
	check("edit_admitted",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted)
	scene.input.finish();await _idle()
	check("edit_receipts",not scene.input.terminal.is_empty())
	check("restore",(await scene.restore_gpu_checkpoint(path)).is_empty())
	started=Time.get_ticks_msec()
	while scene._booting and Time.get_ticks_msec()-started<30000:await process_frame
	for frame in 6:await process_frame
	await _idle()
	if wet_enabled:
		await _snapshot("restored")
		check("restore_history_exact",history==saved.checkpoint.visual_extensions.wet_sand_v1.state)
		check("restore_material_binding",material.get_shader_parameter("surface_wetness_state").texture_rd_rid==scene.runtime.current.state.surface_wetness)
		await _capture("restored")
	var path2:=output+"/restored.sandue"
	var save_error: StringName=await scene.save_gpu_checkpoint(path2)
	observations.save_after_restore_error=String(save_error)
	check("save_after_restore",save_error.is_empty())
	var after:=Codec.load(path2,scene.configuration)
	check("restored_codec",after.error.is_empty())
	if after.error.is_empty():
		for field in saved.checkpoint.native.fields:check("restored_physics_"+field,after.checkpoint.native.fields[field]==saved.checkpoint.native.fields[field])
		check("restored_clock",after.checkpoint.advanced_time_s==saved.checkpoint.advanced_time_s)
	observations.final_tick=scene.runtime.current.completed_tick
	await _close()
