extends RefCounted

const Store=preload("res://scripts/simulation/checkpoint_store.gd")
const Protocol=preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const FIELD_BYTES={"rock":4,"sand":4,"water":4,"momentum_x":4,"momentum_z":4,"sediment":4,"wetness":2,"compaction":2,"obstacle":1,"flux":16}
const VERSION := 1

static func validate(sidecar: Dictionary) -> StringName:
	if sidecar.get("version")!=VERSION or sidecar.get("fixture")!="edit_recovery_numeric_v1" or sidecar.get("grid_size")!=256 or sidecar.get("cell_size_m")!=0.125: return &"invalid_candidate_header"
	for key in ["tick","generation","revision","highwater_id"]:
		if typeof(sidecar.get(key))!=TYPE_INT or sidecar[key]<0: return &"invalid_candidate_identity"
	if sidecar.generation<1 or typeof(sidecar.get("pending_count"))!=TYPE_INT or sidecar.pending_count!=0 or typeof(sidecar.get("reserved_m3")) not in [TYPE_FLOAT,TYPE_INT] or sidecar.reserved_m3!=0.0: return &"unsettled_candidate"
	if not sidecar.get("raw_fields") is Dictionary or sidecar.raw_fields.size()!=FIELD_BYTES.size() or not sidecar.get("ledger") is Dictionary or not sidecar.get("prefix") is Array or not sidecar.get("visual_history") is Dictionary or not sidecar.visual_history.is_empty(): return &"invalid_candidate_payload"
	if sidecar.ledger.size()!=5: return &"invalid_candidate_ledger"
	for key in ["tool_inventory_m3","water_source_m3","water_sink_m3","sand_source_m3","sand_sink_m3"]:
		if typeof(sidecar.ledger.get(key)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(sidecar.ledger[key])) or float(sidecar.ledger[key]) < -Protocol.LEGACY_EPS: return &"invalid_candidate_ledger"
	for field in FIELD_BYTES:
		var data: Variant=sidecar.raw_fields.get(field)
		if not data is PackedByteArray or data.size()!=65536*int(FIELD_BYTES[field]): return &"invalid_native_field_size"
		if field=="obstacle":
			for value in data:
				if value not in [0,255]: return &"invalid_native_obstacle"
		elif field in ["wetness","compaction"]:
			for i in 65536:
				var value: float=data.decode_half(i*2)
				if not is_finite(value) or value<0.0 or value>1.0: return &"invalid_native_half"
		else:
			for value in data.to_float32_array():
				if not is_finite(value) or (field in ["sand","water","sediment"] and value<0.0): return &"invalid_native_float"
	var identities: Dictionary={}
	for item in sidecar.prefix:
		if not item is Dictionary or not item.get("command") is Dictionary or not item.get("result") is Dictionary: return &"invalid_native_prefix"
		var command: Dictionary=item.command
		var result: Dictionary=item.result
		var backend: String=item.get("backend","gpu")
		if backend not in ["gpu","legacy_cpu"]: return &"invalid_edit_backend"
		var accounting: String = item.get("sand_accounting", "inventory")
		if accounting not in ["inventory", "external_v1"] or (accounting == "external_v1" and backend != "gpu"): return &"invalid_sand_accounting"
		var finite: Dictionary=command.duplicate(false)
		if command.get("sand_destination") == "suspended_v1" and (backend != "gpu" or accounting != "external_v1"): return &"invalid_suspended_sand_input"
		if backend=="legacy_cpu" and not finite.has("amount_m3"): finite.amount_m3=0.0
		var kinds: Array=[&"smooth",&"compact"] if backend=="legacy_cpu" else [&"place_sand",&"remove_sand"]
		if not Protocol.finite_command(finite) or typeof(command.get("command_id"))!=TYPE_INT or command.command_id<1 or command.command_id>sidecar.highwater_id or typeof(command.get("generation"))!=TYPE_INT or command.generation<1 or command.generation>sidecar.generation or typeof(command.get("sim_tick"))!=TYPE_INT or command.sim_tick<0 or command.sim_tick>sidecar.tick or command.get("kind") not in kinds: return &"invalid_native_command"
		if backend=="legacy_cpu":
			var legacy: Variant=result.get("legacy_result")
			if not legacy is Dictionary or legacy.get("command_id")!=command.command_id or legacy.get("status") not in [&"applied",&"rejected"] or (result.get("status")==1)!=(legacy.status==&"applied") or not legacy.get("dirty_cells") is PackedInt32Array or not legacy.get("dirty_chunks") is PackedInt32Array: return &"invalid_legacy_result"
		if item.get("policy") not in [0,1,2,3] or typeof(item.get("speed")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(item.speed)) or absf(float(item.speed))>1.0: return &"invalid_native_policy"
		if result.get("status") not in [1,2] or result.get("command_id")!=command.command_id or result.get("generation")!=command.generation or typeof(result.get("applied_tick"))!=TYPE_INT or result.applied_tick<command.sim_tick or result.applied_tick>sidecar.tick: return &"invalid_native_result"
		var identity: String="%d:%d" % [command.generation,command.command_id]
		if item.has("available_m3"):
			if typeof(item.available_m3) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(item.available_m3)) or typeof(item.get("stock_before")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(item.stock_before)) or (accounting == "inventory" and item.available_m3>item.stock_before) or typeof(item.get("execution_tick"))!=TYPE_INT or item.execution_tick<command.sim_tick or item.execution_tick>sidecar.tick: return &"invalid_native_replay_input"
			if accounting == "external_v1" and (item.stock_before != 0.0 or sidecar.ledger.tool_inventory_m3 != 0.0 or item.available_m3 != maxf(0.0, float(command.amount_m3) * float(command.strength)) + Protocol.LEGACY_EPS): return &"invalid_external_sand_input"
		if identities.has(identity): return &"duplicate_native_command"
		identities[identity]=true
	return &""

static func build(raw_fields: Dictionary, ledger: Dictionary, prefix: Array, tick: int, generation: int, revision: int, highwater_id: int, pending_count: int=0, reserved_m3: float=0.0) -> Dictionary:
	var sidecar: Dictionary={"version":VERSION,"fixture":"edit_recovery_numeric_v1","grid_size":256,"cell_size_m":0.125,"tick":tick,"generation":generation,"revision":revision,"highwater_id":highwater_id,"pending_count":pending_count,"reserved_m3":reserved_m3,"raw_fields":raw_fields.duplicate(true),"ledger":ledger.duplicate(true),"prefix":prefix.duplicate(true),"visual_history":{}}
	var error:=validate(sidecar)
	if not error.is_empty(): return {"error":error}
	var domain=Domain.new(256,0.125)
	domain.sim_tick=tick;domain.generation=generation
	for field in ["rock","sand","water","sediment"]: domain.set(field,raw_fields[field].to_float32_array())
	for field in ["wetness","compaction","obstacle"]:
		var values:=PackedFloat32Array();values.resize(65536)
		for i in 65536: values[i]=float(raw_fields[field][i])/255.0 if field=="obstacle" else raw_fields[field].decode_half(i*2)
		domain.set(field,values)
	var flux: PackedFloat32Array=raw_fields.flux.to_float32_array()
	for channel in 4:
		var values:=PackedFloat32Array();values.resize(65536)
		for i in 65536: values[i]=flux[i*4+channel]
		domain.set(["flux_left","flux_right","flux_up","flux_down"][channel],values)
	for key in ledger: domain.set(key,ledger[key])
	# The unchanged legacy schema covers CPU tool commands. Native candidates
	# have their complete int64 execution prefix in the checksummed sidecar.
	var checkpoint: Dictionary={"tick":tick,"preset_index":0,"highwater_id":highwater_id,"revision":revision,"command_ids":PackedInt32Array(),"shadow":domain.snapshot(),"fields":{"water":raw_fields.water.to_float32_array(),"momentum_x":raw_fields.momentum_x.to_float32_array(),"momentum_z":raw_fields.momentum_z.to_float32_array()},"water_source_m3":ledger.water_source_m3,"water_sink_m3":ledger.water_sink_m3,"gpu_edit_sidecar":sidecar}
	return {"error":&"","checkpoint":checkpoint}

static func save(path: String, checkpoint: Dictionary) -> StringName:
	if not checkpoint.get("gpu_edit_sidecar") is Dictionary: return &"missing_candidate_sidecar"
	var error:=validate(checkpoint.gpu_edit_sidecar)
	if not error.is_empty(): return error
	error=validate_projection(checkpoint)
	if not error.is_empty(): return error
	var legacy_prefix: Array[Dictionary]=[]
	return Store.save(path,checkpoint,legacy_prefix,false)

static func load(path: String) -> Dictionary:
	var envelope:=Store.load(path)
	if not envelope.error.is_empty(): return envelope
	if envelope.enable_erosion: return {"error":&"incompatible_candidate_erosion"}
	if not envelope.checkpoint.get("gpu_edit_sidecar") is Dictionary: return {"error":&"missing_candidate_sidecar"}
	var error:=validate(envelope.checkpoint.gpu_edit_sidecar)
	if not error.is_empty(): return {"error":error}
	error=validate_projection(envelope.checkpoint)
	if not error.is_empty(): return {"error":error}
	return {"error":&"","checkpoint":envelope.checkpoint,"sidecar":envelope.checkpoint.gpu_edit_sidecar}

static func validate_projection(checkpoint: Dictionary) -> StringName:
	var sidecar: Dictionary=checkpoint.gpu_edit_sidecar
	var rebuilt:=build(sidecar.raw_fields,sidecar.ledger,sidecar.prefix,sidecar.tick,sidecar.generation,sidecar.revision,sidecar.highwater_id)
	if not rebuilt.error.is_empty(): return rebuilt.error
	# Reject a sidecar which disagrees with the validated legacy projection.
	for key in ["tick","revision","highwater_id","shadow","fields","water_source_m3","water_sink_m3"]:
		if checkpoint.get(key)!=rebuilt.checkpoint[key]: return &"candidate_projection_mismatch"
	if not checkpoint.get("command_ids") is PackedInt32Array or not checkpoint.command_ids.is_empty(): return &"candidate_projection_mismatch"
	return &""
