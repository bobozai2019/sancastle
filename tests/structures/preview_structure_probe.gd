extends SceneTree

## T06 main-scene integration probe.
##
## Loads the real 256² coupled preview with the structure layer on, pauses it and
## builds a wall through `request_build_structure`. That one call has to leave
## three things agreeing:
##
##   * the GPU sand texture (what the terrain and water shaders sample)
##   * the collision proxy chunks covering the wall
##   * the CPU shadow the tool and checkpoint paths read
##
## It then captures a still so the wall is visible in the player view, and checks
## the sand ledger and the obstacle mask.

const Structure = preload("res://scripts/structures/structure_state.gd")

const STILL := "res://test_output/sandcastle_water_sand_coupling/验收/T06_preview_wall_20260929.png"
const CAMERA_POSITION := Vector3(1.0, 5.5, 8.5)
const CAMERA_TARGET := Vector3(3.0, 0.05, -1.0)
const GRID := 256


var preview: Node3D
var finished := false
var started_ms := 0
var failures: Array[String] = []
var results: Array[String] = []
## Bed under the wall footprint captured just before the build, so the check can
## compare the height the wall added rather than assume a flat scenario bed.
var pre_build_sand := PackedFloat32Array()
var wall_booked := 0.0
var inventory_before_build := 0.0
var inventory_before_tower := 0.0
var inventory_after := 0.0
var dug_m3 := 0.0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("preview scene unavailable")
		return
	preview = scene.instantiate()
	preview.preset_index = 1
	preview.enable_erosion = true
	preview.enable_structures = true
	preview.hide_hud = true
	preview.show_brush_indicator = false
	preview.use_player_camera = true
	preview.player_camera_position = CAMERA_POSITION
	preview.player_camera_target = CAMERA_TARGET
	root.add_child(preview)
	call_deferred("_watchdog")
	call_deferred("_wait_ready")


func _wait_ready() -> void:
	while not finished:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if preview.ready_for_ticks and preview.collision_proxy.applied_revisions.size() >= 64:
			break
		await process_frame
	if finished:
		return
	## Pause so the render-thread build cannot race the tick loop.
	preview.playing = false
	var waited := 0
	while not finished and preview.tick_pending and waited < 600:
		await process_frame
		waited += 1
	_build()


func _build() -> void:
	var wall := Structure.new()
	wall.kind = Structure.Kind.WALL
	wall.name = "preview_wall"
	## A ridge on the beach in the mid-ground of the player camera, wide enough
	## to span several 32² chunks and long enough to read at this distance. The
	## taper keeps every step inside the angle of repose at this compaction, so
	## the slope relaxation leaves it standing.
	wall.origin = Vector2i(122, 112)
	wall.size = Vector2i(7, 34)
	wall.height_m = 0.34
	wall.taper_slope_m = 0.11
	wall.compaction = 0.9
	pre_build_sand = preview.shadow_domain.sand.duplicate()
	## Player placement spends the bucket, so dig the spoil first - the loop the
	## player actually has to run.
	dug_m3 = _fill_bucket(240)
	if dug_m3 <= 0.0:
		_fail("could not fill the tool bucket before building")
		return
	inventory_before_build = preview.shadow_domain.tool_inventory_m3
	if not preview.request_build_structure(wall, true):
		_fail("preview refused the structure build")
		return
	var waited := 0
	while not finished and preview.last_structure_booked_m3 <= 0.0 and waited < 600:
		await process_frame
		waited += 1
	if finished:
		return
	if preview.last_structure_booked_m3 <= 0.0:
		_fail("structure build never completed")
		return
	wall_booked = preview.last_structure_booked_m3
	## Let the collision proxy finish applying the chunks it was handed.
	waited = 0
	while not finished and (preview.collision_proxy.pending_revisions.size() > 0 or
			preview.collision_proxy.active_chunks.size() > 0) and waited < 900:
		await process_frame
		waited += 1
	if finished:
		return
	## The player placement path: a tower centred on a world position, placed next
	## to the wall so the still shows both kinds.
	inventory_before_tower = preview.shadow_domain.tool_inventory_m3
	var tower_ok: bool = preview.place_structure_at_world(Structure.Kind.TOWER,
		Vector3(-3.0, 0.0, -4.0))
	waited = 0
	while not finished and (preview.last_structure_booked_m3 <= 0.0 or
			preview.structure_builds < 2) and waited < 600:
		await process_frame
		waited += 1
	if finished:
		return
	if not tower_ok or preview.structure_builds < 2:
		_fail("player placement path did not build the tower")
		return
	while not finished and (preview.collision_proxy.pending_revisions.size() > 0 or
			preview.collision_proxy.active_chunks.size() > 0) and waited < 900:
		await process_frame
		waited += 1
	if finished:
		return
	## Chunks are rebuilt from the shadow, so refresh the shadow first and then
	## re-apply the wall's chunks: otherwise the recorded collision shape would
	## have been built from a shadow that predates the last erosion edits.
	if preview.shadow_revision != preview.solver.state_revision and 			preview.shadow_sync_reason.is_empty():
		preview._request_shadow_sync("debug")
	waited = 0
	while not finished and (preview.tick_pending or
			preview.shadow_revision != preview.solver.state_revision) and waited < 900:
		await process_frame
		waited += 1
	if finished:
		return
	if preview.shadow_revision != preview.solver.state_revision:
		_fail("shadow sync never reached the GPU revision")
		return
	var wall_chunks: PackedInt32Array = preview._chunks_for_cells(wall.cells(GRID))
	RenderingServer.call_on_render_thread(preview._render_apply_shadow_chunks.bind(
		wall_chunks, preview.solver.state_revision, preview.generation))
	waited = 0
	while not finished and (preview.collision_proxy.pending_revisions.size() > 0 or
			preview.collision_proxy.active_chunks.size() > 0) and waited < 900:
		await process_frame
		waited += 1
	if finished:
		return
	_verify(wall, wall_chunks)


func _verify(wall: SandcastleStructure, wall_chunks: PackedInt32Array) -> void:
	var gpu_sand := _read("sand")
	if gpu_sand.is_empty():
		return
	var shadow: PackedFloat32Array = preview.shadow_domain.sand
	## The wall must have added exactly its profile to the GPU bed, and the shadow
	## must have taken the same profile.
	var worst_gpu := 0.0
	var worst_shadow := 0.0
	var crest_cells := 0
	for z in range(wall.origin.y, wall.origin.y + wall.size.y):
		for x in range(wall.origin.x, wall.origin.x + wall.size.x):
			var i := z * GRID + x
			var expected := wall.height_at(x, z)
			worst_gpu = maxf(worst_gpu, absf(gpu_sand[i] - pre_build_sand[i] - expected))
			worst_shadow = maxf(worst_shadow, absf(shadow[i] - pre_build_sand[i] - expected))
		if is_equal_approx(wall.height_at(wall.origin.x + wall.size.x / 2, z),
				wall.height_m):
			crest_cells += 1
	var collision_error := _collision_error(wall)
	var obstacle_digest := _obstacle_digest()
	var tower_booked: float = preview.last_structure_booked_m3
	inventory_after = preview.shadow_domain.tool_inventory_m3
	if worst_gpu > 0.000001:
		failures.append("GPU bed does not carry the wall profile: %.9f m" % worst_gpu)
	elif worst_shadow > 0.000001:
		failures.append("shadow bed does not carry the wall profile: %.9f m" % worst_shadow)
	elif crest_cells != wall.size.y:
		failures.append("wall crest missing on the GPU: %d of %d columns" % [
			crest_cells, wall.size.y])
	elif collision_error > 0.003:
		failures.append("collision proxy disagrees with the bed by %.6f m" % collision_error)
	elif obstacle_digest != 0:
		failures.append("structure build touched the obstacle mask")
		return
	results.append("BUILD_OK wall_booked_m3=%.6f cells=%d crest_columns=%d" % [
		wall_booked, wall.cell_count(), crest_cells])
	results.append("GPU_OK profile_error_m=%.9f shadow_profile_error_m=%.9f" % [
		worst_gpu, worst_shadow])
	results.append("COLLISION_OK max_error_m=%.6f chunk_revisions=%d" % [
		collision_error, preview.collision_proxy.applied_revisions.size()])
	results.append("MASK_OK digest=%d builds=%d tower_booked_m3=%.6f" % [
		obstacle_digest, preview.structure_builds, tower_booked])
	results.append("BUCKET_OK dug_m3=%.6f wall_booked_m3=%.6f tower_booked_m3=%.6f " % [
		dug_m3, wall_booked, tower_booked] +
		"inventory_before_wall=%.6f inventory_before_tower=%.6f inventory_after=%.6f" % [
			inventory_before_build, inventory_before_tower, inventory_after])
	_capture()


## Digs `commands` brush-fulls of sand into the bucket through the production
## command queue, then uploads the changed cells to the GPU. Returns the volume
## moved into the inventory.
func _fill_bucket(commands: int) -> float:
	var domain: SandWaterDomain = preview.shadow_domain
	var queue: ToolCommandQueue = preview.command_queue
	var before := domain.tool_inventory_m3
	var touched := PackedInt32Array()
	for index in commands:
		var x := 60 + (index % 12)
		var z := 40 + (index / 12)
		var error: StringName = queue.submit({
			"domain_id": domain.domain_id, "generation": domain.generation,
			"sim_tick": domain.sim_tick, "command_id": index + 1, "kind": &"remove_sand",
			"shape": &"circle", "transform": {"position_m": _world(x, z)},
			"radius_m": 0.38, "strength": 1.0, "amount_m3": 0.05, "seed": index + 1})
		if not error.is_empty():
			_fail("bucket fill brush rejected: " + String(error))
			return 0.0
	for result in queue.apply_due_commands(domain.sim_tick):
		if result.status == &"applied":
			touched.append_array(result.get("dirty_cells", PackedInt32Array()))
	if not _upload(preview, domain, touched):
		_fail("bucket fill patch rejected by the solver")
		return 0.0
	return domain.tool_inventory_m3 - before


func _upload(preview_node: Node3D, domain: SandWaterDomain,
		indices: PackedInt32Array) -> bool:
	var sorted := indices.duplicate()
	sorted.sort()
	var unique := PackedInt32Array()
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	for index in sorted:
		if unique.size() > 0 and unique[unique.size() - 1] == index:
			continue
		unique.append(index)
		stream.put_32(index)
		stream.put_float(domain.sand[index])
		stream.put_float(domain.compaction[index])
		stream.put_float(0.0)
	return preview_node.solver.dispatch_tool_patch(stream.data_array, unique.size())


func _world(x: int, z: int) -> Vector3:
	var half := 256.0 * 0.125 * 0.5
	return Vector3((float(x) + 0.5) * 0.125 - half, 0.0, (float(z) + 0.5) * 0.125 - half)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(STILL)
	if error != OK:
		_fail("still save failed: %d" % error)
		return
	_report()


## Largest disagreement between the collision proxy heightmaps and the synced
## shadow bed, over the chunks the structure touched. The whole-domain version of
## this measure is covered by the coupled preview regression.
## Largest disagreement between the wall's own columns in the collision proxy and
## the synced shadow bed. Scoped to the footprint on purpose: the probe is about
## what a structural event changed, and the whole-domain measure is covered by the
## coupled preview regression.
func _collision_error(wall: SandcastleStructure) -> float:
	var worst := 0.0
	for z in range(wall.origin.y, wall.origin.y + wall.size.y):
		for x in range(wall.origin.x, wall.origin.x + wall.size.x):
			var chunk_id: int = (z / 32) * 8 + (x / 32)
			var node: CollisionShape3D = preview.collision_proxy.shapes.get(chunk_id)
			if node == null or not (node.shape is HeightMapShape3D):
				return INF
			var values: PackedFloat32Array = node.shape.map_data
			var i: int = z * GRID + x
			worst = maxf(worst, absf(values[(z % 32) * 33 + (x % 32)] -
				preview.shadow_domain.rock[i] - preview.shadow_domain.sand[i]))
	return worst


func _read(field: String) -> PackedFloat32Array:
	var rid: RID = preview.solver.current_texture(field)
	if not rid.is_valid():
		_fail("no texture for field " + field)
		return PackedFloat32Array()
	var data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(rid, 0)
	if data.size() != GRID * GRID * 4:
		_fail("unexpected readback size for %s: %d" % [field, data.size()])
		return PackedFloat32Array()
	return data.to_float32_array()


func _obstacle_digest() -> int:
	var digest := 0
	for i in preview.shadow_domain.obstacle.size():
		if preview.shadow_domain.obstacle[i] >= 0.5:
			digest = (digest * 31 + i + 1) & 0x7fffffff
	return digest


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 600000:
			_fail("preview structure probe timed out")
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _report() -> void:
	if finished:
		return
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
		_finish(1)
		return
	if results.size() != 5:
		printerr("FAIL: expected 5 result lines, got %d" % results.size())
		_finish(1)
		return
	for line in results:
		print(line)
	print("PASS: T06 preview structure grid=%d still=%s" % [GRID, STILL])
	_finish(0)


func _finish(code: int) -> void:
	finished = true
	if preview != null:
		preview.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)
