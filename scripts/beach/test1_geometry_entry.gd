extends "res://scripts/beach/async_pipeline_entry.gd"

const GeometryLayout := preload("res://scripts/scenarios/test1_geometry_layout.gd")
const GRID := preload("res://assets/test1_geometry/visible_grid.res")

func _ready() -> void:
	super._ready()
	player_camera.fov = 30.0
	player_camera.global_transform = $CameraAnchors/Oblique.global_transform
	set_player_camera(true)

func _initialize_domain(target: SandWaterDomain) -> bool:
	return GeometryLayout.initialize(target)

func _make_grid_mesh(_subdivision: int = 1) -> ArrayMesh:
	return GRID

func _configure_scene() -> void:
	super._configure_scene()
	var side_material := $SandSides.material_override as ShaderMaterial
	side_material.set_shader_parameter("rock_state", rock_texture)
	side_material.set_shader_parameter("sand_state", sand_texture)
	$SandFixtureSun.shadow_enabled = true

func _pick_current(hit: Dictionary, allow_completed_collision: bool = false) -> bool:
	if not hit.has("position") or not GeometryLayout.contains(hit.position):
		return false
	return super._pick_current(hit, allow_completed_collision)

func _runtime_configuration_signature() -> Dictionary:
	var signature := super._runtime_configuration_signature()
	_index_sources("res://assets/test1_geometry", signature.sources)
	signature.sources["res://scripts/scenarios/test1_geometry_layout.gd"] = FileAccess.get_sha256("res://scripts/scenarios/test1_geometry_layout.gd")
	for path in ["res://assets/test1_geometry/visible_grid.res", "res://assets/test1_geometry/sand_sides.res"]:
		signature.sources[path] = FileAccess.get_sha256(path)
	return signature
