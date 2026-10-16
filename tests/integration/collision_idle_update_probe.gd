extends SceneTree

# Exercise the production readback/shadow paths with real Jolt heightfields.
const CHUNKS := [0, 1, 8]
const SAMPLES := 33 * 33
var proxy: SandcastleGpuCollisionProxy
var checks := []
var output := "res://test_output/physics_collision_fix_20261014/collision_contract.json"

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_run")

func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"pass":ok})
	print("COLLISION_IDLE_CHECK ",name," ",ok)

func apply(values: PackedFloat32Array, revision: int, token: int = 1) -> void:
	proxy._apply_data(values.to_byte_array(), PackedInt32Array(CHUNKS), revision,
		token, 2.0, PackedInt64Array([100,200,300]), 400, 500)

func ids() -> Array:
	var result := []
	for chunk in CHUNKS: result.append(proxy.shapes[chunk].shape.get_instance_id())
	return result

func maps_equal(values: PackedFloat32Array) -> bool:
	for slot in CHUNKS.size():
		if proxy.shapes[CHUNKS[slot]].shape.map_data != values.slice(slot*SAMPLES,(slot+1)*SAMPLES): return false
	return true

func ray_height() -> float:
	var center: Vector3 = proxy.shapes[0].global_position
	var hit := proxy.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(center+Vector3.UP*10.0,center-Vector3.UP*10.0))
	return hit.position.y if hit.get("collider") == proxy.body else INF

func _run() -> void:
	proxy = load("res://scenes/gpu_collision_proxy.tscn").instantiate()
	proxy.set_script(load("res://scripts/simulation/edit_validation/collision_proxy.gd"))
	proxy.solver = SandcastleGpuShallowSolver.new()
	proxy.solver.grid_size = 256
	proxy.solver.cell_size_m = 0.125
	proxy.generation = 1
	proxy.profile_latency_details = true
	root.add_child(proxy)
	var values := PackedFloat32Array()
	values.resize(SAMPLES*CHUNKS.size())
	for slot in CHUNKS.size():
		for index in SAMPLES: values[slot*SAMPLES+index] = 0.1+slot*0.1+index*0.000001
	apply(values,1)
	check("multi_chunk_heights_preserved",maps_equal(values) and proxy.shape_allocations==3)
	check("full_callback_timer_includes_replace",proxy.last_apply_ms>=proxy.last_replace_ms and proxy.last_apply_generation==1)
	check("initial_batch_counts",proxy.last_batch_replaced_chunks==3 and proxy.last_batch_unchanged_chunks==0)
	await physics_frame
	await physics_frame
	var original_ray := ray_height()
	check("jolt_pick_reads_heightfield",is_finite(original_ray) and absf(original_ray-values[16*33+16])<0.00001)
	var original_ids := ids()
	var first_apply_us: int = proxy.applied_usec[0]
	apply(values,2)
	check("equal_heights_keep_shape_ids",ids()==original_ids and proxy.shape_allocations==3 and proxy.shape_unchanged_skips==3)
	var metadata_ok := true
	for chunk in CHUNKS:
		metadata_ok = metadata_ok and proxy.applied_revisions[chunk]==2 and proxy.applied_stage_usec[chunk].size()==4
	check("skips_acknowledge_revision_and_latency",metadata_ok and proxy.applied_usec[0]>=first_apply_us)
	check("unchanged_batch_counts",proxy.last_batch_replaced_chunks==0 and proxy.last_batch_unchanged_chunks==3)
	await physics_frame
	await physics_frame
	check("skip_preserves_physics_pick",ray_height()==original_ray)
	values[16*33+16] += 0.000001
	apply(values,3)
	var changed_ids := ids()
	check("micrometer_change_still_updates",changed_ids[0]!=original_ids[0] and changed_ids[1]==original_ids[1] and changed_ids[2]==original_ids[2] and maps_equal(values))
	check("mixed_batch_counts",proxy.last_batch_replaced_chunks==1 and proxy.last_batch_unchanged_chunks==2)
	var stale := values.duplicate()
	stale[0] += 1.0
	apply(stale,1)
	check("old_revision_cannot_overwrite",ids()==changed_ids and maps_equal(values) and proxy.applied_revisions[0]==3)
	var invalid_before := proxy.invalid_readbacks
	var batches_before := proxy.completed_batches
	var malformed := values.to_byte_array()
	malformed.resize(malformed.size()-1)
	proxy._apply_data(malformed,PackedInt32Array(CHUNKS),4,1,0.0,PackedInt64Array(),0,0)
	check("bad_length_rejected",proxy.invalid_readbacks==invalid_before+1 and proxy.completed_batches==batches_before and ids()==changed_ids)
	var nonfinite := values.duplicate()
	nonfinite[0] += 1.0
	nonfinite[nonfinite.size()-1] = NAN
	apply(nonfinite,4)
	check("nonfinite_batch_rejected_before_any_replace",proxy.invalid_readbacks==invalid_before+2 and proxy.completed_batches==batches_before and ids()==changed_ids and maps_equal(values))
	apply(stale,4,0)
	check("old_generation_ignored",proxy.completed_batches==batches_before and proxy.applied_revisions[0]==3)
	var rock := PackedFloat32Array()
	var sand := PackedFloat32Array()
	rock.resize(256*256)
	sand.resize(256*256)
	rock.fill(0.15)
	sand.fill(0.05)
	var one := PackedInt32Array([0])
	check("shadow_update_accepted",proxy.apply_shadow_chunks(one,4,1,rock,sand))
	var shadow_id: int = proxy.shapes[0].shape.get_instance_id()
	var allocations_before := proxy.shape_allocations
	check("same_shadow_keeps_shape",proxy.apply_shadow_chunks(one,5,1,rock,sand) and proxy.shape_allocations==allocations_before and proxy.shapes[0].shape.get_instance_id()==shadow_id and proxy.applied_revisions[0]==5)
	var expected_position: Vector3 = proxy.shapes[0].position
	proxy.shapes[0].position += Vector3.RIGHT
	check("transform_change_is_not_skipped",proxy.apply_shadow_chunks(one,6,1,rock,sand) and proxy.shapes[0].position==expected_position and proxy.shape_allocations==allocations_before+1)
	var current := PackedFloat32Array()
	for chunk in CHUNKS: current.append_array(proxy.shapes[chunk].shape.map_data)
	proxy.generation = 2
	proxy.applied_revisions.clear()
	proxy.applied_usec.clear()
	proxy.applied_stage_usec.clear()
	var restore_ids := ids()
	apply(current,0,2)
	check("generation_restore_can_reuse_equal_shapes",ids()==restore_ids and proxy.applied_revisions[0]==0 and proxy.last_apply_generation==2 and proxy.last_batch_unchanged_chunks==3)
	proxy.reuse_chunk_shapes = true
	apply(current,1,2)
	check("reuse_mode_also_skips_equal_heights",proxy.shape_reuses==0 and ids()==restore_ids)
	current[0] += 0.000001
	apply(current,2,2)
	check("reuse_mode_updates_real_change",proxy.shape_reuses==1 and ids()==restore_ids and maps_equal(current))
	var passed := true
	for row in checks: passed = passed and row.pass
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":passed,"checks":checks,"engine":Engine.get_version_info()},"\t"))
	file.close()
	proxy.free()
	quit(0 if passed else 1)
