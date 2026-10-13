extends SceneTree

const WATER_SCENE := preload("res://tests/visual_water_alignment/prototypes/reference_fixed.tscn")
const COUPLED_SCENE := preload("res://scenes/components/water_visual/reference_coupled.tscn")
const UniformSnapshot := preload("res://scripts/visual/water_render_uniform_snapshot.gd")
const RenderProfile := preload("res://scripts/visual/water_render_profile.gd")
const WaveWorkload := preload("res://scripts/visual/water_render_wave_workload.gd")

var case_id := "water"
var output_dir := ""
var run_id := ""
var render_profile_path := ""
var profile_wave_workload_id := "single_packet_v1"
var render_profile := {}
var render_profile_sha256 := ""
var capture_tick := 60
var frames := 0
var with_wave := false
var eta_normals := false
var screen_optics := false
var screen_deep_scatter_scale := 1.0
var optical_shallow_preserve := false
var screen_sky_reflection_scale := 1.0
var screen_fresnel_debug := false
var screen_abs_fresnel := false
var screen_face_normal := false
var screen_scene_reflection := false
var screen_reflection_debug := false
var screen_bed_only := false
var capability_probe := false
var shallow_extinction_m := 0.11
var planar_reflection_probe := false
var planar_reflection_water := false
var planar_reflection_debug := false
var planar_reflection_projected := false
var planar_reflection_size := Vector2i(960, 540)
var depth_bands := false
var write_optical_layers := false
var write_foam_flow_detail := false
var write_shoreline_mask := false
var write_shore_contour_candidate := false
var write_bed_only_multiview := false
var write_depth_bands_multiview := false
var write_contact_alpha_map := false
var write_shore_source_map := false
var write_contact_foam_source := false
var write_contact_foam_candidate := false
var write_contact_front_gate_candidate := false
var write_contact_wide_band_candidate := false
var write_contact_relaxed_front_candidate := false
var write_contact_history_candidate := false
var write_independent_contact_history := false
var write_contact_depth_map := false
var write_contact_height_map := false
var write_contact_flat_crest := false
var write_contact_shared_bed := false
var write_vertex_fragment_delta := false
var write_visible_bed_height := false
var write_contact_residual := false
var write_wet_finish_off := false
var write_wet_trace_candidate := false
var write_refraction_edge := false
var foreground_occluder := false
var transparent_foreground_occluder := false
var submerged_transparent_occluder := false
var foreground_multiview := false
var foreground_sweep := false
var write_caustic_strengths := false
var write_caustic_scales := false
var write_caustic_times := false
var write_caustic_depth_composite := false
var write_caustic_recovery := false
var write_caustic_recovery_times := false
var caustic_recovery_scale := 1.0
var topdown_camera := false
var orthographic_shore_probe := false
var write_extinction_sweep := false
var write_optical_contributors := false
var optical_multiview := false
var refraction_scale := 0.0
var screen_world_glint := false
var screen_world_glint_opposite := false
var depth_guard := true
var require_1080p := false
var pause_hold_ms := 0
var resume_target_ticks: Array[int] = []
var readback_foam := false
var write_foam_history := false
var write_water_field := false
var write_substep_trace := false
var write_bed_fields := false
var write_wetness_field := false
var write_previous_foam := false
var readbacks := {}
var crest_height_m := 0.0
var local_back_cells := 7.5
var local_face_cells := 1.8
var local_lift_depth_scale := 1.5
var crest_shore_depth_m := 0.0
var curl_forward_m := 0.0
var local_overturn_m := 0.0
var crest_white_face := false
var crest_span_smoothing := false
var crest_depth_gate_bypass := false
var geometry_silhouette := false
var geometry_alpha := 1.0
var geometry_keep_alpha := false
var geometry_keep_color := false
var crest_fragment_foam := false
var crest_broken_core := false
var offshore_core := false
var offshore_core_broken := false
var offshore_core_crown := false
var front_face_rim_tone := false
var front_face_foam_gate := false
var front_face_source_gate := false
var depth_write := false
var depth_prepass := false
var crest_curtain := false
var crest_ribbon := false
var crest_ribbon_body := false
var crest_ribbon_attached := false
var crest_ribbon_smooth_mask := false
var crest_rise_ribbon := false
var crest_solid_lip := false
var crest_water_body := false
var crest_lip_only := false
var crest_ribbon_depth_write := false
var crest_row_min := 0
var crest_row_max := 255
var shore_vertex_project := false
var porous_foam := false
var foam_overlay := false
var foam_splats := false
var foam_splats_jitter := false
var foam_front_splats := false
var foam_front_local_dense := false
var foam_front_local_diameter_px := 3.5
var foam_front_smooth := false
var foam_splats_fine := false
var foam_front_raised := false
var foam_front_pixel_sized := false
var crest_volume := false
var crest_volume_debug := false
var local_front_profile := false
var local_front_wide_field := false
var local_front_volume := false
var local_front_segments := false
var local_front_continuous_lip := false
var branch_face := false
var branch_face_capped := false
var branch_face_2d := false
var branch_face_patches := false
var branch_face_row_center := false
var branch_face_soft_material := false
var branch_face_surface_join := false
var foam_suppressed := false
var foam_overlay_debug := false
var foam_overlay_coverage := false
var front_profile := false
var front_foam := false
var crest_smooth_window := false
var crest_forward_toe := false
var crest_main_flat := false
var no_main_foam := false
var shared_boundary := false
var unified_curl := false
var unified_debug := false
var unified_sealed := false
var unified_variable := false
var unified_porous_cap := false
var unified_dense := false
var unified_smooth_profile := false
var unified_no_depth := false
var unified_opaque := false
var unified_sparse_cap := false
var unified_supported_front := false
var unified_local_support := false
var unified_2d_support := false
var unified_expanded_front_range := false
var unified_centered_base := false
var unified_monotonic_base := false
var unified_field_base := false
var unified_localized_base := false
var unified_inactive_anchor := false
var unified_adaptive_anchor := false
var unified_alpha_seal := false
var unified_fragment_wet := false
var unified_wet_toe := false
var unified_smooth_support := false
var unified_body_scale := 1.0
var unified_overturn := false
var unified_layer_debug := false
var unified_broad_back := false
var unified_overturn_cap := false
var unified_surface_probe := 0
var unified_front_wall := false
var unified_row_min := 0
var unified_row_max := 256
var rise_crest := false
var front_field := false
var write_front_field := false
var write_local_front_field := false
var integrated_fold_m := 0.0
var wavefront_camera := false
var reverse_wavefront_camera := false
var sunward_camera := false
var wavefront_center_x_m := 3.6
var wavefront_center_z_m := -5.0
var wavefront_center_z_valid := true
var wavefront_center_x_valid := true
var crest_profile_camera := false
var irregular_foam := false
var aperiodic_foam := false
var offshore_foam_source := false
var front_band_foam_source := false
var front_foam_blend := false
var front_foam_ribbon := false
var broad_crest := false
var coupled_caustics := false
var no_caustics := false
var cell_caustics := false
var fold_caustics := false
var sync_boundary_readback := false
var shared_bed_triangles := false
var midpoint_clip := false
var radial_shore := false
var shore_unscaled_depth := false
var shore_linear_weights := false
var shoreline_debug := false
var subdivision_override := 0
var smooth_reference_shore := false
var natural_reference_shore := false
var structured_reference_bed := false
var sculpted_reference_bed := false
var lobed_reference_bed := false
var branched_reference_bed := false
var estuary_reference_bed := false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_id = arg.trim_prefix("--case=")
		elif arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--profile="):
			render_profile_path = arg.trim_prefix("--profile=")
		elif arg.begins_with("--wave-workload="):
			profile_wave_workload_id = arg.trim_prefix("--wave-workload=")
		elif arg.begins_with("--tick="):
			capture_tick = int(arg.trim_prefix("--tick="))
		elif arg == "--wave":
			with_wave = true
		elif arg == "--eta-normals":
			eta_normals = true
		elif arg == "--screen-optics":
			screen_optics = true
		elif arg == "--screen-world-glint":
			screen_world_glint = true
		elif arg == "--screen-world-glint-opposite":
			screen_world_glint = true
			screen_world_glint_opposite = true
		elif arg.begins_with("--screen-deep-scatter-scale="):
			screen_deep_scatter_scale = float(arg.trim_prefix("--screen-deep-scatter-scale="))
		elif arg == "--optical-shallow-preserve":
			optical_shallow_preserve = true
		elif arg.begins_with("--screen-sky-reflection-scale="):
			screen_sky_reflection_scale = float(arg.trim_prefix("--screen-sky-reflection-scale="))
		elif arg == "--screen-fresnel-debug":
			screen_fresnel_debug = true
		elif arg == "--screen-abs-fresnel":
			screen_abs_fresnel = true
		elif arg == "--screen-face-normal":
			screen_face_normal = true
			screen_abs_fresnel = true
		elif arg == "--screen-scene-reflection":
			screen_optics = true
			screen_face_normal = true
			screen_abs_fresnel = true
			screen_scene_reflection = true
		elif arg == "--screen-reflection-debug":
			screen_optics = true
			screen_face_normal = true
			screen_abs_fresnel = true
			screen_scene_reflection = true
			screen_reflection_debug = true
		elif arg == "--screen-bed-only":
			screen_bed_only = true
		elif arg == "--capability-probe":
			capability_probe = true
		elif arg.begins_with("--shallow-extinction="):
			shallow_extinction_m = float(arg.trim_prefix("--shallow-extinction="))
		elif arg == "--planar-reflection-probe":
			planar_reflection_probe = true
		elif arg == "--planar-reflection-water":
			planar_reflection_probe = true
			planar_reflection_water = true
			screen_optics = true
			screen_face_normal = true
			screen_abs_fresnel = true
		elif arg == "--planar-reflection-debug":
			planar_reflection_probe = true
			planar_reflection_water = true
			planar_reflection_debug = true
			screen_optics = true
			screen_face_normal = true
			screen_abs_fresnel = true
		elif arg == "--planar-reflection-projected":
			planar_reflection_probe = true
			planar_reflection_water = true
			planar_reflection_projected = true
			screen_optics = true
			screen_face_normal = true
			screen_abs_fresnel = true
		elif arg.begins_with("--planar-reflection-size="):
			var size_token := arg.trim_prefix("--planar-reflection-size=")
			if size_token == "half":
				planar_reflection_size = Vector2i(480, 270)
			elif size_token != "full":
				planar_reflection_size = Vector2i.ZERO
		elif arg == "--depth-bands":
			depth_bands = true
		elif arg == "--write-optical-layers":
			write_optical_layers = true
		elif arg == "--write-refraction-edge":
			write_refraction_edge = true
		elif arg == "--foreground-occluder":
			foreground_occluder = true
		elif arg == "--transparent-foreground-occluder":
			transparent_foreground_occluder = true
		elif arg == "--submerged-transparent-occluder":
			submerged_transparent_occluder = true
		elif arg == "--foreground-multiview":
			foreground_multiview = true
		elif arg == "--foreground-sweep":
			foreground_sweep = true
		elif arg == "--write-caustic-strengths":
			write_caustic_strengths = true
		elif arg == "--write-caustic-scales":
			write_caustic_scales = true
		elif arg == "--write-caustic-times":
			write_caustic_times = true
		elif arg == "--write-caustic-depth-composite":
			write_caustic_depth_composite = true
		elif arg == "--write-caustic-recovery":
			write_caustic_recovery = true
		elif arg == "--write-caustic-recovery-times":
			write_caustic_recovery_times = true
		elif arg.begins_with("--caustic-recovery-scale="):
			caustic_recovery_scale = float(arg.trim_prefix(
				"--caustic-recovery-scale="))
		elif arg == "--write-extinction-sweep":
			write_extinction_sweep = true
		elif arg == "--write-optical-contributors":
			write_optical_contributors = true
		elif arg == "--optical-multiview":
			optical_multiview = true
		elif arg.begins_with("--refraction-scale="):
			refraction_scale = float(arg.trim_prefix("--refraction-scale="))
		elif arg == "--no-depth-guard":
			depth_guard = false
		elif arg == "--require-1080p":
			require_1080p = true
		elif arg.begins_with("--pause-hold-ms="):
			pause_hold_ms = int(arg.trim_prefix("--pause-hold-ms="))
		elif arg.begins_with("--resume-target-ticks="):
			for tick_text in arg.trim_prefix("--resume-target-ticks=").split(","):
				resume_target_ticks.append(int(tick_text))
		elif arg == "--readback-foam":
			readback_foam = true
		elif arg == "--write-water-field":
			readback_foam = true
			write_water_field = true
		elif arg == "--write-substep-trace":
			write_substep_trace = true
		elif arg == "--write-bed-fields":
			readback_foam = true
			write_bed_fields = true
		elif arg == "--write-wetness-field":
			readback_foam = true
			write_wetness_field = true
		elif arg == "--write-previous-foam":
			readback_foam = true
			write_previous_foam = true
		elif arg == "--write-foam-history":
			readback_foam = true
			write_foam_history = true
		elif arg == "--write-foam-flow-detail":
			write_foam_flow_detail = true
		elif arg == "--write-shoreline-mask":
			write_shoreline_mask = true
		elif arg == "--write-shore-contour-candidate":
			write_shore_contour_candidate = true
		elif arg == "--write-bed-only-multiview":
			write_bed_only_multiview = true
		elif arg == "--write-depth-bands-multiview":
			write_depth_bands_multiview = true
		elif arg == "--write-contact-alpha-map":
			write_contact_alpha_map = true
		elif arg == "--write-shore-source-map":
			write_shore_source_map = true
		elif arg == "--write-contact-foam-source":
			write_contact_foam_source = true
			readback_foam = true
			write_previous_foam = true
		elif arg == "--write-contact-foam-candidate":
			write_contact_foam_candidate = true
			readback_foam = true
			write_previous_foam = true
		elif arg == "--write-contact-front-gate-candidate":
			write_contact_front_gate_candidate = true
			readback_foam = true
			write_previous_foam = true
		elif arg == "--write-contact-wide-band-candidate":
			write_contact_wide_band_candidate = true
			readback_foam = true
			write_previous_foam = true
		elif arg == "--write-contact-relaxed-front-candidate":
			write_contact_relaxed_front_candidate = true
			readback_foam = true
			write_previous_foam = true
		elif arg == "--write-contact-history-candidate":
			write_contact_history_candidate = true
			readback_foam = true
			write_previous_foam = true
		elif arg == "--write-independent-contact-history":
			write_independent_contact_history = true
			local_front_profile = true
			readback_foam = true
			write_previous_foam = true
			write_water_field = true
			write_local_front_field = true
		elif arg == "--write-contact-depth-map":
			write_contact_depth_map = true
		elif arg == "--write-contact-height-map":
			write_contact_height_map = true
		elif arg == "--write-contact-flat-crest":
			write_contact_flat_crest = true
		elif arg == "--write-contact-shared-bed":
			write_contact_shared_bed = true
		elif arg == "--write-vertex-fragment-delta":
			write_vertex_fragment_delta = true
		elif arg == "--write-visible-bed-height":
			write_visible_bed_height = true
		elif arg == "--write-contact-residual":
			write_contact_residual = true
		elif arg == "--write-wet-finish-off":
			write_wet_finish_off = true
		elif arg == "--write-wet-trace-candidate":
			write_wet_trace_candidate = true
		elif arg == "--topdown-camera":
			topdown_camera = true
		elif arg == "--orthographic-shore-probe":
			orthographic_shore_probe = true
		elif arg.begins_with("--crest-height="):
			crest_height_m = float(arg.trim_prefix("--crest-height="))
		elif arg.begins_with("--local-back-cells="):
			local_back_cells = float(arg.trim_prefix("--local-back-cells="))
		elif arg.begins_with("--local-face-cells="):
			local_face_cells = float(arg.trim_prefix("--local-face-cells="))
		elif arg.begins_with("--local-lift-depth-scale="):
			local_lift_depth_scale = float(arg.trim_prefix("--local-lift-depth-scale="))
		elif arg.begins_with("--crest-shore-depth="):
			crest_shore_depth_m = float(arg.trim_prefix("--crest-shore-depth="))
		elif arg.begins_with("--curl-forward="):
			curl_forward_m = float(arg.trim_prefix("--curl-forward="))
		elif arg.begins_with("--local-overturn="):
			local_overturn_m = float(arg.trim_prefix("--local-overturn="))
		elif arg == "--crest-white-face":
			crest_white_face = true
		elif arg == "--crest-span-smoothing":
			crest_span_smoothing = true
		elif arg == "--crest-depth-gate-bypass":
			crest_depth_gate_bypass = true
		elif arg == "--geometry-silhouette":
			geometry_silhouette = true
		elif arg.begins_with("--geometry-alpha="):
			geometry_alpha = float(arg.trim_prefix("--geometry-alpha="))
		elif arg == "--geometry-keep-alpha":
			geometry_keep_alpha = true
		elif arg == "--geometry-keep-color":
			geometry_keep_color = true
		elif arg == "--crest-fragment-foam":
			crest_fragment_foam = true
		elif arg == "--crest-broken-core":
			crest_broken_core = true
			crest_white_face = true
		elif arg == "--offshore-core":
			offshore_core = true
		elif arg == "--offshore-core-broken":
			offshore_core = true
			offshore_core_broken = true
		elif arg == "--front-face-rim-tone":
			front_face_rim_tone = true
		elif arg == "--front-face-foam-gate":
			front_face_foam_gate = true
		elif arg == "--front-face-source-gate":
			front_face_source_gate = true
		elif arg == "--depth-write":
			depth_write = true
		elif arg == "--depth-prepass":
			depth_prepass = true
		elif arg == "--crest-curtain":
			crest_curtain = true
		elif arg == "--crest-ribbon":
			crest_ribbon = true
		elif arg == "--crest-ribbon-body":
			crest_ribbon = true
			crest_ribbon_body = true
		elif arg == "--crest-ribbon-attached":
			crest_ribbon_attached = true
		elif arg == "--crest-ribbon-smooth-mask":
			crest_ribbon_attached = true
			crest_ribbon_smooth_mask = true
		elif arg == "--crest-rise-ribbon":
			crest_rise_ribbon = true
		elif arg == "--crest-solid-lip":
			crest_solid_lip = true
			crest_rise_ribbon = true
			front_field = true
			rise_crest = true
			depth_write = true
		elif arg == "--crest-water-body":
			crest_water_body = true
			crest_solid_lip = true
			crest_rise_ribbon = true
			front_field = true
			rise_crest = true
			depth_write = true
		elif arg == "--crest-lip-only":
			crest_lip_only = true
		elif arg == "--crest-ribbon-depth-write":
			crest_ribbon_depth_write = true
		elif arg.begins_with("--crest-row-min="):
			crest_row_min = int(arg.trim_prefix("--crest-row-min="))
		elif arg.begins_with("--crest-row-max="):
			crest_row_max = int(arg.trim_prefix("--crest-row-max="))
		elif arg == "--shore-vertex-project":
			shore_vertex_project = true
		elif arg == "--porous-foam":
			porous_foam = true
			irregular_foam = true
		elif arg == "--foam-overlay":
			foam_overlay = true
			irregular_foam = true
		elif arg == "--foam-splats":
			foam_splats = true
		elif arg == "--foam-splats-jitter":
			foam_splats = true
			foam_splats_jitter = true
		elif arg == "--foam-front-splats":
			foam_splats = true
			foam_splats_jitter = true
			foam_front_splats = true
			front_field = true
		elif arg == "--foam-front-only":
			foam_front_splats = true
			front_field = true
		elif arg == "--foam-front-local-dense":
			foam_front_local_dense = true
			local_front_profile = true
			depth_write = true
		elif arg.begins_with("--foam-front-local-diameter="):
			foam_front_local_diameter_px = float(arg.trim_prefix(
				"--foam-front-local-diameter="))
		elif arg == "--foam-front-smooth":
			foam_splats = true
			foam_splats_jitter = true
			foam_front_splats = true
			foam_front_smooth = true
			front_field = true
		elif arg == "--foam-splats-fine":
			foam_splats_fine = true
		elif arg == "--foam-front-raised":
			foam_front_raised = true
		elif arg == "--foam-front-pixel-sized":
			foam_front_pixel_sized = true
		elif arg == "--crest-volume":
			crest_volume = true
			front_field = true
			depth_write = true
		elif arg == "--crest-volume-debug":
			crest_volume = true
			crest_volume_debug = true
			front_field = true
			depth_write = true
		elif arg == "--local-front-profile":
			local_front_profile = true
			depth_write = true
		elif arg == "--local-front-wide-field":
			local_front_profile = true
			local_front_wide_field = true
			depth_write = true
		elif arg == "--local-front-volume":
			local_front_profile = true
			local_front_volume = true
			crest_volume = true
			front_field = true
			depth_write = true
		elif arg == "--local-front-segments":
			local_front_profile = true
			local_front_segments = true
			depth_write = true
		elif arg == "--local-front-continuous-lip":
			local_front_profile = true
			local_front_continuous_lip = true
			front_field = true
			depth_write = true
		elif arg == "--branch-face":
			branch_face = true
		elif arg == "--branch-face-capped":
			branch_face = true
			branch_face_capped = true
		elif arg == "--branch-face-2d":
			branch_face = true
			branch_face_capped = true
			branch_face_2d = true
		elif arg == "--branch-face-patches":
			branch_face = true
			branch_face_capped = true
			branch_face_2d = true
			branch_face_patches = true
		elif arg == "--branch-face-row-center":
			branch_face = true
			branch_face_capped = true
			branch_face_row_center = true
		elif arg == "--branch-face-soft-material":
			branch_face = true
			branch_face_capped = true
			branch_face_soft_material = true
		elif arg == "--branch-face-surface-join":
			branch_face = true
			branch_face_capped = true
			branch_face_surface_join = true
		elif arg == "--write-local-front-field":
			local_front_profile = true
			write_local_front_field = true
			readback_foam = true
			depth_write = true
		elif arg == "--foam-suppressed":
			foam_suppressed = true
		elif arg == "--foam-overlay-debug":
			foam_overlay = true
			foam_overlay_debug = true
		elif arg == "--foam-overlay-coverage":
			foam_overlay = true
			foam_overlay_coverage = true
		elif arg == "--front-profile":
			front_profile = true
			rise_crest = true
			front_field = true
			depth_write = true
		elif arg == "--front-foam":
			front_foam = true
			rise_crest = true
			front_field = true
			depth_write = true
		elif arg == "--crest-smooth-window":
			crest_smooth_window = true
		elif arg == "--crest-forward-toe":
			crest_forward_toe = true
			crest_smooth_window = true
		elif arg == "--crest-main-flat":
			crest_main_flat = true
		elif arg == "--no-main-foam":
			no_main_foam = true
		elif arg == "--shared-boundary":
			shared_boundary = true
		elif arg == "--unified-curl":
			unified_curl = true
			rise_crest = true
			front_field = true
			depth_write = true
		elif arg == "--unified-debug":
			unified_debug = true
		elif arg == "--unified-sealed":
			unified_sealed = true
		elif arg == "--unified-variable":
			unified_variable = true
		elif arg == "--unified-porous-cap":
			unified_porous_cap = true
		elif arg == "--unified-dense":
			unified_dense = true
		elif arg == "--unified-smooth-profile":
			unified_smooth_profile = true
		elif arg == "--unified-no-depth":
			unified_no_depth = true
		elif arg == "--unified-opaque":
			unified_opaque = true
		elif arg == "--unified-sparse-cap":
			unified_sparse_cap = true
		elif arg == "--unified-supported-front":
			unified_supported_front = true
		elif arg == "--unified-local-support":
			unified_local_support = true
		elif arg == "--unified-2d-support":
			unified_2d_support = true
		elif arg == "--unified-expanded-front-range":
			unified_expanded_front_range = true
		elif arg == "--unified-centered-base":
			unified_centered_base = true
		elif arg == "--unified-monotonic-base":
			unified_monotonic_base = true
		elif arg == "--unified-field-base":
			unified_field_base = true
		elif arg == "--unified-localized-base":
			unified_localized_base = true
		elif arg == "--unified-inactive-anchor":
			unified_inactive_anchor = true
		elif arg == "--unified-adaptive-anchor":
			unified_adaptive_anchor = true
		elif arg == "--unified-alpha-seal":
			unified_alpha_seal = true
		elif arg == "--unified-fragment-wet":
			unified_fragment_wet = true
		elif arg == "--unified-wet-toe":
			unified_wet_toe = true
		elif arg == "--unified-smooth-support":
			unified_smooth_support = true
		elif arg.begins_with("--unified-body-scale="):
			unified_body_scale = float(arg.trim_prefix("--unified-body-scale="))
		elif arg == "--unified-overturn":
			unified_overturn = true
		elif arg == "--unified-layer-debug":
			unified_layer_debug = true
		elif arg == "--unified-broad-back":
			unified_broad_back = true
		elif arg == "--unified-overturn-cap":
			unified_overturn_cap = true
		elif arg.begins_with("--unified-surface-probe="):
			unified_surface_probe = int(arg.trim_prefix("--unified-surface-probe="))
		elif arg == "--unified-front-wall":
			unified_front_wall = true
		elif arg.begins_with("--unified-row-min="):
			unified_row_min = int(arg.trim_prefix("--unified-row-min="))
		elif arg.begins_with("--unified-row-max="):
			unified_row_max = int(arg.trim_prefix("--unified-row-max="))
		elif arg == "--rise-crest":
			rise_crest = true
		elif arg == "--front-field":
			front_field = true
		elif arg == "--write-front-field":
			front_field = true
			write_front_field = true
			readback_foam = true
		elif arg.begins_with("--integrated-fold="):
			integrated_fold_m = float(arg.trim_prefix("--integrated-fold="))
		elif arg == "--wavefront-camera":
			wavefront_camera = true
		elif arg == "--wavefront-reverse-camera":
			wavefront_camera = true
			reverse_wavefront_camera = true
		elif arg == "--sunward-camera":
			sunward_camera = true
		elif arg.begins_with("--wavefront-center-x="):
			var center_text := arg.trim_prefix("--wavefront-center-x=")
			wavefront_center_x_valid = center_text.is_valid_float()
			if wavefront_center_x_valid:
				wavefront_center_x_m = center_text.to_float()
		elif arg.begins_with("--wavefront-center-z="):
			var center_z_text := arg.trim_prefix("--wavefront-center-z=")
			wavefront_center_z_valid = center_z_text.is_valid_float()
			if wavefront_center_z_valid:
				wavefront_center_z_m = center_z_text.to_float()
		elif arg == "--crest-profile-camera":
			crest_profile_camera = true
		elif arg == "--irregular-foam":
			irregular_foam = true
		elif arg == "--aperiodic-foam":
			aperiodic_foam = true
		elif arg == "--offshore-foam-source":
			offshore_foam_source = true
		elif arg == "--front-band-foam-source":
			front_band_foam_source = true
		elif arg == "--front-foam-blend":
			front_foam_blend = true
		elif arg == "--front-foam-ribbon":
			front_foam_ribbon = true
		elif arg == "--broad-crest":
			broad_crest = true
		elif arg == "--coupled-caustics":
			coupled_caustics = true
		elif arg == "--no-caustics":
			no_caustics = true
		elif arg == "--cell-caustics":
			cell_caustics = true
		elif arg == "--fold-caustics":
			fold_caustics = true
		elif arg == "--sync-boundary-readback":
			sync_boundary_readback = true
		elif arg == "--shared-bed-triangles":
			shared_bed_triangles = true
		elif arg == "--midpoint-clip":
			midpoint_clip = true
		elif arg == "--radial-shore":
			radial_shore = true
		elif arg == "--shore-unscaled-depth":
			shore_unscaled_depth = true
		elif arg == "--shore-linear-weights":
			shore_linear_weights = true
		elif arg == "--shoreline-debug":
			shoreline_debug = true
		elif arg.begins_with("--subdivision="):
			subdivision_override = int(arg.trim_prefix("--subdivision="))
		elif arg == "--smooth-reference-shore":
			smooth_reference_shore = true
		elif arg == "--natural-reference-shore":
			natural_reference_shore = true
		elif arg == "--structured-reference-bed":
			structured_reference_bed = true
		elif arg == "--sculpted-reference-bed":
			sculpted_reference_bed = true
		elif arg == "--lobed-reference-bed":
			lobed_reference_bed = true
		elif arg == "--branched-reference-bed":
			branched_reference_bed = true
		elif arg == "--estuary-reference-bed":
			estuary_reference_bed = true
	if crest_lip_only:
		rise_crest = false
	call_deferred("_run")


func _run() -> void:
	if profile_wave_workload_id not in ["none", "single_packet_v1", "continuous_packets_v1"] or \
			(render_profile_path.is_empty() and with_wave and \
			profile_wave_workload_id != "single_packet_v1"):
		_fail("invalid profile wave workload")
		return
	if not render_profile_path.is_empty():
		var allowed := ["--wave", "--require-1080p", "--capability-probe",
			"--readback-foam", "--write-water-field", "--write-bed-fields",
			"--write-wetness-field",
			"--write-foam-history",
			"--write-foam-flow-detail",
			"--write-shoreline-mask", "--write-shore-contour-candidate",
			"--write-bed-only-multiview",
			"--write-depth-bands-multiview",
			"--write-contact-alpha-map",
			"--write-shore-source-map",
			"--write-contact-foam-source",
			"--write-contact-foam-candidate",
			"--write-contact-front-gate-candidate",
			"--write-contact-wide-band-candidate",
			"--write-contact-relaxed-front-candidate",
			"--write-contact-history-candidate",
			"--write-independent-contact-history",
			"--write-contact-depth-map",
			"--write-contact-height-map",
			"--write-contact-flat-crest",
			"--write-contact-shared-bed",
			"--write-vertex-fragment-delta",
			"--write-visible-bed-height",
			"--write-contact-residual",
			"--write-wet-finish-off",
			"--write-wet-trace-candidate",
			"--write-previous-foam",
			"--write-optical-layers",
			"--write-refraction-edge",
			"--foreground-occluder",
			"--transparent-foreground-occluder",
			"--submerged-transparent-occluder",
			"--foreground-multiview",
			"--foreground-sweep",
			"--write-caustic-strengths",
			"--write-caustic-scales",
			"--write-caustic-times",
			"--write-caustic-depth-composite",
			"--write-caustic-recovery",
			"--write-caustic-recovery-times",
			"--topdown-camera", "--orthographic-shore-probe",
			"--planar-reflection-probe", "--planar-reflection-water",
			"--planar-reflection-debug", "--planar-reflection-projected",
			"--write-extinction-sweep",
			"--write-optical-contributors",
			"--optical-multiview",
			"--write-local-front-field", "--wavefront-camera",
			"--wavefront-reverse-camera",
			"--optical-shallow-preserve", "--branch-face-2d"]
		for arg in OS.get_cmdline_user_args():
			if arg in allowed or arg.begins_with("--case=") or \
				arg.begins_with("--caustic-recovery-scale=") or \
					arg.begins_with("--output=") or arg.begins_with("--run-id=") or \
					arg.begins_with("--tick=") or arg.begins_with("--profile=") or \
					arg.begins_with("--wave-workload=") or \
					arg.begins_with("--wavefront-center-x=") or \
					arg.begins_with("--wavefront-center-z="):
				continue
			_fail("profile mode forbids visual CLI override: " + arg)
			return
		var loaded: Dictionary = RenderProfile.load_file(render_profile_path)
		if not loaded.get("ok", false):
			_fail("render profile: " + String(loaded.get("code", "invalid")))
			return
		render_profile = loaded.profile
		render_profile_sha256 = loaded.source_sha256
		var requested_fixture := "water_render_demo_v2" if case_id == "water" else \
			"water_render_coupled_v2"
		if requested_fixture not in render_profile.target_fixture_ids:
			_fail("render profile fixture mismatch")
			return
		var cap: Dictionary = render_profile.capabilities
		var visual: Dictionary = render_profile.visual
		eta_normals = cap.eta_normals.enabled
		screen_optics = cap.screen_optics.enabled
		optical_shallow_preserve = optical_shallow_preserve or \
			visual.get("shallow_preserve", false)
		screen_face_normal = visual.face_normal
		screen_abs_fresnel = visual.face_normal
		depth_write = visual.depth_write
		crest_height_m = visual.crest_height_m
		local_front_profile = cap.local_front.enabled
		offshore_core = visual.get("offshore_core", false)
		offshore_core_broken = visual.get("offshore_core_broken", false)
		offshore_core_crown = visual.get("offshore_core_crown", false)
		natural_reference_shore = true
		structured_reference_bed = true
		lobed_reference_bed = render_profile.reference_bed == "estuary_branched_v1"
		branched_reference_bed = lobed_reference_bed
		estuary_reference_bed = lobed_reference_bed
		shallow_extinction_m = visual.shallow_extinction_m
		refraction_scale = visual.refraction_scale
		fold_caustics = cap.fold_caustics.enabled
		coupled_caustics = cap.fold_caustics.enabled and case_id == "coupled"
		no_main_foam = not cap.main_foam.enabled
		subdivision_override = render_profile.render_subdivision
		capability_probe = true
	if smooth_reference_shore and natural_reference_shore:
		_fail("reference shore variants are mutually exclusive")
		return
	if not wavefront_center_x_valid or wavefront_center_x_m < -12.0 or \
			wavefront_center_x_m > 12.0 or \
			(wavefront_center_x_m != 3.6 and not wavefront_camera) or \
			not wavefront_center_z_valid or wavefront_center_z_m < -12.0 or \
			wavefront_center_z_m > 12.0 or \
			(wavefront_center_z_m != -5.0 and not wavefront_camera):
		_fail("invalid wavefront diagnostic camera center")
		return
	if local_front_wide_field and not render_profile_path.is_empty():
		_fail("wide local front field is prototype only")
		return
	if structured_reference_bed and not natural_reference_shore:
		_fail("structured reference bed requires natural reference shore")
		return
	if sculpted_reference_bed and (not structured_reference_bed or not render_profile_path.is_empty()):
		_fail("sculpted reference bed requires isolated structured prototype")
		return
	var profile_estuary_bed: bool = not render_profile.is_empty() and \
		render_profile.reference_bed == "estuary_branched_v1"
	if lobed_reference_bed and (not natural_reference_shore or \
			sculpted_reference_bed or (not render_profile_path.is_empty() and \
			not profile_estuary_bed)):
		_fail("lobed reference bed requires isolated natural-shore prototype")
		return
	if branched_reference_bed and (not lobed_reference_bed or
			not structured_reference_bed or (not render_profile_path.is_empty() and \
			not profile_estuary_bed)):
		_fail("branched reference bed requires isolated lobed structured prototype")
		return
	if estuary_reference_bed and (not branched_reference_bed or
			(not render_profile_path.is_empty() and not profile_estuary_bed)):
		_fail("estuary reference bed requires isolated branched prototype")
		return
	if screen_bed_only and not (local_front_profile and screen_optics):
		_fail("screen bed diagnostic requires local front screen optics")
		return
	if write_optical_layers and (not local_front_profile or not screen_optics):
		_fail("optical layer diagnostic requires local front screen optics")
		return
	if write_refraction_edge and (not local_front_profile or not screen_optics):
		_fail("refraction edge diagnostic requires local front screen optics")
		return
	if (foreground_occluder or transparent_foreground_occluder or \
			submerged_transparent_occluder) and \
			not write_refraction_edge:
		_fail("foreground occluder requires refraction edge diagnostic")
		return
	if write_caustic_strengths and not local_front_profile:
		_fail("caustic strength diagnostic requires staging profile")
		return
	if write_caustic_scales and not local_front_profile:
		_fail("caustic scale diagnostic requires staging profile")
		return
	if write_caustic_times and not local_front_profile:
		_fail("caustic time diagnostic requires staging profile")
		return
	if write_caustic_depth_composite and (not topdown_camera or not local_front_profile or
			not screen_optics):
		_fail("caustic depth composite requires staging screen optics and topdown")
		return
	if write_caustic_recovery and (not topdown_camera or not local_front_profile or
			not screen_optics):
		_fail("caustic recovery requires staging screen optics and topdown")
		return
	if write_caustic_recovery_times and not write_caustic_recovery:
		_fail("caustic recovery times require recovery capture")
		return
	if caustic_recovery_scale < 1.0 or caustic_recovery_scale > 3.0 or \
			(caustic_recovery_scale != 1.0 and not write_caustic_recovery):
		_fail("caustic recovery scale requires recovery capture and range [1,3]")
		return
	if write_extinction_sweep and (not local_front_profile or not screen_optics):
		_fail("extinction sweep requires staging screen optics")
		return
	if write_optical_contributors and (not local_front_profile or not screen_optics):
		_fail("optical contributor diagnostic requires staging screen optics")
		return
	if optical_multiview and not write_optical_contributors:
		_fail("optical multiview requires optical contributors")
		return
	if optical_shallow_preserve and not (local_front_profile and screen_optics):
		_fail("optical shallow preserve requires local front screen optics")
		return
	if screen_world_glint and not (local_front_profile and screen_optics and eta_normals):
		_fail("world glint requires local front, screen optics and eta normals")
		return
	if shallow_extinction_m < 0.11 or shallow_extinction_m > 0.35 or \
			(shallow_extinction_m != 0.11 and not (local_front_profile and screen_optics)):
		_fail("shallow extinction requires local front screen optics and 0.11-0.35m")
		return
	if case_id not in ["water", "coupled"] or output_dir.is_empty() or run_id.is_empty() or capture_tick < 1 or planar_reflection_size == Vector2i.ZERO or (planar_reflection_size != Vector2i(960, 540) and not planar_reflection_probe) or pause_hold_ms < 0 or pause_hold_ms > 10000 or absf(refraction_scale) > 0.25 or screen_deep_scatter_scale < 0.0 or screen_deep_scatter_scale > 1.0 or screen_sky_reflection_scale < 0.0 or screen_sky_reflection_scale > 1.0 or crest_height_m < 0.0 or crest_height_m > (0.4 if local_front_profile and depth_write else 0.25) or crest_shore_depth_m < 0.0 or crest_shore_depth_m > 0.30 or curl_forward_m < 0.0 or curl_forward_m > 0.20 or integrated_fold_m < 0.0 or integrated_fold_m > 0.50 or (integrated_fold_m > 0.0 and (not depth_write or crest_height_m <= 0.0)) or (rise_crest and (not depth_write or crest_height_m <= 0.0 or integrated_fold_m > 0.0)) or geometry_alpha < 0.0 or geometry_alpha > 1.0 or (depth_write and depth_prepass) or (crest_ribbon_attached and (crest_ribbon_body or crest_height_m <= 0.0)) or (cell_caustics and fold_caustics) or (subdivision_override != 0 and subdivision_override not in [1, 2, 4]) or crest_row_min < 0 or crest_row_max > 255 or crest_row_min > crest_row_max:
		_fail("invalid arguments")
		return
	if not DirAccess.dir_exists_absolute(output_dir):
		_fail("output directory does not exist: " + output_dir)
		return
	if (depth_bands or screen_fresnel_debug or screen_abs_fresnel or screen_face_normal or
			screen_scene_reflection or screen_reflection_debug or planar_reflection_water or
			planar_reflection_debug or planar_reflection_projected or
			screen_deep_scatter_scale != 1.0 or screen_sky_reflection_scale != 1.0) and not local_front_profile:
		_fail("requested optical diagnostic requires --local-front-profile")
		return
	var previous_resume_tick := capture_tick
	for target_tick in resume_target_ticks:
		if target_tick <= previous_resume_tick or target_tick > 2000:
			_fail("resume targets must increase after capture tick and stay <=2000")
			return
		previous_resume_tick = target_tick
	if porous_foam and (not depth_write or rise_crest or shore_vertex_project):
		_fail("porous foam requires the isolated depth-write water shader")
		return
	if (foam_overlay or foam_suppressed) and (not depth_write or rise_crest or porous_foam or shore_vertex_project or (foam_overlay and foam_suppressed)):
		_fail("foam layering requires the isolated depth-write water shader")
		return
	if front_profile and (crest_lip_only or integrated_fold_m > 0.0):
		_fail("front profile requires the isolated rise-crest shader")
		return
	if front_foam and (front_profile or crest_lip_only or integrated_fold_m > 0.0):
		_fail("front foam requires the isolated shared-front shader")
		return
	if front_foam and crest_solid_lip and not crest_ribbon_depth_write:
		_fail("shared-front solid lip requires ribbon depth write")
		return
	if crest_smooth_window and not (front_foam and crest_solid_lip and crest_ribbon_depth_write):
		_fail("crest smooth window requires the shared-front solid lip")
		return
	if crest_main_flat and not (front_foam and crest_solid_lip and crest_ribbon_depth_write):
		_fail("flat main crest requires the shared-front solid lip")
		return
	if shared_boundary and not (front_foam and crest_forward_toe and crest_main_flat):
		_fail("shared boundary requires the flat-main forward-toe lip")
		return
	if unified_curl and (front_foam or crest_solid_lip or crest_ribbon or
			crest_rise_ribbon or shared_boundary or integrated_fold_m > 0.0):
		_fail("unified curl owns the water mesh and cannot use a separate lip")
		return
	if unified_debug and not unified_curl:
		_fail("unified debug requires the unified curl mesh")
		return
	if unified_sealed and not unified_curl:
		_fail("unified sealing requires the unified curl mesh")
		return
	if unified_variable and not (unified_curl and unified_sealed):
		_fail("unified variation requires the sealed curl mesh")
		return
	if unified_porous_cap and not (unified_curl and unified_sealed):
		_fail("unified porous cap requires the sealed curl mesh")
		return
	if unified_dense and not unified_curl:
		_fail("unified dense rows require the unified curl mesh")
		return
	if unified_smooth_profile and not unified_curl:
		_fail("unified smooth profile requires the unified curl mesh")
		return
	if unified_no_depth and not unified_curl:
		_fail("unified no-depth requires the unified curl mesh")
		return
	if unified_opaque and not (unified_curl and unified_sealed):
		_fail("unified opaque requires the sealed curl mesh")
		return
	if unified_sparse_cap and (not (unified_curl and unified_sealed) or unified_porous_cap):
		_fail("unified sparse cap requires the sealed curl mesh and excludes porous cap")
		return
	if unified_supported_front and not unified_curl:
		_fail("unified supported front requires the unified curl mesh")
		return
	if unified_local_support and (not unified_curl or unified_supported_front):
		_fail("unified local support requires the curl mesh and excludes weighted front")
		return
	if unified_2d_support and (not unified_curl or local_front_profile):
		_fail("unified 2D support requires curl and excludes local-front water shader")
		return
	if unified_expanded_front_range and not (unified_curl and unified_field_base and unified_2d_support):
		_fail("expanded unified front range requires field-base curl with 2D support")
		return
	if unified_centered_base and not unified_curl:
		_fail("unified centered base requires the curl mesh")
		return
	if unified_monotonic_base and (not unified_curl or unified_centered_base):
		_fail("unified monotonic base requires the curl mesh and excludes centered base")
		return
	if unified_field_base and not (unified_curl and unified_sealed):
		_fail("unified field base requires the sealed curl mesh")
		return
	if unified_localized_base and (not unified_field_base or
			unified_centered_base or unified_monotonic_base):
		_fail("unified localized base requires field base and regular mesh coordinates")
		return
	if unified_inactive_anchor and not unified_field_base:
		_fail("unified inactive anchor requires field-based curl")
		return
	if unified_adaptive_anchor and (not front_field or unified_inactive_anchor or
			not (unified_field_base or local_front_continuous_lip)):
		_fail("adaptive row anchor requires field-based curl or continuous local lip")
		return
	if unified_alpha_seal and not (unified_curl and unified_sealed):
		_fail("unified alpha seal requires the sealed curl mesh")
		return
	if unified_fragment_wet and not (unified_curl and unified_alpha_seal):
		_fail("unified fragment wet requires the alpha-sealed curl mesh")
		return
	if unified_wet_toe and not (unified_curl and unified_field_base):
		_fail("unified wet toe requires the field-based curl mesh")
		return
	if unified_smooth_support and not (unified_curl and unified_field_base):
		_fail("unified smooth support requires the field-based curl mesh")
		return
	if unified_body_scale != 1.0 and (not unified_curl or unified_body_scale < 0.25 or unified_body_scale > 4.0):
		_fail("unified body scale requires the curl mesh and range 0.25..4.0")
		return
	if unified_overturn and not (unified_curl and unified_field_base and unified_wet_toe):
		_fail("unified overturn requires the field-based wet-toe curl mesh")
		return
	if unified_layer_debug and not (unified_curl and unified_debug):
		_fail("unified layer debug requires the unified debug curl mesh")
		return
	if unified_broad_back and not unified_overturn:
		_fail("unified broad back requires the overturn curl profile")
		return
	if unified_overturn_cap and not (unified_overturn and unified_sparse_cap):
		_fail("unified overturn cap requires the sparse overturn curl")
		return
	if unified_surface_probe != 0 and (unified_surface_probe < 1 or unified_surface_probe > 4 or
			not (unified_overturn and unified_layer_debug)):
		_fail("unified surface probe 1..4 requires overturn layer debug")
		return
	if unified_front_wall and not unified_overturn:
		_fail("unified front wall requires the overturn curl")
		return
	if (unified_row_min != 0 or unified_row_max != 256) and (not unified_layer_debug or
			unified_row_min < 0 or unified_row_max > 256 or unified_row_min >= unified_row_max):
		_fail("unified row slice requires layer debug and valid 0..256 range")
		return
	if (foam_splats or foam_front_splats) and unified_curl:
		_fail("foam splats currently sample the flat water surface; unified curl needs shared geometry")
		return
	if foam_front_local_dense and (foam_front_splats or foam_splats or
			local_front_continuous_lip or unified_curl or crest_height_m <= 0.0):
		_fail("dense local foam requires isolated local-front main water")
		return
	if (foam_front_local_diameter_px != 3.5 and not foam_front_local_dense) or \
			foam_front_local_diameter_px < 1.0 or foam_front_local_diameter_px > 12.0:
		_fail("dense local foam diameter requires 1..12px dense layer")
		return
	if foam_front_raised and not (foam_front_splats and local_front_profile and crest_height_m > 0.0):
		_fail("raised front splats require local front water and positive crest height")
		return
	if foam_front_pixel_sized and not foam_front_splats:
		_fail("pixel-sized front splats require the front splat layer")
		return
	if crest_volume and (unified_curl or rise_crest or crest_ribbon or crest_rise_ribbon or crest_curtain):
		_fail("crest volume trial requires the flat depth-writing water without another crest")
		return
	if local_front_profile and (unified_curl or rise_crest or (crest_volume and not local_front_volume) or
			crest_ribbon or crest_rise_ribbon or crest_curtain or crest_height_m <= 0.0):
		_fail("local front profile requires its own depth-writing water and positive height")
		return
	if front_foam_ribbon and not local_front_profile:
		_fail("front foam ribbon requires local front profile")
		return
	if front_band_foam_source and (not local_front_profile or offshore_foam_source):
		_fail("front-band foam source requires local front and excludes offshore source")
		return
	if crest_broken_core and (not local_front_profile or crest_fragment_foam):
		_fail("broken crest core requires local front and excludes fragment foam")
		return
	if offshore_core and not local_front_profile:
		_fail("offshore core requires local front water")
		return
	if front_face_rim_tone and (not local_front_profile or not screen_optics or
			crest_white_face):
		_fail("front face rim tone requires local front and screen optics without white face")
		return
	if front_face_foam_gate and not front_face_rim_tone:
		_fail("front face foam gate requires rim tone")
		return
	if front_face_source_gate and not (front_face_rim_tone or offshore_core):
		_fail("front face source gate requires rim tone or offshore core")
		return
	if local_back_cells < 2.0 or local_back_cells > 12.0 or \
			local_face_cells < 0.25 or local_face_cells > 3.0 or \
			local_lift_depth_scale < 1.0 or local_lift_depth_scale > 3.0 or \
			((local_back_cells != 7.5 or local_face_cells != 1.8 or
				local_lift_depth_scale != 1.5) and not local_front_profile):
		_fail("local front shape parameters require local profile and valid ranges")
		return
	if local_overturn_m < 0.0 or local_overturn_m > 0.60 or \
			(local_overturn_m > 0.0 and (not local_front_profile or
				not depth_write or curl_forward_m > 0.0)):
		_fail("local overturn requires isolated depth-writing local front and 0..0.60m")
		return
	if local_front_segments and (crest_volume or local_front_volume or foam_front_splats or foam_splats):
		_fail("local front segments require the isolated local water profile")
		return
	if local_front_continuous_lip and (local_front_segments or crest_volume or
			local_front_volume or foam_front_splats or foam_splats):
		_fail("continuous front lip requires the isolated local water profile")
		return
	if branch_face and not local_front_continuous_lip:
		_fail("branch face requires the continuous local front lip")
		return
	if branch_face_row_center and (branch_face_2d or not unified_adaptive_anchor):
		_fail("row-center branch face requires adaptive row front and excludes candidate strips")
		return
	var preview: Node3D = WATER_SCENE.instantiate() if case_id == "water" else COUPLED_SCENE.instantiate()
	preview.prototype_front_face_source_gate = front_face_source_gate
	preview.prototype_offshore_core_source_gate = offshore_core
	preview.prototype_smooth_reference_shore = smooth_reference_shore
	preview.prototype_natural_reference_shore = natural_reference_shore
	preview.prototype_structured_reference_bed = structured_reference_bed
	preview.prototype_sculpted_reference_bed = sculpted_reference_bed
	preview.prototype_lobed_reference_bed = lobed_reference_bed
	preview.prototype_branched_reference_bed = branched_reference_bed
	preview.prototype_estuary_reference_bed = estuary_reference_bed
	preview.prototype_coupled_caustics = coupled_caustics and not no_caustics
	preview.prototype_unified_dense = unified_dense
	preview.prototype_unified_smooth_profile = unified_smooth_profile
	preview.prototype_unified_centered_base = unified_centered_base
	preview.prototype_unified_monotonic_base = unified_monotonic_base
	preview.prototype_cell_caustics = cell_caustics
	preview.prototype_fold_caustics = fold_caustics
	if not render_profile_path.is_empty():
		preview.prototype_imported_caustic_pattern_path = \
			String(render_profile.resources.caustic_pattern)
	preview.prototype_sync_boundary_readback = sync_boundary_readback
	preview.prototype_crest_curtain = crest_curtain
	preview.prototype_crest_ribbon = crest_ribbon
	preview.prototype_crest_ribbon_body = crest_ribbon_body
	preview.prototype_crest_ribbon_attached = crest_ribbon_attached
	preview.prototype_crest_ribbon_smooth_mask = crest_ribbon_smooth_mask
	preview.prototype_crest_rise_ribbon = crest_rise_ribbon
	preview.prototype_crest_solid_lip = crest_solid_lip
	preview.prototype_crest_water_body = crest_water_body
	preview.prototype_crest_shared_profile = front_foam and crest_solid_lip and \
		crest_ribbon_depth_write
	preview.prototype_crest_smoothed_lip = crest_smooth_window
	preview.prototype_crest_forward_toe = crest_forward_toe
	preview.prototype_unified_curl = unified_curl
	preview.prototype_foam_splats = foam_splats
	preview.prototype_foam_splats_jitter = foam_splats_jitter
	preview.prototype_foam_front_splats = foam_front_splats
	preview.prototype_foam_front_local_dense = foam_front_local_dense
	preview.prototype_foam_front_local_diameter_px = foam_front_local_diameter_px
	preview.prototype_foam_front_smooth = foam_front_smooth
	preview.prototype_foam_splats_fine = foam_splats_fine
	preview.prototype_foam_front_raised = foam_front_raised
	preview.prototype_foam_front_pixel_sized = foam_front_pixel_sized
	preview.prototype_foam_surface_lift_m = crest_height_m if \
		(foam_front_raised or foam_front_local_dense) else 0.0
	preview.prototype_crest_volume = crest_volume
	preview.prototype_crest_volume_debug = crest_volume_debug
	preview.prototype_local_front_volume = local_front_volume
	preview.prototype_local_front_segments = local_front_segments
	preview.prototype_local_front_continuous_lip = local_front_continuous_lip
	preview.prototype_branch_face = branch_face
	preview.prototype_branch_face_capped = branch_face_capped
	preview.prototype_branch_face_2d = branch_face_2d
	preview.prototype_branch_face_patches = branch_face_patches
	preview.prototype_branch_face_row_center = branch_face_row_center
	preview.prototype_branch_face_soft_material = branch_face_soft_material
	preview.prototype_branch_face_surface_join = branch_face_surface_join
	preview.prototype_local_front_field = local_front_profile or unified_2d_support
	preview.prototype_offshore_foam_source = offshore_foam_source
	preview.prototype_front_band_foam_source = front_band_foam_source
	preview.prototype_contact_history_field = write_independent_contact_history
	preview.prototype_local_front_wide_field = local_front_wide_field
	preview.prototype_crest_ribbon_depth_write = crest_ribbon_depth_write
	preview.prototype_crest_row_window = Vector2(
		(float(crest_row_min) + 0.5) / 256.0,
		(float(crest_row_max) + 0.5) / 256.0)
	preview.prototype_rise_crest = rise_crest and not crest_main_flat
	preview.prototype_rise_front_field = front_field
	preview.prototype_unified_adaptive_anchor = unified_adaptive_anchor
	preview.capture_substep_trace = write_substep_trace
	if subdivision_override != 0:
		preview.render_subdivision = subdivision_override
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks or not preview.last_error.is_empty():
		_fail("fixture initialization: " + preview.last_error)
		return
	if cell_caustics or fold_caustics:
		var pattern := preview.terrain_material.get_shader_parameter("caustic_pattern") as Texture2D
		if pattern == null or pattern.get_width() != 1024 or pattern.get_height() != 1024 or \
				not preview.terrain_material.get_shader_parameter("prototype_texture_caustics"):
			_fail("caustic pattern missing or not bound to terrain shader")
			return
	if require_1080p and root.size != Vector2i(1920, 1080):
		_fail("expected 1920x1080 viewport, got " + str(root.size))
		return
	var initial_state_hashes := {
		"rock": hash(preview.shadow_domain.rock),
		"sand": hash(preview.shadow_domain.sand),
		"water": hash(preview.shadow_domain.water),
	}
	if local_front_profile:
		preview.water_material.shader = load(
			render_profile.resources.water_shader if not render_profile.is_empty() else
			"res://tests/visual_water_alignment/prototypes/reference_water_local_front.gdshader")
	elif rise_crest:
		preview.water_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_water_unified_curl.gdshader" if unified_curl else
			"res://tests/visual_water_alignment/prototypes/reference_water_front_cut.gdshader" if shared_boundary else
			"res://tests/visual_water_alignment/prototypes/reference_water_front_foam.gdshader" if front_foam else
			("res://tests/visual_water_alignment/prototypes/reference_water_front_profile.gdshader" if front_profile else
			"res://tests/visual_water_alignment/prototypes/reference_water_rise_crest.gdshader"))
	elif integrated_fold_m > 0.0:
		preview.water_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_water_integrated_fold.gdshader")
	elif depth_write:
		preview.water_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_water_foam_porous.gdshader" if porous_foam else
			("res://tests/visual_water_alignment/prototypes/reference_water_shore_project.gdshader" if shore_vertex_project else
			"res://tests/visual_water_alignment/prototypes/reference_water_depthwrite.gdshader"))
	elif depth_prepass:
		preview.water_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_water_depthprepass.gdshader")
	if unified_no_depth:
		var no_depth_shader := Shader.new()
		no_depth_shader.code = (preview.water_material.shader as Shader).code.replace(
			"depth_draw_always", "depth_draw_never")
		preview.water_material.shader = no_depth_shader
	# A shader replacement may drop parameters set by the preview during _ready().
	preview.water_material.set_shader_parameter("display_reconstruction",
		preview.render_subdivision > 1)
	preview.water_material.set_shader_parameter("prototype_eta_normals", eta_normals)
	preview.water_material.set_shader_parameter("prototype_shared_bed_triangles",
		shared_bed_triangles)
	preview.water_material.set_shader_parameter("midpoint_clip", midpoint_clip)
	preview.water_material.set_shader_parameter("radial_shore", radial_shore)
	preview.water_material.set_shader_parameter("prototype_shore_unscaled_depth",
		shore_unscaled_depth)
	preview.water_material.set_shader_parameter("prototype_shore_linear_weights",
		shore_linear_weights)
	preview.water_material.set_shader_parameter("shoreline_debug", shoreline_debug)
	preview.water_material.set_shader_parameter("prototype_screen_optics", screen_optics)
	preview.water_material.set_shader_parameter("prototype_optical_shallow_preserve",
		optical_shallow_preserve)
	preview.water_material.set_shader_parameter("prototype_screen_deep_scatter_scale",
		screen_deep_scatter_scale)
	preview.water_material.set_shader_parameter("prototype_screen_sky_reflection_scale",
		screen_sky_reflection_scale)
	preview.water_material.set_shader_parameter("prototype_screen_fresnel_debug",
		screen_fresnel_debug)
	preview.water_material.set_shader_parameter("prototype_screen_abs_fresnel",
		screen_abs_fresnel)
	preview.water_material.set_shader_parameter("prototype_screen_face_normal",
		screen_face_normal)
	preview.water_material.set_shader_parameter("prototype_screen_scene_reflection",
		screen_scene_reflection)
	preview.water_material.set_shader_parameter("prototype_screen_reflection_debug",
		screen_reflection_debug)
	preview.water_material.set_shader_parameter("prototype_screen_world_glint",
		screen_world_glint)
	if screen_world_glint:
		var sun_direction := Vector3(-0.42, 0.84, 0.34)
		if screen_world_glint_opposite:
			sun_direction = Vector3(0.42, 0.84, -0.34)
		preview.water_material.set_shader_parameter("prototype_light_direction_world",
			sun_direction.normalized())
	preview.water_material.set_shader_parameter("prototype_screen_bed_only",
		screen_bed_only)
	preview.water_material.set_shader_parameter("prototype_shallow_extinction_m",
		shallow_extinction_m)
	preview.water_material.set_shader_parameter("prototype_depth_bands", depth_bands)
	preview.water_material.set_shader_parameter("prototype_refraction_scale", refraction_scale)
	if not render_profile.is_empty():
		preview.water_material.set_shader_parameter("water_surface_bias_m",
			render_profile.surface_bias_m)
	preview.water_material.set_shader_parameter("prototype_depth_guard", depth_guard)
	preview.water_material.set_shader_parameter("prototype_crest_height_m",
		0.0 if crest_main_flat else crest_height_m)
	preview.water_material.set_shader_parameter("prototype_local_back_cells",
		local_back_cells)
	preview.water_material.set_shader_parameter("prototype_local_face_cells",
		local_face_cells)
	preview.water_material.set_shader_parameter("prototype_local_lift_depth_scale",
		local_lift_depth_scale)
	if local_front_profile:
		preview.water_material.set_shader_parameter("local_front_state",
			preview.local_front_texture)
		preview.water_material.set_shader_parameter("prototype_use_local_front", true)
		if branch_face:
			preview.water_material.set_shader_parameter("prototype_crest_height_m", 0.0)
	if write_independent_contact_history:
		preview.water_material.set_shader_parameter("contact_history_state",
			preview.contact_history_texture)
	if unified_curl:
		if unified_2d_support:
			preview.water_material.set_shader_parameter("local_front_state",
				preview.local_front_texture)
		preview.water_material.set_shader_parameter("prototype_unified_2d_support",
			unified_2d_support)
		preview.water_material.set_shader_parameter("prototype_unified_expanded_front_range",
			unified_expanded_front_range)
		preview.water_material.set_shader_parameter("prototype_unified_debug", unified_debug)
		preview.water_material.set_shader_parameter("prototype_unified_sealed", unified_sealed)
		preview.water_material.set_shader_parameter("prototype_unified_variable", unified_variable)
		preview.water_material.set_shader_parameter("prototype_unified_porous_cap", unified_porous_cap)
		preview.water_material.set_shader_parameter("prototype_unified_smooth_profile", unified_smooth_profile)
		preview.water_material.set_shader_parameter("prototype_unified_opaque", unified_opaque)
		preview.water_material.set_shader_parameter("prototype_unified_sparse_cap", unified_sparse_cap)
		preview.water_material.set_shader_parameter("prototype_unified_supported_front", unified_supported_front)
		preview.water_material.set_shader_parameter("prototype_unified_local_support", unified_local_support)
		preview.water_material.set_shader_parameter("prototype_unified_field_base", unified_field_base)
		preview.water_material.set_shader_parameter("prototype_unified_localized_base", unified_localized_base)
		preview.water_material.set_shader_parameter("prototype_unified_inactive_anchor", unified_inactive_anchor)
		preview.water_material.set_shader_parameter("prototype_unified_alpha_seal", unified_alpha_seal)
		preview.water_material.set_shader_parameter("prototype_unified_fragment_wet", unified_fragment_wet)
		preview.water_material.set_shader_parameter("prototype_unified_wet_toe", unified_wet_toe)
		preview.water_material.set_shader_parameter("prototype_unified_smooth_support", unified_smooth_support)
		preview.water_material.set_shader_parameter("prototype_unified_body_scale", unified_body_scale)
		preview.water_material.set_shader_parameter("prototype_unified_overturn", unified_overturn)
		preview.water_material.set_shader_parameter("prototype_unified_layer_debug", unified_layer_debug)
		preview.water_material.set_shader_parameter("prototype_unified_broad_back", unified_broad_back)
		preview.water_material.set_shader_parameter("prototype_unified_overturn_cap", unified_overturn_cap)
		preview.water_material.set_shader_parameter("prototype_unified_surface_probe", unified_surface_probe)
		preview.water_material.set_shader_parameter("prototype_unified_front_wall", unified_front_wall)
		preview.water_material.set_shader_parameter("prototype_unified_row_min", float(unified_row_min) / 256.0)
		preview.water_material.set_shader_parameter("prototype_unified_row_max", float(unified_row_max) / 256.0)
	if rise_crest:
		preview.water_material.set_shader_parameter("foam_previous_state",
			preview.previous_foam_texture)
		preview.water_material.set_shader_parameter("prototype_rise_crest", true)
		if front_field:
			preview.water_material.set_shader_parameter("rise_front_state",
				preview.rise_front_texture)
			preview.water_material.set_shader_parameter("prototype_use_front_field", true)
	preview.water_material.set_shader_parameter("prototype_crest_shore_depth_m",
		crest_shore_depth_m)
	preview.water_material.set_shader_parameter("prototype_curl_forward_m", curl_forward_m)
	preview.water_material.set_shader_parameter("prototype_local_overturn_m",
		local_overturn_m)
	if integrated_fold_m > 0.0:
		preview.water_material.set_shader_parameter("prototype_integrated_fold_m", integrated_fold_m)
	preview.water_material.set_shader_parameter("prototype_crest_white_face", crest_white_face)
	preview.water_material.set_shader_parameter("prototype_crest_span_smoothing",
		crest_span_smoothing)
	preview.water_material.set_shader_parameter("prototype_crest_depth_gate_bypass",
		crest_depth_gate_bypass)
	preview.water_material.set_shader_parameter("prototype_geometry_silhouette",
		geometry_silhouette)
	preview.water_material.set_shader_parameter("prototype_geometry_alpha",
		geometry_alpha)
	preview.water_material.set_shader_parameter("prototype_geometry_keep_alpha",
		geometry_keep_alpha)
	preview.water_material.set_shader_parameter("prototype_geometry_keep_color",
		geometry_keep_color)
	preview.water_material.set_shader_parameter("prototype_crest_fragment_foam",
		crest_fragment_foam)
	preview.water_material.set_shader_parameter("prototype_crest_broken_core",
		crest_broken_core)
	preview.water_material.set_shader_parameter("prototype_offshore_core",
		offshore_core)
	preview.water_material.set_shader_parameter("prototype_offshore_core_broken",
		offshore_core_broken)
	preview.water_material.set_shader_parameter("prototype_offshore_core_crown",
		offshore_core_crown)
	preview.water_material.set_shader_parameter("prototype_front_face_rim_tone",
		front_face_rim_tone)
	preview.water_material.set_shader_parameter("prototype_front_face_foam_gate",
		front_face_foam_gate)
	preview.water_material.set_shader_parameter("prototype_irregular_foam", irregular_foam)
	preview.water_material.set_shader_parameter("prototype_aperiodic_foam", aperiodic_foam)
	preview.water_material.set_shader_parameter("prototype_front_foam_blend",
		front_foam_blend)
	preview.water_material.set_shader_parameter("prototype_front_foam_ribbon",
		front_foam_ribbon)
	preview.water_material.set_shader_parameter("prototype_broad_crest", broad_crest)
	if foam_overlay or foam_suppressed or foam_splats or foam_front_splats or crest_volume or local_front_segments:
		preview.water_material.set_shader_parameter("phase2_foam", false)
	if no_main_foam:
		preview.water_material.set_shader_parameter("phase2_foam", false)
	if foam_overlay:
		var foam_mesh := MeshInstance3D.new()
		foam_mesh.name = "PrototypeFoamOverlay"
		foam_mesh.mesh = (preview.get_node("GpuWaterSurface") as MeshInstance3D).mesh
		foam_mesh.custom_aabb = AABB(Vector3(-16.5, -2.0, -16.5),
			Vector3(33.0, 6.0, 33.0))
		var foam_material := ShaderMaterial.new()
		foam_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_water_foam_overlay.gdshader")
		foam_material.render_priority = 1
		foam_material.set_shader_parameter("rock_state", preview.rock_texture)
		foam_material.set_shader_parameter("sand_state", preview.sand_texture)
		foam_material.set_shader_parameter("water_state", preview.water_texture)
		foam_material.set_shader_parameter("foam_state", preview.foam_texture)
		foam_material.set_shader_parameter("water_surface_bias_m", 0.010)
		foam_material.set_shader_parameter("prototype_crest_height_m",
			crest_height_m)
		foam_material.set_shader_parameter("prototype_crest_shore_depth_m",
			crest_shore_depth_m)
		foam_material.set_shader_parameter("prototype_curl_forward_m",
			curl_forward_m)
		foam_material.set_shader_parameter("prototype_crest_span_smoothing",
			crest_span_smoothing)
		foam_material.set_shader_parameter("prototype_crest_depth_gate_bypass",
			crest_depth_gate_bypass)
		foam_material.set_shader_parameter("prototype_broad_crest",
			broad_crest)
		foam_material.set_shader_parameter("prototype_shared_bed_triangles",
			shared_bed_triangles)
		foam_material.set_shader_parameter("midpoint_clip", midpoint_clip)
		foam_material.set_shader_parameter("radial_shore", radial_shore)
		foam_material.set_shader_parameter("prototype_force_visible",
			foam_overlay_debug)
		foam_material.set_shader_parameter("prototype_show_coverage",
			foam_overlay_coverage)
		foam_material.set_shader_parameter("display_reconstruction",
			preview.render_subdivision > 1)
		foam_mesh.material_override = foam_material
		preview.add_child(foam_mesh)
	if crest_ribbon_attached or crest_rise_ribbon:
		var ribbon_material := (preview.get_node("PrototypeCrestRibbon") as MeshInstance3D).material_override as ShaderMaterial
		ribbon_material.set_shader_parameter("crest_height_m", crest_height_m)
	if no_caustics:
		preview.terrain_material.set_shader_parameter("phase2_caustics", false)
	var requested_waves: Array[Dictionary] = []
	if not render_profile.is_empty() or profile_wave_workload_id != "single_packet_v1":
		var scheduled: Dictionary = WaveWorkload.schedule(preview, profile_wave_workload_id)
		if not scheduled.get("ok", false):
			_fail("profile wave workload: " + String(scheduled.get("code", "invalid")))
			return
		for request in scheduled.requests:
			requested_waves.append(request)
	elif with_wave:
		var request := {"domain_id": preview.shadow_domain.domain_id,
			"generation": preview.generation, "request_id": 1,
			"start_tick": 8, "profile_id": &"test_packet",
			"amplitude_m": 0.18, "duration_s": 6.0, "seed": 31}
		var admitted: Dictionary = preview.request_wave(request)
		if not admitted.ok:
			_fail("wave rejected: " + String(admitted.code))
			return
		requested_waves.append(request)
	while preview.completed_ticks < capture_tick - 1 and preview.last_error.is_empty() and frames < 36000:
		await process_frame
		frames += 1
	preview.playing = false
	while preview.tick_pending and frames < 39000:
		await process_frame
		frames += 1
	if preview.tick_pending:
		_fail("GPU did not settle")
		return
	while preview.completed_ticks < capture_tick and preview.last_error.is_empty() and frames < 42000:
		if not preview.tick_pending and not preview.checkpoint_capture_pending:
			preview._start_tick()
		await process_frame
		frames += 1
	if preview.completed_ticks != capture_tick or preview.tick_pending or not preview.last_error.is_empty():
		_fail("exact capture tick failed: got %d, expected %d, error=%s" % [
			preview.completed_ticks, capture_tick, preview.last_error])
		return
	preview.set_visual_time(float(capture_tick) / 30.0)
	if write_contact_foam_source or write_contact_foam_candidate or \
			write_contact_front_gate_candidate or write_contact_wide_band_candidate or \
			write_contact_relaxed_front_candidate or write_contact_history_candidate:
		if preview.foam_field == null:
			_fail("contact foam source previous state unavailable")
			return
		preview.previous_foam_texture.texture_rd_rid = \
			preview.foam_field.textures[1 - preview.foam_field.current_index]
		preview.water_material.set_shader_parameter("foam_previous_state",
			preview.previous_foam_texture)
	var foam_summary := {}
	var foam_field_path := ""
	var foam_history_path := ""
	var water_field_path := ""
	var rock_field_path := ""
	var sand_field_path := ""
	var wetness_field_path := ""
	var previous_foam_path := ""
	var front_field_path := ""
	var local_front_field_path := ""
	var independent_contact_history_field_path := ""
	if readback_foam:
		if preview.foam_field == null:
			_fail("foam field unavailable")
			return
		RenderingServer.call_on_render_thread(_request_foam_readback.bind(preview))
		var expected_readbacks := 2 + (2 if write_bed_fields else 0) + (1 if write_wetness_field else 0) + (1 if write_previous_foam else 0) + (1 if write_front_field else 0) + (1 if write_local_front_field else 0) + (1 if write_independent_contact_history else 0)
		while readbacks.size() < expected_readbacks and frames < 45000:
			await process_frame
			frames += 1
		if readbacks.size() != expected_readbacks or readbacks["foam"].size() != 256 * 256 * 8 or readbacks["water"].size() != 256 * 256 * 4 or (write_bed_fields and (readbacks["rock"].size() != 256 * 256 * 4 or readbacks["sand"].size() != 256 * 256 * 4)) or (write_wetness_field and readbacks["wetness"].size() != 256 * 256 * 2):
			_fail("foam/water readback missing or wrong length")
			return
		var foam_values: PackedFloat32Array = readbacks["foam"].to_float32_array()
		var water_values: PackedFloat32Array = readbacks["water"].to_float32_array()
		var foam_sum := 0.0
		var coverage_05 := 0
		var coverage_20 := 0
		var dry_foam := 0
		var strong_x_weight := 0.0
		var strong_weight := 0.0
		var foam_image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		for cell in 256 * 256:
			var foam: float = foam_values[cell * 2]
			foam_sum += foam
			if foam > 0.05:
				coverage_05 += 1
			if foam > 0.20:
				coverage_20 += 1
				strong_weight += foam
				strong_x_weight += foam * float(cell % 256)
			if water_values[cell] <= 0.0015 and foam > 0.001:
				dry_foam += 1
			foam_image.set_pixel(cell % 256, cell / 256,
				Color(foam, foam, foam, 1.0))
		foam_summary = {"sum": foam_sum, "coverage_05": coverage_05,
			"coverage_20": coverage_20, "dry_foam": dry_foam,
			"strong_centroid_x_cell": strong_x_weight / strong_weight if strong_weight > 0.0 else -1.0}
		foam_field_path = output_dir.path_join("%s_%s_foam_field.png" % [run_id, case_id])
		if foam_image.save_png(foam_field_path) != OK:
			_fail("foam field PNG write")
			return
		if write_foam_history:
			foam_history_path = output_dir.path_join("%s_%s_foam_rg32f.bin" % [
				run_id, case_id])
			var foam_file := FileAccess.open(foam_history_path, FileAccess.WRITE)
			if foam_file == null:
				_fail("foam history binary open")
				return
			foam_file.store_buffer(readbacks["foam"])
			foam_file.close()
		if write_water_field:
			water_field_path = output_dir.path_join("%s_%s_water_f32.bin" % [run_id, case_id])
			var water_file := FileAccess.open(water_field_path, FileAccess.WRITE)
			if water_file == null:
				_fail("water field binary open")
				return
			water_file.store_buffer(readbacks["water"])
			water_file.close()
		if write_bed_fields:
			rock_field_path = output_dir.path_join("%s_%s_rock_f32.bin" % [run_id, case_id])
			sand_field_path = output_dir.path_join("%s_%s_sand_f32.bin" % [run_id, case_id])
			for field_name in ["rock", "sand"]:
				var field_path: String = rock_field_path if field_name == "rock" else sand_field_path
				var field_file := FileAccess.open(field_path, FileAccess.WRITE)
				if field_file == null:
					_fail("bed field binary open: " + field_name)
					return
				field_file.store_buffer(readbacks[field_name])
				field_file.close()
		if write_wetness_field:
			wetness_field_path = output_dir.path_join("%s_%s_wetness_f16.bin" % [run_id, case_id])
			var wetness_file := FileAccess.open(wetness_field_path, FileAccess.WRITE)
			if wetness_file == null:
				_fail("wetness field binary open")
				return
			wetness_file.store_buffer(readbacks["wetness"])
			wetness_file.close()
		if write_previous_foam:
			previous_foam_path = output_dir.path_join("%s_%s_previous_foam_rg32f.bin" % [run_id, case_id])
			var previous_file := FileAccess.open(previous_foam_path, FileAccess.WRITE)
			if previous_file == null or readbacks["previous_foam"].size() != 256 * 256 * 8:
				_fail("previous foam binary write")
				return
			previous_file.store_buffer(readbacks["previous_foam"])
			previous_file.close()
		if write_front_field:
			front_field_path = output_dir.path_join("%s_%s_front_rg32f.bin" % [run_id, case_id])
			var front_file := FileAccess.open(front_field_path, FileAccess.WRITE)
			if front_file == null or readbacks["front"].size() != 256 * 2 * 4:
				_fail("front field binary write")
				return
			front_file.store_buffer(readbacks["front"])
			front_file.close()
		if write_local_front_field:
			local_front_field_path = output_dir.path_join("%s_%s_local_front_rg32f.bin" % [run_id, case_id])
			var local_front_file := FileAccess.open(local_front_field_path, FileAccess.WRITE)
			if local_front_file == null or readbacks["local_front"].size() != 256 * 256 * 2 * 4:
				_fail("local front field binary write")
				return
			local_front_file.store_buffer(readbacks["local_front"])
			local_front_file.close()
		if write_independent_contact_history:
			independent_contact_history_field_path = output_dir.path_join(
				"%s_%s_contact_history_r32f.bin" % [run_id, case_id])
			var contact_history_file := FileAccess.open(
				independent_contact_history_field_path, FileAccess.WRITE)
			if contact_history_file == null or readbacks["contact_history"].size() != 256 * 256 * 4:
				_fail("independent contact history binary write")
				return
			contact_history_file.store_buffer(readbacks["contact_history"])
			contact_history_file.close()
	var camera_ids: Array[StringName] = [&"oblique", &"close", &"grazing"]
	if foreground_multiview:
		camera_ids.append(&"foreground_low_left")
		camera_ids.append(&"foreground_low_right")
	if foreground_sweep:
		for sweep_index in 9:
			camera_ids.append(StringName("foreground_sweep_%02d" % sweep_index))
	var reflection_viewport: SubViewport = null
	var reflection_camera: Camera3D = null
	if planar_reflection_probe:
		reflection_viewport = SubViewport.new()
		reflection_viewport.size = planar_reflection_size
		reflection_viewport.world_3d = root.world_3d
		reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(reflection_viewport)
		reflection_camera = Camera3D.new()
		reflection_camera.cull_mask = 4
		reflection_viewport.add_child(reflection_camera)
		reflection_camera.make_current()
		(preview.get_node("GpuWaterSurface") as MeshInstance3D).layers = 2
		preview.overview_camera.set_cull_mask_value(3, false)
		preview.player_camera.set_cull_mask_value(3, false)
		var reflection_bed := MeshInstance3D.new()
		reflection_bed.name = "ReflectionAboveWaterBed"
		reflection_bed.mesh = (preview.get_node("GpuSandTerrain") as MeshInstance3D).mesh
		reflection_bed.layers = 4
		var reflection_bed_material := preview.terrain_material.duplicate() as ShaderMaterial
		var reflection_bed_shader := Shader.new()
		reflection_bed_shader.code = (preview.terrain_material.shader as Shader).code.replace(
			"void fragment() {",
			"void fragment() {\n    if ((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < 0.0) { discard; }")
		reflection_bed_material.shader = reflection_bed_shader
		reflection_bed.material_override = reflection_bed_material
		preview.add_child(reflection_bed)
		if planar_reflection_water:
			preview.water_material.set_shader_parameter(
				"prototype_planar_reflection_enabled", true)
			preview.water_material.set_shader_parameter(
				"prototype_planar_reflection_debug", planar_reflection_debug)
			preview.water_material.set_shader_parameter(
				"prototype_planar_reflection", reflection_viewport.get_texture())
	if wavefront_camera:
		camera_ids.append(&"wavefront_side")
	if reverse_wavefront_camera:
		camera_ids.append(&"wavefront_reverse")
	if sunward_camera:
		camera_ids.append(&"sunward")
	if topdown_camera:
		camera_ids.append(&"topdown")
	if orthographic_shore_probe:
		camera_ids.append(&"shore_ortho")
	if crest_profile_camera:
		camera_ids.append(&"crest_profile")
		camera_ids.append(&"crest_cross")
	var files: Array[String] = []
	var cameras := {}
	var capture_revision: int = preview.solver.state_revision
	var shader_probe := {}
	var optical_layer_artifacts := {}
	var foam_flow_detail_artifacts := {}
	var shoreline_mask_artifacts := {}
	var shore_contour_candidate_artifacts := {}
	var bed_only_multiview_artifacts := {}
	var depth_band_multiview_artifacts := {}
	var depth_gray_multiview_artifacts := {}
	var contact_alpha_artifacts := {}
	var shore_source_artifacts := {}
	var contact_foam_source_artifacts := {}
	var contact_foam_candidate_artifacts := {}
	var contact_front_gate_candidate_artifacts := {}
	var contact_wide_band_candidate_artifacts := {}
	var contact_relaxed_front_candidate_artifacts := {}
	var contact_history_candidate_artifacts := {}
	var independent_contact_history_artifacts := {}
	var contact_depth_artifacts := {}
	var contact_height_artifacts := {}
	var contact_flat_crest_artifacts := {}
	var contact_shared_bed_artifacts := {}
	var vertex_fragment_delta_artifacts := {}
	var visible_bed_height_artifacts := {}
	var contact_residual_artifacts := {}
	var wet_finish_off_artifacts := {}
	var wet_trace_candidate_artifacts := {}
	var refraction_edge_artifacts := {}
	var caustic_strength_artifacts := {}
	var caustic_scale_artifacts := {}
	var caustic_time_artifacts := {}
	var caustic_depth_composite_artifacts := {}
	var caustic_recovery_artifacts := {}
	var caustic_recovery_time_artifacts := {}
	var extinction_sweep_artifacts := {}
	var optical_contributor_artifacts := {}
	var optical_contributor_bed_artifacts := {}
	var foreground_control_artifact := ""
	var foreground_control_artifacts := {}
	if foreground_occluder:
		preview.get_node("PrototypeForegroundOccluders/OpaqueWall").visible = true
	if transparent_foreground_occluder:
		preview.get_node("PrototypeForegroundOccluders/TransparentWall").visible = true
	if submerged_transparent_occluder:
		preview.get_node("PrototypeForegroundOccluders/SubmergedTransparentWall").visible = true
	var pause_hold_elapsed_ms := 0
	var pause_hold_frames := 0
	for camera_id in camera_ids:
		if camera_id == &"shore_ortho":
			preview.player_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			preview.player_camera.size = 8.0
			preview.player_camera.position = Vector3(1.5, 10.0, -2.5)
			preview.player_camera.look_at(Vector3(1.5, 0.0, -2.5),
				Vector3(0.0, 0.0, -1.0))
			preview.set_player_camera(true)
		elif camera_id == &"topdown":
			preview.player_camera.position = Vector3(0.0, 21.0, 0.0)
			preview.player_camera.look_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
			preview.player_camera.fov = 54.0
			preview.set_player_camera(true)
		elif camera_id == &"wavefront_side":
			preview.aim_player_camera(Vector3(wavefront_center_x_m - 3.6,
				1.5, wavefront_center_z_m - 1.0),
				Vector3(wavefront_center_x_m, 0.18, wavefront_center_z_m))
			preview.player_camera.fov = 50.0
			preview.set_player_camera(true)
		elif camera_id == &"wavefront_reverse":
			preview.aim_player_camera(Vector3(wavefront_center_x_m + 3.6,
				1.5, wavefront_center_z_m - 1.0),
				Vector3(wavefront_center_x_m, 0.18, wavefront_center_z_m))
			preview.player_camera.fov = 50.0
			preview.set_player_camera(true)
		elif camera_id == &"sunward":
			preview.aim_player_camera(Vector3(2.0, 6.0, -13.9),
				Vector3(-3.0, 0.18, -6.9))
			preview.player_camera.fov = 50.0
			preview.set_player_camera(true)
		elif camera_id == &"crest_profile":
			preview.aim_player_camera(Vector3(4.2, 0.80, -8.5),
				Vector3(5.2, 0.23, -5.5))
			preview.player_camera.fov = 48.0
			preview.set_player_camera(true)
		elif camera_id == &"crest_cross":
			preview.aim_player_camera(Vector3(5.8, 0.90, -8.2),
				Vector3(4.7, 0.25, -5.4))
			preview.player_camera.fov = 48.0
			preview.set_player_camera(true)
		elif camera_id in [&"foreground_low_left", &"foreground_low_right"]:
			var object_x := 0.0 if foreground_occluder else 2.0
			var left := camera_id == &"foreground_low_left"
			preview.aim_player_camera(Vector3(object_x + (-3.0 if left else 3.0),
				1.6 if left else 1.1, 10.8 if left else 9.5),
				Vector3(object_x, 1.0, 7.0))
			preview.player_camera.fov = 50.0
			preview.set_player_camera(true)
		elif String(camera_id).begins_with("foreground_sweep_"):
			var sweep_index := int(String(camera_id).trim_prefix("foreground_sweep_"))
			var object_x := 0.0 if foreground_occluder else 2.0
			preview.aim_player_camera(Vector3(
				object_x + lerpf(-3.0, 3.0, float(sweep_index) / 8.0),
				1.3, 10.0), Vector3(object_x, 1.0, 7.0))
			preview.player_camera.fov = 50.0
			preview.set_player_camera(true)
		elif not preview.set_fixture_camera(camera_id):
			_fail("unknown camera: " + String(camera_id))
			return
		if planar_reflection_probe:
			var source_camera := root.get_camera_3d()
			reflection_camera.fov = source_camera.fov
			reflection_camera.near = source_camera.near
			reflection_camera.far = source_camera.far
			var source_basis := source_camera.global_transform.basis
			var reflected_position := source_camera.global_position
			reflected_position.y = -reflected_position.y
			var reflected_forward := -source_basis.z
			reflected_forward.y = -reflected_forward.y
			var reflected_up := source_basis.y
			reflected_up.y = -reflected_up.y
			reflection_camera.global_position = reflected_position
			reflection_camera.look_at(reflected_position + reflected_forward,
				reflected_up)
			if planar_reflection_projected:
				var reflected_view_projection := reflection_camera.get_camera_projection() * \
					Projection(reflection_camera.global_transform.affine_inverse())
				preview.water_material.set_shader_parameter(
					"prototype_planar_reflection_projected", true)
				preview.water_material.set_shader_parameter(
					"prototype_planar_view_projection", reflected_view_projection)
		if camera_id == &"oblique" and local_front_profile:
			var prior_depth_bands: bool = preview.water_material.get_shader_parameter(
				"prototype_depth_bands")
			preview.water_material.set_shader_parameter("prototype_depth_bands", true)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var probe_image := root.get_texture().get_image()
			var red_samples := 0
			var blue_samples := 0
			for py in range(8, probe_image.get_height(), 16):
				for px in range(8, probe_image.get_width(), 16):
					var probe_color := probe_image.get_pixel(px, py)
					if probe_color.r > 0.70 and probe_color.g < 0.27 and \
							probe_color.b < 0.27:
						red_samples += 1
					if probe_color.b > 0.70 and probe_color.r < 0.27 and \
							probe_color.g < 0.27:
						blue_samples += 1
			preview.water_material.set_shader_parameter("prototype_depth_bands",
				prior_depth_bands)
			shader_probe = {"red_samples": red_samples,
				"blue_samples": blue_samples, "stride_px": 16}
			if red_samples < 20 or blue_samples < 20:
				_fail("local water shader did not render expected depth bands: " +
					str(shader_probe))
				return
			if planar_reflection_probe:
				var reflected_image := reflection_viewport.get_texture().get_image()
				var sand_samples := 0
				for py in range(8, reflected_image.get_height(), 16):
					for px in range(8, reflected_image.get_width(), 16):
						var probe_color := reflected_image.get_pixel(px, py)
						if probe_color.r > 0.45 and probe_color.g > 0.30 and \
								probe_color.r > probe_color.b * 1.20:
							sand_samples += 1
				shader_probe["reflected_sand_samples"] = sand_samples
				if sand_samples < 20:
					_fail("reflected terrain shader did not render above-water bed: " +
						str(shader_probe))
					return
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if camera_id == &"oblique" and pause_hold_ms > 0:
			# Let temporal AA settle before comparing the same camera at a paused tick.
			for warmup_frame in 28:
				await RenderingServer.frame_post_draw
		var camera := root.get_camera_3d()
		if camera == null:
			_fail("camera missing: " + String(camera_id))
			return
		cameras[String(camera_id)] = {"transform": str(camera.global_transform),
			"projection": camera.projection, "fov_deg": camera.fov,
			"orthographic_size": camera.size, "near": camera.near, "far": camera.far}
		var path := output_dir.path_join("%s_%s_%s.png" % [run_id, case_id, camera_id])
		if root.get_texture().get_image().save_png(path) != OK:
			_fail("PNG write: " + path)
			return
		files.append(path)
		if write_foam_flow_detail:
			preview.water_material.set_shader_parameter(
				"prototype_foam_flow_detail", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var detail_path := output_dir.path_join(
				"%s_%s_%s_foam_flow_detail.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(detail_path) != OK:
				_fail("foam flow detail PNG write")
				return
			files.append(detail_path)
			foam_flow_detail_artifacts[String(camera_id)] = detail_path
			preview.water_material.set_shader_parameter(
				"prototype_foam_flow_detail", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_shoreline_mask:
			preview.water_material.set_shader_parameter("shoreline_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var mask_path := output_dir.path_join(
				"%s_%s_%s_shoreline_mask.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(mask_path) != OK:
				_fail("shoreline mask PNG write")
				return
			files.append(mask_path)
			shoreline_mask_artifacts[String(camera_id)] = mask_path
			preview.water_material.set_shader_parameter("shoreline_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_shore_contour_candidate:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_shore_linear_weights = false;"):
				_fail("shore contour candidate requires local-front water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_shore_unscaled_depth", true)
			preview.water_material.set_shader_parameter(
				"prototype_shore_linear_weights", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var contour_path := output_dir.path_join(
				"%s_%s_%s_shore_contour_candidate.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(contour_path) != OK:
				_fail("shore contour candidate PNG write")
				return
			files.append(contour_path)
			shore_contour_candidate_artifacts[String(camera_id)] = contour_path
			preview.water_material.set_shader_parameter("shoreline_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var contour_mask_path := output_dir.path_join(
				"%s_%s_%s_shore_contour_mask.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(contour_mask_path) != OK:
				_fail("shore contour mask PNG write")
				return
			files.append(contour_mask_path)
			shore_contour_candidate_artifacts[String(camera_id) + "_mask"] = contour_mask_path
			preview.water_material.set_shader_parameter("shoreline_debug", false)
			if write_contact_residual:
				preview.water_material.set_shader_parameter(
					"prototype_render_grid_size", float(256 * preview.render_subdivision))
				preview.water_material.set_shader_parameter(
					"prototype_contact_residual_debug", true)
				for settle in 4:
					await RenderingServer.frame_post_draw
				var contour_residual_path := output_dir.path_join(
					"%s_%s_%s_shore_contour_residual.png" % [
					run_id, case_id, camera_id])
				if root.get_texture().get_image().save_png(contour_residual_path) != OK:
					_fail("shore contour residual PNG write")
					return
				files.append(contour_residual_path)
				shore_contour_candidate_artifacts[String(camera_id) + "_residual"] = \
					contour_residual_path
				preview.water_material.set_shader_parameter(
					"prototype_contact_residual_debug", false)
			preview.water_material.set_shader_parameter(
				"prototype_shore_unscaled_depth", false)
			preview.water_material.set_shader_parameter(
				"prototype_shore_linear_weights", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_bed_only_multiview:
			var probe_water_mesh := preview.get_node("GpuWaterSurface") as MeshInstance3D
			probe_water_mesh.visible = false
			for settle in 4:
				await RenderingServer.frame_post_draw
			var bed_only_path := output_dir.path_join(
				"%s_%s_%s_bed_only.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(bed_only_path) != OK:
				_fail("bed-only multiview PNG write")
				return
			files.append(bed_only_path)
			bed_only_multiview_artifacts[String(camera_id)] = bed_only_path
			probe_water_mesh.visible = true
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_depth_bands_multiview:
			preview.water_material.set_shader_parameter("prototype_depth_bands", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var bands_path := output_dir.path_join(
				"%s_%s_%s_depth_bands.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(bands_path) != OK:
				_fail("depth bands PNG write: " + bands_path)
				return
			files.append(bands_path)
			depth_band_multiview_artifacts[String(camera_id)] = bands_path
			preview.water_material.set_shader_parameter("prototype_depth_bands", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
			preview.water_material.set_shader_parameter("prototype_depth_gray_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var gray_path := output_dir.path_join(
				"%s_%s_%s_depth_gray.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(gray_path) != OK:
				_fail("depth gray PNG write: " + gray_path)
				return
			files.append(gray_path)
			depth_gray_multiview_artifacts[String(camera_id)] = gray_path
			preview.water_material.set_shader_parameter("prototype_depth_gray_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_alpha_map:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_alpha_debug = false;"):
				_fail("contact alpha map requires reference water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_alpha_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var alpha_path := output_dir.path_join(
				"%s_%s_%s_contact_alpha.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(alpha_path) != OK:
				_fail("contact alpha PNG write")
				return
			files.append(alpha_path)
			contact_alpha_artifacts[String(camera_id)] = alpha_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_alpha_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_shore_source_map:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_shore_source_debug = false;"):
				_fail("shore source map requires reference water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_shore_source_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var source_path := output_dir.path_join(
				"%s_%s_%s_shore_source.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(source_path) != OK:
				_fail("shore source PNG write")
				return
			files.append(source_path)
			shore_source_artifacts[String(camera_id)] = source_path
			preview.water_material.set_shader_parameter(
				"prototype_shore_source_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_foam_source:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_foam_source_debug = false;"):
				_fail("contact foam source requires local-front water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_source_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var contact_foam_path := output_dir.path_join(
				"%s_%s_%s_contact_foam_source.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(contact_foam_path) != OK:
				_fail("contact foam source PNG write")
				return
			files.append(contact_foam_path)
			contact_foam_source_artifacts[String(camera_id)] = contact_foam_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_source_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_foam_candidate:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_foam_candidate = false;"):
				_fail("contact foam candidate requires local-front water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var candidate_path := output_dir.path_join(
				"%s_%s_%s_contact_foam_candidate.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(candidate_path) != OK:
				_fail("contact foam candidate PNG write")
				return
			files.append(candidate_path)
			contact_foam_candidate_artifacts[String(camera_id)] = candidate_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_front_gate_candidate:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_front_gate = false;"):
				_fail("contact front gate requires local-front water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_front_gate", true)
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var front_gate_path := output_dir.path_join(
				"%s_%s_%s_contact_front_gate_candidate.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(front_gate_path) != OK:
				_fail("contact front gate candidate PNG write")
				return
			files.append(front_gate_path)
			contact_front_gate_candidate_artifacts[String(camera_id)] = front_gate_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", false)
			preview.water_material.set_shader_parameter(
				"prototype_contact_front_gate", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_wide_band_candidate:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_wide_band = false;"):
				_fail("contact wide band requires local-front water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_front_gate", true)
			preview.water_material.set_shader_parameter(
				"prototype_contact_wide_band", true)
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var wide_band_path := output_dir.path_join(
				"%s_%s_%s_contact_wide_band_candidate.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(wide_band_path) != OK:
				_fail("contact wide band candidate PNG write")
				return
			files.append(wide_band_path)
			contact_wide_band_candidate_artifacts[String(camera_id)] = wide_band_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", false)
			preview.water_material.set_shader_parameter(
				"prototype_contact_wide_band", false)
			preview.water_material.set_shader_parameter(
				"prototype_contact_front_gate", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_relaxed_front_candidate:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_relaxed_front_gate = false;"):
				_fail("relaxed contact front gate requires local-front water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_front_gate", true)
			preview.water_material.set_shader_parameter(
				"prototype_contact_relaxed_front_gate", true)
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var relaxed_front_path := output_dir.path_join(
				"%s_%s_%s_contact_relaxed_front_candidate.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(relaxed_front_path) != OK:
				_fail("relaxed contact front candidate PNG write")
				return
			files.append(relaxed_front_path)
			contact_relaxed_front_candidate_artifacts[String(camera_id)] = relaxed_front_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", false)
			preview.water_material.set_shader_parameter(
				"prototype_contact_relaxed_front_gate", false)
			preview.water_material.set_shader_parameter(
				"prototype_contact_front_gate", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_history_candidate:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_history_gate = false;"):
				_fail("contact history gate requires local-front water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_history_gate", true)
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var history_path := output_dir.path_join(
				"%s_%s_%s_contact_history_candidate.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(history_path) != OK:
				_fail("contact history candidate PNG write")
				return
			files.append(history_path)
			contact_history_candidate_artifacts[String(camera_id)] = history_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", false)
			preview.water_material.set_shader_parameter(
				"prototype_contact_history_gate", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_independent_contact_history:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_independent_history_gate = false;"):
				_fail("independent contact history requires local-front water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_independent_history_gate", true)
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var independent_history_path := output_dir.path_join(
				"%s_%s_%s_independent_contact_history.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(independent_history_path) != OK:
				_fail("independent contact history PNG write")
				return
			files.append(independent_history_path)
			independent_contact_history_artifacts[String(camera_id)] = independent_history_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_foam_candidate", false)
			preview.water_material.set_shader_parameter(
				"prototype_contact_independent_history_gate", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_depth_map:
			if not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_depth_debug = false;"):
				_fail("contact depth map requires reference water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_depth_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var contact_path := output_dir.path_join(
				"%s_%s_%s_contact_depth.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(contact_path) != OK:
				_fail("contact depth PNG write")
				return
			files.append(contact_path)
			contact_depth_artifacts[String(camera_id)] = contact_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_depth_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_height_map:
			if case_id != "coupled" or not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_height_debug = false;"):
				_fail("contact height map requires coupled reference water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_height_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var height_path := output_dir.path_join(
				"%s_%s_%s_contact_height.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(height_path) != OK:
				_fail("contact height PNG write")
				return
			files.append(height_path)
			contact_height_artifacts[String(camera_id)] = height_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_height_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_flat_crest:
			if case_id != "coupled" or not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_height_debug = false;"):
				_fail("flat crest contact map requires coupled reference water shader")
				return
			var previous_crest_height: Variant = preview.water_material.get_shader_parameter(
				"prototype_crest_height_m")
			if previous_crest_height == null or float(previous_crest_height) <= 0.0:
				_fail("flat crest contact map requires active crest")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_height_debug", true)
			preview.water_material.set_shader_parameter(
				"prototype_crest_height_m", 0.0)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var flat_path := output_dir.path_join(
				"%s_%s_%s_contact_flat_crest.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(flat_path) != OK:
				_fail("flat crest contact PNG write")
				return
			files.append(flat_path)
			contact_flat_crest_artifacts[String(camera_id)] = flat_path
			preview.water_material.set_shader_parameter(
				"prototype_crest_height_m", previous_crest_height)
			preview.water_material.set_shader_parameter(
				"prototype_contact_height_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_shared_bed:
			if case_id != "coupled" or not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_height_debug = false;") or shared_bed_triangles:
				_fail("shared-bed contact map requires coupled baseline")
				return
			preview.water_material.set_shader_parameter(
				"prototype_contact_height_debug", true)
			preview.water_material.set_shader_parameter(
				"prototype_shared_bed_triangles", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var shared_path := output_dir.path_join(
				"%s_%s_%s_contact_shared_bed.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(shared_path) != OK:
				_fail("shared-bed contact PNG write")
				return
			files.append(shared_path)
			contact_shared_bed_artifacts[String(camera_id)] = shared_path
			preview.water_material.set_shader_parameter(
				"prototype_shared_bed_triangles", false)
			preview.water_material.set_shader_parameter(
				"prototype_contact_height_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_vertex_fragment_delta:
			if case_id != "coupled" or not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_vertex_fragment_delta_debug = false;"):
				_fail("vertex-fragment delta requires coupled reference water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_vertex_fragment_delta_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var delta_path := output_dir.path_join(
				"%s_%s_%s_vertex_fragment_delta.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(delta_path) != OK:
				_fail("vertex-fragment delta PNG write")
				return
			files.append(delta_path)
			vertex_fragment_delta_artifacts[String(camera_id)] = delta_path
			preview.water_material.set_shader_parameter(
				"prototype_vertex_fragment_delta_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_visible_bed_height:
			if case_id != "coupled" or not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_visible_bed_height_debug = false;"):
				_fail("visible bed height requires coupled reference water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_render_grid_size", float(256 * preview.render_subdivision))
			preview.water_material.set_shader_parameter(
				"prototype_visible_bed_height_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var visible_path := output_dir.path_join(
				"%s_%s_%s_visible_bed_height.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(visible_path) != OK:
				_fail("visible bed height PNG write")
				return
			files.append(visible_path)
			visible_bed_height_artifacts[String(camera_id)] = visible_path
			preview.water_material.set_shader_parameter(
				"prototype_visible_bed_height_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_contact_residual:
			if case_id != "coupled" or not (preview.water_material.shader as Shader).code.contains(
				"uniform bool prototype_contact_residual_debug = false;"):
				_fail("contact residual requires coupled reference water shader")
				return
			preview.water_material.set_shader_parameter(
				"prototype_render_grid_size", float(256 * preview.render_subdivision))
			preview.water_material.set_shader_parameter(
				"prototype_contact_residual_debug", true)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var residual_path := output_dir.path_join(
				"%s_%s_%s_contact_residual.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(residual_path) != OK:
				_fail("contact residual PNG write")
				return
			files.append(residual_path)
			contact_residual_artifacts[String(camera_id)] = residual_path
			preview.water_material.set_shader_parameter(
				"prototype_contact_residual_debug", false)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_wet_finish_off:
			var previous_wet_finish: Variant = preview.terrain_material.get_shader_parameter(
				"use_wet_finish")
			if case_id != "coupled" or not (preview.terrain_material.shader as Shader).code.contains(
				"uniform bool use_wet_finish = true;") or previous_wet_finish == false:
				_fail("wet-finish control requires enabled coupled sand shader")
				return
			preview.terrain_material.set_shader_parameter("use_wet_finish", false)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var wet_finish_off_path := output_dir.path_join(
				"%s_%s_%s_wet_finish_off.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(wet_finish_off_path) != OK:
				_fail("wet finish off PNG write")
				return
			files.append(wet_finish_off_path)
			wet_finish_off_artifacts[String(camera_id)] = wet_finish_off_path
			preview.terrain_material.set_shader_parameter("use_wet_finish",
				true if previous_wet_finish == null else previous_wet_finish)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if write_wet_trace_candidate:
			var previous_trace_gain: Variant = preview.terrain_material.get_shader_parameter(
				"prototype_wet_trace_gain")
			if case_id != "coupled" or not (preview.terrain_material.shader as Shader).code.contains(
				"uniform float prototype_wet_trace_gain = 0.0;") or (previous_trace_gain != null and float(previous_trace_gain) != 0.0):
				_fail("wet-trace candidate requires disabled coupled shader uniform")
				return
			preview.terrain_material.set_shader_parameter(
				"prototype_wet_trace_gain", 1.0)
			for settle in 4:
				await RenderingServer.frame_post_draw
			var wet_trace_path := output_dir.path_join(
				"%s_%s_%s_wet_trace_candidate.png" % [run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(wet_trace_path) != OK:
				_fail("wet trace candidate PNG write")
				return
			files.append(wet_trace_path)
			wet_trace_candidate_artifacts[String(camera_id)] = wet_trace_path
			preview.terrain_material.set_shader_parameter(
				"prototype_wet_trace_gain",
				0.0 if previous_trace_gain == null else previous_trace_gain)
			for settle in 2:
				await RenderingServer.frame_post_draw
		if (camera_id in [&"oblique", &"foreground_low_left",
				&"foreground_low_right"] or \
				String(camera_id).begins_with("foreground_sweep_")) and \
				(foreground_occluder or transparent_foreground_occluder or \
				submerged_transparent_occluder):
			var water_mesh := preview.get_node("GpuWaterSurface") as MeshInstance3D
			water_mesh.visible = false
			for settle in 4:
				await RenderingServer.frame_post_draw
			var control_path := output_dir.path_join(
				"%s_%s_%s_foreground_no_water.png" % [
					run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(
					control_path) != OK:
				_fail("foreground control PNG write")
				return
			files.append(control_path)
			foreground_control_artifacts[String(camera_id)] = control_path
			if camera_id == &"oblique":
				foreground_control_artifact = control_path
			water_mesh.visible = true
			for settle in 4:
				await RenderingServer.frame_post_draw
		if camera_id in [&"oblique", &"topdown"] and write_optical_layers:
			var optical_modes := [
				{"name": "depth_layers", "layers": true, "bed_only": false,
					"caustics": true},
				{"name": "bed_only", "layers": false, "bed_only": true,
					"caustics": true},
				{"name": "bed_no_caustics", "layers": false, "bed_only": true,
					"caustics": false},
				{"name": "normal_no_caustics", "layers": false, "bed_only": false,
					"caustics": false},
			]
			var previous_caustics: bool = preview.terrain_material.get_shader_parameter(
				"phase2_caustics")
			for optical_mode in optical_modes:
				preview.water_material.set_shader_parameter(
					"prototype_depth_layers_debug", optical_mode.layers)
				preview.water_material.set_shader_parameter(
					"prototype_screen_bed_only", optical_mode.bed_only)
				preview.terrain_material.set_shader_parameter("phase2_caustics",
					previous_caustics and optical_mode.caustics)
				for settle in 4:
					await RenderingServer.frame_post_draw
				var optical_name := "topdown_%s" % optical_mode.name if \
					camera_id == &"topdown" else String(optical_mode.name)
				var optical_path := output_dir.path_join("%s_%s_%s.png" % [
					run_id, case_id, optical_name])
				if root.get_texture().get_image().save_png(optical_path) != OK:
					_fail("optical PNG write: " + optical_path)
					return
				files.append(optical_path)
				optical_layer_artifacts[optical_name] = optical_path
			preview.water_material.set_shader_parameter(
				"prototype_depth_layers_debug", false)
			preview.water_material.set_shader_parameter(
				"prototype_screen_bed_only", screen_bed_only)
			preview.terrain_material.set_shader_parameter("phase2_caustics",
				previous_caustics)
		if camera_id in [&"oblique", &"topdown"] and write_caustic_strengths:
			var previous_value: Variant = preview.terrain_material.get_shader_parameter(
				"prototype_caustic_strength")
			var previous_strength := float(previous_value) if previous_value != null else 1.0
			for candidate in [0.0, 0.4, 0.6]:
				preview.terrain_material.set_shader_parameter(
					"prototype_caustic_strength", candidate)
				for settle in 4:
					await RenderingServer.frame_post_draw
				var label := "off" if candidate == 0.0 else str(int(candidate * 100.0))
				var caustic_name := "topdown_caustic_%s" % label if \
					camera_id == &"topdown" else "caustic_%s" % label
				var caustic_path := output_dir.path_join("%s_%s_%s.png" % [
					run_id, case_id, caustic_name])
				if root.get_texture().get_image().save_png(caustic_path) != OK:
					_fail("caustic strength PNG write: " + caustic_path)
					return
				files.append(caustic_path)
				caustic_strength_artifacts["topdown_" + label if \
					camera_id == &"topdown" else label] = caustic_path
			preview.terrain_material.set_shader_parameter(
				"prototype_caustic_strength", previous_strength)
		if camera_id == &"topdown" and write_caustic_depth_composite:
			var old_bed_decay_value: Variant = preview.terrain_material.get_shader_parameter(
				"prototype_caustic_depth_decay_m")
			var old_bed_decay := float(old_bed_decay_value) if \
				old_bed_decay_value != null else 0.17
			var old_deep_extinction_value: Variant = preview.water_material.get_shader_parameter(
				"prototype_deep_extinction_m")
			var old_deep_extinction := float(old_deep_extinction_value) if \
				old_deep_extinction_value != null else 0.11
			var old_depth_caustics_value: Variant = preview.terrain_material.get_shader_parameter(
				"phase2_caustics")
			var old_depth_caustics := bool(old_depth_caustics_value) if \
				old_depth_caustics_value != null else true
			var old_bed_only_value: Variant = preview.water_material.get_shader_parameter(
				"prototype_screen_bed_only")
			var old_bed_only := bool(old_bed_only_value) if \
				old_bed_only_value != null else false
			for bed_decay in [0.17, 0.35]:
				preview.terrain_material.set_shader_parameter(
					"prototype_caustic_depth_decay_m", bed_decay)
				for deep_extinction in [0.11, 0.25]:
					preview.water_material.set_shader_parameter(
						"prototype_deep_extinction_m", deep_extinction)
					for caustics_enabled in [true, false]:
						preview.terrain_material.set_shader_parameter(
							"phase2_caustics", caustics_enabled)
						for settle in 4:
							await RenderingServer.frame_post_draw
						var depth_label := "b%d_e%d_%s" % [
							int(bed_decay * 100.0), int(deep_extinction * 100.0),
							"on" if caustics_enabled else "off"]
						var depth_composite_path := output_dir.path_join("%s_%s_depth_%s.png" % [
							run_id, case_id, depth_label])
						if root.get_texture().get_image().save_png(depth_composite_path) != OK:
							_fail("caustic depth composite PNG write: " + depth_composite_path)
							return
						files.append(depth_composite_path)
						caustic_depth_composite_artifacts[depth_label] = depth_composite_path
				if bed_decay == 0.35:
					preview.water_material.set_shader_parameter(
						"prototype_screen_bed_only", true)
					for caustics_enabled in [true, false]:
						preview.terrain_material.set_shader_parameter(
							"phase2_caustics", caustics_enabled)
						for settle in 4:
							await RenderingServer.frame_post_draw
						var bed_depth_label := "b35_bed_only_%s" % (
							"on" if caustics_enabled else "off")
						var bed_depth_path := output_dir.path_join("%s_%s_depth_%s.png" % [
							run_id, case_id, bed_depth_label])
						if root.get_texture().get_image().save_png(bed_depth_path) != OK:
							_fail("caustic bed-only PNG write: " + bed_depth_path)
							return
						files.append(bed_depth_path)
						caustic_depth_composite_artifacts[bed_depth_label] = bed_depth_path
					preview.water_material.set_shader_parameter(
						"prototype_screen_bed_only", old_bed_only)
			preview.terrain_material.set_shader_parameter(
				"prototype_caustic_depth_decay_m", old_bed_decay)
			preview.water_material.set_shader_parameter(
				"prototype_deep_extinction_m", old_deep_extinction)
			preview.terrain_material.set_shader_parameter("phase2_caustics", old_depth_caustics)
			preview.water_material.set_shader_parameter(
				"prototype_screen_bed_only", old_bed_only)
		if write_caustic_recovery:
			var recovery_pattern := preview.terrain_material.get_shader_parameter(
				"caustic_pattern") as Texture2D
			if recovery_pattern == null:
				_fail("caustic recovery pattern missing")
				return
			preview.water_material.set_shader_parameter(
				"prototype_caustic_pattern", recovery_pattern)
			var prior_recovery_value: Variant = preview.water_material.get_shader_parameter(
				"prototype_caustic_recovery_gain")
			var prior_recovery := float(prior_recovery_value) if \
				prior_recovery_value != null else 0.0
			var prior_bed_scale_value: Variant = preview.terrain_material.get_shader_parameter(
				"prototype_caustic_uv_scale")
			var prior_bed_scale := float(prior_bed_scale_value) if \
				prior_bed_scale_value != null else 1.0
			preview.terrain_material.set_shader_parameter(
				"prototype_caustic_uv_scale", caustic_recovery_scale)
			preview.water_material.set_shader_parameter(
				"prototype_caustic_recovery_uv_scale", caustic_recovery_scale)
			var prior_caustics_value: Variant = preview.terrain_material.get_shader_parameter(
				"phase2_caustics")
			var prior_caustics := bool(prior_caustics_value) if \
				prior_caustics_value != null else true
			var recovery_gains := [0.0, 0.5, 1.0] if camera_id == &"topdown" else \
				[0.0, 0.5]
			for recovery_gain in recovery_gains:
				for caustics_enabled in [true, false]:
					preview.terrain_material.set_shader_parameter(
						"phase2_caustics", caustics_enabled)
					preview.water_material.set_shader_parameter(
						"prototype_caustic_recovery_gain",
						recovery_gain if caustics_enabled else 0.0)
					for settle in 4:
						await RenderingServer.frame_post_draw
					var recovery_label := "%sg%d_%s" % [
						"" if camera_id == &"topdown" else String(camera_id) + "_",
						int(recovery_gain * 100.0),
						"on" if caustics_enabled else "off"]
					var recovery_path := output_dir.path_join("%s_%s_recovery_%s.png" % [
						run_id, case_id, recovery_label])
					if root.get_texture().get_image().save_png(recovery_path) != OK:
						_fail("caustic recovery PNG write: " + recovery_path)
						return
					files.append(recovery_path)
					caustic_recovery_artifacts[recovery_label] = recovery_path
			if camera_id == &"topdown" and write_caustic_recovery_times:
				var prior_visual_time: float = preview.visual_time_s
				var old_recovery_bed_only_value: Variant = \
					preview.water_material.get_shader_parameter("prototype_screen_bed_only")
				var old_recovery_bed_only := bool(old_recovery_bed_only_value) if \
					old_recovery_bed_only_value != null else false
				for phase_time in [6.0, 8.0, 10.0]:
					preview.set_visual_time(phase_time)
					for view_name in ["final", "bed"]:
						preview.water_material.set_shader_parameter(
							"prototype_screen_bed_only", view_name == "bed")
						for caustics_enabled in [true, false]:
							preview.terrain_material.set_shader_parameter(
								"phase2_caustics", caustics_enabled)
							preview.water_material.set_shader_parameter(
								"prototype_caustic_recovery_gain",
								0.5 if caustics_enabled else 0.0)
							for settle in 4:
								await RenderingServer.frame_post_draw
							var phase_label := "t%02d_%s_%s" % [int(phase_time),
								view_name, "on" if caustics_enabled else "off"]
							var phase_path := output_dir.path_join("%s_%s_recovery_%s.png" % [
								run_id, case_id, phase_label])
							if root.get_texture().get_image().save_png(phase_path) != OK:
								_fail("caustic recovery phase PNG write: " + phase_path)
								return
							files.append(phase_path)
							caustic_recovery_time_artifacts[phase_label] = phase_path
				preview.water_material.set_shader_parameter(
						"prototype_screen_bed_only", false)
				preview.set_visual_time(8.0)
				preview.terrain_material.set_shader_parameter("phase2_caustics", true)
				preview.water_material.set_shader_parameter(
					"prototype_caustic_recovery_gain", 0.5)
				for settle in 4:
					await RenderingServer.frame_post_draw
				for hold_label in ["return", "hold"]:
					if hold_label == "hold":
						var hold_start := Time.get_ticks_msec()
						while Time.get_ticks_msec() - hold_start < 1500:
							await RenderingServer.frame_post_draw
					if preview.completed_ticks != capture_tick or preview.tick_pending or \
							preview.visual_time_s != 8.0:
						_fail("caustic recovery freeze changed state/time")
						return
					var hold_path := output_dir.path_join("%s_%s_recovery_t08_%s.png" % [
						run_id, case_id, hold_label])
					if root.get_texture().get_image().save_png(hold_path) != OK:
						_fail("caustic recovery freeze PNG write: " + hold_path)
						return
					files.append(hold_path)
					caustic_recovery_time_artifacts["t08_" + hold_label] = hold_path
				preview.set_visual_time(prior_visual_time)
				preview.water_material.set_shader_parameter(
					"prototype_screen_bed_only", old_recovery_bed_only)
			preview.water_material.set_shader_parameter(
				"prototype_caustic_recovery_gain", prior_recovery)
			preview.terrain_material.set_shader_parameter(
				"prototype_caustic_uv_scale", prior_bed_scale)
			preview.water_material.set_shader_parameter(
				"prototype_caustic_recovery_uv_scale", 1.0)
			preview.terrain_material.set_shader_parameter("phase2_caustics", prior_caustics)
		if camera_id == &"oblique" and write_caustic_scales:
			var previous_strength_value: Variant = preview.terrain_material.get_shader_parameter(
				"prototype_caustic_strength")
			var previous_scale_value: Variant = preview.terrain_material.get_shader_parameter(
				"prototype_caustic_uv_scale")
			var restore_strength := float(previous_strength_value) if \
				previous_strength_value != null else 1.0
			var restore_scale := float(previous_scale_value) if \
				previous_scale_value != null else 1.0
			preview.terrain_material.set_shader_parameter("prototype_caustic_strength", 0.4)
			for candidate_scale in [1.0, 1.5, 2.0, 3.0]:
				preview.terrain_material.set_shader_parameter(
					"prototype_caustic_uv_scale", candidate_scale)
				for settle in 4:
					await RenderingServer.frame_post_draw
				var label := str(int(candidate_scale * 10.0))
				var scale_path := output_dir.path_join("%s_%s_caustic_scale_%s.png" % [
					run_id, case_id, label])
				if root.get_texture().get_image().save_png(scale_path) != OK:
					_fail("caustic scale PNG write: " + scale_path)
					return
				files.append(scale_path)
				caustic_scale_artifacts[label] = scale_path
			preview.terrain_material.set_shader_parameter("prototype_caustic_strength",
				restore_strength)
			preview.terrain_material.set_shader_parameter("prototype_caustic_uv_scale",
				restore_scale)
		if camera_id == &"oblique" and write_caustic_times:
			var old_time_value: Variant = preview.terrain_material.get_shader_parameter(
				"visual_time_s")
			var old_strength_value: Variant = preview.terrain_material.get_shader_parameter(
				"prototype_caustic_strength")
			var old_scale_value: Variant = preview.terrain_material.get_shader_parameter(
				"prototype_caustic_uv_scale")
			var old_time := float(old_time_value) if old_time_value != null else \
				float(capture_tick) / 30.0
			var old_strength := float(old_strength_value) if old_strength_value != null else 1.0
			var old_scale := float(old_scale_value) if old_scale_value != null else 1.0
			preview.terrain_material.set_shader_parameter("prototype_caustic_strength", 0.4)
			preview.terrain_material.set_shader_parameter("prototype_caustic_uv_scale", 1.0)
			for sample in [{"label": "06", "time": 6.0},
					{"label": "08", "time": 8.0}, {"label": "10", "time": 10.0}]:
				preview.terrain_material.set_shader_parameter("visual_time_s", sample.time)
				for settle in 4:
					await RenderingServer.frame_post_draw
				var phase_path := output_dir.path_join("%s_%s_caustic_time_%s.png" % [
					run_id, case_id, sample.label])
				if root.get_texture().get_image().save_png(phase_path) != OK:
					_fail("caustic time PNG write: " + phase_path)
					return
				files.append(phase_path)
				caustic_time_artifacts[sample.label] = phase_path
			preview.terrain_material.set_shader_parameter("visual_time_s", old_time)
			preview.terrain_material.set_shader_parameter("prototype_caustic_strength",
				old_strength)
			preview.terrain_material.set_shader_parameter("prototype_caustic_uv_scale",
				old_scale)
		if camera_id == &"oblique" and write_extinction_sweep:
			var old_extinction_value: Variant = preview.water_material.get_shader_parameter(
				"prototype_shallow_extinction_m")
			var old_caustics_value: Variant = preview.terrain_material.get_shader_parameter(
				"phase2_caustics")
			var old_strength_value: Variant = preview.terrain_material.get_shader_parameter(
				"prototype_caustic_strength")
			var old_extinction := float(old_extinction_value) if \
				old_extinction_value != null else shallow_extinction_m
			var old_caustics := bool(old_caustics_value) if \
				old_caustics_value != null else true
			var old_strength := float(old_strength_value) if \
				old_strength_value != null else 1.0
			preview.terrain_material.set_shader_parameter("prototype_caustic_strength", 0.4)
			for sample in [{"label": "25", "extinction": 0.25},
					{"label": "30", "extinction": 0.30},
					{"label": "35", "extinction": 0.35}]:
				preview.water_material.set_shader_parameter(
					"prototype_shallow_extinction_m", sample.extinction)
				for caustics_enabled in [true, false]:
					preview.terrain_material.set_shader_parameter("phase2_caustics",
						old_caustics and caustics_enabled)
					for settle in 4:
						await RenderingServer.frame_post_draw
					var label := "%s_%s" % [sample.label,
						"on" if caustics_enabled else "off"]
					var sweep_path := output_dir.path_join("%s_%s_extinction_%s.png" % [
						run_id, case_id, label])
					if root.get_texture().get_image().save_png(sweep_path) != OK:
						_fail("extinction sweep PNG write: " + sweep_path)
						return
					files.append(sweep_path)
					extinction_sweep_artifacts[label] = sweep_path
			preview.water_material.set_shader_parameter("prototype_shallow_extinction_m",
				old_extinction)
			preview.terrain_material.set_shader_parameter("phase2_caustics", old_caustics)
			preview.terrain_material.set_shader_parameter("prototype_caustic_strength",
				old_strength)
		if write_optical_contributors and (camera_id == &"oblique" or optical_multiview):
			var saved_caustics: Variant = preview.terrain_material.get_shader_parameter(
				"phase2_caustics")
			var saved_refraction: Variant = preview.water_material.get_shader_parameter(
				"prototype_refraction_scale")
			var saved_reflection: Variant = preview.water_material.get_shader_parameter(
				"prototype_screen_sky_reflection_scale")
			var saved_bed_only: Variant = preview.water_material.get_shader_parameter(
				"prototype_screen_bed_only")
			var caustics_before := bool(saved_caustics) if saved_caustics != null else true
			var refraction_before := float(saved_refraction) if saved_refraction != null else 0.0
			var reflection_before := float(saved_reflection) if saved_reflection != null else 1.0
			var bed_only_before := bool(saved_bed_only) if saved_bed_only != null else false
			preview.terrain_material.set_shader_parameter("phase2_caustics", false)
			for sample in [{"label": "normal", "refraction": refraction_before,
					"reflection": reflection_before},
					{"label": "no_refraction", "refraction": 0.0,
					"reflection": reflection_before},
					{"label": "no_reflection", "refraction": refraction_before,
					"reflection": 0.0},
					{"label": "neither", "refraction": 0.0, "reflection": 0.0}]:
				preview.water_material.set_shader_parameter("prototype_refraction_scale",
					sample.refraction)
				preview.water_material.set_shader_parameter(
					"prototype_screen_sky_reflection_scale", sample.reflection)
				for settle in 4:
					await RenderingServer.frame_post_draw
				var contributor_label: String = sample.label if camera_id == &"oblique" else \
					"%s_%s" % [String(camera_id), sample.label]
				var contributor_path := output_dir.path_join(
					"%s_%s_optical_%s.png" % [run_id, case_id, contributor_label])
				if root.get_texture().get_image().save_png(contributor_path) != OK:
					_fail("optical contributor PNG write: " + contributor_path)
					return
				files.append(contributor_path)
				optical_contributor_artifacts[contributor_label] = contributor_path
				preview.water_material.set_shader_parameter("prototype_screen_bed_only", true)
				for settle in 4:
					await RenderingServer.frame_post_draw
				var bed_path := output_dir.path_join("%s_%s_optical_%s_bed.png" % [
					run_id, case_id, contributor_label])
				if root.get_texture().get_image().save_png(bed_path) != OK:
					_fail("optical contributor bed PNG write: " + bed_path)
					return
				files.append(bed_path)
				optical_contributor_bed_artifacts[contributor_label] = bed_path
				preview.water_material.set_shader_parameter("prototype_screen_bed_only",
					bed_only_before)
			preview.terrain_material.set_shader_parameter("phase2_caustics",
				caustics_before)
			preview.water_material.set_shader_parameter("prototype_refraction_scale",
				refraction_before)
			preview.water_material.set_shader_parameter(
				"prototype_screen_sky_reflection_scale", reflection_before)
			preview.water_material.set_shader_parameter("prototype_screen_bed_only",
				bed_only_before)
		if camera_id in [&"oblique", &"grazing"] and write_refraction_edge:
			var original_scale: float = preview.water_material.get_shader_parameter(
				"prototype_refraction_scale")
			var edge_images := {}
			preview.water_material.set_shader_parameter("prototype_refraction_scale",
				-0.2)
			for edge_mode in ["fallback", "legacy", "debug"]:
				preview.water_material.set_shader_parameter(
					"prototype_legacy_edge_clamp", edge_mode == "legacy")
				preview.water_material.set_shader_parameter(
					"prototype_refraction_fallback_debug", edge_mode == "debug")
				for settle in 4:
					await RenderingServer.frame_post_draw
				var edge_path := output_dir.path_join("%s_%s_%s_%s.png" % [
					run_id, case_id, camera_id, edge_mode])
				if root.get_texture().get_image().save_png(edge_path) != OK:
					_fail("refraction edge PNG write: " + edge_path)
					return
				files.append(edge_path)
				edge_images[edge_mode] = edge_path
			refraction_edge_artifacts[String(camera_id)] = edge_images
			preview.water_material.set_shader_parameter("prototype_refraction_scale",
				original_scale)
			preview.water_material.set_shader_parameter("prototype_legacy_edge_clamp",
				false)
			preview.water_material.set_shader_parameter(
				"prototype_refraction_fallback_debug", false)
		if planar_reflection_probe:
			var reflected_path := output_dir.path_join("%s_%s_%s_reflected.png" % [
				run_id, case_id, camera_id])
			if reflection_viewport.get_texture().get_image().save_png(
					reflected_path) != OK:
				_fail("reflected PNG write: " + reflected_path)
				return
			files.append(reflected_path)
		if camera_id == &"oblique" and pause_hold_ms > 0:
			var hold_start_ms := Time.get_ticks_msec()
			while Time.get_ticks_msec() - hold_start_ms < pause_hold_ms and \
					pause_hold_frames < 1000:
				await RenderingServer.frame_post_draw
				pause_hold_frames += 1
			pause_hold_elapsed_ms = Time.get_ticks_msec() - hold_start_ms
			if pause_hold_elapsed_ms < pause_hold_ms or \
					preview.completed_ticks != capture_tick or preview.tick_pending or \
					preview.visual_time_s != float(capture_tick) / 30.0 or \
					str(root.get_camera_3d().global_transform) != cameras[String(camera_id)].transform:
				_fail("paused hold changed tick/time/camera or timed out")
				return
			var hold_path := output_dir.path_join("%s_%s_%s_hold.png" % [
				run_id, case_id, camera_id])
			if root.get_texture().get_image().save_png(hold_path) != OK:
				_fail("paused hold PNG write: " + hold_path)
				return
			files.append(hold_path)
	var resumed_frames := []
	for target_tick in resume_target_ticks:
		preview.playing = true
		var resume_wait_frames := 0
		while preview.completed_ticks < target_tick - 1 and \
				preview.last_error.is_empty() and resume_wait_frames < 72000:
			await process_frame
			resume_wait_frames += 1
		preview.playing = false
		while preview.tick_pending and resume_wait_frames < 75000:
			await process_frame
			resume_wait_frames += 1
		while preview.completed_ticks < target_tick and \
				preview.last_error.is_empty() and resume_wait_frames < 78000:
			if not preview.tick_pending and not preview.checkpoint_capture_pending:
				preview._start_tick()
			await process_frame
			resume_wait_frames += 1
		if preview.completed_ticks != target_tick or preview.tick_pending or \
				not preview.last_error.is_empty():
			_fail("resume exact tick failed: got %d expected %d error=%s" % [
				preview.completed_ticks, target_tick, preview.last_error])
			return
		preview.set_visual_time(float(target_tick) / 30.0)
		if not preview.set_fixture_camera(&"oblique"):
			_fail("resume oblique camera missing")
			return
		for warmup_frame in 30:
			await RenderingServer.frame_post_draw
		var resume_path := output_dir.path_join("%s_%s_resume_tick%d_oblique.png" % [
			run_id, case_id, target_tick])
		if root.get_texture().get_image().save_png(resume_path) != OK:
			_fail("resume PNG write: " + resume_path)
			return
		files.append(resume_path)
		resumed_frames.append({"tick": target_tick,
			"revision": preview.solver.state_revision,
			"visual_time_s": preview.visual_time_s,
			"camera_transform": str(root.get_camera_3d().global_transform),
			"artifact": resume_path})
	var runtime_capabilities := {}
	if capability_probe:
		runtime_capabilities = _runtime_capabilities(preview)
		if not runtime_capabilities.get("valid", false):
			_fail("runtime capability probe: " + str(runtime_capabilities.get("errors", [])))
			return
	if not render_profile.is_empty():
		var expected_terrain: String = render_profile.resources.terrain_coupled_shader if \
			case_id == "coupled" else render_profile.resources.terrain_fixed_shader
		if preview.water_material.shader.resource_path != render_profile.resources.water_shader or \
				preview.terrain_material.shader.resource_path != expected_terrain or \
				preview.water_material.get_shader_parameter("phase2_foam") != \
				render_profile.capabilities.main_foam.enabled or \
				not is_equal_approx(float(preview.water_material.get_shader_parameter(
					"water_surface_bias_m")), float(render_profile.surface_bias_m)):
			_fail("render profile effective values mismatch")
			return
	var manifest := {
		"role": "w08_staging_profile_capture" if not render_profile.is_empty() else "w07_reference_prototype",
		"run_id": run_id,
		"fixture_id": String(preview.fixture_id),
		"case": case_id,
		"profile_id": render_profile.profile_id if not render_profile.is_empty() else \
			("prototype_reference_fixed" if case_id == "water" else "prototype_reference_coupled"),
		"tick": capture_tick,
		"generation": preview.generation,
		"revision": capture_revision,
		"substep_trace": preview.capture_substep_rows.map(func(row: Vector3i) -> Array:
			return [row.x, row.y, row.z]) if write_substep_trace else [],
		"visual_time_s": float(capture_tick) / 30.0,
		"pause_hold_requested_ms": pause_hold_ms,
		"pause_hold_elapsed_ms": pause_hold_elapsed_ms,
		"pause_hold_frames": pause_hold_frames,
		"resumed_frames": resumed_frames,
		"render_subdivision": preview.render_subdivision,
		"prototype_smooth_reference_shore": smooth_reference_shore,
		"prototype_natural_reference_shore": natural_reference_shore,
		"prototype_structured_reference_bed": structured_reference_bed,
		"prototype_sculpted_reference_bed": sculpted_reference_bed,
		"prototype_lobed_reference_bed": lobed_reference_bed,
		"prototype_branched_reference_bed": branched_reference_bed,
		"prototype_estuary_reference_bed": estuary_reference_bed,
		"topdown_camera": topdown_camera,
		"orthographic_shore_probe": orthographic_shore_probe,
		"effective_water_shader": preview.water_material.shader.resource_path,
		"water_shader_sha256": FileAccess.get_sha256(
			preview.water_material.shader.resource_path) if not \
			preview.water_material.shader.resource_path.is_empty() else "",
		"terrain_shader_sha256": FileAccess.get_sha256(
			preview.terrain_material.shader.resource_path) if not \
			preview.terrain_material.shader.resource_path.is_empty() else "",
		"shader_probe": shader_probe,
		"effective_display_reconstruction": preview.water_material.get_shader_parameter(
			"display_reconstruction"),
		"water_mesh_vertex_count": (preview.get_node("GpuWaterSurface") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
		"grid_size": preview.shadow_domain.grid_size,
		"cell_size_m": preview.shadow_domain.cell_size_m,
		"sim_hz": 30,
		"camera": cameras,
		"wave_requests": requested_waves,
		"wave_workload_id": profile_wave_workload_id if not render_profile.is_empty() or \
			profile_wave_workload_id != "single_packet_v1" else \
			("legacy_single_packet" if with_wave else "none"),
		"prototype_eta_normals": eta_normals,
		"prototype_screen_optics": screen_optics,
		"prototype_optical_shallow_preserve": optical_shallow_preserve,
		"prototype_screen_deep_scatter_scale": screen_deep_scatter_scale,
		"prototype_screen_sky_reflection_scale": screen_sky_reflection_scale,
		"prototype_screen_fresnel_debug": screen_fresnel_debug,
		"prototype_screen_abs_fresnel": screen_abs_fresnel,
		"prototype_screen_face_normal": screen_face_normal,
		"prototype_screen_scene_reflection": screen_scene_reflection,
		"prototype_screen_world_glint": screen_world_glint,
		"prototype_screen_world_glint_opposite": screen_world_glint_opposite,
		"prototype_screen_reflection_debug": screen_reflection_debug,
		"prototype_screen_bed_only": screen_bed_only,
		"prototype_shallow_extinction_m": shallow_extinction_m,
		"prototype_planar_reflection_probe": planar_reflection_probe,
		"prototype_planar_reflection_water": planar_reflection_water,
		"prototype_planar_reflection_debug": planar_reflection_debug,
		"prototype_planar_reflection_projected": planar_reflection_projected,
		"prototype_planar_reflection_viewport_px": [planar_reflection_size.x, planar_reflection_size.y] if planar_reflection_probe else [],
		"prototype_depth_bands": depth_bands,
		"write_optical_layers": write_optical_layers,
		"write_foam_flow_detail": write_foam_flow_detail,
		"foam_flow_detail_artifacts": foam_flow_detail_artifacts,
		"write_shoreline_mask": write_shoreline_mask,
		"shoreline_mask_artifacts": shoreline_mask_artifacts,
		"write_shore_contour_candidate": write_shore_contour_candidate,
		"shore_contour_candidate_artifacts": shore_contour_candidate_artifacts,
		"write_bed_only_multiview": write_bed_only_multiview,
		"bed_only_multiview_artifacts": bed_only_multiview_artifacts,
		"depth_band_multiview_artifacts": depth_band_multiview_artifacts,
		"depth_gray_multiview_artifacts": depth_gray_multiview_artifacts,
		"write_contact_alpha_map": write_contact_alpha_map,
		"contact_alpha_artifacts": contact_alpha_artifacts,
		"write_shore_source_map": write_shore_source_map,
		"shore_source_artifacts": shore_source_artifacts,
		"write_contact_foam_source": write_contact_foam_source,
		"contact_foam_source_artifacts": contact_foam_source_artifacts,
		"write_contact_foam_candidate": write_contact_foam_candidate,
		"contact_foam_candidate_artifacts": contact_foam_candidate_artifacts,
		"write_contact_front_gate_candidate": write_contact_front_gate_candidate,
		"contact_front_gate_candidate_artifacts": contact_front_gate_candidate_artifacts,
		"write_contact_wide_band_candidate": write_contact_wide_band_candidate,
		"contact_wide_band_candidate_artifacts": contact_wide_band_candidate_artifacts,
		"write_contact_relaxed_front_candidate": write_contact_relaxed_front_candidate,
		"contact_relaxed_front_candidate_artifacts": contact_relaxed_front_candidate_artifacts,
		"write_contact_history_candidate": write_contact_history_candidate,
		"contact_history_candidate_artifacts": contact_history_candidate_artifacts,
		"write_independent_contact_history": write_independent_contact_history,
		"independent_contact_history_artifacts": independent_contact_history_artifacts,
		"write_contact_depth_map": write_contact_depth_map,
		"contact_depth_artifacts": contact_depth_artifacts,
		"write_contact_height_map": write_contact_height_map,
		"contact_height_artifacts": contact_height_artifacts,
		"write_contact_flat_crest": write_contact_flat_crest,
		"contact_flat_crest_artifacts": contact_flat_crest_artifacts,
		"write_contact_shared_bed": write_contact_shared_bed,
		"contact_shared_bed_artifacts": contact_shared_bed_artifacts,
		"write_vertex_fragment_delta": write_vertex_fragment_delta,
		"vertex_fragment_delta_artifacts": vertex_fragment_delta_artifacts,
		"write_visible_bed_height": write_visible_bed_height,
		"visible_bed_height_artifacts": visible_bed_height_artifacts,
		"write_contact_residual": write_contact_residual,
		"contact_residual_artifacts": contact_residual_artifacts,
		"write_wet_finish_off": write_wet_finish_off,
		"wet_finish_off_artifacts": wet_finish_off_artifacts,
		"write_wet_trace_candidate": write_wet_trace_candidate,
		"wet_trace_candidate_artifacts": wet_trace_candidate_artifacts,
		"write_refraction_edge": write_refraction_edge,
		"refraction_edge_artifacts": refraction_edge_artifacts,
		"foreground_occluder": foreground_occluder,
		"transparent_foreground_occluder": transparent_foreground_occluder,
		"submerged_transparent_occluder": submerged_transparent_occluder,
		"foreground_control_artifact": foreground_control_artifact,
		"foreground_control_artifacts": foreground_control_artifacts,
		"foreground_multiview": foreground_multiview,
		"foreground_sweep": foreground_sweep,
		"caustic_strength_artifacts": caustic_strength_artifacts,
		"caustic_scale_artifacts": caustic_scale_artifacts,
		"caustic_time_artifacts": caustic_time_artifacts,
		"caustic_depth_composite_artifacts": caustic_depth_composite_artifacts,
		"caustic_recovery_artifacts": caustic_recovery_artifacts,
		"caustic_recovery_time_artifacts": caustic_recovery_time_artifacts,
		"caustic_recovery_scale": caustic_recovery_scale,
		"extinction_sweep_artifacts": extinction_sweep_artifacts,
		"optical_contributor_artifacts": optical_contributor_artifacts,
		"optical_contributor_bed_artifacts": optical_contributor_bed_artifacts,
		"optical_multiview": optical_multiview,
		"optical_layer_artifacts": optical_layer_artifacts,
		"prototype_refraction_scale": refraction_scale,
		"prototype_depth_guard": depth_guard,
		"prototype_crest_height_m": crest_height_m,
		"prototype_local_back_cells": local_back_cells,
		"prototype_local_face_cells": local_face_cells,
		"prototype_local_lift_depth_scale": local_lift_depth_scale,
		"prototype_crest_shore_depth_m": crest_shore_depth_m,
		"prototype_curl_forward_m": curl_forward_m,
		"prototype_local_overturn_m": local_overturn_m,
		"prototype_integrated_fold_m": integrated_fold_m,
		"prototype_crest_white_face": crest_white_face,
		"prototype_crest_span_smoothing": crest_span_smoothing,
		"prototype_crest_depth_gate_bypass": crest_depth_gate_bypass,
		"prototype_geometry_silhouette": geometry_silhouette,
		"prototype_geometry_alpha": geometry_alpha,
		"prototype_geometry_keep_alpha": geometry_keep_alpha,
		"prototype_geometry_keep_color": geometry_keep_color,
		"prototype_crest_fragment_foam": crest_fragment_foam,
		"prototype_crest_broken_core": crest_broken_core,
		"prototype_offshore_core": offshore_core,
		"prototype_offshore_core_broken": offshore_core_broken,
		"prototype_offshore_core_crown": offshore_core_crown,
		"prototype_front_face_rim_tone": front_face_rim_tone,
		"prototype_front_face_foam_gate": front_face_foam_gate,
		"prototype_front_face_source_gate": front_face_source_gate,
		"prototype_depth_write": depth_write,
		"prototype_depth_prepass": depth_prepass,
		"prototype_crest_curtain": crest_curtain,
		"prototype_crest_ribbon": crest_ribbon,
		"prototype_crest_ribbon_body": crest_ribbon_body,
		"prototype_crest_ribbon_attached": crest_ribbon_attached,
		"prototype_crest_ribbon_smooth_mask": crest_ribbon_smooth_mask,
		"prototype_crest_rise_ribbon": crest_rise_ribbon,
		"prototype_crest_solid_lip": crest_solid_lip,
		"prototype_crest_water_body": crest_water_body,
		"prototype_crest_lip_only": crest_lip_only,
		"prototype_crest_ribbon_depth_write": crest_ribbon_depth_write,
		"prototype_crest_row_min": crest_row_min,
		"prototype_crest_row_max": crest_row_max,
		"prototype_shore_vertex_project": shore_vertex_project,
		"prototype_porous_foam": porous_foam,
		"prototype_foam_overlay": foam_overlay,
		"prototype_foam_splats": foam_splats,
		"prototype_foam_splats_jitter": foam_splats_jitter,
		"prototype_foam_front_splats": foam_front_splats,
		"prototype_foam_front_local_dense": foam_front_local_dense,
		"prototype_foam_front_local_diameter_px": foam_front_local_diameter_px,
		"prototype_foam_front_smooth": foam_front_smooth,
		"prototype_foam_splats_fine": foam_splats_fine,
		"prototype_foam_front_raised": foam_front_raised,
		"prototype_foam_front_pixel_sized": foam_front_pixel_sized,
		"prototype_crest_volume": crest_volume,
		"prototype_crest_volume_debug": crest_volume_debug,
		"prototype_local_front_profile": local_front_profile,
		"prototype_branch_face": branch_face,
		"prototype_branch_face_capped": branch_face_capped,
		"prototype_branch_face_2d": branch_face_2d,
		"prototype_branch_face_patches": branch_face_patches,
		"prototype_branch_face_row_center": branch_face_row_center,
		"prototype_branch_face_soft_material": branch_face_soft_material,
		"prototype_branch_face_surface_join": branch_face_surface_join,
		"prototype_local_front_wide_field": local_front_wide_field,
		"prototype_local_front_volume": local_front_volume,
		"prototype_local_front_segments": local_front_segments,
		"prototype_local_front_continuous_lip": local_front_continuous_lip,
		"prototype_foam_suppressed": foam_suppressed,
		"prototype_foam_overlay_debug": foam_overlay_debug,
		"prototype_foam_overlay_coverage": foam_overlay_coverage,
		"prototype_front_profile": front_profile,
		"prototype_front_foam": front_foam,
		"prototype_crest_smooth_window": crest_smooth_window,
		"prototype_crest_forward_toe": crest_forward_toe,
		"prototype_crest_main_flat": crest_main_flat,
		"prototype_no_main_foam": no_main_foam,
		"prototype_shared_boundary": shared_boundary,
		"prototype_unified_curl": unified_curl,
		"prototype_unified_debug": unified_debug,
		"prototype_unified_sealed": unified_sealed,
		"prototype_unified_variable": unified_variable,
		"prototype_unified_porous_cap": unified_porous_cap,
		"prototype_unified_dense": unified_dense,
		"prototype_unified_smooth_profile": unified_smooth_profile,
		"prototype_unified_no_depth": unified_no_depth,
		"prototype_unified_opaque": unified_opaque,
		"prototype_unified_sparse_cap": unified_sparse_cap,
		"prototype_unified_supported_front": unified_supported_front,
		"prototype_unified_local_support": unified_local_support,
		"prototype_unified_2d_support": unified_2d_support,
		"prototype_unified_expanded_front_range": unified_expanded_front_range,
		"prototype_unified_centered_base": unified_centered_base,
		"prototype_unified_monotonic_base": unified_monotonic_base,
		"prototype_unified_field_base": unified_field_base,
		"prototype_unified_localized_base": unified_localized_base,
		"prototype_unified_inactive_anchor": unified_inactive_anchor,
		"prototype_unified_adaptive_anchor": unified_adaptive_anchor,
		"prototype_unified_alpha_seal": unified_alpha_seal,
		"prototype_unified_fragment_wet": unified_fragment_wet,
		"prototype_unified_wet_toe": unified_wet_toe,
		"prototype_unified_smooth_support": unified_smooth_support,
		"prototype_unified_body_scale": unified_body_scale,
		"prototype_unified_overturn": unified_overturn,
		"prototype_unified_layer_debug": unified_layer_debug,
		"prototype_unified_broad_back": unified_broad_back,
		"prototype_unified_overturn_cap": unified_overturn_cap,
		"prototype_unified_surface_probe": unified_surface_probe,
		"prototype_unified_front_wall": unified_front_wall,
		"prototype_unified_row_min": unified_row_min,
		"prototype_unified_row_max": unified_row_max,
		"prototype_rise_crest": rise_crest,
		"prototype_rise_front_field": front_field,
		"prototype_shared_bed_triangles": shared_bed_triangles,
		"prototype_midpoint_clip": midpoint_clip,
		"prototype_radial_shore": radial_shore,
		"prototype_shore_unscaled_depth": shore_unscaled_depth,
		"prototype_shore_linear_weights": shore_linear_weights,
		"prototype_shoreline_debug": shoreline_debug,
		"prototype_irregular_foam": irregular_foam,
		"prototype_aperiodic_foam": aperiodic_foam,
		"prototype_offshore_foam_source": offshore_foam_source,
		"prototype_front_band_foam_source": front_band_foam_source,
		"prototype_front_foam_blend": front_foam_blend,
		"prototype_front_foam_ribbon": front_foam_ribbon,
		"prototype_broad_crest": broad_crest,
		"prototype_coupled_caustics": coupled_caustics and not no_caustics,
		"prototype_no_caustics": no_caustics,
		"prototype_cell_caustics": cell_caustics,
		"prototype_fold_caustics": fold_caustics,
		"prototype_sync_boundary_readback": sync_boundary_readback,
		"foam_summary": foam_summary,
		"foam_field_artifact": foam_field_path,
		"foam_history_artifact": foam_history_path,
		"water_field_artifact": water_field_path,
		"rock_field_artifact": rock_field_path,
		"sand_field_artifact": sand_field_path,
		"wetness_field_artifact": wetness_field_path,
		"previous_foam_artifact": previous_foam_path,
		"front_field_artifact": front_field_path,
		"local_front_field_artifact": local_front_field_path,
		"independent_contact_history_field_artifact": independent_contact_history_field_path,
		"initial_state_hashes": initial_state_hashes,
		"viewport_px": [root.size.x, root.size.y],
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"hardware": RenderingServer.get_video_adapter_name(),
		"artifacts": files,
	}
	if capability_probe:
		manifest["runtime_capabilities"] = runtime_capabilities
	if not render_profile.is_empty():
		manifest["schema_version"] = render_profile.schema_version
		manifest["requested_profile"] = render_profile_path
		manifest["requested_profile_sha256"] = render_profile_sha256
		manifest["effective_profile"] = RenderProfile.effective_from_materials(
			render_profile, preview.fixture_id, preview.water_material,
			preview.terrain_material, preview.render_subdivision,
			preview.visual_time_s, "estuary_branched_v1" if \
			preview.prototype_estuary_reference_bed else "natural_structured_v1")
		manifest["effective_profile_sha256"] = JSON.stringify(
			manifest.effective_profile).sha256_text()
	var manifest_path := output_dir.path_join("%s_%s_manifest.json" % [run_id, case_id])
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("manifest write: " + manifest_path)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: WR reference prototype %s tick=%d files=%d" % [case_id, capture_tick, files.size()])
	quit(0)


func _runtime_capabilities(preview: Node3D) -> Dictionary:
	var errors: Array[String] = []
	var terrain: ShaderMaterial = preview.terrain_material
	var water: ShaderMaterial = preview.water_material
	var terrain_resources := _material_resources(terrain,
		["rock_state", "sand_state", "wetness_state", "compaction_state",
		"water_state"], errors, "terrain")
	var water_resources := _material_resources(water,
		["rock_state", "sand_state", "water_state", "momentum_x_state",
		"momentum_z_state", "foam_state", "local_front_state"] if
		local_front_profile else ["rock_state", "sand_state", "water_state",
		"momentum_x_state", "momentum_z_state", "foam_state"],
		errors, "water")
	var terrain_caustics: Variant = terrain.get_shader_parameter("phase2_caustics")
	var water_optics: Variant = water.get_shader_parameter("prototype_screen_optics")
	var water_normals: Variant = water.get_shader_parameter("prototype_eta_normals")
	var water_foam: Variant = water.get_shader_parameter("phase2_foam")
	if typeof(terrain_caustics) != TYPE_BOOL or \
			terrain_caustics != (not no_caustics and
			(case_id == "water" or coupled_caustics)):
		errors.append("terrain phase2_caustics effective value mismatch")
	if local_front_profile and (water_optics != screen_optics or
			water_normals != eta_normals):
		errors.append("water optical/normal effective value mismatch")
	if typeof(water_foam) != TYPE_BOOL or (no_main_foam and water_foam):
		errors.append("water phase2_foam effective value mismatch")
	return {"valid": errors.is_empty(), "errors": errors,
		"terrain_shader": terrain.shader.resource_path,
		"water_shader": water.shader.resource_path,
		"terrain_resources": terrain_resources,
		"water_resources": water_resources,
		"terrain_phase2_caustics": terrain_caustics,
		"water_screen_optics": water_optics,
		"water_eta_normals": water_normals,
		"water_phase2_foam": water_foam,
		"terrain_uniforms": UniformSnapshot.material_values(terrain),
		"water_uniforms": UniformSnapshot.material_values(water),
		"terrain_caustic_pattern": _texture_status(terrain.get_shader_parameter(
			"caustic_pattern")) if (cell_caustics or fold_caustics) else {}}


func _material_resources(material: ShaderMaterial, names: Array,
		errors: Array[String], material_name: String) -> Dictionary:
	var values := {}
	for name in names:
		if not material.shader.code.contains("uniform sampler2D " + name):
			errors.append(material_name + " shader lacks " + name)
		var status := _texture_status(material.get_shader_parameter(name))
		values[name] = status
		if not status.get("bound", false):
			errors.append(material_name + " missing " + name)
	return values


func _texture_status(value: Variant) -> Dictionary:
	var texture := value as Texture2D
	return {"bound": texture != null,
		"class": texture.get_class() if texture != null else "",
		"width": texture.get_width() if texture != null else 0,
		"height": texture.get_height() if texture != null else 0}


func _fail(message: String) -> void:
	push_error("FAIL: WR reference prototype " + message)
	quit(1)


func _request_foam_readback(preview: Node3D) -> void:
	if preview.foam_field.request_data(_on_readback.bind("foam")) != OK:
		call_deferred("_receive_readback", PackedByteArray(), "foam")
	if preview.solver.request_data("water", _on_readback.bind("water")) != OK:
		call_deferred("_receive_readback", PackedByteArray(), "water")
	if write_bed_fields:
		for field_name in ["rock", "sand"]:
			if preview.solver.request_data(field_name, _on_readback.bind(field_name)) != OK:
				call_deferred("_receive_readback", PackedByteArray(), field_name)
	if write_wetness_field:
		if preview.solver.request_data("wetness", _on_readback.bind("wetness")) != OK:
			call_deferred("_receive_readback", PackedByteArray(), "wetness")
	if write_previous_foam:
		var previous_rid: RID = preview.foam_field.textures[1 - preview.foam_field.current_index]
		if preview.foam_field.rd.texture_get_data_async(previous_rid, 0,
			_on_readback.bind("previous_foam")) != OK:
			call_deferred("_receive_readback", PackedByteArray(), "previous_foam")
	if write_front_field:
		if preview.rise_front_field == null or preview.rise_front_field.request_data(
			_on_readback.bind("front")) != OK:
			call_deferred("_receive_readback", PackedByteArray(), "front")
	if write_local_front_field:
		if preview.local_front_field == null or preview.local_front_field.request_data(
			_on_readback.bind("local_front")) != OK:
			call_deferred("_receive_readback", PackedByteArray(), "local_front")
	if write_independent_contact_history:
		if preview.contact_history_field == null or preview.contact_history_field.request_data(
			_on_readback.bind("contact_history")) != OK:
			call_deferred("_receive_readback", PackedByteArray(), "contact_history")


func _on_readback(data: PackedByteArray, field: String) -> void:
	call_deferred("_receive_readback", data, field)


func _receive_readback(data: PackedByteArray, field: String) -> void:
	readbacks[field] = data
