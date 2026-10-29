extends RefCounted

const Job = preload("res://scripts/collision/collision_prepare_job.gd")
const MAX_WAITING := 4
const MAX_PAYLOAD := 2 * 1024 * 1024

var accepting := true
var waiting: Array[RefCounted] = []
var active: RefCounted
var group_id := -1
var last_admitted_id := 0
var reclaimed_groups := 0
var completed_requests := 0
var canceled_waiting := 0
var highwater_payload := 0
var highwater_waiting := 0
var serial_retries := 0
static var detached: Array[RefCounted] = []
static var detached_reclaimed := 0

func detach(tree: SceneTree) -> void:
	stop_admission()
	if active == null or detached.has(self):
		return
	detached.append(self)
	if not tree.process_frame.is_connected(_poll_detached):
		tree.process_frame.connect(_poll_detached)

static func _poll_detached() -> void:
	for scheduler in detached.duplicate():
		var before: int = scheduler.reclaimed_groups
		scheduler.poll_completed()
		detached_reclaimed += scheduler.reclaimed_groups - before
		if not scheduler.has_in_flight():
			detached.erase(scheduler)
	if detached.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.process_frame.is_connected(_poll_detached):
			tree.process_frame.disconnect(_poll_detached)

func payload_bytes() -> int:
	var bytes: int = active.request.raw_heights.size() * 2 if active != null else 0
	for job in waiting:
		bytes += job.request.raw_heights.size() * 2
	return bytes

func queued_count() -> int:
	return waiting.size()

func has_in_flight() -> bool:
	return active != null or not waiting.is_empty()

func enqueue(request: Dictionary) -> StringName:
	if not accepting:
		return &"closing"
	var error: StringName = Job.validate(request)
	if not error.is_empty():
		return error
	if request.request_id <= last_admitted_id:
		return &"invalid_request"
	if (active != null and waiting.size() >= MAX_WAITING) or \
			payload_bytes() + request.raw_heights.size() * 2 > MAX_PAYLOAD:
		return &"backpressure"
	var job := Job.new(request)
	last_admitted_id = request.request_id
	waiting.append(job)
	highwater_waiting = maxi(highwater_waiting, waiting.size())
	_start_next()
	highwater_payload = maxi(highwater_payload, payload_bytes())
	return &""

func _start_next() -> void:
	if active != null or waiting.is_empty():
		return
	active = waiting.pop_front()
	active.scheduled_usec = Time.get_ticks_usec()
	var policy: String = active.request.task_policy
	if policy == "serial":
		active.prepare_serial()
		group_id = -1
	else:
		active.worker_count = int(policy.trim_prefix("worker"))
		group_id = WorkerThreadPool.add_group_task(active.prepare_slot,
			active.slots.size(), active.worker_count, false, "sandcastle_collision_prepare")

func poll_completed() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if active == null:
		_start_next()
		return results
	if group_id >= 0:
		if not WorkerThreadPool.is_group_task_completed(group_id):
			return results
		# Sole reclamation point. Never wait on an unfinished group.
		WorkerThreadPool.wait_for_group_task_completion(group_id)
		reclaimed_groups += 1
		group_id = -1
	active.collected_usec = Time.get_ticks_usec()
	var result: Dictionary = active.result()
	if result.status == &"worker_failed":
		# Completed group only. One main-thread recovery attempt, using original bytes.
		serial_retries += 1
		active.prepare_serial()
		result = active.result()
		result.serial_retry = true
	results.append(result)
	completed_requests += 1
	active = null
	_start_next()
	return results

func stop_admission() -> void:
	accepting = false
	canceled_waiting += waiting.size()
	waiting.clear()
	# Keep the active job/ID until poll_completed reclaims it. The owner must drain.
