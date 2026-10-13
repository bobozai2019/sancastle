extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(_before: Dictionary) -> void:
	var rows:=[]
	var start:int=preview.completed_ticks
	var deadline:=Time.get_ticks_msec()+300000
	for tick in range(start,start+301,6):
		preview.replay_target_tick=tick;preview.replay_ready=false
		while not preview.replay_ready:
			await process_frame
			if not preview.last_error.is_empty() or Time.get_ticks_msec()>deadline:_fail("RDC sequence timeout");return
		preview._seal_test1_effective_profile()
		if preview.completed_ticks!=tick or preview.tick_pending or not is_equal_approx(preview.visual_time_s,tick/30.):_fail("RDC completed-state mismatch");return
		for material in [preview.water_material,preview.terrain_material]:
			if not is_equal_approx(material.get_shader_parameter("visual_time_s"),tick/30.):_fail("RDC clock mismatch");return
		var images:={}
		for cam in [&"close",&"oblique",&"grazing"]:
			preview.set_fixture_camera(cam)
			for frame in range(3):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%04d.png"%[String(cam),tick]
			root.get_texture().get_image().save_png(path)
			images[String(cam)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		var row:={"tick":tick,"visual_time_s":preview.visual_time_s,"generation":preview.generation,"images":images}
		if tick in [start,start+150,start+300]:
			var before:=await _hash_state()
			preview.set_fixture_camera(&"close")
			for frame in range(6):await process_frame
			await RenderingServer.frame_post_draw
			var first:=root.get_texture().get_image()
			for frame in range(30):await process_frame
			await RenderingServer.frame_post_draw
			var repeat:=root.get_texture().get_image()
			var after:=await _hash_state()
			if before!=after or first.get_data()!=repeat.get_data():_fail("RDC pause drift");return
			row["held"]={"authority_unchanged":true,"pixels_exact":true,"render_frames":30,"fields":before}
		rows.append(row)
		var progress:=FileAccess.open(output+"/progress.json",FileAccess.WRITE);progress.store_string(JSON.stringify({"tick":tick,"frames":rows.size()}));progress.close()
	var file:=FileAccess.open(output+"/rdc_sequence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":rows,"pass":true,"effective_style":preview.effective_style,"scope":"10 simulated seconds, 5 samples/s, three cameras; held texture/clock/pixels. Not performance or full long-run gate."},"\t"));file.close()
