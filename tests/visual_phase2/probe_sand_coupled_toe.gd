extends SceneTree

const SCENE := preload("res://scenes/sand_coupled_fixture.tscn")
const OUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/S05_coupled_toe_probe.json"
const N := 256
const AREA := 0.125 * 0.125

var preview: Node3D
var received := {}
var frames := 0
var no_wave := false


func _init() -> void:
	no_wave = OS.get_cmdline_user_args().has("--no-wave")
	call_deferred("_run")


func _run() -> void:
	preview = SCENE.instantiate()
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 5000:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks:
		_fail("fixture init: " + preview.last_error)
		return
	var initial_water_m3: float = preview.shadow_domain.total_water_m3()
	var wave := {"domain_id": preview.shadow_domain.domain_id,
		"generation": preview.generation, "request_id": 1,
		"start_tick": preview.completed_ticks + 8, "profile_id": &"test_packet",
		"amplitude_m": 0.20, "duration_s": 5.0, "seed": 53021}
	if not no_wave:
		var admission: Dictionary = preview.request_wave(wave)
		if not admission.ok:
			_fail("wave admission: " + str(admission))
			return
	var samples := {}
	for target in [150, 300, 600, 900]:
		while preview.completed_ticks < target and preview.last_error.is_empty() and frames < 120000:
			await process_frame
			frames += 1
		if not preview.last_error.is_empty():
			_fail("tick: " + preview.last_error)
			return
		preview.playing = false
		while preview.tick_pending:
			await process_frame
		received.clear()
		RenderingServer.call_on_render_thread(_read)
		while received.size() < 3 and frames < 125000:
			await process_frame
			frames += 1
		var sand: PackedFloat32Array = received.sand.to_float32_array()
		var sediment: PackedFloat32Array = received.sediment.to_float32_array()
		var water: PackedFloat32Array = received.water.to_float32_array()
		var toe := 0.0
		var outside := 0.0
		var suspended := 0.0
		var water_m3 := 0.0
		var wet_cells := 0
		var packed := 0.0
		var min_sand := INF
		for z in N:
			for x in N:
				var i := z * N + x
				outside += sand[i] * AREA
				suspended += sediment[i] * AREA
				water_m3 += water[i] * AREA
				min_sand = minf(min_sand, sand[i])
				if x >= 69 and x <= 71 and z >= 120 and z <= 136:
					toe += sand[i] * AREA
					if water[i] > 0.001:
						wet_cells += 1
				if x >= 72 and x <= 88 and z >= 120 and z <= 136:
					packed += sand[i] * AREA
		await physics_frame
		await physics_frame
		var ray_x := 72
		var ray_z := 128
		var world_x := (float(ray_x) + 0.5) * 0.125 - 16.0
		var world_z := (float(ray_z) + 0.5) * 0.125 - 16.0
		var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(
				Vector3(world_x, 10.0, world_z),
				Vector3(world_x, -10.0, world_z)))
		var collision_error := absf(hit.position.y - (-0.12 + sand[ray_z * N + ray_x])) \
			if hit.has("position") else INF
		samples[str(preview.completed_ticks)] = {"toe_m3": toe,
			"packed_m3": packed, "total_bed_m3": outside,
			"suspended_m3": suspended, "toe_wet_cells": wet_cells,
			"water_m3": water_m3,
			"water_source_m3": preview.solver.water_source_m3,
			"water_sink_m3": preview.solver.water_sink_m3,
			"water_closure_m3": water_m3 - initial_water_m3 - \
				preview.solver.water_source_m3 + preview.solver.water_sink_m3,
			"min_sand_m": min_sand, "collision_error_m": collision_error,
			"collision_readback_ms": preview.collision_proxy.last_readback_ms,
			"collision_replace_ms": preview.collision_proxy.last_replace_ms,
			"revision": preview.solver.state_revision,
			"support_events": preview.support_loss_events.duplicate(true),
			"sensor_toe_m3": preview.auto_support_toe_latest_m3,
			"sensor_in_flight": preview.auto_support_sensor_in_flight,
			"nonzero_dirty_ticks": preview.nonzero_dirty_summary_ticks}
		preview.set_fixture_camera(&"oblique")
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(
			"res://test_output/sandcastle_visual_reconstruction_phase2/验收/S05_toe_t%d.png" % preview.completed_ticks))
		preview.playing = true
	var output_path := OUT.replace(".json", "_no_wave.json") if no_wave else OUT
	var file := FileAccess.open(ProjectSettings.globalize_path(output_path), FileAccess.WRITE)
	file.store_string(JSON.stringify({"wave": {} if no_wave else wave,
		"initial_water_m3": initial_water_m3, "samples": samples}, "  "))
	file.close()
	print("PASS: S05 coupled toe probe " + JSON.stringify(samples))
	quit(0)


func _read() -> void:
	var rd := RenderingServer.get_rendering_device()
	var data := {}
	for field in ["sand", "sediment", "water"]:
		data[field] = rd.texture_get_data(preview.solver.current_texture(field), 0)
	call_deferred("_receive", data)


func _receive(data: Dictionary) -> void:
	received = data


func _fail(reason: String) -> void:
	push_error("FAIL: S05 coupled toe " + reason)
	quit(1)
