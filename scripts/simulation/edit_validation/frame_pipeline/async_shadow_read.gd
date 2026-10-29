extends RefCounted

# Controlled-tool CPU synchronization only; ordinary GPU work never enters here.
var owner
var revision:=0
var generation:=0
var full:=false
var registered:=[]
var received:={}
var registration_done:=false
var inject_failure:=false

func _init(entry, state_revision: int, epoch: int, all_fields: bool) -> void:
	owner=entry;revision=state_revision;generation=epoch;full=all_fields

func run_render() -> void:
	owner.call_deferred("_async_shadow_started",self)
	var error: StringName=&""
	if owner.closing or generation!=owner.generation or owner.solver.state_revision!=revision:
		error=&"shadow_request_cancelled"
	else:
		for field in (["sand","sediment","wetness","compaction"] if full else ["sand"]):
			var result: Error=ERR_UNAVAILABLE
			if inject_failure:inject_failure=false
			else:result=owner.solver.request_data(field,_arrived.bind(field))
			if result==OK:registered.append(field)
			else:error=&"shadow_readback_registration_failed"
	call_deferred("_registration_done",error)

func _registration_done(error: StringName) -> void:
	registration_done=true
	if not error.is_empty():owner._fail("GPU pipeline fatal: "+String(error))
	_finish_if_drained()

func _arrived(bytes: PackedByteArray, field: String) -> void:
	call_deferred("_record",bytes,field)

func _record(bytes: PackedByteArray, field: String) -> void:
	if received.has(field):return
	received[field]=true
	if owner.last_error.is_empty():owner._async_shadow_field(bytes,field,revision,generation)
	_finish_if_drained()

func _finish_if_drained() -> void:
	if registration_done and received.size()==registered.size():owner._async_shadow_finished(self)
