extends RefCounted

# Appearance-only history. The single writer is the successful publication pass.
const PROFILE={"version":2,"contact_on_m":0.001,"contact_full_m":0.003,"fill_time_s":0.75,"hold_time_s":18.0,"fade_time_s":12.0,"full_wet_at":0.4,"surface_reset_m":0.005,"sand_min_m":0.02}
const SOURCES=["res://scripts/simulation/unified_edit/surface_wetness.gd","res://scripts/simulation/unified_edit/publish_wet_sand.glsl"]
const KEYS=["version","domain_id","profile","tick","revision","source_generation","state"]

static func enabled(config: Dictionary) -> bool:
	return config.get("environment",{}).has("surface_wetness_profile")

static func configuration_error(config: Dictionary) -> StringName:
	if not enabled(config):return &""
	if config.get("domain_id") not in ["main_beach","test1_geometry"] or not valid_profile(config.environment.surface_wetness_profile):return &"invalid_surface_wetness_profile"
	return &""

static func valid_profile(profile: Variant) -> bool:
	if not profile is Dictionary or profile.size()!=PROFILE.size():return false
	for key in PROFILE:
		if not profile.has(key):return false
		if key in ["hold_time_s","fade_time_s"]:
			var v: Variant=profile[key]
			if typeof(v) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(v)) or v>(300.0) or v<(0.0 if key=="hold_time_s" else 0.1):return false
		elif profile[key]!=PROFILE[key]:return false
	return true

static func seed(sand: PackedFloat32Array, water: PackedFloat32Array) -> PackedByteArray:
	var values:=PackedFloat32Array();values.resize(65536)
	for i in 65536:
		values[i]=0.4*smoothstep(0.001,0.003,maxf(water[i],0.0)) if sand[i]>0.02 else 0.0
	return values.to_byte_array()

static func record(value: Dictionary, bytes: PackedByteArray) -> Dictionary:
	return {"version":1,"domain_id":value.domain_id,"profile":value.configuration.environment.surface_wetness_profile.duplicate(),"tick":value.sim_tick,"revision":value.revision,"source_generation":value.generation,"state":bytes}

static func validate(value: Dictionary) -> StringName:
	var ext: Variant=value.visual_extensions.get("wet_sand_v1")
	if not ext is Dictionary or ext.size()!=KEYS.size():return &"invalid_surface_wetness_state"
	for key in KEYS:
		if not ext.has(key):return &"invalid_surface_wetness_state"
	for key in ["version","tick","revision","source_generation"]:
		if typeof(ext[key])!=TYPE_INT:return &"invalid_surface_wetness_state"
	if ext.version!=1 or ext.domain_id!=value.domain_id or ext.profile!=value.configuration.environment.surface_wetness_profile or ext.tick!=value.sim_tick or ext.revision!=value.revision or ext.source_generation!=value.generation:return &"surface_wetness_identity_mismatch"
	if not ext.state is PackedByteArray or ext.state.size()!=262144:return &"invalid_surface_wetness_size"
	for m in ext.state.to_float32_array():
		if not is_finite(m) or m<0.0 or m>1.0:return &"invalid_surface_wetness_value"
	return &""
