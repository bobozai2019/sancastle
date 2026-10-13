extends SceneTree

const SCENE := preload("res://scenes/water_visual_fixture.tscn")
const TARGET_TICK := 60
const AREA_M2 := 0.125 * 0.125

var received: Dictionary = {}
var readback_error := ""
var case_token := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline: Dictionary = await _run_case(&"")
	if baseline.is_empty():
		quit(1)
		return
	var packet: Dictionary = await _run_case(&"test_packet")
	if packet.is_empty():
		quit(1)
		return
	var small_packet: Dictionary = await _run_case(&"small_packet")
	if small_packet.is_empty():
		quit(1)
		return
	var packet_without_foam: Dictionary = await _run_case(&"test_packet", false)
	if packet_without_foam.is_empty():
		quit(1)
		return
	var base_water: PackedFloat32Array = baseline.water
	var wave_water: PackedFloat32Array = packet.water
	var base_qx: PackedFloat32Array = baseline.momentum_x
	var wave_qx: PackedFloat32Array = packet.momentum_x
	var positive_interior := 0
	var max_depth_gain := 0.0
	var max_qx_gain := 0.0
	for z in range(32, 224):
		for x in range(12, 49):
			var i := z * 256 + x
			var gain := wave_water[i] - base_water[i]
			if gain > 0.005:
				positive_interior += 1
			max_depth_gain = maxf(max_depth_gain, gain)
			max_qx_gain = maxf(max_qx_gain, wave_qx[i] - base_qx[i])
	var wave_closed: float = packet.closure_fraction
	var foam_isolated: bool = packet.water == packet_without_foam.water and \
			packet.momentum_x == packet_without_foam.momentum_x and \
			packet.source_m3 == packet_without_foam.source_m3 and \
			packet.sink_m3 == packet_without_foam.sink_m3
	var small_gain := 0.0
	for z in range(32, 224):
		for x in range(12, 49):
			var i := z * 256 + x
			small_gain = maxf(small_gain, small_packet.water[i] - base_water[i])
	var passes: bool = positive_interior > 50 and max_depth_gain > 0.01 and \
			max_qx_gain > 0.002 and wave_closed <= 0.005 and \
			packet.invalid_count == 0 and packet.negative_count == 0 and \
			packet.source_m3 > baseline.source_m3 and \
			small_gain > 0.002 and small_packet.closure_fraction <= 0.005 and \
			packet.max_substeps <= 32 and small_packet.max_substeps <= 32 and foam_isolated
	var report := {"tick": TARGET_TICK, "wave_start_tick": packet.start_tick,
		"positive_interior_cells": positive_interior,
		"max_interior_depth_gain_m": max_depth_gain,
		"max_interior_qx_gain_m2_s": max_qx_gain,
		"small_profile_max_interior_depth_gain_m": small_gain,
		"small_profile_closure_fraction": small_packet.closure_fraction,
		"test_profile_max_substeps": packet.max_substeps,
		"small_profile_max_substeps": small_packet.max_substeps,
		"foam_gpu_state_isolated": foam_isolated,
		"baseline_source_m3": baseline.source_m3,
		"wave_source_m3": packet.source_m3,
		"wave_sink_m3": packet.sink_m3,
		"wave_closure_fraction": wave_closed,
		"wave_invalid_cells": packet.invalid_count,
		"wave_negative_cells": packet.negative_count,
		"wave_clamp_events": packet.wave_clamp_events}
	var path := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/W04_wave_probe.json"
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print(("PASS" if passes else "FAIL") + ": W04 wave probe " + JSON.stringify(report))
	quit(0 if passes else 1)


func _run_case(profile_id: StringName, with_foam: bool = true) -> Dictionary:
	case_token += 1
	var token := case_token
	received.clear()
	readback_error = ""
	var preview: Node3D = SCENE.instantiate()
	preview.enable_phase2_foam = with_foam
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks:
		push_error("fixture did not initialize: " + preview.last_error)
		return {}
	var initial_water_m3: float = preview.shadow_domain.total_water_m3()
	var start_tick := -1
	if not profile_id.is_empty():
		start_tick = preview.completed_ticks + 8
		var request := {"domain_id": preview.shadow_domain.domain_id,
			"generation": preview.generation, "request_id": 1,
			"start_tick": start_tick, "profile_id": profile_id,
			"amplitude_m": 0.05 if profile_id == &"small_packet" else 0.10,
			"duration_s": 1.5, "seed": 17}
		var stale: Dictionary = request.duplicate()
		stale.generation = preview.generation - 1
		if preview.request_wave(stale).code != &"inactive_generation":
			push_error("stale generation accepted")
			return {}
		var invalid_profile: Dictionary = request.duplicate()
		invalid_profile.profile_id = &"missing"
		if preview.request_wave(invalid_profile).code != &"invalid_profile":
			push_error("invalid wave profile accepted")
			return {}
		var accepted: Dictionary = preview.request_wave(request)
		if not accepted.ok or accepted.effective_tick != start_tick:
			push_error("wave request rejected: " + str(accepted))
			return {}
		if preview.request_wave(request).code != &"duplicate_request":
			push_error("duplicate wave accepted")
			return {}
	var max_substeps := 0
	while preview.completed_ticks < TARGET_TICK and preview.last_error.is_empty() and frames < 3600:
		await process_frame
		max_substeps = maxi(max_substeps, preview.last_substeps)
		frames += 1
	if preview.completed_ticks < TARGET_TICK or not preview.last_error.is_empty():
		push_error("case did not reach target: " + preview.last_error)
		return {}
	preview.playing = false
	while preview.tick_pending and frames < 3900:
		await process_frame
		frames += 1
	RenderingServer.call_on_render_thread(_request_fields.bind(preview, token))
	while received.size() < 2 and readback_error.is_empty() and frames < 4200:
		await process_frame
		frames += 1
	if received.size() < 2 or not readback_error.is_empty():
		push_error("wave readback failed: " + readback_error)
		return {}
	var water: PackedFloat32Array = received.water.to_float32_array()
	var qx: PackedFloat32Array = received.momentum_x.to_float32_array()
	if water.size() != 65536 or qx.size() != 65536:
		push_error("wave readback size mismatch")
		return {}
	var volume := 0.0
	var invalid := 0
	var negative := 0
	for value in water:
		if not is_finite(value):
			invalid += 1
		elif value < -0.000001:
			negative += 1
		volume += value * AREA_M2
	var source: float = preview.solver.water_source_m3
	var sink: float = preview.solver.water_sink_m3
	var result := {"water": water, "momentum_x": qx,
		"source_m3": source, "sink_m3": sink,
		"closure_fraction": absf(volume - (initial_water_m3 + source - sink)) / maxf(volume, 1.0),
		"invalid_count": invalid, "negative_count": negative,
		"wave_clamp_events": preview.wave_clamp_events,
		"max_substeps": max_substeps,
		"start_tick": start_tick}
	preview.queue_free()
	await process_frame
	await process_frame
	return result


func _request_fields(preview: Node3D, token: int) -> void:
	for field in ["water", "momentum_x"]:
		var error: Error = preview.solver.request_data(field, _on_field.bind(field, token))
		if error != OK:
			call_deferred("_receive_error", "%s: %d" % [field, error], token)


func _on_field(data: PackedByteArray, field: String, token: int) -> void:
	call_deferred("_receive_field", data, field, token)


func _receive_field(data: PackedByteArray, field: String, token: int) -> void:
	if token == case_token:
		received[field] = data


func _receive_error(message: String, token: int) -> void:
	if token == case_token:
		readback_error = message
