extends SceneTree

const C=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Legacy=preload("res://scripts/simulation/unified_edit/legacy_sources.gd")
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const I=preload("res://scripts/simulation/unified_edit/intent.gd")
const FIXTURES=["res://test_output/unified_edit_pipeline/g0_function_baseline01/regression_all_tools_1.sandgp","res://test_output/gpu_pipeline/g7_20261017_03/migration.sandcp"]
var checks: Array=[]
var failed:=false
var output:=""
var registry
var pins: Array=[]

func check(label: String, pass_value: bool) -> void:
	checks.append({"name":label,"pass":pass_value});failed=failed or not pass_value
	print("UNIFIED_CONFIG ",label," ",pass_value)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")

func freeze(domain: String, simulation: Dictionary, gravel: bool=true, diagnostics: Dictionary={}) -> Dictionary:
	return C.freeze(registry,domain,simulation,{"gravel_enabled":gravel},diagnostics,{"engine":"4.7.2","fixture":"headless_contract"})

func finish() -> void:
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"pinned_sources":pins,"scope":"CPU configuration/container and genuine old source validation only; no GPU restore or consumer readiness claim"},"\t"))
	quit(1 if failed else 0)

func has_legacy_runtime(node: Node) -> bool:
	var script: Script=node.get_script()
	while script!=null:
		if script.resource_path in ["res://scripts/simulation/edit_validation/frame_pipeline/async_controller.gd","res://scripts/simulation/edit_validation/frame_pipeline/async_editor.gd","res://scripts/simulation/edit_validation/frame_pipeline/editor.gd","res://scripts/beach/beach_playable_entry.gd"]:return true
		script=script.get_base_script()
	for child in node.get_children():
		if has_legacy_runtime(child):return true
	return false

func _run() -> void:
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	check("registry",created.error.is_empty())
	if not created.error.is_empty():finish();return
	registry=created.registry
	var sim:={"enable_erosion":true,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":true,"rise_front_history":false,"contact_history":false}
	var base:=freeze("main_beach",sim)
	check("freeze",base.error.is_empty())
	if not base.error.is_empty():print(base);finish();return
	var cfg: Dictionary=base.value
	check("snapshot_valid_disk",C.validate(cfg,true).is_empty())
	check("diagnostics_do_not_change_physical_hash",freeze("main_beach",sim,true,{"profile_passes":true}).value.configuration_hash==cfg.configuration_hash)
	check("effects_change_hash",freeze("main_beach",sim,false).value.configuration_hash!=cfg.configuration_hash)
	var changed:=sim.duplicate();changed.enable_erosion=false
	check("physics_change_hash",freeze("main_beach",changed).value.configuration_hash!=cfg.configuration_hash)
	check("unknown_effect_rejected",C.freeze(registry,"main_beach",sim,{"validate":false}).error==&"invalid_feature_flag")
	check("unknown_diagnostic_rejected",C.freeze(registry,"main_beach",sim,{}, {"skip_commit":true}).error==&"invalid_feature_flag")
	check("callable_environment_rejected",not C.freeze(registry,"main_beach",sim,{}, {},{"callback":finish}).error.is_empty())
	check("nan_environment_rejected",not C.freeze(registry,"main_beach",sim,{}, {},{"value":NAN}).error.is_empty())
	changed=sim.duplicate();changed.unrestricted_sand_tools=false
	check("inventory_not_promoted_from_approximate",freeze("main_beach",changed).error==&"unsupported_inventory_accounting")
	for key in ["enable_structures","rise_front_history","contact_history"]:
		changed=sim.duplicate();changed[key]=true
		check("unsupported_"+key,not freeze("main_beach",changed).error.is_empty())
	changed=sim.duplicate();changed.enable_erosion=1
	check("flag_integer_rejected",not freeze("main_beach",changed).error.is_empty())
	var copy: Dictionary=cfg.duplicate(true);copy.simulation.enable_erosion=false
	check("mutation_hash_rejected",not C.validate(copy).is_empty())
	copy=cfg.duplicate(true);copy.profiles.fill_v1.defaults.amount_m3=0.9;copy.configuration_hash=C.stable_hash(copy)
	check("nested_profile_hash_rejected",C.validate(copy)==&"configuration_profile_hash_mismatch")
	copy=cfg.duplicate(true);copy.sources.erase(C.MATERIAL_PATH);copy.configuration_hash=C.stable_hash(copy)
	check("missing_source_rejected",not C.validate(copy).is_empty())
	changed=sim.duplicate();changed.enable_brush_water=false
	var dry: Dictionary=freeze("main_beach",changed).value
	var profile: Dictionary=registry.profile(&"fill_v1")
	var req:={"domain_id":"main_beach","generation":1,"command_id":1,"sim_tick":0,"profile_id":"fill_v1","profile_version":1,"profile_hash":profile.profile_hash,"start_xz_m":Vector2.ZERO}
	var intent:=I.freeze(registry,req,"main_beach",1)
	check("water_capability_denied",intent.error.is_empty() and C.allows_intent(dry,intent.value)==&"unsupported_water_capability")
	req.features={"water_policy":0};intent=I.freeze(registry,req,"main_beach",1)
	check("explicit_declared_no_water_accepted",intent.error.is_empty() and C.allows_intent(dry,intent.value).is_empty())
	var source:=Legacy.new()
	check("uninitialized_source_rejected",source.inspect_file(FIXTURES[0]).error==&"legacy_sources_not_initialized")
	for path in FIXTURES:pins.append({"path":path,"sha256":FileAccess.get_sha256(path)})
	var source_error:=source.initialize(pins)
	check("actual_old_sources_validated",source_error.is_empty())
	if not source_error.is_empty():print(source_error);finish();return
	check("source_catalog_cannot_reinitialize",not source.initialize(pins).is_empty())
	var wrong:=pins.duplicate(true);wrong[0].sha256="0".repeat(64)
	check("source_hash_mismatch_rejected",Legacy.new().initialize(wrong)==&"legacy_fixture_identity_mismatch")
	for index in FIXTURES.size():
		var inspected:=source.inspect_file(FIXTURES[index])
		check("inspect_actual_"+str(index),inspected.error.is_empty())
		if not inspected.error.is_empty():print(inspected.error);continue
		var old: Dictionary=inspected.checkpoint
		var legacy_sim: Dictionary=old.simulation.duplicate(true) if index==0 else sim.duplicate()
		legacy_sim.erase("prescribed_tide_boundary")
		var domain: String=old.domain_id if index==0 else String(old.shadow.domain_id)
		var frozen:=freeze(domain,legacy_sim,old.visual_extensions.gravel_v1.enabled)
		check("source_compatible_configuration_"+str(index),frozen.error.is_empty())
		if not frozen.error.is_empty():continue
		var target: Dictionary=frozen.value
		var projection:=Codec.project_validated_legacy(inspected,target)
		check("project_actual_"+str(index),projection.error.is_empty())
		if not projection.error.is_empty():print(projection.error);continue
		var value: Dictionary=projection.checkpoint
		var native: Dictionary=old.native if index==0 else old.gpu_beach_native
		for key in ["fields","spare","material","foam"]:check("raw_"+str(index)+"_"+key,value.native[key]==native[key])
		check("ledger_preserved_"+str(index),value.ledger==(old.ledger if index==0 else old.gpu_beach_edit.ledger))
		check("provenance_"+str(index),value.source_provenance.sha256==pins[index].sha256 and value.source_provenance.configuration==inspected.provenance.configuration)
		check("candidate_not_runtime_restore_"+str(index),projection.requires_candidate_build and not projection.has("restored"))
		if index==0:
			check("native_control_clock_and_seq_preserved",value.native.control==old.native.control and value.advanced_time_s==old.advanced_time_s and value.state_seq==old.state_seq)
		else:
			check("legacy_prefix_retained",value.source_provenance.original_prefix==old.gpu_beach_edit.prefix)
			check("legacy_clock_mapping_declared",value.source_provenance.policies.clock=="legacy_tick_over_30_f32" and value.state_seq==0)
		var path:=output.get_base_dir()+"/roundtrip_"+str(index)+".sandue"
		check("new_save_"+str(index),Codec.save(path,value,target).is_empty())
		var loaded:=Codec.load(path,target)
		check("new_load_exact_"+str(index),loaded.error.is_empty() and loaded.checkpoint==value)
		check("no_overwrite_"+str(index),Codec.save(path,value,target)==&"already_exists")
		var large: Dictionary=value.duplicate(true);large.highwater_id=9007199254740993;large.ticket_id=9223372036854775807;large.wave_highwater_id=9223372036854775807
		path=output.get_base_dir()+"/int64_"+str(index)+".sandue"
		check("save_exact_i64_"+str(index),Codec.save(path,large,target).is_empty())
		loaded=Codec.load(path,target)
		check("load_exact_i64_"+str(index),loaded.error.is_empty() and typeof(loaded.checkpoint.ticket_id)==TYPE_INT and loaded.checkpoint.ticket_id==9223372036854775807 and loaded.checkpoint.highwater_id==9007199254740993)
		var bad: Dictionary=value.duplicate(true);bad.highwater_id=1.0
		check("float_identity_rejected_"+str(index),not Codec.validate(bad,target).is_empty())
		bad=value.duplicate(true);bad.native.fields.sand=PackedByteArray([0])
		check("truncated_field_rejected_"+str(index),not Codec.validate(bad,target).is_empty())
		bad=value.duplicate(true);bad.native.fields.sand.encode_float(0,NAN)
		check("nan_field_rejected_"+str(index),not Codec.validate(bad,target).is_empty())
		bad=value.duplicate(true);bad.native.control.encode_u32(48,1)
		check("unknown_control_extension_rejected_"+str(index),not Codec.validate(bad,target).is_empty())
		bad=value.duplicate(true);bad.ledger.tool_inventory_m3=0.1
		check("inventory_rejected_"+str(index),not Codec.validate(bad,target).is_empty())
		bad=value.duplicate(true);bad.native.fields.compaction.encode_half(0,2.0)
		check("invalid_half_rejected_"+str(index),not Codec.validate(bad,target).is_empty())
		bad=value.duplicate(true);bad.advanced_time_s+=1.0
		check("clock_mismatch_rejected_"+str(index),not Codec.validate(bad,target).is_empty())
		bad=value.duplicate(true);bad.visual_extensions.gravel_v1=0
		check("malformed_visual_rejected_"+str(index),not Codec.validate(bad,target).is_empty())
		bad=value.duplicate(true);bad.configuration.profiles={};bad.configuration.configuration_hash=C.stable_hash(bad.configuration)
		check("malformed_saved_configuration_rejected_"+str(index),not Codec.validate(bad,target).is_empty())
		var other: Dictionary=target.duplicate(true);other.environment.fixture="different";other.configuration_hash=C.stable_hash(other)
		check("different_environment_rejected_"+str(index),Codec.validate(value,other)==&"checkpoint_configuration_mismatch")
		var forged: Dictionary=inspected.duplicate(true)
		if index==0:forged.checkpoint.native.fields.sand=PackedByteArray([0])
		else:forged.checkpoint.gpu_beach_edit.prefix[0].result.command_id+=1
		check("projection_revalidates_old_"+str(index),not Codec.project_validated_legacy(forged,target).error.is_empty())
		var bytes:=FileAccess.get_file_as_bytes(path);bytes[bytes.size()-1]=bytes[bytes.size()-1]^1
		var corrupt:=output.get_base_dir()+"/corrupt_"+str(index)+".sandue"
		FileAccess.open(corrupt,FileAccess.WRITE).store_buffer(bytes)
		check("checksum_rejected_"+str(index),Codec.load(corrupt,target).error==&"checksum_mismatch")
		check("legacy_family_not_loaded_as_new_"+str(index),not Codec.load(FIXTURES[index],target).error.is_empty())
		check("old_fixture_unchanged_"+str(index),FileAccess.get_sha256(FIXTURES[index])==pins[index].sha256)
	check("projection_flag_alone_insufficient",not Codec.project_validated_legacy({"error":&"","requires_candidate_build":true},cfg).error.is_empty())
	check("no_legacy_scene_instantiated",current_scene==null and not has_legacy_runtime(root))
	finish()
