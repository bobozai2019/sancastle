extends "res://tools/water_foam/g0_timing.gd"

# Diagnostic only: VSYNC_DISABLED cases are never release cost acceptance.
func run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.content_scale_size=Vector2i(1280,720)
	beach=load(scene_path).instantiate();beach.playing=false;root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error("DIAGNOSTIC_BOOT");quit(1);return
	var owner=beach.runtime.current
	while owner.completed_tick<240:
		if not owner.request_tick(1.0/30.0).is_empty():quit(1);return
		while owner.pending_count()!=0 or owner.active_count()!=0:await process_frame
	var service=root.get_node("Parameters")
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var water: ShaderMaterial=beach.get_node("GpuWaterSurface").material_override
	var final_shader: Shader=water.shader
	var original: Shader=load("res://task/water_foam_visual/验收/G4/before_integration/assets/water_material_natural_candidate/async_rdc_water.gdshader")
	var values:={}
	for u in final_shader.get_shader_uniform_list():values[u.name]=water.get_shader_parameter(u.name)
	var contact: ShaderMaterial=beach.get_node("ShoreContactOverlay").material_override
	var metadata:={"scope":"Frozen frame pacing attribution only, 10s warm/10s sample. VSync-off cases are diagnostic, never C05 acceptance.","engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"intervals":[],"tick":owner.completed_tick,"time_s":owner.advanced_time_s}
	for item in [["old_on",false,1],["new_on",true,1],["new_off",true,0],["old_off",false,0]]:
		water.shader=final_shader if item[1] else original
		for u in water.shader.get_shader_uniform_list():
			if values.has(u.name):water.set_shader_parameter(u.name,values[u.name])
		contact.set_shader_parameter("natural_contact_gain",0.55 if item[1] else 1.0)
		DisplayServer.window_set_vsync_mode(item[2])
		await create_timer(10.0).timeout
		phase=item[0];previous_us=Time.get_ticks_usec()
		var start:=previous_us
		await create_timer(10.0).timeout
		metadata.intervals.append({"phase":phase,"wall_s":(Time.get_ticks_usec()-start)/1000000.0,"vsync":DisplayServer.window_get_vsync_mode(),"shader_sha256":water.shader.code.sha256_text(),"end_tick":owner.completed_tick,"end_time_s":owner.advanced_time_s})
		phase=""
		print("PACING_DIAGNOSTIC ",item[0])
	metadata.error=beach.last_error
	FileAccess.open(output+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify({"metadata":metadata,"frames":rows}))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	await beach.shutdown();quit()
