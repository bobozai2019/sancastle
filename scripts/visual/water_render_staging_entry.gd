extends "res://tests/visual_water_alignment/prototypes/reference_preview.gd"

const RenderProfile = preload("res://scripts/visual/water_render_profile.gd")
const WaveWorkload = preload("res://scripts/visual/water_render_wave_workload.gd")

@export_file("*.json") var render_profile_path := \
	"res://tests/visual_water_alignment/prototypes/water_render_staging_v1.json"
@export_enum("none", "single_packet_v1", "continuous_packets_v1") \
	var staging_wave_workload := "single_packet_v1"

var requested_render_profile := {}
var requested_render_profile_sha256 := ""
var effective_render_profile := {}
# Fixed uniforms/resources are audited on startup, invalidation and restore.
# Direct runtime uniform edits must invalidate explicitly (ShaderMaterial.changed
# does not report set_shader_parameter). The clock and export digest stay current.
var effective_profile_cache_enabled := true
var effective_profile_dirty := true
var effective_profile_generation := -1
var effective_profile_revision := 0
var effective_profile_digest_dirty := true
var effective_profile_digest := ""
var effective_profile_resources: Array[Resource] = []
var effective_water_material: ShaderMaterial
var effective_terrain_material: ShaderMaterial
var effective_water_shader: Shader
var effective_terrain_shader: Shader
var effective_render_profile_sha256: String:
	get:
		if _effective_profile_needs_refresh() and ready_for_ticks:
			refresh_effective_render_profile()
		if effective_profile_digest_dirty:
			effective_profile_digest = JSON.stringify(effective_render_profile).sha256_text()
			effective_profile_digest_dirty = false
		return effective_profile_digest


func _ready() -> void:
	var result: Dictionary = RenderProfile.load_file(render_profile_path)
	if not result.get("ok", false):
		last_error = "render profile: " + String(result.get("code", "invalid"))
		push_error(last_error)
		return
	requested_render_profile = result.profile
	requested_render_profile_sha256 = result.source_sha256
	if not replay_checkpoint.is_empty():
		var saved_profile: Variant = replay_checkpoint.get("render_profile", {})
		if not saved_profile is Dictionary or \
				saved_profile.get("profile_id") != requested_render_profile.profile_id or \
				saved_profile.get("schema_version") != requested_render_profile.schema_version or \
				saved_profile.get("source_path") != render_profile_path or \
				saved_profile.get("source_sha256") != requested_render_profile_sha256 or \
				not replay_checkpoint.get("local_front_history") is PackedFloat32Array or \
				replay_checkpoint.local_front_history.size() != 256 * 256 * 2 or \
				not is_equal_approx(float(saved_profile.get("visual_time_s", -1.0)),
					float(replay_checkpoint.get("tick", -1)) / 30.0):
			last_error = "render profile: checkpoint mismatch"
			push_error(last_error)
			return
	if String(fixture_id) not in requested_render_profile.target_fixture_ids or \
			fixture_id not in [&"water_render_demo_v2", &"water_render_coupled_v2"]:
		last_error = "render profile: fixture mismatch"
		push_error(last_error)
		return
	var cap: Dictionary = requested_render_profile.capabilities
	var visual: Dictionary = requested_render_profile.visual
	prototype_natural_reference_shore = true
	prototype_structured_reference_bed = true
	prototype_lobed_reference_bed = requested_render_profile.reference_bed == \
		"estuary_branched_v1"
	prototype_branched_reference_bed = prototype_lobed_reference_bed
	prototype_estuary_reference_bed = prototype_lobed_reference_bed
	prototype_local_front_field = cap.local_front.enabled
	prototype_offshore_core_source_gate = visual.get("offshore_core", false)
	prototype_fold_caustics = cap.fold_caustics.enabled
	prototype_imported_caustic_pattern_path = String(requested_render_profile.resources.caustic_pattern)
	prototype_coupled_caustics = cap.fold_caustics.enabled and enable_erosion
	enable_phase2_foam = cap.main_foam.enabled
	render_subdivision = int(requested_render_profile.render_subdivision)
	visual_time_s = 0.0
	if not replay_checkpoint.is_empty():
		visual_time_s = float(replay_checkpoint.tick) / 30.0
	super._ready()


func _start_checkpoint_capture() -> void:
	super._start_checkpoint_capture()
	if checkpoint_capture_pending and not checkpoint_capture.is_empty():
		checkpoint_capture["render_profile"] = {
			"profile_id": requested_render_profile.profile_id,
			"schema_version": requested_render_profile.schema_version,
			"source_path": render_profile_path,
			"source_sha256": requested_render_profile_sha256,
			"visual_time_s": float(completed_ticks) / 30.0,
		}


func _configure_scene() -> void:
	super._configure_scene()
	var resources: Dictionary = requested_render_profile.resources
	var visual: Dictionary = requested_render_profile.visual
	var cap: Dictionary = requested_render_profile.capabilities
	var terrain_path: String = String(resources.terrain_coupled_shader) if \
			fixture_id == &"water_render_coupled_v2" else \
			String(resources.terrain_fixed_shader)
	terrain_material.shader = load(terrain_path)
	water_material.shader = load(resources.water_shader)
	water_material.set_shader_parameter("rock_state", rock_texture)
	water_material.set_shader_parameter("sand_state", sand_texture)
	water_material.set_shader_parameter("water_state", water_texture)
	water_material.set_shader_parameter("momentum_x_state", momentum_x_texture)
	water_material.set_shader_parameter("momentum_z_state", momentum_z_texture)
	water_material.set_shader_parameter("foam_state", foam_texture)
	water_material.set_shader_parameter("local_front_state", local_front_texture)
	water_material.set_shader_parameter("prototype_use_local_front", cap.local_front.enabled)
	water_material.set_shader_parameter("phase2_optics", true)
	water_material.set_shader_parameter("phase2_foam", cap.main_foam.enabled)
	water_material.set_shader_parameter("prototype_crest_broken_core", false)
	water_material.set_shader_parameter("prototype_offshore_core",
		visual.get("offshore_core", false))
	water_material.set_shader_parameter("prototype_offshore_core_broken",
		visual.get("offshore_core_broken", false))
	water_material.set_shader_parameter("prototype_offshore_core_crown",
		visual.get("offshore_core_crown", false))
	water_material.set_shader_parameter("prototype_eta_normals", cap.eta_normals.enabled)
	water_material.set_shader_parameter("prototype_screen_optics", cap.screen_optics.enabled)
	water_material.set_shader_parameter("prototype_optical_shallow_preserve",
		visual.get("shallow_preserve", false))
	water_material.set_shader_parameter("prototype_screen_world_glint", false)
	water_material.set_shader_parameter("prototype_screen_abs_fresnel", visual.face_normal)
	water_material.set_shader_parameter("prototype_screen_face_normal", visual.face_normal)
	water_material.set_shader_parameter("prototype_crest_height_m", visual.crest_height_m)
	water_material.set_shader_parameter("prototype_shallow_extinction_m",
		visual.shallow_extinction_m)
	water_material.set_shader_parameter("prototype_refraction_scale", visual.refraction_scale)
	water_material.set_shader_parameter("water_surface_bias_m",
		requested_render_profile.surface_bias_m)
	water_material.set_shader_parameter("display_reconstruction", render_subdivision > 1)
	water_material.set_shader_parameter("visual_time_s", visual_time_s)
	terrain_material.set_shader_parameter("visual_time_s", visual_time_s)
	terrain_material.set_shader_parameter("phase2_caustics", cap.fold_caustics.enabled)
	if requested_render_profile.schema_version >= 7:
		terrain_material.set_shader_parameter("prototype_caustic_softness",
			visual.caustic_softness)
		terrain_material.set_shader_parameter("prototype_caustic_strength",
			visual.caustic_strength)
		terrain_material.set_shader_parameter("prototype_caustic_uv_scale",
			visual.caustic_uv_scale)


func _mark_ready(token: int) -> void:
	super._mark_ready(token)
	if not ready_for_ticks or not last_error.is_empty():
		return
	if replay_checkpoint.is_empty():
		var scheduled: Dictionary = WaveWorkload.schedule(self, staging_wave_workload)
		if not scheduled.get("ok", false):
			_fail("staging wave workload: " + String(scheduled.get("code", "invalid")))
			return
	refresh_effective_render_profile()


func invalidate_effective_render_profile() -> void:
	effective_profile_dirty = true
	effective_profile_digest_dirty = true


func _effective_profile_needs_refresh() -> bool:
	return effective_profile_dirty or effective_profile_generation != generation or \
		water_material != effective_water_material or terrain_material != effective_terrain_material or \
		water_material.shader != effective_water_shader or terrain_material.shader != effective_terrain_shader


func _effective_profile_request() -> Dictionary:
	return requested_render_profile

func refresh_effective_render_profile() -> bool:
	# A forced call also audits direct uniform edits used by tools and probes.
	var effective_request:=_effective_profile_request()
	effective_render_profile = RenderProfile.effective_from_materials(
		effective_request, fixture_id, water_material, terrain_material,
		render_subdivision, visual_time_s, _effective_reference_bed())
	if not RenderProfile.effective_matches_request(effective_request,
			fixture_id, effective_render_profile):
		_fail("render profile effective values mismatch")
		return false
	effective_profile_generation = generation
	effective_profile_revision += 1
	effective_water_material = water_material
	effective_terrain_material = terrain_material
	effective_water_shader = water_material.shader
	effective_terrain_shader = terrain_material.shader
	for resource in effective_profile_resources:
		if resource.changed.is_connected(invalidate_effective_render_profile):
			resource.changed.disconnect(invalidate_effective_render_profile)
	effective_profile_resources.assign([water_material, terrain_material,
		water_material.shader, terrain_material.shader])
	for resource in effective_profile_resources:
		if not resource.changed.is_connected(invalidate_effective_render_profile):
			resource.changed.connect(invalidate_effective_render_profile)
	effective_profile_dirty = false
	_seal_test1_effective_profile()
	effective_profile_digest_dirty = true
	return last_error.is_empty()


func _seal_test1_effective_profile() -> void:
	pass


func set_visual_time(seconds: float) -> void:
	super.set_visual_time(seconds)
	if not effective_render_profile.is_empty() and effective_render_profile.visual_time_s != seconds:
		effective_render_profile.visual_time_s = seconds
		effective_profile_digest_dirty = true


func _tick_finished(substeps: int, source_m3: float, sink_m3: float,
		token: int) -> void:
	super._tick_finished(substeps, source_m3, sink_m3, token)
	if last_error.is_empty() and token == generation:
		set_visual_time(float(completed_ticks) / 30.0)
		if not effective_profile_cache_enabled or _effective_profile_needs_refresh():
			refresh_effective_render_profile()


func _effective_reference_bed() -> String:
	if prototype_natural_reference_shore and prototype_structured_reference_bed and \
			prototype_lobed_reference_bed and prototype_branched_reference_bed and \
			prototype_estuary_reference_bed:
		return "estuary_branched_v1"
	return "natural_structured_v1"
