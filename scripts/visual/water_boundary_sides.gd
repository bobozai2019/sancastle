extends MeshInstance3D

## Fixed topology; only the vertex shader moves the boundary. The source water
## owns the Texture2DRD wrappers, including publication and restore RID changes.
const MANIFEST := "res://assets/water_sides/geometry_manifest.json"
const DYNAMIC_PARAMETERS := [&"visual_time_s", &"use_async_clock", &"async_clock", &"prototype_front_face_source_gate", &"prototype_front_face_source_started"]
@export var boundary_min := Vector2(-15.96875, -15.96875)
@export var boundary_max := Vector2(15.96875, 15.96875)
var source_material: ShaderMaterial
var bound_generation := -1
var last_profile_revision := -1
var parameter_cache := {}
var configured := false

func bind_surface(water: ShaderMaterial, bed: ShaderMaterial) -> String:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary or manifest.get("schema") != 1:
		return "water_side_manifest"
	for pair in [[water.shader, "water"], [bed.shader, "bed"], [(material_override as ShaderMaterial).shader, "shader"]]:
		var shader: Shader = pair[0]
		var key: String = pair[1]
		var expected: String = manifest[key + "_sha256"] if shader.resource_path == manifest[key] else str(manifest.equivalent_sources.get(shader.resource_path, ""))
		if expected.is_empty() or FileAccess.get_sha256(shader.resource_path) != expected:
			return "water_side_stale_geometry:" + key
	source_material = water
	var material := material_override as ShaderMaterial
	material.set_shader_parameter("side_min_xz", boundary_min)
	material.set_shader_parameter("side_max_xz", boundary_max)
	sync_parameters()
	configured = true
	return ""

func sync_parameters() -> void:
	if source_material == null: return
	var material := material_override as ShaderMaterial
	var supported := {}
	for entry in material.shader.get_shader_uniform_list(): supported[entry.name] = true
	for entry in source_material.shader.get_shader_uniform_list():
		if supported.has(entry.name): _copy_parameter(entry.name)

func _copy_parameter(key: StringName) -> void:
	var value: Variant = source_material.get_shader_parameter(key)
	if value == null:
		value = RenderingServer.shader_get_parameter_default(source_material.shader.get_rid(), key)
	if value != null and (not parameter_cache.has(key) or parameter_cache[key] != value):
		(material_override as ShaderMaterial).set_shader_parameter(key, value)
		parameter_cache[key] = value

func _process(_delta: float) -> void:
	if not configured: return
	var beach := get_parent()
	visible = beach.ready_for_ticks and not beach.closing and beach.last_error.is_empty()
	if not visible: return
	if bound_generation != beach.generation or last_profile_revision != beach.effective_profile_revision:
		sync_parameters()
		bound_generation = beach.generation
		last_profile_revision = beach.effective_profile_revision
	for key in DYNAMIC_PARAMETERS: _copy_parameter(key)
