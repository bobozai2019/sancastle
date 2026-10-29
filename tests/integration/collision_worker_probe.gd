extends SceneTree

const Scheduler = preload("res://scripts/collision/collision_prepare_scheduler.gd")
const Job = preload("res://scripts/collision/collision_prepare_job.gd")
var output := "res://test_output/physics_threading/t02_worker/worker.json"
var checks := []
var measurements := []
var timed_out := false
var last_poll_cpu_us := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_run")

func check(name: String, passed: bool) -> void:
	checks.append({"name":name, "pass":passed})
	if not passed: printerr("WORKER_CHECK_FAIL ", name)

func request(count: int, policy: String, id: int = 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261014
	var heights := PackedFloat32Array()
	heights.resize(count * 1089)
	for index in heights.size():
		heights[index] = rng.randf_range(-15.0, 15.0) + float(index % 33) * 0.01
	heights[0] = -0.0
	var chunks := PackedInt32Array()
	for index in count: chunks.append(index)
	return {"schema_version":1, "request_id":id, "generation":41,
		"captured_revision":21, "grid_size":256, "chunks":chunks,
		"raw_heights":heights.to_byte_array(), "queued_usec":PackedInt64Array(),
		"requested_usec":0, "readback_done_usec":0, "task_policy":policy}

func collect(scheduler: RefCounted) -> Dictionary:
	last_poll_cpu_us = 0
	var deadline := Time.get_ticks_msec() + 10000
	while scheduler.has_in_flight() and Time.get_ticks_msec() < deadline:
		var poll_start := Time.get_ticks_usec()
		var ready: Array[Dictionary] = scheduler.poll_completed()
		last_poll_cpu_us += Time.get_ticks_usec()-poll_start
		if not ready.is_empty(): return ready[0]
		await process_frame
	timed_out = true
	return {}

func byte_oracle(result: Dictionary, original: Dictionary) -> bool:
	if result.get("status") != &"prepared" or result.chunks.size() != original.chunks.size(): return false
	for index in original.chunks.size():
		var chunk: Dictionary = result.chunks[index]
		if chunk.chunk_id != original.chunks[index] or chunk.heights.size() != 1089:
			return false
		# Independent oracle is the immutable original byte range, not prepare_serial.
		var expected: PackedByteArray = original.raw_heights.slice(index*4356, (index+1)*4356)
		if chunk.heights.to_byte_array() != expected: return false
	return true

func _run() -> void:
	for policy in ["serial", "worker1", "worker2", "worker4"]:
		for count in [1, 4, 16]:
			var scheduler := Scheduler.new()
			var original := request(count, policy, 9007199254741009)
			var begin := Time.get_ticks_usec()
			check("admit_%s_%d" % [policy,count], scheduler.enqueue(original).is_empty())
			var result: Dictionary = await collect(scheduler)
			check("byte_oracle_%s_%d" % [policy,count], byte_oracle(result, original))
			check("identity_int64_%s_%d" % [policy,count], result.get("request_id") == original.request_id and result.get("generation") == 41 and result.get("captured_revision") == 21)
			check("reclaim_once_%s_%d" % [policy,count], scheduler.reclaimed_groups == (0 if policy == "serial" else 1) and scheduler.poll_completed().is_empty() and scheduler.completed_requests == 1 and scheduler.payload_bytes() == 0)
			measurements.append({"policy":policy,"chunks":count,"wall_us":Time.get_ticks_usec()-begin,"result":result.timings,"main_thread_id":OS.get_thread_caller_id()})
			for bad_value in [NAN, INF, -INF]:
				for position in [0, int(count*1089/2), count*1089-1]:
					var invalid := request(count, policy)
					invalid.raw_heights.encode_float(position*4, bad_value)
					var bad_scheduler := Scheduler.new()
					check("nonfinite_admit",bad_scheduler.enqueue(invalid).is_empty())
					var bad: Dictionary = await collect(bad_scheduler)
					check("whole_batch_nonfinite_%s_%d_%d" % [policy,count,position], bad.get("status") == &"non_finite" and bad.get("chunks",[1]).is_empty() and bad_scheduler.payload_bytes() == 0)
	var malformed := request(4,"worker2")
	malformed.raw_heights.resize(malformed.raw_heights.size()-1)
	var meta_scheduler := Scheduler.new()
	check("length_rejected_before_task", meta_scheduler.enqueue(malformed) == &"invalid_length" and not meta_scheduler.has_in_flight())
	for ids in [PackedInt32Array([0,0]), PackedInt32Array([-1,0]), PackedInt32Array([0,64])]:
		var invalid := request(2,"worker2");invalid.chunks=ids
		check("invalid_chunk_metadata",meta_scheduler.enqueue(invalid) == &"invalid_chunk" and not meta_scheduler.has_in_flight())
	var float_id := request(1,"worker1");float_id.request_id=1.0
	check("float_identity_rejected",meta_scheduler.enqueue(float_id) == &"invalid_request")
	var large_identity := request(1,"worker1");large_identity.grid_size=9223372036854775776
	check("domain_overflow_rejected",meta_scheduler.enqueue(large_identity) == &"invalid_request")
	var copied := request(16,"worker4")
	var expected := copied.duplicate(true)
	var snapshot_scheduler := Scheduler.new()
	check("snapshot_admit",snapshot_scheduler.enqueue(copied).is_empty())
	copied.raw_heights.encode_float(0,12345.0);copied.chunks[0]=63;copied.generation=999
	check("caller_mutation_isolated",byte_oracle(await collect(snapshot_scheduler),expected))
	var queued := Scheduler.new()
	for id in range(1,6): check("bounded_admit_%d" % id,queued.enqueue(request(16,"worker2",id)).is_empty())
	check("backpressure_no_id_consumption",queued.enqueue(request(16,"worker2",6)) == &"backpressure" and queued.last_admitted_id == 5 and queued.queued_count() == 4 and queued.payload_bytes() <= queued.MAX_PAYLOAD)
	check("duplicate_id_rejected",queued.enqueue(request(16,"worker2",5)) == &"invalid_request")
	queued.stop_admission()
	check("closing_and_waiting_cancel",queued.enqueue(request(16,"worker2",6)) == &"closing" and queued.queued_count() == 0 and queued.canceled_waiting == 4)
	var late: Dictionary = await collect(queued)
	check("active_close_reclaimed_with_true_identity",late.get("generation") == 41 and queued.reclaimed_groups == 1 and not queued.has_in_flight() and queued.payload_bytes() == 0)
	var incomplete := Job.new(request(1,"serial"))
	check("incomplete_slot_explicit_failure",incomplete.result().status == &"worker_failed" and incomplete.result().chunks.is_empty())
	var stress := Scheduler.new()
	var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	for id in range(1,301):
		var original := request(16,"worker2",id)
		if not stress.enqueue(original).is_empty(): check("stress_admission",false);break
		var ready: Dictionary = await collect(stress)
		if not byte_oracle(ready,original): check("stress_oracle",false);break
	check("stress_all_groups_reclaimed",stress.reclaimed_groups == 300 and stress.completed_requests == 300 and stress.payload_bytes() == 0 and not timed_out)
	var memory_after := Performance.get_monitor(Performance.MEMORY_STATIC)
	var cost_samples := []
	# Paired data only: repeated scheduling/collection costs do not measure the game.
	for count in [1,4,16]:
		var common := request(count,"serial")
		for repeat_index in 25:
			var policies := ["serial","worker1","worker2","worker4"]
			if repeat_index % 2 == 1: policies.reverse()
			for policy in policies:
				var candidate := Scheduler.new()
				var input := common.duplicate(true);input.task_policy=policy
				var begin := Time.get_ticks_usec()
				var admission_error: StringName=candidate.enqueue(input)
				var admission_end := Time.get_ticks_usec()
				var ready: Dictionary=await collect(candidate)
				check("cost_sample_integrity",admission_error.is_empty() and byte_oracle(ready,input) and not candidate.has_in_flight())
				cost_samples.append({"policy":policy,"chunks":count,"repeat":repeat_index,
					"enqueue_cpu_us":admission_end-begin,"poll_cpu_us":last_poll_cpu_us,
					"wall_us":Time.get_ticks_usec()-begin,"timings":ready.get("timings",[])})
	var passed := not timed_out
	for row in checks: passed = passed and row.pass
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":passed,"checks":checks,"measurements":measurements,"cost_samples":cost_samples,
		"engine":Engine.get_version_info(),"memory_static_before":memory_before,
		"memory_static_after":memory_after,"stress_reclaimed":stress.reclaimed_groups,
		"stress_highwater_payload":stress.highwater_payload,
		"scope":"headless pure data and task reclamation; not GPU/Jolt or real-window performance"},"\t"))
	file.close()
	print("COLLISION_WORKER ",passed," checks=",checks.size())
	quit(0 if passed else 1)
