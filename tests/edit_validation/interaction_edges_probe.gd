extends "res://tests/edit_validation/water_transaction_probe.gd"

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("interaction_edges_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"wide static camera, engine event and physics ray, clipped edges and chunk seams; B policy"},"\t"))

func _click(world: Vector3) -> void:
	var p: Vector2=lab.get_viewport().get_final_transform()*lab.get_node("Camera").unproject_position(world)
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_RIGHT;release.position=p;release.pressed=false;Input.parse_input_event(release)
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_RIGHT;e.pressed=true;e.position=p;Input.parse_input_event(e)

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_interaction_wide_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.water_policy=0
	await physics_frame;await physics_frame
	var points: Array[Vector2i]=[Vector2i(1,1),Vector2i(254,1),Vector2i(1,254),Vector2i(254,254),Vector2i(31,127),Vector2i(32,127),Vector2i(127,31),Vector2i(127,32)]
	for point in points:
		var prefix: String="%d_%d" % [point.x,point.y]
		var before: Dictionary=await _snapshot(prefix+"_before")
		var bs: PackedFloat32Array=before.sand.to_float32_array();var br: PackedFloat32Array=before.rock.to_float32_array()
		var index: int=point.y*256+point.x
		var world:=Vector3((point.x+0.5)*0.125-16,bs[index]+br[index],(point.y+0.5)*0.125-16)
		var count: int=lab.input_results.size()
		_click(world)
		var deadline:=Time.get_ticks_msec()+3000
		while lab.input_results.size()==count and Time.get_ticks_msec()<deadline and lab.last_error.is_empty(): await process_frame
		if lab.input_results.size()==count:
			rows.append({"failed_cell":prefix,"screen":lab.get_node("Camera").unproject_position(world),"hit":lab.pick(lab.get_node("Camera").unproject_position(world)),"events":lab.input_events,"rejections":lab.input_rejections,"input_mapping":lab.last_input_mapping})
			_write(false,"edge event not completed "+prefix);finished=true;quit(1);return
		var after: Dictionary=await _snapshot(prefix+"_after")
		var sand: PackedFloat32Array=after.sand.to_float32_array();var rock: PackedFloat32Array=after.rock.to_float32_array()
		var query:=PhysicsRayQueryParameters3D.create(Vector3(world.x,10,world.z),Vector3(world.x,-10,world.z))
		var hit: Dictionary=lab.get_world_3d().direct_space_state.intersect_ray(query)
		var ray_error: float=INF if hit.is_empty() else absf(hit.position.y-sand[index]-rock[index])
		var maximum:=0.0
		for chunk in lab.collision_proxy.shapes:
			var values: PackedFloat32Array=lab.collision_proxy.shapes[chunk].shape.map_data
			for z in 33:
				for x in 33:
					var i: int=mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)
					maximum=maxf(maximum,absf(values[z*33+x]-sand[i]-rock[i]))
		var outcome: Dictionary=lab.input_results[-1]
		var actual: Vector3=lab.input_events[-1].command.transform.position_m
		var pick_error:=Vector2(actual.x-world.x,actual.z-world.z).length()
		var affected: bool=sand[index]>bs[index]
		var shape_us:=0
		for chunk in outcome.collision_chunks: shape_us=maxi(shape_us,int(lab.collision_proxy.applied_usec[chunk]))
		var delay: float=(shape_us-lab.input_events[-1].input_us)/1000.0
		var ok: bool=outcome.receipt.get("status")==1 and ray_error<=1e-5 and maximum<=1e-6 and delay<=100.0 and pick_error<=0.0002 and affected
		rows.append({"pass":ok,"cell":[point.x,point.y],"ray_error_m":ray_error,"shape_error_m":maximum,"feedback_ms":delay,"pick_error_xz_m":pick_error,"target_cell_affected":affected,"receipt":outcome.receipt})
		_write(false,"running")
	var count: int=lab.input_events.size();var stock: float=lab.domain.tool_inventory_m3
	var before_miss: Dictionary=await _snapshot("miss_before")
	_click(Vector3(18,0.4,0))
	await process_frame;await process_frame
	var after_miss: Dictionary=await _snapshot("miss_after")
	var unchanged: bool=lab.input_events.size()==count and lab.domain.tool_inventory_m3==stock and lab.active_brush==&""
	for key in before_miss:
		if key!="water_receipt": unchanged=unchanged and before_miss[key]==after_miss[key]
	rows.append({"case":"background_miss","pass":unchanged})
	var ok:=rows.size()==9
	for row in rows: ok=ok and row.pass
	_write(ok);await lab.shutdown();lab.queue_free();finished=true;print("INTERACTION_EDGES_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

