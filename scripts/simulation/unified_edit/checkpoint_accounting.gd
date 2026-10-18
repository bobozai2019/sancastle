extends RefCounted

# Non-authoritative lifecycle metadata. Approximate nominal history is never
# advertised as physical stock; exact operations settle only validated results.
const P=preload("res://scripts/simulation/unified_edit/tool_profile.gd")
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const Wire=preload("res://scripts/simulation/unified_edit/protocol.gd")
var ledger:={"tool_inventory_m3":0.0,"sand_source_m3":0.0,"sand_sink_m3":0.0,"water_source_m3":0.0,"water_sink_m3":0.0}
var initial_sand_total_m3:=0.0
var nominal_upper_supply:=0.0
var material_ever_used:=false
var ticket_floor:=0
var wave_highwater_id:=0
var stroke: Dictionary={}
var inactive_foam: Dictionary={}
var provenance: Dictionary={"format":"native_v6","path":"","sha256":"","configuration":{},"trusted_fixture":{},"original_prefix":[],"policies":{}}
var water_anchor:=PackedFloat64Array([0.0,0.0])
var water_ledger_anchor:=PackedFloat64Array([0.0,0.0])
var water_state_seq:=0
var immutable_hashes: Dictionary={}

func initialize(domain, restored: Dictionary) -> StringName:
	if not restored.is_empty():
		ledger=restored.ledger.duplicate(true);initial_sand_total_m3=restored.initial_sand_total_m3;nominal_upper_supply=restored.nominal_upper_supply
		material_ever_used=restored.native.material.ever_used;ticket_floor=restored.ticket_id;wave_highwater_id=restored.wave_highwater_id
		inactive_foam=restored.native.foam.duplicate(true);provenance=restored.source_provenance.duplicate(true)
		water_anchor=PackedFloat64Array([restored.native.control.decode_float(88),restored.native.control.decode_float(92)]);water_state_seq=restored.state_seq
		immutable_hashes={"rock":_sha(restored.native.fields.rock),"obstacle":_sha(restored.native.fields.obstacle)}
	else:
		for key in ledger:
			var value: Variant=domain.get(key)
			if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(value) or value<0.0 or (key=="tool_inventory_m3" and value!=0.0):return &"invalid_initial_ledger"
			ledger[key]=float(value)
		var bed:=PackedFloat32Array();bed.resize(65536)
		var tagged: Variant=domain.get_meta("brush_initial_mold_depth",PackedFloat32Array())
		for index in 65536:
			initial_sand_total_m3+=(float(domain.sand[index])+float(domain.sediment[index]))*0.015625
			bed[index]=domain.rock[index]+domain.sand[index]
			if tagged is PackedFloat32Array and tagged.size()==65536 and tagged[index]>0.0:material_ever_used=true
		var foam:=PackedByteArray();foam.resize(65536*8)
		# Explicitly disabled history has CPU seed data, not fictional GPU data.
		inactive_foam={"current_index":0,"foam_0":foam,"foam_1":foam,"bed_0":bed.to_byte_array(),"bed_1":bed.to_byte_array()}
		var obstacle:=PackedByteArray();obstacle.resize(65536)
		for index in 65536:obstacle[index]=255 if domain.obstacle[index]>=0.5 else 0
		immutable_hashes={"rock":_sha(domain.rock.to_byte_array()),"obstacle":_sha(obstacle)}
	water_ledger_anchor=PackedFloat64Array([ledger.water_source_m3,ledger.water_sink_m3])
	return &""

func book_record(commands: Array) -> void:
	for command in commands:
		if command.control_kind!=L.ControlKind.NONE:continue
		if Wire.ledger_for(command)==L.Ledger.APPROXIMATE_EXTERNAL:
			var amount: float=command.parameters.amount_m3*command.parameters.strength
			if command.configuration.volume_sign==P.VolumeSign.ADD:ledger.sand_source_m3+=amount;nominal_upper_supply+=2.0*amount+1.0
			else:ledger.sand_sink_m3+=amount
		elif command.configuration.operation==P.Operation.TARGET_HEIGHT:
			var budgets:=Wire._budgets(command)
			nominal_upper_supply+=2.0*budgets.add_budget_m3+1.0

func settle(command: Dictionary, result: Dictionary) -> void:
	if command.control_kind!=L.ControlKind.NONE:
		if result.outcome!=L.Outcome.REJECTED:
			if command.control_kind==L.ControlKind.BEGIN:stroke={"stroke_id":command.stroke_id,"baseline_token":command.baseline_token}
			else:stroke={}
		return
	if result.ledger==L.Ledger.EXACT_EXTERNAL and result.outcome==L.Outcome.APPLIED:ledger.sand_source_m3+=result.source_m3;ledger.sand_sink_m3+=result.sink_m3
	if result.outcome==L.Outcome.APPLIED and command.configuration.material_policy==P.MaterialPolicy.MOLDED and (result.changed_fields&P.MATERIAL)!=0:material_ever_used=true

func water_ledger(control: PackedByteArray) -> Dictionary:
	var source: float=control.decode_float(88);var sink: float=control.decode_float(92)
	if source<water_anchor[0] or sink<water_anchor[1]:return {"error":&"checkpoint_water_counter_regression"}
	var result: Dictionary=ledger.duplicate(true)
	result.water_source_m3=water_ledger_anchor[0]+(source-water_anchor[0]);result.water_sink_m3=water_ledger_anchor[1]+(sink-water_anchor[1])
	return {"error":&"","value":result}

func observe_water(control: PackedByteArray, values: Dictionary) -> void:
	ledger.water_source_m3=values.water_source_m3;ledger.water_sink_m3=values.water_sink_m3;water_state_seq=control.decode_s64(16)

func _sha(bytes: PackedByteArray) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
