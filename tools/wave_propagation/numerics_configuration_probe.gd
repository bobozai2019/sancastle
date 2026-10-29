extends SceneTree
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
var rows: Array=[]
var failed:=false

func check(name: String,okay: bool) -> void:
	rows.append({"name":name,"pass":okay});failed=failed or not okay

func _initialize() -> void:
	var output:=""
	var legacy:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--legacy="):legacy=arg.trim_prefix("--legacy=")
	if output.is_empty() or FileAccess.file_exists(output):quit(2);return
	var registry: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	var flags:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	var effects:={"foam_enabled":false,"gravel_enabled":false}
	var default_configuration:=Config.freeze(registry.registry,"main_beach",flags,effects,{}, {},extra)
	var first:=Config.freeze(registry.registry,"main_beach",flags,effects,{}, {"water_numerics":{"schema":1,"solver_id":"rusanov_first_order_v1"}},extra)
	var second:=Config.freeze(registry.registry,"main_beach",flags,effects,{}, {"water_numerics":{"schema":1,"solver_id":"muscl_mc_ssprk2_v1"}},extra)
	check("valid_startup_default",default_configuration.error.is_empty() and default_configuration.value.environment.water_numerics.solver_id==Config.Numerics.DEFAULT_SOLVER and Config.validate(default_configuration.value,true).is_empty())
	check("valid_explicit_first_order",first.error.is_empty() and first.value.environment.water_numerics.solver_id==Config.Numerics.FIRST_ORDER and Config.validate(first.value,true).is_empty())
	check("missing_historical_solver_stays_first_order",Config.Numerics.solver_id({})==Config.Numerics.FIRST_ORDER)
	check("valid_explicit_muscl",second.error.is_empty() and Config.validate(second.value,true).is_empty())
	check("algorithm_changes_hash_same_sources",first.value.configuration_hash!=second.value.configuration_hash and first.value.sources==second.value.sources)
	var obsolete_policy: Dictionary=first.value.duplicate(true)
	obsolete_policy.ledger_policy.transfer="conservative_source_sink_unchanged_v1";obsolete_policy.configuration_hash=Config.stable_hash(obsolete_policy)
	check("runtime_rejects_historical_ledger_policy",Config.validate(obsolete_policy,false)==&"invalid_configuration_catalog")
	for test in [[{},"invalid_water_numerics"],["bad","invalid_water_numerics"],[{"schema":true,"solver_id":"muscl_mc_ssprk2_v1"},"invalid_water_numerics"],[{"schema":99,"solver_id":"muscl_mc_ssprk2_v1"},"unsupported_water_numerics_schema"],[{"schema":1,"solver_id":"unknown"},"unknown_water_solver_id"],[{"schema":1,"solver_id":"muscl_mc_ssprk2_v1","courant":0.9},"invalid_water_numerics"]]:
		var invalid:=Config.freeze(registry.registry,"main_beach",flags,effects,{}, {"water_numerics":test[0]},extra)
		check("reject:"+test[1],String(invalid.error)==test[1])
	for amount in [0.0,0.5,1.0]:
		var tuned:=Config.freeze(registry.registry,"main_beach",flags,effects,{}, {"water_numerics":Config.Numerics.selection(Config.Numerics.MUSCL,amount)},extra)
		check("retention_valid:"+str(amount),tuned.error.is_empty() and Config.Numerics.retention(tuned.value.environment)==amount and Config.validate(tuned.value,true).is_empty())
	for amount in [-0.1,1.1,NAN,INF,true,"0.5"]:
		check("retention_invalid:"+str(amount),not Config.Numerics.configuration_error({"water_numerics":{"schema":2,"solver_id":Config.Numerics.MUSCL,"wave_retention":amount}}).is_empty())
	check("retention_requires_muscl",Config.Numerics.configuration_error({"water_numerics":{"schema":2,"solver_id":Config.Numerics.FIRST_ORDER,"wave_retention":0.5}})==&"unsupported_wave_retention_solver")
	var coupled_flags:=flags.duplicate(true);coupled_flags.enable_erosion=true
	var coupled:=Config.freeze(registry.registry,"main_beach",coupled_flags,effects,{}, {"water_numerics":{"schema":1,"solver_id":"muscl_mc_ssprk2_v1"}},extra)
	var candidate=Pipeline.new()
	check("implemented_coupling_configured",coupled.error.is_empty() and candidate.configure(registry.registry,coupled.value,1002).is_empty() and not candidate.initialization_started and candidate._configuration.environment.water_numerics.solver_id==Config.Numerics.MUSCL)
	if not legacy.is_empty():
		var loaded:=Codec.read_container(legacy)
		check("legacy_container",loaded.error.is_empty())
		if loaded.error.is_empty():
			var configuration: Dictionary=loaded.checkpoint.configuration
			var original:=var_to_bytes(configuration)
			check("historical_missing_object_is_first_order",not configuration.environment.has("water_numerics") and Config.Numerics.solver_id(configuration.environment)==Config.Numerics.FIRST_ORDER)
			check("historical_validation_without_mutation",Config.validate(configuration,false).is_empty() and var_to_bytes(configuration)==original)
	var result:={"outcome":"fail" if failed else "pass","checks":rows,"first_hash":first.value.configuration_hash,"muscl_hash":second.value.configuration_hash,"probe_sha256":FileAccess.get_sha256(get_script().resource_path),"sources":first.value.sources,"scope":"Configuration validation and capability gate only; actual dispatch tested by GPU cases"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(1 if failed else 0)
