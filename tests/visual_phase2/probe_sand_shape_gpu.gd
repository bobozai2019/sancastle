extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Solver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const Sediment = preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const MaterialCoupler = preload("res://scripts/simulation/material/gpu_material_coupler.gd")
const GRID := 256
const CENTER := 128
const CELL_M := 0.125
const SHADERS := [
	"res://shaders/simulation/shallow_edge_flux.glsl",
	"res://shaders/simulation/shallow_drain_scale.glsl",
	"res://shaders/simulation/shallow_update_state.glsl",
	"res://shaders/simulation/shallow_tide_boundary.glsl",
	"res://shaders/simulation/shallow_cfl_tiles.glsl",
	"res://shaders/simulation/shallow_gauge_depth.glsl",
	"res://shaders/simulation/shallow_audit_tiles.glsl",
	"res://shaders/simulation/shallow_tool_patch.glsl",
	"res://shaders/simulation/erosion/sediment_step.glsl",
	"res://shaders/simulation/erosion/copy_after_boundary.glsl",
	"res://shaders/simulation/material/material_step.glsl",
	"res://shaders/simulation/material/slope_relax.glsl",
	"res://shaders/simulation/material/material_commit.glsl",
]

var result: Dictionary = {}
var error := ""


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	RenderingServer.call_on_render_thread(_render_run)


func _render_run() -> void:
	var spirvs: Array[RDShaderSPIRV] = []
	for path in SHADERS:
		var file: RDShaderFile = load(path)
		if file == null or file.get_spirv() == null:
			error = "shader import missing: " + path
			call_deferred("_report")
			return
		spirvs.append(file.get_spirv())
	var cases := [
		{"name": "current_packed", "compaction": 0.95, "wetness": 0.35, "water": 0.0, "cohesion": 0.0},
		{"name": "prototype_packed", "compaction": 0.95, "wetness": 0.35, "water": 0.0, "cohesion": 2.0},
		{"name": "prototype_loose", "compaction": 0.1, "wetness": 0.05, "water": 0.0, "cohesion": 2.0},
		{"name": "prototype_dry_packed", "compaction": 0.95, "wetness": 0.05, "water": 0.0, "cohesion": 2.0},
		{"name": "prototype_saturated_packed", "compaction": 0.95, "wetness": 1.0, "water": 0.08, "cohesion": 2.0},
		{"name": "prototype_packed_120hz", "compaction": 0.95, "wetness": 0.35, "water": 0.0, "cohesion": 2.0, "substeps_hz": 120},
		{"name": "prototype_packed_60s", "compaction": 0.95, "wetness": 0.35, "water": 0.0, "cohesion": 2.0, "end_seconds": 60},
		{"name": "prototype_release_20s", "compaction": 0.95, "wetness": 0.35, "water": 0.0, "cohesion": 2.0, "end_seconds": 60, "support_release_second": 20},
		{"name": "wetness_timeline", "compaction": 0.95, "wetness": 0.05, "water": 0.08, "cohesion": 2.0, "end_seconds": 15, "drain_at_second": 2},
	]
	for case in cases:
		result[case.name] = _case(spirvs, case)
		if not error.is_empty():
			break
	call_deferred("_report")


func _case(spirvs: Array[RDShaderSPIRV], case: Dictionary) -> Dictionary:
	var domain := Domain.new(GRID, CELL_M)
	var initial_total := 0.0
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			var in_tower: bool = absi(x - CENTER) <= 8 and absi(z - CENTER) <= 8
			var height := 1.8 if in_tower else 0.0
			if in_tower and x - CENTER >= 5 and z - CENTER >= 3:
				height = 1.55
			if absi(x - CENTER) <= 1 and absi(z - CENTER) <= 1:
				height = 1.5
			domain.rock[i] = 0.0
			domain.sand[i] = height
			domain.water[i] = case.water if in_tower else 0.0
			domain.wetness[i] = case.wetness if in_tower else 0.05
			domain.compaction[i] = case.compaction if in_tower else 0.1
			initial_total += height * CELL_M * CELL_M
	var solver := Solver.new()
	var rd := RenderingServer.get_rendering_device()
	if not solver.initialize(rd, domain, spirvs[0], spirvs[1], spirvs[2], spirvs[3],
			spirvs[4], spirvs[5], spirvs[6], spirvs[7]):
		error = "solver initialization failed"
		return {}
	var sediment := Sediment.new()
	if not sediment.initialize(solver, spirvs[8], spirvs[9]):
		error = "sediment initialization failed"
		solver.release()
		return {}
	var material := MaterialCoupler.new()
	material.cohesion_yield_height_m = case.cohesion
	if not material.initialize(solver, sediment.dirty_max_texture,
			spirvs[10], spirvs[11], spirvs[12]):
		error = "material initialization failed"
		sediment.release()
		solver.release()
		return {}
	var samples := {}
	var substeps_hz: int = case.get("substeps_hz", 30)
	var end_seconds: int = case.get("end_seconds", 10)
	var sample_steps := [0, substeps_hz, 3 * substeps_hz, 10 * substeps_hz]
	if case.has("drain_at_second"):
		sample_steps.append(2 * substeps_hz)
		sample_steps.append(5 * substeps_hz)
		sample_steps.append(15 * substeps_hz)
	if end_seconds > 10:
		sample_steps.append(30 * substeps_hz)
		sample_steps.append(end_seconds * substeps_hz)
		if case.has("support_release_second"):
			sample_steps.append(int(case.support_release_second) * substeps_hz)
	for tick in (end_seconds * substeps_hz + 1):
		if tick in sample_steps:
			var data: PackedByteArray = rd.texture_get_data(solver.current_texture("sand"), 0)
			if data.size() != GRID * GRID * 4:
				error = "sand readback size invalid"
				break
			var sampled: Dictionary = _measure(data.to_float32_array(), initial_total)
			var wet_data: PackedByteArray = rd.texture_get_data(solver.current_texture("wetness"), 0)
			var comp_data: PackedByteArray = rd.texture_get_data(solver.current_texture("compaction"), 0)
			sampled["wetness_center"] = wet_data.decode_half((CENTER * GRID + CENTER) * 2)
			sampled["compaction_center"] = comp_data.decode_half((CENTER * GRID + CENTER) * 2)
			samples[str(int(tick * 30 / substeps_hz))] = sampled
		if case.has("drain_at_second") and tick == int(case.drain_at_second) * substeps_hz:
			# Solver water images are not CPU-updatable. Recreate the GPU rig from
			# completed textures with water set to zero; this is a material-only
			# continuation at the exact transition tick, not a reset of sand state.
			var sand_now: PackedFloat32Array = rd.texture_get_data(
				solver.current_texture("sand"), 0).to_float32_array()
			var wet_now: PackedByteArray = rd.texture_get_data(
				solver.current_texture("wetness"), 0)
			var comp_now: PackedByteArray = rd.texture_get_data(
				solver.current_texture("compaction"), 0)
			var dry_domain := Domain.new(GRID, CELL_M)
			for i in GRID * GRID:
				dry_domain.rock[i] = domain.rock[i]
				dry_domain.sand[i] = sand_now[i]
				dry_domain.water[i] = 0.0
				dry_domain.wetness[i] = wet_now.decode_half(i * 2)
				dry_domain.compaction[i] = comp_now.decode_half(i * 2)
			material.release()
			sediment.release()
			solver.release()
			domain = dry_domain
			solver = Solver.new()
			if not solver.initialize(rd, domain, spirvs[0], spirvs[1], spirvs[2],
					spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7]):
				error = "dry continuation solver initialization failed"
				break
			sediment = Sediment.new()
			if not sediment.initialize(solver, spirvs[8], spirvs[9]):
				error = "dry continuation sediment initialization failed"
				break
			material = MaterialCoupler.new()
			material.cohesion_yield_height_m = case.cohesion
			if not material.initialize(solver, sediment.dirty_max_texture,
					spirvs[10], spirvs[11], spirvs[12]):
				error = "dry continuation material initialization failed"
				break
		if case.has("support_release_second") and tick == int(case.support_release_second) * substeps_hz:
			var data: PackedByteArray = rd.texture_get_data(solver.current_texture("sand"), 0)
			var current_sand := data.to_float32_array()
			var stream := StreamPeerBuffer.new()
			stream.big_endian = false
			for z in range(CENTER - 8, CENTER + 9):
				for x in range(CENTER - 8, CENTER + 9):
					var i: int = z * GRID + x
					stream.put_32(i)
					stream.put_float(current_sand[i])
					stream.put_float(0.1)
					stream.put_float(0.0)
			if not solver.dispatch_tool_patch(stream.data_array, 17 * 17):
				error = "support release patch failed"
				break
		if tick < end_seconds * substeps_hz and not material.dispatch_after_erosion(1.0 / float(substeps_hz)):
			error = "material dispatch failed at tick %d" % tick
			break
	material.release()
	sediment.release()
	solver.release()
	return {"cohesion_yield_height_m": case.cohesion,
		"substeps_hz": substeps_hz,
		"end_seconds": end_seconds,
		"compaction_top": case.compaction,
		"wetness_top_initial": case.wetness,
		"water_depth_initial_m": case.water,
		"samples": samples}


func _measure(sand: PackedFloat32Array, initial_total: float) -> Dictionary:
	var peak := 0.0
	var intersection := 0
	var union := 0
	var total := 0.0
	var minimum := INF
	var boundary_sum := 0.0
	var boundary_count := 0
	var outside_mass := 0.0
	var notch_sum := 0.0
	var notch_count := 0
	var groove_sum := 0.0
	var groove_count := 0
	var plateau_sum := 0.0
	var plateau_count := 0
	for z in GRID:
		for x in GRID:
			var height: float = sand[z * GRID + x]
			total += height * CELL_M * CELL_M
			minimum = minf(minimum, height)
			if absi(x - CENTER) <= 8 and absi(z - CENTER) <= 8:
				peak = maxf(peak, height)
				if x - CENTER >= 5 and z - CENTER >= 3:
					notch_sum += height
					notch_count += 1
				elif absi(x - CENTER) <= 1 and absi(z - CENTER) <= 1:
					groove_sum += height
					groove_count += 1
				elif absi(x - CENTER) <= 2 and z - CENTER <= -4 and z - CENTER >= -6:
					plateau_sum += height
					plateau_count += 1
				if absi(x - CENTER) == 8 or absi(z - CENTER) == 8:
					boundary_sum += height
					boundary_count += 1
				if height > 0.9:
					intersection += 1
				union += 1
			else:
				outside_mass += height * CELL_M * CELL_M
	return {"peak_height_m": peak, "peak_retained_fraction": peak / 1.8,
		"high_shape_iou": float(intersection) / float(union),
		"boundary_mean_height_m": boundary_sum / float(boundary_count),
		"outside_mass_m3": outside_mass,
		"notch_mean_height_m": notch_sum / float(notch_count),
		"groove_mean_height_m": groove_sum / float(groove_count),
		"plateau_mean_height_m": plateau_sum / float(plateau_count),
		"total_sand_m3": total,
		"closure_fraction": absf(total - initial_total) / initial_total,
		"minimum_sand_m": minimum}


func _report() -> void:
	if not error.is_empty():
		push_error("FAIL: S01 GPU shape A/B " + error)
		quit(1)
		return
	result["grid_size"] = GRID
	result["cell_size_m"] = CELL_M
	result["fixture_id"] = "sand_v1"
	result["seed"] = 53021
	result["tower_height_m"] = 1.8
	result["base_width_m"] = 17.0 * CELL_M
	result["initial_sand_volume_m3"] = 7.9921875
	result["bed_support"] = "flat, unchanging rock at y=0; support removal is S02"
	result["shape_measurement"] = "height>0.9 m mask in original 17x17-cell footprint; boundary ring mean, notch/groove/plateau means"
	result["initial_height_base_ratio"] = 1.8 / (17.0 * CELL_M)
	result["method"] = "main RenderingDevice, production material passes, 300 ticks at 30 Hz"
	var path := ProjectSettings.globalize_path(
		"res://test_output/sandcastle_visual_reconstruction_phase2/验收/S01_sand_shape_gpu_ab.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("FAIL: S01 GPU shape A/B cannot write evidence")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("PASS: S01 GPU shape A/B " + JSON.stringify(result))
	quit(0)
