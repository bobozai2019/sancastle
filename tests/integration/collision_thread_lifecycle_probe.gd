extends SceneTree

const Scheduler = preload("res://scripts/collision/collision_prepare_scheduler.gd")
const Job = preload("res://scripts/collision/collision_prepare_job.gd")
class FailedWorkerJob extends "res://scripts/collision/collision_prepare_job.gd":
	var main_thread_id := OS.get_thread_caller_id()
	func prepare_slot(index: int) -> void:
		if OS.get_thread_caller_id()!=main_thread_id:return
		super.prepare_slot(index)

class FailedWorkerScheduler extends "res://scripts/collision/collision_prepare_scheduler.gd":
	func _start_next() -> void:
		if active!=null or waiting.is_empty():return
		var queued: RefCounted=waiting.pop_front()
		active=FailedWorkerJob.new(queued.request)
		active.scheduled_usec=Time.get_ticks_usec();active.worker_count=1
		group_id=WorkerThreadPool.add_group_task(active.prepare_slot,active.slots.size(),1,false,"collision_failed_worker_probe")
var checks := []
var output := "res://test_output/physics_threading/t03_lifecycle/lifecycle.json"

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("_run")

func check(name: String, passed: bool) -> void:
	checks.append({"name":name,"pass":passed})
	print("COLLISION_THREAD_CHECK ",name," ",passed)

func make_proxy(policy: String):
	var proxy=load("res://scenes/gpu_collision_proxy.tscn").instantiate()
	proxy.set_script(load("res://scripts/simulation/edit_validation/collision_proxy.gd"))
	proxy.solver=SandcastleGpuShallowSolver.new()
	proxy.solver.grid_size=256;proxy.solver.cell_size_m=0.125
	proxy.generation=1;proxy.prepare_policy=policy;proxy.profile_latency_details=true
	root.add_child(proxy)
	return proxy

func values(count: int, base: float = 0.1) -> PackedFloat32Array:
	var result:=PackedFloat32Array();result.resize(count*1089)
	for i in result.size(): result[i]=base+float(i)*0.000001
	return result

func apply(proxy, heights: PackedFloat32Array, chunks: PackedInt32Array, revision: int, token: int = 1) -> void:
	var now:=Time.get_ticks_usec()
	proxy._apply_data(heights.to_byte_array(),chunks,revision,token,0.0,PackedInt64Array(),now,now)

func settled(proxy) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while proxy.has_prepare_in_flight() and Time.get_ticks_msec()<deadline: await process_frame
	return not proxy.has_prepare_in_flight()

func matches(proxy, heights: PackedFloat32Array, chunks: PackedInt32Array) -> bool:
	for i in chunks.size():
		if not proxy.shapes.has(chunks[i]) or proxy.shapes[chunks[i]].shape.map_data.to_byte_array()!=heights.slice(i*1089,(i+1)*1089).to_byte_array(): return false
	return true

func shape_ids(proxy, chunks: PackedInt32Array) -> Array:
	var result:=[]
	for chunk in chunks: result.append(proxy.shapes[chunk].shape.get_instance_id())
	return result

func _run() -> void:
	root.size=Vector2i(1280,720)
	var chunks:=PackedInt32Array([0,1,8])
	for policy in ["serial","worker1","worker2","worker4"]:
		var proxy=make_proxy(policy)
		var original:=values(3)
		apply(proxy,original,chunks,1)
		if policy!="serial":check(policy+"_prepare_not_published_early",proxy.applied_revisions.is_empty())
		check(policy+"_settled",await settled(proxy))
		check(policy+"_byte_heights",matches(proxy,original,chunks))
		await physics_frame;await physics_frame
		var center: Vector3=proxy.shapes[0].global_position
		var query:=PhysicsRayQueryParameters3D.create(center+Vector3.UP*10.0,center-Vector3.UP*10.0)
		var hit: Dictionary=proxy.get_world_3d().direct_space_state.intersect_ray(query)
		check(policy+"_real_jolt_ray",hit.get("collider")==proxy.body and absf(hit.position.y-original[16*33+16])<0.00001)
		var ids:=shape_ids(proxy,chunks)
		apply(proxy,original,chunks,2);await settled(proxy)
		check(policy+"_equal_ack_without_shape_replace",shape_ids(proxy,chunks)==ids and proxy.applied_revisions[0]==2)
		var changed:=original.duplicate();changed[16*33+16]+=0.000001
		apply(proxy,changed,chunks,3);await settled(proxy)
		check(policy+"_micrometer_updates",shape_ids(proxy,chunks)[0]!=ids[0] and matches(proxy,changed,chunks))
		var current_ids:=shape_ids(proxy,chunks)
		var nan_tail:=changed.duplicate();nan_tail[0]+=1.0;nan_tail[nan_tail.size()-1]=NAN
		var invalid_before: int=proxy.invalid_readbacks
		apply(proxy,nan_tail,chunks,4);await settled(proxy)
		check(policy+"_whole_batch_rejected",proxy.invalid_readbacks==invalid_before+1 and shape_ids(proxy,chunks)==current_ids and matches(proxy,changed,chunks))
		apply(proxy,values(3,2.0),chunks,10)
		proxy.prepare_policy="baseline"
		var newest:=values(3,3.0)
		apply(proxy,newest,chunks,20)
		proxy.prepare_policy=policy
		await settled(proxy)
		check(policy+"_newer_shape_beats_late_worker",matches(proxy,newest,chunks) and proxy.applied_revisions[0]==20)
		apply(proxy,values(3,4.0),chunks,21)
		proxy.generation=2;proxy.applied_revisions.clear()
		await settled(proxy)
		if policy!="serial":
			check(policy+"_old_generation_cannot_publish",matches(proxy,newest,chunks) and proxy.applied_revisions.is_empty())
		else:
			check("serial_completed_before_generation_change",matches(proxy,values(3,4.0),chunks))
		apply(proxy,newest,chunks,0,2);await settled(proxy)
		check(policy+"_generation_restore_ack",proxy.applied_revisions[0]==0 and matches(proxy,newest,chunks))
		check(policy+"_all_tasks_reclaimed",proxy.prepare_scheduler.group_id==-1 and proxy.prepare_scheduler.payload_bytes()==0)
		proxy.free()
	# Force backpressure before main-frame collection: disjoint chunks must all publish.
	var pressure=make_proxy("worker2")
	for chunk in 6: apply(pressure,values(1,float(chunk)),PackedInt32Array([chunk]),7)
	await settled(pressure)
	var all_chunks:=true
	for chunk in 6:all_chunks=all_chunks and pressure.applied_revisions.get(chunk)==7
	check("backpressure_retains_disjoint_revisions",all_chunks and pressure.prepare_backpressure_fallbacks==1)
	var duplicate_request:= {"schema_version":1,"request_id":pressure.prepare_serial,"generation":1,
		"captured_revision":7,"grid_size":256,"chunks":PackedInt32Array([5]),
		"raw_heights":values(1,100.0).to_byte_array(),"queued_usec":PackedInt64Array(),
		"requested_usec":0,"readback_done_usec":0,"task_policy":"serial"}
	var duplicate:=Job.new(duplicate_request);duplicate.prepare_serial()
	var batches: int=pressure.completed_batches
	pressure._commit_prepared(duplicate.result())
	check("duplicate_delivery_not_applied",pressure.completed_batches==batches and pressure.shapes[5].shape.map_data[0]==5.0)
	pressure.free()
	var shadow=make_proxy("worker2")
	var rock:=PackedFloat32Array();rock.resize(256*256);rock.fill(0.15)
	var sand:=PackedFloat32Array();sand.resize(256*256);sand.fill(0.05)
	check("shadow_initial_complete",shadow.apply_shadow_chunks(chunks,1,1,rock,sand))
	var shadow_ids:=shape_ids(shadow,chunks)
	rock[0]+=0.1;rock[64*256+32]=NAN
	check("shadow_last_slot_invalid_no_partial_publish",not shadow.apply_shadow_chunks(chunks,2,1,rock,sand) and shape_ids(shadow,chunks)==shadow_ids and shadow.applied_revisions[0]==1)
	rock.fill(3e38);sand.fill(3e38)
	check("shadow_float32_overflow_rejected",not shadow.apply_shadow_chunks(chunks,2,1,rock,sand) and shape_ids(shadow,chunks)==shadow_ids)
	rock.fill(0.15);sand.fill(0.05)
	check("shadow_duplicate_chunks_rejected",not shadow.apply_shadow_chunks(PackedInt32Array([0,0]),2,1,rock,sand) and shadow.applied_revisions[0]==1)
	shadow.free()
	# Build one continuous analytic bed across shared chunks and the clamped domain edge.
	var seam=make_proxy("worker2")
	var seam_chunks:=PackedInt32Array([0,1,8,9,63])
	for z in 256:
		for x in 256:rock[z*256+x]=0.4+0.002*x-0.001*z
	sand.fill(0.05)
	check("seam_shadow_preparation",seam.apply_shadow_chunks(seam_chunks,1,1,rock,sand))
	var packed:=PackedFloat32Array()
	for chunk in seam_chunks:packed.append_array(seam.shapes[chunk].shape.map_data)
	var original_position: Vector3=seam.shapes[0].position
	var original_shape: int=seam.shapes[0].shape.get_instance_id()
	apply(seam,packed,seam_chunks,2)
	seam.shapes[0].position+=Vector3.RIGHT
	await settled(seam)
	check("worker_rechecks_live_transform",seam.shapes[0].position==original_position and seam.shapes[0].shape.get_instance_id()!=original_shape)
	var shared_equal:=true
	for local_z in 33:
		shared_equal=shared_equal and seam.shapes[0].shape.map_data[local_z*33+32]==seam.shapes[1].shape.map_data[local_z*33]
	check("shared_seam_samples_identical",shared_equal)
	await physics_frame;await physics_frame
	for pixel in [Vector2i(32,16),Vector2i(16,32),Vector2i(32,32),Vector2i(255,240)]:
		var height: float=rock[pixel.y*256+pixel.x]+sand[pixel.y*256+pixel.x]
		var point:=Vector3((pixel.x+0.5)*0.125-16.0,height,(pixel.y+0.5)*0.125-16.0)
		for direction in [Vector3(0,10,0),Vector3(0.5,10,0.5)]:
			var hit: Dictionary=seam.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+direction,point-direction))
			check("seam_and_edge_ray_%s_%s" % [pixel,direction],hit.get("collider")==seam.body and absf(hit.position.y-height)<0.00001 and hit.position.distance_to(point)<0.0001)
	seam.free()
	var retry=make_proxy("worker1")
	var failed_scheduler:=FailedWorkerScheduler.new()
	retry.prepare_scheduler=failed_scheduler
	var retry_values:=values(3,0.3)
	apply(retry,retry_values,chunks,1)
	await settled(retry)
	check("worker_failure_serial_retry_once",failed_scheduler.serial_retries==1 and failed_scheduler.reclaimed_groups==1 and matches(retry,retry_values,chunks) and retry.invalid_readbacks==0)
	retry.free()
	var closing=make_proxy("worker2")
	apply(closing,values(16),PackedInt32Array(range(16)),1)
	closing.closing=true
	await settled(closing)
	check("closing_reclaims_without_publish",closing.shapes.is_empty() and closing.prepare_scheduler.reclaimed_groups==1)
	closing.free()
	var reclaimed_before: int=Scheduler.detached_reclaimed
	var abandoned=make_proxy("worker2")
	apply(abandoned,values(16),PackedInt32Array(range(16)),1)
	abandoned.free()
	var deadline:=Time.get_ticks_msec()+5000
	while not Scheduler.detached.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("node_exit_reaper_survives_owner",Scheduler.detached.is_empty() and Scheduler.detached_reclaimed==reclaimed_before+1)
	var passed:=true
	for row in checks:passed=passed and row.pass
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":passed,"checks":checks,"engine":Engine.get_version_info(),
		"detached_left":Scheduler.detached.size(),"scope":"real Jolt heightfields and proxy-level CPU lifecycle; not GPU/checkpoint/scene-service coverage"},"\t"));file.close()
	quit(0 if passed else 1)
