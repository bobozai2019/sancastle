extends "res://tests/edit_validation/beach_gpu_probe.gd"

var rows := []

func _write() -> void:
	var file:=FileAccess.open(output.path_join("beach_collision_bounds_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"rows":rows,"checks":checks,
		"scope":"actual sand delta independent all64 heightmap coverage; interior/shared edges/domain edges across four policies"},"\t"))

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_interaction_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): _error(preview.last_error);_write();finished=true;quit(1);return
	await _ticks(15)
	while preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty(): await process_frame
	await physics_frame;await physics_frame
	preview.domain.tool_inventory_m3=0.5
	var serial:=0
	for selected_policy in [0,1,2,3]:
		for point in [Vector3(-2.0625,0,-0.0625),Vector3(-0.0625,0,-0.0625),Vector3(-15.9375,0,-15.9375),Vector3(15.9375,0,15.9375)]:
			serial+=1
			var before: Dictionary=await _snapshot("before_%d"%serial)
			var old_shapes: Dictionary={}
			for chunk in 64: old_shapes[chunk]=preview.collision_proxy.shapes[chunk].shape.map_data.to_byte_array()
			preview.water_policy=selected_policy;preview.signed_speed_m_s=0.25 if selected_policy>=2 else 0.0
			var command: Dictionary={"domain_id":preview.domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,
				"command_id":serial,"kind":&"place_sand","shape":&"circle","transform":{"position_m":point},"radius_m":0.3,
				"strength":1.0,"amount_m3":0.001,"seed":101}
			var receipt: Dictionary=await preview.apply_gpu_command(command)
			var after: Dictionary=await _snapshot("after_%d"%serial)
			var old_sand: PackedFloat32Array=before.sand.to_float32_array()
			var new_sand: PackedFloat32Array=after.sand.to_float32_array()
			var rock: PackedFloat32Array=after.rock.to_float32_array()
			var changed:=[]
			for i in old_sand.size():
				if old_sand[i]!=new_sand[i]: changed.append(Vector2i(i%256,i/256))
			var selected: PackedInt32Array=preview._gpu_chunks(receipt)
			var expected:=PackedInt32Array()
			var missing:=false
			var selected_exact:=true
			var unrelated_unchanged:=true
			for chunk in 64:
				var bx: int=(chunk%8)*32
				var bz: int=(chunk/8)*32
				var touched:=false
				for cell in changed:
					touched=touched or (cell.x>=bx and cell.x<=mini(bx+32,255) and cell.y>=bz and cell.y<=mini(bz+32,255))
				if touched: expected.append(chunk);missing=missing or chunk not in selected
				var actual: PackedFloat32Array=preview.collision_proxy.shapes[chunk].shape.map_data
				if chunk in selected:
					var heights:=PackedFloat32Array();heights.resize(1089)
					for z in 33:
						for x in 33:
							var i: int=mini(bz+z,255)*256+mini(bx+x,255)
							heights[z*33+x]=new_sand[i]+rock[i]
					selected_exact=selected_exact and heights.to_byte_array()==actual.to_byte_array()
				else: unrelated_unchanged=unrelated_unchanged and actual.to_byte_array()==old_shapes[chunk]
			var ok: bool=receipt.get("status")==1 and not changed.is_empty() and not missing and selected_exact and unrelated_unchanged and preview.last_error.is_empty()
			rows.append({"policy":selected_policy,"point":point,"changed_cells":changed.size(),"expected_touched":expected,"selected":selected,
				"missing":missing,"selected_exact":selected_exact,"unrelated_unchanged":unrelated_unchanged,"pass":ok})
			_check("actual_delta_all64_policy%d_case%d"%[selected_policy,serial],ok,rows[-1])
			failed=failed or not ok
	await preview.shutdown();_write();preview.queue_free();finished=true;print("BEACH_COLLISION_BOUNDS_COMPLETE pass=",not failed);quit(1 if failed else 0)
