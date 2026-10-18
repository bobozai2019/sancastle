extends "res://scripts/simulation/unified_edit/water_response.gd"
# Probe-only inherited numerical record/commit with timestamp spans, no new RIDs.
var original
var serial:=0
var sparse:=false
var sampled_frame:=-1
var sample_current:=true
func adopt(value) -> void:
 original=value;rd=value.rd;owned=value.owned;kernels=value.kernels;source_hashes=value.source_hashes
 state=value.state;owner=value.owner;buffers=value.buffers;sets=value.sets
func record(policy: int) -> Array:
 serial+=1
 sample_current=not sparse or sampled_frame!=Engine.get_process_frames()
 if sample_current:sampled_frame=Engine.get_process_frames()
 var label:="shovel_water_"+str(serial)+"_total"
 if sample_current:rd.capture_timestamp(label+"_start")
 var result:=super.record(policy)
 if sample_current:rd.capture_timestamp(label+"_end")
 return result
func dispatch(name: String, binding_set: RID, groups: Vector3i, push: PackedByteArray=PackedByteArray()) -> void:
 var mode:=push.decode_u32(0) if push.size()>=4 else 999
 var label:="shovel_water_"+str(serial)+"_response_"+str(mode)
 if sample_current:rd.capture_timestamp(label+"_start")
 super.dispatch(name,binding_set,groups,push)
 if sample_current:rd.capture_timestamp(label+"_end")
func _legacy_dispatch(name: String, push: PackedByteArray) -> void:
 var label:="shovel_water_"+str(serial)+"_"+name
 if sample_current:rd.capture_timestamp(label+"_start")
 super._legacy_dispatch(name,push)
 if sample_current:rd.capture_timestamp(label+"_end")
func release() -> void:original.release()
