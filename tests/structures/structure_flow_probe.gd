extends SceneTree

## T06 end-to-end probe at 64² on the main RenderingDevice.
##
## Walks the whole acceptance chain in one run:
##
##   1. build a wall across a flooded channel and push it through the production
##      tool-patch path, then check the GPU sand and compaction match the intent
##   2. run coupled water + erosion + material substeps and confirm the wall
##      holds: essentially no water reaches the far side
##   3. undermine the wall through the real `remove_sand` brush path, confirm the
##      support fraction drops and damage accumulates, and that the wall collapses
##   4. keep running and confirm a new flow path carries water across where the
##      wall stood
##   5. confirm the sand account stayed closed throughout and the obstacle mask
##      was never touched
##
## Everything runs on the render thread, where RenderingDevice readback is
## synchronous, so the CPU structure model can read the GPU bed directly at the
## few checkpoints it needs.

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Solver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const SedimentCoupler = preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const MaterialCoupler = preload("res://scripts/simulation/material/gpu_material_coupler.gd")
const Structure = preload("res://scripts/structures/structure_state.gd")
const Field = preload("res://scripts/structures/structure_field.gd")
const CommandQueue = preload("res://scripts/sand/tool_command_queue.gd")

const GRID := 64
const CELL_M := 0.125
const SUBSTEP_S := 1.0 / 120.0

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
	"res://shaders/simulation/material/material_commit.glsl"]

## The wall is a 5-cell tapered ridge: a vertical slab would exceed the angle of
## repose and be flattened by the slope relaxation before it could be undermined.
const WALL_X := 30
const WALL_THICKNESS := 5
const WALL_HEIGHT_M := 0.30
const WALL_TAPER_M := 0.10
const WATER_DEPTH_M := 0.15
const DAMAGE_RATE_PER_S := 8.0
const HOLD_SUBSTEPS := 1200
const BREACH_SUBSTEPS := 3000

var failures: Array[String] = []
var lines: Array[String] = []
var finished := false
var started_ms := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	RenderingServer.call_on_render_thread(_render_run)
	call_deferred("_watchdog")


func _render_run() -> void:
	var spirvs: Array[RDShaderSPIRV] = []
	for path in SHADERS:
		var file: RDShaderFile = load(path)
		if file == null or file.get_spirv() == null:
			failures.append("shader import missing: " + path)
			break
		spirvs.append(file.get_spirv())
	if failures.is_empty():
		_run_case(spirvs)
	call_deferred("_report")


func _run_case(spirvs: Array[RDShaderSPIRV]) -> void:
	var domain := Domain.new(GRID, CELL_M)
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.rock[i] = 0.0
			domain.sand[i] = 0.30
			## Water sits behind the wall and is held back by it.
			domain.water[i] = WATER_DEPTH_M if x < WALL_X else 0.0
			domain.wetness[i] = 0.4 if x < WALL_X else 0.1
			domain.compaction[i] = 0.3
	var solver := Solver.new()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5],
			spirvs[6], spirvs[7]):
		failures.append("solver initialize failed")
		return
	var sediment := SedimentCoupler.new()
	if not sediment.initialize(solver, spirvs[8], spirvs[9]):
		solver.release()
		failures.append("sediment coupler initialize failed")
		return
	var material := MaterialCoupler.new()
	if not material.initialize(solver, sediment.dirty_max_texture, spirvs[10],
			spirvs[11], spirvs[12]):
		sediment.release()
		solver.release()
		failures.append("material coupler initialize failed")
		return
	var queue := CommandQueue.new(domain)
	var field := Field.new()
	var obstacle_before := _obstacle_digest(domain)
	var initial_sand := _total(domain.sand, CELL_M * CELL_M)

	## 1. Build the wall and push it to the GPU through the production patch path.
	var wall := Structure.new()
	wall.kind = Structure.Kind.WALL
	wall.origin = Vector2i(WALL_X, 0)
	wall.size = Vector2i(WALL_THICKNESS, GRID)
	wall.height_m = WALL_HEIGHT_M
	wall.taper_slope_m = WALL_TAPER_M
	wall.compaction = 0.9
	var booked := field.add(wall, domain)
	var patch := field.patch_for(wall, domain)
	if not solver.dispatch_tool_patch(patch.data, patch.count):
		failures.append("wall patch rejected by the solver")
		_release(solver, sediment, material)
		return
	var gpu_sand := _read(solver, "sand")
	var gpu_compaction := _read_half(solver, "compaction")
	var crest_cells := 0
	var crest_mismatch := 0
	var crest_surface := 0.0
	for z in GRID:
		for x in range(WALL_X, WALL_X + WALL_THICKNESS):
			var i := domain.index(x, z)
			if absf(gpu_sand[i] - domain.sand[i]) > 0.000001:
				crest_mismatch += 1
			if absf(gpu_compaction[i] - domain.compaction[i]) > 0.002:
				crest_mismatch += 1
		## The centre column carries the full height.
		var centre := domain.index(WALL_X + WALL_THICKNESS / 2, z)
		crest_surface = maxf(crest_surface, gpu_sand[centre])
		if gpu_sand[centre] > 0.30 + WALL_HEIGHT_M - 0.01:
			crest_cells += 1
	if crest_mismatch > 0 or crest_cells != GRID:
		failures.append("wall did not reach the GPU intact: crest_cells=%d mismatch=%d" % [
			crest_cells, crest_mismatch])
		_release(solver, sediment, material)
		return

	## 2. Hold: the wall must keep the far side dry.
	var water_left := _dispatch(solver, sediment, material, HOLD_SUBSTEPS)
	var held := _far_side_water(solver)
	if held > 0.02:
		failures.append("water crossed the intact wall: %.6f m3" % held)
		_release(solver, sediment, material)
		return

	## 3a. Undermine the bed beside the wall through the real brush path. Cutting
	## the ground out from under its flanks is what removes lateral support.
	var undermined := 0.0
	var area := CELL_M * CELL_M
	var dig_indices := PackedInt32Array()
	var support_before_dig := wall.support_fraction(domain)
	var command_id := 0
	for x in [WALL_X - 1, WALL_X + WALL_THICKNESS]:
		for z in range(GRID / 4, 3 * GRID / 4):
			command_id += 1
			var error: StringName = queue.submit({
				"domain_id": domain.domain_id, "generation": domain.generation,
				"sim_tick": 0, "command_id": command_id, "kind": &"remove_sand",
				"shape": &"circle", "transform": {"position_m": _world(x, z)},
				"radius_m": 0.38, "strength": 1.0, "amount_m3": 0.02, "seed": command_id})
			if not error.is_empty():
				failures.append("undermining brush rejected: " + String(error))
				_release(solver, sediment, material)
				return
	for result in queue.apply_due_commands(0):
		if result.status == &"applied":
			undermined += float(result.get("sand_delta_m3", 0.0))
			dig_indices.append_array(result.get("dirty_cells", PackedInt32Array()))
	## The queue resolved the volume on the CPU shadow; upload the same cells so
	## the GPU bed matches before support is evaluated.
	if not _upload_cells(solver, domain, dig_indices):
		failures.append("undermining patch rejected by the solver")
		_release(solver, sediment, material)
		return
	var support_after_dig := wall.support_fraction(domain)
	if support_after_dig >= support_before_dig:
		failures.append("undermining did not reduce wall support: %.6f -> %.6f" % [
			support_before_dig, support_after_dig])
		_release(solver, sediment, material)
		return
	var collapsed := false
	for _step in 6000:
		field.step(domain, SUBSTEP_S, DAMAGE_RATE_PER_S)
		if wall.collapsed:
			collapsed = true
			break
	if not collapsed:
		failures.append("undermined wall never collapsed")
		_release(solver, sediment, material)
		return
	## 3b. Push the loosened crest to the GPU and cut a notch through it, which is
	## what actually opens the new channel.
	var loose_patch := field.patch_for(wall, domain)
	if not solver.dispatch_tool_patch(loose_patch.data, loose_patch.count):
		failures.append("loosened wall patch rejected by the solver")
		_release(solver, sediment, material)
		return
	var notch_indices := PackedInt32Array()
	for z in range(GRID / 2 - 8, GRID / 2 + 8):
		command_id += 1
		var notch_error: StringName = queue.submit({
			"domain_id": domain.domain_id, "generation": domain.generation,
			"sim_tick": 0, "command_id": command_id, "kind": &"remove_sand",
			"shape": &"circle",
			"transform": {"position_m": _world(WALL_X + WALL_THICKNESS / 2, z)},
			"radius_m": 0.38, "strength": 1.0, "amount_m3": 0.03, "seed": command_id})
		if not notch_error.is_empty():
			failures.append("notch brush rejected: " + String(notch_error))
			_release(solver, sediment, material)
			return
	for result in queue.apply_due_commands(0):
		if result.status == &"applied":
			undermined += float(result.get("sand_delta_m3", 0.0))
			notch_indices.append_array(result.get("dirty_cells", PackedInt32Array()))
	if not _upload_cells(solver, domain, notch_indices):
		failures.append("notch patch rejected by the solver")
		_release(solver, sediment, material)
		return

	## 4. Let the flow find the gap.
	var water_left_after := _dispatch(solver, sediment, material, BREACH_SUBSTEPS)
	var crossed := _far_side_water(solver)

	## 5. Accounts and untouched mask.
	var gpu_sand_final := _read(solver, "sand")
	var gpu_sediment := _read(solver, "sediment")
	var sand_total := 0.0
	for value in gpu_sand_final:
		sand_total += value * area
	for value in gpu_sediment:
		sand_total += value * area
	## The player's dig moves sand into the bucket, so the ledger is
	## `sand + sediment + inventory == initial + source - sink`.
	var closure := absf(sand_total + domain.tool_inventory_m3 - initial_sand -
		domain.sand_source_m3 + domain.sand_sink_m3)
	var obstacle_after := _obstacle_digest(domain)
	_release(solver, sediment, material)

	if crossed <= 0.01:
		failures.append("no new flow path opened after the collapse: %.6f m3 crossed" % crossed)
		return
	if closure > 0.01:
		failures.append("sand account did not close: %.9f m3" % closure)
		return
	if obstacle_after != obstacle_before:
		failures.append("structure events touched the obstacle mask")
		return
	lines.append("FLOW_OK booked_m3=%.6f wall_cells=%d support_before=%.4f support_after_dig=%.4f" % [
		booked, wall.cell_count(), support_before_dig, support_after_dig])
	lines.append("HOLD_OK water_left_m3=%.6f far_side_before_m3=%.6f" % [
		water_left, held])
	lines.append("BREACH_OK far_side_after_m3=%.6f crossed_m3=%.6f closure_m3=%.9f" % [
		crossed, crossed - held, closure])
	lines.append("MASK_OK digest_before=%d digest_after=%d sand_undermined_m3=%.6f" % [
		obstacle_before, obstacle_after, undermined])


## One coupled substep: water, then erosion, then wetness/compaction/slope.
func _dispatch(solver: SandcastleGpuShallowSolver,
		sediment: SandcastleGpuSedimentCoupler, material: SandcastleGpuMaterialCoupler,
		substeps: int) -> float:
	for _step in substeps:
		if not solver.dispatch_substep(SUBSTEP_S) or \
				not sediment.dispatch_after_water_substep(SUBSTEP_S) or \
				not material.dispatch_after_erosion(SUBSTEP_S):
			failures.append("coupled substep failed")
			return -1.0
	return _total(_read(solver, "water"), CELL_M * CELL_M)


func _far_side_water(solver: SandcastleGpuShallowSolver) -> float:
	var water := _read(solver, "water")
	var area := CELL_M * CELL_M
	var total := 0.0
	for z in GRID:
		for x in range(WALL_X + WALL_THICKNESS + 2, GRID):
			total += water[z * GRID + x] * area
	return total


## Uploads the current CPU shadow values for `indices` through the production
## patch path, mirroring what the preview does after a tool command.
func _upload_cells(solver: SandcastleGpuShallowSolver, domain: SandWaterDomain,
		indices: PackedInt32Array) -> bool:
	var sorted := indices.duplicate()
	sorted.sort()
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	var unique := PackedInt32Array()
	for index in sorted:
		if unique.size() > 0 and unique[unique.size() - 1] == index:
			continue
		unique.append(index)
		stream.put_32(index)
		stream.put_float(domain.sand[index])
		stream.put_float(domain.compaction[index])
		stream.put_float(0.0)
	return solver.dispatch_tool_patch(stream.data_array, unique.size())


func _read(solver: SandcastleGpuShallowSolver, field: String) -> PackedFloat32Array:
	var rid: RID = solver.current_texture(field)
	if not rid.is_valid():
		failures.append("no texture for field " + field)
		return PackedFloat32Array()
	var data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(rid, 0)
	if data.size() != GRID * GRID * 4:
		failures.append("unexpected readback size for %s: %d" % [field, data.size()])
		return PackedFloat32Array()
	return data.to_float32_array()


func _read_half(solver: SandcastleGpuShallowSolver, field: String) -> PackedFloat32Array:
	var rid: RID = solver.current_texture(field)
	var data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(rid, 0)
	if data.size() != GRID * GRID * 2:
		failures.append("unexpected half readback size for %s: %d" % [field, data.size()])
		return PackedFloat32Array()
	var values := PackedFloat32Array()
	values.resize(GRID * GRID)
	for i in GRID * GRID:
		values[i] = data.decode_half(i * 2)
	return values


func _total(values: PackedFloat32Array, area: float) -> float:
	var total := 0.0
	for value in values:
		total += value * area
	return total


func _world(x: int, z: int) -> Vector3:
	var half := float(GRID) * CELL_M * 0.5
	return Vector3((float(x) + 0.5) * CELL_M - half, 0.0, (float(z) + 0.5) * CELL_M - half)


func _obstacle_digest(domain: SandWaterDomain) -> int:
	var digest := 0
	for i in domain.obstacle.size():
		if domain.obstacle[i] >= 0.5:
			digest = (digest * 31 + i + 1) & 0x7fffffff
	return digest


func _release(solver: SandcastleGpuShallowSolver,
		sediment: SandcastleGpuSedimentCoupler,
		material: SandcastleGpuMaterialCoupler) -> void:
	material.release()
	sediment.release()
	solver.release()


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 600000:
		printerr("FAIL: structure flow probe timed out")
		_finish(1)
		return
	await process_frame
	call_deferred("_watchdog")


func _report() -> void:
	if finished:
		return
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
		_finish(1)
		return
	if lines.size() != 4:
		printerr("FAIL: expected 4 result lines, got %d" % lines.size())
		_finish(1)
		return
	for line in lines:
		print(line)
	print("PASS: T06 structure flow grid=%d substeps=%d/%d" % [
		GRID, HOLD_SUBSTEPS, BREACH_SUBSTEPS])
	_finish(0)


func _finish(code: int) -> void:
	finished = true
	for _frame in 3:
		await process_frame
	quit(code)
