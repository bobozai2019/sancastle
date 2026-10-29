extends "res://assets/water_material_natural_candidate/foam_entry.gd"

@export_file("*.json") var reflection_profile_path:="res://assets/water_material_natural_candidate/reflection_baseline.json"
var reflection_profile:={}
var effective_reflection:={}

func _ready() -> void:
	var p:Variant=JSON.parse_string(FileAccess.get_file_as_string(reflection_profile_path))
	if not p is Dictionary:_reject("invalid_reflection_profile");return
	var keys:=["reflection_schema_version","foam_profile","foam_profile_sha256","derived_foam_profile","base_profile","water_shader","sampling_mode","perturbation_enabled","normal_shift_m","uv_shift_limit","edge_margin_px","edge_fade_px","reflection_strength","softness_px"]
	if p.get("reflection_schema_version",0) in [2.0,3.0]:keys.append_array(["color_mode","sky_fallback"])
	if p.get("reflection_schema_version",0)==3:keys.append("projection_y_mode")
	if not _keys(p,keys):
		_reject("invalid_reflection_profile");return
	if not (_number(p.reflection_schema_version,1,1) or _number(p.reflection_schema_version,2,2) or _number(p.reflection_schema_version,3,3)) or not _resource_path(p.foam_profile) or FileAccess.get_sha256(p.foam_profile)!=p.foam_profile_sha256:
		_reject("invalid_reflection_identity");return
	if p.reflection_schema_version>=2 and (p.color_mode not in ["raw","srgb"] or p.sky_fallback not in ["legacy","environment_background"]):
		_reject("invalid_reflection_color_mode");return
	if p.reflection_schema_version==3 and p.projection_y_mode not in ["legacy","viewport_top_left"]:
		_reject("invalid_reflection_y_mode");return
	for name in ["derived_foam_profile","base_profile","water_shader"]:
		if not _resource_path(p[name]):_reject("missing_reflection_resource");return
	if p.sampling_mode not in ["legacy","protected"] or typeof(p.perturbation_enabled)!=TYPE_BOOL:
		_reject("invalid_reflection_mode");return
	if not _number(p.normal_shift_m,0,.5) or not _number(p.uv_shift_limit,0,.05) or not _number(p.edge_margin_px,0,8) or not _number(p.edge_fade_px,0,32) or not _number(p.reflection_strength,0,2) or not _number(p.softness_px,0,8):
		_reject("invalid_reflection_range");return
	var source:Variant=JSON.parse_string(FileAccess.get_file_as_string(p.foam_profile))
	var derived:Variant=JSON.parse_string(FileAccess.get_file_as_string(p.derived_foam_profile))
	if not source is Dictionary or not derived is Dictionary:
		_reject("invalid_reflection_composition");return
	var expected:Dictionary=source.duplicate(true)
	expected.base_profile=p.base_profile;expected.water_shader=p.water_shader;expected.geometry_bindings=derived.get("geometry_bindings","")
	if expected!=derived:_reject("reflection_changed_foam_inputs");return
	var old_geometry:Variant=JSON.parse_string(FileAccess.get_file_as_string(source.geometry_bindings))
	var new_geometry:Variant=JSON.parse_string(FileAccess.get_file_as_string(derived.geometry_bindings))
	if not old_geometry is Dictionary or not new_geometry is Dictionary:
		_reject("missing_reflection_geometry");return
	old_geometry.source_water_shader=p.water_shader
	old_geometry.source_sha256=FileAccess.get_sha256(p.water_shader)
	if old_geometry!=new_geometry:_reject("reflection_changed_contact_geometry");return
	reflection_profile=p
	foam_profile_path=p.derived_foam_profile
	super._ready()

func _configure_scene() -> void:
	super._configure_scene()
	water_material.set_shader_parameter("natural_reflection_protected",reflection_profile.sampling_mode=="protected")
	water_material.set_shader_parameter("natural_reflection_perturbation",reflection_profile.perturbation_enabled)
	water_material.set_shader_parameter("natural_reflection_shift_m",reflection_profile.normal_shift_m)
	water_material.set_shader_parameter("natural_reflection_uv_limit",reflection_profile.uv_shift_limit)
	water_material.set_shader_parameter("natural_reflection_edge_margin_px",reflection_profile.edge_margin_px)
	water_material.set_shader_parameter("natural_reflection_edge_fade_px",reflection_profile.edge_fade_px)
	water_material.set_shader_parameter("natural_reflection_gain",reflection_profile.reflection_strength)
	water_material.set_shader_parameter("prototype_planar_reflection_softness_px",reflection_profile.softness_px)
	water_material.set_shader_parameter("natural_planar_reflection_srgb",$ReflectionViewport.get_texture())
	water_material.set_shader_parameter("natural_reflection_srgb",reflection_profile.get("color_mode","raw")=="srgb")
	water_material.set_shader_parameter("natural_reflection_flip_y",reflection_profile.get("projection_y_mode","legacy")=="viewport_top_left")
	var sky_linear:=Vector3(.55,.75,.86)
	if reflection_profile.get("sky_fallback","legacy")=="environment_background":
		var env:Environment=$WorldEnvironment.environment
		if env.background_mode!=Environment.BG_COLOR or env.tonemap_mode!=Environment.TONE_MAPPER_LINEAR or not is_equal_approx(env.tonemap_exposure,1.) or $ReflectionViewport.use_hdr_2d:
			_fail("unsupported_reflection_sky_environment");return
		var color:=env.background_color.srgb_to_linear()
		sky_linear=Vector3(color.r,color.g,color.b)*env.background_energy_multiplier
	water_material.set_shader_parameter("natural_reflection_sky_linear",sky_linear)

func _seal_test1_effective_profile() -> void:
	super._seal_test1_effective_profile()
	effective_reflection={"schema":reflection_profile.reflection_schema_version,"profile":reflection_profile_path,"profile_sha256":_candidate_digest(reflection_profile_path),
		"shader":water_material.shader.resource_path,"shader_sha256":_candidate_digest(water_material.shader.resource_path),
		"sampling_mode":reflection_profile.sampling_mode,"foreground_protection":"existing visible-water/opaque depth test; reflection UV is not main-view depth UV",
		"source_foam_profile":reflection_profile.foam_profile,"source_foam_sha256":reflection_profile.foam_profile_sha256,
		"texture_size":str(Vector2i($ReflectionViewport.size)),"reflection_camera_cull_mask":$ReflectionViewport/ReflectionCamera.cull_mask}
	effective_reflection["color_mode"]=reflection_profile.get("color_mode","raw")
	effective_reflection["sky_fallback"]=reflection_profile.get("sky_fallback","legacy")
	effective_reflection["projection_y_mode"]=reflection_profile.get("projection_y_mode","legacy")
	effective_reflection["sampler_srgb_texture_size"]=str(Vector2i($ReflectionViewport.size))
	for name in ["natural_reflection_protected","natural_reflection_perturbation","natural_reflection_shift_m","natural_reflection_uv_limit","natural_reflection_edge_margin_px","natural_reflection_edge_fade_px","natural_reflection_gain","prototype_planar_reflection_softness_px","natural_reflection_srgb","natural_reflection_sky_linear","natural_reflection_flip_y"]:
		effective_reflection[name]=water_material.get_shader_parameter(name)
