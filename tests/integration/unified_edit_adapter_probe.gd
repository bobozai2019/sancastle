extends SceneTree

const A=preload("res://scripts/simulation/unified_edit/api_adapter.gd")
const W=preload("res://scripts/simulation/unified_edit/protocol.gd")
const B=preload("res://scripts/simulation/brushes/brush_protocol.gd")
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
var registry
var checks: Array=[]
var failed:=false
var output:=""

func check(name: String, value: bool) -> void:
	checks.append({"name":name,"pass":value});failed=failed or not value
	print("UNIFIED_ADAPTER ",name," ",value)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")

func ordinary(kind: StringName=&"place_sand", shape: StringName=&"circle") -> Dictionary:
	var transform:={"position_m":Vector3(0,77,0)}
	if shape==&"swept_segment":transform.end_position_m=Vector3(1,-99,0.5)
	return {"domain_id":&"main_beach","generation":9007199254740993,"command_id":9007199254740995,"sim_tick":7,"kind":kind,"shape":shape,"transform":transform,"radius_m":0.75,"strength":1.0,"amount_m3":0.1,"seed":101}

func adapt(value: Dictionary, policy: Variant=3, speed: Variant=0.0) -> Dictionary:
	return A.adapt(registry,value,&"main_beach",9007199254740993,policy,speed)

func _run() -> void:
	registry=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry().registry
	for kind in [&"remove_sand",&"place_sand",&"smooth",&"compact"]:
		for shape in [&"circle",&"swept_segment"]:
			var mapped:=adapt(ordinary(kind,shape))
			if kind in [&"smooth",&"compact"] and shape==&"swept_segment":check("unsupported_sweep_"+String(kind),not mapped.error.is_empty());continue
			check("map_"+String(kind)+"_"+String(shape),mapped.error.is_empty())
			if mapped.error.is_empty():check("canonical_wire_"+String(kind)+String(shape),not W.encode_command(mapped.frozen,registry).is_empty() and mapped.frozen.command_id==9007199254740995 and mapped.frozen.generation==9007199254740993)
	var command:=ordinary();command.sand_destination="suspended_v1"
	check("suspended_mapping",adapt(command).frozen.profile_id=="suspended_v1")
	command=ordinary(&"remove_sand");command.sand_destination="suspended_v1"
	check("suspended_remove_rejected",not adapt(command).error.is_empty())
	for pair in [["kind",&"unknown"],["shape",&"unknown"],["generation",9007199254740993.0],["command_id",9007199254740995.0],["seed",1.0],["amount_m3",NAN],["strength",INF],["radius_m",0.0],["schema_version",3],["schema_version",1.0],["domain_id",&"other"],["execute",Callable()]]:
		command=ordinary();command[pair[0]]=pair[1];check("invalid_"+str(checks.size()),not adapt(command).error.is_empty())
	command=ordinary();command.transform.position_m=Vector3(NAN,0,0)
	check("invalid_transform_rejected",not adapt(command).error.is_empty())
	command=ordinary();command.transform.callback=Callable()
	check("injected_transform_key_rejected",not adapt(command).error.is_empty())
	command=ordinary();command.schema_version=1
	check("explicit_schema_one",adapt(command).error.is_empty())
	check("water_off_explicit",adapt(command,0).frozen.configuration.water_policy==0)
	check("inactive_impulse_rejected",not adapt(command,0,0.5).error.is_empty())
	check("policy_float_rejected",not adapt(command,0.0).error.is_empty())
	command.erase("generation")
	check("old_optional_generation_uses_owner_epoch",adapt(command).frozen.generation==9007199254740993)
	for profile_id in [&"castle_v1",&"wall_v1",&"shovel_v1"]:
		var definition=B.registry.definition(profile_id)
		var old:=B.make_command(profile_id,definition.default_params,Vector2.ZERO,Vector2.ZERO,&"main_beach",9007199254740993,9007199254740995,9007199254740997,1,7,9007199254740999)
		var mapped:=adapt(old)
		check("old_definition_"+String(profile_id),mapped.error.is_empty())
		if mapped.error.is_empty():
			check("old_wire_"+String(profile_id),not W.encode_command(mapped.frozen,registry).is_empty())
			check("old_stroke_"+String(profile_id),mapped.frozen.stroke_id==old.stroke_id and mapped.frozen.baseline_token==old.baseline_token and mapped.frozen.sample_index==1)
		old["transfer_budget_m3" if profile_id==&"shovel_v1" else "add_budget_m3"]=0.0
		mapped=adapt(old)
		check("restricted_zero_"+String(profile_id),mapped.error.is_empty() and mapped.frozen.authorization.values()[0]==0.0)
		old.definition_hash="0".repeat(64)
		check("old_identity_rejected_"+String(profile_id),not adapt(old).error.is_empty())
	var control_id:={"domain_id":&"main_beach","generation":9007199254740993,"command_id":9007199254740995,"sim_tick":7,"stroke_id":9007199254740997,"baseline_token":9007199254740999}
	for mode in ["begin","end","cancel"]:
		var converted:=A.control(mode,control_id)
		check("control_data_"+mode,converted.error.is_empty() and not W.encode_command(converted.value,registry).is_empty())
	check("unknown_control_rejected",not A.control("other",control_id).error.is_empty())
	control_id.command_id=1.0
	check("control_float_id_rejected",not A.control("begin",control_id).error.is_empty())
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"scope":"legacy API pure-data to canonical intent; no legacy writer instantiation"},"\t"))
	quit(1 if failed else 0)
