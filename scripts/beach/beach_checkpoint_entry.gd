extends "res://scripts/beach/beach_lab_entry.gd"

const CheckpointFoam=preload("res://scripts/simulation/edit_validation/checkpoint_foam_field.gd")
const NativeCodec=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")
const BeachCodec=preload("res://scripts/simulation/edit_validation/beach_native_codec.gd")
var capture_raw := {}
var capture_original := {}
var capture_flushed := false
signal beach_capture_submitted
var observe_beach_capture := false
var pending_beach_native_readbacks := 0
var beach_native_callback_us := -1
var native_restore_complete := false
var native_ready_published := false

func _supports_native_version(version: int) -> bool:
	return version==1

func _restore_native_extensions(target_solver, native: Dictionary) -> bool:
	return native.version==1

func _capture_native_extensions(revision: int, token: int) -> void:
	pass

func _native_capture_raw_count() -> int:
	return 22

func _is_native_extension_field(field: String) -> bool:
	return false

func _assemble_native_record(fields: Dictionary, spare: Dictionary, foam: Dictionary) -> Dictionary:
	return {"version":1,"fields":fields,"spare":spare,"current_index":solver.current_index,"foam":foam}

func _validate_checkpoint_extensions(candidate:Dictionary) -> StringName:
	return _checkpoint_runtime_profile_error()

func _checkpoint_runtime_profile_error() -> StringName:
	# Native checkpoints restore the release erosion constants. Probe overrides
	# are not serialized, so accepting them would silently change the simulation.
	if sediment_coupler!=null and (
			sediment_coupler.capacity_per_speed_s!=SandcastleGpuSedimentCoupler.CAPACITY_PER_SPEED_S or
			sediment_coupler.erosion_rate_per_s!=SandcastleGpuSedimentCoupler.EROSION_RATE_PER_S or
			sediment_coupler.deposition_rate_per_s!=SandcastleGpuSedimentCoupler.DEPOSITION_RATE_PER_S):
		return &"unsupported_checkpoint_erosion_profile"
	return &""

func _mark_ready(token: int) -> void:
	if replay_checkpoint.has("gpu_beach_native") and not native_restore_complete: return
	if native_ready_published: return
	super._mark_ready(token)
	if ready_for_ticks: native_ready_published=true

func _publish_textures() -> void:
	if replay_checkpoint.has("gpu_beach_native") and not native_restore_complete: return
	super._publish_textures()

func _native_capture_request(texture: RID, field: String, revision: int, token: int) -> void:
	pending_beach_native_readbacks+=1
	if _request_beach_capture(texture,_on_checkpoint_field.bind(field,revision,token))!=OK:
		pending_beach_native_readbacks-=1;call_deferred("_fail","beach native capture request failed")

func _request_beach_capture(texture: RID, callback: Callable) -> Error:
	return solver.rd.texture_get_data_async(texture,0,callback)

func _on_checkpoint_field(data: PackedByteArray, field: String, revision: int, token: int) -> void:
	pending_beach_native_readbacks-=1;beach_native_callback_us=Time.get_ticks_usec()
	super._on_checkpoint_field(data,field,revision,token)

func _notify_beach_capture() -> void: beach_capture_submitted.emit()

func _create_foam_field() -> SandcastleGpuFoamField:
	var field=CheckpointFoam.new()
	if replay_checkpoint.has("gpu_beach_native"): field.native_history=replay_checkpoint.gpu_beach_native.foam.duplicate(true)
	return field

func _ready() -> void:
	if replay_checkpoint.has("gpu_beach_native"):
		var error:=BeachCodec.validate(replay_checkpoint)
		if error.is_empty() and not _supports_native_version(replay_checkpoint.gpu_beach_native.version): error=&"unsupported_native_version"
		if not error.is_empty(): last_error=String(error);push_error(last_error);return
	super._ready()

func _render_setup(domain: SandWaterDomain, token: int) -> void:
	super._render_setup(domain,token)
	if not replay_checkpoint.has("gpu_beach_native") or solver==null or closing or token!=generation: return
	if not solver.restore_native_fields(replay_checkpoint.gpu_beach_native.fields,replay_checkpoint.revision,replay_checkpoint.gpu_beach_native.spare,replay_checkpoint.gpu_beach_native.current_index):
		call_deferred("_fail","beach native restore failed");return
	if not _restore_native_extensions(solver,replay_checkpoint.gpu_beach_native):
		call_deferred("_fail","beach native extension restore failed");return
	native_restore_complete=true
	_publish_textures()
	call_deferred("_mark_ready",token)

func _start_checkpoint_capture() -> void:
	capture_raw.clear();capture_original.clear();capture_flushed=false
	var profile_error:=_checkpoint_runtime_profile_error()
	if not profile_error.is_empty():
		last_save_error=profile_error;pending_save_path="";checkpoint_capture_pending=false;checkpoint_capture.clear();return
	super._start_checkpoint_capture()

func _render_capture_checkpoint(revision: int, token: int) -> void:
	if closing or token!=generation or solver.state_revision!=revision: return
	if prototype_contact_history_field or prototype_rise_front_field:
		call_deferred("_fail","unsupported beach extra history");return
	for field in ["water","momentum_x","momentum_z"]:
		_native_capture_request(solver.current_texture(field),field,revision,token)
	if foam_field!=null: _native_capture_request(foam_field.textures[foam_field.current_index],"foam_history",revision,token)
	if local_front_field!=null: _native_capture_request(local_front_field.texture,"local_front_history",revision,token)
	for field in NativeCodec.FIELD_BYTES:
		_native_capture_request(solver.current_texture(field),"raw_"+field,revision,token)
	for field in ["sand","water","momentum_x","momentum_z","sediment","wetness","compaction","flux"]:
		_native_capture_request(solver.textures[field][1-solver.current_index],"spare_"+field,revision,token)
	for index in 2:
		_native_capture_request(foam_field.textures[index],"foam_%d" % index,revision,token)
		_native_capture_request(foam_field.bed_textures[index],"bed_%d" % index,revision,token)
	_capture_native_extensions(revision,token)
	if observe_beach_capture: call_deferred("_notify_beach_capture")

func _checkpoint_field_ready(data: PackedByteArray, field: String, revision: int, token: int) -> void:
	if closing or token!=generation or not checkpoint_capture_pending or checkpoint_capture.get("revision",-1)!=revision or capture_flushed: return
	if field.begins_with("raw_") or field.begins_with("spare_") or field.begins_with("foam_") and field!="foam_history" or field.begins_with("bed_") or _is_native_extension_field(field):
		capture_raw[field]=data
	else: capture_original[field]=data
	if capture_raw.size()!=_native_capture_raw_count() or capture_original.size()!=(3+(1 if foam_field!=null else 0)+(1 if local_front_field!=null else 0)): return
	var fields: Dictionary={};var spare: Dictionary={};var foam: Dictionary={"current_index":foam_field.current_index}
	for key in capture_raw:
		if _is_native_extension_field(key): continue
		if key.begins_with("raw_"): fields[key.trim_prefix("raw_")]=capture_raw[key]
		elif key.begins_with("spare_"): spare[key.trim_prefix("spare_")]=capture_raw[key]
		else: foam[key]=capture_raw[key]
	checkpoint_capture.gpu_beach_native=_assemble_native_record(fields,spare,foam)
	capture_flushed=true
	var candidate: Dictionary=checkpoint_capture.duplicate(false)
	candidate.fields={}
	for key in ["water","momentum_x","momentum_z"]: candidate.fields[key]=capture_original[key].to_float32_array()
	candidate.foam_history=capture_original.foam_history.to_float32_array()
	var error:=BeachCodec.validate(candidate)
	if not error.is_empty(): _fail("beach checkpoint validation: "+String(error));return
	error=_validate_checkpoint_extensions(candidate)
	if not error.is_empty():
		last_save_error=error;pending_save_path="";checkpoint_capture_pending=false;checkpoint_capture.clear();return
	for key in capture_original: super._checkpoint_field_ready(capture_original[key],key,revision,token)
