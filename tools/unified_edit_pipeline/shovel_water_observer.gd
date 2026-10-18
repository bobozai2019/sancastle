extends "res://scripts/simulation/unified_edit/water_response.gd"
# Probe-only inherited numerical record/commit with timestamp spans, no new RIDs.
var original
var serial:=0
var sparse:=false
var sampled_frame:=-1
var sample_current:=true
var reference_packed:=false
var packed_phases:=false
var reference_velocity:=false
var calls: Array=[]
func adopt(value) -> void:
 original=value;rd=value.rd;owned=value.owned;kernels=value.kernels;source_hashes=value.source_hashes
 state=value.state;owner=value.owner;buffers=value.buffers;sets=value.sets
 reference_packed="--reference-packed" in OS.get_cmdline_user_args()
 packed_phases="--packed-phases" in OS.get_cmdline_user_args()
 reference_velocity="--reference-velocity" in OS.get_cmdline_user_args()
 if reference_packed:
  if not compile("packed_reference","res://shaders/simulation/edit_validation/water_packed_cached.glsl"):
   push_error(last_error);return
  kernels.packed=kernels.packed_reference
  sets.packed=binding("packed_reference",{0:buffers.input,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt})
func record(policy: int) -> Array:
 serial+=1
 sample_current=not sparse or sampled_frame!=Engine.get_process_frames()
 if sample_current:sampled_frame=Engine.get_process_frames()
 if sample_current:calls.append({"serial":serial,"at_us":Time.get_ticks_usec(),"frame":Engine.get_process_frames(),"policy":policy})
 var label:="shovel_water_"+str(serial)+"_total"
 if sample_current:rd.capture_timestamp(label+"_start")
 var result:=super.record(policy)
 if sample_current:rd.capture_timestamp(label+"_end")
 return result
func dispatch(name: String, binding_set: RID, groups: Vector3i, push: PackedByteArray=PackedByteArray()) -> void:
 var mode:=push.decode_u32(0) if push.size()>=4 else 999
 var label:="shovel_water_"+str(serial)+"_"+name+"_"+str(mode)
 if sample_current:rd.capture_timestamp(label+"_start")
 super.dispatch(name,binding_set,groups,push)
 if sample_current:rd.capture_timestamp(label+"_end")
func _legacy_dispatch(name: String, push: PackedByteArray) -> void:
 var label:="shovel_water_"+str(serial)+"_"+name
 if sample_current:rd.capture_timestamp(label+"_start")
 super._legacy_dispatch(name,push)
 if sample_current:rd.capture_timestamp(label+"_end")
func _packed_math(push: PackedByteArray) -> void:
 if not reference_packed:super._packed_math(push)
func _velocity_only() -> void:
 var label:="shovel_water_"+str(serial)+"_velocity_prepare_total"
 if sample_current:rd.capture_timestamp(label+"_start")
 if reference_velocity:
  var push:=PackedFloat32Array([0,0.125,0,0]).to_byte_array();push.encode_u32(0,256);push.encode_u32(12,1)
  _legacy_dispatch("displace",push)
 else:super._velocity_only()
 if sample_current:rd.capture_timestamp(label+"_end")
func _packed_phase(mode: int, push: PackedByteArray) -> void:
 var label:="shovel_water_"+str(serial)+"_packed_phase_"+str(mode)
 if sample_current and packed_phases:rd.capture_timestamp(label+"_start")
 super._packed_phase(mode,push)
 if sample_current and packed_phases:rd.capture_timestamp(label+"_end")
func release() -> void:
 original.release();original=null
 # The coarse observer installs us on the original executor as its response.
 # Drop our borrowed owner reference after teardown to avoid a probe-only cycle.
 owner=null;state=null;rd=null
