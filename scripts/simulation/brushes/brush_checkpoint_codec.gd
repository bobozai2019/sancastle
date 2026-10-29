extends RefCounted

const Brush=preload("res://scripts/simulation/brushes/brush_protocol.gd")
const Legacy=preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
const Original=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")

static func keys(value:Variant,expected:Array) -> bool:
	if not value is Dictionary or value.size()!=expected.size():return false
	for key in expected:
		if not value.has(key):return false
	return true

static func number(value:Variant) -> bool:return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value))

static func selection_error(selection:Variant) -> StringName:
	if not keys(selection,["tool","parameters","dig_amount_m3","fill_amount_m3"]):return &"invalid_brush_selection"
	if typeof(selection.tool) not in [TYPE_STRING,TYPE_STRING_NAME] or not selection.parameters is Dictionary:return &"invalid_brush_selection"
	for key in ["dig_amount_m3","fill_amount_m3"]:
		if not number(selection[key]) or selection[key]<0.01 or selection[key]>1.0:return &"invalid_brush_selection"
	if selection.tool in [&"remove_sand",&"place_sand",&"suspended_sand"]:return &"" if selection.parameters.is_empty() else &"invalid_brush_selection"
	if selection.tool == &"gravel_drop":
		return &"" if keys(selection.parameters, ["count"]) and typeof(selection.parameters.count) == TYPE_INT and selection.parameters.count >= 1 and selection.parameters.count <= 128 else &"invalid_brush_selection"
	return &"" if Brush.Spec.parameter_error(StringName(selection.tool),selection.parameters).is_empty() else &"invalid_brush_selection"

static func same_result(result:Dictionary,decoded:Dictionary) -> bool:
	if not decoded.get("ok",false) or result.size()!=decoded.size():return false
	for key in decoded:
		if not result.has(key) or typeof(result[key])!=typeof(decoded[key]) or result[key]!=decoded[key]:return false
	return true

static func validate_edit(checkpoint:Dictionary,signature:Dictionary) -> StringName:
	var edit:Dictionary=checkpoint.gpu_beach_edit
	if not keys(edit,["version","brush_schema","configuration","prefix","ledger","selection","pending_count","reserved_m3"]) or edit.version!=4 or typeof(edit.brush_schema)!=TYPE_INT or edit.brush_schema!=2:return &"invalid_brush_edit_header"
	if checkpoint.gpu_beach_native.version!=2 or edit.configuration!=signature or not signature.get("brush_checkpoint_v4_enabled",false) or not signature.get("brush_native_material_enabled",false):return &"brush_checkpoint_configuration_mismatch"
	if not edit.prefix is Array or not edit.ledger is Dictionary or typeof(edit.pending_count)!=TYPE_INT or edit.pending_count!=0 or not number(edit.reserved_m3) or edit.reserved_m3!=0.0:return &"unsettled_brush_checkpoint"
	if not keys(edit.selection,["policy","speed","sand_accounting","brush"]) or typeof(edit.selection.policy)!=TYPE_INT or edit.selection.policy not in [0,1,2,3] or not number(edit.selection.speed) or absf(edit.selection.speed)>1.0 or edit.selection.sand_accounting!="external_v1":return &"invalid_brush_edit_selection"
	var error:=selection_error(edit.selection.brush)
	if not error.is_empty():return error
	if not checkpoint.command_ids.is_empty():return &"invalid_beach_legacy_projection"
	var sidecar:Dictionary={"version":1,"fixture":"edit_recovery_numeric_v1","grid_size":256,"cell_size_m":0.125,"tick":checkpoint.tick,"generation":checkpoint.shadow.generation,"revision":checkpoint.revision,"highwater_id":checkpoint.highwater_id,"pending_count":0,"reserved_m3":0.0,"raw_fields":checkpoint.gpu_beach_native.fields,"ledger":edit.ledger,"prefix":[],"visual_history":{}}
	error=Original.validate(sidecar)
	if not error.is_empty():return error
	if edit.ledger.tool_inventory_m3!=0.0:return &"invalid_external_sand_ledger"
	for key in ["tool_inventory_m3","sand_source_m3","sand_sink_m3"]:
		if edit.ledger[key]!=checkpoint.shadow[key]:return &"invalid_beach_ledger_projection"
	for key in ["water_source_m3","water_sink_m3"]:
		if edit.ledger[key]!=checkpoint[key]:return &"invalid_beach_ledger_projection"
	var last_id:=0;var last_generation:=0;var last_tick:=0;var source:=0.0;var sink:=0.0
	var stroke_samples:Dictionary={}
	for row in edit.prefix:
		var expected:Array=["backend","sand_accounting","command","result","policy","speed","stock_before","available_m3","execution_tick"]
		if row is Dictionary and row.get("backend")!="legacy_cpu":expected.append("receipt_raw")
		if not keys(row,expected) or not row.command is Dictionary or not row.result is Dictionary or row.sand_accounting!="external_v1":return &"invalid_brush_prefix"
		var command:Dictionary=row.command;var result:Dictionary=row.result
		if typeof(command.get("command_id"))!=TYPE_INT or command.command_id<=last_id or command.command_id>checkpoint.highwater_id or typeof(command.get("generation"))!=TYPE_INT or command.generation<maxi(1,last_generation) or command.generation>checkpoint.shadow.generation or command.get("domain_id")!=checkpoint.shadow.domain_id:return &"invalid_brush_prefix_identity"
		if typeof(command.get("sim_tick"))!=TYPE_INT or command.sim_tick<0 or typeof(row.execution_tick)!=TYPE_INT or row.execution_tick<command.sim_tick or row.execution_tick<last_tick or row.execution_tick>checkpoint.tick:return &"invalid_brush_prefix_tick"
		if typeof(row.policy)!=TYPE_INT or row.policy not in [0,1,2,3] or not number(row.speed) or absf(row.speed)>1.0 or not number(row.available_m3) or row.available_m3<0.0 or not number(row.stock_before) or row.stock_before!=0.0:return &"invalid_brush_prefix_authorization"
		if row.backend=="brush_v2":
			error=Brush.command_error(command)
			if not error.is_empty():return error
			if not row.receipt_raw is PackedByteArray:return &"invalid_brush_receipt_raw"
			var decoded:=Brush.decode_receipt(row.receipt_raw)
			if not same_result(result,decoded) or typeof(result.get("ticket_id"))!=TYPE_INT or result.ticket_id<=0 or typeof(result.get("input_revision"))!=TYPE_INT or result.input_revision<0 or result.output_revision>checkpoint.revision or not Brush.receipt_matches(result,command,result.ticket_id,result.input_revision):return &"invalid_brush_prefix_receipt"
			if row.policy!=command.water_policy or row.speed!=command.speed_m_s or row.available_m3!=command.add_budget_m3 or result.applied_tick!=row.execution_tick:return &"invalid_brush_prefix_authorization"
			var wire:=Brush.encode(command,result.ticket_id,result.input_revision)
			var budget:float=wire.decode_float(156 if command.brush_id==&"shovel_v1" else 152)
			if result.requested_budget_m3!=budget:return &"invalid_brush_prefix_budget"
			if result.status==1:
				if command.brush_id==&"shovel_v1":
					if result.removed_m3>budget+result.eps_sand_m3 or absf(result.sand_error_m3)>result.eps_transfer_m3 or absf(result.left_received_m3-result.right_received_m3)>result.eps_transfer_m3:return &"invalid_brush_prefix_transfer"
				elif result.added_m3>budget+result.eps_sand_m3 or result.transferred_m3!=0.0 or result.left_received_m3!=0.0 or result.right_received_m3!=0.0:return &"invalid_brush_prefix_budget"
			var stroke_key:=str([command.generation,command.stroke_id,command.baseline_token])
			if stroke_samples.has(stroke_key) and command.sample_index<=stroke_samples[stroke_key]:return &"invalid_brush_prefix_sample"
			stroke_samples[stroke_key]=command.sample_index
			source+=result.external_source_delta_m3;sink+=result.external_sink_delta_m3
		elif row.backend in ["legacy_v1","legacy_cpu"]:
			if command.has("schema_version"):return &"invalid_brush_prefix_backend"
			var old:Dictionary=row.duplicate(true);old.backend="gpu" if row.backend=="legacy_v1" else "legacy_cpu"
			if row.backend=="legacy_cpu":old.sand_accounting="inventory"
			old.erase("receipt_raw");sidecar.prefix=[old]
			error=Original.validate(sidecar)
			if not error.is_empty():return error
			if result.applied_tick!=row.execution_tick:return &"invalid_brush_prefix_tick"
			if row.backend=="legacy_v1":
				if not row.receipt_raw is PackedByteArray:return &"invalid_brush_receipt_raw"
				if not same_result(result,Legacy.decode_receipt(row.receipt_raw)) or result.ticket_id<=0 or result.input_revision<0 or result.output_revision>checkpoint.revision or not Legacy.receipt_matches(result,result.ticket_id,command.command_id,command.generation,result.input_revision):return &"invalid_brush_prefix_receipt"
				if result.status!=1 and (result.actual_sand_m3!=0.0 or result.edited_cells!=0):return &"invalid_brush_prefix_receipt"
				if result.status==1:
					if command.kind==&"place_sand":source+=result.actual_sand_m3
					else:sink+=result.actual_sand_m3
			elif row.available_m3!=0.0:return &"invalid_brush_prefix_authorization"
		else:return &"invalid_brush_prefix_backend"
		last_id=command.command_id;last_generation=command.generation;last_tick=row.execution_tick
	if source!=edit.ledger.sand_source_m3 or sink!=edit.ledger.sand_sink_m3:return &"invalid_brush_prefix_ledger"
	return &""
