extends "res://tests/integration/async_pipeline_edit_probe.gd"

const Collision=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_collision.gd")
const Heights=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_height_codec.gd")
const Water=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_water.gd")
const Coupled=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_coupled.gd")
const Sediment=preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const Materials=preload("res://scripts/simulation/brushes/brush_material_coupler.gd")
var heights
var collision_initialized:=false
var collision_ok:=false
var consume_enabled:=false
var physics_calls:=0
var request_ray:=false
var ray_result:={}
var ray_point:=Vector3(-7.9375,0,-7.9375)
var collision_released:=false
var busy_release_blocked:=false
var water:=Water.new()
var coupled:=Coupled.new()
var sediment:=Sediment.new()
var material:=Materials.new()

func _physics_process(_delta: float) -> bool:
	physics_calls+=1
	if consume_enabled and heights!=null:heights.physics_consume(consume_order)
	if request_ray:
		var query:=PhysicsRayQueryParameters3D.create(ray_point+Vector3(0,50,0),ray_point-Vector3(0,50,0))
		ray_result=preview.get_world_3d().direct_space_state.intersect_ray(query)
	return false

func _collision_initialize_render() -> void:
	collision_ok=heights.initialize(editor)
	if collision_ok:collision_ok=water.initialize(editor) and sediment.initialize(editor,preview.spirvs[10],preview.spirvs[11]) and material.initialize(editor,sediment.dirty_max_texture,preview.spirvs[12],preview.spirvs[13],preview.spirvs[14])
	if collision_ok:collision_ok=coupled.initialize(water,sediment,material)
	call_deferred("_collision_initialized")

func _collision_initialized() -> void:
	collision_initialized=true

func wait_captures(count: int) -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		var ready:=0
		for slot in heights.slots:
			if slot.task>=0 and WorkerThreadPool.is_task_completed(slot.task):ready+=1
		if ready>=count:return true
		await process_frame
	return false

func drain() -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		heights.pump()
		if heights.pending.is_empty() and heights.active_count()==0:return true
		await process_frame
	return false

func _collision_release_render() -> void:
	collision_released=heights.release_render()
	coupled.detach()
	water.release()
	material.release()
	sediment.release()

func _busy_release_render() -> void:
	busy_release_blocked=not heights.release_render()

func _simulate_render(id: Dictionary, depths: PackedByteArray) -> void:
	var values:=depths.to_float32_array()
	for index in values.size():values[index]*=2.0
	for index in 2:
		var source:=editor._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,values.to_byte_array())
		editor._copy_texture(source,editor.textures.momentum_x[index])
		editor.rd.free_rid(source)
	var error:=water.dispatch(id,1.0/60.0,_arrived)
	if not error.is_empty():call_deferred("_transport_error",error)

func simulation_height_refresh() -> void:
	var before: Dictionary=await snapshot()
	var id: Dictionary=pool.acquire().identity
	pool.submitted(id)
	RenderingServer.call_on_render_thread(_simulate_render.bind(id,before.water0))
	heights.mark_all() # Conservative source for erosion/material bed changes.
	heights.pump()
	var deadline:=Time.get_ticks_msec()+30000
	while not callbacks.has(id.batch_seq) and Time.get_ticks_msec()<deadline:await process_frame
	var result: Dictionary=pool.consume(id)
	check("actual_simulation_complete",result.error.is_empty() and result.error_flags==0 and result.sim_tick==1 and result.state_seq==4)
	RenderingServer.call_on_render_thread(_retire_render.bind(id))
	check("simulation_height_drain",await drain())
	check("simulation_snapshots_versioned",heights.applied_state_seq.values().all(func(v):return v==4) and heights.applied_sim_tick.values().all(func(v):return v==1))
	var after: Dictionary=await snapshot()
	check("erosion_material_really_changed_bed",before.sand0!=after.sand0)
	var sand: PackedFloat32Array=after.sand0.to_float32_array()
	var bed:=PackedFloat32Array()
	bed.resize(65536)
	for index in 65536:bed[index]=preview.shadow_domain.rock[index]+sand[index]
	var equal:=true
	for chunk in 64:
		var values: PackedFloat32Array=preview.collision_proxy.shapes[chunk].shape.map_data
		for z in 33:
			for x in 33:equal=equal and values[z*33+x]==bed[mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)]
	check("simulation_collisions_equal_latest_gpu_bed",equal)

func inject_invalid_snapshots() -> void:
	var unchanged: PackedFloat32Array=preview.collision_proxy.shapes[18].shape.map_data.duplicate()
	var baseline: int=heights.invalid_results
	heights.serial+=1
	var id:={"generation":preview.generation,"snapshot_seq":heights.serial,"slot_id":0,"chunks":PackedInt32Array([18])}
	heights.slots[0]={"identity":id,"result":{},"job":null,"task":-1}
	var bytes:=_ready_snapshot_bytes(id,2,0.5)
	var old:=id.duplicate()
	old.generation+=1
	heights._receive(bytes,old)
	check("old_generation_cannot_release_snapshot",heights.active_count()==1 and heights.invalid_results==baseline)
	heights._receive(bytes.slice(0,bytes.size()-1),id)
	check("bad_length_requeues",heights.active_count()==0 and heights.pending.has(18) and heights.invalid_results==baseline+1)
	check("bad_length_keeps_shape",preview.collision_proxy.shapes[18].shape.map_data==unchanged)
	check("after_bad_length_refresh",await drain())
	heights.serial+=1
	id.snapshot_seq=heights.serial
	heights.slots[0]={"identity":id.duplicate(true),"result":{},"job":null,"task":-1}
	bytes=_ready_snapshot_bytes(id,2,0.5)
	bytes.encode_float(128,NAN)
	heights._receive(bytes,id)
	var task: int=heights.slots[0].task
	heights._receive(bytes,id)
	check("duplicate_snapshot_no_second_worker",task>=0 and heights.slots[0].task==task)
	var deadline:=Time.get_ticks_msec()+10000
	while heights.active_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check("nonfinite_worker_requeues",heights.invalid_results==baseline+2 and heights.pending.has(18))
	check("nonfinite_keeps_shape",preview.collision_proxy.shapes[18].shape.map_data==unchanged)
	check("after_nonfinite_refresh",await drain())

func _ready_snapshot_bytes(id: Dictionary, state_seq: int, value: float) -> PackedByteArray:
	var bytes:=PackedByteArray()
	bytes.resize(128+id.chunks.size()*1089*4)
	bytes.encode_u32(0,1)
	bytes.encode_u64(8,id.generation)
	bytes.encode_u64(16,id.snapshot_seq)
	bytes.encode_u64(24,state_seq)
	bytes.encode_u32(40,id.chunks.size())
	bytes.encode_u32(44,33)
	bytes.encode_u32(48,256)
	bytes.encode_float(52,0.125)
	bytes.encode_u32(56,id.chunks.size()*1089*4)
	for index in id.chunks.size():bytes.encode_u32(64+index*4,id.chunks[index])
	for index in id.chunks.size()*1089:bytes.encode_float(128+index*4,value)
	return bytes

func negative_codecs() -> void:
	var id:={"generation":preview.generation,"snapshot_seq":99,"slot_id":0,"chunks":PackedInt32Array([1])}
	var bytes:=_ready_snapshot_bytes(id,0x100000002,0.5)
	check("snapshot_u64_layout",Heights.decode(bytes,id).state_seq==0x100000002)
	check("snapshot_short",Heights.decode(bytes.slice(0,bytes.size()-1),id).error=="snapshot_layout")
	var bad:=bytes.duplicate()
	bad.encode_u64(8,id.generation+1)
	check("snapshot_wrong_generation",Heights.decode(bad,id).error=="snapshot_identity")
	bad=bytes.duplicate()
	bad.encode_u32(64,64)
	check("snapshot_bad_chunk",Heights.decode(bad,id).error=="snapshot_chunks")
	bad=bytes.duplicate()
	bad.encode_float(52,NAN)
	check("snapshot_bad_cell",Heights.decode(bad,id).error=="snapshot_layout")

func _run() -> void:
	preview=load("res://scenes/main.tscn").instantiate()
	preview.playing=false
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("main_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	while preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty() or preview.collision_proxy.has_prepare_in_flight():await process_frame
	pool=Slots.new(preview.generation)
	RenderingServer.call_on_render_thread(_initialize_render)
	while not initialized and Time.get_ticks_msec()<deadline:await process_frame
	check("async_editor_ready",initialized and initialize_ok)
	heights=Collision.new(preview.collision_proxy)
	heights.observe=true
	RenderingServer.call_on_render_thread(_collision_initialize_render)
	while not collision_initialized and Time.get_ticks_msec()<deadline:await process_frame
	check("height_pool_ready",collision_initialized and collision_ok)
	if collision_ok:
		negative_codecs()
		heights.mark_all()
		check("two_snapshot_slots",heights.pump()==2 and heights.active_count()==2 and heights.pending.size()==32)
		check("snapshots_finished_while_held",await wait_captures(2))
		RenderingServer.call_on_render_thread(_busy_release_render)
		await process_frame
		await process_frame
		check("cannot_release_active_height_pool",busy_release_blocked)
		var edit:=make(Vector3(-8,0,-8))
		var results: Array=await wait_batch(submit([edit]),1)
		heights.mark_command(edit)
		check("edit_while_collision_saturated",results.size()==1 and results[0].status==1 and heights.active_count()==2 and heights.pump()==0)
		check("new_dirty_survives_old_snapshot",heights.pending.has(18))
		check("captured_gpu_state_labels",heights.slots.all(func(slot):return slot.result.state_seq==0 and slot.result.sim_tick==0))
		consume_enabled=true
		check("eventual_dirty_drain",await drain())
		heights.mark_all()
		check("latest_global_refresh",await drain())
		check("physics_consumer_ran",physics_calls>0)
		check("all_chunks_latest",heights.applied_state_seq.size()==64 and heights.applied_state_seq.values().all(func(v):return v==1))
		var current: Dictionary=await snapshot()
		var rock: PackedFloat32Array=preview.shadow_domain.rock
		var sand: PackedFloat32Array=current.sand0.to_float32_array()
		var bed:=PackedFloat32Array()
		bed.resize(65536)
		for index in 65536:bed[index]=rock[index]+sand[index]
		var all_equal:=true
		for chunk in 64:
			var shape: HeightMapShape3D=preview.collision_proxy.shapes[chunk].shape
			for z in 33:
				for x in 33:
					var cell_x:=mini((chunk%8)*32+x,255)
					var cell_z:=mini((chunk/8)*32+z,255)
					all_equal=all_equal and shape.map_data[z*33+x]==bed[cell_z*256+cell_x]
		check("all_real_heights_and_shared_edges",all_equal)
		request_ray=true
		deadline=Time.get_ticks_msec()+5000
		while (ray_result.is_empty() or absf(ray_result.position.y-bed[64*256+64])>0.0001) and Time.get_ticks_msec()<deadline:await process_frame
		request_ray=false
		check("jolt_ray_hits_real_height",not ray_result.is_empty() and absf(ray_result.position.y-bed[64*256+64])<=0.0001)
		var skipped: int=preview.collision_proxy.shape_unchanged_skips
		heights.mark_all()
		check("unchanged_refresh_drains",await drain())
		check("unchanged_shapes_skipped",preview.collision_proxy.shape_unchanged_skips>=skipped+64)
		# Two immutable versions of one chunk: apply newer slot1 before slot0.
		consume_enabled=false
		heights.mark_chunks(PackedInt32Array([18]))
		heights.pump()
		check("old_request_ready",await wait_captures(1))
		var command:=make(Vector3(-8,0,-8))
		await wait_batch(submit([command]),1)
		heights.mark_command(command)
		heights.pump()
		check("new_request_ready",await wait_captures(2))
		check("two_true_versions",heights.slots[0].result.state_seq==1 and heights.slots[1].result.state_seq==2)
		# Route selected consumption through the actual physics callback.
		consume_order=PackedInt32Array([1])
		consume_enabled=true
		while heights.slots[1].task>=0:await process_frame
		check("newer_applied_first",heights.applied_state_seq[18]==2 and heights.slots[0].task>=0)
		consume_order=PackedInt32Array([0,1])
		check("late_old_drains",await drain())
		check("old_cannot_overwrite",heights.applied_state_seq[18]==2)
		check("no_uninjected_invalid_readbacks",heights.invalid_results==0 and heights.last_error.is_empty())
		await inject_invalid_snapshots()
		var before_rejection: int=preview.collision_proxy.shape_unchanged_skips
		var rejected_command:=make(Vector3(-8,0,-8))
		var rejected: Array=await wait_batch(submit([rejected_command],true),1)
		heights.mark_command(rejected_command)
		check("rejected_command_refreshes",rejected.size()==1 and rejected[0].status==2 and await drain() and heights.applied_state_seq[18]==3)
		check("rejected_snapshot_unchanged",preview.collision_proxy.shape_unchanged_skips>before_rejection)
		check("only_injected_snapshot_errors",heights.invalid_results==2 and heights.last_error.is_empty())
		await simulation_height_refresh()
		heights.closing=true
		RenderingServer.call_on_render_thread(_collision_release_render)
		while not collision_released:await process_frame
		check("height_resources_released",heights.rd==null)
		RenderingServer.call_on_render_thread(_release_render)
		while not released:await process_frame
		check("editor_resources_released",released)
	await preview.shutdown()
	check("main_released",preview.gpu_release_done)
	preview.queue_free()
	await process_frame
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"events":heights.events,"scope":"P04 candidate heights/physics; main pump integration pending"},"\t"))
	quit(1 if failed else 0)

var consume_order:=PackedInt32Array([0,1])
