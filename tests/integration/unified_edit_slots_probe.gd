extends SceneTree

const Slots=preload("res://scripts/simulation/unified_edit/slots.gd")
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const W=preload("res://scripts/simulation/unified_edit/protocol.gd")
var checks: Array=[]
var failed:=false
var output:=""

func check(name: String, value: bool) -> void:
	checks.append({"name":name,"pass":value});failed=failed or not value
	print("UNIFIED_SLOTS ",name," ",value)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")

func packet(id: Dictionary, fatal: bool=false) -> PackedByteArray:
	return W.encode_completion(id,[],{"state_seq":1,"sim_tick":1,"revision":0,"state":L.CompletionState.FATAL if fatal else L.CompletionState.COMPLETE,"error_flags":16 if fatal else 0,"advanced_time_s":0.033,"actual_dt":0.033,"accepted_count":0,"rejected_count":0})

func instance() -> RefCounted:
	var slots:=Slots.new()
	check("initialize_"+str(checks.size()),slots.initialize("main_beach",9007199254740993).is_empty())
	return slots

func _run() -> void:
	var slots:=Slots.new()
	check("before_initialize",slots.acquire().error==&"slots_not_initialized")
	check("float_generation_rejected",not slots.initialize("main_beach",1.0).is_empty())
	check("initialize",slots.initialize("main_beach",9007199254740993).is_empty())
	check("reinitialize_rejected",not slots.initialize("main_beach",2).is_empty())
	var identities: Array=[]
	for index in L.WORK_SLOTS:
		var acquired:=slots.acquire();identities.append(acquired.identity)
		check("acquire_"+str(index),acquired.error.is_empty() and acquired.identity.generation==9007199254740993)
	check("three_slot_backpressure",slots.acquire().error==&"no_slot" and slots.active_count()==3)
	var first: Dictionary=identities[0]
	check("tick_rejects_edit_count",not slots.queued(first,[{}],L.WorkKind.WATER_TICK).is_empty())
	check("edit_rejects_empty",not slots.queued(first,[]).is_empty())
	check("queue_tick",slots.queued(first,[],L.WorkKind.WATER_TICK).is_empty())
	check("queued_cannot_cancel",not slots.cancel_unsubmitted(first))
	check("cannot_consume_queued",slots.consume(first).error==&"not_complete")
	check("cannot_retire_queued",not slots.retired(first))
	check("valid_tick_completion",slots.completed(packet(first),first).is_empty())
	check("duplicate_completion_rejected",not slots.completed(packet(first),first).is_empty())
	var consumed:=slots.consume(first)
	check("consume_result",consumed.error.is_empty() and not consumed.fatal and consumed.header.sim_tick==1)
	check("consume_does_not_free",slots.active_count()==3 and slots.acquire().error==&"no_slot")
	check("duplicate_consume_rejected",slots.consume(first).error==&"not_complete")
	check("render_retirement_frees",slots.retired(first) and slots.active_count()==2)
	var next: Dictionary=slots.acquire().identity
	check("same_slot_new_lease",next.slot_id==first.slot_id and next.lease_id>first.lease_id)
	check("stale_cannot_cancel_new_owner",not slots.cancel_unsubmitted(first) and slots.active_count()==3)
	check("stale_completion_ignored",slots.completed(packet(first),first)==&"stale_lease" and slots.fault_reason().is_empty())
	var escaped:=slots.slot_snapshot(next.slot_id);escaped.identity.generation=1;escaped.state=Slots.State.FREE
	check("snapshot_not_shared",slots.slot_snapshot(next.slot_id).identity.generation==9007199254740993 and slots.active_count()==3)
	check("cancel_unsubmitted",slots.cancel_unsubmitted(next))
	for index in [1,2]:check("cancel_remaining_"+str(index),slots.cancel_unsubmitted(identities[index]))
	slots.stop_admission()
	check("closed_and_empty_releasable",slots.can_release() and slots.acquire().error==&"closing")
	for mode in ["short","fatal","unknown","unrecorded"]:
		slots=instance();var id: Dictionary=slots.acquire().identity
		check("queue_"+mode,slots.queued(id,[],L.WorkKind.WATER_TICK).is_empty())
		if mode=="unrecorded":
			check("known_unrecorded_can_abandon",slots.abandon_unrecorded(id) and slots.active_count()==0 and slots.fault_reason().is_empty());continue
		if mode=="unknown":check("mark_unknown",slots.unknown(id,&"readback_submit_failed"))
		else:check("reject_"+mode,not slots.completed(PackedByteArray([0]) if mode=="short" else packet(id,true),id).is_empty())
		check("retain_"+mode,slots.active_count()==1 and slots.acquire().error==&"backend_failed")
		check("no_business_result_"+mode,slots.consume(id).error==&"not_complete")
		check("unconfirmed_cannot_abort_"+mode,not slots.abort_after_retired(id,false) and not slots.can_release())
		check("confirmed_retirement_can_abort_"+mode,slots.abort_after_retired(id,true) and slots.can_release())
		check("fault_not_reset_on_release_"+mode,slots.acquire().error==&"backend_failed")
	slots=Slots.new();check("maximum_counter_initializes",slots.initialize("main_beach",1,L.INT64_MAX,0).is_empty())
	check("no_identity_wrap",slots.acquire().error==&"identity_exhausted" and slots.can_release())
	slots=instance();var foreign: Dictionary=slots.acquire().identity
	foreign.domain_hash="1".repeat(64)
	check("foreign_domain_cannot_cancel",not slots.cancel_unsubmitted(foreign) and slots.active_count()==1)
	check("bad_slot_cannot_index",slots.completed(PackedByteArray(),{"generation":1,"batch_seq":1,"slot_id":99,"lease_id":1,"domain_hash":"1".repeat(64)})==&"stale_lease")
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"scope":"CPU work-slot state machine with synthetic packets; no GPU consumer proof or G2 acceptance"},"\t"))
	quit(1 if failed else 0)
