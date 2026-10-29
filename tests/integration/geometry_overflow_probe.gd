extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
const Boundary=preload("res://scripts/simulation/unified_edit/boundary.gd")

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
	observations.profile=Boundary.for_scene("test1_geometry").overflow
	observations.device={"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"size":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode()}
	observations.samples=[]
	var any_active:=false;var any_stopped:=false;var restored:=false
	for target in [0.0,2.0,4.0,6.0,8.0,10.0,15.0,20.0,25.0,30.0]:
		scene.playing=target>0;start=Time.get_ticks_msec()
		while scene.runtime.current.advanced_time_s<target and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
		scene.playing=false;await _idle()
		check("advanced_"+str(target),scene.runtime.current.advanced_time_s>=target and scene.last_error.is_empty())
		var saved: Dictionary=await _snapshot("time_"+str(target))
		if saved.is_empty():break
		var control: PackedByteArray=saved.native.control
		var row:=_stats(saved);observations.samples.append(row);print("OVERFLOW_SAMPLE ",JSON.stringify(row))
		var active:=control.decode_u32(104)==1
		if any_active and not active:any_stopped=true
		any_active=any_active or active
		check("low_frequency_"+str(target),control.decode_u32(116)<=ceili(saved.advanced_time_s/.5)+1)
		var baseline: float=saved.advanced_time_s
		for frame in 4:await process_frame
		check("paused_clock_"+str(target),scene.runtime.current.advanced_time_s==baseline)
		if active and not restored:
			var paused: Dictionary=await _snapshot("paused")
			check("pause_keeps_water_and_overflow",paused.native.fields.water==saved.native.fields.water and paused.native.control==control)
			check("restore_active_drain",(await scene.restore_gpu_checkpoint(output+"/time_"+str(target)+".sandue")).is_empty())
			start=Time.get_ticks_msec()
			while (not scene.ready_for_ticks or scene._booting or not scene.runtime.retired.is_empty()) and Time.get_ticks_msec()-start<30000:await process_frame
			var after: Dictionary=await _snapshot("restored")
			check("restore_exact_overflow_and_water",after.native.control.slice(104)==control.slice(104) and after.native.fields.water==saved.native.fields.water)
			var broken:=after.duplicate(true);broken.native.control.encode_u32(104,2)
			check("reject_invalid_overflow_state",Codec.validate(broken,scene.configuration)==&"invalid_overflow_control")
			broken=after.duplicate(true);broken.native.control.encode_float(108,NAN)
			check("reject_nonfinite_detection_clock",Codec.validate(broken,scene.configuration)==&"invalid_overflow_control")
			restored=true
		if target in [0.0,6.0,15.0,30.0]:
			scene.hide_hud=true;await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/time_"+str(target)+".png")
	check("high_water_activates_drain",any_active)
	check("low_water_stops_drain",any_stopped)
	check("active_checkpoint_exercised",restored)
	if observations.samples.size()>1:
		check("water_sink_increases",observations.samples[-1].overflow_removed_m3>0 and observations.samples[-1].water_sink_m3>=observations.samples[-1].overflow_removed_m3)
	await _close()

func _snapshot(label: String) -> Dictionary:
	var path:=output+"/"+label+".sandue"
	var error: StringName=await scene.save_gpu_checkpoint(path)
	check(label+"_saved",error.is_empty())
	if not error.is_empty():observations.snapshot_error=String(error);return {}
	var result:=Codec.load(path,scene.configuration)
	check(label+"_valid",result.error.is_empty())
	return result.get("checkpoint",{})

func _stats(saved: Dictionary) -> Dictionary:
	var c: PackedByteArray=saved.native.control
	var water: PackedFloat32Array=saved.native.fields.water.to_float32_array()
	var sand: PackedFloat32Array=saved.native.fields.sand.to_float32_array()
	var rock: PackedFloat32Array=saved.native.fields.rock.to_float32_array()
	var volume:=0.0;var surface:=0.0;var wet:=0;var middle_wet:=0;var shoreline:=0.0
	for z in range(68,188):
		for x in range(8,248):
			var i:=z*256+x;volume+=water[i]*.015625
			if water[i]>.03:
				wet+=1;surface+=rock[i]+sand[i]+water[i]
				if x in [127,128]:middle_wet+=1
	for x in range(8,248):
		var wet_z:=0
		for z in range(68,188):
			if water[z*256+x]>.03:wet_z+=1
		if wet_z>=60:shoreline=(float(x)+.5)*.125-16.0
	return {"time_s":saved.advanced_time_s,"active":c.decode_u32(104),"checks":c.decode_u32(116),"sampled_mean_m":c.decode_float(112),"full_wet_mean_m":surface/maxi(wet,1),"water_volume_m3":volume,"overflow_removed_m3":c.decode_float(120),"water_sink_m3":saved.ledger.water_sink_m3,"outlet_m":c.decode_float(96),"middle_wet_fraction":float(middle_wet)/240.0,"majority_shoreline_x":shoreline}
