extends RefCounted

# Independent edit v5/native v3. No legacy shadow/prefix projection is written.
const Wire=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_protocol.gd")
const MaterialCodec=preload("res://scripts/simulation/brushes/brush_material_state_codec.gd")
const Gravel=preload("res://scripts/visual/gravel_checkpoint_codec.gd")
const BrushSelection=preload("res://scripts/simulation/brushes/brush_checkpoint_codec.gd")
const MAGIC="SANDGP05"
const CONTAINER_VERSION=1
const MAX_BYTES=32*1024*1024
# The display history is an unmodified float32 weighted centroid: up to 25 X
# taps, 9 Z taps, positive products/reductions, then division. The real GPU
# produces 255+1..4 ULP at the right edge. Bound each positive reduction path
# by gamma(40), plus four unit roundoffs for division; preserve raw bytes.
# This is validation roundoff headroom, not a spatial/visual parameter.
const FLOAT32_U=0.000000059604644775390625
const LOCAL_FRONT_GAMMA=40.0*FLOAT32_U/(1.0-40.0*FLOAT32_U)
const LOCAL_FRONT_COORD_MAX=255.0*(1.0+LOCAL_FRONT_GAMMA)/(1.0-LOCAL_FRONT_GAMMA)*(1.0+4.0*FLOAT32_U)
const FIELD_BYTES={"rock":4,"sand":4,"water":4,"momentum_x":4,"momentum_z":4,"sediment":4,"wetness":2,"compaction":2,"obstacle":1,"flux":16}
const SPARE=["sand","water","momentum_x","momentum_z","sediment","wetness","compaction","flux"]
const KEYS=["version","pipeline_protocol_version","grid_size","cell_size_m","domain_id","generation","state_seq","sim_tick","revision","advanced_time_s","highwater_id","ticket_id","configuration","simulation","ledger_precision","ledger","initial_sand_total_m3","nominal_upper_supply","selection","cohesion_yield_height_m","wave_requests","wave_highwater_id","wave_start_times","native","visual_extensions"]
const SIMULATION_KEYS=["enable_erosion","enable_brush_water","unrestricted_sand_tools","enable_structures","local_front_history","rise_front_history","contact_history","prescribed_tide_boundary"]
const LEDGER=["tool_inventory_m3","sand_source_m3","sand_sink_m3","water_source_m3","water_sink_m3"]

static func exact_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size():return false
	for key in keys:
		if not value.has(key):return false
	return true

static func number(value: Variant, low: float=0.0, high: float=INF) -> bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value)) and value>=low and value<=high

static func counter(value: Variant, minimum: int=0) -> bool:
	return typeof(value)==TYPE_INT and value>=minimum

static func validate(value: Dictionary, configuration: Dictionary={}) -> StringName:
	if not exact_keys(value,KEYS) or value.version!=5 or value.pipeline_protocol_version!=Wire.VERSION or value.grid_size!=256 or value.cell_size_m!=0.125:return &"invalid_pipeline_header"
	for key in ["version","pipeline_protocol_version","grid_size"]:
		if typeof(value[key])!=TYPE_INT:return &"invalid_pipeline_header"
	if typeof(value.domain_id)!=TYPE_STRING or value.domain_id not in ["main_beach","test1_capture","test1_backwash","test1_geometry"]:return &"invalid_pipeline_domain"
	for key in ["generation","state_seq","sim_tick","revision","highwater_id","ticket_id","wave_highwater_id"]:
		if not counter(value[key],1 if key=="generation" else 0):return &"invalid_pipeline_counter"
	if not number(value.advanced_time_s) or not number(value.initial_sand_total_m3) or not number(value.nominal_upper_supply) or not number(value.cohesion_yield_height_m,0.0,2.0):return &"invalid_pipeline_scalar"
	if not value.configuration is Dictionary or value.configuration.is_empty() or (not configuration.is_empty() and value.configuration!=configuration):return &"pipeline_configuration_mismatch"
	if value.configuration.get("async_pipeline_enabled")!=true or value.configuration.get("pipeline_protocol")!=Wire.VERSION or value.configuration.get("ledger_precision")!="approximate":return &"pipeline_configuration_mismatch"
	if not exact_keys(value.simulation,SIMULATION_KEYS):return &"invalid_pipeline_simulation"
	for key in SIMULATION_KEYS:
		if typeof(value.simulation[key])!=TYPE_BOOL:return &"invalid_pipeline_simulation"
	for key in ["enable_structures","rise_front_history","contact_history"]:
		if value.simulation[key]:return &"unsupported_pipeline_history"
	if value.ledger_precision!="approximate" or not exact_keys(value.ledger,LEDGER):return &"invalid_pipeline_ledger"
	for key in LEDGER:
		if not number(value.ledger[key]):return &"invalid_pipeline_ledger"
	if not exact_keys(value.selection,["policy","speed","brush"]) or typeof(value.selection.policy)!=TYPE_INT or value.selection.policy not in [0,1,2,3] or not number(value.selection.speed,-1.0,1.0):return &"invalid_pipeline_selection"
	var selection_error:=BrushSelection.selection_error(value.selection.brush)
	if not selection_error.is_empty():return selection_error
	var error:=validate_native(value)
	if not error.is_empty():return error
	if not value.wave_requests is Array or value.wave_requests.size()>128 or not value.wave_start_times is Dictionary or value.wave_start_times.size()!=value.wave_requests.size():return &"invalid_pipeline_waves"
	var previous:=0
	for wave in value.wave_requests:
		if not wave is Dictionary or not counter(wave.get("request_id"),1) or wave.request_id<=previous or wave.request_id>value.wave_highwater_id or not counter(wave.get("generation"),1) or wave.generation!=value.generation or typeof(wave.get("domain_id")) not in [TYPE_STRING,TYPE_STRING_NAME] or String(wave.domain_id)!=value.domain_id or not counter(wave.get("start_tick"),1) or typeof(wave.get("seed"))!=TYPE_INT or not value.wave_start_times.has(wave.request_id) or not number(value.wave_start_times[wave.request_id],-INF):return &"invalid_pipeline_waves"
		var profile: Variant=wave.get("profile_id")
		if profile not in [&"small_packet",&"test_packet"] or not number(wave.get("amplitude_m"),0.0,0.06 if profile==&"small_packet" else 0.20) or not number(wave.get("duration_s"),0.5,3.0 if profile==&"small_packet" else 6.0):return &"invalid_pipeline_waves"
		previous=wave.request_id
	if not exact_keys(value.visual_extensions,["gravel_v1"]):return &"invalid_pipeline_visuals"
	# Reuse the independent gravel subrecord validator, never a v4 edit prefix.
	var projection={"visual_extensions":value.visual_extensions,"shadow":{"domain_id":value.domain_id,"generation":value.generation},"tick":value.sim_tick,"revision":value.revision}
	return Gravel.validate(projection,{},value.domain_id)

static func validate_native(value: Dictionary) -> StringName:
	var native: Variant=value.native
	if not exact_keys(native,["version","current_index","fields","spare","material","foam","histories","control"]) or native.version!=3 or native.current_index!=0:return &"invalid_pipeline_native_header"
	if typeof(native.version)!=TYPE_INT or typeof(native.current_index)!=TYPE_INT:return &"invalid_pipeline_native_header"
	if not exact_keys(native.fields,FIELD_BYTES.keys()) or not exact_keys(native.spare,SPARE):return &"invalid_pipeline_native_fields"
	for group in [native.fields,native.spare]:
		for field in group:
			var bytes: Variant=group[field]
			if not bytes is PackedByteArray or bytes.size()!=65536*int(FIELD_BYTES[field]):return &"invalid_pipeline_field_size"
			if field=="obstacle":
				for v in bytes:
					if v not in [0,255]:return &"invalid_pipeline_obstacle"
			elif field in ["wetness","compaction"]:
				for i in 65536:
					if not number(bytes.decode_half(i*2),0.0,1.0):return &"invalid_pipeline_half"
			else:
				for v in bytes.to_float32_array():
					if not number(v,0.0 if field in ["sand","water","sediment"] else -INF):return &"invalid_pipeline_float"
	var material_error:=MaterialCodec.validate(native.material,native.fields.sand,native.spare.sand,FileAccess.get_sha256("res://assets/brushes/molded_material_candidate.json"))
	if not material_error.is_empty():return material_error
	if not exact_keys(native.foam,["current_index","foam_0","foam_1","bed_0","bed_1"]) or typeof(native.foam.current_index)!=TYPE_INT or native.foam.current_index not in [0,1]:return &"invalid_pipeline_foam"
	for key in ["foam_0","foam_1","bed_0","bed_1"]:
		var bytes: Variant=native.foam[key]
		if not bytes is PackedByteArray or bytes.size()!=65536*(8 if key.begins_with("foam") else 4):return &"invalid_pipeline_foam"
		var floats: PackedFloat32Array=bytes.to_float32_array()
		for i in floats.size():
			if not number(floats[i],0.0 if key.begins_with("foam") else -INF,1.0 if key.begins_with("foam") and i%2==0 else INF):return &"invalid_pipeline_foam"
	if not exact_keys(native.histories,["local_front"] if value.simulation.local_front_history else []):return &"invalid_pipeline_histories"
	if value.simulation.local_front_history:
		var bytes: Variant=native.histories.local_front
		if not bytes is PackedByteArray or bytes.size()!=65536*8:return &"invalid_pipeline_local_front"
		var floats: PackedFloat32Array=bytes.to_float32_array()
		for i in floats.size():
			if not number(floats[i],0.0,LOCAL_FRONT_COORD_MAX if i%2==0 else INF):return &"invalid_pipeline_local_front"
	var c: Variant=native.control
	if not c is PackedByteArray or c.size()!=Wire.CONTROL_BYTES or c.decode_u32(0)!=Wire.VERSION or c.decode_u32(4)!=0:return &"invalid_pipeline_control"
	for pair in [[8,"generation"],[16,"state_seq"],[24,"sim_tick"],[40,"revision"]]:
		if c.decode_u64(pair[0])!=value[pair[1]]:return &"pipeline_control_identity_mismatch"
	if c.decode_float(32)!=value.advanced_time_s or not number(c.decode_float(36)):return &"pipeline_control_time_mismatch"
	if c.decode_u32(80)>64 or c.decode_u32(84)>1:return &"invalid_pipeline_control_cfl"
	for offset in [88,92]:
		if not number(c.decode_float(offset)):return &"invalid_pipeline_control_ledger"
	for offset in [96,100]:
		if not number(c.decode_float(offset),-INF):return &"invalid_pipeline_control_boundary"
	return &""

static func digest(bytes: PackedByteArray) -> PackedByteArray:
	var hash:=HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256)!=OK:return PackedByteArray()
	hash.update(bytes)
	return hash.finish()

static func save(path: String, checkpoint: Dictionary) -> StringName:
	var error:=validate(checkpoint)
	if not error.is_empty():return error
	if FileAccess.file_exists(path):return &"already_exists"
	var payload:=var_to_bytes(checkpoint)
	if payload.is_empty() or payload.size()>MAX_BYTES:return &"invalid_payload_size"
	var hash:=digest(payload)
	if hash.size()!=32:return &"hash_init_failed"
	var temporary:=path+".tmp."+str(Time.get_ticks_usec())
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return &"open_failed"
	file.store_buffer(MAGIC.to_ascii_buffer());file.store_32(CONTAINER_VERSION);file.store_32(payload.size());file.store_buffer(hash);file.store_buffer(payload);file.flush()
	var write_error:=file.get_error()
	file.close()
	if write_error!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return &"write_failed"
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return &"rename_failed"
	return &""

static func load(path: String, configuration: Dictionary={}) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"error":&"open_failed"}
	if file.get_length()<48 or file.get_length()>48+MAX_BYTES:return {"error":&"invalid_file_size"}
	var magic:=file.get_buffer(8).get_string_from_ascii()
	var version:=file.get_32()
	var count:=file.get_32()
	if magic!=MAGIC or version!=CONTAINER_VERSION or count<1 or file.get_length()!=48+count:return {"error":&"invalid_header"}
	var checksum:=file.get_buffer(32)
	var payload:=file.get_buffer(count)
	file.close()
	if digest(payload)!=checksum:return {"error":&"checksum_mismatch"}
	var value: Variant=bytes_to_var(payload)
	if not value is Dictionary:return {"error":&"invalid_payload"}
	var error:=validate(value,configuration)
	return {"error":error,"checkpoint":value} if error.is_empty() else {"error":error}
