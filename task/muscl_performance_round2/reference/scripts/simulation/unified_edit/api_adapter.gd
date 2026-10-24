extends RefCounted

# Old names are confined to this data boundary. No legacy writer is created.
const I=preload("res://scripts/simulation/unified_edit/intent.gd")
const P=preload("res://scripts/simulation/unified_edit/tool_profile.gd")
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const Brush=preload("res://scripts/simulation/brushes/brush_protocol.gd")
const BASE=["domain_id","sim_tick","command_id","kind","shape","transform","radius_m","strength","seed"]
const OPTIONAL=["generation","schema_version","amount_m3","sand_destination"]

# Data conversion only. The owning stroke stage must actually execute BEGIN /
# END / CANCEL before these envelopes can be advertised as a runtime API.
static func control(mode: Variant, identity: Dictionary) -> Dictionary:
	if typeof(mode) not in [TYPE_STRING,TYPE_STRING_NAME] or String(mode) not in ["begin","end","cancel"] or identity.size()!=6:return {"error":&"invalid_control"}
	for key in ["domain_id","generation","command_id","sim_tick","stroke_id","baseline_token"]:
		if not identity.has(key):return {"error":&"invalid_control"}
	var kind: int={"begin":L.ControlKind.BEGIN,"end":L.ControlKind.END,"cancel":L.ControlKind.CANCEL}[String(mode)]
	return I.control(identity.domain_id,identity.generation,identity.command_id,identity.sim_tick,kind,identity.stroke_id,identity.baseline_token)

static func adapt(registry, command: Dictionary, domain: StringName, generation: int, water_policy: Variant=3, speed: Variant=0.0) -> Dictionary:
	if typeof(command.get("schema_version",1))!=TYPE_INT:return {"error":&"invalid_input"}
	if command.get("schema_version",1)==2:return _shape(registry,command,domain,generation)
	if command.get("schema_version",1)!=1:return {"error":&"unsupported_schema"}
	for key in BASE:
		if not command.has(key):return {"error":&"invalid_input"}
	for key in command:
		if key not in BASE and key not in OPTIONAL:return {"error":&"invalid_input"}
	if typeof(command.kind) not in [TYPE_STRING,TYPE_STRING_NAME] or command.kind not in [&"remove_sand",&"place_sand",&"smooth",&"compact"] or command.shape not in [&"circle",&"swept_segment"] or not command.transform is Dictionary:return {"error":&"invalid_input"}
	for key in command.transform:
		if key not in ["position_m","end_position_m"]:return {"error":&"invalid_input"}
	var a: Variant=command.transform.get("position_m")
	var b: Variant=command.transform.get("end_position_m",a)
	if not a is Vector3 or not b is Vector3 or not a.is_finite() or not b.is_finite() or (command.shape==&"swept_segment" and not command.transform.has("end_position_m")):return {"error":&"invalid_input"}
	if typeof(water_policy)!=TYPE_INT or water_policy not in [0,1,2,3] or not P.finite_number(speed) or absf(speed)>1.0:return {"error":&"invalid_input"}
	var destination: Variant=command.get("sand_destination","bed")
	if destination not in ["bed","suspended_v1"] or (destination=="suspended_v1" and command.kind!=&"place_sand"):return {"error":&"invalid_input"}
	var profile_id: StringName
	match command.kind:
		&"remove_sand":profile_id=&"dig_sweep_v1" if command.shape==&"swept_segment" else &"dig_v1"
		&"place_sand":
			if destination=="suspended_v1":profile_id=&"suspended_sweep_v1" if command.shape==&"swept_segment" else &"suspended_v1"
			else:profile_id=&"fill_sweep_v1" if command.shape==&"swept_segment" else &"fill_v1"
		&"smooth",&"compact":
			if command.shape!=&"circle":return {"error":&"invalid_input"}
			profile_id=&"smooth_v1" if command.kind==&"smooth" else &"compact_v1"
	var params:={"radius_m":command.radius_m,"strength":command.strength}
	var features:={"water_policy":water_policy}
	if profile_id in [&"smooth_v1",&"compact_v1"] or destination=="suspended_v1":
		# These old operations never performed a bed displacement response.
		features.water_policy=0
		if command.has("amount_m3") and not P.finite_number(command.amount_m3):return {"error":&"invalid_input"}
	if profile_id not in [&"smooth_v1",&"compact_v1"]:
		params.amount_m3=command.get("amount_m3")
		if destination=="bed":params.speed_m_s=speed
	var profile: Dictionary=registry.profile(profile_id)
	if profile.is_empty():return {"error":&"invalid_profile"}
	var request:={"domain_id":command.domain_id,"generation":command.get("generation",generation),"command_id":command.command_id,"sim_tick":command.sim_tick,"profile_id":profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(a.x,a.z),"parameters":params,"features":features,"seed":command.seed,"source_context":"legacy_public_api"}
	if command.shape==&"swept_segment":request.end_xz_m=Vector2(b.x,b.z)
	return _freeze_request(registry,request,domain,generation)

static func _shape(registry, command: Dictionary, domain: StringName, generation: int) -> Dictionary:
	var error:=Brush.command_error(command)
	if not error.is_empty():return {"error":error}
	var profile: Dictionary=registry.profile(StringName(command.brush_id))
	if profile.is_empty():return {"error":&"invalid_profile"}
	if not profile.template.is_empty() and profile.template.sha256!=command.template_hash:return {"error":&"template_mismatch"}
	var params:={}
	for key in profile.defaults:
		if key=="speed_m_s":params[key]=command.speed_m_s
		else:params[key]=command[key]
	var features:={"water_policy":command.water_policy,"material_policy":P.MaterialPolicy.MOLDED if command.material_profile_id==&"molded_v1" else P.MaterialPolicy.PLAIN}
	if profile.operation==P.Operation.TRANSFER:features.material_policy=P.MaterialPolicy.PRESERVE
	var auth:={"transfer_budget_m3":command.transfer_budget_m3} if profile.operation==P.Operation.TRANSFER else {"add_budget_m3":command.add_budget_m3}
	var request:={"domain_id":command.domain_id,"generation":command.generation,"command_id":command.command_id,"sim_tick":command.sim_tick,"profile_id":profile.profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":command.start_xz_m,"end_xz_m":command.end_xz_m,"parameters":params,"features":features,"authorization":auth,"seed":command.seed,"stroke_id":command.stroke_id,"baseline_token":command.baseline_token,"sample_index":command.sample_index,"source_context":"legacy_shape_api"}
	return _freeze_request(registry,request,domain,generation)

static func _freeze_request(registry, request: Dictionary, domain: StringName, generation: int) -> Dictionary:
	var frozen:=I.freeze(registry,request,domain,generation)
	if not frozen.error.is_empty():return frozen
	return {"error":&"","request":request.duplicate(true),"frozen":frozen.value}
