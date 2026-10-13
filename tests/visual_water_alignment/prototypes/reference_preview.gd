extends Node3D

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const GpuSolver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const SyncGpuSolver = preload("res://tests/visual_water_alignment/prototypes/reference_sync_readback_solver.gd")
const SandAudit = preload("res://scripts/simulation/gpu_sand_audit.gd")
const CheckpointStore = preload("res://scripts/simulation/checkpoint_store.gd")
const SedimentCoupler = preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const MaterialCoupler = preload("res://scripts/simulation/material/gpu_material_coupler.gd")
const StructureField = preload("res://scripts/structures/structure_field.gd")
const Structure = preload("res://scripts/structures/structure_state.gd")
const ObstacleRemap = preload("res://scripts/structures/gpu_obstacle_remap.gd")
const CommandQueue = preload("res://scripts/sand/tool_command_queue.gd")
const Scenarios = preload("res://scripts/scenarios/standard_scenarios.gd")
const WaterFixture = preload("res://tests/visual_water_alignment/prototypes/reference_bed.gd")
const SandFixture = preload("res://tests/visual_water_alignment/prototypes/reference_bed.gd")
const FoamField = preload("res://scripts/visual/gpu_foam_field.gd")
const RiseFrontField = preload("res://tests/visual_water_alignment/prototypes/reference_rise_front_field.gd")
const LocalFrontField = preload("res://tests/visual_water_alignment/prototypes/reference_local_front_field.gd")
const ContactHistoryField = preload("res://tests/visual_water_alignment/prototypes/reference_contact_history_field.gd")
const TideLedgerRing = preload("res://tests/visual_water_alignment/prototypes/reference_tide_ledger_ring.gd")
const TideLedgerBatches = preload("res://tests/visual_water_alignment/prototypes/reference_tide_ledger_batches.gd")
const BatchedLedgerSolver = preload("res://tests/visual_water_alignment/prototypes/reference_batched_ledger_solver.gd")
const FixedSubstepSolver = preload("res://tests/visual_water_alignment/prototypes/reference_fixed_substep_solver.gd")
## Structure damage accrues at this rate once support is missing, divided by the
## same strength curve the erosion pass uses.
const STRUCTURE_DAMAGE_RATE_PER_S := 4.0
const GRID_SIZE := 256
const CELL_SIZE_M := 0.125
const SIM_DELTA := 1.0 / 30.0
const WAVE_PROFILES := {
	&"small_packet": {"amplitude_max_m": 0.06, "duration_min_s": 0.5,
		"duration_max_s": 3.0},
	&"test_packet": {"amplitude_max_m": 0.20, "duration_min_s": 0.5,
		"duration_max_s": 6.0},
}
const MAX_CHECKPOINTS := 8
const DEBUG_NAMES := ["画面", "床高", "水深", "流速方向", "湿度", "压实度", "沙厚",
	"悬沙", "障碍", "−X 出流", "+X 出流", "−Z 出流", "+Z 出流",
	"脏块", "碰撞差异"]

@export_range(0, 2) var preset_index := 0
@export var enable_erosion := false
@export_range(0.0, 2.0) var sand_cohesion_yield_height_m := 0.0
@export var sand_fixture_wetness_override := -1.0
@export var fixture_id: StringName = &""
@export var fixture_camera_id: StringName = &"oblique"
@export var visual_time_s := -1.0
@export var prototype_imported_caustic_pattern_path := ""
@export var enable_phase2_foam := true
@export var prototype_coupled_caustics := false
@export var prototype_cell_caustics := false
@export var prototype_fold_caustics := false
@export var prototype_sync_boundary_readback := false
@export var prototype_crest_curtain := false
@export var prototype_crest_ribbon := false
@export var prototype_crest_ribbon_body := false
@export var prototype_crest_ribbon_attached := false
@export var prototype_crest_ribbon_smooth_mask := false
@export var prototype_crest_rise_ribbon := false
@export var prototype_rise_crest := false
@export var prototype_rise_front_field := false
@export var prototype_unified_adaptive_anchor := false
@export var prototype_local_front_field := false
@export var prototype_branch_face := false
@export var prototype_branch_face_capped := false
@export var prototype_branch_face_2d := false
@export var prototype_branch_face_patches := false
@export var prototype_branch_face_row_center := false
@export var prototype_branch_face_soft_material := false
@export var prototype_branch_face_surface_join := false
@export var prototype_offshore_foam_source := false
@export var prototype_front_band_foam_source := false
@export var prototype_contact_history_field := false
@export var prototype_local_front_wide_field := false
@export var prototype_crest_solid_lip := false
@export var prototype_crest_water_body := false
@export var prototype_crest_shared_profile := false
@export var prototype_crest_smoothed_lip := false
@export var prototype_crest_forward_toe := false
@export var prototype_unified_curl := false
@export var prototype_foam_splats := false
@export var prototype_foam_splats_jitter := false
@export var prototype_foam_front_splats := false
@export var prototype_foam_front_local_dense := false
@export var prototype_front_face_source_gate := false
@export var prototype_offshore_core_source_gate := false
@export var prototype_foam_front_local_diameter_px := 3.5
@export var prototype_foam_front_smooth := false
@export var prototype_foam_splats_fine := false
@export var prototype_foam_front_raised := false
@export var prototype_foam_front_pixel_sized := false
@export var prototype_foam_surface_lift_m := 0.0
@export var prototype_crest_volume := false
@export var prototype_crest_volume_debug := false
@export var prototype_local_front_volume := false
@export var prototype_local_front_segments := false
@export var prototype_local_front_continuous_lip := false
@export var prototype_unified_dense := false
@export var prototype_unified_smooth_profile := false
@export var prototype_unified_centered_base := false
@export var prototype_unified_monotonic_base := false
@export var prototype_crest_ribbon_depth_write := false
@export var prototype_crest_row_window := Vector2(0.0, 1.0)
@export_range(0, 4096) var prototype_ledger_ring_capacity := 0
@export_range(0, 1024) var prototype_ledger_batch_ticks := 0
@export var prototype_batched_ledger_bookkeeping := false
@export_range(0, 64) var prototype_fixed_substeps := 0
@export var prototype_fixed_cfl_audit := false
@export var prototype_smooth_reference_shore := false
@export var prototype_natural_reference_shore := false
@export var prototype_structured_reference_bed := false
@export var prototype_sculpted_reference_bed := false
@export var prototype_lobed_reference_bed := false
@export var prototype_branched_reference_bed := false
@export var prototype_estuary_reference_bed := false
@export var prototype_test1_sand_forms := false
@export_range(1, 4) var render_subdivision := 1
## Player-facing presentation switches. The recording path turns both on so the
## captured frames show the effect instead of the diagnostic overlay.
@export var hide_hud := false
## T06 structure layer. Off by default so the existing coupled regressions keep
## their exact behaviour; a build pushes packed sand plus collision in one event.
@export var enable_structures := false
## The brush ring is tool feedback, not clutter, so it is its own switch: a
## recording can hide the text HUD and still show where the brush will act (or
## hide both, for a fully unobstructed view).
@export var show_brush_indicator := true
@export var use_player_camera := false
@export var player_camera_position := Vector3(-6.0, 3.2, 7.5)
@export var player_camera_target := Vector3(3.0, 0.2, -0.5)

var solver: SandcastleGpuShallowSolver
var tide_ledger_ring
var tide_ledger_batches
var tide_ledger_ring_spirv: RDShaderSPIRV
var tide_ledger_cpu_pairs: Array[Dictionary] = []
var tide_ledger_batch_results: Array[Dictionary] = []
var tide_ledger_pending_batches := {}
var tide_ledger_next_batch := 0
var tide_ledger_settled_ticks := 0
var tide_ledger_checkpoint_waiting := false
var fixed_cfl_audit_count := 0
var fixed_cfl_max_required := 0
var fixed_cfl_over_bound := 0
var foam_field: SandcastleGpuFoamField
var rise_front_field
var rise_front_spirv: RDShaderSPIRV
var rise_front_anchor_spirv: RDShaderSPIRV
var local_front_field
var contact_history_field
var contact_history_spirv: RDShaderSPIRV
var local_front_x_spirv: RDShaderSPIRV
var local_front_z_spirv: RDShaderSPIRV
var sand_audit: SandcastleGpuSandAudit
var sediment_coupler: SandcastleGpuSedimentCoupler
var material_coupler: SandcastleGpuMaterialCoupler
var structure_field: SandcastleStructureField
var obstacle_remap: SandcastleGpuObstacleRemap
## Volume booked by the most recent structure build, published back to the main
## thread by the render-thread build so a caller can confirm it took effect.
var last_structure_booked_m3 := 0.0
var structure_builds := 0
## Structures whose collapse has been decided but not yet pushed to the GPU.
var pending_collapse_patches: Array[SandcastleStructure] = []
var structures_collapsed := 0
## Set when the last placement was refused, so the HUD can explain why instead of
## the player seeing nothing happen.
var last_structure_error := ""
## Volume the last refused placement asked for, so the HUD can say how short the
## bucket was.
var structure_requirement_hint_m3 := 0.0
@onready var collision_proxy: SandcastleGpuCollisionProxy = $GpuCollisionProxy
var shadow_domain: SandWaterDomain
var command_queue: ToolCommandQueue
var rock_texture := Texture2DRD.new()
var sand_texture := Texture2DRD.new()
var wetness_texture := Texture2DRD.new()
var compaction_texture := Texture2DRD.new()
var water_texture := Texture2DRD.new()
var momentum_x_texture := Texture2DRD.new()
var momentum_z_texture := Texture2DRD.new()
var sediment_texture := Texture2DRD.new()
var obstacle_texture := Texture2DRD.new()
var flux_texture := Texture2DRD.new()
var foam_texture := Texture2DRD.new()
var previous_foam_texture := Texture2DRD.new()
var rise_front_texture := Texture2DRD.new()
var local_front_texture := Texture2DRD.new()
var contact_history_texture := Texture2DRD.new()
var chunk_debug_texture: ImageTexture
var terrain_material: ShaderMaterial
var water_material: ShaderMaterial
var spirvs: Array[RDShaderSPIRV] = []
@onready var status_label: Label = $Interface/StatusLabel
@onready var overview_camera: Camera3D = $GpuOverviewCamera
@onready var player_camera: Camera3D = $GpuPlayerCamera
@onready var brush_indicator: SandcastleBrushIndicator = $BrushIndicator
var completed_ticks := 0
## Optional W07 prototype-only timing across main/render threads. The clocks
## share Time.get_ticks_usec; no GPU synchronization or solver path is changed.
var profile_tick_timing := false
@export var prototype_worker_handoff := false
var worker_ledger_seen := false
var worker_cfl_seen := false
var worker_ledger_valid := false
var worker_cfl_bytes := PackedByteArray()
var worker_cfl_revision := -1
var worker_cfl_substeps := 0
var worker_finish_dispatched := false
var worker_task_id := -1
var profile_main_frame_timing := false
var profile_main_frame_rows: Array[PackedInt64Array] = []
var profile_tick_start_us := 0
var profile_ledger_us := 0
var profile_cfl_us := 0
var profile_both_us := 0
var profile_render_begin_us := 0
var profile_render_submit_us := 0
var profile_ledger_render_us := 0
var profile_cfl_render_us := 0
var profile_render_finish_us := 0
var profile_render_finish_submit_us := 0
var profile_tick_rows: Array[PackedInt64Array] = []
var capture_substep_trace := false
var capture_substep_rows: Array[Vector3i] = []
var generation := 1
var accumulator := 0.0
var playing := true
var tick_pending := false
var water_tick_in_flight := false
var tide_ready := false
var cfl_ready := false
var finish_dispatched := false
var cfl_data := PackedByteArray()
var cfl_revision := -1
var cfl_substeps := 0
var ready_for_ticks := false
var closing := false
var last_error := ""
var last_substeps := 0
var last_source_m3 := 0.0
var last_sink_m3 := 0.0
var wave_requests: Array[Dictionary] = []
var wave_highwater_id := 0
var wave_clamp_events := 0
var support_loss_highwater_id := 0
var support_loss_applied_id := 0
var support_loss_events: Array[Dictionary] = []
var last_support_loss_error: StringName = &""
var auto_support_sensor_in_flight := false
var auto_support_pending := false
var auto_support_event_active := false
var auto_support_toe_initial_m3 := 51.0 * 0.18 * CELL_SIZE_M * CELL_SIZE_M
var auto_support_toe_latest_m3 := NAN
var auto_support_trigger_revision := -1
var command_id := 0
var last_tool_submit_usec := -1
@export var prefetch_sand_on_hover := false
var last_sand_hover_usec := -1
var completed_patch_batches := 0
var last_dirty_cells := 0
var last_dirty_chunks := PackedInt32Array()
var dirty_debug_revision := 0
var chunk_debug_dirty_revision := -1
var chunk_debug_collision_batches := -1
var proxy_debug_max_error_m := 0.0
var proxy_debug_missing_chunks := 64
var proxy_debug_shadow_stale := false
var max_cell_edit_height_m := 0.0
var tool_revision_by_command_id: Dictionary = {}
var tool_apply_usec_by_command_id: Dictionary = {}
var profile_tool_latency := false
var debug_view := 0
var audit_water_m3 := NAN
var audit_min_depth_m := NAN
var audit_invalid_cells := -1
var audit_negative_cells := -1
var audit_revision := -1
var initial_sand_total_m3 := 0.0
var audit_sand_m3 := NAN
var audit_sediment_m3 := NAN
var audit_sand_total_m3 := NAN
var audit_sand_closure_m3 := NAN
var audit_sand_invalid_cells := -1
var audit_sand_negative_cells := -1
var audit_sand_revision := -1
var sand_audit_refresh_required := false
var shadow_revision := -1
var shadow_sand_revision := -1
var shadow_sync_fields := {}
var shadow_sync_reason := ""
var shadow_sync_full := false
var full_shadow_syncs := 0
var full_shadow_bytes := 0
var sand_only_syncs := 0
var sand_only_bytes := 0
var sand_prefetch_revision := -1
var sand_prefetch_in_flight := false
var sand_prefetch_hits := 0
var sand_prefetch_bytes := 0
var dirty_summary_bytes := 0
var collision_change_upper_bound_m := PackedFloat32Array()
var dirty_summaries_checked := 0
## The dirty-chunk summary is a conservative upper bound on how far the bed moved,
## and it only feeds the collision proxy - nothing in the water or sand physics
## reads it. It therefore does not gate the tick: the tick finishes as soon as its
## substeps are dispatched and the summary is consumed whenever it lands. When a
## summary is still in flight the reset is skipped, so the pending readback
## carries the max over all the ticks it covers; `dirty_ticks_covered` is how many,
## and the per-tick bound is scaled by it.
var dirty_ticks_covered := 0
var dirty_summaries_missed := 0
var nonzero_dirty_summary_ticks := 0
var max_gpu_dirty_um := 0
var replay_commands: Array[Dictionary] = []
var replay_target_tick := -1
var replay_highwater_id := 0
var replay_ready := false
var replay_collision_requested := false
var replay_checkpoint: Dictionary = {}
var replay_prefix_commands: Array[Dictionary] = []
var replay_wave_requests: Array[Dictionary] = []
var checkpoint_interval_ticks := 0
var checkpoints: Array[Dictionary] = []
var checkpoint_capture_pending := false
var checkpoint_capture: Dictionary = {}
var pending_save_path := ""
var last_save_path := ""
var last_save_error: StringName = &""
var active_brush_kind: StringName = &""
var last_brush_position := Vector3.ZERO


func _initialize_domain(target: SandWaterDomain) -> bool:
	if fixture_id == WaterFixture.FIXTURE_ID:
		return WaterFixture.initialize(target, -1.0, false,
			prototype_smooth_reference_shore, prototype_natural_reference_shore,
			prototype_structured_reference_bed, prototype_sculpted_reference_bed,
			prototype_lobed_reference_bed, prototype_branched_reference_bed,
			prototype_estuary_reference_bed, prototype_test1_sand_forms)
	if fixture_id in [&"reference_sand_unused", SandFixture.COUPLED_FIXTURE_ID]:
		return SandFixture.initialize(target, sand_fixture_wetness_override,
			fixture_id == SandFixture.COUPLED_FIXTURE_ID,
			prototype_smooth_reference_shore, prototype_natural_reference_shore,
			prototype_structured_reference_bed, prototype_sculpted_reference_bed,
			prototype_lobed_reference_bed, prototype_branched_reference_bed,
			prototype_estuary_reference_bed, prototype_test1_sand_forms)
	return Scenarios.initialize(target, preset_index) if fixture_id.is_empty() else false

func _ready() -> void:
	$EditorPreviewController.visible = false
	var visual_editor_preview := get_node_or_null("VisualEditorPreview") as Node3D
	if visual_editor_preview != null:
		visual_editor_preview.visible = false
	shadow_domain = Domain.new(GRID_SIZE, CELL_SIZE_M)
	var fixture_ok := _initialize_domain(shadow_domain)
	if not fixture_ok:
		_fail("invalid GPU preset index: %d" % preset_index)
		return
	if fixture_id == WaterFixture.FIXTURE_ID and (enable_erosion or enable_structures or WaterFixture.camera_index(fixture_camera_id) < 0):
		_fail("water fixture requires frozen sand, no structures, and a valid camera")
		return
	if fixture_id in [&"reference_sand_unused", SandFixture.COUPLED_FIXTURE_ID] and (not enable_erosion or
			SandFixture.camera_index(fixture_camera_id) < 0):
		_fail("sand fixture requires material coupling and a valid camera")
		return
	initial_sand_total_m3 = shadow_domain.total_sand_m3(true)
	if not replay_checkpoint.is_empty():
		if replay_checkpoint.get("tick", -1) < 0 or \
				replay_checkpoint.get("tick", -1) > replay_target_tick or \
				replay_checkpoint.get("preset_index", -1) != preset_index or \
				StringName(replay_checkpoint.get("fixture_id", fixture_id)) != fixture_id or \
				not shadow_domain.restore(replay_checkpoint.get("shadow", {})):
			_fail("GPU replay checkpoint invalid")
			return
		completed_ticks = replay_checkpoint.tick
		sand_cohesion_yield_height_m = float(replay_checkpoint.get(
			"sand_cohesion_yield_height_m", sand_cohesion_yield_height_m))
		support_loss_highwater_id = int(replay_checkpoint.get("support_loss_highwater_id", 0))
		for original_event in replay_checkpoint.get("support_loss_events", []):
			var event: Dictionary = original_event.duplicate(true)
			support_loss_events.append(event)
			support_loss_applied_id = maxi(support_loss_applied_id, int(event.request_id))
	collision_change_upper_bound_m.resize(64)
	collision_change_upper_bound_m.fill(0.0)
	# A restored snapshot carries historical data, but callbacks and new commands
	# belong to this scene instance's fresh generation.
	generation = maxi(generation, shadow_domain.generation)
	shadow_domain.generation = generation
	for event in support_loss_events:
		event["generation"] = generation
	command_queue = CommandQueue.new(shadow_domain)
	if not replay_checkpoint.is_empty():
		command_queue.applied_log = replay_prefix_commands.duplicate(true)
		for i in command_queue.applied_log.size():
			command_queue.applied_log[i]["generation"] = shadow_domain.generation
		command_queue.last_command_id = replay_checkpoint.highwater_id
	var restored_waves: Array = replay_wave_requests if not replay_wave_requests.is_empty() else \
		replay_checkpoint.get("wave_requests", [])
	for original_wave in restored_waves:
		var wave: Dictionary = original_wave.duplicate(true)
		wave["generation"] = generation
		wave_requests.append(wave)
	wave_highwater_id = int(replay_checkpoint.get("wave_highwater_id", 0))
	for wave in wave_requests:
		wave_highwater_id = maxi(wave_highwater_id, int(wave.request_id))
	for path in [
		"res://shaders/simulation/shallow_edge_flux.glsl",
		"res://shaders/simulation/shallow_drain_scale.glsl",
		"res://shaders/simulation/shallow_update_state.glsl",
		"res://shaders/simulation/shallow_tide_boundary.glsl",
		"res://shaders/simulation/shallow_cfl_tiles.glsl",
		"res://shaders/simulation/shallow_gauge_depth.glsl",
		"res://shaders/simulation/shallow_audit_tiles.glsl",
		"res://shaders/simulation/shallow_tool_patch.glsl",
		"res://shaders/simulation/shallow_collision_pack.glsl",
		"res://shaders/simulation/shallow_sand_audit_tiles.glsl",
		"res://shaders/simulation/erosion/sediment_step.glsl",
		"res://shaders/simulation/erosion/copy_after_boundary.glsl",
		"res://shaders/simulation/material/material_step.glsl",
		"res://shaders/simulation/material/slope_relax.glsl",
		"res://shaders/simulation/material/material_commit.glsl",
		"res://shaders/simulation/structures/obstacle_remap.glsl",
		"res://shaders/simulation/structures/obstacle_commit.glsl"]:
		var shader_file: RDShaderFile = load(path)
		if shader_file == null or shader_file.get_spirv() == null:
			_fail("compute shader import missing: " + path)
			return
		spirvs.append(shader_file.get_spirv())
	if fixture_id in [WaterFixture.FIXTURE_ID, SandFixture.COUPLED_FIXTURE_ID] and \
			enable_phase2_foam:
		var foam_shader_path := "res://shaders/simulation/visual_foam_step.glsl"
		if prototype_front_band_foam_source:
			foam_shader_path = "res://tests/visual_water_alignment/prototypes/reference_visual_foam_front_band.glsl"
		elif prototype_offshore_foam_source:
			foam_shader_path = "res://tests/visual_water_alignment/prototypes/reference_visual_foam_offshore.glsl"
		var foam_file: RDShaderFile = load(foam_shader_path)
		if foam_file == null or foam_file.get_spirv() == null:
			_fail("visual foam compute shader import missing")
			return
		spirvs.append(foam_file.get_spirv())
	if prototype_ledger_ring_capacity > 0 or prototype_ledger_batch_ticks > 0:
		var ring_file: RDShaderFile = load(
			"res://tests/visual_water_alignment/prototypes/reference_tide_ledger_ring.glsl")
		if ring_file == null or ring_file.get_spirv() == null:
			_fail("tide ledger ring shader import missing")
			return
		tide_ledger_ring_spirv = ring_file.get_spirv()
	if prototype_rise_front_field:
		var front_file: RDShaderFile = load(
			"res://tests/visual_water_alignment/prototypes/reference_rise_front_field.glsl")
		if front_file == null or front_file.get_spirv() == null:
			_fail("rise front compute shader import missing")
			return
		rise_front_spirv = front_file.get_spirv()
		if prototype_unified_adaptive_anchor:
			var anchor_file: RDShaderFile = load(
				"res://tests/visual_water_alignment/prototypes/reference_rise_front_anchor.glsl")
			if anchor_file == null or anchor_file.get_spirv() == null:
				_fail("rise front anchor compute shader import missing")
				return
			rise_front_anchor_spirv = anchor_file.get_spirv()
	if prototype_local_front_field:
		for path in [
			("res://tests/visual_water_alignment/prototypes/reference_local_front_x_wide.glsl" if prototype_local_front_wide_field else
			"res://tests/visual_water_alignment/prototypes/reference_local_front_x.glsl"),
			"res://tests/visual_water_alignment/prototypes/reference_local_front_z.glsl"]:
			var local_file: RDShaderFile = load(path)
			if local_file == null or local_file.get_spirv() == null:
				_fail("local front compute shader import missing: " + path)
				return
			if local_front_x_spirv == null:
				local_front_x_spirv = local_file.get_spirv()
			else:
				local_front_z_spirv = local_file.get_spirv()
	if prototype_contact_history_field:
		if not prototype_local_front_field:
			_fail("contact history requires local front field")
			return
		var contact_file: RDShaderFile = load(
			"res://tests/visual_water_alignment/prototypes/reference_contact_history_step.glsl")
		if contact_file == null or contact_file.get_spirv() == null:
			_fail("contact history compute shader import missing")
			return
		contact_history_spirv = contact_file.get_spirv()
	for original in replay_commands:
		var command: Dictionary = original.duplicate(true)
		command["generation"] = shadow_domain.generation
		var replay_error: StringName = command_queue.submit(command)
		if not replay_error.is_empty():
			_fail("GPU replay command rejected: " + String(replay_error))
			return
	command_id = maxi(replay_highwater_id, command_queue.last_command_id)
	## A restored checkpoint turns the structure layer on when it carries one, so a
	## scene saved with walls comes back with walls rather than inert sand.
	var saved_structures: Variant = replay_checkpoint.get("structures", {})
	var has_saved_structures: bool = typeof(saved_structures) == TYPE_DICTIONARY and \
		not (saved_structures as Dictionary).is_empty()
	if has_saved_structures:
		enable_structures = bool(replay_checkpoint.get("enable_structures", true))
	if enable_structures:
		structure_field = StructureField.new()
		if has_saved_structures and not structure_field.restore(saved_structures):
			_fail("checkpoint structure layer is malformed")
			return
	_configure_scene()
	RenderingServer.call_on_render_thread(_render_setup.bind(shadow_domain, generation))


func _configure_scene() -> void:
	player_camera.position = player_camera_position
	player_camera.look_at(player_camera_target, Vector3.UP)
	if use_player_camera:
		set_player_camera(true)
	if fixture_id in [WaterFixture.FIXTURE_ID, &"reference_sand_unused",
			SandFixture.COUPLED_FIXTURE_ID]:
		set_fixture_camera(fixture_camera_id)
	var environment: Environment = $WorldEnvironment.environment
	var sand_fixture: bool = fixture_id in [&"reference_sand_unused",
		SandFixture.COUPLED_FIXTURE_ID]
	if fixture_id in [&"reference_sand_unused", SandFixture.COUPLED_FIXTURE_ID]:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(1.0, 0.93, 0.82)
		environment.ambient_light_energy = 0.75
	$SandFixtureSun.visible = sand_fixture
	$SandFixtureSun.shadow_enabled = fixture_id == &"reference_sand_unused"
	var grid_mesh := _make_grid_mesh(render_subdivision)
	var terrain: MeshInstance3D = $GpuSandTerrain
	terrain.mesh = grid_mesh
	terrain_material = terrain.material_override as ShaderMaterial
	terrain_material.shader = load("res://shaders/visual/gpu_sand_phase2.gdshader") if \
		fixture_id == &"reference_sand_unused" else \
		(load("res://tests/visual_water_alignment/prototypes/reference_coupled_bed.gdshader") if \
		fixture_id == SandFixture.COUPLED_FIXTURE_ID else \
		load("res://tests/visual_water_alignment/prototypes/reference_terrain.gdshader"))
	terrain_material.set_shader_parameter("rock_state", rock_texture)
	terrain_material.set_shader_parameter("sand_state", sand_texture)
	terrain_material.set_shader_parameter("wetness_state", wetness_texture)
	terrain_material.set_shader_parameter("compaction_state", compaction_texture)
	terrain_material.set_shader_parameter("water_state", water_texture)
	terrain_material.set_shader_parameter("prototype_texture_caustics",
		prototype_cell_caustics or prototype_fold_caustics)
	if prototype_cell_caustics or prototype_fold_caustics:
		var pattern_path := "res://tests/visual_water_alignment/prototypes/caustic_fold_v1.png" if \
			prototype_fold_caustics else "res://tests/visual_water_alignment/prototypes/caustic_cells_v1.png"
		if not prototype_imported_caustic_pattern_path.is_empty():
			terrain_material.set_shader_parameter("caustic_pattern",
				load(prototype_imported_caustic_pattern_path) as Texture2D)
		else:
			var caustic_image := Image.load_from_file(pattern_path)
			terrain_material.set_shader_parameter("caustic_pattern",
				ImageTexture.create_from_image(caustic_image))
	terrain_material.set_shader_parameter("momentum_x_state", momentum_x_texture)
	terrain_material.set_shader_parameter("momentum_z_state", momentum_z_texture)
	terrain_material.set_shader_parameter("sediment_state", sediment_texture)
	terrain_material.set_shader_parameter("obstacle_state", obstacle_texture)
	terrain_material.set_shader_parameter("flux_state", flux_texture)
	if fixture_id == WaterFixture.FIXTURE_ID:
		terrain_material.set_shader_parameter("apply_underwater_tint", false)
		terrain_material.set_shader_parameter("underwater_relief_boost", 4.0)
		terrain_material.set_shader_parameter("phase2_caustics", true)
		terrain_material.set_shader_parameter("visual_time_s", visual_time_s)
		terrain_material.set_shader_parameter("display_reconstruction", render_subdivision > 1)
	elif fixture_id in [&"reference_sand_unused", SandFixture.COUPLED_FIXTURE_ID]:
		terrain_material.set_shader_parameter("display_reconstruction", render_subdivision > 1)
		if fixture_id == SandFixture.COUPLED_FIXTURE_ID:
			terrain_material.set_shader_parameter("phase2_caustics", prototype_coupled_caustics)
			terrain_material.set_shader_parameter("visual_time_s", visual_time_s)
	var chunk_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	chunk_image.fill(Color.BLACK)
	chunk_debug_texture = ImageTexture.create_from_image(chunk_image)
	terrain_material.set_shader_parameter("chunk_debug_state", chunk_debug_texture)
	var water: MeshInstance3D = $GpuWaterSurface
	water.mesh = _make_unified_curl_mesh() if prototype_unified_curl else grid_mesh
	if prototype_unified_curl:
		water.custom_aabb = AABB(Vector3(-16.5, -2.0, -16.5),
			Vector3(33.0, 6.0, 33.0))
	water_material = water.material_override as ShaderMaterial
	water_material.shader = load("res://tests/visual_water_alignment/prototypes/reference_water.gdshader")
	water_material.set_shader_parameter("rock_state", rock_texture)
	water_material.set_shader_parameter("sand_state", sand_texture)
	water_material.set_shader_parameter("water_state", water_texture)
	# T07 flow ripples and foam read the same momentum the solver publishes.
	water_material.set_shader_parameter("momentum_x_state", momentum_x_texture)
	water_material.set_shader_parameter("momentum_z_state", momentum_z_texture)
	water_material.set_shader_parameter("foam_state", foam_texture)
	water_material.set_shader_parameter("visual_time_s", visual_time_s)
	if prototype_crest_volume:
		var volume := MeshInstance3D.new()
		volume.name = "PrototypeCrestVolume"
		volume.mesh = _make_crest_volume_mesh()
		volume.custom_aabb = AABB(Vector3(-16.5, -2.0, -16.5),
			Vector3(33.0, 6.0, 33.0))
		var volume_material := ShaderMaterial.new()
		volume_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_crest_local_volume.gdshader" if prototype_local_front_volume else
			"res://tests/visual_water_alignment/prototypes/reference_crest_volume.gdshader")
		volume_material.set_shader_parameter("rock_state", rock_texture)
		volume_material.set_shader_parameter("sand_state", sand_texture)
		volume_material.set_shader_parameter("water_state", water_texture)
		volume_material.set_shader_parameter("rise_front_state", rise_front_texture)
		if prototype_local_front_volume:
			volume_material.set_shader_parameter("local_front_state", local_front_texture)
			volume_material.set_shader_parameter("radius_x_m", 0.12)
			volume_material.set_shader_parameter("radius_y_m", 0.15)
		volume_material.set_shader_parameter("display_reconstruction",
			render_subdivision > 1)
		volume_material.set_shader_parameter("layer_debug",
			prototype_crest_volume_debug)
		volume.material_override = volume_material
		add_child(volume)
	if prototype_local_front_segments:
		var segments := MeshInstance3D.new()
		segments.name = "PrototypeLocalFrontSegments"
		segments.mesh = _make_local_front_segment_mesh()
		segments.custom_aabb = AABB(Vector3(-16.5, -2.0, -16.5),
			Vector3(33.0, 6.0, 33.0))
		var segment_material := ShaderMaterial.new()
		segment_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_crest_local_segments.gdshader")
		segment_material.set_shader_parameter("rock_state", rock_texture)
		segment_material.set_shader_parameter("sand_state", sand_texture)
		segment_material.set_shader_parameter("water_state", water_texture)
		segment_material.set_shader_parameter("local_front_state", local_front_texture)
		segment_material.set_shader_parameter("display_reconstruction",
			render_subdivision > 1)
		segments.material_override = segment_material
		add_child(segments)
	if prototype_local_front_continuous_lip:
		var lip: MeshInstance3D = $PrototypeFrontLips/PatchFrontLip if \
			prototype_branch_face_patches else ($PrototypeFrontLips/BranchFrontLip if \
			prototype_branch_face_2d else $PrototypeFrontLips/RowFrontLip)
		lip.visible = true
		var lip_material := lip.material_override as ShaderMaterial
		lip_material.set_shader_parameter("rock_state", rock_texture)
		lip_material.set_shader_parameter("sand_state", sand_texture)
		lip_material.set_shader_parameter("water_state", water_texture)
		lip_material.set_shader_parameter("local_front_state", local_front_texture)
		lip_material.set_shader_parameter("rise_front_state", rise_front_texture)
		lip_material.set_shader_parameter("prototype_branch_face", prototype_branch_face)
		lip_material.set_shader_parameter("prototype_branch_face_capped", prototype_branch_face_capped)
		lip_material.set_shader_parameter("prototype_branch_face_2d", prototype_branch_face_2d)
		lip_material.set_shader_parameter("prototype_branch_face_row_center",
			prototype_branch_face_row_center)
		lip_material.set_shader_parameter("prototype_branch_face_soft_material",
			prototype_branch_face_soft_material)
		lip_material.set_shader_parameter("prototype_branch_face_surface_join",
			prototype_branch_face_surface_join)
		lip_material.set_shader_parameter("display_reconstruction",
			render_subdivision > 1)
	if prototype_foam_splats:
		var splats := MeshInstance3D.new()
		splats.name = "PrototypeFoamSplats"
		splats.mesh = _make_foam_splat_mesh()
		splats.custom_aabb = AABB(Vector3(-16.5, -2.0, -16.5),
			Vector3(33.0, 6.0, 33.0))
		var splat_material := ShaderMaterial.new()
		splat_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_foam_splats.gdshader")
		splat_material.render_priority = 1
		splat_material.set_shader_parameter("rock_state", rock_texture)
		splat_material.set_shader_parameter("sand_state", sand_texture)
		splat_material.set_shader_parameter("water_state", water_texture)
		splat_material.set_shader_parameter("foam_state", foam_texture)
		splat_material.set_shader_parameter("display_reconstruction",
			render_subdivision > 1)
		splat_material.set_shader_parameter("splat_jitter_m",
			0.10 if prototype_foam_splats_jitter else 0.0)
		splat_material.set_shader_parameter("splat_half_width_m",
			0.018 if prototype_foam_splats_fine else 0.055)
		splats.material_override = splat_material
		add_child(splats)
	if prototype_foam_front_splats:
		var front_splats := MeshInstance3D.new()
		front_splats.name = "PrototypeFrontFoamSplats"
		front_splats.mesh = _make_foam_splat_mesh(true)
		front_splats.custom_aabb = AABB(Vector3(-16.5, -2.0, -16.5),
			Vector3(33.0, 6.0, 33.0))
		var front_material := ShaderMaterial.new()
		front_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_foam_splats.gdshader")
		front_material.render_priority = 2
		front_material.set_shader_parameter("rock_state", rock_texture)
		front_material.set_shader_parameter("sand_state", sand_texture)
		front_material.set_shader_parameter("water_state", water_texture)
		front_material.set_shader_parameter("foam_state", foam_texture)
		front_material.set_shader_parameter("rise_front_state", rise_front_texture)
		if prototype_foam_front_raised:
			front_material.set_shader_parameter("local_front_state", local_front_texture)
			front_material.set_shader_parameter("raised_local_front", true)
			front_material.set_shader_parameter("crest_height_m",
				prototype_foam_surface_lift_m)
		front_material.set_shader_parameter("display_reconstruction",
			render_subdivision > 1)
		front_material.set_shader_parameter("front_concentrated", true)
		front_material.set_shader_parameter("front_smooth_support",
			prototype_foam_front_smooth)
		front_material.set_shader_parameter("splat_jitter_m", 0.025)
		front_material.set_shader_parameter("splat_half_width_m",
			0.018 if prototype_foam_splats_fine else 0.055)
		if prototype_foam_front_pixel_sized:
			front_material.set_shader_parameter("target_diameter_px", 3.5)
		front_splats.material_override = front_material
		add_child(front_splats)
	if prototype_foam_front_local_dense:
		var dense_splats := $PrototypeFrontFoamDense as MeshInstance3D
		dense_splats.visible = true
		var dense_material := dense_splats.material_override as ShaderMaterial
		dense_material.set_shader_parameter("rock_state", rock_texture)
		dense_material.set_shader_parameter("sand_state", sand_texture)
		dense_material.set_shader_parameter("water_state", water_texture)
		dense_material.set_shader_parameter("foam_state", foam_texture)
		dense_material.set_shader_parameter("local_front_state", local_front_texture)
		dense_material.set_shader_parameter("display_reconstruction",
			render_subdivision > 1)
		dense_material.set_shader_parameter("crest_height_m",
			prototype_foam_surface_lift_m)
		dense_material.set_shader_parameter("target_diameter_px",
			prototype_foam_front_local_diameter_px)
	if prototype_crest_curtain:
		var curtain := MeshInstance3D.new()
		curtain.name = "PrototypeCrestCurtain"
		curtain.mesh = _make_crest_curtain_mesh()
		var curtain_material := ShaderMaterial.new()
		curtain_material.shader = load("res://tests/visual_water_alignment/prototypes/reference_crest_curtain.gdshader")
		curtain_material.render_priority = 1
		curtain_material.set_shader_parameter("rock_state", rock_texture)
		curtain_material.set_shader_parameter("sand_state", sand_texture)
		curtain_material.set_shader_parameter("water_state", water_texture)
		curtain_material.set_shader_parameter("foam_state", foam_texture)
		curtain.material_override = curtain_material
		add_child(curtain)
	if prototype_crest_ribbon or prototype_crest_ribbon_attached or prototype_crest_rise_ribbon:
		var ribbon := MeshInstance3D.new()
		ribbon.name = "PrototypeCrestRibbon"
		ribbon.mesh = _make_crest_ribbon_mesh()
		ribbon.custom_aabb = AABB(Vector3(-16.5, -2.0, -16.5),
			Vector3(33.0, 6.0, 33.0))
		var ribbon_material := ShaderMaterial.new()
		if prototype_crest_rise_ribbon:
			ribbon_material.shader = load(
				"res://tests/visual_water_alignment/prototypes/reference_crest_forward_toe.gdshader" if prototype_crest_forward_toe else
				"res://tests/visual_water_alignment/prototypes/reference_crest_smoothed_lip.gdshader" if prototype_crest_smoothed_lip else
				"res://tests/visual_water_alignment/prototypes/reference_crest_shared_front_lip.gdshader" if prototype_crest_shared_profile else
				("res://tests/visual_water_alignment/prototypes/reference_crest_rise_ribbon_depthwrite.gdshader" if prototype_crest_ribbon_depth_write else
				"res://tests/visual_water_alignment/prototypes/reference_crest_rise_ribbon.gdshader"))
		else:
			ribbon_material.shader = load("res://tests/visual_water_alignment/prototypes/reference_crest_ribbon.gdshader")
		ribbon_material.render_priority = 1
		ribbon_material.set_shader_parameter("rock_state", rock_texture)
		ribbon_material.set_shader_parameter("sand_state", sand_texture)
		ribbon_material.set_shader_parameter("water_state", water_texture)
		ribbon_material.set_shader_parameter("foam_state", foam_texture)
		if prototype_crest_rise_ribbon:
			ribbon_material.set_shader_parameter("foam_previous_state", previous_foam_texture)
			if prototype_rise_front_field:
				ribbon_material.set_shader_parameter("rise_front_state", rise_front_texture)
				ribbon_material.set_shader_parameter("prototype_use_front_field", true)
		ribbon_material.set_shader_parameter("prototype_full_body",
			prototype_crest_ribbon_body)
		ribbon_material.set_shader_parameter("prototype_attached_body",
			prototype_crest_ribbon_attached or prototype_crest_rise_ribbon)
		ribbon_material.set_shader_parameter("prototype_attached_smooth_mask",
			prototype_crest_ribbon_smooth_mask)
		if prototype_crest_solid_lip:
			ribbon_material.set_shader_parameter("prototype_solid_lip", true)
			ribbon_material.set_shader_parameter("prototype_water_body",
				prototype_crest_water_body)
			ribbon_material.set_shader_parameter("prototype_main_rise",
				prototype_rise_crest)
			ribbon_material.set_shader_parameter("prototype_row_window",
				prototype_crest_row_window)
		ribbon.material_override = ribbon_material
		add_child(ribbon)
	if fixture_id in [WaterFixture.FIXTURE_ID, &"reference_sand_unused",
			SandFixture.COUPLED_FIXTURE_ID]:
		water_material.set_shader_parameter("phase2_optics", true)
		# sand_v1 starts dry and does not allocate foam history. If a tool or test
		# introduces water, it still uses the frozen phase-2 colour profile without
		# sampling an unavailable foam texture.
		water_material.set_shader_parameter("phase2_foam",
			enable_phase2_foam and fixture_id != &"reference_sand_unused")
		water_material.set_shader_parameter("water_surface_bias_m", 0.003)
		water_material.set_shader_parameter("display_reconstruction", render_subdivision > 1)
	_set_debug_view(0)
	_update_status()


func _make_grid_mesh(subdivision: int = 1) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half := float(GRID_SIZE) * CELL_SIZE_M * 0.5
	var display_size := GRID_SIZE * clampi(subdivision, 1, 4)
	var display_cell_m := CELL_SIZE_M / float(clampi(subdivision, 1, 4))
	for z in display_size:
		for x in display_size:
			vertices.append(Vector3((float(x) + 0.5) * display_cell_m - half,
				0.0, (float(z) + 0.5) * display_cell_m - half))
			uvs.append(Vector2((float(x) + 0.5) / float(display_size),
				(float(z) + 0.5) / float(display_size)))
	for z in display_size - 1:
		for x in display_size - 1:
			var i := z * display_size + x
			indices.append_array(PackedInt32Array([i, i + display_size + 1, i + 1,
				i, i + display_size, i + display_size + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _make_crest_volume_mesh() -> ArrayMesh:
	# One closed X/Y ring per coastline row, joined in Z. UV.x is the ring
	# angle; the shader positions each row from the completed front field.
	const SIDES := 24
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in GRID_SIZE:
		var world_z := (float(z) + 0.5) * CELL_SIZE_M - 16.0
		for side in SIDES + 1:
			vertices.append(Vector3(0.0, 0.0, world_z))
			uvs.append(Vector2(float(side) / float(SIDES),
				(float(z) + 0.5) / float(GRID_SIZE)))
	for z in GRID_SIZE - 1:
		for side in SIDES:
			var i := z * (SIDES + 1) + side
			indices.append_array(PackedInt32Array([
				i, i + SIDES + 1, i + 1,
				i + 1, i + SIDES + 1, i + SIDES + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _make_local_front_segment_mesh() -> ArrayMesh:
	# Independent short spans let separate wet branches produce separate lips.
	# Candidate spacing is four cells; the shader selects the one nearest the
	# local 2D ridge and collapses/discards every other span.
	const LAYERS := 9
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var selector_uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in GRID_SIZE - 1:
		for candidate in range(96, 249, 4):
			var base := vertices.size()
			var candidate_uv := (float(candidate) + 0.5) / float(GRID_SIZE)
			var middle_uv := (float(z) + 1.0) / float(GRID_SIZE)
			for endpoint in 2:
				var row := z + endpoint
				var row_uv := (float(row) + 0.5) / float(GRID_SIZE)
				var world_z := (float(row) + 0.5) * CELL_SIZE_M - 16.0
				for layer in LAYERS:
					vertices.append(Vector3(0.0, 0.0, world_z))
					uvs.append(Vector2(float(layer) / float(LAYERS - 1),
						row_uv))
					selector_uvs.append(Vector2(candidate_uv, middle_uv))
			for layer in LAYERS - 1:
				var a := base + layer
				var b := base + LAYERS + layer
				indices.append_array(PackedInt32Array([a, b, a + 1,
					a + 1, b, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = selector_uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _make_foam_splat_mesh(front_concentrated: bool = false) -> ArrayMesh:
	# 128 x 256 independent horizontal quads, one per two simulation cells.
	# The shader samples current eta and history; no CPU field readback or TIME.
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var corners := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in GRID_SIZE:
		for x in (32 if front_concentrated else int(GRID_SIZE / 2)):
			var center_x := 0.0 if front_concentrated else \
				(float(x * 2) + 1.0) * CELL_SIZE_M - 16.0
			var center_z := (float(z) + 0.5) * CELL_SIZE_M - 16.0
			var center_uv := Vector2((float(x) + 0.5) / 32.0 if \
				front_concentrated else (center_x + 16.0) / 32.0,
				(center_z + 16.0) / 32.0)
			var base := vertices.size()
			for corner in [Vector2(0.0, 0.0), Vector2(1.0, 0.0),
					Vector2(0.0, 1.0), Vector2(1.0, 1.0)]:
				vertices.append(Vector3(center_x, 0.0, center_z))
				uvs.append(center_uv)
				corners.append(corner)
			indices.append_array(PackedInt32Array([
				base, base + 2, base + 1,
				base + 1, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = corners
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _make_unified_curl_mesh() -> ArrayMesh:
	# One connected row runs from offshore water, through eleven curl points,
	# to shoreward water. UV2.x selects the region and UV2.y its local position.
	const SIDE_STEPS := 128
	var curl_steps := 40 if prototype_unified_smooth_profile else 10
	var rows := GRID_SIZE * (2 if prototype_unified_dense else 1)
	var columns := SIDE_STEPS + curl_steps + 1 + SIDE_STEPS
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var region_uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var fallback_offsets := PackedFloat32Array([
		-0.70, -0.50, -0.25, 0.00, 0.25, 0.42,
		0.48, 0.43, 0.32, 0.33, 0.58])
	for z in rows:
		var world_z := (float(z) + 0.5) * 32.0 / float(rows) - 16.0
		var uv_z := (float(z) + 0.5) / float(rows)
		for col in columns:
			var region := 0.0
			var local_t := 0.0
			if col < SIDE_STEPS:
				local_t = float(col) / float(SIDE_STEPS)
			elif col <= SIDE_STEPS + curl_steps:
				region = 1.0
				local_t = float(col - SIDE_STEPS) / float(curl_steps)
			else:
				region = 2.0
				local_t = float(col - SIDE_STEPS - curl_steps) / float(SIDE_STEPS)
			var base_x := (float(col) / float(columns - 1)) * 32.0 - 16.0
			if prototype_unified_centered_base or prototype_unified_monotonic_base:
				if region == 0.0:
					base_x = lerpf(-15.9375, 3.30, local_t)
				elif region == 2.0:
					base_x = lerpf(4.58, 15.9375, local_t)
				elif prototype_unified_monotonic_base:
					base_x = lerpf(3.30, 4.58, local_t)
				else:
					var profile_index := local_t * 10.0
					var low := mini(int(floorf(profile_index)), 10)
					var high := mini(low + 1, 10)
					base_x = 4.0 + lerpf(fallback_offsets[low],
						fallback_offsets[high], profile_index - float(low))
			vertices.append(Vector3(base_x,
				0.0, world_z))
			uvs.append(Vector2(0.0, uv_z))
			region_uvs.append(Vector2(region, local_t))
	for z in rows - 1:
		for col in columns - 1:
			var i := z * columns + col
			indices.append_array(PackedInt32Array([i, i + columns + 1, i + 1,
				i, i + columns, i + columns + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = region_uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _make_crest_curtain_mesh() -> ArrayMesh:
	# W07 display-only geometry: one vertical quad per simulation cell. The
	# shader collapses/discards quads away from the advancing foam edge.
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cell_uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var half := float(GRID_SIZE) * CELL_SIZE_M * 0.5
	for z in GRID_SIZE:
		for x in GRID_SIZE:
			var index := vertices.size()
			var px := (float(x) + 0.5) * CELL_SIZE_M - half
			var z0 := float(z) * CELL_SIZE_M - half
			var z1 := float(z + 1) * CELL_SIZE_M - half
			var center_uv := Vector2((float(x) + 0.5) / float(GRID_SIZE),
				(float(z) + 0.5) / float(GRID_SIZE))
			for layer in 3:
				for edge in 2:
					vertices.append(Vector3(px, 0.0, z1 if edge == 1 else z0))
					uvs.append(Vector2(center_uv.x,
						float(z + edge) / float(GRID_SIZE)))
					cell_uvs.append(center_uv)
					colors.append(Color(float(layer) * 0.5, 0.0, 0.0))
			for layer in 2:
				var strip := index + layer * 2
				indices.append_array(PackedInt32Array([strip, strip + 1,
					strip + 3, strip, strip + 3, strip + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = cell_uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _make_crest_ribbon_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var layers := 11 if prototype_crest_solid_lip else 7
	for z in GRID_SIZE:
		var world_z := ((float(z) + 0.5) * CELL_SIZE_M -
			float(GRID_SIZE) * CELL_SIZE_M * 0.5)
		for layer in layers:
			vertices.append(Vector3(0.0, 0.0, world_z))
			uvs.append(Vector2(float(layer) / float(layers - 1),
				(float(z) + 0.5) / float(GRID_SIZE)))
	for z in GRID_SIZE - 1:
		for layer in layers - 1:
			var i := z * layers + layer
			indices.append_array(PackedInt32Array([i, i + layers, i + 1,
				i + 1, i + layers, i + layers + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _create_solver() -> SandcastleGpuShallowSolver:
	# Factory allows isolated validation backends without duplicating setup.
	if prototype_batched_ledger_bookkeeping:
		return FixedSubstepSolver.new() if prototype_fixed_substeps > 0 else BatchedLedgerSolver.new()
	return SyncGpuSolver.new() if prototype_sync_boundary_readback else GpuSolver.new()

func _create_foam_field() -> SandcastleGpuFoamField:
	return FoamField.new()


func _create_material_coupler() -> SandcastleGpuMaterialCoupler:
	return MaterialCoupler.new()

func _render_setup(domain: SandWaterDomain, token: int) -> void:
	if closing or token != generation:
		return
	if prototype_fixed_substeps > 0 and not prototype_batched_ledger_bookkeeping:
		call_deferred("_fail", "fixed substeps require batched ledger bookkeeping")
		return
	if prototype_batched_ledger_bookkeeping:
		if prototype_ledger_batch_ticks < 1 or prototype_sync_boundary_readback:
			call_deferred("_fail", "batched ledger mode requires batch capture")
			return
	solver = _create_solver()
	var initial_qx: PackedFloat32Array = replay_checkpoint.fields["momentum_x"] if \
			not replay_checkpoint.is_empty() else PackedFloat32Array()
	var initial_qz: PackedFloat32Array = replay_checkpoint.fields["momentum_z"] if \
			not replay_checkpoint.is_empty() else PackedFloat32Array()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7],
			initial_qx, initial_qz):
		call_deferred("_fail", "GPU shallow solver initialization failed")
		return
	if not replay_checkpoint.is_empty():
		solver.water_source_m3 = replay_checkpoint.water_source_m3
		solver.water_sink_m3 = replay_checkpoint.water_sink_m3
	if prototype_batched_ledger_bookkeeping:
		tide_ledger_settled_ticks = completed_ticks
	if prototype_ledger_ring_capacity > 0:
		tide_ledger_ring = TideLedgerRing.new()
		if not tide_ledger_ring.initialize(solver.rd, tide_ledger_ring_spirv,
				solver.current_texture("tide_delta"), GRID_SIZE,
				prototype_ledger_ring_capacity):
			call_deferred("_fail", "tide ledger ring initialization failed")
			return
	if prototype_ledger_batch_ticks > 0:
		tide_ledger_batches = TideLedgerBatches.new()
		if not tide_ledger_batches.initialize(solver.rd, tide_ledger_ring_spirv,
				solver.current_texture("tide_delta"), GRID_SIZE,
				prototype_ledger_batch_ticks, _on_tide_ledger_batch):
			call_deferred("_fail", "tide ledger batches initialization failed")
			return
	if fixture_id in [WaterFixture.FIXTURE_ID, SandFixture.COUPLED_FIXTURE_ID] and \
			enable_phase2_foam:
		foam_field = _create_foam_field()
		var initial_foam: PackedFloat32Array = replay_checkpoint.get("foam_history",
			PackedFloat32Array())
		var initial_bed := PackedFloat32Array()
		initial_bed.resize(GRID_SIZE * GRID_SIZE)
		for cell in initial_bed.size():
			initial_bed[cell] = shadow_domain.rock[cell] + shadow_domain.sand[cell]
		if not foam_field.initialize(solver, spirvs[17], initial_foam, initial_bed,
				prototype_front_band_foam_source):
			call_deferred("_fail", "GPU foam field initialization failed")
			return
	if prototype_rise_front_field:
		rise_front_field = RiseFrontField.new()
		if foam_field == null or not rise_front_field.initialize(solver, foam_field,
				rise_front_spirv, rise_front_anchor_spirv):
			call_deferred("_fail", "GPU rise front field initialization failed")
			return
	if prototype_local_front_field:
		local_front_field = LocalFrontField.new()
		var initial_front: PackedFloat32Array = replay_checkpoint.get(
			"local_front_history", PackedFloat32Array())
		if foam_field == null or not local_front_field.initialize(solver, foam_field,
				local_front_x_spirv, local_front_z_spirv, initial_front):
			call_deferred("_fail", "GPU local front field initialization failed")
			return
	if prototype_front_band_foam_source:
		if local_front_field == null or not foam_field.configure_uniforms(solver,
				local_front_field.texture):
			call_deferred("_fail", "GPU front-band foam uniforms failed")
			return
	if prototype_contact_history_field:
		contact_history_field = ContactHistoryField.new()
		if not contact_history_field.initialize(solver, foam_field,
				local_front_field, contact_history_spirv):
			call_deferred("_fail", "GPU contact history field initialization failed")
			return
	sand_audit = SandAudit.new()
	if not sand_audit.initialize(solver, spirvs[9]):
		call_deferred("_fail", "GPU sand audit initialization failed")
		return
	if enable_erosion:
		sediment_coupler = SedimentCoupler.new()
		if not sediment_coupler.initialize(solver, spirvs[10], spirvs[11]):
			call_deferred("_fail", "GPU sediment coupler initialization failed")
			return
		material_coupler = _create_material_coupler()
		material_coupler.cohesion_yield_height_m = sand_cohesion_yield_height_m
		if not material_coupler.initialize(solver, sediment_coupler.dirty_max_texture,
				spirvs[12], spirvs[13], spirvs[14]):
			call_deferred("_fail", "GPU material coupler initialization failed")
			return
	if enable_structures:
		obstacle_remap = ObstacleRemap.new()
		if not obstacle_remap.initialize(solver, spirvs[15], spirvs[16]):
			call_deferred("_fail", "GPU obstacle remap initialization failed")
			return
	if not collision_proxy.setup_render(solver, spirvs[8], token):
		call_deferred("_fail", "GPU collision proxy initialization failed")
		return
	if replay_target_tick < 0:
		_request_full_collision_render(token)
	_publish_textures()
	call_deferred("_mark_ready", token)


func _publish_textures() -> void:
	rock_texture.texture_rd_rid = solver.current_texture("rock")
	sand_texture.texture_rd_rid = solver.current_texture("sand")
	wetness_texture.texture_rd_rid = solver.current_texture("wetness")
	compaction_texture.texture_rd_rid = solver.current_texture("compaction")
	water_texture.texture_rd_rid = solver.current_texture("water")
	momentum_x_texture.texture_rd_rid = solver.current_texture("momentum_x")
	momentum_z_texture.texture_rd_rid = solver.current_texture("momentum_z")
	sediment_texture.texture_rd_rid = solver.current_texture("sediment")
	obstacle_texture.texture_rd_rid = solver.current_texture("obstacle")
	flux_texture.texture_rd_rid = solver.current_texture("flux")
	if foam_field != null:
		foam_texture.texture_rd_rid = foam_field.current_texture()
		if prototype_crest_rise_ribbon or prototype_rise_crest:
			previous_foam_texture.texture_rd_rid = foam_field.textures[1 - foam_field.current_index]
	if rise_front_field != null:
		rise_front_texture.texture_rd_rid = rise_front_field.final_texture()
	if local_front_field != null:
		local_front_texture.texture_rd_rid = local_front_field.texture
	if contact_history_field != null:
		contact_history_texture.texture_rd_rid = contact_history_field.current_texture()


func _mark_ready(token: int) -> void:
	if closing or token != generation:
		return
	shadow_revision = solver.state_revision
	shadow_sand_revision = solver.state_revision
	_update_front_face_source_gate()
	ready_for_ticks = true
	_update_status()


func _process(delta: float) -> void:
	if profile_main_frame_timing:
		profile_main_frame_rows.append(PackedInt64Array([
			Engine.get_process_frames(), Time.get_ticks_usec(), completed_ticks,
			int(tick_pending)]))
	if not ready_for_ticks or closing:
		return
	_update_structures()
	_update_brush_indicator()
	if debug_view >= 13 and (chunk_debug_dirty_revision != dirty_debug_revision or \
			chunk_debug_collision_batches != collision_proxy.completed_batches or \
			(debug_view == 14 and enable_erosion and not proxy_debug_shadow_stale and \
			shadow_revision != solver.state_revision)):
		_refresh_chunk_debug_texture()
	if debug_view == 14 and enable_erosion and not playing and not tick_pending and \
			shadow_revision != solver.state_revision and shadow_sync_reason.is_empty():
		_request_shadow_sync("debug")
	if checkpoint_capture_pending:
		return
	if auto_support_pending and not tick_pending and replay_target_tick < 0:
		playing = false
		auto_support_pending = false
		auto_support_event_active = true
		var admitted: Dictionary = request_sand_support_loss({
			"generation": generation,
			"request_id": support_loss_highwater_id + 1,
			"side_only": true})
		if not admitted.ok:
			auto_support_event_active = false
			_fail("automatic sand support event rejected: " + String(admitted.code))
		return
	if auto_support_event_active:
		return
	if replay_target_tick >= 0:
		if replay_ready or tick_pending:
			return
		if completed_ticks < replay_target_tick:
			_start_tick()
		elif not command_queue.pending.is_empty():
			_dispatch_paused_patch()
		else:
			_request_replay_collision()
			replay_ready = true
		return
	if playing:
		accumulator = minf(accumulator + delta, SIM_DELTA * 4.0)
	if not playing or tick_pending:
		return
	if accumulator < SIM_DELTA:
		return
	accumulator -= SIM_DELTA
	_start_tick()


func _start_tick() -> void:
	if enable_erosion and not command_queue.pending.is_empty() and \
			shadow_sand_revision != solver.state_revision:
		if sand_prefetch_in_flight and sand_prefetch_revision == solver.state_revision:
			return
		_request_shadow_sync("start_tick")
		return
	if profile_tick_timing:
		profile_tick_start_us = Time.get_ticks_usec()
		profile_ledger_us = 0
		profile_cfl_us = 0
		profile_both_us = 0
		profile_render_begin_us = 0
		profile_render_submit_us = 0
		profile_ledger_render_us = 0
		profile_cfl_render_us = 0
		profile_render_finish_us = 0
		profile_render_finish_submit_us = 0
	tick_pending = true
	water_tick_in_flight = true
	tide_ready = false
	cfl_ready = false
	finish_dispatched = false
	var patch: Dictionary = _apply_due_tool_commands()
	var level: float = Scenarios.tide_level(float(completed_ticks) * SIM_DELTA)
	var wave_height_m := _wave_height_at_tick(completed_ticks + 1)
	RenderingServer.call_on_render_thread(_render_begin_tick.bind(level + wave_height_m,
		wave_height_m,
		patch.data, patch.count, patch.chunks, patch.command_ids, generation))


func _request_shadow_sync(reason: String) -> void:
	if closing or not enable_erosion or not shadow_sync_reason.is_empty():
		return
	var full := reason not in ["start_tick", "paused_patch"]
	if (shadow_revision if full else shadow_sand_revision) == solver.state_revision:
		_resume_shadow_sync(reason)
		return
	shadow_sync_reason = reason
	shadow_sync_full = full
	shadow_sync_fields.clear()
	tick_pending = true
	water_tick_in_flight = false
	RenderingServer.call_on_render_thread(_render_shadow_sync.bind(
		solver.state_revision, generation, full))


func _render_shadow_sync(revision: int, token: int, full: bool) -> void:
	if closing or token != generation or solver.state_revision != revision:
		return
	## wetness and compaction are material-state fields the T05 passes evolve on
	## the GPU only. A checkpoint that captured a stale CPU copy would restart
	## from the wrong moisture, so a full sync carries them too.
	for field in (["sand", "sediment", "wetness", "compaction"] if full else ["sand"]):
		var error: Error = solver.request_data(field,
			_on_shadow_field.bind(field, revision, token))
		if error != OK:
			call_deferred("_fail", "shadow sync readback failed: %s %d" % [field, error])
			return


func _on_shadow_field(data: PackedByteArray, field: String,
		revision: int, token: int) -> void:
	call_deferred("_shadow_field_ready", data, field, revision, token)


func _shadow_field_ready(data: PackedByteArray, field: String,
		revision: int, token: int) -> void:
	if closing or token != generation or shadow_sync_reason.is_empty() or \
			solver.state_revision != revision:
		return
	var values := PackedFloat32Array()
	if data.size() == GRID_SIZE * GRID_SIZE * 4:
		values = data.to_float32_array()
	elif data.size() == GRID_SIZE * GRID_SIZE * 2:
		## wetness and compaction are R16F.
		values.resize(GRID_SIZE * GRID_SIZE)
		for i in GRID_SIZE * GRID_SIZE:
			values[i] = data.decode_half(i * 2)
	else:
		_fail("shadow sync size mismatch: " + field)
		return
	for value in values:
		if not is_finite(value) or value < -0.000001:
			_fail("shadow sync nonfinite/negative: " + field)
			return
		if field in ["wetness", "compaction"] and value > 1.000001:
			_fail("shadow sync out of range: " + field)
			return
	shadow_sync_fields[field] = values
	if shadow_sync_fields.size() < (4 if shadow_sync_full else 1):
		return
	shadow_domain.sand = shadow_sync_fields["sand"]
	shadow_sand_revision = revision
	if shadow_sync_full:
		shadow_domain.sediment = shadow_sync_fields["sediment"]
		shadow_domain.wetness = shadow_sync_fields["wetness"]
		shadow_domain.compaction = shadow_sync_fields["compaction"]
		shadow_revision = revision
		full_shadow_syncs += 1
		full_shadow_bytes += GRID_SIZE * GRID_SIZE * (8 + 4)
	else:
		sand_only_syncs += 1
		sand_only_bytes += GRID_SIZE * GRID_SIZE * 4
	shadow_sync_fields.clear()
	var reason := shadow_sync_reason
	shadow_sync_reason = ""
	shadow_sync_full = false
	tick_pending = false
	_resume_shadow_sync(reason)


func _resume_shadow_sync(reason: String) -> void:
	match reason:
		"start_tick":
			if not playing and replay_target_tick < 0:
				_dispatch_paused_patch()
			else:
				_start_tick()
		"paused_patch":
			_dispatch_paused_patch()
		"checkpoint":
			_start_checkpoint_capture()
		"replay_complete":
			_complete_replay_target()
		"debug":
			if debug_view == 14:
				_refresh_chunk_debug_texture()
			_update_status()


func _render_begin_tick(level_m: float, wave_height_m: float,
		patch_data: PackedByteArray,
		patch_count: int, chunks: PackedInt32Array,
		command_ids: PackedInt32Array, token: int) -> void:
	if closing or token != generation:
		return
	if prototype_worker_handoff:
		worker_ledger_seen = false
		worker_cfl_seen = false
		worker_finish_dispatched = false
	if profile_tick_timing:
		profile_render_begin_us = Time.get_ticks_usec()
	if patch_count > 0 and not solver.dispatch_tool_patch(patch_data, patch_count):
		call_deferred("_fail", "tool patch batch dispatch failed")
		return
	if patch_count > 0:
		call_deferred("_record_tool_revisions", command_ids,
			chunks, solver.state_revision, token)
	if not solver.dispatch_wave_boundary(level_m, wave_height_m):
		call_deferred("_fail", "tide boundary dispatch failed")
		return
	if enable_erosion and not sediment_coupler.dispatch_after_boundary():
		call_deferred("_fail", "sediment boundary carry failed")
		return
	if tide_ledger_ring != null and not tide_ledger_ring.dispatch():
		call_deferred("_fail", "tide ledger ring dispatch failed")
		return
	if tide_ledger_batches != null and not tide_ledger_batches.dispatch():
		call_deferred("_fail", "tide ledger batches dispatch failed")
		return
	if prototype_batched_ledger_bookkeeping:
		if not solver.call("acknowledge_tide_ledger_capture"):
			call_deferred("_fail", "batched tide ledger capture acknowledgement failed")
			return
		call_deferred("_ledger_ready", true, token)
	else:
		var error := solver.request_tide_ledger(_on_ledger.bind(token))
		if error != OK:
			call_deferred("_fail", "tide ledger request failed: %d" % error)
			return
	if prototype_fixed_substeps > 0:
		if prototype_fixed_cfl_audit:
			var audit_error := solver.request_cfl_tiles(
				_on_fixed_cfl_audit.bind(token))
			if audit_error != OK:
				call_deferred("_fail", "fixed CFL audit request failed: %d" % audit_error)
				return
		call_deferred("_fixed_cfl_ready", solver.state_revision, token)
	else:
		# The ledger and CFL reductions read separate outputs of the same boundary
		# state. Submit both before waiting, avoiding a second CPU/GPU round trip.
		var cfl_error := solver.request_cfl_tiles(_on_cfl.bind(token))
		if cfl_error != OK:
			call_deferred("_fail", "CFL tile request failed: %d" % cfl_error)
			return
	if profile_tick_timing:
		profile_render_submit_us = Time.get_ticks_usec()


func _on_ledger(_source: float, _sink: float, _revision: int,
		valid: bool, token: int) -> void:
	if (tide_ledger_ring != null or tide_ledger_batches != null) and valid:
		tide_ledger_cpu_pairs.append({"source_m3": _source,
			"sink_m3": _sink, "revision": _revision})
	if profile_tick_timing:
		profile_ledger_render_us = Time.get_ticks_usec()
	if prototype_worker_handoff:
		worker_ledger_seen = true
		worker_ledger_valid = valid
		_maybe_worker_finish_tick(token)
		return
	call_deferred("_ledger_ready", valid, token)


func _on_tide_ledger_batch(index: int, count: int,
		data: PackedByteArray) -> void:
	if prototype_batched_ledger_bookkeeping:
		tide_ledger_pending_batches[index] = {"count": count, "data": data}
		while tide_ledger_pending_batches.has(tide_ledger_next_batch):
			var batch: Dictionary = tide_ledger_pending_batches[tide_ledger_next_batch]
			if not _settle_tide_ledger_batch(batch.count, batch.data):
				call_deferred("_fail", "batched tide ledger data invalid")
				return
			tide_ledger_pending_batches.erase(tide_ledger_next_batch)
			tide_ledger_next_batch += 1
	call_deferred("_record_tide_ledger_batch", index, count, data)


func _settle_tide_ledger_batch(count: int, data: PackedByteArray) -> bool:
	if count < 1 or count > prototype_ledger_batch_ticks or \
			data.size() != prototype_ledger_batch_ticks * GRID_SIZE * 4:
		return false
	var values := data.to_float32_array()
	for tick_index in count:
		var source_m3 := 0.0
		var sink_m3 := 0.0
		for z in GRID_SIZE:
			var delta_m3: float = values[tick_index * GRID_SIZE + z]
			if not is_finite(delta_m3):
				return false
			if delta_m3 >= 0.0:
				source_m3 += delta_m3
			else:
				sink_m3 -= delta_m3
		solver.water_source_m3 += source_m3
		solver.water_sink_m3 += sink_m3
		tide_ledger_settled_ticks += 1
	return true


func _record_tide_ledger_batch(index: int, count: int,
		data: PackedByteArray) -> void:
	if closing:
		return
	tide_ledger_batch_results.append({"index": index,
		"count": count, "data": data})
	if tide_ledger_checkpoint_waiting and \
			tide_ledger_settled_ticks == completed_ticks:
		tide_ledger_checkpoint_waiting = false
		checkpoint_capture_pending = false
		_start_checkpoint_capture()


func _ledger_ready(valid: bool, token: int) -> void:
	if closing or token != generation:
		return
	if not valid:
		_fail("tide ledger contained invalid data")
		return
	tide_ready = true
	if profile_tick_timing:
		profile_ledger_us = Time.get_ticks_usec()
	_maybe_finish_tick(token)


func _on_cfl(data: PackedByteArray, revision: int, token: int) -> void:
	if profile_tick_timing:
		profile_cfl_render_us = Time.get_ticks_usec()
	if prototype_worker_handoff:
		worker_cfl_seen = true
		worker_cfl_bytes = data
		worker_cfl_revision = revision
		worker_cfl_substeps = solver.substeps_from_cfl(SIM_DELTA, data)
		_maybe_worker_finish_tick(token)
		return
	call_deferred("_cfl_ready", data, revision, token)


func _fixed_cfl_ready(revision: int, token: int) -> void:
	if closing or token != generation:
		return
	cfl_data = PackedByteArray()
	cfl_revision = revision
	cfl_substeps = prototype_fixed_substeps
	cfl_ready = true
	if profile_tick_timing:
		profile_cfl_us = Time.get_ticks_usec()
	_maybe_finish_tick(token)


func _on_fixed_cfl_audit(data: PackedByteArray, _revision: int,
		token: int) -> void:
	if closing or token != generation:
		return
	var required := solver.substeps_from_cfl(SIM_DELTA, data)
	if required < 1 or required > solver.MAX_SUBSTEPS:
		call_deferred("_fail", "fixed CFL audit invalid")
		return
	fixed_cfl_audit_count += 1
	fixed_cfl_max_required = maxi(fixed_cfl_max_required, required)
	if required > prototype_fixed_substeps:
		fixed_cfl_over_bound += 1
		call_deferred("_fail", "fixed CFL bound exceeded: %d > %d" % [
			required, prototype_fixed_substeps])


func _maybe_worker_finish_tick(token: int) -> void:
	if closing or token != generation or not worker_ledger_seen or \
			not worker_cfl_seen or worker_finish_dispatched:
		return
	worker_finish_dispatched = true
	if not worker_ledger_valid or worker_cfl_substeps < 1 or \
			worker_cfl_substeps > solver.MAX_SUBSTEPS:
		call_deferred("_fail", "worker handoff boundary/CFL data invalid")
		return
	worker_task_id = WorkerThreadPool.add_task(
		_worker_schedule_finish.bind(worker_cfl_bytes, worker_cfl_revision,
			worker_cfl_substeps, token), true, "W07 boundary handoff")


func _worker_schedule_finish(data: PackedByteArray, revision: int,
		substeps: int, token: int) -> void:
	RenderingServer.call_on_render_thread(_render_finish_tick.bind(
		data, revision, substeps, token))


func _cfl_ready(data: PackedByteArray, revision: int, token: int) -> void:
	if closing or token != generation:
		return
	var substeps := solver.substeps_from_cfl(SIM_DELTA, data)
	if substeps < 1 or substeps > solver.MAX_SUBSTEPS:
		_fail("CFL substep request invalid: %d" % substeps)
		return
	cfl_data = data
	cfl_revision = revision
	cfl_substeps = substeps
	cfl_ready = true
	if profile_tick_timing:
		profile_cfl_us = Time.get_ticks_usec()
	_maybe_finish_tick(token)


func _maybe_finish_tick(token: int) -> void:
	if not tick_pending or not tide_ready or not cfl_ready or finish_dispatched:
		return
	if profile_tick_timing:
		profile_both_us = Time.get_ticks_usec()
	finish_dispatched = true
	RenderingServer.call_on_render_thread(_render_finish_tick.bind(
		cfl_data, cfl_revision, cfl_substeps, token))


## Coupled passes for one water substep, in the order the data contract fixes:
## suspended-sand transport plus erosion/deposition first, then the T05
## wetness/compaction evolution and the conservative slope relaxation on the
## sand that erosion just wrote.
func _dispatch_coupled_substep(delta_s: float) -> bool:
	if not sediment_coupler.dispatch_after_water_substep(delta_s):
		return false
	return material_coupler.dispatch_after_erosion(delta_s)


func _render_finish_tick(data: PackedByteArray, revision: int,
		substeps: int, token: int) -> void:
	if closing or token != generation:
		return
	if profile_tick_timing:
		profile_render_finish_us = Time.get_ticks_usec()
	var post_substep := _dispatch_coupled_substep if enable_erosion else Callable()
	## Skipping the reset while a summary is in flight is safe: the texture is an
	## atomic max, so the pending readback then carries the worst of both ticks.
	## Either way this tick is now covered by an outstanding summary.
	if enable_erosion:
		sediment_coupler.clear_dirty_max()
		dirty_ticks_covered += 1
	var step_ok: bool = solver.call("dispatch_tick_fixed", SIM_DELTA,
		substeps, revision, post_substep) if prototype_fixed_substeps > 0 else \
		solver.dispatch_tick_with_cfl(SIM_DELTA, data, revision, post_substep)
	if not step_ok:
		call_deferred("_fail", "GPU shallow tick failed")
		return
	if prototype_front_band_foam_source and (local_front_field == null or
			not local_front_field.dispatch(solver, foam_field, true)):
		call_deferred("_fail", "GPU pre-foam local front tick failed")
		return
	if foam_field != null and not foam_field.dispatch(solver, SIM_DELTA):
		call_deferred("_fail", "GPU foam tick failed")
		return
	if rise_front_field != null and not rise_front_field.dispatch(solver, foam_field):
		call_deferred("_fail", "GPU rise front tick failed")
		return
	if local_front_field != null and not prototype_front_band_foam_source and \
			not local_front_field.dispatch(solver, foam_field):
		call_deferred("_fail", "GPU local front tick failed")
		return
	if contact_history_field != null and not contact_history_field.dispatch(solver,
			foam_field, SIM_DELTA):
		call_deferred("_fail", "GPU contact history tick failed")
		return
	if completed_ticks == 0 or (completed_ticks + 1) % 30 == 0:
		var audit_error := solver.request_audit_tiles(_on_debug_audit.bind(token))
		if audit_error != OK:
			call_deferred("_fail", "debug audit request failed: %d" % audit_error)
			return
		_request_sand_audit_render(token)
	_publish_textures()
	if enable_erosion:
		if ((last_tool_submit_usec >= 0 and \
				Time.get_ticks_usec() - last_tool_submit_usec < 500000) or \
				(prefetch_sand_on_hover and last_sand_hover_usec >= 0 and \
				Time.get_ticks_usec() - last_sand_hover_usec < 500000)) and \
				not sand_prefetch_in_flight:
			sand_prefetch_revision = solver.state_revision
			sand_prefetch_in_flight = true
			var prefetch_error: Error = solver.request_data("sand",
				_on_sand_prefetch.bind(sand_prefetch_revision, token))
			if prefetch_error != OK:
				call_deferred("_fail", "sand prefetch failed: %d" % prefetch_error)
				return
		var dirty_error := sediment_coupler.request_dirty_max(_on_dirty_max.bind(
			substeps, solver.water_source_m3, solver.water_sink_m3, token))
		if dirty_error != OK and dirty_error != ERR_UNAVAILABLE:
			call_deferred("_fail", "sediment dirty-max readback failed: %d" % dirty_error)
			return
		if dirty_error == ERR_UNAVAILABLE:
			## A summary is already in flight; the tick does not wait for it.
			dirty_summaries_missed += 1
		if false and fixture_id == SandFixture.COUPLED_FIXTURE_ID and \
				support_loss_events.is_empty() and not auto_support_sensor_in_flight and \
				(completed_ticks + 1) % 30 == 0:
			auto_support_sensor_in_flight = true
			var sensor_error := solver.request_data("sand",
				_on_auto_support_sand.bind(solver.state_revision, token))
			if sensor_error != OK:
				auto_support_sensor_in_flight = false
				call_deferred("_fail", "support toe sensor readback failed: %d" % sensor_error)
				return
	if profile_tick_timing:
		profile_render_finish_submit_us = Time.get_ticks_usec()
	call_deferred("_tick_finished", substeps, solver.water_source_m3,
		solver.water_sink_m3, token)


func _on_sand_prefetch(data: PackedByteArray, revision: int, token: int) -> void:
	call_deferred("_record_sand_prefetch", data, revision, token)


func _on_auto_support_sand(data: PackedByteArray, revision: int, token: int) -> void:
	call_deferred("_record_auto_support_sand", data, revision, token)


func _record_auto_support_sand(data: PackedByteArray, revision: int,
		token: int) -> void:
	auto_support_sensor_in_flight = false
	if closing or token != generation or fixture_id != SandFixture.COUPLED_FIXTURE_ID or \
			not support_loss_events.is_empty() or auto_support_pending or \
			auto_support_event_active:
		return
	if data.size() != GRID_SIZE * GRID_SIZE * 4:
		_fail("support toe sensor size mismatch")
		return
	var values := data.to_float32_array()
	var toe_mass := 0.0
	for z in range(SandFixture.CENTER_Z - SandFixture.BASE_RADIUS_CELLS,
			SandFixture.CENTER_Z + SandFixture.BASE_RADIUS_CELLS + 1):
		for x in range(SandFixture.PACKED_CENTER_X - 11,
				SandFixture.PACKED_CENTER_X - 8):
			toe_mass += values[z * GRID_SIZE + x] * CELL_SIZE_M * CELL_SIZE_M
	auto_support_toe_latest_m3 = toe_mass
	if auto_support_toe_initial_m3 - toe_mass >= 0.015:
		auto_support_trigger_revision = revision
		auto_support_pending = true


func _record_sand_prefetch(data: PackedByteArray, revision: int, token: int) -> void:
	if closing or token != generation:
		return
	if sand_prefetch_revision == revision:
		sand_prefetch_in_flight = false
	if data.size() != GRID_SIZE * GRID_SIZE * 4:
		_fail("sand prefetch size mismatch")
		return
	if revision != solver.state_revision or not shadow_sync_reason.is_empty():
		return
	var values := data.to_float32_array()
	for value in values:
		if not is_finite(value) or value < -0.000001:
			_fail("sand prefetch invalid value")
			return
	shadow_domain.sand = values
	shadow_sand_revision = revision
	sand_prefetch_hits += 1
	sand_prefetch_bytes += data.size()
	if not tick_pending and not command_queue.pending.is_empty():
		_dispatch_paused_patch()


func _on_dirty_max(data: PackedByteArray, revision: int,
		substeps: int, source_m3: float, sink_m3: float, token: int) -> void:
	call_deferred("_record_dirty_max", data, revision,
		substeps, source_m3, sink_m3, token)


func _record_dirty_max(data: PackedByteArray, revision: int,
		substeps: int, source_m3: float, sink_m3: float, token: int) -> void:
	## Deliberately not guarded on `tick_pending` or on the revision matching: the
	## tick that produced this summary has already been allowed to finish, and the
	## bound it contributes is still valid even if later ticks have dispatched.
	if closing or token != generation or not enable_erosion:
		return
	var covered := maxi(dirty_ticks_covered, 1)
	dirty_ticks_covered = 0
	var dirty_result: Dictionary = sediment_coupler.decode_dirty_max(data)
	if not dirty_result.get("valid", false):
		_fail("coupled dirty-max data invalid")
		return
	var dirty_max_um: PackedInt32Array = dirty_result.max_delta_um
	dirty_summary_bytes += data.size()
	var this_tick_max_um := 0
	for chunk_id in 64:
		this_tick_max_um = maxi(this_tick_max_um, dirty_max_um[chunk_id])
	dirty_summaries_checked += 1
	max_gpu_dirty_um = maxi(max_gpu_dirty_um, this_tick_max_um)
	if this_tick_max_um > 0:
		nonzero_dirty_summary_ticks += 1
	var chunks := _erosion_collision_chunks(dirty_max_um, substeps * covered)
	if not chunks.is_empty():
		last_dirty_chunks = chunks.duplicate()
		dirty_debug_revision += 1
		RenderingServer.call_on_render_thread(_render_request_erosion_chunks.bind(
			chunks, revision, token))


func _erosion_collision_chunks(dirty_max_um: PackedInt32Array,
		substeps: int) -> PackedInt32Array:
	var selected := {}
	for chunk_id in 64:
		collision_change_upper_bound_m[chunk_id] += \
			float(dirty_max_um[chunk_id] * substeps) / 1000000.0
		if collision_change_upper_bound_m[chunk_id] < 0.001:
			continue
		var cx: int = chunk_id % 8
		var cz: int = chunk_id / 8
		selected[chunk_id] = true
		if cx > 0:
			selected[chunk_id - 1] = true
		if cz > 0:
			selected[chunk_id - 8] = true
		if cx > 0 and cz > 0:
			selected[chunk_id - 9] = true
	last_dirty_cells = 0
	var keys: Array = selected.keys()
	keys.sort()
	for chunk_id in keys:
		collision_change_upper_bound_m[chunk_id] = 0.0
	return PackedInt32Array(keys)


func _render_request_erosion_chunks(chunks: PackedInt32Array,
		revision: int, token: int) -> void:
	if closing or token != generation:
		return
	if not collision_proxy.request_chunks_render(chunks, revision, token):
		call_deferred("_fail", "erosion collision chunk request failed")


func _tick_finished(substeps: int, source_m3: float, sink_m3: float,
		token: int) -> void:
	if closing or token != generation:
		return
	if prototype_worker_handoff and worker_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(worker_task_id)
		worker_task_id = -1
	if profile_tick_timing:
		profile_tick_rows.append(PackedInt64Array([completed_ticks + 1,
			profile_tick_start_us, profile_ledger_us, profile_cfl_us,
			profile_both_us, Time.get_ticks_usec(), substeps,
			profile_render_begin_us, profile_render_submit_us,
			profile_ledger_render_us, profile_cfl_render_us,
			profile_render_finish_us, profile_render_finish_submit_us]))
	if capture_substep_trace:
		capture_substep_rows.append(Vector3i(completed_ticks + 1, substeps,
			solver.state_revision))
	completed_ticks += 1
	shadow_domain.sim_tick = completed_ticks
	_update_front_face_source_gate()
	last_substeps = substeps
	last_source_m3 = source_m3
	last_sink_m3 = sink_m3
	tick_pending = false
	water_tick_in_flight = false
	_update_status()
	if replay_target_tick < 0 and checkpoint_interval_ticks > 0 and \
			completed_ticks % checkpoint_interval_ticks == 0 and \
			command_queue.pending.is_empty() and \
			(last_tool_submit_usec < 0 or \
			Time.get_ticks_usec() - last_tool_submit_usec >= 500000):
		_start_checkpoint_capture()
	if replay_target_tick >= 0 and completed_ticks >= replay_target_tick:
		playing = false
		if enable_erosion and shadow_revision != solver.state_revision:
			_request_shadow_sync("replay_complete")
		else:
			_complete_replay_target()
		return
	if not checkpoint_capture_pending and not command_queue.pending.is_empty():
		_dispatch_paused_patch()


func _update_front_face_source_gate() -> void:
	if (not prototype_front_face_source_gate and
			not prototype_offshore_core_source_gate) or water_material == null:
		return
	var source_started := false
	for request in wave_requests:
		if int(request.generation) == generation and \
				int(request.start_tick) <= completed_ticks and \
				float(request.amplitude_m) > 0.0:
			source_started = true
			break
	if prototype_front_face_source_gate:
		water_material.set_shader_parameter("prototype_front_face_source_gate", true)
		water_material.set_shader_parameter("prototype_front_face_source_started",
			source_started)
	if prototype_offshore_core_source_gate:
		water_material.set_shader_parameter(
			"prototype_offshore_core_source_started", source_started)


func _complete_replay_target() -> void:
	if command_queue.pending.is_empty():
		_request_replay_collision()
		replay_ready = true
	else:
		_dispatch_paused_patch()


func _start_checkpoint_capture() -> void:
	if prototype_batched_ledger_bookkeeping and \
			tide_ledger_settled_ticks != completed_ticks:
		checkpoint_capture_pending = true
		tide_ledger_checkpoint_waiting = true
		RenderingServer.call_on_render_thread(_render_flush_ledger_for_checkpoint)
		return
	if enable_erosion and shadow_revision != solver.state_revision:
		checkpoint_capture_pending = true
		_request_shadow_sync("checkpoint")
		return
	# Stop tick dispatch until all three async reads refer to this exact GPU
	# revision. CPU shadow/history are frozen here before later commands apply.
	checkpoint_capture_pending = true
	var command_ids := PackedInt32Array()
	for command in command_queue.applied_log:
		command_ids.append(command["command_id"])
	checkpoint_capture = {"tick": completed_ticks,
		"preset_index": preset_index,
		"fixture_id": fixture_id,
		"sand_cohesion_yield_height_m": sand_cohesion_yield_height_m,
		"support_event_schema_version": 2 if fixture_id == \
			SandFixture.COUPLED_FIXTURE_ID else 1,
		"support_loss_events": support_loss_events.duplicate(true),
		"support_loss_highwater_id": support_loss_highwater_id,
		"shadow": shadow_domain.snapshot(),
		"command_ids": command_ids,
		"highwater_id": command_id,
		"water_source_m3": solver.water_source_m3,
		"water_sink_m3": solver.water_sink_m3,
		"foam_history_expected": foam_field != null,
		"local_front_history_expected": local_front_field != null,
		"wave_requests": wave_requests.duplicate(true),
		"wave_highwater_id": wave_highwater_id,
		"fields": {}, "revision": solver.state_revision,
		## T06: the heightfield cannot express support, so the topology and damage
		## travel alongside it or a restored wall would be inert sand.
		"structures": structure_field.to_dict() if structure_field != null else {},
		"enable_structures": enable_structures}
	RenderingServer.call_on_render_thread(_render_capture_checkpoint.bind(
		solver.state_revision, generation))


func _render_flush_ledger_for_checkpoint() -> void:
	if not tide_ledger_batches.flush():
		call_deferred("_fail", "checkpoint tide ledger flush failed")


func request_checkpoint_save(path: String) -> StringName:
	if path.is_empty() or FileAccess.file_exists(path):
		return &"invalid_or_existing_path"
	if closing or not ready_for_ticks or playing or tick_pending or \
			checkpoint_capture_pending or not command_queue.pending.is_empty() or \
			replay_target_tick >= 0 or not pending_save_path.is_empty():
		return &"save_busy"
	pending_save_path = path
	last_save_error = &""
	_start_checkpoint_capture()
	return StringName()


func _render_capture_checkpoint(revision: int, token: int) -> void:
	if closing or token != generation or solver.state_revision != revision:
		return
	for field in ["water", "momentum_x", "momentum_z"]:
		var error: Error = solver.request_data(field,
			_on_checkpoint_field.bind(field, revision, token))
		if error != OK:
			call_deferred("_fail", "checkpoint readback failed: %s %d" % [field, error])
	if foam_field != null:
		var foam_error: Error = foam_field.request_data(
			_on_checkpoint_field.bind("foam_history", revision, token))
		if foam_error != OK:
			call_deferred("_fail", "checkpoint foam readback failed: %d" % foam_error)
	if local_front_field != null:
		var front_error: Error = local_front_field.request_data(
			_on_checkpoint_field.bind("local_front_history", revision, token))
		if front_error != OK:
			call_deferred("_fail", "checkpoint local front readback failed: %d" % front_error)


func _on_checkpoint_field(data: PackedByteArray, field: String,
		revision: int, token: int) -> void:
	call_deferred("_checkpoint_field_ready", data, field, revision, token)


func _checkpoint_field_ready(data: PackedByteArray, field: String,
		revision: int, token: int) -> void:
	if closing or token != generation or not checkpoint_capture_pending or \
			checkpoint_capture.get("revision", -1) != revision:
		return
	var is_foam := field == "foam_history"
	var is_front := field == "local_front_history"
	if data.size() != GRID_SIZE * GRID_SIZE * (8 if is_foam or is_front else 4):
		_fail("checkpoint readback size mismatch: " + field)
		return
	var values := data.to_float32_array()
	for i in values.size():
		var value: float = values[i]
		if not is_finite(value) or (is_foam and \
				((i % 2 == 0 and (value < 0.0 or value > 1.0)) or \
				(i % 2 == 1 and value < 0.0))):
			_fail("checkpoint contained nonfinite data: " + field)
			return
	if is_foam:
		checkpoint_capture["foam_history"] = values
	elif is_front:
		checkpoint_capture["local_front_history"] = values
	else:
		checkpoint_capture.fields[field] = values
	if checkpoint_capture.fields.size() != 3 or \
			(checkpoint_capture.foam_history_expected and \
			not checkpoint_capture.has("foam_history")) or \
			(checkpoint_capture.local_front_history_expected and \
			not checkpoint_capture.has("local_front_history")):
		return
	checkpoint_capture.erase("foam_history_expected")
	checkpoint_capture.erase("local_front_history_expected")
	checkpoint_capture.shadow["water"] = checkpoint_capture.fields["water"]
	checkpoints.append(checkpoint_capture)
	if checkpoints.size() > MAX_CHECKPOINTS:
		checkpoints.pop_front()
	if not pending_save_path.is_empty():
		var prefix: Array[Dictionary] = command_queue.applied_log.duplicate(true)
		last_save_error = CheckpointStore.save(pending_save_path,
			checkpoint_capture, prefix, enable_erosion)
		if last_save_error.is_empty():
			last_save_path = pending_save_path
		pending_save_path = ""
	checkpoint_capture = {}
	checkpoint_capture_pending = false
	if not playing and not tick_pending and not command_queue.pending.is_empty():
		_dispatch_paused_patch()


func set_player_camera(enabled: bool) -> void:
	use_player_camera = enabled
	if overview_camera == null or player_camera == null:
		return
	player_camera.current = enabled
	overview_camera.current = not enabled


func set_fixture_camera(camera_id: StringName) -> bool:
	if fixture_id not in [WaterFixture.FIXTURE_ID, &"reference_sand_unused",
			SandFixture.COUPLED_FIXTURE_ID]:
		return false
	var index := WaterFixture.camera_index(camera_id) if fixture_id == WaterFixture.FIXTURE_ID else SandFixture.camera_index(camera_id)
	if index < 0:
		return false
	fixture_camera_id = camera_id
	if overview_camera == null:
		return true
	var camera := overview_camera
	if fixture_id == WaterFixture.FIXTURE_ID:
		camera.position = WaterFixture.CAMERA_POSITIONS[index]
		camera.fov = WaterFixture.CAMERA_FOV[index]
		camera.look_at(WaterFixture.CAMERA_TARGETS[index], Vector3.UP)
	else:
		camera.position = SandFixture.CAMERA_POSITIONS[index]
		camera.fov = SandFixture.CAMERA_FOV[index]
		camera.look_at(SandFixture.CAMERA_TARGETS[index], Vector3.UP)
	set_player_camera(false)
	return true


func set_visual_time(seconds: float) -> void:
	visual_time_s = seconds
	if water_material != null:
		water_material.set_shader_parameter("visual_time_s", seconds)
	if terrain_material != null:
		terrain_material.set_shader_parameter("visual_time_s", seconds)


## A fixture-scoped support-loss event. It demotes the packed tower's material
## state without changing sand mass; the normal conservative slope pass then
## produces the local collapse. Call only at a completed, paused tick.
func request_sand_support_loss(request: Dictionary) -> Dictionary:
	var request_id: int = request.get("request_id", 0) if \
			typeof(request.get("request_id", null)) == TYPE_INT else 0
	if fixture_id not in [&"reference_sand_unused", SandFixture.COUPLED_FIXTURE_ID] or closing or not ready_for_ticks or \
			tick_pending or playing or solver == null:
		return {"ok": false, "code": &"state_not_ready", "request_id": request_id}
	if typeof(request.get("generation", null)) != TYPE_INT or \
			int(request.generation) != generation:
		return {"ok": false, "code": &"inactive_generation", "request_id": request_id}
	if request_id <= support_loss_highwater_id or request_id <= 0 or \
			not support_loss_events.is_empty():
		return {"ok": false, "code": &"invalid_request", "request_id": request_id}
	support_loss_highwater_id = request_id
	last_support_loss_error = &""
	var side_only: bool = request.get("side_only", false) == true and \
		fixture_id == SandFixture.COUPLED_FIXTURE_ID
	RenderingServer.call_on_render_thread(_render_sand_support_loss.bind(
		request_id, generation, completed_ticks, side_only))
	return {"ok": true, "code": &"accepted", "request_id": request_id,
		"tick": completed_ticks}


func _render_sand_support_loss(request_id: int, token: int, tick: int,
		side_only: bool) -> void:
	if closing or token != generation or solver == null:
		call_deferred("_finish_sand_support_loss", request_id, tick,
			&"inactive_generation", token, -1, 0, side_only)
		return
	var data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(
		solver.current_texture("sand"), 0)
	if data.size() != GRID_SIZE * GRID_SIZE * 4:
		call_deferred("_finish_sand_support_loss", request_id, tick,
			&"state_not_ready", token, -1, 0, side_only)
		return
	var current_sand := data.to_float32_array()
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	var count := 0
	for z in range(SandFixture.CENTER_Z - SandFixture.BASE_RADIUS_CELLS,
			SandFixture.CENTER_Z + SandFixture.BASE_RADIUS_CELLS + 1):
		for x in range(SandFixture.PACKED_CENTER_X - SandFixture.BASE_RADIUS_CELLS,
				(SandFixture.PACKED_CENTER_X - 2 if side_only else \
				SandFixture.PACKED_CENTER_X + SandFixture.BASE_RADIUS_CELLS + 1)):
			var index: int = z * GRID_SIZE + x
			stream.put_32(index)
			stream.put_float(current_sand[index])
			stream.put_float(0.1)
			stream.put_float(0.0)
			shadow_domain.compaction[index] = 0.1
			count += 1
	if not solver.dispatch_tool_patch(stream.data_array, count):
		call_deferred("_finish_sand_support_loss", request_id, tick,
			&"state_not_ready", token, -1, 0, side_only)
		return
	call_deferred("_finish_sand_support_loss", request_id, tick,
		&"ok", token, solver.state_revision, count, side_only)


func _finish_sand_support_loss(request_id: int, tick: int,
		code: StringName, token: int, revision: int, count: int,
		side_only: bool) -> void:
	if closing or token != generation:
		return
	last_support_loss_error = &"" if code == &"ok" else code
	if code == &"ok":
		support_loss_applied_id = request_id
		var event := {"generation": generation,
			"request_id": request_id, "tick": tick, "revision": revision,
			"affected_cells": count, "compaction_after": 0.1}
		if side_only:
			event["cause"] = "erosion_toe_loss"
			event["sensor_revision"] = auto_support_trigger_revision
			event["toe_initial_m3"] = auto_support_toe_initial_m3
			event["toe_at_trigger_m3"] = auto_support_toe_latest_m3
		support_loss_events.append(event)
	if auto_support_event_active:
		auto_support_event_active = false
		if code == &"ok":
			playing = true
		else:
			_fail("automatic sand support application failed: " + String(code))


func request_wave(request: Dictionary) -> Dictionary:
	var request_id: int = request.get("request_id", 0) if \
			typeof(request.get("request_id", null)) == TYPE_INT else 0
	if closing or not ready_for_ticks or shadow_domain == null:
		return _wave_result(&"not_ready", request_id, -1)
	if typeof(request.get("generation", null)) != TYPE_INT or \
			int(request.generation) != generation:
		return _wave_result(&"inactive_generation", request_id, -1)
	if not request.has("domain_id") or \
			StringName(request.domain_id) != shadow_domain.domain_id or \
			request_id <= 0 or typeof(request.get("start_tick", null)) != TYPE_INT or \
			typeof(request.get("seed", null)) != TYPE_INT or \
			typeof(request.get("amplitude_m", null)) not in [TYPE_FLOAT, TYPE_INT] or \
			typeof(request.get("duration_s", null)) not in [TYPE_FLOAT, TYPE_INT]:
		return _wave_result(&"invalid_request", request_id, -1)
	for prior in wave_requests:
		if int(prior.request_id) == request_id:
			return _wave_result(&"duplicate_request", request_id, int(prior.start_tick))
	if request_id <= wave_highwater_id:
		return _wave_result(&"invalid_request", request_id, -1)
	var profile_id := StringName(request.get("profile_id", &""))
	if not WAVE_PROFILES.has(profile_id):
		return _wave_result(&"invalid_profile", request_id, -1)
	var profile: Dictionary = WAVE_PROFILES[profile_id]
	var amplitude_m := float(request.amplitude_m)
	var duration_s := float(request.duration_s)
	if not is_finite(amplitude_m) or amplitude_m < 0.0 or \
			amplitude_m > float(profile.amplitude_max_m) or \
			not is_finite(duration_s) or duration_s < float(profile.duration_min_s) or \
			duration_s > float(profile.duration_max_s):
		return _wave_result(&"invalid_request", request_id, -1)
	var start_tick: int = request.start_tick
	if start_tick <= completed_ticks + (1 if tick_pending else 0):
		return _wave_result(&"past_tick", request_id, -1)
	wave_requests.append({"domain_id": shadow_domain.domain_id,
		"generation": generation, "request_id": request_id,
		"start_tick": start_tick, "profile_id": profile_id,
		"amplitude_m": amplitude_m, "duration_s": duration_s,
		"seed": int(request.seed)})
	wave_highwater_id = request_id
	return _wave_result(&"", request_id, start_tick)


func _wave_result(code: StringName, request_id: int, effective_tick: int) -> Dictionary:
	return {"ok": code.is_empty(), "code": code,
		"request_id": request_id, "effective_tick": effective_tick}


func _wave_height_at_tick(tick: int) -> float:
	var total := 0.0
	for request in wave_requests:
		if int(request.generation) != generation or tick < int(request.start_tick):
			continue
		var u := (float(tick - int(request.start_tick)) + 0.5) * SIM_DELTA / \
			float(request.duration_s)
		if u >= 1.0:
			continue
		var phase := float(int(request.seed) & 1023) * TAU / 1024.0
		var envelope := pow(sin(PI * u), 2.0)
		var modulation := 0.95 + 0.05 * sin(TAU * u + phase)
		total += float(request.amplitude_m) * envelope * modulation
	if total > 0.25:
		wave_clamp_events += 1
	return minf(total, 0.25)


func aim_player_camera(position_m: Vector3, target_m: Vector3) -> void:
	player_camera_position = position_m
	player_camera_target = target_m
	if player_camera == null:
		return
	player_camera.position = position_m
	player_camera.look_at(target_m, Vector3.UP)


## Main-thread entry point for a structure event. Rasterises on the shadow,
## pushes the packed cells to the GPU and refreshes the collision chunks they
## touch, so the drawn mesh, the collision proxy and the solver all follow from
## the same heightfield with no obstacle bit involved.
func request_build_structure(structure: SandcastleStructure,
		funded_by_bucket := false) -> bool:
	if not enable_structures or not ready_for_ticks or closing or tick_pending:
		return false
	last_structure_booked_m3 = 0.0
	last_structure_error = ""
	structure_requirement_hint_m3 = structure.volume_m3(CELL_SIZE_M)
	RenderingServer.call_on_render_thread(_render_build_structure.bind(
		structure, funded_by_bucket, generation))
	return true


func _render_build_structure(structure: SandcastleStructure,
		funded_by_bucket: bool, token: int) -> void:
	if closing or token != generation or structure_field == null or solver == null:
		return
	var booked := structure_field.add(structure, shadow_domain, funded_by_bucket)
	if booked > 0.0 and structure.blocks_water and not _push_obstacles(token):
		return
	if booked <= 0.0:
		var reason := "insufficient_sand" if funded_by_bucket else "build_rejected"
		call_deferred("_finish_build_structure", 0.0, reason, token)
		return
	var patch := structure_field.patch_for(structure, shadow_domain)
	if not solver.dispatch_tool_patch(patch.data, patch.count):
		call_deferred("_fail", "structure patch dispatch failed")
		return
	var chunks := _chunks_for_cells(patch.dirty_cells)
	if not collision_proxy.apply_shadow_chunks(chunks, solver.state_revision, token,
			shadow_domain.rock, shadow_domain.sand):
		call_deferred("_fail", "structure collision chunk update failed")
		return
	## The shadow now matches the GPU for sand, so the next sync is not required.
	shadow_sand_revision = solver.state_revision
	call_deferred("_finish_build_structure", booked, "", token)


func _finish_build_structure(booked: float, error: String, token: int) -> void:
	if closing or token != generation:
		return
	last_structure_booked_m3 = booked
	last_structure_error = error
	if booked > 0.0:
		structure_builds += 1
	_update_status()


## Render-thread: rebuild the given collision chunks from the current shadow.
## Callers use this after a shadow sync so a chunk recorded earlier is not left
## describing an older bed.
func _render_apply_shadow_chunks(chunks: PackedInt32Array, revision: int,
		token: int) -> void:
	if closing or token != generation or solver.state_revision != revision:
		return
	call_deferred("_record_tool_revisions", PackedInt32Array(), chunks, revision, token)


## Pushes the field's obstacle mask and drains the water out of any cell that just
## became blocked. Returns false on a device failure.
##
## This is the one structure event that changes the water's effective area, so it
## must go through `obstacle_remap` - the contract forbids changing the mask
## without remapping the volume.
func _push_obstacles(token: int) -> bool:
	if obstacle_remap == null or solver == null:
		return false
	var mask := structure_field.obstacle_mask(GRID_SIZE)
	if not solver.update_obstacles(mask):
		call_deferred("_fail", "structure obstacle upload failed")
		return false
	if not obstacle_remap.clear_tiles() or not obstacle_remap.dispatch():
		call_deferred("_fail", "structure obstacle remap dispatch failed")
		return false
	shadow_domain.obstacle = mask
	return true


## Runs the T06 support model on the shadow bed and queues the loosened patch for
## any structure that lets go, so a wall built in the main scene can actually
## collapse instead of only standing there.
##
## Support is evaluated against the CPU shadow, which can lag the GPU by one sync
## interval; the CPU-reference tests evaluate it against an exact bed, so the main
## scene's collapse timing is an approximation of theirs, not the same figure.
func _update_structures() -> void:
	if not enable_structures or structure_field == null or structure_field.structures.is_empty():
		return
	if not pending_collapse_patches.is_empty():
		return
	if closing or tick_pending or replay_target_tick >= 0 or not ready_for_ticks:
		return
	var had_impermeable := structure_field.has_impermeable()
	var collapsed := structure_field.step(shadow_domain, SIM_DELTA,
		STRUCTURE_DAMAGE_RATE_PER_S)
	for structure_id in collapsed:
		var structure := structure_field.find(structure_id)
		if structure != null:
			pending_collapse_patches.append(structure)
	## A collapse that opens area back up only needs the mask updated; the solver
	## refills it on the next substep, so no volume has to be moved.
	if had_impermeable and not structure_field.has_impermeable():
		RenderingServer.call_on_render_thread(_push_obstacles.bind(generation))
	if pending_collapse_patches.is_empty():
		return
	structures_collapsed += pending_collapse_patches.size()
	pending_collapse_patches.clear()
	## Every standing structure needs its loosened compaction on the GPU. Send the
	## whole field so a collapse and a later build cannot disagree.
	if tick_pending:
		return
	RenderingServer.call_on_render_thread(_render_push_structures.bind(generation))


func _render_push_structures(token: int) -> void:
	if closing or token != generation or structure_field == null or solver == null:
		return
	for structure in structure_field.structures:
		var patch := structure_field.patch_for(structure, shadow_domain)
		if not solver.dispatch_tool_patch(patch.data, patch.count):
			call_deferred("_fail", "structure collapse patch dispatch failed")
			return
	shadow_sand_revision = solver.state_revision


func _chunks_for_cells(cells: PackedInt32Array) -> PackedInt32Array:
	var chunks := PackedInt32Array()
	var chunks_per_row := GRID_SIZE / 32
	for index in cells:
		var chunk_id := (index / GRID_SIZE / 32) * chunks_per_row + (index % GRID_SIZE) / 32
		if not chunks.has(chunk_id):
			chunks.append(chunk_id)
	chunks.sort()
	return chunks


func _update_status() -> void:
	if status_label == null:
		return
	status_label.visible = not hide_hud
	if hide_hud:
		return
	status_label.text = "GPU 水沙状态预览 | 256² | 场景 %d：%s | %s | 调试：%s\nTick %d  CFL 子步 %d  入水 %.4f m³  出水 %.4f m³  桶 %.4f m³\n左键挖沙 右键放沙 空格暂停 V 调试 F5 玩家视角 F6 隐藏 HUD%s；暂停后 Z/Y 撤销/重做。%s" % [
		preset_index + 1, Scenarios.NAMES[preset_index],
		"故障" if not last_error.is_empty() else ("运行" if playing else "暂停"),
		DEBUG_NAMES[debug_view],
		completed_ticks, last_substeps, last_source_m3, last_sink_m3,
		shadow_domain.tool_inventory_m3,
		" B 建墙 N 建塔" if enable_structures else "",
		"水沙耦合实验模式。" if enable_erosion else "侵蚀尚未接入。"]
	if audit_revision >= 0:
		status_label.text += "\nGPU 审计 r%d：水 %.4f m³  最小深 %.6f m  无效 %d  负水 %d" % [
			audit_revision, audit_water_m3, audit_min_depth_m,
			audit_invalid_cells, audit_negative_cells]
	if audit_sand_revision >= 0:
		status_label.text += "\nGPU 沙审计 r%d：沙 %.4f  悬 %.4f  连桶 %.4f m³  闭合差 %.6f m³  负沙 %d  无效 %d" % [
			audit_sand_revision, audit_sand_m3, audit_sediment_m3,
			audit_sand_total_m3, audit_sand_closure_m3,
			audit_sand_negative_cells, audit_sand_invalid_cells]
		status_label.text += "\n沙源 %.4f  沙汇 %.4f m³  GPU NaN %d  GPU 超载 %d  CPU 截沙 %d" % [
			shadow_domain.sand_source_m3, shadow_domain.sand_sink_m3,
			solver.nan_events if solver != null else 0,
			solver.overload_events if solver != null else 0,
			shadow_domain.clamped_sand_events]
	if debug_view == 13 and collision_proxy != null:
		status_label.text += "\n最近脏块 %d  待回读 %d  正在回读 %d" % [
			last_dirty_chunks.size(), collision_proxy.pending_revisions.size(),
			collision_proxy.active_chunks.size()]
	elif debug_view == 14:
		if proxy_debug_shadow_stale:
			status_label.text += "\n碰撞差异待同步：GPU r%d，CPU 影子 r%d（运行中不做全域回读）" % [
				solver.state_revision, shadow_revision]
		else:
			status_label.text += "\n碰撞代理相对 CPU 影子床高：最大差 %.6f m  缺块 %d" % [
				proxy_debug_max_error_m, proxy_debug_missing_chunks]
	if not last_error.is_empty():
		status_label.text += "\n" + last_error


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			playing = not playing
			_update_status()
		elif event.keycode == KEY_V:
			_set_debug_view((debug_view + 1) % DEBUG_NAMES.size())
			_update_status()
		elif event.keycode == KEY_B and enable_structures:
			_place_structure_at_cursor(Structure.Kind.WALL)
		elif event.keycode == KEY_N and enable_structures:
			_place_structure_at_cursor(Structure.Kind.TOWER)
		elif event.keycode == KEY_F5:
			set_player_camera(not use_player_camera)
			_update_status()
		elif event.keycode == KEY_F6:
			hide_hud = not hide_hud
			_update_status()
		elif event.keycode == KEY_Z and not playing:
			_undo_tool_command()
		elif event.keycode == KEY_Y and not playing:
			_redo_tool_command()
	if event is InputEventMouseButton and ready_for_ticks:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				active_brush_kind = &"remove_sand" if event.button_index == MOUSE_BUTTON_LEFT else &"place_sand"
				var hit = _brush_hit()
				if hit != null:
					last_brush_position = hit
					_submit_brush(active_brush_kind, 0.015, hit, hit, &"circle")
			else:
				active_brush_kind = &""
	if event is InputEventMouseMotion and not active_brush_kind.is_empty():
		var hit = _brush_hit()
		if hit != null:
			var distance_m: float = last_brush_position.distance_to(hit)
			if distance_m >= 0.025:
				_submit_brush(active_brush_kind, maxf(0.0005, distance_m * 0.02),
					last_brush_position, hit, &"swept_segment")
				last_brush_position = hit


## Places a structure centred on the cursor. B builds a wall, N a tower; both are
## tapered to sit inside the angle of repose at their build compaction, so the
## slope relaxation leaves them standing.
func _place_structure_at_cursor(kind: int) -> bool:
	var hit = _brush_hit()
	if hit == null:
		return false
	return place_structure_at_world(kind, hit)


## Builds a structure centred on a world position. Split out from the cursor path
## so the placement maths can be driven without a mouse.
func place_structure_at_world(kind: int, world: Vector3) -> bool:
	if not enable_structures or closing or not ready_for_ticks or tick_pending:
		return false
	var half := float(GRID_SIZE) * CELL_SIZE_M * 0.5
	var centre_x := int(round((world.x + half) / CELL_SIZE_M - 0.5))
	var centre_z := int(round((world.z + half) / CELL_SIZE_M - 0.5))
	var structure := Structure.new()
	structure.kind = kind
	structure.compaction = 0.9
	structure.taper_slope_m = 0.11
	if kind == Structure.Kind.TOWER:
		structure.size = Vector2i(9, 9)
		structure.height_m = 0.45
		structure.origin = Vector2i(centre_x - 4, centre_z - 4)
	else:
		structure.size = Vector2i(7, 30)
		structure.height_m = 0.34
		structure.origin = Vector2i(centre_x - 3, centre_z - 15)
	## Player placement spends the bucket, so a structure cannot manufacture sand.
	return request_build_structure(structure, true)


## Keeps the ring under the cursor, at the bed height the shadow knows about.
## The shadow can lag the GPU between syncs, so the ring is a guide, not a
## measurement.
func _update_brush_indicator() -> void:
	if brush_indicator == null or not show_brush_indicator or not ready_for_ticks:
		return
	var hit = _brush_hit()
	if hit == null:
		brush_indicator.hide_indicator()
		return
	if prefetch_sand_on_hover and enable_erosion:
		last_sand_hover_usec = Time.get_ticks_usec()
	var half := float(GRID_SIZE) * CELL_SIZE_M * 0.5
	var cell_x := clampi(int(floor((hit.x + half) / CELL_SIZE_M)), 0, GRID_SIZE - 1)
	var cell_z := clampi(int(floor((hit.z + half) / CELL_SIZE_M)), 0, GRID_SIZE - 1)
	var index := cell_z * GRID_SIZE + cell_x
	var surface_y: float = shadow_domain.rock[index] + shadow_domain.sand[index]
	brush_indicator.aim(hit, surface_y, active_brush_kind)


func _brush_hit():
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var cursor := get_viewport().get_mouse_position()
	return Plane(Vector3.UP, 0.0).intersects_ray(
		camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))


func _submit_brush(kind: StringName, amount_m3: float,
		start: Vector3, end: Vector3, shape: StringName) -> StringName:
	if not ready_for_ticks or closing:
		return &"backend_unavailable"
	if not pending_save_path.is_empty():
		return &"save_in_progress"
	command_id += 1
	var transform := {"position_m": start}
	if shape == &"swept_segment":
		transform["end_position_m"] = end
	# Only an in-flight water tick advances time; a paused edit patch does not.
	var target_tick := completed_ticks + (1 if water_tick_in_flight else 0)
	var command := {"domain_id": shadow_domain.domain_id,
		"generation": shadow_domain.generation, "sim_tick": target_tick,
		"command_id": command_id, "kind": kind, "shape": shape,
		"transform": transform, "radius_m": 0.38,
		"strength": 1.0, "amount_m3": amount_m3, "seed": command_id}
	var error: StringName = command_queue.submit(command)
	if not error.is_empty():
		return error
	last_tool_submit_usec = Time.get_ticks_usec()
	if not tick_pending:
		_dispatch_paused_patch()
	return StringName()


func _apply_due_tool_commands() -> Dictionary:
	var results: Array[Dictionary] = command_queue.apply_due_commands(completed_ticks)
	var applied_usec := Time.get_ticks_usec()
	for result in results:
		if profile_tool_latency and result.status == &"applied" and \
				result.has("command_id"):
			tool_apply_usec_by_command_id[int(result.command_id)] = applied_usec
		max_cell_edit_height_m = maxf(max_cell_edit_height_m,
			float(result.get("max_cell_delta_m", 0.0)))
	return _patch_for_results(results)


func _patch_for_results(results: Array[Dictionary]) -> Dictionary:
	var patch := command_queue.build_gpu_patch_batch(results)
	var chunks := {}
	var command_ids := PackedInt32Array()
	var chunks_per_row: int = GRID_SIZE / 32
	for result in results:
		if result.status == &"applied":
			if result.has("command_id"):
				command_ids.append(result.command_id)
			for chunk_id in result.dirty_chunks:
				chunks[chunk_id] = true
			for cell_index in result.dirty_cells:
				var x: int = cell_index % GRID_SIZE
				var z: int = cell_index / GRID_SIZE
				var cx: int = x / 32
				var cz: int = z / 32
				if x % 32 == 0 and cx > 0:
					chunks[cz * chunks_per_row + cx - 1] = true
				if z % 32 == 0 and cz > 0:
					chunks[(cz - 1) * chunks_per_row + cx] = true
				if x % 32 == 0 and z % 32 == 0 and cx > 0 and cz > 0:
					chunks[(cz - 1) * chunks_per_row + cx - 1] = true
	var sorted_chunks: Array = chunks.keys()
	sorted_chunks.sort()
	patch["chunks"] = PackedInt32Array(sorted_chunks)
	patch["command_ids"] = command_ids
	last_dirty_cells = patch.count
	if patch.count > 0:
		if enable_erosion:
			for chunk_id in patch.chunks:
				collision_change_upper_bound_m[chunk_id] = 0.0
		last_dirty_chunks = patch.chunks.duplicate()
		dirty_debug_revision += 1
	return patch


func _dispatch_paused_patch() -> void:
	if enable_erosion and shadow_sand_revision != solver.state_revision:
		if sand_prefetch_in_flight and sand_prefetch_revision == solver.state_revision:
			return
		_request_shadow_sync("paused_patch")
		return
	var patch := _apply_due_tool_commands()
	if patch.count == 0:
		_update_status()
		return
	_dispatch_paused_patch_data(patch)


func _dispatch_paused_patch_data(patch: Dictionary) -> void:
	tick_pending = true
	RenderingServer.call_on_render_thread(_render_paused_patch.bind(
		patch.data, patch.count, patch.chunks, patch.command_ids, generation))


func _undo_tool_command() -> bool:
	if playing or tick_pending or not ready_for_ticks or \
			not command_queue.pending.is_empty():
		return false
	var before_sand := shadow_domain.sand.duplicate()
	var before_compaction := shadow_domain.compaction.duplicate()
	if not command_queue.undo_last():
		return false
	_dispatch_state_diff(before_sand, before_compaction)
	return true


func _redo_tool_command() -> bool:
	if playing or tick_pending or not ready_for_ticks or \
			not command_queue.pending.is_empty():
		return false
	var before_sand := shadow_domain.sand.duplicate()
	var before_compaction := shadow_domain.compaction.duplicate()
	if not command_queue.redo_last():
		return false
	_dispatch_state_diff(before_sand, before_compaction)
	return true


func _dispatch_state_diff(before_sand: PackedFloat32Array,
		before_compaction: PackedFloat32Array) -> void:
	var dirty := PackedInt32Array()
	for i in shadow_domain.sand.size():
		if before_sand[i] != shadow_domain.sand[i] or \
				before_compaction[i] != shadow_domain.compaction[i]:
			dirty.append(i)
	if dirty.is_empty():
		_update_status()
		return
	var results: Array[Dictionary] = [{"status": &"applied", "dirty_cells": dirty,
		"dirty_chunks": PackedInt32Array()}]
	_dispatch_paused_patch_data(_patch_for_results(results))


func _render_paused_patch(data: PackedByteArray, count: int,
		chunks: PackedInt32Array, command_ids: PackedInt32Array,
		token: int) -> void:
	if closing or token != generation:
		return
	if not solver.dispatch_tool_patch(data, count):
		call_deferred("_fail", "paused tool patch dispatch failed")
		return
	call_deferred("_record_tool_revisions", command_ids,
		chunks, solver.state_revision, token)
	_request_sand_audit_render(token)
	_publish_textures()
	call_deferred("_paused_patch_finished", token)


func _paused_patch_finished(token: int) -> void:
	if closing or token != generation:
		return
	completed_patch_batches += 1
	if enable_erosion:
		shadow_sand_revision = solver.state_revision
	tick_pending = false
	if sand_audit_refresh_required:
		sand_audit_refresh_required = false
		RenderingServer.call_on_render_thread(_request_sand_audit_render.bind(token))
	_update_status()
	if replay_target_tick >= 0 and completed_ticks >= replay_target_tick and \
			command_queue.pending.is_empty():
		_request_replay_collision()
		replay_ready = true
		return
	if not playing and not command_queue.pending.is_empty():
		_dispatch_paused_patch()


func _record_tool_revisions(command_ids: PackedInt32Array,
		chunks: PackedInt32Array, revision: int, token: int) -> void:
	if closing or token != generation:
		return
	if not collision_proxy.apply_shadow_chunks(chunks, revision, token,
			shadow_domain.rock, shadow_domain.sand):
		_fail("tool shadow collision chunk update failed")
		return
	for id in command_ids:
		tool_revision_by_command_id[id] = revision


func _fail(message: String) -> void:
	if closing:
		return
	last_error = message
	playing = false
	tick_pending = false
	water_tick_in_flight = false
	push_error(message)
	_update_status()


func _request_replay_collision() -> void:
	if replay_collision_requested:
		return
	replay_collision_requested = true
	RenderingServer.call_on_render_thread(_request_full_collision_render.bind(generation))


func _request_full_collision_render(token: int) -> void:
	if closing or token != generation:
		return
	var all_chunks := PackedInt32Array()
	for chunk_id in (GRID_SIZE / 32) * (GRID_SIZE / 32):
		all_chunks.append(chunk_id)
	if not collision_proxy.request_chunks_render(all_chunks, solver.state_revision, token):
		call_deferred("_fail", "GPU full collision request failed")


func _set_debug_view(mode: int) -> void:
	debug_view = mode
	if debug_view >= 13 and chunk_debug_texture != null and collision_proxy != null:
		_refresh_chunk_debug_texture()
	if terrain_material != null:
		terrain_material.set_shader_parameter("debug_mode", debug_view)
	if water_material != null:
		water_material.set_shader_parameter("debug_mode", debug_view)


func _refresh_chunk_debug_texture() -> void:
	if chunk_debug_texture == null or collision_proxy == null or shadow_domain == null:
		return
	proxy_debug_shadow_stale = debug_view == 14 and enable_erosion and \
			shadow_revision != solver.state_revision
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	if proxy_debug_shadow_stale:
		image.fill(Color(0.35, 0.35, 0.35))
		chunk_debug_texture.update(image)
		chunk_debug_dirty_revision = dirty_debug_revision
		chunk_debug_collision_batches = collision_proxy.completed_batches
		_update_status()
		return
	var dirty := {}
	for chunk_id in last_dirty_chunks:
		dirty[chunk_id] = true
	proxy_debug_max_error_m = 0.0
	proxy_debug_missing_chunks = 0
	for chunk_id in 64:
		var value := 0.0
		if debug_view == 13:
			value = 0.5 if dirty.has(chunk_id) else 0.0
			if collision_proxy.pending_revisions.has(chunk_id) or \
					chunk_id in collision_proxy.active_chunks:
				value = 1.0
		elif debug_view == 14:
			var shape: CollisionShape3D = collision_proxy.shapes.get(chunk_id)
			if shape == null or shape.shape == null:
				value = 1.0
				proxy_debug_missing_chunks += 1
			else:
				var heights: PackedFloat32Array = shape.shape.map_data
				var chunk_error := 0.0
				for local_z in 33:
					for local_x in 33:
						var x: int = mini((chunk_id % 8) * 32 + local_x, 255)
						var z: int = mini((chunk_id / 8) * 32 + local_z, 255)
						var i := z * GRID_SIZE + x
						chunk_error = maxf(chunk_error, absf(heights[local_z * 33 + local_x] - \
							shadow_domain.rock[i] - shadow_domain.sand[i]))
				proxy_debug_max_error_m = maxf(proxy_debug_max_error_m, chunk_error)
				value = 0.25 + 0.5 * clampf(chunk_error / 0.01, 0.0, 1.0)
		image.set_pixel(chunk_id % 8, chunk_id / 8, Color(value, 0.0, 0.0))
	chunk_debug_texture.update(image)
	chunk_debug_dirty_revision = dirty_debug_revision
	chunk_debug_collision_batches = collision_proxy.completed_batches
	_update_status()


func _on_debug_audit(data: PackedByteArray, revision: int, token: int) -> void:
	call_deferred("_record_debug_audit", data, revision, token)


func _request_sand_audit_render(token: int) -> void:
	if closing or token != generation or sand_audit == null:
		return
	if sand_audit.pending:
		if not playing:
			sand_audit_refresh_required = true
		return
	var ledger := {"inventory_m3": shadow_domain.tool_inventory_m3,
		"source_m3": shadow_domain.sand_source_m3,
		"sink_m3": shadow_domain.sand_sink_m3}
	var error: Error = sand_audit.request(_on_sand_audit.bind(ledger, token))
	if error != OK:
		call_deferred("_fail", "GPU sand audit request failed: %d" % error)


func _on_sand_audit(data: PackedByteArray, revision: int,
		ledger: Dictionary, token: int) -> void:
	call_deferred("_record_sand_audit", data, revision, ledger, token)


func _record_sand_audit(data: PackedByteArray, revision: int,
		ledger: Dictionary, token: int) -> void:
	if closing or token != generation or sand_audit == null:
		return
	var result: Dictionary = sand_audit.decode(data)
	if not result.get("valid", false):
		_fail("GPU sand audit data invalid at revision %d" % revision)
		return
	if result.invalid_cells != 0 or result.negative_cells != 0:
		_fail("GPU sand audit found invalid/negative cells at revision %d" % revision)
		return
	var current_total: float = result.sand_m3 + result.sediment_m3 + ledger.inventory_m3
	var closure := absf(current_total - initial_sand_total_m3 - \
		ledger.source_m3 + ledger.sink_m3)
	if closure > maxf(0.001, initial_sand_total_m3 * 0.005):
		_fail("GPU sand account did not close at revision %d: %.6f m3" % [
			revision, closure])
		return
	if revision > audit_sand_revision:
		audit_sand_m3 = result.sand_m3
		audit_sediment_m3 = result.sediment_m3
		audit_sand_total_m3 = current_total
		audit_sand_closure_m3 = closure
		audit_sand_invalid_cells = result.invalid_cells
		audit_sand_negative_cells = result.negative_cells
		audit_sand_revision = revision
		_update_status()
	if sand_audit_refresh_required and not playing and not tick_pending:
		sand_audit_refresh_required = false
		RenderingServer.call_on_render_thread(_request_sand_audit_render.bind(token))


func _record_debug_audit(data: PackedByteArray, revision: int, token: int) -> void:
	if closing or token != generation or solver == null:
		return
	var result := solver.decode_audit_tiles(data)
	if not result.get("valid", false):
		_fail("debug audit invalid at revision %d" % revision)
		return
	if result.invalid_cells != 0 or result.negative_cells != 0 or \
			result.minimum_depth_m < -0.000001:
		_fail("debug audit found invalid/negative water at revision %d" % revision)
		return
	if revision <= audit_revision:
		return
	audit_water_m3 = result.water_m3
	audit_min_depth_m = result.minimum_depth_m
	audit_invalid_cells = result.invalid_cells
	audit_negative_cells = result.negative_cells
	audit_revision = revision
	_update_status()


func _exit_tree() -> void:
	closing = true
	generation += 1
	if worker_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(worker_task_id)
		worker_task_id = -1
	RenderingServer.call_on_render_thread(_render_release)


func _render_release() -> void:
	if tide_ledger_batches != null:
		tide_ledger_batches.release()
	if tide_ledger_ring != null:
		tide_ledger_ring.release()
	if rise_front_field != null:
		rise_front_field.release()
	if contact_history_field != null:
		contact_history_field.release()
	if prototype_front_band_foam_source and foam_field != null:
		foam_field.release_uniform_sets()
	if local_front_field != null:
		local_front_field.release()
	if foam_field != null:
		foam_field.release()
	foam_texture.texture_rd_rid = RID()
	previous_foam_texture.texture_rd_rid = RID()
	rise_front_texture.texture_rd_rid = RID()
	local_front_texture.texture_rd_rid = RID()
	contact_history_texture.texture_rd_rid = RID()
	if obstacle_remap != null:
		obstacle_remap.release()
	if material_coupler != null:
		material_coupler.release()
	if sediment_coupler != null:
		sediment_coupler.release()
	if sand_audit != null:
		sand_audit.release()
	for wrapper in [rock_texture, sand_texture, wetness_texture, compaction_texture,
			water_texture, momentum_x_texture, momentum_z_texture,
			sediment_texture, obstacle_texture, flux_texture]:
		wrapper.texture_rd_rid = RID()
	if solver != null:
		solver.release()

