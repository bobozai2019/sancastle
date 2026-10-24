extends "res://tests/visual_water_alignment/foam_natural_sequence.gd"

func _data(parameter: StringName) -> PackedFloat32Array:
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var texture: Texture2D=material.get_shader_parameter(parameter)
	return texture.get_image().get_data().to_float32_array()

func _edit(tool: StringName, point: Vector2, amount: float) -> void:
	check(String(tool)+"_begin",scene.input.begin(tool,point,{},amount,3,0.25).accepted)
	check(String(tool)+"_finish",scene.input.finish().accepted)
	await _idle()

func _after_sequence() -> void:
	var owner=scene.runtime.current
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var water:=_data(&"water_state");var foam:=_data(&"foam_state");var sand:=_data(&"sand_state");var rock:=_data(&"rock_state")
	var selected:=-1;var best:=-1.0
	for z in range(72 if scene_key=="test1_geometry" else 8,184 if scene_key=="test1_geometry" else 248):
		for x in range(12,244):
			var i:=z*256+x
			if water[i]>0.003 and water[i]<0.08 and sand[i]>0.03 and foam[i*2]>best:
				best=foam[i*2];selected=i
	check("wet_foam_sand_edit_target",selected>=0 and best>0.03)
	if selected<0:return
	var point:=Vector2((float(selected%256)+0.5)*0.125-16.0,(float(selected/256)+0.5)*0.125-16.0)
	observations.edits={"point_xz":var_to_str(point),"cell":selected,"before":{"water":water[selected],"sand":sand[selected],"rock":rock[selected],"foam":best,"tick":owner.completed_tick,"time_s":owner.advanced_time_s}}
	var clock: float=owner.advanced_time_s
	var tick: int=owner.completed_tick
	await _capture("edit_before")
	await _edit(&"place_sand",point,0.5)
	await _capture("edit_paused_fill")
	water=_data(&"water_state");sand=_data(&"sand_state");foam=_data(&"foam_state")
	observations.edits.paused_fill={"water":water[selected],"sand":sand[selected],"foam":foam[selected*2],"tick":owner.completed_tick,"time_s":owner.advanced_time_s}
	check("paused_fill_raises_bed",sand[selected]>float(observations.edits.before.sand))
	check("paused_fill_creates_dry_sand",water[selected]<=0.001)
	check("paused_fill_keeps_completed_clock",owner.advanced_time_s==clock and owner.completed_tick==tick)
	var camera: Camera3D=scene.get_viewport().get_camera_3d()
	var screen:=camera.unproject_position(Vector3(point.x,rock[selected]+sand[selected],point.y))
	observations.edits.fill_screen=var_to_str(screen)
	var water_gain: Variant=material.get_shader_parameter("natural_main_foam_gain")
	var contact_material: ShaderMaterial=scene.get_node("ShoreContactOverlay").material_override
	var shore_gain: Variant=contact_material.get_shader_parameter("natural_contact_gain")
	material.set_shader_parameter("natural_main_foam_gain",0.0);contact_material.set_shader_parameter("natural_contact_gain",0.0)
	await _capture("edit_paused_fill_foam_off")
	var roi:=Rect2i(Vector2i(screen)-Vector2i(1,1),Vector2i(3,3))
	if Rect2i(Vector2i.ZERO,root.size).encloses(roi):
		var on_image:=Image.load_from_file(output+"/edit_paused_fill.png").get_region(roi)
		var off_image:=Image.load_from_file(output+"/edit_paused_fill_foam_off.png").get_region(roi)
		check("new_dry_sand_center_has_no_floating_foam",on_image.get_data()==off_image.get_data())
	else:check("new_dry_sand_target_visible",false)
	material.set_shader_parameter("natural_main_foam_gain",water_gain);contact_material.set_shader_parameter("natural_contact_gain",shore_gain)
	await _edit(&"remove_sand",point,0.4)
	await _capture("edit_paused_dig")
	sand=_data(&"sand_state");water=_data(&"water_state")
	observations.edits.paused_dig={"water":water[selected],"sand":sand[selected],"tick":owner.completed_tick,"time_s":owner.advanced_time_s}
	check("paused_dig_lowers_bed",sand[selected]<float(observations.edits.paused_fill.sand))
	check("paused_dig_keeps_completed_clock",owner.advanced_time_s==clock and owner.completed_tick==tick)
	scene.playing=true
	var deadline:=Time.get_ticks_msec()+30000
	while owner.completed_tick<tick+6 and Time.get_ticks_msec()<deadline:await process_frame
	check("live_edit_begin",scene.input.begin(&"place_sand",point,{},0.1,3,0.25).accepted)
	scene.input.finish()
	while not scene.input.waiting.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	scene.playing=false
	check("live_fill_props_pause",(await scene._props_hold(true,&"user")).is_empty())
	await _idle()
	check("live_edit_clock_advances",owner.completed_tick>tick and owner.advanced_time_s>clock)
	await _capture("edit_live_fill")
	observations.edits.live_fill={"tick":owner.completed_tick,"time_s":owner.advanced_time_s,"water":_data(&"water_state")[selected],"sand":_data(&"sand_state")[selected],"receipts":scene.input.terminal.duplicate(true)}
	var live_tick: int=owner.completed_tick
	scene.playing=true
	deadline=Time.get_ticks_msec()+30000
	while owner.completed_tick<live_tick+6 and Time.get_ticks_msec()<deadline:await process_frame
	check("live_dig_begin",scene.input.begin(&"remove_sand",point,{},0.2,3,0.25).accepted)
	scene.input.finish()
	while not scene.input.waiting.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	scene.playing=false
	check("live_dig_props_pause",(await scene._props_hold(true,&"user")).is_empty())
	await _idle()
	await _capture("edit_live_dig")
	observations.edits.live_dig={"tick":owner.completed_tick,"time_s":owner.advanced_time_s,"water":_data(&"water_state")[selected],"sand":_data(&"sand_state")[selected],"receipts":scene.input.terminal.duplicate(true)}
	check("live_dig_lowers_bed",float(observations.edits.live_dig.sand)<float(observations.edits.live_fill.sand))
	check("edits_no_runtime_error",scene.last_error.is_empty())
	# No activity in shallow water must not create a permanent white contact ring.
	var old_foam: Variant=material.get_shader_parameter("foam_state")
	var contact: ShaderMaterial=scene.get_node("ShoreContactOverlay").material_override
	var contact_foam: Variant=contact.get_shader_parameter("foam_state")
	var contact_front: Variant=contact.get_shader_parameter("local_front_state")
	var zero:=Image.create(4,4,false,Image.FORMAT_RGF);zero.fill(Color(0,0,0,0))
	var empty:=ImageTexture.create_from_image(zero)
	material.set_shader_parameter("foam_state",empty)
	contact.set_shader_parameter("foam_state",empty);contact.set_shader_parameter("local_front_state",empty)
	await _capture("static_no_activity")
	var gain: Variant=material.get_shader_parameter("natural_main_foam_gain")
	var contact_gain: Variant=contact.get_shader_parameter("natural_contact_gain")
	material.set_shader_parameter("natural_main_foam_gain",0.0);contact.set_shader_parameter("natural_contact_gain",0.0)
	await _capture("static_no_activity_gains_zero")
	check("no_activity_no_permanent_white_ring",FileAccess.get_sha256(output+"/static_no_activity.png")==FileAccess.get_sha256(output+"/static_no_activity_gains_zero.png"))
	material.set_shader_parameter("foam_state",old_foam);material.set_shader_parameter("natural_main_foam_gain",gain)
	contact.set_shader_parameter("foam_state",contact_foam);contact.set_shader_parameter("local_front_state",contact_front);contact.set_shader_parameter("natural_contact_gain",contact_gain)
