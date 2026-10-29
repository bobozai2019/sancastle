extends "res://tests/edit_validation/beach_gpu_probe.gd"

func _write() -> void:
	var file:=FileAccess.open(output.path_join("beach_interaction_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"input_events":preview.input_events if preview!=null else [],"terminal":preview.input_results if preview!=null else [],"scope":"full beach Godot mouse event and PhysicsRay queue burst; no OS input or performance acceptance"},"\t"))

func _event(world: Vector3, button := false) -> void:
	var position: Vector2=preview.get_viewport().get_final_transform()*preview.get_viewport().get_camera_3d().unproject_position(world)
	if button:
		var event:=InputEventMouseButton.new();event.position=position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;Input.parse_input_event(event)
	else:
		var event:=InputEventMouseMotion.new();event.position=position;event.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(event)

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_interaction_lab.tscn").instantiate();preview.playing=false
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	await _ticks(15)
	while preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty(): await process_frame
	await physics_frame;await physics_frame
	var before: Dictionary=await _snapshot("before_ui")
	var sand: PackedFloat32Array=before.sand.to_float32_array();var rock: PackedFloat32Array=before.rock.to_float32_array()
	var points:=[]
	for z in range(32,224,8):
		for x in range(32,224,8):
			var index: int=z*256+x
			if sand[index]<0.4: continue
			var p:=Vector3((x+0.5)*0.125-16,rock[index]+sand[index],(z+0.5)*0.125-16)
			var screen: Vector2=preview.get_viewport().get_camera_3d().unproject_position(p)
			if not preview.get_viewport().get_visible_rect().has_point(screen): continue
			var hit: Dictionary=preview.pick(screen)
			if not hit.is_empty() and preview._pick_current(hit) and Vector2(hit.position.x,hit.position.z).distance_to(Vector2(p.x,p.z))<0.001: points.append(p)
	if points.size()<68: _error("insufficient visible real terrain points");_write();finished=true;quit(1);return
	Input.use_accumulated_input=false;preview.water_policy=0
	_event(points[0],true)
	for i in range(1,66): _event(points[i])
	# Count actual admitted/rejected intents reaching the terrain controller;
	# Events without an eligible terrain drag intent do not fill the queue.
	var additional := 66
	while preview.input_events.size()<66 and additional<points.size():
		_event(points[additional]);additional+=1
	var accepted := 0;var full := 0
	for event in preview.input_events:
		if event.admission_error.is_empty(): accepted+=1
		elif event.admission_error=="backend_unavailable": full+=1
	_check("full_scene_ui_pending64_capacity",accepted==64 and full==2 and preview.input_scheduler.max_pending==64,{"accepted":accepted,"capacity_rejections":full,"mouse_events_sent":additional})
	while not preview.gpu_busy and preview.last_error.is_empty(): await process_frame
	# A distant, currently acknowledged collision chunk remains eligible while
	# the first transaction is in flight. Admission freezes its current policy.
	preview.water_policy=3;preview.signed_speed_m_s=0.25
	var prior: int=preview.input_events.size()
	_event(points[-1])
	_check("full_scene_ui_accepts_during_actual_gpu_work",preview.input_events.size()==prior+1 and preview.input_events[-1].busy_at_capture and preview.input_events[-1].admission_error.is_empty())
	while preview.input_running and preview.last_error.is_empty(): await process_frame
	var once: bool=preview.input_results.size()==65 and preview.gpu_prefix.size()==65 and preview.command_queue.applied_log.size()==65
	var identities:= {}
	for item in preview.input_results:
		once=once and item.result.get("status")==1 and not identities.has(item.command.command_id)
		identities[item.command.command_id]=true
	var configurations:=true
	for i in preview.gpu_prefix.size(): configurations=configurations and preview.gpu_prefix[i].policy==(3 if i==64 else 0)
	_check("full_scene_ui_exactly_once_policy_and_reservation",once and configurations and preview.input_scheduler.reserved_total()==0.0 and preview.command_queue.pending.is_empty(),{"terminal":preview.input_results.size(),"prefix":preview.gpu_prefix.size(),"stock":preview.domain.tool_inventory_m3})
	var state: Dictionary=await _snapshot("ui_complete")
	_check("full_scene_ui_completed_publication_and_collision",await _published_exact(state) and _chunks_exact(state))
	var events_before: int=preview.input_events.size()
	var highwater_before: int=preview.command_queue.last_command_id
	var background:=InputEventMouseButton.new();background.button_index=MOUSE_BUTTON_LEFT;background.pressed=true;background.position=Vector2(-10000,-10000);Input.parse_input_event(background)
	var no_edit: Dictionary=await _snapshot("background_no_edit")
	var unchanged:=true
	for field in state: unchanged=unchanged and state[field]==no_edit[field]
	_check("full_scene_background_no_command_or_state_change",unchanged and preview.input_events.size()==events_before and preview.command_queue.last_command_id==highwater_before)
	var reservation: Dictionary=preview.input_events[0].command.duplicate(true)
	reservation.kind=&"place_sand";reservation.amount_m3=preview.domain.tool_inventory_m3*0.4
	var reservation_errors:=[]
	for i in 3:
		reservation.command_id=preview.command_queue.last_command_id+1
		reservation_errors.append(String(preview.input_scheduler.submit(reservation.duplicate(true),0,0.0)))
	var reserved: float=preview.input_scheduler.reserved_total()
	var preserved_id: int=preview.command_queue.last_command_id
	preview.input_scheduler.cancel_pending("reservation_probe_cancel")
	_check("full_scene_stock_aggregate_reservation_and_cancel",reservation_errors==["","","insufficient_inventory"] and reserved==2.0*reservation.amount_m3 and preserved_id==highwater_before+2 and preview.input_scheduler.reserved_total()==0.0 and preview.command_queue.pending.is_empty() and preview.domain.tool_inventory_m3==preview.input_results[-1].stock,{"errors":reservation_errors,"reserved_m3":reserved,"stock":preview.domain.tool_inventory_m3})
	await _ticks(3)
	state=await _snapshot("ui_then_ticks")
	_check("full_scene_ui_then_full_load_ticks",preview.completed_ticks==18 and preview.last_error.is_empty() and await _published_exact(state))
	for item in checks: failed=failed or not item.pass
	failed=failed or not preview.last_error.is_empty()
	await process_frame;root.get_texture().get_image().save_png(output.path_join("ui_beach.png"))
	await preview.shutdown();_write();preview.queue_free();for i in 8: await process_frame
	finished=true;print("BEACH_INTERACTION_COMPLETE pass=%s" % str(not failed));quit(1 if failed else 0)
