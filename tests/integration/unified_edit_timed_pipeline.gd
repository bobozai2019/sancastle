extends "res://scripts/simulation/unified_edit/pipeline.gd"

# Probe-only CPU boundaries. No timestamp participates in scheduling or physics.
var queued_us: Dictionary={}
var recorded: Array[Dictionary]=[]
var consumed: Dictionary={}

func _enqueue(frozen: Dictionary) -> Dictionary:
	var value:=super._enqueue(frozen)
	if value.accepted:queued_us[frozen.command_id]=Time.get_ticks_usec()
	return value

func _record_work(input: RID, control: RID, output: RID, count: int, kind: int, dt: float, commands: Array) -> void:
	var start:=Time.get_ticks_usec();var ids:=[]
	for command in commands:ids.append(command.command_id)
	super._record_work(input,control,output,count,kind,dt,commands)
	call_deferred("_record_observation",ids,kind,start,Time.get_ticks_usec())

func _record_observation(ids: Array, kind: int, start: int, finish: int) -> void:
	recorded.append({"ids":ids.duplicate(),"kind":kind,"record_start_us":start,"record_end_us":finish})

func _poll() -> void:
	super._poll()
	for id in _results:
		if consumed.has(id):continue
		var result: Dictionary=_results[id]
		if result.has("state_seq"):consumed[id]={"observed_complete_us":Time.get_ticks_usec(),"state_seq":result.state_seq,"tick":result.applied_tick}
