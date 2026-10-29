extends SceneTree

const P=preload("res://scripts/simulation/unified_edit/tool_profile.gd")
const I=preload("res://scripts/simulation/unified_edit/intent.gd")
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const Wire=preload("res://scripts/simulation/unified_edit/protocol.gd")
const DOMAIN=&"main_beach"
const GENERATION:=9007199254740995
const FIRST_ID:=9007199254740993
var registry
var checks: Array=[]
var failed:=false
var output:=""
var emit_abi:=false

func check(name: String, value: bool) -> void:
	checks.append({"name":name,"pass":value});failed=failed or not value
	print("UNIFIED_WIRE ",name," ",value)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--emit-abi":emit_abi=true
	call_deferred("_run")

func request(profile_id: StringName, id: int=FIRST_ID) -> Dictionary:
	var profile: Dictionary=registry.profile(profile_id)
	var value:={"domain_id":DOMAIN,"generation":GENERATION,"command_id":id,"sim_tick":7,"profile_id":profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(3,0),"seed":-9223372036854775807-1}
	if profile.shape==P.Shape.SWEPT_CAPSULE:value.end_xz_m=Vector2(3,0.5)
	if profile.stroke_policy==P.StrokePolicy.FIXED_BASELINE_COVERAGE:
		value.stroke_id=4294967297;value.baseline_token=9007199254740997;value.sample_index=4294967299
	return value

func frozen(profile_id: StringName, id: int=FIRST_ID) -> Dictionary:
	var result:=I.freeze(registry,request(profile_id,id),DOMAIN,GENERATION)
	check("freeze_"+String(profile_id)+"_%d"%checks.size(),result.error.is_empty())
	return result.get("value",{})

func identity() -> Dictionary:
	return {"generation":GENERATION,"batch_seq":9007199254741001,"slot_id":2,"lease_id":9007199254741003,"domain_hash":String(DOMAIN).sha256_text()}

func result_record(value: Dictionary) -> Dictionary:
	var id:=identity()
	var control: bool=value.control_kind!=0
	var config: Dictionary=value.configuration
	var fields:=0 if control else (P.SUSPENDED if config.destination==P.Destination.SUSPENDED_SAND else P.MATERIAL if config.destination==P.Destination.MATERIAL else P.BED)
	var record:={"command_id":value.command_id,"generation":value.generation,"stroke_id":value.stroke_id,"baseline_token":value.baseline_token,"sample_index":value.sample_index,"input_revision":20,"output_revision":20 if control else 21,"applied_tick":12,"state_seq":40,"batch_seq":id.batch_seq,"lease_id":id.lease_id,"slot_id":id.slot_id,"domain_hash":id.domain_hash,"effective_hash":Wire.ZERO_HASH if control else config.effective_hash,"profile_version":0 if control else config.version,"outcome":L.Outcome.NO_CHANGE if control else L.Outcome.APPLIED,"completion_phase":L.GPU_COMPLETE,"changed_fields":fields,"changed_cells":0 if control else 1,"touched_cells":0 if control else 1,"dirty_high":0 if control else 16,"rect_x":0 if control else 130,"rect_z":0 if control else 130,"rect_w":0 if control else 1,"rect_h":0 if control else 1,"ledger":Wire.ledger_for(value),"eps_sand_m3":0.000001,"eps_transfer_m3":0.000002,"eps_water_m3":0.000001,"eps_sediment_m3":0.000001}
	if control:
		for key in L.RESULT_F32:record[key]=0.0
		return record
	match config.operation:
		P.Operation.VOLUME_DELTA:
			var amount: float=value.parameters.amount_m3*value.parameters.strength
			if config.volume_sign==P.VolumeSign.ADD:record.source_m3=amount;record.added_m3=0.01
			else:record.sink_m3=amount;record.removed_m3=0.01
		P.Operation.TARGET_HEIGHT:record.added_m3=0.01;record.source_m3=0.01
		P.Operation.TRANSFER:
			record.added_m3=0.01;record.removed_m3=0.01;record.transferred_m3=0.01;record.left_received_m3=0.005;record.right_received_m3=0.005
	return record

func no_change(record: Dictionary, rejected: bool=false) -> Dictionary:
	var value:=record.duplicate(true)
	value.outcome=L.Outcome.REJECTED if rejected else L.Outcome.NO_CHANGE
	value.error_code=L.ErrorCode.BUDGET_EXCEEDED if rejected else 0
	value.output_revision=value.input_revision
	for key in ["changed_fields","changed_cells","dirty_low","dirty_high","rect_x","rect_z","rect_w","rect_h","coverage_changed"]:value[key]=0
	for key in ["added_m3","removed_m3","transferred_m3","left_received_m3","right_received_m3","displaced_water_m3","retained_water_m3","impulse_x_m4_s","impulse_z_m4_s","max_cell_delta_m","absolute_volume_delta_m3"]:value[key]=0.0
	if value.ledger!=L.Ledger.APPROXIMATE_EXTERNAL:value.source_m3=0.0;value.sink_m3=0.0
	return value

func completion_state(revision: int=21, accepted: int=1, rejected: int=1) -> Dictionary:
	return {"state_seq":40,"sim_tick":12,"revision":revision,"state":L.CompletionState.COMPLETE,"error_flags":0,"advanced_time_s":0.4,"actual_dt":0.0,"accepted_count":accepted,"rejected_count":rejected}

func map_integrity(name: String, size: int, maps: Array) -> void:
	var used:={};var valid:=true
	for pair in maps:
		for offset in pair[0].values():
			valid=valid and offset%4==0 and offset+pair[1]<=size
			for byte in range(offset,offset+pair[1]):
				if used.has(byte):valid=false
				used[byte]=true
	check(name,valid)

func _run() -> void:
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	check("registry",created.error.is_empty())
	if not created.error.is_empty():finish();return
	registry=created.registry
	map_integrity("command_layout_no_overlap",L.COMMAND_BYTES,[[L.COMMAND_U32,4],[L.COMMAND_I64,8],[L.COMMAND_F32,4],[L.COMMAND_HASH,32]])
	map_integrity("result_layout_no_overlap",L.RESULT_BYTES,[[L.RESULT_U32,4],[L.RESULT_I64,8],[L.RESULT_F32,4],[L.RESULT_HASH,32]])
	map_integrity("header_layout_no_overlap",L.HEADER_BYTES,[[L.HEADER_U32,4],[L.HEADER_I64,8],[L.HEADER_HASH,32]])
	map_integrity("completion_layout_no_overlap",L.COMPLETION_BYTES,[[L.COMPLETION_U32,4],[L.COMPLETION_I64,8],[L.COMPLETION_F32,4]])
	check("slot_capacities",L.INPUT_BYTES==32864 and L.OUTPUT_BYTES==24672 and L.WORK_SLOTS==3 and L.HEIGHT_SLOTS==2)
	check("candidate_summary_capacity",L.CELL_BYTES==64 and L.CELL_WORDS.size()==16 and L.REDUCE_BLOCK_BYTES==128 and L.REDUCE_BLOCKS==256)
	if emit_abi:FileAccess.open("res://scripts/simulation/unified_edit/protocol.glslinc",FileAccess.WRITE).store_string(L.shader_defines())
	check("shader_header_matches_layout",FileAccess.get_file_as_string("res://scripts/simulation/unified_edit/protocol.glslinc")==L.shader_defines())
	check("shader_header_uses_uint_words",not ".0u" in L.shader_defines() and "UE_C_COMMAND_ID_WORD 8u" in L.shader_defines())
	for profile_id in [&"dig_v1",&"fill_v1",&"suspended_v1",&"wall_v1",&"castle_v1",&"shovel_v1",&"smooth_v1",&"compact_v1",&"dig_sweep_v1",&"fill_sweep_v1",&"suspended_sweep_v1"]:
		var value:=frozen(profile_id)
		if value.is_empty():finish();return
		var bytes:=Wire.encode_command(value,registry)
		check("fixed_stride_"+String(profile_id),bytes.size()==512)
		var decoded:=Wire.decode_command(bytes,bytes)
		check("roundtrip_"+String(profile_id),decoded.error.is_empty() and not decoded.get("structural_only",true))
		if not decoded.error.is_empty():continue
		check("identity_precision_"+String(profile_id),decoded.value.command_id==FIRST_ID and decoded.value.generation==GENERATION and decoded.value.seed==(-9223372036854775807-1))
		if value.stroke_id!=0:check("stroke_identity_precision_"+String(profile_id),decoded.value.baseline_token==9007199254740997 and decoded.value.sample_index==4294967299)
		var result:=Wire.decode_result(Wire.encode_result(result_record(value)),value,identity())
		check("result_roundtrip_"+String(profile_id),result.error.is_empty())
	var fill:=frozen(&"fill_v1")
	var encoded:=Wire.encode_command(fill,registry)
	var decoded: Dictionary=Wire.decode_command(encoded).value
	check("authorization_never_rounds_up",decoded.available_m3<=0.100001 and decoded.add_budget_m3<=0.1)
	var max_request:=request(&"fill_v1",L.INT64_MAX);max_request.generation=L.INT64_MAX;max_request.sim_tick=L.INT64_MAX
	var max_snapshot:=I.freeze(registry,max_request,DOMAIN,L.INT64_MAX)
	check("int64_max_admitted",max_snapshot.error.is_empty())
	var max_wire:=Wire.decode_command(Wire.encode_command(max_snapshot.value,registry))
	check("int64_max_roundtrip",max_wire.error.is_empty() and max_wire.value.command_id==L.INT64_MAX and max_wire.value.sim_tick==L.INT64_MAX and max_wire.value.generation==L.INT64_MAX)
	check("id_allocation_last_value",I.next_identity(L.INT64_MAX-1).value==L.INT64_MAX)
	check("id_allocation_overflow_rejected",I.next_identity(L.INT64_MAX).error==&"identity_exhausted")
	check("float_identity_allocator_rejected",not I.next_identity(float(FIRST_ID)).error.is_empty())
	for key in ["generation","command_id","sim_tick"]:
		var bad:=request(&"fill_v1");bad[key]=float(bad[key])
		check("float_intent_"+key,not I.freeze(registry,bad,DOMAIN,GENERATION).error.is_empty())
	check("float_owner_generation_rejected",not I.freeze(registry,request(&"fill_v1"),DOMAIN,float(GENERATION)).error.is_empty())
	check("float_control_identity_rejected",not I.control(DOMAIN,float(GENERATION),FIRST_ID,0,1,1,1).error.is_empty())
	check("float_profile_version_rejected",not registry.resolve(&"fill_v1",1.0,registry.profile(&"fill_v1").profile_hash).error.is_empty())
	var bad_request:=request(&"fill_v1");bad_request.domain_id=&"other"
	check("cross_domain_rejected",not I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	bad_request=request(&"wall_v1");bad_request.baseline_token=0
	check("missing_baseline_rejected",not I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	bad_request=request(&"fill_v1");bad_request.start_xz_m=Vector2(NAN,0)
	check("nonfinite_transform_rejected",not I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	bad_request=request(&"wall_v1");bad_request.end_xz_m=Vector2(3,3)
	check("segment_limit",not I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	bad_request=request(&"fill_sweep_v1");bad_request.start_xz_m=Vector2(-15,0);bad_request.end_xz_m=Vector2(15,0)
	check("ordinary_whole_domain_sweep_preserved",I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	bad_request=request(&"fill_v1");bad_request.features={"water_policy":0}
	var selected:=I.freeze(registry,bad_request,DOMAIN,GENERATION)
	var selected_wire:=Wire.decode_command(Wire.encode_command(selected.value,registry))
	check("feature_override_encoded",selected_wire.error.is_empty() and selected_wire.value.water_policy==0 and selected_wire.value.fields==(P.BED|P.MATERIAL))
	bad_request.features={"validate":0}
	check("unsafe_feature_intent_rejected",not I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	bad_request=request(&"wall_v1");bad_request.authorization={"add_budget_m3":0.0}
	var limited:=I.freeze(registry,bad_request,DOMAIN,GENERATION)
	check("restrictive_budget_admitted",limited.error.is_empty())
	var limited_bytes:=Wire.encode_command(limited.value,registry)
	check("restrictive_budget_preserved_on_wire",Wire.decode_command(limited_bytes).value.add_budget_m3==0.0)
	check("unauthorized_result_rejected",not Wire.decode_result(Wire.encode_result(result_record(limited.value)),limited.value,identity()).error.is_empty())
	bad_request.authorization.add_budget_m3=100.0
	check("caller_cannot_expand_authorization",not I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	bad_request.authorization={"transfer_budget_m3":0.0}
	check("caller_cannot_change_authorization_kind",not I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	bad_request=request(&"castle_v1");bad_request.start_xz_m=Vector2(15,0)
	check("stamp_footprint_bound",not I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	bad_request=request(&"fill_v1");bad_request.start_xz_m=Vector2(16,0)
	check("ordinary_edge_clipping_preserved",I.freeze(registry,bad_request,DOMAIN,GENERATION).error.is_empty())
	var forged:=fill.duplicate(true);forged.configuration.derived_fields=0
	check("forged_snapshot_mask_rejected",Wire.encode_command(forged,registry).is_empty())
	forged=fill.duplicate(true);forged.parameters.amount_m3=0.9
	check("modified_snapshot_rejected",Wire.encode_command(forged,registry).is_empty())
	forged=fill.duplicate(true);forged.control_kind=false
	check("boolean_control_rejected",Wire.encode_command(forged,registry).is_empty())
	for pair in [[0,0],[4,2],[8,128],[12,99],[16,99],[20,99],[24,0],[28,128],[80,0],[84,99],[88,99],[92,99],[308,1],[312,2],[360,128],[364,1],[508,1]]:
		var bad:=encoded.duplicate();bad.encode_u32(pair[0],pair[1])
		check("bad_command_word_%d"%pair[0],not Wire.decode_command(bad).error.is_empty())
	var bad_bytes:=encoded.duplicate();bad_bytes.encode_float(192,NAN)
	check("wire_nan_rejected",not Wire.decode_command(bad_bytes).error.is_empty())
	bad_bytes=encoded.duplicate();bad_bytes.encode_float(224,0.5)
	check("unused_field_rejected",not Wire.decode_command(bad_bytes).error.is_empty())
	bad_bytes=encoded.duplicate();bad_bytes.encode_s64(32,-1)
	check("negative_wire_identity",not Wire.decode_command(bad_bytes).error.is_empty())
	for length in [0,128,256,511,513]:
		var bad:=encoded.duplicate();bad.resize(length)
		check("bad_command_length_%d"%length,not Wire.decode_command(bad).error.is_empty())
	var canonical_bad:=encoded.duplicate();canonical_bad.encode_float(248,0.2)
	check("canonical_snapshot_mismatch",not Wire.decode_command(canonical_bad,encoded).error.is_empty())
	for kind in [L.ControlKind.BEGIN,L.ControlKind.END,L.ControlKind.CANCEL]:
		var value: Dictionary=I.control(DOMAIN,GENERATION,FIRST_ID,7,kind,4294967297,9007199254740997).value
		var bytes:=Wire.encode_command(value,registry)
		check("control_wire_%d"%kind,Wire.decode_command(bytes).error.is_empty())
		check("control_result_%d"%kind,Wire.decode_result(Wire.encode_result(result_record(value)),value,identity()).error.is_empty())
		var rejected_control:=result_record(value);rejected_control.outcome=L.Outcome.REJECTED;rejected_control.error_code=L.ErrorCode.INVALID_BASELINE
		check("control_rejection_%d"%kind,Wire.decode_result(Wire.encode_result(rejected_control),value,identity()).error.is_empty())
		rejected_control.eps_sand_m3=0.000001
		check("control_rejection_cannot_report_quantity_%d"%kind,not Wire.decode_result(Wire.encode_result(rejected_control),value,identity()).error.is_empty())
		rejected_control.eps_sand_m3=0.0;rejected_control.outcome=L.Outcome.APPLIED;rejected_control.error_code=0
		rejected_control.output_revision=rejected_control.input_revision+1;rejected_control.changed_fields=P.BED;rejected_control.changed_cells=1;rejected_control.touched_cells=1;rejected_control.dirty_high=16
		rejected_control.rect_x=130;rejected_control.rect_z=130;rejected_control.rect_w=1;rejected_control.rect_h=1
		check("control_cannot_apply_authority_%d"%kind,not Wire.decode_result(Wire.encode_result(rejected_control),value,identity()).error.is_empty())
		bytes.encode_float(192,1.0)
		check("control_cannot_carry_geometry_%d"%kind,not Wire.decode_command(bytes).error.is_empty())
	var commands: Array[PackedByteArray]=[]
	var snapshots: Array=[]
	for index in 64:
		var value:=fill.duplicate(true);value.command_id=FIRST_ID+index
		commands.append(Wire.encode_command(value,registry));snapshots.append(value)
	var packed:=Wire.pack_batch(identity(),commands)
	check("64_command_batch_capacity",packed.size()==L.INPUT_BYTES and Wire.decode_batch(packed,identity()).error.is_empty())
	commands.append(encoded)
	check("65_command_batch_rejected",Wire.pack_batch(identity(),commands).is_empty())
	var reversed: Array[PackedByteArray]=[commands[1],commands[0]]
	check("batch_order_rejected",Wire.pack_batch(identity(),reversed).is_empty())
	var cross:=identity();cross.domain_hash="a".repeat(64)
	check("batch_cross_domain_rejected",not Wire.decode_batch(packed,cross).error.is_empty())
	for pair in [[12,65],[16,128],[20,256],[24,3],[28,99],[88,1]]:
		var bad:=packed.duplicate();bad.encode_u32(pair[0],pair[1])
		check("batch_bad_word_%d"%pair[0],not Wire.decode_batch(bad,identity()).error.is_empty())
	check("tick_header_has_no_fake_brush",Wire.decode_batch(Wire.pack_tick(identity()),identity()).get("work_kind",-1)==L.WorkKind.WATER_TICK)
	var row:=result_record(fill)
	var raw:=Wire.encode_result(row)
	for pair in [[0,0],[4,2],[8,256],[12,4],[96,1],[100,128],[104,31],[108,2],[120,65537],[124,65537],[288,1],[300,1],[316,1],[380,1]]:
		var bad:=raw.duplicate();bad.encode_u32(pair[0],pair[1])
		check("result_bad_word_%d"%pair[0],not Wire.decode_result(bad,fill,identity()).error.is_empty())
	for pair in [[16,FIRST_ID+1],[24,GENERATION-1],[56,22],[64,6],[80,1],[88,1]]:
		var bad:=raw.duplicate();bad.encode_s64(pair[0],pair[1])
		check("result_bad_identity_%d"%pair[0],not Wire.decode_result(bad,fill,identity()).error.is_empty())
	bad_bytes=raw.duplicate();bad_bytes.encode_float(128,NAN)
	check("result_nonfinite",not Wire.decode_result(bad_bytes,fill,identity()).error.is_empty())
	check("result_missing_expected_command",not Wire.decode_result(raw,{},identity()).error.is_empty())
	var nochange:=no_change(row)
	check("ordinary_no_change_keeps_estimated_ledger",Wire.decode_result(Wire.encode_result(nochange),fill,identity()).error.is_empty())
	var rejection:=no_change(row,true)
	check("ordinary_rejection_keeps_estimated_ledger",Wire.decode_result(Wire.encode_result(rejection),fill,identity()).error.is_empty())
	rejection.added_m3=0.01
	check("rejection_cannot_modify_authority",not Wire.decode_result(Wire.encode_result(rejection),fill,identity()).error.is_empty())
	var wall:=frozen(&"wall_v1")
	var coverage:=no_change(result_record(wall));coverage.changed_fields=P.COVERAGE;coverage.coverage_changed=1
	check("coverage_only_does_not_advance_revision",Wire.decode_result(Wire.encode_result(coverage),wall,identity()).error.is_empty())
	var shovel:=frozen(&"shovel_v1")
	var transfer:=result_record(shovel);transfer.source_m3=0.1
	check("transfer_cannot_use_external_source",not Wire.decode_result(Wire.encode_result(transfer),shovel,identity()).error.is_empty())
	transfer=result_record(shovel);transfer.right_received_m3=0.0
	check("transfer_missing_receipt_rejected",not Wire.decode_result(Wire.encode_result(transfer),shovel,identity()).error.is_empty())
	transfer=result_record(shovel);transfer.right_received_m3=0.0;transfer.added_m3=0.005;transfer.transferred_m3=0.005;transfer.sink_m3=0.005
	check("capped_transfer_unbalanced_with_exact_sink",Wire.decode_result(Wire.encode_result(transfer),shovel,identity()).error.is_empty())
	transfer.sink_m3=0.0
	check("capped_transfer_missing_sink_rejected",not Wire.decode_result(Wire.encode_result(transfer),shovel,identity()).error.is_empty())
	transfer=result_record(shovel);transfer.left_received_m3=0.0;transfer.right_received_m3=0.0;transfer.added_m3=0.0;transfer.transferred_m3=0.0;transfer.sink_m3=0.01
	check("capped_transfer_full_sink",Wire.decode_result(Wire.encode_result(transfer),shovel,identity()).error.is_empty())
	transfer.sink_m3=0.02
	check("capped_transfer_excess_sink_rejected",not Wire.decode_result(Wire.encode_result(transfer),shovel,identity()).error.is_empty())
	transfer=result_record(shovel);transfer.added_m3=0.1
	check("transfer_cannot_create_sand",not Wire.decode_result(Wire.encode_result(transfer),shovel,identity()).error.is_empty())
	var overflow:=result_record(fill);overflow.added_m3=0.5
	check("volume_cannot_exceed_authorization",not Wire.decode_result(Wire.encode_result(overflow),fill,identity()).error.is_empty())
	var compact:=frozen(&"compact_v1");var compact_result:=result_record(compact);compact_result.added_m3=0.01
	check("compact_cannot_hide_volume_change",not Wire.decode_result(Wire.encode_result(compact_result),compact,identity()).error.is_empty())
	var smooth:=frozen(&"smooth_v1");var smooth_result:=result_record(smooth);smooth_result.added_m3=0.01
	check("smooth_must_conserve_volume",not Wire.decode_result(Wire.encode_result(smooth_result),smooth,identity()).error.is_empty())
	var excessive_error:=result_record(fill);excessive_error.water_error_m3=0.01
	check("applied_cannot_hide_water_error",not Wire.decode_result(Wire.encode_result(excessive_error),fill,identity()).error.is_empty())
	var next:=fill.duplicate(true);next.command_id=FIRST_ID+1
	var first_result:=Wire.encode_result(no_change(result_record(fill),true))
	var second_result:=Wire.encode_result(result_record(next))
	var results: Array[PackedByteArray]=[first_result,second_result]
	var packet:=Wire.encode_completion(identity(),results,completion_state())
	var completion:=Wire.decode_completion(packet,identity(),[fill,next])
	check("rejected_then_applied_packet",completion.error.is_empty() and completion.results[0].outcome==L.Outcome.REJECTED and completion.results[1].outcome==L.Outcome.APPLIED)
	var wrong_second:=result_record(next);wrong_second.input_revision=21;wrong_second.output_revision=22
	var wrong_results: Array[PackedByteArray]=[first_result,Wire.encode_result(wrong_second)]
	check("actual_revision_chain_checked",not Wire.decode_completion(Wire.encode_completion(identity(),wrong_results,completion_state(22)),identity(),[fill,next]).error.is_empty())
	for pair in [[0,0],[4,2],[8,80],[12,1],[64,0],[68,3],[72,1],[76,256],[88,2],[92,0]]:
		var bad:=packet.duplicate();bad.encode_u32(pair[0],pair[1])
		check("completion_bad_word_%d"%pair[0],not Wire.decode_completion(bad,identity(),[fill,next]).error.is_empty())
	var fatal_state:=completion_state();fatal_state.state=L.CompletionState.FATAL;fatal_state.error_flags=4
	var fatal:=Wire.decode_completion(Wire.encode_completion(identity(),results,fatal_state),identity(),[fill,next])
	check("fatal_is_not_business_rejection",fatal.error.is_empty() and fatal.fatal and fatal.results.is_empty() and fatal.raw_results.size()==2*L.RESULT_BYTES)
	for flag in [16,32,63]:
		fatal_state.error_flags=flag
		var flagged:=Wire.decode_completion(Wire.encode_completion(identity(),results,fatal_state),identity(),[fill,next])
		check("fatal_preserves_flags_"+str(flag),flagged.error.is_empty() and flagged.fatal and flagged.results.is_empty())
	fatal_state.error_flags=64
	check("fatal_unknown_flag_rejected",not Wire.decode_completion(Wire.encode_completion(identity(),results,fatal_state),identity(),[fill,next]).error.is_empty())
	for length in [0,80,336,479,481]:
		var legacy:=PackedByteArray();legacy.resize(length)
		check("legacy_or_bad_completion_size_%d"%length,not Wire.decode_completion(legacy,identity(),[fill]).error.is_empty())
	var zero_results: Array[PackedByteArray]=[]
	var water_state:=completion_state(20,0,0);water_state.actual_dt=1.0/30.0
	check("water_tick_completion",Wire.decode_completion(Wire.encode_completion(identity(),zero_results,water_state),identity(),[],L.WorkKind.WATER_TICK).error.is_empty())
	finish()

func finish() -> void:
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"layout":L.description(),"scope":"T01 CPU data/ABI only; no new GPU execution or ownership release claim"},"\t"))
	quit(1 if failed else 0)
