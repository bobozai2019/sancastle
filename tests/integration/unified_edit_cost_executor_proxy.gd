extends "res://scripts/simulation/unified_edit/executor.gd"

# Observer-only decorator installed after initialization on the render thread.
# It retains the already initialized executor and delegates the sole record call.
# It adds no kernel, command, authority write, scheduling or resource ownership.
var original
var enabled:=true
var cpu_records: Array=[]
var serial:=0

func adopt(value) -> void:
	original=value
	# Keep the already initialized stage's exact resource references. No
	# initialize/recompile/record operation is performed during observation setup.
	rd=value.rd;owned=value.owned;kernels=value.kernels;source_hashes=value.source_hashes;last_error=value.last_error
	state=value.state;transport=value.transport;buffers=value.buffers;images=value.images;sets=value.sets
	recorded_commands=value.recorded_commands;traces=value.traces;response=value.response
func record(input: RID, control: RID, output: RID, count: int, commands: Array) -> void:
	serial+=1
	var label:="uep_cost_edit_"+str(serial)
	if enabled:original.rd.capture_timestamp(label+"_start")
	var start:=Time.get_ticks_usec()
	original.record(input,control,output,count,commands)
	recorded_commands=original.recorded_commands
	cpu_records.append({"serial":serial,"commands":count,"command_ids":commands.map(func(value):return value.command_id),"control_kinds":commands.map(func(value):return value.control_kind),"record_us":Time.get_ticks_usec()-start})
	if enabled:original.rd.capture_timestamp(label+"_end")
func release() -> void:original.release()
