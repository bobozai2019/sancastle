extends RefCounted

const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const P=preload("res://scripts/simulation/unified_edit/tool_profile.gd")
const Wire=preload("res://scripts/simulation/unified_edit/protocol.gd")
const ParameterSchema=preload("res://scripts/parameters/parameter_schema.gd")
const Numerics=preload("res://scripts/simulation/unified_edit/water_numerics.gd")
const Wet=preload("res://scripts/simulation/unified_edit/surface_wetness.gd")
const FAMILY="unified_edit"
const SCHEMA:=1
const MATERIAL_PATH="res://assets/brushes/molded_material_candidate.json"
const SIMULATION_KEYS=["enable_erosion","enable_brush_water","unrestricted_sand_tools","enable_structures","local_front_history","rise_front_history","contact_history"]
const EFFECT_DEFAULTS={"foam_enabled":true,"gravel_enabled":true}
const DIAGNOSTIC_DEFAULTS={"profile_passes":false,"collision_observe":false}
const KEYS=["schema","family","abi_version","domain_id","grid_size","cell_size_m","simulation","effects","diagnostics","profiles","sources","environment","material","ledger_policy","configuration_hash"]
const DATA_FILES=["res://scripts/simulation/unified_edit/configuration.gd","res://scripts/simulation/unified_edit/layout.gd","res://scripts/simulation/unified_edit/intent.gd","res://scripts/simulation/unified_edit/protocol.gd","res://scripts/simulation/unified_edit/profile_registry.gd","res://scripts/simulation/unified_edit/profile_catalog.gd","res://scripts/simulation/unified_edit/tool_profile.gd","res://scripts/simulation/unified_edit/height_stamp.gd","res://scripts/simulation/unified_edit/protocol.glslinc",MATERIAL_PATH]
const LEDGER_POLICY={"volume_delta":"approximate_on_known_recording_v1","target_height":"exact_external_v1","transfer":"balanced_conservative_or_capped_exact_sink_v2","redistribute":"unchanged_v1","field_adjust":"unchanged_v1","control":"unchanged_v1"}
const CHECKPOINT_FILES=["res://scripts/simulation/unified_edit/unit_half.gd","res://scripts/simulation/unified_edit/checkpoint_codec.gd","res://scripts/simulation/unified_edit/legacy_sources.gd","res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd","res://scripts/simulation/checkpoint_store.gd","res://scripts/beach/beach_recovery_entry.gd","res://scripts/simulation/brushes/brush_checkpoint_codec.gd","res://scripts/simulation/brushes/brush_material_state_codec.gd","res://scripts/visual/gravel_checkpoint_codec.gd"]

static func exact(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size():return false
	for key in keys:
		if not value.has(key):return false
	return true

static func safe_data(value: Variant, depth: int=0) -> bool:
	if depth>12:return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_INT:return true
		TYPE_FLOAT:return is_finite(value)
		TYPE_STRING,TYPE_STRING_NAME:return String(value).length()<=8192
		TYPE_VECTOR2,TYPE_VECTOR3:return value.is_finite()
		TYPE_COLOR:return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
		TYPE_ARRAY:
			if value.size()>4096:return false
			for element in value:
				if not safe_data(element,depth+1):return false
			return true
		TYPE_DICTIONARY:
			if value.size()>4096:return false
			for key in value:
				if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or String(key).length()>512 or not safe_data(value[key],depth+1):return false
			return true
	return false

static func canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result:={};var keys: Array=value.keys();keys.sort_custom(func(first,second):return String(first)<String(second))
		for key in keys:result[String(key)]=canonical(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for element in value:result.append(canonical(element))
		return result
	return String(value) if typeof(value)==TYPE_STRING_NAME else value

static func digest_data(value: Variant) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(canonical(value)))
	return hash.finish().hex_encode()

static func stable_hash(snapshot: Dictionary) -> String:
	var value:=snapshot.duplicate(true)
	value.erase("configuration_hash");value.erase("diagnostics")
	return digest_data(value)

static func _flags(input: Dictionary, defaults: Dictionary) -> Dictionary:
	var values:=defaults.duplicate(true)
	for key in input:
		if not defaults.has(key) or typeof(input[key])!=TYPE_BOOL:return {"error":&"invalid_feature_flag"}
		values[key]=input[key]
	return {"error":&"","value":values}

static func freeze(registry, domain: Variant, simulation: Dictionary, effects: Dictionary={}, diagnostics: Dictionary={}, environment: Dictionary={}, extra_sources: PackedStringArray=PackedStringArray()) -> Dictionary:
	if typeof(domain) not in [TYPE_STRING,TYPE_STRING_NAME] or String(domain).is_empty() or String(domain).length()>128:return {"error":&"invalid_configuration_domain"}
	if not exact(simulation,SIMULATION_KEYS):return {"error":&"invalid_simulation_flags"}
	for value in simulation.values():
		if typeof(value)!=TYPE_BOOL:return {"error":&"invalid_simulation_flags"}
	if not simulation.unrestricted_sand_tools:return {"error":&"unsupported_inventory_accounting"}
	for key in ["enable_structures","rise_front_history","contact_history"]:
		if simulation[key]:return {"error":&"unsupported_history_capability"}
	var effect:=_flags(effects,EFFECT_DEFAULTS);var diagnostic:=_flags(diagnostics,DIAGNOSTIC_DEFAULTS)
	if not effect.error.is_empty():return effect
	if not diagnostic.error.is_empty():return diagnostic
	if not safe_data(environment) or var_to_bytes(environment).size()>256*1024:return {"error":&"invalid_environment_configuration"}
	var numerics:=Numerics.effective(environment)
	if not numerics.error.is_empty():return numerics
	var coupling_error:=ParameterSchema.coupling_error(environment.get("coupling_parameters",{}))
	if not coupling_error.is_empty():return {"error":coupling_error}
	for pair in [["foam_parameters","foam"],["prop_parameters","prop"]]:
		var tuning_error:=ParameterSchema.typed_parameters_error(environment.get(pair[0],{}),pair[1])
		if not tuning_error.is_empty():return {"error":tuning_error}
	environment=numerics.value
	var profiles: Dictionary=registry.catalog_snapshot()
	if profiles.is_empty():return {"error":&"empty_configuration_catalog"}
	var paths: Array=DATA_FILES.duplicate()
	paths.append_array(CHECKPOINT_FILES)
	paths.append(Numerics.SELF)
	paths.append_array(ParameterSchema.SOURCES)
	paths.append_array(Array(extra_sources))
	for profile in profiles.values():
		if not profile.resource_identity.path.is_empty():paths.append(profile.resource_identity.path)
		if not profile.template.is_empty():
			paths.append(profile.template.payload_path)
			if not profile.template.resource_path.is_empty():paths.append(profile.template.resource_path)
	if paths.size()>4096:return {"error":&"configuration_source_capacity"}
	var sources:={}
	for path in paths:
		if typeof(path)!=TYPE_STRING or not path.begins_with("res://") or ".." in path or not FileAccess.file_exists(path):return {"error":&"missing_configuration_source"}
		sources[path]=FileAccess.get_sha256(path)
	if FileAccess.get_file_as_string("res://scripts/simulation/unified_edit/protocol.glslinc")!=L.shader_defines():return {"error":&"stale_shader_layout"}
	var material: Variant=JSON.parse_string(FileAccess.get_file_as_string(MATERIAL_PATH))
	if not material is Dictionary or material.get("compaction_target")!=0.95 or material.get("compaction_storage_value")!=0.9501953125 or material.get("support_format")!="RG32F" or material.get("cohesion_yield_height_m")!=0.9 or material.get("saturation_tagged_depth_m")!=0.125:return {"error":&"unsupported_material_configuration"}
	var snapshot:={"schema":SCHEMA,"family":FAMILY,"abi_version":L.VERSION,"domain_id":String(domain),"grid_size":256,"cell_size_m":0.125,"simulation":simulation.duplicate(true),"effects":effect.value,"diagnostics":diagnostic.value,"profiles":profiles,"sources":sources,"environment":environment.duplicate(true),"material":{"path":MATERIAL_PATH,"sha256":sources[MATERIAL_PATH],"compaction_target":0.95,"compaction_storage_value":0.9501953125,"cohesion_yield_height_m":0.9,"saturation_tagged_depth_m":0.125},"ledger_policy":LEDGER_POLICY.duplicate(true)}
	snapshot.configuration_hash=stable_hash(snapshot)
	return {"error":&"","value":snapshot}

static func validate(snapshot: Variant, verify_disk: bool=false) -> StringName:
	return _validate_snapshot(snapshot,verify_disk,LEDGER_POLICY)

# Historical policy labels describe future operations in their source release.
# Only the complete offline-pinned source configuration may select that label;
# target/runtime validation always uses validate() and the current policy.
static func _validate_snapshot(snapshot: Variant, verify_disk: bool, expected_ledger_policy: Dictionary) -> StringName:
	if not exact(snapshot,KEYS) or not safe_data(snapshot):return &"invalid_configuration"
	for key in ["schema","abi_version","grid_size"]:
		if typeof(snapshot[key])!=TYPE_INT:return &"invalid_configuration_header"
	if snapshot.schema!=SCHEMA or snapshot.family!=FAMILY or snapshot.abi_version!=L.VERSION or snapshot.grid_size!=256 or snapshot.cell_size_m!=0.125 or typeof(snapshot.domain_id)!=TYPE_STRING or snapshot.domain_id.is_empty() or snapshot.domain_id.length()>128:return &"invalid_configuration_header"
	if not exact(snapshot.simulation,SIMULATION_KEYS):return &"invalid_simulation_flags"
	for value in snapshot.simulation.values():
		if typeof(value)!=TYPE_BOOL:return &"invalid_simulation_flags"
	if not snapshot.simulation.unrestricted_sand_tools:return &"unsupported_inventory_accounting"
	for key in ["enable_structures","rise_front_history","contact_history"]:
		if snapshot.simulation[key]:return &"unsupported_history_capability"
	if not exact(snapshot.effects,EFFECT_DEFAULTS.keys()) or not exact(snapshot.diagnostics,DIAGNOSTIC_DEFAULTS.keys()):return &"invalid_feature_flag"
	for group in [snapshot.effects,snapshot.diagnostics]:
		for value in group.values():
			if typeof(value)!=TYPE_BOOL:return &"invalid_feature_flag"
	if not snapshot.profiles is Dictionary or snapshot.profiles.is_empty() or snapshot.profiles.size()>L.MAX_PROFILES or not snapshot.sources is Dictionary or snapshot.sources.is_empty() or not snapshot.environment is Dictionary or snapshot.ledger_policy!=expected_ledger_policy:return &"invalid_configuration_catalog"
	var wet_error:=Wet.configuration_error(snapshot)
	if not wet_error.is_empty():return wet_error
	var numerical_error:=Numerics.configuration_error(snapshot.environment)
	if not numerical_error.is_empty():return numerical_error
	var coupling_error:=ParameterSchema.coupling_error(snapshot.environment.get("coupling_parameters",{}))
	if not coupling_error.is_empty():return coupling_error
	for pair in [["foam_parameters","foam"],["prop_parameters","prop"]]:
		var tuning_error:=ParameterSchema.typed_parameters_error(snapshot.environment.get(pair[0],{}),pair[1])
		if not tuning_error.is_empty():return tuning_error
	if not Wire.hash_valid(snapshot.configuration_hash,true) or stable_hash(snapshot)!=snapshot.configuration_hash:return &"configuration_hash_mismatch"
	for path in snapshot.sources:
		if not path.begins_with("res://") or ".." in path or not Wire.hash_valid(snapshot.sources[path],true):return &"invalid_configuration_source"
		if verify_disk and (not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=snapshot.sources[path]):return &"configuration_source_changed"
	for path in DATA_FILES+CHECKPOINT_FILES:
		if not snapshot.sources.has(path):return &"incomplete_configuration_sources"
	for id in snapshot.profiles:
		var profile: Variant=snapshot.profiles[id]
		if not profile is Dictionary or profile.get("profile_id")!=id or not Wire.hash_valid(profile.get("profile_hash"),true) or not profile.get("resource_identity") is Dictionary:return &"invalid_configuration_profile"
		var unsigned: Dictionary=profile.duplicate(true);unsigned.erase("profile_hash")
		if JSON.stringify(unsigned,"",true).sha256_text()!=profile.profile_hash:return &"configuration_profile_hash_mismatch"
		var path: Variant=profile.resource_identity.get("path")
		if typeof(path)!=TYPE_STRING or (not path.is_empty() and snapshot.sources.get(path)!=profile.resource_identity.get("sha256")):return &"incomplete_configuration_profile_source"
		if not profile.get("template") is Dictionary:return &"invalid_configuration_template"
		if not profile.template.is_empty():
			if snapshot.sources.get(profile.template.get("payload_path"))!=profile.template.get("sha256"):return &"incomplete_configuration_template_source"
	if not snapshot.material is Dictionary or snapshot.material.get("sha256")!=snapshot.sources.get(MATERIAL_PATH) or snapshot.material.get("compaction_target")!=0.95 or snapshot.material.get("compaction_storage_value")!=0.9501953125:return &"invalid_material_configuration"
	return &""

static func allows_intent(snapshot: Dictionary, frozen: Dictionary) -> StringName:
	# The actor owns this validated immutable snapshot; no per-input disk hashes.
	if frozen.get("domain_id")!=snapshot.get("domain_id"):return &"configuration_domain_mismatch"
	if frozen.get("control_kind",0)!=0:return &""
	var profile: Dictionary=frozen.get("configuration",{})
	var registered: Dictionary=snapshot.profiles.get(frozen.get("profile_id",""),{})
	if registered.is_empty() or registered.profile_hash!=frozen.get("profile_hash") or registered.version!=frozen.get("profile_version"):return &"configuration_profile_mismatch"
	if profile.get("water_policy",0)!=0 and not snapshot.simulation.enable_brush_water:return &"unsupported_water_capability"
	if profile.get("destination")==P.Destination.SUSPENDED_SAND and not snapshot.simulation.enable_erosion:return &"unsupported_suspended_capability"
	return &""
