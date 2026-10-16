extends "res://tests/shape_brushes/checkpoint_v4_probe.gd"
var repack_done:=false
func repack(chunks:PackedInt32Array,old:bool=false) -> void:
	var ok:bool=preview.collision_proxy.request_chunks_render(chunks,preview.solver.state_revision,preview.generation-1 if old else preview.generation)
	call_deferred("repack_result",ok,old)
func repack_result(ok:bool,old:bool) -> void:_check("old_collision_rejected" if old else "repack_admitted",not ok if old else ok);repack_done=true
func wait_collision() -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while (preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty() or preview.collision_proxy.has_prepare_in_flight()) and Time.get_ticks_msec()<deadline:await process_frame
	await physics_frame;await physics_frame
func verify_shapes(state:Dictionary) -> void:
	var rock:PackedFloat32Array=state.rock.to_float32_array();var sand:PackedFloat32Array=state.sand.to_float32_array();var good:=true
	for chunk in preview.collision_needed:
		var expected:=PackedFloat32Array()
		for z in 33:
			for x in 33:
				var row:int=mini((chunk/8)*32+z,255);var col:int=mini((chunk%8)*32+x,255);expected.append(rock[row*256+col]+sand[row*256+col])
		good=good and preview.collision_proxy.shapes.has(chunk) and preview.collision_proxy.shapes[chunk].shape.map_data==expected and int(preview.collision_proxy.applied_revisions.get(chunk,-1))>=int(preview.collision_needed[chunk])
	_check("all_needed_chunk_samples_exact",good)
func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/water_lab.tscn").instantiate();preview.brush_fixture="dry_flat";preview.playing=false;preview.hide_hud=true;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("collision_matrix_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	_check("micro_wall_begin",(await preview.begin_shape_stroke(5900)).is_empty())
	for sample in 2:
		var before_replace:int=preview.collision_proxy.shape_allocations+preview.collision_proxy.shape_reuses
		var command:=BrushProtocol.make_command(&"wall_v1",{"height_m":0.3+sample*0.00001,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(3,-0.5),Vector2(3,0.5),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,5900,sample,0,preview.shape_baseline_token)
		command.material_profile_id=&"molded_v1"
		var result:=await submit(command);_check("micro_wall_applied",result.get("status")==1,result)
		await wait_collision();var state:=await snapshot("micro_wall_"+str(sample));verify_shapes(state)
		if sample==1:_check("micro_height_replaces_shape",preview.collision_proxy.shape_allocations+preview.collision_proxy.shape_reuses>before_replace and result.max_cell_delta_m>0 and result.max_cell_delta_m<0.00002,result.max_cell_delta_m)
	await preview.end_shape_stroke()
	for entry in [{"id":&"castle_v1","params":{"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0},"a":Vector2.ZERO,"b":Vector2.ZERO},{"id":&"wall_v1","params":{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},"a":Vector2(3,-0.5),"b":Vector2(3,0.5)},{"id":&"shovel_v1","params":{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},"a":Vector2(-0.5,0),"b":Vector2(0.5,0)}]:
		var result:=await stamp(entry.id,entry.params,entry.a,entry.b,6000+preview.command_queue.last_command_id)
		_check(String(entry.id)+"_applied",result.get("status")==1,result)
		await wait_collision();var state:=await snapshot(String(entry.id)+"_collision");verify_shapes(state)
		_check("published_sand_matches_collision_source",state.sand==state.published_sand)
		var pos:Vector2=preview.player_camera.unproject_position(Vector3(entry.b.x,0,entry.b.y));var hit:Dictionary=preview.pick(pos)
		_check(String(entry.id)+"_physics_pick_current",not hit.is_empty() and preview._pick_current(hit))
		_check("cross_chunk_dirty",preview.collision_needed.size()>=4)
	var chunk:int=preview.collision_needed.keys()[0];var chunks:=PackedInt32Array([chunk]);var before_skip:int=preview.collision_proxy.shape_unchanged_skips;var before_batches:int=preview.collision_proxy.completed_batches
	repack_done=false;RenderingServer.call_on_render_thread(repack.bind(chunks))
	while not repack_done:await process_frame
	deadline=Time.get_ticks_msec()+30000
	while preview.collision_proxy.completed_batches==before_batches and Time.get_ticks_msec()<deadline:await process_frame
	await wait_collision();_check("identical_heights_ack_without_replace",preview.collision_proxy.shape_unchanged_skips>before_skip and preview.collision_proxy.applied_revisions[chunk]>=preview.collision_needed[chunk])
	repack_done=false;RenderingServer.call_on_render_thread(repack.bind(chunks,true))
	while not repack_done:await process_frame
	await preview.shutdown();_check("collision_matrix_release",preview.gpu_release_done and preview.collision_proxy.rd==null);preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
