extends "res://tests/edit_validation/water_transaction_probe.gd"

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("interaction_queue_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"Godot event dispatch burst and during active transaction; not OS injection or performance"},"\t"))

func _event(world: Vector3, button: bool=false) -> void:
	var p: Vector2=lab.get_viewport().get_final_transform()*lab.get_node("Camera").unproject_position(world)
	if button:
		var e:=InputEventMouseButton.new();e.position=p;e.pressed=true;e.button_index=MOUSE_BUTTON_RIGHT;Input.parse_input_event(e)
	else:
		var e:=InputEventMouseMotion.new();e.position=p;e.button_mask=MOUSE_BUTTON_MASK_RIGHT;Input.parse_input_event(e)

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_interaction_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	await physics_frame;await physics_frame
	Input.use_accumulated_input=false
	_event(Vector3(-1,0.4,0.0625),true)
	for k in range(1,66): _event(Vector3(-1+(k%20)*0.03,0.4,0.0625))
	var accepted:=0;var full:=0
	for event in lab.input_events:
		if event.admission_error.is_empty(): accepted+=1
		elif event.admission_error=="backend_unavailable": full+=1
	var burst: bool=accepted==64 and full==2 and lab.input_scheduler.max_pending==64
	var deadline:=Time.get_ticks_msec()+3000
	while not (lab.busy and lab.receipt.is_empty()) and Time.get_ticks_msec()<deadline: await process_frame
	var before: int=lab.input_events.size()
	_event(Vector3(1,0.4,0.0625))
	var while_busy: bool=lab.input_events.size()==before+1 and lab.input_events[-1].busy_at_capture and lab.input_events[-1].admission_error.is_empty()
	while lab.input_running and lab.last_error.is_empty(): await process_frame
	var once: bool=lab.input_results.size()==65 and lab.input_scheduler.terminal.size()==65 and lab.command_queue.applied_log.size()==65
	for item in lab.input_results: once=once and item.receipt.get("status")==1
	var state: Dictionary=await _snapshot("queued_final")
	var sand: PackedFloat32Array=state.sand.to_float32_array()
	var rock: PackedFloat32Array=state.rock.to_float32_array()
	var maximum:=0.0
	for chunk in lab.collision_proxy.shapes:
		var values: PackedFloat32Array=lab.collision_proxy.shapes[chunk].shape.map_data
		for z in 33:
			for x in 33:
				var index: int=mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)
				maximum=maxf(maximum,absf(values[z*33+x]-sand[index]-rock[index]))
	var ok: bool=burst and while_busy and once and maximum<=1e-6 and lab.input_scheduler.reserved_total()==0.0 and lab.last_error.is_empty()
	rows.append({"pass":ok,"burst64":burst,"full_rejections":full,"accepted_during_busy":while_busy,"exactly_once":once,"shape_error_m":maximum,"stock":lab.domain.tool_inventory_m3,"input_events":lab.input_events,"collision_rejections":lab.input_rejections,"terminal":lab.input_scheduler.terminal})
	_write(ok);await lab.shutdown();lab.queue_free();finished=true
	print("INTERACTION_QUEUE_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)
