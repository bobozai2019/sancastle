extends "res://tests/integration/unified_edit_playable_probe.gd"

func _wait_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.scene_key+"_ready",not scene._booting and scene.ready_for_ticks and scene.last_error.is_empty())
	return not scene._booting and scene.ready_for_ticks and scene.last_error.is_empty()

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	var hub=root.get_node("BeachScenes")
	hub.session_directory=output+"/sessions";DirAccess.make_dir_recursive_absolute(hub.session_directory)
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene);current_scene=scene
	if not await _wait_ready():await _close();return
	for key in ["main","test1_geometry"]:
		if key!="main":
			check("switch_to_geometry",hub.request_switch(key))
			var deadline:=Time.get_ticks_msec()+180000
			while hub.busy and Time.get_ticks_msec()<deadline:await process_frame
			scene=hub.active_scene
			check("switch_settled",not hub.busy and hub.last_error.is_empty() and scene.scene_key==key)
			print("PARITY_SWITCH ",hub.last_error," ",hub.message)
			if scene.scene_key!=key:await _close();return
			if not await _wait_ready():await _close();return
		await _exercise(key)
	var geometry=scene
	check("return_to_main",hub.request_switch("main"))
	var deadline:=Time.get_ticks_msec()+180000
	while hub.busy and Time.get_ticks_msec()<deadline:await process_frame
	scene=hub.active_scene
	check("return_releases_geometry",not is_instance_valid(geometry) and scene.scene_key=="main" and hub.last_error.is_empty())
	if await _wait_ready():check("return_props_active",scene.floating_props.active and scene.floating_props.last_error.is_empty())
	observations.releases=hub.release_records.duplicate(true)
	await _close()

func _exercise(key: String) -> void:
	var props=scene.floating_props
	check(key+"_props_present",props!=null and scene.props_panel!=null and scene.props_panel.is_visible_in_tree())
	if props==null:return
	check(key+"_props_active",props.active and props.registry.size()==3 and props.last_error.is_empty())
	scene.props_panel.get_node("Margin/Rows/Slots/Slot1").pressed.emit()
	check(key+"_prop_ui_select",scene.props_panel.selected_body_id==1)
	var pickup: Dictionary=await props.manipulate_body(1,Vector2.ZERO,0.0,true)
	check(key+"_prop_pickup",pickup.error.is_empty() and props.body_for_id(1).in_inventory)
	var place: Dictionary=await props.manipulate_body(1,Vector2(4,3),0.0,false)
	check(key+"_prop_place",place.error.is_empty() and not props.body_for_id(1).in_inventory)
	if key=="test1_geometry":check("geometry_prop_bounds",props.placement_error(1,Vector2(0,9))==&"out_of_domain")
	scene.panel.get_node("Margin/Controls/Tools/Castle").pressed.emit()
	check(key+"_castle_button_cancels_props",scene.selected_sand_tool==&"castle_v1" and not scene.props_panel.has_world_mode())
	for frame in 6:await physics_frame
	var hit: Dictionary={};var screen:=Vector2.ZERO
	for y in range(220,560,35):
		for x in range(350,850,35):
			var candidate: Dictionary=scene.pick(Vector2(x,y))
			if not candidate.is_empty() and candidate.position.y>0.8 and absf(candidate.position.x)<10 and absf(candidate.position.z)<4:
				hit=candidate;screen=Vector2(x,y);break
		if not hit.is_empty():break
	check(key+"_raised_bed_pick",not hit.is_empty())
	if hit.is_empty():return
	var point:=Vector2(hit.position.x,hit.position.z)
	if key=="test1_geometry":
		check("old_zero_datum_admitted",scene.input.begin(&"castle_v1",point,scene.tool_parameters(),0.1,scene.water_policy,scene.signed_speed_m_s).accepted)
		scene.input.finish();await _idle()
		var unchanged:=false
		for receipt in scene.input.terminal:
			if receipt.profile_version==2:unchanged=receipt.outcome==L.Outcome.NO_CHANGE
		check("old_zero_datum_buried",unchanged)
	root.grab_focus()
	for frame in 3:await process_frame
	check(key+"_window_focused",root.has_focus())
	var motion:=InputEventMouseMotion.new();motion.position=screen
	scene._unhandled_input(motion)
	var descriptor: Dictionary=scene._preview_descriptor()
	check(key+"_preview_uses_picked_bed",descriptor.error.is_empty() and is_equal_approx(descriptor.geometry.parameters.datum_y_m,hit.position.y))
	var intent=preload("res://scripts/simulation/unified_edit/intent.gd")
	var protocol=preload("res://scripts/simulation/unified_edit/protocol.gd")
	var frozen: Dictionary=intent.freeze(scene.registry,descriptor.request,scene._domain_id(),scene.generation)
	var wire: PackedByteArray=protocol.encode_command(frozen.value,scene.registry)
	check(key+"_datum_wire_roundtrip",protocol.decode_command(wire).error.is_empty())
	wire.encode_float(L.COMMAND_F32.datum_y_m,17.0)
	check(key+"_invalid_datum_wire_rejected",protocol.decode_command(wire).error==&"command_parameters")
	var before: int=scene.preview_received_count
	var deadline:=Time.get_ticks_msec()+15000
	while scene.preview_received_count==before and Time.get_ticks_msec()<deadline:await process_frame
	check(key+"_preview_base_matches",scene.preview_received_count>before and absf(scene.preview_result.base-hit.position.y)<0.01)
	scene.input.terminal.clear()
	var click:=InputEventMouseButton.new();click.position=screen;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	scene._unhandled_input(click);scene._finish_ui_stroke(false)
	for frame in 8:await process_frame
	print("PARITY_EDIT ",key," error=",scene.last_error," message=",scene.action_message," fault=",scene.runtime.current.fault_reason()," pending=",scene.runtime.current.pending_count()," waiting=",scene.input.waiting)
	await _idle()
	var applied:=false
	for receipt in scene.input.terminal:
		if receipt.profile_version==2 and receipt.outcome==L.Outcome.APPLIED and receipt.changed_cells>0:applied=true
	check(key+"_mouse_castle_applied",applied)
	var profile: Dictionary=scene.registry.profile(&"castle_v1")
	check(key+"_datum_range_rejected",not scene.registry.resolve(&"castle_v1",profile.version,profile.profile_hash,{"datum_y_m":17.0}).error.is_empty())
	observations[key]={"position":hit.position,"preview":scene.preview_result.duplicate(true),"receipts":scene.input.terminal.duplicate(true),"sources":scene.configuration.sources.duplicate(true)}
	scene.playing=true;deadline=Time.get_ticks_msec()+30000
	while scene.runtime.current.completed_tick<3 and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	scene.playing=false;await _idle()
	check(key+"_short_live_run",scene.runtime.current.completed_tick>=3 and scene.last_error.is_empty() and props.last_error.is_empty())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/"+key+".png")
