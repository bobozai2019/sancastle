extends SceneTree

const Height=preload("res://scripts/simulation/unified_edit/height.gd")
const Job=preload("res://scripts/collision/collision_prepare_job.gd")

class ObservedHeight extends Height:
	var acknowledgements: Array=[]
	func _ack(id: Dictionary, retry: bool) -> void:
		acknowledgements.append({"identity":id.duplicate(),"retry":retry})
		slots[id.slot_id].phase=&"ack_pending"

class ShapeConsumer extends RefCounted:
	var calls: Array=[]
	var delay_usec:=0
	var rejected_chunk:=-1
	func _replace_chunk_shape(chunk: int, version: int, _heights: PackedFloat32Array, _epoch: int) -> bool:
		calls.append({"chunk":chunk,"version":version,"frame":Engine.get_process_frames()})
		if delay_usec>0:OS.delay_usec(delay_usec)
		return chunk!=rejected_chunk

var output:=""
var checks: Array=[]
var failed:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")

func check(label: String, value: bool) -> void:
	checks.append({"name":label,"pass":value});failed=failed or not value
	print("HEIGHT_BUDGET ",label," ",value)

func prepare(subject, slot_index: int, first_chunk: int, count: int) -> void:
	var chunks:=PackedInt32Array();var bounds:={}
	for index in count:chunks.append(first_chunk+index);bounds[first_chunk+index]=0.1
	var heights:=PackedFloat32Array();heights.resize(count*1089);heights.fill(0.4)
	var request:={"schema_version":1,"request_id":slot_index+1,"generation":1,"captured_revision":2,"grid_size":256,"chunks":chunks,"raw_heights":heights.to_byte_array(),"queued_usec":PackedInt64Array(),"requested_usec":0,"readback_done_usec":0,"task_policy":"serial"}
	check("valid_job_"+str(checks.size()),Job.validate(request).is_empty())
	var job:=Job.new(request)
	var task:=WorkerThreadPool.add_task(job.prepare_serial)
	subject.slots[slot_index]={"identity":{"generation":1,"snapshot_seq":slot_index+1,"slot_id":slot_index},"phase":&"worker","result":{"state_seq":2,"sim_tick":1,"revision":2,"chunks":chunks,"change_bounds":bounds},"job":job,"task":task}
	var deadline:=Time.get_ticks_msec()+5000
	while not WorkerThreadPool.is_task_completed(task) and Time.get_ticks_msec()<deadline:await process_frame
	check("worker_complete_"+str(checks.size()),WorkerThreadPool.is_task_completed(task))

func _run() -> void:
	var subject:=ObservedHeight.new();subject.generation=1
	var proxy:=ShapeConsumer.new();subject.proxy=proxy
	await prepare(subject,0,0,16);await prepare(subject,1,16,16)
	subject.physics_consume();subject.physics_consume()
	check("repeated_physics_calls_share_render_frame_cap",proxy.calls.size()==Height.APPLY_MAX_CHUNKS)
	check("partial_slots_keep_borrowed_ownership",subject.acknowledgements.is_empty() and subject.active_count()==2)
	check("first_slot_retains_exact_cursor",subject.slots[0].next_chunk==Height.APPLY_MAX_CHUNKS)
	await process_frame
	subject.physics_consume()
	check("second_slot_gets_next_frame_turn",proxy.calls[Height.APPLY_MAX_CHUNKS].chunk>=16)
	subject.applied_state_seq[15]=9
	var frames:=0
	while subject.acknowledgements.size()<2 and frames<16:
		await process_frame;subject.physics_consume();frames+=1
	check("both_snapshots_eventually_acknowledged",subject.acknowledgements.size()==2 and subject.applied_state_seq.size()==32)
	check("older_partial_snapshot_cannot_regress_newer_chunk",subject.applied_state_seq[15]==9 and proxy.calls.size()==31)
	var per_frame:={}
	for call in proxy.calls:per_frame[call.frame]=int(per_frame.get(call.frame,0))+1
	var bounded:=true
	for count in per_frame.values():bounded=bounded and count<=Height.APPLY_MAX_CHUNKS
	check("cap_holds_across_all_frames",bounded)

	var slow:=ObservedHeight.new();slow.generation=1
	var delayed:=ShapeConsumer.new();delayed.delay_usec=Height.APPLY_BUDGET_USEC+500;slow.proxy=delayed
	await prepare(slow,0,0,10)
	slow.physics_consume();slow.physics_consume()
	check("time_budget_stops_after_one_atomic_shape",delayed.calls.size()==1 and slow.acknowledgements.is_empty())
	slow.close();slow.physics_consume()
	check("closing_discards_partial_cpu_work_then_acknowledges",delayed.calls.size()==1 and slow.acknowledgements.size()==1 and not slow.acknowledgements[0].retry)

	var rejected:=ObservedHeight.new();rejected.generation=1
	var denial:=ShapeConsumer.new();denial.rejected_chunk=1;rejected.proxy=denial
	await prepare(rejected,0,0,4);rejected.physics_consume()
	check("failed_shape_requeues_borrowed_chunks",rejected.acknowledgements.size()==1 and rejected.acknowledgements[0].retry and rejected.applied_state_seq.has(0) and not rejected.applied_state_seq.has(1))
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"scope":"Real completed worker jobs with CPU consumer/ACK doubles: per-render-frame count/time budgets, slot fairness, partial lease retention, stale versions, close and rejection. Real GPU dirty/ACK convergence is verified by the height integration probe."},"\t"))
	quit(1 if failed else 0)
