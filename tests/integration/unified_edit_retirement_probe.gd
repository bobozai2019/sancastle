extends SceneTree

const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Transport=preload("res://scripts/simulation/unified_edit/transport.gd")
const W=preload("res://scripts/simulation/unified_edit/protocol.gd")
const L=preload("res://scripts/simulation/unified_edit/layout.gd")

# CPU ownership test. This substitutes only the render-owner proof response;
# the separate submit-ahead GPU probe exercises real transport retirement.
class ProofTransport extends Transport:
	var confirmed:=true
	var proof_checked:=false
	var caller_thread:=0
	func retire(_id: Dictionary) -> bool:
		proof_checked=true;caller_thread=OS.get_thread_caller_id()
		return confirmed

var checks: Array=[]
var output:=""
var failed:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")

func check(label: String, ok: bool) -> void:
	checks.append({"name":label,"pass":ok});failed=failed or not ok
	print("RETIREMENT ",label," ",ok)

func prepared() -> Dictionary:
	var owner:=Pipeline.new()
	owner.transport=ProofTransport.new()
	check("slots_initialize_"+str(checks.size()),owner.slots.initialize("main_beach",1).is_empty())
	var id: Dictionary=owner.slots.acquire().identity
	check("queued_"+str(checks.size()),owner.slots.queued(id,[],L.WorkKind.WATER_TICK).is_empty())
	var bytes:=W.encode_completion(id,[],{"state_seq":1,"sim_tick":1,"revision":0,"state":L.CompletionState.COMPLETE,"error_flags":0,"advanced_time_s":0.001,"actual_dt":0.001,"accepted_count":0,"rejected_count":0})
	check("completion_"+str(checks.size()),owner.slots.completed(bytes,id).is_empty())
	check("consume_"+str(checks.size()),owner.slots.consume(id).error.is_empty())
	return {"owner":owner,"id":id}

func _run() -> void:
	var direct:=prepared()
	direct.owner._retire_render(direct.id)
	check("same_owner_confirms_before_return",direct.owner.transport.proof_checked and direct.owner.active_count()==0 and direct.owner.fault_reason().is_empty())
	var next: Dictionary=direct.owner.slots.acquire().identity
	check("reuse_has_new_lease",next.slot_id==direct.id.slot_id and next.lease_id>direct.id.lease_id)
	await process_frame
	check("no_duplicate_deferred_ack",direct.owner.fault_reason().is_empty() and direct.owner.slots.slot_snapshot(next.slot_id).identity==next)

	var foreign:=prepared()
	var worker:=Thread.new()
	check("worker_started",worker.start(foreign.owner._retire_render.bind(foreign.id))==OK)
	# Join only this tiny CPU test worker, not a production GPU/collision path.
	worker.wait_to_finish()
	check("foreign_thread_does_not_touch_slot_owner",foreign.owner.transport.caller_thread!=OS.get_thread_caller_id() and foreign.owner.slots.slot_snapshot(foreign.id.slot_id).state==Pipeline.Slots.State.CPU_RECLAIM)
	await process_frame
	check("foreign_ack_delivered_to_owner",foreign.owner.active_count()==0 and foreign.owner.fault_reason().is_empty())

	for threaded in [false,true]:
		var denied:=prepared();denied.owner.transport.confirmed=false
		if threaded:
			var reject_worker:=Thread.new()
			check("reject_worker_started",reject_worker.start(denied.owner._retire_render.bind(denied.id))==OK)
			reject_worker.wait_to_finish();await process_frame
		else:denied.owner._retire_render(denied.id)
		check("failed_proof_never_frees_"+str(threaded),denied.owner.active_count()==1 and denied.owner.fault_reason()==&"retirement_failed")

	var stale:=prepared()
	stale.owner._retire_render(stale.id)
	var fresh: Dictionary=stale.owner.slots.acquire().identity
	stale.owner._retired(stale.id,true)
	check("stale_ack_never_frees_new_lease",stale.owner.active_count()==1 and stale.owner.slots.slot_snapshot(fresh.slot_id).identity==fresh and stale.owner.fault_reason()==&"retirement_failed")
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"scope":"CPU ownership only: same-thread immediate ACK, foreign-thread marshaling, failed proof and stale lease. Real GPU transport verified separately."},"\t"))
	quit(1 if failed else 0)
