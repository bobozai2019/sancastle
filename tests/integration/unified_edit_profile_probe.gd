extends SceneTree

const Profile=preload("res://scripts/simulation/unified_edit/tool_profile.gd")
const Registry=preload("res://scripts/simulation/unified_edit/profile_registry.gd")
const Stamp=preload("res://scripts/simulation/unified_edit/height_stamp.gd")
var checks: Array=[]
var failed:=false
var output:=""
var callback_called:=false

func check(name: String, value: bool) -> void:
	checks.append({"name":name,"pass":value});failed=failed or not value
	print("UNIFIED_PROFILE ",name," ",value)

func injected_callable() -> void:
	callback_called=true

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")

func reject_profile(label: String, profile: Resource) -> void:
	var registry:=Registry.new()
	check(label,not registry.initialize([profile]).is_empty())
	check(label+"_atomic",registry.profile(&"fill_v1").is_empty())

func _run() -> void:
	var catalog=load("res://assets/unified_edit/default_catalog.tres")
	check("static_catalog_loaded",catalog!=null)
	if catalog==null:quit(1);return
	var created: Dictionary=catalog.instantiate_registry()
	check("eight_tools_eleven_profiles_initialized",created.error.is_empty() and catalog.profiles.size()==11)
	if not created.error.is_empty():quit(1);return
	var registry=created.registry
	for resource in catalog.profiles:
		var snapshot: Dictionary=registry.profile(resource.profile_id)
		check("identity_"+String(resource.profile_id),snapshot.profile_hash.length()==64 and snapshot.resource_identity.sha256.length()==64)
		var result: Dictionary=registry.resolve(resource.profile_id,snapshot.version,snapshot.profile_hash)
		check("defaults_"+String(resource.profile_id),result.error.is_empty() and result.value.parameters==resource.defaults)
		check("unknown_key_"+String(resource.profile_id),registry.resolve(resource.profile_id,snapshot.version,snapshot.profile_hash,{"write_mask":0}).error==&"invalid_parameters")
	var fill: Dictionary=registry.profile(&"fill_v1")
	check("bad_hash_rejected",registry.resolve(&"fill_v1",1,"0".repeat(64)).error==&"profile_identity_mismatch")
	check("bad_version_rejected",registry.resolve(&"fill_v1",2,fill.profile_hash).error==&"profile_identity_mismatch")
	check("unknown_profile",registry.resolve(&"missing",1,fill.profile_hash).error==&"invalid_profile")
	var no_water: Dictionary=registry.resolve(&"fill_v1",1,fill.profile_hash,{}, {"water_policy":0})
	check("declared_feature_override",no_water.error.is_empty() and no_water.value.water_policy==0 and no_water.value.derived_fields==(Profile.BED|Profile.MATERIAL))
	check("features_participate_in_identity",no_water.value.effective_hash!=registry.resolve(&"fill_v1",1,fill.profile_hash).value.effective_hash)
	check("features_do_not_mutate_registered_default",registry.profile(&"fill_v1").water_policy==3)
	check("cannot_disable_validation",not registry.resolve(&"fill_v1",1,fill.profile_hash,{}, {"validate":0}).error.is_empty())
	check("feature_type_is_strict",not registry.resolve(&"fill_v1",1,fill.profile_hash,{}, {"water_policy":false}).error.is_empty())
	check("undeclared_material_feature_rejected",not registry.resolve(&"fill_v1",1,fill.profile_hash,{}, {"material_policy":1}).error.is_empty())
	check("inactive_impulse_rejected",not registry.resolve(&"fill_v1",1,fill.profile_hash,{"speed_m_s":0.5},{"water_policy":0}).error.is_empty())
	for pair in [["radius_m",0.0],["radius_m",4.01],["amount_m3",-1.0],["amount_m3",1.01],["strength",NAN],["strength",INF],["strength",true],["speed_m_s",1e100],["radius_m",1e-300],["strength",injected_callable]]:
		check("bad_value_%d"%checks.size(),registry.resolve(&"fill_v1",1,fill.profile_hash,{pair[0]:pair[1]}).error==&"invalid_parameters")
	check("no_callable_executed",not callback_called)
	var a: Dictionary=registry.resolve(&"fill_v1",1,fill.profile_hash,{"amount_m3":0.25})
	var b: Dictionary=registry.resolve(&"fill_v1",1,fill.profile_hash,{"amount_m3":0.25})
	check("effective_hash_deterministic",a.error.is_empty() and a.value.effective_hash==b.value.effective_hash)
	check("effective_parameters_change_identity",a.value.effective_hash!=registry.resolve(&"fill_v1",1,fill.profile_hash).value.effective_hash)
	var original=catalog.profiles[1]
	original.defaults.amount_m3=0.9;original.version=99
	check("resource_mutation_does_not_change_registry",registry.resolve(&"fill_v1",1,fill.profile_hash).value.parameters.amount_m3==0.1)
	check("accepted_snapshot_unchanged",a.value.parameters.amount_m3==0.25 and a.value.version==1)
	fill.defaults.amount_m3=0.8
	check("lookup_returns_detached_copy",registry.profile(&"fill_v1").defaults.amount_m3==0.1)
	a.value.parameters.amount_m3=0.7
	check("resolved_copy_detached",b.value.parameters.amount_m3==0.25)
	check("registry_cannot_reinitialize",registry.initialize(catalog.profiles)==&"registry_already_initialized")
	var duplicate:=Registry.new()
	check("duplicate_profile_rejected",duplicate.initialize([catalog.profiles[0],catalog.profiles[0]])==&"duplicate_profile")
	check("duplicate_registry_atomic",duplicate.profile(&"dig_v1").is_empty())
	check("empty_registry_rejected",Registry.new().initialize([])==&"empty_registry")
	var excessive: Array=[]
	for index in 65:excessive.append(catalog.profiles[0])
	check("profile_capacity_rejected",Registry.new().initialize(excessive)==&"profile_capacity")
	var bad=load("res://assets/unified_edit/compact_v1.tres").duplicate(true)
	bad.destination=Profile.Destination.BED_SAND
	reject_profile("material_operation_cannot_write_bed",bad)
	bad=load("res://assets/unified_edit/suspended_v1.tres").duplicate(true)
	bad.volume_sign=Profile.VolumeSign.REMOVE
	reject_profile("suspended_remove_rejected",bad)
	bad=load("res://assets/unified_edit/wall_v1.tres").duplicate(true)
	bad.height_reference=Profile.HeightReference.FIXED_WORLD
	reject_profile("wall_must_use_stroke_baseline",bad)
	bad=load("res://assets/unified_edit/shovel_v1.tres").duplicate(true)
	bad.material_policy=Profile.MaterialPolicy.MOLDED
	reject_profile("transfer_must_preserve_material",bad)
	bad=load("res://assets/unified_edit/dig_v1.tres").duplicate(true)
	bad.set("operation",999)
	reject_profile("unknown_operation_rejected",bad)
	bad=load("res://assets/unified_edit/dig_v1.tres").duplicate(true)
	bad.defaults.erase("radius_m");bad.defaults.shader="res://bad.glsl"
	reject_profile("executor_parameter_injection_rejected",bad)
	bad=load("res://assets/unified_edit/dig_v1.tres").duplicate(true)
	bad.ranges.radius_m=[0.0,5.0]
	reject_profile("range_cannot_expand_capability",bad)
	bad=load("res://assets/unified_edit/dig_v1.tres").duplicate(true)
	bad.max_buffer_points=257
	reject_profile("unbounded_sampling_rejected",bad)
	bad=load("res://assets/unified_edit/suspended_v1.tres").duplicate(true)
	bad.allowed_water_policies=PackedInt32Array([0,3])
	reject_profile("illegal_feature_combination_rejected",bad)
	var foreign=load("res://tests/integration/unified_edit_foreign_profile.gd").new()
	reject_profile("profile_subclass_rejected",foreign)
	reject_profile("generic_resource_rejected",Resource.new())
	var castle: Dictionary=registry.profile(&"castle_v1")
	var bytes: PackedByteArray=registry.template_bytes(castle.template.sha256)
	check("template_raw_cached",bytes.size()==65*65*16 and Stamp.bytes_sha256(bytes)==castle.template.sha256)
	bytes[0]^=1
	check("template_lookup_detached",Stamp.bytes_sha256(registry.template_bytes(castle.template.sha256))==castle.template.sha256)
	var corrupt: PackedByteArray=registry.template_bytes(castle.template.sha256)
	corrupt.encode_float(0,NAN)
	check("template_nan_rejected",Stamp.payload_error(corrupt)==&"invalid_template_payload")
	corrupt=registry.template_bytes(castle.template.sha256);corrupt.encode_float(4,0.5)
	check("template_bad_mask_rejected",Stamp.payload_error(corrupt)==&"invalid_template_payload")
	check("template_short_payload_rejected",Stamp.payload_error(PackedByteArray())==&"invalid_template_size")
	bad=load("res://assets/unified_edit/castle_v1.tres").duplicate(true)
	bad.shape_resource.payload_path="res://assets/../scripts/execute.gd"
	reject_profile("template_path_injection_rejected",bad)
	check("template_file_mutation_does_not_change_cached_identity",registry.profile(&"castle_v1").template.payload_path==castle.template.payload_path)
	check("bed_write_mask_derived",registry.profile(&"fill_v1").derived_fields==(Profile.BED|Profile.MATERIAL|Profile.WATER|Profile.SUSPENDED|Profile.MOMENTUM))
	check("suspended_write_mask_derived",registry.profile(&"suspended_v1").derived_fields==Profile.SUSPENDED)
	check("compact_write_mask_derived",registry.profile(&"compact_v1").derived_fields==Profile.MATERIAL)
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"scope":"T01 profile data contract only, no GPU execution claim"},"\t"))
	quit(1 if failed else 0)
