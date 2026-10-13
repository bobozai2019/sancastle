extends SceneTree

const SCENE := preload("res://scenes/water_visual_fixture.tscn")
const TARGET_TICK := 1200

var preview: Node3D
var wave_requested := false
var close_camera := false
var grazing_camera := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preview = SCENE.instantiate()
	preview.hide_hud = true
	preview.show_brush_indicator = false
	root.add_child(preview)
	while preview.completed_ticks < TARGET_TICK and preview.last_error.is_empty():
		await process_frame
		if not preview.ready_for_ticks:
			continue
		var tick: int = preview.completed_ticks
		preview.set_visual_time(float(tick) / 30.0)
		if tick >= 60 and not wave_requested:
			var accepted: Dictionary = preview.request_wave({
				"domain_id": preview.shadow_domain.domain_id,
				"generation": preview.generation, "request_id": 1,
				"start_tick": tick + 8, "profile_id": &"test_packet",
				"amplitude_m": 0.18, "duration_s": 6.0, "seed": 31})
			if not accepted.ok:
				push_error("movie wave request failed: " + str(accepted))
				quit(1)
				return
			wave_requested = true
		if tick >= 480 and not close_camera:
			preview.set_fixture_camera(&"close")
			close_camera = true
		if tick >= 900 and not grazing_camera:
			preview.set_fixture_camera(&"grazing")
			grazing_camera = true
	if not preview.last_error.is_empty():
		push_error("movie scene failed: " + preview.last_error)
		quit(1)
		return
	print("PASS: W05 foam movie tick=%d revision=%d" % [
		preview.completed_ticks, preview.solver.state_revision])
	quit(0)
