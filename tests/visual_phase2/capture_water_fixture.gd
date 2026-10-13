extends SceneTree

const SCENE := preload("res://scenes/water_visual_fixture.tscn")
const Fixture = preload("res://scripts/scenarios/water_visual_fixture.gd")
const OUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/"
const CAPTURE_TICK := 60
const VISUAL_TIME_S := 6.0
var capture_tick := CAPTURE_TICK
var with_wave := false
var phase2_optics := false
var reconstruction := false
var reconstruction_subdivision := 2
var radial_shore := false
var shoreline_debug := false
var midpoint_clip := false
var optics_component := "all"
var water_surface_bias_m := 0.006

var preview: Node3D
var elapsed_frames := 0
var field_bytes: Dictionary = {}
var readback_error := ""


func _init() -> void:
	phase2_optics = "--phase2-optics" in OS.get_cmdline_user_args()
	reconstruction = "--reconstruction" in OS.get_cmdline_user_args()
	radial_shore = "--radial-shore" in OS.get_cmdline_user_args()
	shoreline_debug = "--shoreline-debug" in OS.get_cmdline_user_args()
	midpoint_clip = "--midpoint-clip" in OS.get_cmdline_user_args()
	with_wave = "--wave" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-tick="):
			capture_tick = int(arg.trim_prefix("--capture-tick="))
		if arg.begins_with("--component="):
			optics_component = arg.trim_prefix("--component=")
		if arg.begins_with("--subdivision="):
			reconstruction_subdivision = int(arg.trim_prefix("--subdivision="))
		if arg.begins_with("--water-bias="):
			water_surface_bias_m = float(arg.trim_prefix("--water-bias="))
	call_deferred("_run")


func _run() -> void:
	preview = SCENE.instantiate()
	# W01-W03 frozen image baselines predate the W05 history field.
	preview.enable_phase2_foam = false
	preview.render_subdivision = reconstruction_subdivision if reconstruction else 1
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty() and elapsed_frames < 1800:
		await process_frame
		elapsed_frames += 1
	if not _check(preview.ready_for_ticks, "fixture did not initialize"):
		return
	if not _check(preview.fixture_id == Fixture.FIXTURE_ID and not preview.enable_erosion and not preview.enable_structures, "water-only switches are wrong"):
		return
	if not _check(preview.material_coupler == null and preview.sediment_coupler == null and preview.structure_field == null, "water-only modules are running"):
		return
	preview.water_material.set_shader_parameter("phase2_optics", phase2_optics)
	preview.water_material.set_shader_parameter("water_surface_bias_m", water_surface_bias_m)
	preview.water_material.set_shader_parameter("radial_shore", radial_shore)
	preview.water_material.set_shader_parameter("shoreline_debug", shoreline_debug)
	preview.water_material.set_shader_parameter("midpoint_clip", midpoint_clip)
	preview.water_material.set_shader_parameter("use_detail_normals", optics_component != "no_detail")
	preview.water_material.set_shader_parameter("use_specular", optics_component != "no_specular")
	preview.water_material.set_shader_parameter("use_caustics", optics_component != "no_caustics")
	preview.terrain_material.set_shader_parameter("apply_underwater_tint", not phase2_optics)
	preview.terrain_material.set_shader_parameter("underwater_relief_boost", 4.0 if phase2_optics else 0.0)
	preview.terrain_material.set_shader_parameter("phase2_caustics", phase2_optics and optics_component != "no_caustics")
	var sand_hash: int = hash(preview.shadow_domain.sand)
	var rock_hash: int = hash(preview.shadow_domain.rock)
	var initial_water_m3: float = preview.shadow_domain.total_water_m3()
	if with_wave:
		var accepted: Dictionary = preview.request_wave({
			"domain_id": preview.shadow_domain.domain_id,
			"generation": preview.generation, "request_id": 1,
			"start_tick": 8, "profile_id": &"test_packet",
			"amplitude_m": 0.18, "duration_s": 6.0, "seed": 31})
		if not _check(accepted.ok, "dynamic shoreline wave rejected"):
			return
	while preview.completed_ticks < capture_tick and preview.last_error.is_empty() and elapsed_frames < 36000:
		await process_frame
		elapsed_frames += 1
	if not _check(preview.completed_ticks >= capture_tick, "capture tick not reached"):
		return
	preview.playing = false
	while preview.tick_pending and elapsed_frames < 3900:
		await process_frame
		elapsed_frames += 1
	if not _check(not preview.tick_pending and preview.last_error.is_empty(), "GPU did not settle"):
		return
	preview.set_visual_time(float(capture_tick) / 30.0 if with_wave else VISUAL_TIME_S)
	RenderingServer.call_on_render_thread(_request_fields)
	while field_bytes.size() < 3 and readback_error.is_empty() and elapsed_frames < 4200:
		await process_frame
		elapsed_frames += 1
	if not _check(readback_error.is_empty() and field_bytes.size() == 3, "state readback failed: " + readback_error):
		return
	var water_values: PackedFloat32Array = field_bytes["water"].to_float32_array()
	var qx_values: PackedFloat32Array = field_bytes["momentum_x"].to_float32_array()
	var qz_values: PackedFloat32Array = field_bytes["momentum_z"].to_float32_array()
	if not _check(water_values.size() == 65536 and qx_values.size() == 65536 and qz_values.size() == 65536, "state readback size is wrong"):
		return
	var distribution := _distribution(water_values, qx_values, qz_values)
	var depth_probes := _depth_probes(water_values)
	var feature_probes := _feature_probes(water_values)
	var artifacts: Array[String] = []
	var feature_pixels := {}
	var shoreline_mask_measurements := {}
	var visibility_measurements := {}
	var prefix := ("W03_midpoint_%d" % reconstruction_subdivision if midpoint_clip else ("W03_mask_%d" % reconstruction_subdivision if shoreline_debug else ("W03_radial_%d" % reconstruction_subdivision if radial_shore else "W03_%d" % reconstruction_subdivision))) if reconstruction else ("W02_mask" if shoreline_debug else (("W02_" + optics_component if optics_component != "all" else "W02") if phase2_optics else "W01"))
	if with_wave:
		prefix = ("W06_wave_mask_%d" if shoreline_debug else "W06_wave_%d") % capture_tick
	if not is_equal_approx(water_surface_bias_m, 0.006):
		prefix += "_bias%d" % roundi(water_surface_bias_m * 1000.0)
	for camera_id in Fixture.CAMERA_IDS:
		if not _check(preview.set_fixture_camera(camera_id), "camera failed: " + String(camera_id)):
			return
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var file := "%s_water_%s.png" % [prefix, camera_id]
		var frame := root.get_texture().get_image()
		feature_pixels[String(camera_id)] = _feature_pixels(frame, feature_probes)
		if shoreline_debug:
			shoreline_mask_measurements[String(camera_id)] = _measure_shoreline_mask(frame, water_values)
			visibility_measurements[String(camera_id)] = _probe_visibility(frame, water_values)
		var result := frame.save_png(OUT + file)
		if not _check(result == OK, "PNG write failed: " + file):
			return
		artifacts.append(file)
	var topdown_measurement := {}
	if shoreline_debug:
		var diagnostic_camera := Camera3D.new()
		diagnostic_camera.name = "ShorelineDiagnosticCamera"
		diagnostic_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		diagnostic_camera.size = 8.0
		diagnostic_camera.position = Vector3(1.5, 10.0, -2.5)
		preview.add_child(diagnostic_camera)
		diagnostic_camera.look_at(Vector3(1.5, 0.0, -2.5), Vector3(0.0, 0.0, -1.0))
		preview.overview_camera.current = false
		diagnostic_camera.current = true
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var topdown := root.get_texture().get_image()
		var topdown_file := prefix + "_water_topdown.png"
		if not _check(topdown.save_png(OUT + topdown_file) == OK, "topdown PNG write failed"):
			return
		artifacts.append(topdown_file)
		topdown_measurement = _measure_topdown_shoreline(topdown, water_values, diagnostic_camera)
	var manifest := {
		"fixture_id": String(Fixture.FIXTURE_ID),
		"seed": Fixture.SEED,
		"grid_size": preview.shadow_domain.grid_size,
		"render_subdivision": preview.render_subdivision,
		"cell_size_m": preview.shadow_domain.cell_size_m,
		"viewport_px": [root.size.x, root.size.y],
		"camera": Fixture.CAMERA_IDS.map(func(id: StringName) -> String: return String(id)),
		"tick": preview.completed_ticks,
		"generation": preview.generation,
		"revision": preview.solver.state_revision,
		"visual_time_s": float(capture_tick) / 30.0 if with_wave else VISUAL_TIME_S,
		"water_surface_bias_m": water_surface_bias_m,
		"profile_id": "water_v1_optics" if phase2_optics else "water_v1_baseline",
		"effect_flags": {"enable_erosion": preview.enable_erosion,
			"enable_material": preview.material_coupler != null,
			"enable_structures": preview.enable_structures,
			"phase2_optics": phase2_optics,
			"use_detail_normals": optics_component != "no_detail",
			"use_specular": optics_component != "no_specular",
			"use_caustics": optics_component != "no_caustics"},
		"reconstruction_mode": "radial" if radial_shore else ("bilinear" if reconstruction else "nearest"),
		"shoreline_debug": shoreline_debug,
		"midpoint_clip": midpoint_clip,
		"wave_requests": preview.wave_requests,
		"hardware": {"rendering_device": RenderingServer.get_video_adapter_name()},
		"frame_stats": {},
		"audit": {"initial_water_m3": initial_water_m3,
			"rock_hash": rock_hash, "sand_hash": sand_hash,
			"sand_hash_after": hash(preview.shadow_domain.sand),
			"rock_hash_after": hash(preview.shadow_domain.rock),
			"water_m3": preview.audit_water_m3,
			"min_depth_m": preview.audit_min_depth_m,
			"invalid_cells": preview.audit_invalid_cells,
			"negative_cells": preview.audit_negative_cells,
			"audit_revision": preview.audit_revision,
			"distribution": distribution,
			"state_hashes": {"water": hash(water_values),
				"momentum_x": hash(qx_values), "momentum_z": hash(qz_values)},
			"depth_probes": depth_probes,
			"bed_feature_probes": feature_probes,
			"feature_pixels": feature_pixels,
			"shoreline_mask_measurements": shoreline_mask_measurements,
			"visibility_measurements": visibility_measurements,
			"topdown_shoreline": topdown_measurement},
		"artifacts": artifacts,
	}
	var output := FileAccess.open(OUT + prefix + "_water_manifest.json", FileAccess.WRITE)
	if not _check(output != null, "manifest open failed"):
		return
	output.store_string(JSON.stringify(manifest, "\t"))
	output.close()
	if not _check(sand_hash == hash(preview.shadow_domain.sand) and rock_hash == hash(preview.shadow_domain.rock), "bed changed"):
		return
	print("PASS: %s water fixture tick=%d revision=%d sand_hash=%d captures=%s" % [prefix, preview.completed_ticks, preview.solver.state_revision, sand_hash, ",".join(artifacts)])
	quit(0)


func _request_fields() -> void:
	for field in ["water", "momentum_x", "momentum_z"]:
		var error: Error = preview.solver.request_data(field, _on_field.bind(field))
		if error != OK:
			call_deferred("_receive_error", "%s: %d" % [field, error])


func _on_field(data: PackedByteArray, field: String) -> void:
	call_deferred("_receive_field", field, data)


func _receive_field(field: String, data: PackedByteArray) -> void:
	field_bytes[field] = data


func _receive_error(message: String) -> void:
	readback_error = message


func _distribution(water: PackedFloat32Array, qx: PackedFloat32Array,
		qz: PackedFloat32Array) -> Dictionary:
	var depth_bins := [0, 0, 0, 0, 0]
	var speed_bins := [0, 0, 0, 0]
	var max_depth := 0.0
	var max_speed := 0.0
	for i in water.size():
		var depth: float = water[i]
		if depth <= 0.001:
			depth_bins[0] += 1
			continue
		var speed := Vector2(qx[i], qz[i]).length() / depth
		max_depth = maxf(max_depth, depth)
		max_speed = maxf(max_speed, speed)
		if depth < 0.02:
			depth_bins[1] += 1
		elif depth < 0.08:
			depth_bins[2] += 1
		elif depth < 0.25:
			depth_bins[3] += 1
		else:
			depth_bins[4] += 1
		if speed < 0.1:
			speed_bins[0] += 1
		elif speed < 0.5:
			speed_bins[1] += 1
		elif speed < 1.0:
			speed_bins[2] += 1
		else:
			speed_bins[3] += 1
	return {"depth_bins_m": ["dry_or_under_0.001", "0.001_to_0.02",
		"0.02_to_0.08", "0.08_to_0.25", "at_least_0.25"],
		"depth_counts": depth_bins, "speed_bins_m_s": ["under_0.1",
		"0.1_to_0.5", "0.5_to_1.0", "at_least_1.0"],
		"speed_counts": speed_bins, "max_depth_m": max_depth,
		"max_speed_m_s": max_speed}


func _depth_probes(water: PackedFloat32Array) -> Array[Dictionary]:
	var probes: Array[Dictionary] = []
	for target in [0.02, 0.08, 0.25]:
		var best_index := -1
		var best_error := INF
		for i in water.size():
			var x := i % 256
			var z := i / 256
			# Interior probes avoid the prescribed ocean edge and camera clipping.
			if x < 16 or x >= 240 or z < 16 or z >= 240:
				continue
			var error := absf(water[i] - target)
			if error < best_error:
				best_error = error
				best_index = i
		var px := best_index % 256
		var pz := best_index / 256
		probes.append({"target_depth_m": target, "actual_depth_m": water[best_index],
			"cell": [px, pz],
			"world_xz_m": [(float(px) + 0.5) * 0.125 - 16.0,
				(float(pz) + 0.5) * 0.125 - 16.0],
			"bed_m": preview.shadow_domain.bed_at(best_index)})
	return probes


func _feature_probes(water: PackedFloat32Array) -> Array[Dictionary]:
	var probes: Array[Dictionary] = []
	for feature in [{"name": "sand_ridge", "world_z_m": -1.5},
			{"name": "sand_channel", "world_z_m": 1.5}]:
		var x: int = roundi((-5.0 + 16.0) / 0.125 - 0.5)
		var z: int = roundi((float(feature.world_z_m) + 16.0) / 0.125 - 0.5)
		var i: int = preview.shadow_domain.index(x, z)
		probes.append({"name": feature.name, "cell": [x, z],
			"bed_m": preview.shadow_domain.bed_at(i), "water_depth_m": water[i],
			"water_surface_m": preview.shadow_domain.bed_at(i) + water[i]})
	return probes


func _feature_pixels(frame: Image, probes: Array[Dictionary]) -> Dictionary:
	var result := {}
	for probe in probes:
		var x: int = probe.cell[0]
		var z: int = probe.cell[1]
		var world := Vector3((float(x) + 0.5) * 0.125 - 16.0,
			float(probe.water_surface_m) + 0.006,
			(float(z) + 0.5) * 0.125 - 16.0)
		var screen: Vector2 = preview.overview_camera.unproject_position(world)
		var pixel := Vector2i(roundi(screen.x), roundi(screen.y))
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= frame.get_width() or pixel.y >= frame.get_height():
			result[String(probe.name)] = {"visible": false}
			continue
		var color := frame.get_pixelv(pixel)
		result[String(probe.name)] = {"visible": true, "pixel": [pixel.x, pixel.y],
			"rgb": [color.r, color.g, color.b]}
	return result


func _is_water_mask(frame: Image, pixel: Vector2i) -> bool:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= frame.get_width() or pixel.y >= frame.get_height():
		return false
	var color := frame.get_pixelv(pixel)
	return color.r > 0.96 and color.g > 0.96 and color.b > 0.96


func _measure_shoreline_mask(frame: Image, water: PackedFloat32Array) -> Dictionary:
	var normalized_errors: Array[float] = []
	var dry_centres := 0
	var dry_centres_white := 0
	var camera: Camera3D = preview.overview_camera
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	for z in range(74, 143):
		for x in range(108, 176):
			var i: int = preview.shadow_domain.index(x, z)
			for offset in offsets:
				var nx: int = x + offset.x
				var nz: int = z + offset.y
				var j: int = preview.shadow_domain.index(nx, nz)
				var wet_i: bool = water[i] > 0.001
				var wet_j: bool = water[j] > 0.001
				if wet_i == wet_j:
					continue
				var wet_index: int = i if wet_i else j
				var dry_index: int = j if wet_i else i
				var wet_x: int = x if wet_i else nx
				var wet_z: int = z if wet_i else nz
				var dry_x: int = nx if wet_i else x
				var dry_z: int = nz if wet_i else z
				var wet_world := Vector3((float(wet_x) + 0.5) * 0.125 - 16.0,
					preview.shadow_domain.bed_at(wet_index) + water[wet_index] + 0.006,
					(float(wet_z) + 0.5) * 0.125 - 16.0)
				var dry_world := Vector3((float(dry_x) + 0.5) * 0.125 - 16.0,
					preview.shadow_domain.bed_at(dry_index) + 0.006,
					(float(dry_z) + 0.5) * 0.125 - 16.0)
				if camera.is_position_behind(wet_world) or camera.is_position_behind(dry_world):
					continue
				var wet_screen: Vector2 = camera.unproject_position(wet_world)
				var dry_screen: Vector2 = camera.unproject_position(dry_world)
				var scale_px := wet_screen.distance_to(dry_screen)
				if scale_px < 2.0:
					continue
				var predicted := (wet_screen + dry_screen) * 0.5
				if predicted.x < 12.0 or predicted.y < 12.0 or predicted.x >= frame.get_width() - 12 or predicted.y >= frame.get_height() - 12:
					continue
				var dry_pixel := Vector2i(roundi(dry_screen.x), roundi(dry_screen.y))
				if dry_pixel.x >= 0 and dry_pixel.y >= 0 and dry_pixel.x < frame.get_width() and dry_pixel.y < frame.get_height():
					dry_centres += 1
					if _is_water_mask(frame, dry_pixel):
						dry_centres_white += 1
				var centre := Vector2i(roundi(predicted.x), roundi(predicted.y))
				var closest := INF
				for py in range(centre.y - 10, centre.y + 11):
					for px in range(centre.x - 10, centre.x + 11):
						var pixel := Vector2i(px, py)
						if not _is_water_mask(frame, pixel):
							continue
						if _is_water_mask(frame, pixel + Vector2i(1, 0)) and \
								_is_water_mask(frame, pixel + Vector2i(-1, 0)) and \
								_is_water_mask(frame, pixel + Vector2i(0, 1)) and \
								_is_water_mask(frame, pixel + Vector2i(0, -1)):
							continue
						closest = minf(closest, Vector2(px, py).distance_to(predicted))
				if closest < INF:
					normalized_errors.append(closest / scale_px)
	normalized_errors.sort()
	var count := normalized_errors.size()
	return {"boundary_pairs_measured": count,
		"median_offset_cells": normalized_errors[count / 2] if count > 0 else -1.0,
		"p95_offset_cells": normalized_errors[mini(count - 1, floori(float(count) * 0.95))] if count > 0 else -1.0,
		"max_offset_cells": normalized_errors[count - 1] if count > 0 else -1.0,
		"dry_centres_checked": dry_centres,
		"dry_centres_white": dry_centres_white,
		"dry_centre_white_fraction": float(dry_centres_white) / float(maxi(dry_centres, 1))}


func _probe_visibility(frame: Image, water: PackedFloat32Array) -> Dictionary:
	var camera: Camera3D = preview.overview_camera
	var dry_checked := 0
	var dry_white := 0
	var dry_white_samples := []
	var wet_checked := 0
	var wet_missing := 0
	var cell_size := 0.125
	for py in range(104, frame.get_height() - 24, 8):
		for px in range(24, frame.get_width() - 24, 8):
			var pixel := Vector2i(px, py)
			var origin: Vector3 = camera.project_ray_origin(Vector2(px, py))
			var direction: Vector3 = camera.project_ray_normal(Vector2(px, py))
			if direction.y >= -0.001:
				continue
			for step in 720:
				var distance_m := float(step) * 0.0625
				var world := origin + direction * distance_m
				var gx := floori((world.x + 16.0) / cell_size)
				var gz := floori((world.z + 16.0) / cell_size)
				if gx < 1 or gz < 1 or gx >= 255 or gz >= 255:
					continue
				var index: int = preview.shadow_domain.index(gx, gz)
				var top: float = preview.shadow_domain.bed_at(index) + water[index] + water_surface_bias_m
				if world.y > top:
					continue
				var interior_dry := true
				var interior_wet := true
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var neighbor: int = preview.shadow_domain.index(gx + dx, gz + dz)
						interior_dry = interior_dry and water[neighbor] <= 0.001
						interior_wet = interior_wet and water[neighbor] > 0.001
				if interior_dry:
					dry_checked += 1
					if _is_water_mask(frame, pixel):
						dry_white += 1
						dry_white_samples.append({"pixel": [px, py],
							"cell": [gx, gz], "world_xz": [world.x, world.z],
							"distance_m": distance_m,
							"fine_first_hit": _fine_first_hit(origin, direction, water,
								distance_m + 0.125),
						"display_first_hit": _display_first_hit(origin, direction, water,
								distance_m + 0.125)})
				elif interior_wet:
					wet_checked += 1
					if not _is_water_mask(frame, pixel):
						wet_missing += 1
				break
	return {"sample_stride_px": 8, "ray_step_m": 0.0625,
		"interior_dry_checked": dry_checked, "interior_dry_white": dry_white,
		"dry_white_samples": dry_white_samples,
		"interior_dry_white_fraction": float(dry_white) / float(maxi(dry_checked, 1)),
		"interior_wet_checked": wet_checked, "interior_wet_missing": wet_missing,
		"interior_wet_missing_fraction": float(wet_missing) / float(maxi(wet_checked, 1))}


func _fine_first_hit(origin: Vector3, direction: Vector3,
		water: PackedFloat32Array, maximum_m: float) -> Dictionary:
	for step in ceili(maximum_m / 0.0078125):
		var distance_m := float(step) * 0.0078125
		var world := origin + direction * distance_m
		var gx := floori((world.x + 16.0) / 0.125)
		var gz := floori((world.z + 16.0) / 0.125)
		if gx < 1 or gz < 1 or gx >= 255 or gz >= 255:
			continue
		var index: int = preview.shadow_domain.index(gx, gz)
		var top: float = preview.shadow_domain.bed_at(index) + water[index] + water_surface_bias_m
		if world.y > top:
			continue
		return {"cell": [gx, gz], "distance_m": distance_m,
			"water_depth_m": water[index]}
	return {}


func _display_first_hit(origin: Vector3, direction: Vector3,
		water: PackedFloat32Array, maximum_m: float) -> Dictionary:
	for step in ceili(maximum_m / 0.0078125):
		var distance_m := float(step) * 0.0078125
		var world := origin + direction * distance_m
		if world.x < -16.0 or world.x >= 16.0 or world.z < -16.0 or world.z >= 16.0:
			continue
		var display := _display_surface_at(world.x, world.z, water)
		if world.y > display.x + display.y + water_surface_bias_m:
			continue
		return {"distance_m": distance_m,
			"display_depth_m": display.y,
			"world_xz": [world.x, world.z]}
	return {}


func _display_surface_at(world_x: float, world_z: float,
		water: PackedFloat32Array) -> Vector2:
	var cell_x := (world_x + 16.0) / 0.125 - 0.5
	var cell_z := (world_z + 16.0) / 0.125 - 0.5
	var low_x := floori(cell_x)
	var low_z := floori(cell_z)
	var tx := cell_x - float(low_x)
	var tz := cell_z - float(low_z)
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var total_bed := 0.0
	var wet_eta := 0.0
	var wet_fraction := 0.0
	var local_max := 0.0
	for dz in 2:
		for dx in 2:
			var gx := clampi(low_x + dx, 0, 255)
			var gz := clampi(low_z + dz, 0, 255)
			var index: int = preview.shadow_domain.index(gx, gz)
			var weight := (tx if dx == 1 else 1.0 - tx) * \
				(tz if dz == 1 else 1.0 - tz)
			var bed: float = preview.shadow_domain.bed_at(index)
			var depth: float = maxf(water[index], 0.0)
			var wet := 1.0 if depth >= 0.001 else 0.0
			total_bed += weight * bed
			wet_eta += weight * (bed + depth) * wet
			wet_fraction += weight * wet
			local_max = maxf(local_max, depth)
	var display_depth := 0.0
	if wet_fraction > 0.0:
		display_depth = minf(maxf(wet_eta / wet_fraction - total_bed, 0.0) * \
			wet_fraction, local_max)
	return Vector2(total_bed, display_depth)


func _measure_topdown_shoreline(frame: Image, water: PackedFloat32Array,
		camera: Camera3D) -> Dictionary:
	var dry_overreach: Array[float] = []
	var wet_underreach: Array[float] = []
	var dry_pixels := 0
	var wet_pixels := 0
	for py in range(96, frame.get_height() - 96, 2):
		for px in range(280, frame.get_width() - 280, 2):
			var pixel := Vector2i(px, py)
			var world: Vector3 = camera.project_ray_origin(Vector2(px, py))
			var gx := floori((world.x + 16.0) / 0.125)
			var gz := floori((world.z + 16.0) / 0.125)
			if gx < 3 or gz < 3 or gx >= 253 or gz >= 253:
				continue
			var cell: int = preview.shadow_domain.index(gx, gz)
			var actual_wet := water[cell] > 0.001
			var display_wet := _is_water_mask(frame, pixel)
			if actual_wet:
				wet_pixels += 1
			else:
				dry_pixels += 1
			if actual_wet == display_wet:
				continue
			var nearest_opposite := INF
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var neighbor: int = preview.shadow_domain.index(gx + dx, gz + dz)
					if (water[neighbor] > 0.001) == actual_wet:
						continue
					var cx := (float(gx + dx) + 0.5) * 0.125 - 16.0
					var cz := (float(gz + dz) + 0.5) * 0.125 - 16.0
					var border_dx := maxf(absf(world.x - cx) - 0.0625, 0.0)
					var border_dz := maxf(absf(world.z - cz) - 0.0625, 0.0)
					nearest_opposite = minf(nearest_opposite,
						Vector2(border_dx, border_dz).length() / 0.125)
			if actual_wet:
				wet_underreach.append(nearest_opposite)
			else:
				dry_overreach.append(nearest_opposite)
	dry_overreach.sort()
	wet_underreach.sort()
	return {"sample_stride_px": 2, "dry_pixels": dry_pixels,
		"wet_pixels": wet_pixels,
		"dry_overreach_pixels": dry_overreach.size(),
		"wet_underreach_pixels": wet_underreach.size(),
		"max_dry_overreach_cells": dry_overreach[-1] if not dry_overreach.is_empty() else 0.0,
		"p95_dry_overreach_cells": dry_overreach[mini(dry_overreach.size() - 1,
			floori(float(dry_overreach.size()) * 0.95))] if not dry_overreach.is_empty() else 0.0,
		"max_wet_underreach_cells": wet_underreach[-1] if not wet_underreach.is_empty() else 0.0,
		"p95_wet_underreach_cells": wet_underreach[mini(wet_underreach.size() - 1,
			floori(float(wet_underreach.size()) * 0.95))] if not wet_underreach.is_empty() else 0.0}


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	print("FAIL: W01 " + message)
	quit(1)
	return false
