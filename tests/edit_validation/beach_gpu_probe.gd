extends "res://tests/edit_validation/beach_scene_probe.gd"

var finished := false
var visual_bytes := {}
var collision_diagnostics := []
var close_result := {}

func _init() -> void:
	super._init();call_deferred("_watchdog")

func _watchdog() -> void:
	var started:=Time.get_ticks_msec()
	while not finished:
		if Time.get_ticks_msec()-started>150000: _error("beach GPU timeout");_write();quit(1);return
		await process_frame

func _write() -> void:
	var file:=FileAccess.open(output.path_join("beach_gpu_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"collision_diagnostics":collision_diagnostics,"events":preview.gpu_events if preview!=null else [],"scope":"full original beach load, four native edit policies and dirty-neighbor collision; input and recovery integration pending"},"\t"))

func _read_visual() -> void:
	for item in [["sand",preview.solver.published_sand],["water",preview.solver.published_water],["momentum_x",preview.stable_q.momentum_x],["momentum_z",preview.stable_q.momentum_z]]:
		preview.solver.rd.texture_get_data_async(item[1],0,_visual_data.bind(item[0]))

func _visual_data(bytes: PackedByteArray, key: String) -> void: call_deferred("_visual_record",bytes,key)
func _visual_record(bytes: PackedByteArray, key: String) -> void: visual_bytes[key]=bytes

func _published_exact(state: Dictionary) -> bool:
	visual_bytes.clear();RenderingServer.call_on_render_thread(_read_visual)
	while visual_bytes.size()<4: await process_frame
	for key in visual_bytes:
		var file:=FileAccess.open(output.path_join("published_"+str(checks.size())+"_"+key+".bin"),FileAccess.WRITE);file.store_buffer(visual_bytes[key])
		if visual_bytes[key]!=state[key]: return false
	return true

func _chunks_exact(state: Dictionary) -> bool:
	var sand: PackedFloat32Array=state.sand.to_float32_array();var rock: PackedFloat32Array=state.rock.to_float32_array()
	for chunk in preview.collision_needed:
		if not preview.collision_proxy.shapes.has(chunk): return false
		var values: PackedFloat32Array=preview.collision_proxy.shapes[chunk].shape.map_data
		var expected:=PackedFloat32Array();expected.resize(33*33)
		var double_difference := 0.0
		for z in 33:
			for x in 33:
				var index: int=mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)
				expected[z*33+x]=sand[index]+rock[index]
				double_difference=maxf(double_difference,absf(values[z*33+x]-(sand[index]+rock[index])))
		var exact: bool=values.to_byte_array()==expected.to_byte_array()
		collision_diagnostics.append({"chunk":chunk,"float32_bytes_exact":exact,"maximum_vs_unrounded_float64":double_difference,"revision":preview.collision_proxy.applied_revisions[chunk]})
		var file:=FileAccess.open(output.path_join("collision_%d_%d.bin" % [checks.size(),chunk]),FileAccess.WRITE);file.store_buffer(values.to_byte_array())
		if not exact: return false
	return true

func _ticks(count: int) -> void:
	for i in count:
		preview._start_tick()
		while preview.tick_pending and preview.last_error.is_empty(): await process_frame

func _closing_command(command: Dictionary) -> void: close_result=await preview.apply_gpu_command(command)

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_gpu_lab.tscn").instantiate();preview.playing=false
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): _error(preview.last_error);_write();finished=true;quit(1);return
	await _ticks(15)
	var state: Dictionary=await _snapshot("before_edit")
	var sand: PackedFloat32Array=state.sand.to_float32_array();var water: PackedFloat32Array=state.water.to_float32_array()
	var chosen := -1
	for i in sand.size():
		if sand[i]>0.1 and water[i]>0.005 and i%256>8 and i%256<247 and i/256>8 and i/256<247: chosen=i;break
	if chosen<0: _error("no natural wet sand test point");_write();finished=true;quit(1);return
	var position:=Vector3((chosen%256+0.5)*0.125-16,0,(chosen/256+0.5)*0.125-16)
	for policy in [0,1,2,3]:
		preview.water_policy=policy;preview.signed_speed_m_s=0.25 if policy>=2 else 0.0
		var command: Dictionary={"domain_id":preview.shadow_domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":preview.command_queue.last_command_id+1,"kind":&"remove_sand" if policy%2==0 else &"place_sand","shape":&"circle","transform":{"position_m":position},"radius_m":0.75,"strength":1.0,"amount_m3":0.005,"seed":101}
		var stock: float=preview.shadow_domain.tool_inventory_m3
		var result: Dictionary=await preview.apply_gpu_command(command)
		state=await _snapshot("policy_%d" % policy)
		var delta: float=result.get("actual_sand_m3",0.0)*(1.0 if command.kind==&"remove_sand" else -1.0)
		var exact: bool=await _published_exact(state)
		_check("full_beach_native_policy_%d" % policy,result.get("status")==1 and preview.shadow_domain.tool_inventory_m3==stock+delta and exact and _chunks_exact(state),{"receipt":result,"position":position,"published_exact":exact,"collision_chunks":Array(preview.collision_needed.keys())})
		await _ticks(2)
		state=await _snapshot("continued_policy_%d" % policy)
		_check("full_beach_edit_then_coupled_ticks_%d" % policy,preview.last_error.is_empty() and await _published_exact(state),{"tick":preview.completed_ticks})
	_check("full_beach_load_preserved",preview.enable_erosion and preview.sediment_coupler!=null and preview.material_coupler!=null and preview.foam_field!=null and preview.local_front_field!=null and preview.wave_requests.size()==80 and preview.completed_ticks==23)
	_check("unserialized_prefix_save_rejected",preview.request_checkpoint_save(output.path_join("unsupported.scp"))==&"gpu_beach_prefix_not_serialized" and not FileAccess.file_exists(output.path_join("unsupported.scp")))
	var invalid: Dictionary={"domain_id":preview.shadow_domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":preview.command_queue.last_command_id+1,"kind":&"remove_sand","shape":&"circle","transform":{"position_m":position},"radius_m":0.75,"strength":1.0,"amount_m3":0.005,"seed":101}
	var id_before: int=preview.command_queue.last_command_id
	preview.signed_speed_m_s=1.1
	var invalid_result: Dictionary=await preview.apply_gpu_command(invalid)
	_check("invalid_speed_no_admission",invalid_result.get("error")=="invalid_command" and preview.command_queue.last_command_id==id_before)
	preview.signed_speed_m_s=0.25
	await process_frame;root.get_texture().get_image().save_png(output.path_join("edited_beach.png"))
	call_deferred("_closing_command",invalid)
	while not preview.gpu_busy: await process_frame
	var ticks_before: int=preview.completed_ticks
	preview._start_tick()
	var denied: Dictionary=await preview.apply_gpu_command(invalid)
	_check("active_gpu_blocks_tick_and_admission",preview.completed_ticks==ticks_before and denied.get("error")=="backend_unavailable" and preview.request_checkpoint_save(output.path_join("busy.scp"))==&"save_busy")
	var owned_solver=preview.solver
	var actual_pending: bool=owned_solver.receipt_pending
	await preview.shutdown()
	while close_result.is_empty(): await process_frame
	_check("full_beach_close_finishes_actual_receipt",actual_pending and close_result.get("status")==1 and preview.gpu_release_done and owned_solver.rd==null and preview.collision_proxy.rd==null and preview.gpu_release_us>=owned_solver.receipt_callback_us and preview.gpu_prefix.size()==5,{"receipt":close_result,"release_us":preview.gpu_release_us,"receipt_callback_us":owned_solver.receipt_callback_us})
	for item in checks: failed=failed or not item.pass
	failed=failed or not preview.last_error.is_empty()
	_write();preview.queue_free();for i in 8: await process_frame
	finished=true;print("BEACH_GPU_COMPLETE pass=%s" % str(not failed));quit(1 if failed else 0)
