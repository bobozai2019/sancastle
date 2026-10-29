extends RefCounted

# One bounded whole-domain reader under the pipeline's admission barrier.
# It borrows existing RIDs; registration failure never authorizes early reuse.
const MomentumBytes=preload("res://scripts/simulation/unified_edit/momentum_bytes.gd")
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const MaterialCodec=preload("res://scripts/simulation/brushes/brush_material_state_codec.gd")
var phase: StringName=&"draining"
var scheduled:=false
var started:=false
var pending:=0
var finished:=false
var cancelled:=false
var unknown:=false
var error: StringName=&""
var raw: Dictionary={}
var expected_sizes: Dictionary={}
var records: Dictionary={}
var hold_delivery:=false
var held: Dictionary={}
var inject_registration_failure_once:=false
var inject_packet_fault_once:=""
var registered:=0
var _submitting:=false
var _readers_done:=false
var _proof_pending:=false
var _owner
var _callback: Callable
var metadata: Dictionary={}

func configure(owner, selection: Dictionary, callback: Callable) -> void:
	_owner=owner;_callback=callback
	metadata={"selection":selection.duplicate(true)}

func render_capture() -> void:
	if started:return
	started=true;phase=&"reading"
	if cancelled:error=&"checkpoint_cancelled";call_deferred("_readers_finished");return
	if _owner.boundary.enabled and not _owner.water.configure_boundary(_owner.water.tide,metadata.boundary_packets):error=&"checkpoint_boundary_upload";call_deferred("_readers_finished");return
	var images:={}
	for field in Codec.Old.FIELD_BYTES:
		if field in ["momentum_x","momentum_z"]:continue
		images["field/"+field]=_owner.state.textures[field] if field in ["rock","obstacle"] else _owner.state.textures[field][0]
		expected_sizes["field/"+field]=65536*Codec.Old.FIELD_BYTES[field]
	for field in Codec.Old.SPARE:
		if field in ["momentum_x","momentum_z"]:continue
		images["spare/"+field]=_owner.state.textures[field][1];expected_sizes["spare/"+field]=65536*Codec.Old.FIELD_BYTES[field]
	for pair in [["field",0],["spare",1]]:
		var key: String=pair[0]+"/momentum"
		images[key]=_owner.state.textures.momentum[pair[1]];expected_sizes[key]=MomentumBytes.PACKED_BYTES
	for index in 2:images["material/"+str(index)]=_owner.state.textures.mold_support[index];expected_sizes["material/"+str(index)]=65536*8
	if _owner.state.surface_wetness.is_valid():
		images.surface_wetness=_owner.state.surface_wetness;expected_sizes.surface_wetness=262144
	images.published_sand=_owner.state.published_sand;images.published_water=_owner.state.published_water;images.clock=_owner.transport.clock_texture
	for key in _owner.visuals.capture_images():
		images[key]=_owner.visuals.capture_images()[key]
		expected_sizes[key]=16384 if "gravel_" in key else (65536*4 if "bed_" in key else 65536*8)
	# Only native display histories participate in SANDUE06. Decorative plants
	# are regenerated from the restored completed bed/water for each generation.
	for field in ["foam","local_front","gravel"]:
		if not _owner.visuals.published.has(field):continue
		images["visual_view/"+field]=_owner.visuals.published[field];expected_sizes["visual_view/"+field]=16384 if field=="gravel" else 65536*8
	expected_sizes.published_sand=65536*4;expected_sizes.published_water=65536*4;expected_sizes.clock=4
	var buffers:={"control":[_owner.transport.control,128],"stamp":[_owner.state.published_stamp,32],"stroke":[_owner.executor.buffers.stroke,64]}
	if _owner.boundary.enabled:buffers.boundary_waves=[_owner.water.waves,2048]
	if _owner.visuals.gravel_enabled:buffers.display_active_count=[_owner.visuals.gravel_meta,4]
	for key in buffers:expected_sizes[key]=buffers[key][1]
	_submitting=true
	for key in images:
		pending+=1
		var status: Error=ERR_UNAVAILABLE
		if inject_registration_failure_once:inject_registration_failure_once=false
		else:status=_owner.transport.rd.texture_get_data_async(images[key],0,_arrived.bind(key))
		if status!=OK:pending-=1;error=&"checkpoint_readback_registration"
		else:registered+=1
	for key in buffers:
		pending+=1
		if _owner.transport.rd.buffer_get_data_async(buffers[key][0],_arrived.bind(key),0,buffers[key][1])!=OK:pending-=1;error=&"checkpoint_readback_registration"
		else:registered+=1
	_submitting=false;_maybe_finished()

func _arrived(bytes: PackedByteArray, key: String) -> void:
	if finished or not expected_sizes.has(key) or raw.has(key) or held.has(key):return
	if hold_delivery:held[key]=bytes;return
	if not inject_packet_fault_once.is_empty() and (inject_packet_fault_once=="truncate" or key=="field/rock"):
		var fault:=inject_packet_fault_once;inject_packet_fault_once="";bytes=bytes.duplicate()
		if fault=="truncate":bytes=bytes.slice(0,1)
		elif not bytes.is_empty():bytes[0]^=1
	if bytes.size()!=expected_sizes[key]:error=&"checkpoint_readback_size"
	raw[key]=bytes;records[key]={"bytes":bytes.size(),"sha256":_sha(bytes)};pending-=1;_maybe_finished()

func release_held_render() -> void:
	hold_delivery=false;var data:=held;held={}
	for key in data:_arrived(data[key],key)

func _maybe_finished() -> void:
	if _submitting or pending!=0 or _readers_done:return
	_readers_done=true;call_deferred("_readers_finished")

func _readers_finished() -> void:
	if finished:return
	if cancelled and error.is_empty():error=&"checkpoint_cancelled"
	if error.is_empty():_finish({"error":&"","raw":raw});return
	if registered==0:_finish({"error":error});return
	phase=&"proving";_proof_pending=true;RenderingServer.call_on_render_thread(_request_proof_render)

func _request_proof_render() -> void:_owner.transport.request_idle_proof(_proof_arrived)
func _proof_arrived(confirmed: bool) -> void:call_deferred("_proof_result",confirmed)

func _proof_result(confirmed: bool) -> void:
	_proof_pending=false
	if not confirmed:unknown=true;phase=&"unknown";return
	unknown=false;_finish({"error":error})

func retry_lifetime() -> void:
	if unknown and not _proof_pending:
		unknown=false;phase=&"proving";_proof_pending=true;RenderingServer.call_on_render_thread(_request_proof_render)

func cancel() -> void:cancelled=true

func finish_unrecorded(failure: StringName) -> void:
	if not scheduled and not started:_finish({"error":failure})

func _finish(result: Dictionary) -> void:
	if finished:return
	finished=true;phase=&"finished"
	var callback:=_callback;_callback=Callable();_owner=null
	callback.call(result)

func _sha(bytes: PackedByteArray) -> String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()

func assemble(owner, data: Dictionary) -> Dictionary:
	# Split only after the physical async requests completed and passed lengths.
	# Keep raw callback records/pending counts physical, not per logical channel.
	data=data.duplicate()
	for prefix in ["field","spare"]:
		var decoded:=MomentumBytes.split(data.get(prefix+"/momentum",PackedByteArray()))
		if not decoded.error.is_empty():return {"error":&"checkpoint_readback_size"}
		data[prefix+"/momentum_x"]=decoded.momentum_x;data[prefix+"/momentum_z"]=decoded.momentum_z
	if owner.visuals.gravel_enabled and data.display_active_count.decode_u32(0)!=owner.visuals.active_count:return {"error":&"checkpoint_display_count_mismatch"}
	if owner.boundary.enabled and data.boundary_waves!=owner.boundary.encode_packets(metadata.boundary_packets):return {"error":&"checkpoint_boundary_binding_mismatch"}
	var control: PackedByteArray=data.control
	for pair in [[8,"generation"],[16,"state_seq"],[24,"sim_tick"],[40,"revision"]]:
		if control.decode_s64(pair[0])!=metadata[pair[1]]:return {"error":&"checkpoint_completed_identity_mismatch"}
	if control.decode_float(32)!=metadata.advanced_time_s or data.clock!=control.slice(32,36):return {"error":&"checkpoint_completed_clock_mismatch"}
	var stamp: PackedByteArray=data.stamp
	for pair in [[0,8],[8,16],[16,40],[24,24]]:
		if stamp.decode_s64(pair[0])!=control.decode_s64(pair[1]):return {"error":&"checkpoint_publication_identity_mismatch"}
	if data.stroke.decode_u32(0)!=0:return {"error":&"checkpoint_active_stroke"}
	if data.published_sand!=data["field/sand"] or data.published_water!=data["field/water"]:return {"error":&"checkpoint_publication_fields_mismatch"}
	for field in ["rock","obstacle"]:
		if _sha(data["field/"+field])!=owner.accounting.immutable_hashes[field]:return {"error":&"checkpoint_immutable_field_mismatch"}
	var water: Dictionary=owner.accounting.water_ledger(control)
	if not water.error.is_empty():return water
	var fields:={};var spare:={}
	for field in Codec.Old.FIELD_BYTES:fields[field]=data["field/"+field]
	for field in Codec.Old.SPARE:spare[field]=data["spare/"+field]
	var value: Dictionary=metadata.duplicate(true)
	value.erase("end_id");value.erase("end_result");value.erase("material_ever_used");value.erase("inactive_foam");value.erase("boundary_packets")
	value.native={"version":3,"current_index":0,"fields":fields,"spare":spare,"material":MaterialCodec.make_record(data["material/0"],data["material/1"],metadata.material_ever_used,value.configuration.material.sha256),"foam":metadata.inactive_foam.duplicate(true),"histories":{},"control":control}
	if owner.visuals.foam_enabled:
		value.native.foam={"current_index":owner.visuals.foam_index}
		for index in 2:
			for field in ["foam_","bed_"]:value.native.foam[field+str(index)]=data["visual/"+field+str(index)]
		if data["visual_view/foam"]!=data["visual/foam_"+str(owner.visuals.foam_index)]:return {"error":&"checkpoint_visual_publication_mismatch"}
	if owner.visuals.front_enabled:
		value.native.histories.local_front=data["visual/local_front"]
		if data["visual_view/local_front"]!=value.native.histories.local_front:return {"error":&"checkpoint_visual_publication_mismatch"}
	if owner.visuals.gravel_enabled:
		value.visual_extensions.gravel_v1=owner.visuals.gravel_extension(value.generation,value.sim_tick,value.revision,data)
		if data["visual_view/gravel"]!=data["visual/gravel_"+str(owner.visuals.gravel_index)]:return {"error":&"checkpoint_visual_publication_mismatch"}
	if owner.state.surface_wetness.is_valid():value.visual_extensions.wet_sand_v1=Codec.Wet.record(value,data.surface_wetness)
	value.ledger=water.value
	var failure:=Codec.validate(value,value.configuration)
	if not failure.is_empty():return {"error":failure}
	owner.accounting.observe_water(control,value.ledger)
	return {"error":&"","checkpoint":value}
