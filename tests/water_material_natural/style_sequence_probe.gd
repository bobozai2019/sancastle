extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(_before: Dictionary) -> void:
	var frames := []
	var checkpoints := {}
	var deadline := Time.get_ticks_msec() + 1800000
	for tick in range(target_tick, target_tick + 1801, 3):
		preview.replay_target_tick = tick
		preview.replay_ready = false
		while not preview.replay_ready:
			await process_frame
			if not preview.last_error.is_empty() or Time.get_ticks_msec() > deadline:
				_fail("style sequence completion timeout: " + preview.last_error); return
		if preview.completed_ticks != tick or preview.tick_pending or not is_equal_approx(preview.visual_time_s, float(tick) / 30.):
			_fail("style sequence clock/completed state mismatch"); return
		var images := {}
		for camera in [&"oblique", &"close", &"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(3): await process_frame
			await RenderingServer.frame_post_draw
			var path: String = output + "/%s_%04d.png" % [String(camera), tick]
			if root.get_texture().get_image().save_png(path) != OK:
				_fail("style sequence capture failure"); return
			images[String(camera)] = {"path": path, "sha256": FileAccess.get_sha256(path)}
		if (tick - target_tick) % 300 == 0:
			var hashes := await _hash_state()
			var clocks := {}
			for pair in [["water",preview.water_material],["bed",preview.terrain_material]]:
				var value:Variant=pair[1].get_shader_parameter("visual_time_s")
				if value==null or not is_equal_approx(float(value),float(tick)/30.):
					_fail("actual shader clock mismatch: "+String(pair[0]));return
				clocks[String(pair[0])]=value
			for name in fields:
				var raw := FileAccess.open(output + "/%s_%04d.bin" % [name, tick], FileAccess.WRITE)
				raw.store_buffer(fields[name]); raw.close()
			checkpoints[str(tick)] = {"hashes": hashes, "generation": preview.generation,
				"revision": preview.solver.state_revision, "visual_time_s": preview.visual_time_s,
				"shader_clocks":clocks,"effective_style":preview.effective_style.duplicate(true),
				"state_only_layers":["fine_foam","contact"]}
		if tick in [target_tick, target_tick + 900, target_tick + 1800]:
			preview.set_fixture_camera(&"close")
			for i in range(8): await process_frame
			await RenderingServer.frame_post_draw
			var held_path: String = output + "/held_%04d.png" % tick
			root.get_texture().get_image().save_png(held_path)
			var before := await _hash_state()
			for i in range(30): await process_frame
			await RenderingServer.frame_post_draw
			var repeat_path: String = output + "/held_repeat_%04d.png" % tick
			root.get_texture().get_image().save_png(repeat_path)
			var after := await _hash_state()
			if before != after or preview.completed_ticks != tick:
				_fail("held completed-state authority changed"); return
			checkpoints[str(tick)]["held"] = {"first": held_path, "repeat": repeat_path,
				"authority_unchanged": true, "render_frames": 30}
		frames.append({"tick": tick, "time_s": preview.visual_time_s, "generation": preview.generation,
			"revision": preview.solver.state_revision, "images": images})
		if (tick - target_tick) % 90 == 0 or tick == target_tick + 1800:
			var progress := FileAccess.open(output + "/sequence_progress.json", FileAccess.WRITE)
			progress.store_string(JSON.stringify({"frames": frames.size(), "tick": tick,
				"visual_time_s": preview.visual_time_s, "target_end_tick": target_tick + 1800}, "\t")); progress.close()
	var file := FileAccess.open(output + "/style_sequence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "checkpoints": checkpoints,
		"workload": preview.staging_wave_workload, "wave_request_count": preview.wave_requests.size(),
		"viewport_px": root.size, "effective_style": preview.effective_style,
		"effective_reflection": preview.effective_reflection, "effective_foam": preview.effective_foam,
		"timebase": "completed_tick/30; 60 simulated seconds at 10 samples/s for each of three cameras; offline, not realtime throughput or cost",
		"new_visual_history": false}, "\t")); file.close()
