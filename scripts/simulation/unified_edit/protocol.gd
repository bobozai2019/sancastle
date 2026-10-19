extends RefCounted
const Display=preload("res://scripts/simulation/unified_edit/display_intent.gd")

const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const Intent=preload("res://scripts/simulation/unified_edit/intent.gd")
const P=preload("res://scripts/simulation/unified_edit/tool_profile.gd")
const ZERO_HASH="0000000000000000000000000000000000000000000000000000000000000000"
const ID_KEYS=["generation","batch_seq","slot_id","lease_id","domain_hash"]

static func hash_valid(value: Variant, nonzero: bool=false) -> bool:
	if typeof(value)!=TYPE_STRING or value.length()!=64 or value.to_lower()!=value:return false
	for character in value:
		if character not in "0123456789abcdef":return false
	return not nonzero or value!=ZERO_HASH

static func identity_valid(id: Dictionary) -> bool:
	if id.size()!=ID_KEYS.size():return false
	for key in ID_KEYS:
		if not id.has(key):return false
	for key in ["generation","batch_seq","lease_id"]:
		if not Intent.counter(id[key],1):return false
	return Intent.counter(id.slot_id) and id.slot_id<L.WORK_SLOTS and hash_valid(id.domain_hash,true)

static func ledger_for(frozen: Dictionary) -> int:
	if frozen.control_kind!=L.ControlKind.NONE:return L.Ledger.UNCHANGED
	match frozen.configuration.operation:
		P.Operation.VOLUME_DELTA:return L.Ledger.APPROXIMATE_EXTERNAL
		P.Operation.TARGET_HEIGHT:return L.Ledger.EXACT_EXTERNAL
		P.Operation.TRANSFER:return L.Ledger.TRANSFER_WITH_SINK if frozen.configuration.transfer_policy==P.TransferPolicy.CAPPED_SHOULDERS else L.Ledger.CONSERVATIVE_TRANSFER
	return L.Ledger.UNCHANGED

static func _budgets(frozen: Dictionary) -> Dictionary:
	var values:=Intent.budget_limits(frozen.configuration,frozen.start_xz_m,frozen.end_xz_m)
	values.merge(frozen.authorization,true)
	return values

static func gpu_nominal(frozen: Dictionary) -> float:
	# The shader multiplies the individually encoded f32 parameters. This is
	# distinct from the retained CPU f64 nominal-history accounting policy.
	var amount: float=PackedFloat32Array([frozen.parameters.amount_m3])[0]
	var strength: float=PackedFloat32Array([frozen.parameters.strength])[0]
	return PackedFloat32Array([amount*strength])[0]

static func command_values(frozen: Dictionary, registry) -> Dictionary:
	var values:={"magic":L.COMMAND_MAGIC,"version":L.VERSION,"stride":L.COMMAND_BYTES,"control_kind":frozen.control_kind,"domain_hash":frozen.domain_hash}
	for key in L.COMMAND_I64:values[key]=frozen[key]
	if frozen.control_kind!=L.ControlKind.NONE:
		values.operation=L.CONTROL_OPERATION
		return values
	var profile: Dictionary=frozen.configuration
	for key in ["operation","shape","destination","profile_version","water_policy","material_policy","volume_sign","height_reference","target_rule","transfer_policy","stroke_policy"]:
		values[key]=profile.version if key=="profile_version" else profile[key]
	values.fields=profile.derived_fields
	values.capabilities=(1 if profile.material_policy==P.MaterialPolicy.MOLDED else 0)|(2 if profile.material_policy==P.MaterialPolicy.PRESERVE else 0)|(4 if profile.water_policy!=0 else 0)
	values.effective_hash=profile.effective_hash
	values.start_x=frozen.start_xz_m.x;values.start_z=frozen.start_xz_m.y
	values.end_x=frozen.end_xz_m.x;values.end_z=frozen.end_xz_m.y
	for key in frozen.parameters:values[key]=frozen.parameters[key]
	values.merge(_budgets(frozen))
	values.cell_size_m=0.125;values.legacy_epsilon_m3=0.000001;values.dry_depth_m=0.001
	values.ridge_height_m=0.5 if profile.operation==P.Operation.TRANSFER else 0.0
	values.ledger=ledger_for(frozen)
	values.grid_size=256
	var rect:=Intent.bounds(frozen)
	values.rect_x=rect.position.x;values.rect_z=rect.position.y;values.rect_w=rect.size.x;values.rect_h=rect.size.y
	if not profile.template.is_empty():
		values.template_hash=profile.template.sha256
		values.template_index=registry.template_index(profile.template.sha256)
		values.template_width=profile.template.width;values.template_height=profile.template.height
		values.template_channels=4;values.template_spacing_m=profile.template.spacing_m
	return values

static func _write(bytes: PackedByteArray, values: Dictionary, u32: Dictionary, i64: Dictionary, f32: Dictionary, hashes: Dictionary) -> bool:
	for key in values:
		if not u32.has(key) and not i64.has(key) and not f32.has(key) and not hashes.has(key):return false
	for key in u32:
		var value: Variant=values.get(key,0)
		if not Intent.counter(value) or value>0xffffffff:return false
		bytes.encode_u32(u32[key],value)
	for key in i64:
		var value: Variant=values.get(key,0)
		if typeof(value)!=TYPE_INT:return false
		bytes.encode_s64(i64[key],value)
	for key in f32:
		var value: Variant=values.get(key,0.0)
		if not P.finite_number(value):return false
		bytes.encode_float(f32[key],float(value))
	for key in hashes:
		var value: Variant=values.get(key,ZERO_HASH)
		if not hash_valid(value):return false
		var raw: PackedByteArray=value.hex_decode()
		for index in 32:bytes[hashes[key]+index]=raw[index]
	return true

static func encode_command(frozen: Dictionary, registry) -> PackedByteArray:
	if not Intent.revalidate(registry,frozen).is_empty():return PackedByteArray()
	var values:=command_values(frozen,registry)
	var bytes:=PackedByteArray();bytes.resize(L.COMMAND_BYTES)
	if not _write(bytes,values,L.COMMAND_U32,L.COMMAND_I64,L.COMMAND_F32,L.COMMAND_HASH):return PackedByteArray()
	# Authorization amounts narrow downward, as in the frozen original wire.
	for key in ["add_budget_m3","transfer_budget_m3","available_m3"]:
		var value: float=values.get(key,0.0)
		var offset: int=L.COMMAND_F32[key]
		if bytes.decode_float(offset)>value:bytes.encode_u32(offset,bytes.decode_u32(offset)-1)
	return bytes

static func _read(bytes: PackedByteArray, u32: Dictionary, i64: Dictionary, f32: Dictionary, hashes: Dictionary) -> Dictionary:
	var values:={}
	for key in u32:values[key]=bytes.decode_u32(u32[key])
	for key in i64:values[key]=bytes.decode_s64(i64[key])
	for key in f32:values[key]=bytes.decode_float(f32[key])
	for key in hashes:values[key]=bytes.slice(hashes[key],hashes[key]+32).hex_encode()
	return values

static func _reserved_zero(bytes: PackedByteArray, maps: Array) -> bool:
	var used:=PackedByteArray();used.resize(bytes.size())
	for pair in maps:
		for offset in pair[0].values():
			for index in pair[1]:used[offset+index]=1
	for index in bytes.size():
		if used[index]==0 and bytes[index]!=0:return false
	return true

static func _wire_profile(value: Dictionary):
	var profile:=P.new()
	for key in ["operation","shape","destination","volume_sign","height_reference","target_rule","transfer_policy","material_policy","water_policy","stroke_policy"]:profile.set(key,value[key])
	if value.shape==P.Shape.HEIGHT_STAMP:profile.shape_resource=P.Stamp.new()
	return profile

static func decode_command(bytes: PackedByteArray, canonical: PackedByteArray=PackedByteArray()) -> Dictionary:
	if bytes.size()!=L.COMMAND_BYTES:return {"error":&"command_size"}
	var value:=_read(bytes,L.COMMAND_U32,L.COMMAND_I64,L.COMMAND_F32,L.COMMAND_HASH)
	if value.magic!=L.COMMAND_MAGIC or value.version!=L.VERSION or value.stride!=L.COMMAND_BYTES:return {"error":&"command_header"}
	if not _reserved_zero(bytes,[[L.COMMAND_U32,4],[L.COMMAND_I64,8],[L.COMMAND_F32,4],[L.COMMAND_HASH,32]]):return {"error":&"command_reserved"}
	if not Intent.counter(value.command_id,1) or not Intent.counter(value.generation,1) or not Intent.counter(value.sim_tick) or not Intent.counter(value.sample_index) or not Intent.counter(value.stroke_id) or not Intent.counter(value.baseline_token) or not hash_valid(value.domain_hash,true):return {"error":&"command_identity"}
	for key in L.COMMAND_F32:
		if not is_finite(value[key]):return {"error":&"command_nonfinite"}
	if value.control_kind!=L.ControlKind.NONE:
		if value.control_kind not in [L.ControlKind.BEGIN,L.ControlKind.END,L.ControlKind.CANCEL] or value.operation!=L.CONTROL_OPERATION or value.stroke_id==0 or value.baseline_token==0:return {"error":&"command_control"}
		var allowed:={"magic":L.COMMAND_MAGIC,"version":L.VERSION,"stride":L.COMMAND_BYTES,"operation":L.CONTROL_OPERATION,"control_kind":value.control_kind,"domain_hash":value.domain_hash}
		for key in ["command_id","generation","sim_tick","stroke_id","baseline_token"]:allowed[key]=value[key]
		var expected:=PackedByteArray();expected.resize(L.COMMAND_BYTES)
		if not _write(expected,allowed,L.COMMAND_U32,L.COMMAND_I64,L.COMMAND_F32,L.COMMAND_HASH) or bytes!=expected:return {"error":&"command_control_payload"}
	else:
		if value.profile_version==0 or value.grid_size!=256 or value.cell_size_m!=0.125 or value.legacy_epsilon_m3!=PackedFloat32Array([0.000001])[0] or value.dry_depth_m!=PackedFloat32Array([0.001])[0] or not hash_valid(value.effective_hash,true):return {"error":&"command_configuration"}
		var profile=_wire_profile(value)
		if not profile.combination_error().is_empty() or value.fields!=profile.derived_fields():return {"error":&"command_capability"}
		var capabilities: int=(1 if value.material_policy==P.MaterialPolicy.MOLDED else 0)|(2 if value.material_policy==P.MaterialPolicy.PRESERVE else 0)|(4 if value.water_policy!=0 else 0)
		if value.capabilities!=capabilities:return {"error":&"command_capability"}
		for key in profile.parameter_keys():
			var limits: Array=profile._capability_limits(key)
			if value[key]<PackedFloat32Array([limits[0]])[0] or value[key]>PackedFloat32Array([limits[1]])[0] or (key in ["radius_m","amount_m3"] and value[key]<=0.0):return {"error":&"command_parameters"}
		if value.operation==P.Operation.TARGET_HEIGHT and value.shape==P.Shape.SWEPT_CAPSULE and value.top_width_m>value.bottom_width_m:return {"error":&"command_parameters"}
		if value.water_policy not in [2,3] and value.speed_m_s!=0.0:return {"error":&"command_parameters"}
		var used: Array=profile.parameter_keys()+["start_x","start_z","end_x","end_z","add_budget_m3","transfer_budget_m3","available_m3","cell_size_m","legacy_epsilon_m3","dry_depth_m","template_spacing_m"]
		if value.operation==P.Operation.TRANSFER:used.append("ridge_height_m")
		for key in L.COMMAND_F32:
			if key not in used and value[key]!=0.0:return {"error":&"command_unused_field"}
		if value.ridge_height_m!=(0.5 if value.operation==P.Operation.TRANSFER else 0.0):return {"error":&"command_parameters"}
		if value.operation!=P.Operation.TRANSFER and value.transfer_budget_m3!=0.0:return {"error":&"command_budget"}
		if value.operation!=P.Operation.VOLUME_DELTA and value.available_m3!=0.0:return {"error":&"command_budget"}
		if value.operation not in [P.Operation.TARGET_HEIGHT,P.Operation.VOLUME_DELTA] and value.add_budget_m3!=0.0:return {"error":&"command_budget"}
		if value.operation==P.Operation.VOLUME_DELTA and value.volume_sign==P.VolumeSign.REMOVE and value.add_budget_m3!=0.0:return {"error":&"command_budget"}
		if value.stroke_policy==P.StrokePolicy.FIXED_BASELINE_COVERAGE:
			if value.stroke_id==0 or value.baseline_token==0:return {"error":&"command_stroke"}
		elif value.stroke_id!=0 or value.baseline_token!=0 or value.sample_index!=0:return {"error":&"command_stroke"}
		if value.shape==P.Shape.HEIGHT_STAMP:
			if value.template_index<1 or value.template_index>L.MAX_TEMPLATES or value.template_width!=65 or value.template_height!=65 or value.template_channels!=4 or value.template_spacing_m!=0.0625 or value.template_hash==ZERO_HASH:return {"error":&"command_template"}
		elif value.template_index!=0 or value.template_width!=0 or value.template_height!=0 or value.template_channels!=0 or value.template_spacing_m!=0.0 or value.template_hash!=ZERO_HASH:return {"error":&"command_template"}
		if value.rect_w==0 or value.rect_h==0 or value.rect_x+value.rect_w>256 or value.rect_z+value.rect_h>256:return {"error":&"command_bounds"}
		for key in ["add_budget_m3","transfer_budget_m3","available_m3"]:
			if value[key]<0.0:return {"error":&"command_budget"}
		var fake:={"control_kind":0,"configuration":{"operation":value.operation,"transfer_policy":value.transfer_policy}}
		if value.ledger!=ledger_for(fake):return {"error":&"command_ledger"}
	if not canonical.is_empty() and bytes!=canonical:return {"error":&"command_snapshot_mismatch"}
	return {"error":&"","value":value,"structural_only":canonical.is_empty()}

static func encode_result(record: Dictionary) -> PackedByteArray:
	var values:=record.duplicate(true)
	values.magic=L.RESULT_MAGIC;values.version=L.VERSION;values.stride=L.RESULT_BYTES
	var bytes:=PackedByteArray();bytes.resize(L.RESULT_BYTES)
	return bytes if _write(bytes,values,L.RESULT_U32,L.RESULT_I64,L.RESULT_F32,L.RESULT_HASH) else PackedByteArray()

static func decode_result(bytes: PackedByteArray, frozen: Dictionary, id: Dictionary) -> Dictionary:
	if bytes.size()!=L.RESULT_BYTES:return {"error":&"result_size"}
	if not identity_valid(id):return {"error":&"result_expected_identity"}
	if frozen.size()!=Intent.SNAPSHOT_KEYS.size():return {"error":&"result_expected_command"}
	for key in Intent.SNAPSHOT_KEYS:
		if not frozen.has(key):return {"error":&"result_expected_command"}
	if typeof(frozen.control_kind)!=TYPE_INT or frozen.control_kind not in L.ControlKind.values() or not frozen.configuration is Dictionary or not frozen.parameters is Dictionary:return {"error":&"result_expected_command"}
	if frozen.control_kind==0:
		for key in ["operation","volume_sign","derived_fields","version","effective_hash","transfer_policy"]:
			if not frozen.configuration.has(key):return {"error":&"result_expected_command"}
		if frozen.configuration.operation not in P.Operation.values():return {"error":&"result_expected_command"}
		if frozen.configuration.operation==P.Operation.VOLUME_DELTA:
			for key in ["amount_m3","strength"]:
				if not P.finite_number(frozen.parameters.get(key)):return {"error":&"result_expected_command"}
	var value:=_read(bytes,L.RESULT_U32,L.RESULT_I64,L.RESULT_F32,L.RESULT_HASH)
	if value.magic!=L.RESULT_MAGIC or value.version!=L.VERSION or value.stride!=L.RESULT_BYTES or not _reserved_zero(bytes,[[L.RESULT_U32,4],[L.RESULT_I64,8],[L.RESULT_F32,4],[L.RESULT_HASH,32]]):return {"error":&"result_header"}
	for key in ["command_id","generation","stroke_id","baseline_token","sample_index"]:
		if not frozen.has(key) or typeof(frozen[key])!=TYPE_INT or value[key]!=frozen[key]:return {"error":&"result_command_identity"}
	for key in ["generation","batch_seq","slot_id","lease_id","domain_hash"]:
		if value[key]!=id[key]:return {"error":&"result_lease_identity"}
	if frozen.get("domain_hash")!=value.domain_hash:return {"error":&"result_domain"}
	var control: bool=frozen.get("control_kind",0)!=0
	var config: Dictionary=frozen.get("configuration",{})
	if value.effective_hash!=(ZERO_HASH if control else config.get("effective_hash","")) or value.profile_version!=(0 if control else config.get("version",0)) or value.ledger!=ledger_for(frozen):return {"error":&"result_configuration"}
	for key in ["input_revision","output_revision","applied_tick","state_seq"]:
		if not Intent.counter(value[key]):return {"error":&"result_counter"}
	if value.state_seq==0 or value.completion_phase!=L.GPU_COMPLETE or value.outcome not in L.Outcome.values() or (value.changed_fields&~63)!=0 or (value.invalid_flags&~8191)!=0 or value.coverage_changed>1 or value.error_code not in L.ErrorCode.values():return {"error":&"result_status"}
	if bool(value.changed_fields&P.COVERAGE)!=bool(value.coverage_changed) or value.changed_cells>65536 or value.touched_cells>65536 or value.changed_cells>value.touched_cells:return {"error":&"result_changes"}
	for key in L.RESULT_F32:
		if not is_finite(value[key]):return {"error":&"result_nonfinite"}
		if key not in ["sand_error_m3","water_error_m3","sediment_error_m3","impulse_x_m4_s","impulse_z_m4_s"] and value[key]<0.0:return {"error":&"result_negative"}
	if value.outcome==L.Outcome.APPLIED:
		if value.input_revision==L.INT64_MAX or value.output_revision!=value.input_revision+1 or value.error_code!=0 or value.invalid_flags!=0 or (value.changed_fields&~P.COVERAGE)==0 or value.changed_cells==0 or (value.dirty_low|value.dirty_high)==0:return {"error":&"result_applied"}
		if value.rect_w==0 or value.rect_h==0 or value.rect_x+value.rect_w>256 or value.rect_z+value.rect_h>256:return {"error":&"result_bounds"}
	else:
		if value.output_revision!=value.input_revision or (value.changed_fields&~P.COVERAGE)!=0 or value.changed_cells!=0 or value.dirty_low!=0 or value.dirty_high!=0 or value.rect_x!=0 or value.rect_z!=0 or value.rect_w!=0 or value.rect_h!=0:return {"error":&"result_no_authority_change"}
		for key in ["added_m3","removed_m3","transferred_m3","left_received_m3","right_received_m3","displaced_water_m3","retained_water_m3","impulse_x_m4_s","impulse_z_m4_s","max_cell_delta_m","absolute_volume_delta_m3"]:
			if value[key]!=0.0:return {"error":&"result_no_authority_change"}
		if value.outcome==L.Outcome.REJECTED:
			if value.error_code==0 or value.coverage_changed!=0:return {"error":&"result_rejected"}
		elif value.error_code!=0 or value.invalid_flags!=0:return {"error":&"result_no_change"}
	if value.applied_tick<int(frozen.get("sim_tick",0)):return {"error":&"result_applied_before_requested_tick"}
	if not control and (value.changed_fields&~int(config.derived_fields))!=0:return {"error":&"result_field_capability"}
	if control and (value.outcome not in [L.Outcome.NO_CHANGE,L.Outcome.REJECTED] or value.changed_fields!=0):return {"error":&"result_control"}
	if control:
		if value.touched_cells!=0:return {"error":&"result_control"}
		for key in L.RESULT_F32:
			if value[key]!=0.0:return {"error":&"result_control"}
	if value.outcome==L.Outcome.APPLIED:
		for pair in [["sand_error_m3","eps_sand_m3"],["water_error_m3","eps_water_m3"],["sediment_error_m3","eps_sediment_m3"]]:
			if absf(value[pair[0]])>value[pair[1]]:return {"error":&"result_numeric_budget"}
		var op: int=config.operation
		if op==P.Operation.FIELD_ADJUST:
			for key in ["added_m3","removed_m3","transferred_m3","left_received_m3","right_received_m3","max_cell_delta_m","absolute_volume_delta_m3"]:
				if value[key]!=0.0:return {"error":&"result_field_adjust_volume"}
		elif op==P.Operation.REDISTRIBUTE:
			if absf(value.added_m3-value.removed_m3)>value.eps_sand_m3:return {"error":&"result_redistribution_volume"}
		elif op==P.Operation.VOLUME_DELTA:
			var add: bool=config.volume_sign==P.VolumeSign.ADD
			if (value.removed_m3 if add else value.added_m3)!=0.0:return {"error":&"result_volume_sign"}
			var nominal:=gpu_nominal(frozen)
			if maxf(value.added_m3,value.removed_m3)>nominal+value.eps_sand_m3:return {"error":&"result_volume_authorization"}
			if maxf(value.added_m3,value.removed_m3)>_budgets(frozen).available_m3+value.eps_sand_m3:return {"error":&"result_volume_authorization"}
		elif op==P.Operation.TARGET_HEIGHT:
			if value.removed_m3!=0.0 or value.added_m3>_budgets(frozen).add_budget_m3+value.eps_sand_m3:return {"error":&"result_target_authorization"}
		elif op==P.Operation.TRANSFER:
			if absf(value.added_m3+value.sink_m3-value.removed_m3)>value.eps_transfer_m3 or value.removed_m3>_budgets(frozen).transfer_budget_m3+value.eps_transfer_m3:return {"error":&"result_transfer_authorization"}
		if op!=P.Operation.TRANSFER and (value.transferred_m3!=0.0 or value.left_received_m3!=0.0 or value.right_received_m3!=0.0):return {"error":&"result_unexpected_transfer"}
	if value.ledger==L.Ledger.CONSERVATIVE_TRANSFER:
		if value.source_m3!=0.0 or value.sink_m3!=0.0 or absf(value.removed_m3-value.left_received_m3-value.right_received_m3)>value.eps_transfer_m3 or absf(value.left_received_m3-value.right_received_m3)>value.eps_transfer_m3 or absf(value.transferred_m3-value.removed_m3)>value.eps_transfer_m3:return {"error":&"result_transfer_ledger"}
	elif value.ledger==L.Ledger.TRANSFER_WITH_SINK:
		var received: float=value.left_received_m3+value.right_received_m3
		if value.source_m3!=0.0 or absf(value.added_m3-received)>value.eps_transfer_m3 or absf(value.transferred_m3-received)>value.eps_transfer_m3 or absf(value.removed_m3-received-value.sink_m3)>value.eps_transfer_m3 or maxf(value.left_received_m3,value.right_received_m3)>value.removed_m3*0.5+value.eps_transfer_m3:return {"error":&"result_transfer_ledger"}
	elif value.ledger==L.Ledger.UNCHANGED:
		if value.source_m3!=0.0 or value.sink_m3!=0.0:return {"error":&"result_unchanged_ledger"}
	elif value.ledger==L.Ledger.EXACT_EXTERNAL:
		if absf(value.source_m3-value.added_m3)>value.eps_sand_m3 or absf(value.sink_m3-value.removed_m3)>value.eps_sand_m3:return {"error":&"result_exact_ledger"}
	else:
		# Compatibility: nominal bookkeeping occurs on known recording, including
		# ordinary business rejection. It is not an exact physical source/sink.
		var rounded:=gpu_nominal(frozen)
		var add: bool=config.volume_sign==P.VolumeSign.ADD
		if value.source_m3!=(rounded if add else 0.0) or value.sink_m3!=(0.0 if add else rounded):return {"error":&"result_approximate_ledger"}
	return {"error":&"","value":value}

static func _batch_header(id: Dictionary, count: int, kind: int) -> PackedByteArray:
	if not identity_valid(id) or kind not in L.WorkKind.values() or (kind==L.WorkKind.EDIT and (count<1 or count>L.MAX_COMMANDS)) or (kind==L.WorkKind.WATER_TICK and count!=0):return PackedByteArray()
	var packet:=PackedByteArray();packet.resize(L.HEADER_BYTES)
	var values:=id.duplicate(true)
	values.merge({"magic":L.BATCH_MAGIC,"version":L.VERSION,"stride":L.HEADER_BYTES,"command_count":count,"command_stride":L.COMMAND_BYTES,"result_stride":L.RESULT_BYTES,"work_kind":kind})
	if not _write(packet,values,L.HEADER_U32,L.HEADER_I64,{},L.HEADER_HASH):return PackedByteArray()
	return packet

static func pack_tick(id: Dictionary) -> PackedByteArray:
	return _batch_header(id,0,L.WorkKind.WATER_TICK)

static func pack_batch(id: Dictionary, commands: Array[PackedByteArray]) -> PackedByteArray:
	if not identity_valid(id) or commands.is_empty() or commands.size()>L.MAX_COMMANDS:return PackedByteArray()
	var previous:=0
	for bytes in commands:
		var decoded:=decode_command(bytes)
		if not decoded.error.is_empty() or decoded.value.generation!=id.generation or decoded.value.domain_hash!=id.domain_hash or decoded.value.command_id<=previous:return PackedByteArray()
		previous=decoded.value.command_id
	var packet:=_batch_header(id,commands.size(),L.WorkKind.EDIT)
	for bytes in commands:packet.append_array(bytes)
	return packet

static func decode_batch(packet: PackedByteArray, expected: Dictionary) -> Dictionary:
	if packet.size()>=4 and packet.decode_u32(0)==Display.BATCH_MAGIC:
		if not identity_valid(expected):return {"error":&"batch_expected_identity"}
		return Display.decode_batch(packet,expected)
	if packet.size()<L.HEADER_BYTES or not identity_valid(expected):return {"error":&"batch_size_or_identity"}
	var header:=_read(packet,L.HEADER_U32,L.HEADER_I64,{},L.HEADER_HASH)
	var count: int=header.command_count
	var kind: int=header.work_kind
	if kind not in L.WorkKind.values() or (kind==L.WorkKind.EDIT and (count<1 or count>L.MAX_COMMANDS)) or (kind==L.WorkKind.WATER_TICK and count!=0) or packet.size()!=L.HEADER_BYTES+count*L.COMMAND_BYTES:return {"error":&"batch_size"}
	if header.magic!=L.BATCH_MAGIC or header.version!=L.VERSION or header.stride!=L.HEADER_BYTES or header.command_stride!=L.COMMAND_BYTES or header.result_stride!=L.RESULT_BYTES or not _reserved_zero(packet.slice(0,L.HEADER_BYTES),[[L.HEADER_U32,4],[L.HEADER_I64,8],[L.HEADER_HASH,32]]):return {"error":&"batch_header"}
	for key in ID_KEYS:
		if header[key]!=expected[key]:return {"error":&"batch_identity"}
	var commands: Array=[];var previous:=0
	for index in count:
		var decoded:=decode_command(packet.slice(L.HEADER_BYTES+index*L.COMMAND_BYTES,L.HEADER_BYTES+(index+1)*L.COMMAND_BYTES))
		if not decoded.error.is_empty():return decoded
		if decoded.value.command_id<=previous or decoded.value.generation!=expected.generation or decoded.value.domain_hash!=expected.domain_hash:return {"error":&"batch_command_order_or_domain"}
		previous=decoded.value.command_id;commands.append(decoded.value)
	return {"error":&"","commands":commands,"work_kind":kind}

static func encode_completion(id: Dictionary, results: Array[PackedByteArray], state: Dictionary) -> PackedByteArray:
	if not identity_valid(id) or results.size()>L.MAX_COMMANDS:return PackedByteArray()
	for bytes in results:
		if bytes.size()!=L.RESULT_BYTES:return PackedByteArray()
	var keys:=["state_seq","sim_tick","revision","state","error_flags","advanced_time_s","actual_dt","accepted_count","rejected_count"]
	if state.size()!=keys.size():return PackedByteArray()
	for key in keys:
		if not state.has(key):return PackedByteArray()
	for key in ["state_seq","sim_tick","revision","state","error_flags","accepted_count","rejected_count"]:
		if not Intent.counter(state[key]):return PackedByteArray()
	for key in ["advanced_time_s","actual_dt"]:
		if not P.finite_number(state[key]) or state[key]<0.0:return PackedByteArray()
	var packet:=PackedByteArray();packet.resize(L.COMPLETION_BYTES)
	var values:=state.duplicate(true)
	for key in ["generation","batch_seq","lease_id","slot_id"]:values[key]=id[key]
	values.merge({"magic":L.COMPLETION_MAGIC,"version":L.VERSION,"stride":L.COMPLETION_BYTES,"result_count":results.size(),"result_stride":L.RESULT_BYTES})
	if not _write(packet,values,L.COMPLETION_U32,L.COMPLETION_I64,L.COMPLETION_F32,{}):return PackedByteArray()
	for bytes in results:packet.append_array(bytes)
	return packet

static func decode_completion(packet: PackedByteArray, id: Dictionary, commands: Array, work_kind: int=L.WorkKind.EDIT) -> Dictionary:
	if not identity_valid(id) or (work_kind not in L.WorkKind.values() and work_kind!=Display.WORK_KIND) or (work_kind==Display.WORK_KIND and commands.size()!=1) or (work_kind==L.WorkKind.EDIT and (commands.is_empty() or commands.size()>L.MAX_COMMANDS)) or (work_kind==L.WorkKind.WATER_TICK and not commands.is_empty()):return {"error":&"completion_expected_identity"}
	if packet.size()!=L.COMPLETION_BYTES+commands.size()*L.RESULT_BYTES:return {"error":&"completion_size"}
	var header:=_read(packet,L.COMPLETION_U32,L.COMPLETION_I64,L.COMPLETION_F32,{})
	if header.magic!=L.COMPLETION_MAGIC or header.version!=L.VERSION or header.stride!=L.COMPLETION_BYTES or header.result_count!=commands.size() or header.result_stride!=L.RESULT_BYTES:return {"error":&"completion_header"}
	for key in ["generation","batch_seq","lease_id","slot_id"]:
		if header[key]!=id[key]:return {"error":&"completion_identity"}
	for key in ["state_seq","sim_tick","revision"]:
		if not Intent.counter(header[key],1 if key=="state_seq" else 0):return {"error":&"completion_counter"}
	if not is_finite(header.advanced_time_s) or not is_finite(header.actual_dt) or header.advanced_time_s<0.0 or header.actual_dt<0.0 or header.state not in L.CompletionState.values() or (header.error_flags&~L.FATAL_FLAGS_MASK)!=0:return {"error":&"completion_state"}
	if header.accepted_count+header.rejected_count>commands.size():return {"error":&"completion_counts"}
	if header.state==L.CompletionState.FATAL:
		if header.error_flags==0:return {"error":&"completion_fatal_without_reason"}
		# Retain the packet as diagnostic bytes. No business outcomes, settlement,
		# replay permission or consumer ACK is inferred from a fatal notification.
		return {"error":&"","fatal":true,"header":header,"raw_results":packet.slice(L.COMPLETION_BYTES),"results":[]}
	if header.error_flags!=0 or header.accepted_count+header.rejected_count!=commands.size():return {"error":&"completion_counts"}
	var results: Array=[];var previous_revision:=-1;var accepted:=0;var rejected:=0;var previous_command:=0
	for index in commands.size():
		var frozen: Variant=commands[index]
		if not frozen is Dictionary or not Intent.counter(frozen.get("command_id"),1) or frozen.command_id<=previous_command:return {"error":&"completion_command_order"}
		previous_command=frozen.command_id
		var body:=packet.slice(L.COMPLETION_BYTES+index*L.RESULT_BYTES,L.COMPLETION_BYTES+(index+1)*L.RESULT_BYTES)
		var decoded:=Display.decode_result(body,frozen,id) if work_kind==Display.WORK_KIND else decode_result(body,frozen,id)
		if not decoded.error.is_empty():return decoded
		var value: Dictionary=decoded.value
		if (previous_revision>=0 and value.input_revision!=previous_revision) or value.state_seq!=header.state_seq or value.applied_tick!=header.sim_tick:return {"error":&"completion_result_chain"}
		previous_revision=value.output_revision
		if value.outcome==L.Outcome.REJECTED:rejected+=1
		else:accepted+=1
		results.append(value)
	if (previous_revision>=0 and previous_revision!=header.revision) or accepted!=header.accepted_count or rejected!=header.rejected_count:return {"error":&"completion_result_summary"}
	return {"error":&"","fatal":false,"header":header,"results":results}
