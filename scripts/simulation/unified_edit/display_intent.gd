extends RefCounted

# Separate tagged display schema. Physical ABI v1 offsets/enums/semantics stay
# frozen; both schemas use the same bounded work slots and completion header.
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const I=preload("res://scripts/simulation/unified_edit/intent.gd")
const Gravel=preload("res://scripts/visual/gpu_gravel_field.gd")
const VERSION:=1
const WORK_KIND:=2
const BATCH_MAGIC:=0x31424455 # UDB1
const COMMAND_MAGIC:=0x31434455 # UDC1
const RESULT_MAGIC:=0x31524455 # UDR1
const KEYS=["domain_id","generation","command_id","sim_tick","point_xz_m","count"]
const SOURCES=["res://scripts/simulation/unified_edit/display_intent.gd","res://scripts/simulation/unified_edit/display_emit.glsl"]

static func _hash(value: Variant) -> String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(var_to_bytes(value));return context.finish().hex_encode()
static func _effective(profile: String, point: Vector2, count: int, seed: int) -> String:return _hash([VERSION,profile,point,count,seed])
static func _hash_valid(value: Variant) -> bool:
	return value is String and value.length()==64 and value.hex_decode().size()==32 and value!="0".repeat(64)

static func freeze(request: Dictionary, config: Dictionary, epoch: int) -> Dictionary:
	if request.size()!=KEYS.size():return {"error":&"invalid_display_request"}
	for key in KEYS:
		if not request.has(key):return {"error":&"invalid_display_request"}
	var error:=I.domain_error(request,config.domain_id,epoch)
	if not error.is_empty():return {"error":error}
	if not config.effects.gravel_enabled:return {"error":&"display_disabled"}
	if not request.point_xz_m is Vector2 or not request.point_xz_m.is_finite() or absf(request.point_xz_m.x)>15.55 or absf(request.point_xz_m.y)>15.55:return {"error":&"out_of_domain"}
	if typeof(request.count)!=TYPE_INT or request.count<1 or request.count>128:return {"error":&"invalid_display_count"}
	var profile: Dictionary=config.environment.get("gravel_profile",Gravel.default_profile("main" if config.domain_id=="main_beach" else config.domain_id))
	var value:=request.duplicate(true);value.domain_id=String(config.domain_id);value.domain_hash=value.domain_id.sha256_text();value.profile_hash=Gravel.profile_hash(profile);value.seed=int(profile.seed)
	value.effective_hash=_effective(value.profile_hash,value.point_xz_m,value.count,value.seed)
	value.control_kind=0
	return {"error":&"","value":value}

static func encode_command(value: Dictionary) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(L.COMMAND_BYTES)
	for pair in [[0,COMMAND_MAGIC],[4,VERSION],[8,L.COMMAND_BYTES],[12,1],[16,value.count]]:bytes.encode_u32(pair[0],pair[1])
	for pair in [[32,value.command_id],[40,value.generation],[72,value.sim_tick],[320,value.seed]]:bytes.encode_s64(pair[0],pair[1])
	for pair in [[96,value.domain_hash],[128,value.effective_hash],[160,value.profile_hash]]:var hash_bytes: PackedByteArray=pair[1].hex_decode();for index in 32:bytes[pair[0]+index]=hash_bytes[index]
	bytes.encode_float(192,value.point_xz_m.x);bytes.encode_float(196,value.point_xz_m.y)
	return bytes

static func decode_command(bytes: PackedByteArray) -> Dictionary:
	if bytes.size()!=L.COMMAND_BYTES or bytes.decode_u32(0)!=COMMAND_MAGIC or bytes.decode_u32(4)!=VERSION or bytes.decode_u32(8)!=L.COMMAND_BYTES or bytes.decode_u32(12)!=1:return {"error":&"display_command_header"}
	var value:={"command_id":bytes.decode_s64(32),"generation":bytes.decode_s64(40),"sim_tick":bytes.decode_s64(72),"seed":bytes.decode_s64(320),"count":bytes.decode_u32(16),"point_xz_m":Vector2(bytes.decode_float(192),bytes.decode_float(196)),"domain_hash":bytes.slice(96,128).hex_encode(),"effective_hash":bytes.slice(128,160).hex_encode(),"profile_hash":bytes.slice(160,192).hex_encode(),"control_kind":0}
	if not I.counter(value.command_id,1) or not I.counter(value.generation,1) or not I.counter(value.sim_tick) or value.count<1 or value.count>128 or not value.point_xz_m.is_finite() or absf(value.point_xz_m.x)>15.55 or absf(value.point_xz_m.y)>15.55:return {"error":&"display_command_parameters"}
	if not _hash_valid(value.domain_hash) or not _hash_valid(value.profile_hash) or value.effective_hash!=_effective(value.profile_hash,value.point_xz_m,value.count,value.seed):return {"error":&"display_command_hash"}
	if encode_command(value)!=bytes:return {"error":&"display_command_reserved"}
	return {"error":&"","value":value}

static func pack(id: Dictionary, value: Dictionary) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(L.HEADER_BYTES)
	for key in L.HEADER_U32:
		var constants:={"magic":BATCH_MAGIC,"version":VERSION,"stride":L.HEADER_BYTES,"command_count":1,"command_stride":L.COMMAND_BYTES,"result_stride":L.RESULT_BYTES,"slot_id":id.slot_id,"work_kind":WORK_KIND}
		bytes.encode_u32(L.HEADER_U32[key],constants[key])
	for key in L.HEADER_I64:bytes.encode_s64(L.HEADER_I64[key],id[key])
	var domain: PackedByteArray=id.domain_hash.hex_decode()
	for index in 32:bytes[56+index]=domain[index]
	bytes.append_array(encode_command(value));return bytes

static func decode_batch(bytes: PackedByteArray, id: Dictionary) -> Dictionary:
	if bytes.size()!=L.HEADER_BYTES+L.COMMAND_BYTES:return {"error":&"display_batch_size"}
	var decoded:=decode_command(bytes.slice(L.HEADER_BYTES))
	if not decoded.error.is_empty():return decoded
	if decoded.value.generation!=id.generation or decoded.value.domain_hash!=id.domain_hash or pack(id,decoded.value)!=bytes:return {"error":&"display_batch_identity"}
	return {"error":&"","commands":[decoded.value],"work_kind":WORK_KIND}

static func decode_result(bytes: PackedByteArray, command: Dictionary, id: Dictionary) -> Dictionary:
	if bytes.size()!=L.RESULT_BYTES:return {"error":&"display_result_size"}
	var value: Dictionary={};var canonical:=PackedByteArray();canonical.resize(L.RESULT_BYTES)
	for key in L.RESULT_U32:value[key]=bytes.decode_u32(L.RESULT_U32[key]);canonical.encode_u32(L.RESULT_U32[key],value[key])
	for key in L.RESULT_I64:value[key]=bytes.decode_s64(L.RESULT_I64[key]);canonical.encode_s64(L.RESULT_I64[key],value[key])
	for key in L.RESULT_F32:
		value[key]=bytes.decode_float(L.RESULT_F32[key])
		if value[key]!=0.0:return {"error":&"display_changed_physical_amount"}
	for key in L.RESULT_HASH:
		value[key]=bytes.slice(L.RESULT_HASH[key],L.RESULT_HASH[key]+32).hex_encode()
		for index in 32:canonical[L.RESULT_HASH[key]+index]=bytes[L.RESULT_HASH[key]+index]
	if canonical!=bytes:return {"error":&"display_result_reserved"}
	if value.magic!=RESULT_MAGIC or value.version!=VERSION or value.stride!=L.RESULT_BYTES or value.completion_phase!=L.GPU_COMPLETE or value.profile_version!=VERSION:return {"error":&"display_result_header"}
	for key in ["generation","batch_seq","lease_id","slot_id"]:
		if value[key]!=id[key]:return {"error":&"display_result_identity"}
	for key in ["command_id","domain_hash","effective_hash"]:
		if value[key]!=command[key]:return {"error":&"display_result_command"}
	for key in ["stroke_id","baseline_token","sample_index","changed_fields","dirty_low","dirty_high","rect_x","rect_z","rect_w","rect_h","coverage_changed"]:
		if value[key]!=0:return {"error":&"display_result_authority"}
	if not I.counter(value.state_seq,1) or not I.counter(value.applied_tick) or value.applied_tick<command.sim_tick or not I.counter(value.input_revision) or value.output_revision!=value.input_revision or value.ledger!=L.Ledger.UNCHANGED or value.touched_cells>1024:return {"error":&"display_result_state"}
	if value.outcome==L.Outcome.APPLIED:
		if value.changed_cells!=command.count or value.touched_cells<command.count or value.error_code!=0 or value.invalid_flags!=0:return {"error":&"display_result_count"}
	elif value.outcome==L.Outcome.REJECTED:
		if value.changed_cells!=0 or value.error_code==0 or value.error_code>3 or value.invalid_flags>1:return {"error":&"display_result_rejection"}
	else:return {"error":&"display_result_outcome"}
	value.kind="display";value.display_count=value.changed_cells;value.active_count=value.touched_cells;value.authority_changed=false
	return {"error":&"","value":value}
