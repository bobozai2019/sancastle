extends RefCounted

const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Old=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd")
const Gravel=preload("res://scripts/visual/gravel_checkpoint_codec.gd")
const Selection=preload("res://scripts/simulation/brushes/brush_checkpoint_codec.gd")
const I=preload("res://scripts/simulation/unified_edit/intent.gd")
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const Legacy=preload("res://scripts/simulation/unified_edit/legacy_sources.gd")
const UnitHalf=preload("res://scripts/simulation/unified_edit/unit_half.gd")
const MAGIC="SANDUE06"
const VERSION:=6
const NATIVE_VERSION:=3 # Existing physical fields/control layout is retained.
const CONTAINER_VERSION:=1
const MAX_BYTES:=32*1024*1024
const KEYS=["version","protocol_family","pipeline_protocol_version","grid_size","cell_size_m","domain_id","generation","state_seq","sim_tick","revision","advanced_time_s","highwater_id","ticket_id","configuration","simulation","ledger_precision","ledger","initial_sand_total_m3","nominal_upper_supply","selection","cohesion_yield_height_m","wave_requests","wave_highwater_id","wave_start_times","native","visual_extensions","source_provenance"]
const PRECISION="mixed_operation_v1"

static func validate(value: Dictionary, configuration: Dictionary, verify_configuration_disk: bool=true) -> StringName:
	var error:=Config.validate(configuration,verify_configuration_disk)
	if not error.is_empty():return error
	if not Config.exact(value,KEYS) or typeof(value.version)!=TYPE_INT or value.version!=VERSION or value.protocol_family!=Config.FAMILY or typeof(value.pipeline_protocol_version)!=TYPE_INT or value.pipeline_protocol_version!=L.VERSION or typeof(value.grid_size)!=TYPE_INT or value.grid_size!=256 or value.cell_size_m!=0.125:return &"invalid_unified_checkpoint_header"
	if value.domain_id!=configuration.domain_id or typeof(value.domain_id)!=TYPE_STRING:return &"checkpoint_domain_mismatch"
	for key in ["generation","state_seq","sim_tick","revision","highwater_id","ticket_id","wave_highwater_id"]:
		if not I.counter(value[key],1 if key=="generation" else 0):return &"invalid_checkpoint_counter"
	if not value.configuration is Dictionary:return &"invalid_configuration"
	if value.configuration.get("configuration_hash")!=configuration.configuration_hash:return &"checkpoint_configuration_mismatch"
	error=Config.validate(value.configuration)
	if not error.is_empty():return error
	if not Config.exact(value.simulation,Old.SIMULATION_KEYS):return &"invalid_checkpoint_simulation"
	for key in Old.SIMULATION_KEYS:
		if typeof(value.simulation[key])!=TYPE_BOOL:return &"invalid_checkpoint_simulation"
		if key!="prescribed_tide_boundary" and value.simulation[key]!=configuration.simulation[key]:return &"checkpoint_simulation_mismatch"
	if value.ledger_precision!=PRECISION or not Config.exact(value.ledger,Old.LEDGER) or value.ledger.tool_inventory_m3!=0.0:return &"invalid_checkpoint_ledger"
	for amount in value.ledger.values():
		if not Old.number(amount):return &"invalid_checkpoint_ledger"
	for key in ["advanced_time_s","initial_sand_total_m3","nominal_upper_supply"]:
		if not Old.number(value[key]):return &"invalid_checkpoint_scalar"
	if not Old.number(value.cohesion_yield_height_m,0.0,2.0) or not Config.exact(value.selection,["policy","speed","brush"]) or typeof(value.selection.policy)!=TYPE_INT or value.selection.policy not in [0,1,2,3] or not Old.number(value.selection.speed,-1.0,1.0):return &"invalid_checkpoint_selection"
	error=Selection.selection_error(value.selection.brush)
	if not error.is_empty():return error
	# This calls the unchanged native-v3 field/material/foam/control validator.
	# The native version is genuinely still 3: no fake old header is constructed.
	error=Old.validate_native(value)
	if not error.is_empty():return error
	# Host decode_half may flush subnormals; reject illegal native bits directly.
	for group in [value.native.fields,value.native.spare]:
		for field in ["wetness","compaction"]:
			if not UnitHalf.decode(group[field]).error.is_empty():return &"invalid_pipeline_half"
	for offset in range(48,72,4):
		if value.native.control.decode_u32(offset)!=0:return &"unsupported_control_extension"
	for offset in range(104,L.CONTROL_BYTES,4):
		if value.native.control.decode_u32(offset)!=0:return &"unsupported_control_extension"
	if not value.wave_requests is Array or value.wave_requests.size()>128 or not value.wave_start_times is Dictionary or value.wave_start_times.size()!=value.wave_requests.size():return &"invalid_checkpoint_waves"
	var previous:=0
	for wave in value.wave_requests:
		if not wave is Dictionary or not I.counter(wave.get("request_id"),1) or wave.request_id<=previous or wave.request_id>value.wave_highwater_id or not I.counter(wave.get("generation"),1) or wave.generation!=value.generation or wave.get("domain_id")!=value.domain_id or not I.counter(wave.get("start_tick"),1) or typeof(wave.get("seed"))!=TYPE_INT or not value.wave_start_times.has(wave.request_id) or not Old.number(value.wave_start_times[wave.request_id],-INF):return &"invalid_checkpoint_wave"
		if wave.get("profile_id") not in [&"small_packet",&"test_packet"] or not Old.number(wave.get("amplitude_m"),0.0,0.06 if wave.profile_id==&"small_packet" else 0.20) or not Old.number(wave.get("duration_s"),0.5,3.0 if wave.profile_id==&"small_packet" else 6.0):return &"invalid_checkpoint_wave"
		previous=wave.request_id
	if not Config.exact(value.visual_extensions,["gravel_v1"]) or not value.visual_extensions.gravel_v1 is Dictionary or value.visual_extensions.gravel_v1.get("enabled")!=configuration.effects.gravel_enabled:return &"checkpoint_visual_configuration_mismatch"
	var projection:={"visual_extensions":value.visual_extensions,"shadow":{"domain_id":value.domain_id,"generation":value.generation},"tick":value.sim_tick,"revision":value.revision}
	error=Gravel.validate(projection,{},value.domain_id)
	if not error.is_empty():return error
	var provenance: Variant=value.source_provenance
	if not Config.exact(provenance,["format","path","sha256","configuration","trusted_fixture","original_prefix","policies"]):return &"invalid_checkpoint_provenance"
	if provenance.format not in ["native_v6","edit5_native3","edit4_native2"] or typeof(provenance.path)!=TYPE_STRING or not provenance.configuration is Dictionary or not provenance.trusted_fixture is Dictionary or not provenance.original_prefix is Array or not provenance.policies is Dictionary:return &"invalid_checkpoint_provenance"
	if provenance.format!="native_v6" and (not WireHash(provenance.sha256) or provenance.configuration.is_empty()):return &"invalid_checkpoint_provenance"
	return &""

static func WireHash(value: Variant) -> bool:
	return preload("res://scripts/simulation/unified_edit/protocol.gd").hash_valid(value,true)

static func project_validated_legacy(inspected: Dictionary, configuration: Dictionary) -> Dictionary:
	if not inspected.has("error") or not inspected.error.is_empty() or not inspected.get("requires_candidate_build",false):return {"error":&"unvalidated_legacy_projection"}
	if not inspected.get("checkpoint") is Dictionary or not inspected.get("provenance") is Dictionary or not inspected.provenance.get("configuration") is Dictionary or typeof(inspected.get("format"))!=TYPE_STRING:return {"error":&"unvalidated_legacy_projection"}
	var legacy_error:=Legacy.validate_data(inspected.checkpoint,inspected.format,inspected.provenance.configuration,inspected.get("enable_erosion",true))
	if not legacy_error.is_empty():return {"error":legacy_error}
	var error:=Config.validate(configuration,true)
	if not error.is_empty():return {"error":error}
	var old: Dictionary=inspected.checkpoint
	var value: Dictionary
	var provenance: Dictionary=inspected.provenance.duplicate(true)
	provenance.original_prefix=[];provenance.policies={}
	if inspected.format=="edit5_native3":
		value=old.duplicate(true)
		value.configuration=configuration.duplicate(true)
		provenance.policies={"clock":"preserve_actual_f32","state_seq":"preserve","ledger":"preserve_approximate_history_and_future_operation_policy","native":"preserve_v3_raw_fields"}
	elif inspected.format=="edit4_native2":
		if old.shadow.domain_id!=configuration.domain_id or inspected.enable_erosion!=configuration.simulation.enable_erosion:return {"error":&"legacy_domain_or_erosion_mismatch"}
		var simulation: Dictionary=configuration.simulation.duplicate(true)
		simulation.prescribed_tide_boundary=old.tick>0
		var histories:={}
		if simulation.local_front_history:
			if not old.get("local_front_history") is PackedFloat32Array:return {"error":&"missing_legacy_local_front"}
			histories.local_front=old.local_front_history.to_byte_array()
		var time: float=PackedFloat32Array([float(old.tick)/30.0])[0]
		var control:=PackedByteArray();control.resize(L.CONTROL_BYTES)
		control.encode_u32(0,1);control.encode_s64(8,old.shadow.generation);control.encode_s64(24,old.tick);control.encode_float(32,time);control.encode_s64(40,old.revision)
		var ticket:=0
		for row in old.gpu_beach_edit.prefix:ticket=maxi(ticket,int(row.result.get("ticket_id",0)))
		var clocks:={}
		for wave in old.wave_requests:clocks[wave.request_id]=(float(wave.start_tick)-1.5)/30.0
		var initial: float=old.gpu_beach_edit.ledger.tool_inventory_m3-old.gpu_beach_edit.ledger.sand_source_m3+old.gpu_beach_edit.ledger.sand_sink_m3
		for field in ["sand","sediment"]:
			for amount in old.gpu_beach_native.fields[field].to_float32_array():initial+=float(amount)*0.015625
		value={"grid_size":256,"cell_size_m":0.125,"domain_id":String(old.shadow.domain_id),"generation":old.shadow.generation,"state_seq":0,"sim_tick":old.tick,"revision":old.revision,"advanced_time_s":time,"highwater_id":old.highwater_id,"ticket_id":ticket,"configuration":configuration.duplicate(true),"simulation":simulation,"ledger":old.gpu_beach_edit.ledger.duplicate(true),"initial_sand_total_m3":initial,"nominal_upper_supply":0.0,"selection":{"policy":old.gpu_beach_edit.selection.policy,"speed":old.gpu_beach_edit.selection.speed,"brush":old.gpu_beach_edit.selection.brush.duplicate(true)},"cohesion_yield_height_m":old.sand_cohesion_yield_height_m,"wave_requests":old.wave_requests.duplicate(true),"wave_highwater_id":old.wave_highwater_id,"wave_start_times":clocks,"native":{"version":3,"current_index":0,"fields":old.gpu_beach_native.fields.duplicate(true),"spare":old.gpu_beach_native.spare.duplicate(true),"material":old.gpu_beach_native.material.duplicate(true),"foam":old.gpu_beach_native.foam.duplicate(true),"histories":histories,"control":control},"visual_extensions":old.visual_extensions.duplicate(true)}
		provenance.original_prefix=old.gpu_beach_edit.prefix.duplicate(true)
		provenance.policies={"clock":"legacy_tick_over_30_f32","state_seq":"new_zero_not_invented_gpu_completions","ledger":"preserve_exact_legacy_history","native":"preserve_raw_fields_normalize_binding_index_only"}
	else:return {"error":&"unsupported_legacy_projection"}
	value.version=VERSION;value.protocol_family=Config.FAMILY;value.pipeline_protocol_version=L.VERSION
	value.ledger_precision=PRECISION;value.source_provenance=provenance
	error=validate(value,configuration)
	if not error.is_empty():return {"error":error}
	return {"error":&"","checkpoint":value,"requires_candidate_build":true}

static func save(path: String, value: Dictionary, configuration: Dictionary) -> StringName:
	var error:=validate(value,configuration)
	if not error.is_empty():return error
	if FileAccess.file_exists(path):return &"already_exists"
	var payload:=var_to_bytes(value)
	if payload.is_empty() or payload.size()>MAX_BYTES:return &"invalid_payload_size"
	var temporary:=path+".tmp."+str(Time.get_ticks_usec())
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return &"open_failed"
	file.store_buffer(MAGIC.to_ascii_buffer());file.store_32(CONTAINER_VERSION);file.store_32(payload.size());file.store_buffer(Old.digest(payload));file.store_buffer(payload);file.flush()
	var write_error:=file.get_error();file.close()
	if write_error!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary));return &"write_failed"
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary));return &"rename_failed"
	return &""

static func read_container(path: String) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"error":&"open_failed"}
	if file.get_length()<48 or file.get_length()>48+MAX_BYTES:return {"error":&"invalid_file_size"}
	var magic:=file.get_buffer(8).get_string_from_ascii();var version:=file.get_32();var count:=file.get_32()
	if magic!=MAGIC or version!=CONTAINER_VERSION or count<1 or file.get_length()!=48+count:return {"error":&"invalid_checkpoint_container"}
	var checksum:=file.get_buffer(32);var payload:=file.get_buffer(count);file.close()
	if checksum!=Old.digest(payload):return {"error":&"checksum_mismatch"}
	var value: Variant=bytes_to_var(payload) # Object deserialization stays disabled.
	if not value is Dictionary:return {"error":&"invalid_checkpoint_payload"}
	return {"error":&"","checkpoint":value}

static func load(path: String, configuration: Dictionary) -> Dictionary:
	var loaded:=read_container(path)
	if not loaded.error.is_empty():return loaded
	var error:=validate(loaded.checkpoint,configuration)
	return loaded if error.is_empty() else {"error":error}
