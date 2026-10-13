extends "res://tests/water_material_natural/capture.gd"

func _hash_state() -> Dictionary:
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("sequence readback timeout");return {}
	var result:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		result[name]=ctx.finish().hex_encode()
	return result

func _lighting_sweep(_before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var fine:ShaderMaterial=preview.get_node("PrototypeFrontFoamDense").material_override
	var contact:ShaderMaterial=preview.get_node("ShoreContactOverlay").material_override
	var frames:=[]
	var hashes:={}
	var deadline:=Time.get_ticks_msec()+600000
	for tick in range(target_tick,target_tick+361,3):
		preview.replay_target_tick=tick
		preview.replay_ready=false
		while not preview.replay_ready:
			await process_frame
			if not preview.last_error.is_empty() or Time.get_ticks_msec()>deadline:
				_fail("foam sequence completion timeout: "+preview.last_error);return
		if preview.completed_ticks!=tick or preview.tick_pending or not is_equal_approx(preview.visual_time_s,float(tick)/30.):
			_fail("foam sequence clock/completed state mismatch");return
		preview.set_fixture_camera(&"close")
		var before:={}
		if tick in [target_tick,target_tick+180,target_tick+360]:before=await _hash_state()
		var images:={}
		for mode in ["all_on","all_off"]:
			water.set_shader_parameter("natural_main_foam_gain",1. if mode=="all_on" else 0.)
			fine.set_shader_parameter("natural_fine_enabled",mode=="all_on")
			contact.set_shader_parameter("natural_contact_enabled",mode=="all_on")
			for i in range(3):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%04d.png"%[mode,tick]
			root.get_texture().get_image().save_png(path)
			images[mode]={"path":path,"sha256":FileAccess.get_sha256(path)}
		if not before.is_empty():
			var after:=await _hash_state()
			if before!=after:_fail("foam sequence visual controls changed authority");return
			hashes[str(tick)]={"before":before,"after":after,"unchanged":true}
		frames.append({"tick":tick,"time_s":preview.visual_time_s,"generation":preview.generation,
			"revision":preview.solver.state_revision,"images":images,"effective_foam":preview.effective_foam})
	var file:=FileAccess.open(output+"/foam_sequence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":frames,"authority_pairs":hashes,"workload":preview.staging_wave_workload,
		"wave_request_count":preview.wave_requests.size(),"camera":"close","viewport_px":root.size,
		"timebase":"completed_tick/30, sampled every 3 ticks; offline sequence, not realtime throughput",
		"new_visual_history":false},"\t"));file.close()
