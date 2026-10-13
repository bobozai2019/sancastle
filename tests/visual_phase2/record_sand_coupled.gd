extends SceneTree

const SCENE := preload("res://scenes/sand_coupled_fixture.tscn")
const TARGET_TICK := 2100
const OUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/"

var preview: Node3D
var wave_requested := false
var remove_requested := false
var place_requested := false
var snapshots := {}
var snapshot_targets := [120, 240, 360, 600, 900, 1200, 1500, 1800, 2100]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preview = SCENE.instantiate()
	root.add_child(preview)
	while preview.completed_ticks < TARGET_TICK and preview.last_error.is_empty():
		await process_frame
		if not preview.ready_for_ticks:
			continue
		var tick: int = preview.completed_ticks
		preview.set_visual_time(float(tick) / 30.0)
		if tick >= 20 and not remove_requested:
			var site := Vector3(6.0625, 1.5, 0.0625)
			var error: StringName = preview._submit_brush(&"remove_sand", 0.03,
				site, site, &"circle")
			if not error.is_empty():
				_fail("remove tool: " + String(error))
				return
			remove_requested = true
		if tick >= 40 and not place_requested:
			var site := Vector3(7.0625, -0.12, 0.0625)
			var error: StringName = preview._submit_brush(&"place_sand", 0.03,
				site, site, &"circle")
			if not error.is_empty():
				_fail("place tool: " + String(error))
				return
			place_requested = true
		if tick >= 60 and not wave_requested:
			var accepted: Dictionary = preview.request_wave({
				"domain_id": preview.shadow_domain.domain_id,
				"generation": preview.generation, "request_id": 1,
				"start_tick": tick + 8, "profile_id": &"test_packet",
				"amplitude_m": 0.20, "duration_s": 5.0, "seed": 53021})
			if not accepted.ok:
				_fail("wave: " + str(accepted))
				return
			wave_requested = true
		if tick >= 450 and tick < 900:
			preview.set_fixture_camera(&"close")
		elif tick >= 900 and tick < 1500:
			preview.set_fixture_camera(&"grazing")
		elif tick >= 1500:
			preview.set_fixture_camera(&"oblique")
		if not snapshot_targets.is_empty() and tick >= snapshot_targets[0]:
			var intended_tick: int = snapshot_targets.pop_front()
			var image_path := ProjectSettings.globalize_path(
				OUT + "S05_demo_t%d.png" % intended_tick)
			if root.get_viewport().get_texture().get_image().save_png(image_path) != OK:
				_fail("snapshot %d" % intended_tick)
				return
			snapshots[str(intended_tick)] = {"actual_tick": tick,
				"camera": String(preview.fixture_camera_id),
				"revision": preview.solver.state_revision,
				"support_events": preview.support_loss_events.size()}
	if not preview.last_error.is_empty():
		_fail("scene: " + preview.last_error)
		return
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var report := {"end_tick": preview.completed_ticks,
		"wave_requests": preview.wave_requests.duplicate(true),
		"support_events": preview.support_loss_events.duplicate(true),
		"tool_commands": preview.command_queue.applied_log.duplicate(true),
		"snapshots": snapshots, "water_source_m3": preview.solver.water_source_m3,
		"water_sink_m3": preview.solver.water_sink_m3,
		"max_gpu_dirty_um": preview.max_gpu_dirty_um}
	var file := FileAccess.open(ProjectSettings.globalize_path(
		OUT + "S05_sand_coupled_demo.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	if preview.support_loss_events.size() != 1 or \
			preview.command_queue.applied_log.size() != 2 or \
			preview.wave_requests.size() != 1 or not snapshot_targets.is_empty():
		_fail("event/command/snapshot count: " + JSON.stringify(report))
		return
	print("PASS: S05 sand coupled movie tick=%d event_tick=%d snapshots=%d" % [
		preview.completed_ticks, preview.support_loss_events[0].tick, snapshots.size()])
	quit(0)


func _fail(reason: String) -> void:
	push_error("FAIL: S05 sand coupled movie " + reason)
	quit(1)
