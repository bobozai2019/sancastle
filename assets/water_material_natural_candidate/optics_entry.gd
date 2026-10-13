extends "res://assets/water_material_natural_candidate/lighting_entry.gd"

@export_file("*.json") var optics_profile_path := "res://assets/water_material_natural_candidate/optics_legacy.json"
var optics_profile := {}
var effective_optics := {}

func _ready() -> void:
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(optics_profile_path))
	var keys := ["optics_schema_version","lighting_profile","lighting_profile_sha256","path_mode","extinction_shallow_m","extinction_deep_m","scatter_gain","shallow_preserve","refraction_scale"]
	if not decoded is Dictionary or not _keys(decoded,keys):
		_reject("invalid_optics_profile"); return
	optics_profile = decoded
	var valid_version: bool = _number(decoded.optics_schema_version,1.0,1.0) or _number(decoded.optics_schema_version,2.0,2.0)
	var valid_mode: bool = decoded.path_mode in ["legacy_vertical","depth_reconstructed"] or (decoded.optics_schema_version == 2 and decoded.path_mode == "depth_unrefracted")
	if not valid_version or not valid_mode:
		_reject("invalid_optics_identity"); return
	if not _resource_path(decoded.lighting_profile) or FileAccess.get_sha256(decoded.lighting_profile) != decoded.lighting_profile_sha256:
		_reject("optics_resource_hash_mismatch"); return
	if not _number(decoded.extinction_shallow_m,0.001,20.0) or not _number(decoded.extinction_deep_m,0.001,20.0) or not _number(decoded.scatter_gain,0.0,2.0) or not _number(decoded.refraction_scale,0.0,0.03):
		_reject("invalid_optics_range"); return
	if typeof(decoded.shallow_preserve) != TYPE_BOOL:
		_reject("invalid_optics_boolean"); return
	lighting_profile_path = decoded.lighting_profile
	super._ready()

func _configure_scene() -> void:
	super._configure_scene()
	water_material.set_shader_parameter("natural_path_mode",1 if optics_profile.path_mode == "depth_reconstructed" else 0)
	if optics_profile.optics_schema_version == 2:
		water_material.set_shader_parameter("natural_path_mode",0 if optics_profile.path_mode == "legacy_vertical" else 1)
		water_material.set_shader_parameter("natural_path_unrefracted",optics_profile.path_mode == "depth_unrefracted")
	water_material.set_shader_parameter("prototype_shallow_extinction_m",optics_profile.extinction_shallow_m)
	water_material.set_shader_parameter("prototype_deep_extinction_m",optics_profile.extinction_deep_m)
	water_material.set_shader_parameter("natural_scatter_gain",optics_profile.scatter_gain)
	water_material.set_shader_parameter("prototype_optical_shallow_preserve",optics_profile.shallow_preserve)
	water_material.set_shader_parameter("prototype_refraction_scale",optics_profile.refraction_scale)

func _seal_test1_effective_profile() -> void:
	super._seal_test1_effective_profile()
	effective_optics = {"schema":optics_profile.optics_schema_version,"profile":optics_profile_path,"profile_sha256":_candidate_digest(optics_profile_path),
		"shader":water_material.shader.resource_path,"shader_sha256":_candidate_digest(water_material.shader.resource_path),
		"path_mode":optics_profile.path_mode,"path_semantics":"view-space Euclidean water-to-opaque distance; schema2 depth_unrefracted uses original SCREEN_UV",
		"invalid_path_fallback":"legacy_vertical","path_limit_m":50.0}
	for name in ["natural_path_mode","natural_scatter_gain","prototype_shallow_extinction_m","prototype_deep_extinction_m","prototype_optical_shallow_preserve","prototype_refraction_scale"]:
		effective_optics[name] = water_material.get_shader_parameter(name)
	if optics_profile.optics_schema_version == 2:
		effective_optics["natural_path_unrefracted"] = water_material.get_shader_parameter("natural_path_unrefracted")
