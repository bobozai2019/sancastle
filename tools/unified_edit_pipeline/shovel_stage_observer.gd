extends "res://scripts/simulation/unified_edit/executor.gd"
# Probe-only: same inherited record/_pass numerical work, extra timestamps.
var original
var cpu_records: Array=[]
var serial:=0
var command_serial:=0
func adopt(value) -> void:
 original=value
 rd=value.rd;owned=value.owned;kernels=value.kernels;source_hashes=value.source_hashes
 state=value.state;transport=value.transport;buffers=value.buffers;images=value.images;sets=value.sets;response=value.response
 recorded_commands=value.recorded_commands;traces=value.traces
func record(input: RID, control: RID, output: RID, count: int, commands: Array) -> void:
 serial+=1
 var label:="uep_cost_edit_"+str(serial);rd.capture_timestamp(label+"_start")
 var started:=Time.get_ticks_usec()
 super.record(input,control,output,count,commands)
 cpu_records.append({"serial":serial,"commands":count,"command_ids":commands.map(func(value):return value.command_id),"control_kinds":commands.map(func(value):return value.control_kind),"record_us":Time.get_ticks_usec()-started})
 rd.capture_timestamp(label+"_end")
func _pass(slot: int, index: int, mode: int, groups: int, dispatches: int, trace: Array, phase: int=0) -> void:
 if mode==0:command_serial+=1
 var label:="shovel_stage_"+str(command_serial)+"_"+str(mode)+"_"+str(phase)
 rd.capture_timestamp(label+"_start")
 super._pass(slot,index,mode,groups,dispatches,trace,phase)
 rd.capture_timestamp(label+"_end")
func release() -> void:original.release()
