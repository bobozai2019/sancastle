extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var rows:={}
	for id in ["uncached","cached"]:
		preview.candidate_metadata_cache_enabled=id=="cached"
		var timings:=[]
		for i in range(50):
			var start:=Time.get_ticks_usec()
			preview._seal_test1_effective_profile()
			timings.append(Time.get_ticks_usec()-start)
		var metadata:={}
		for name in ["effective_render_profile","effective_candidate","effective_lighting","effective_optics","effective_foam","effective_reflection","effective_style"]:
			metadata[name]=preview.get(name).duplicate(true)
		var images:={}
		for camera in [&"oblique",&"close",&"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[id,String(camera)]
			if root.get_texture().get_image().save_png(path)!=OK:_fail("cache capture failed");return
			images[String(camera)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"seal_us":timings,"metadata":metadata,"images":images,"fields":await _hash_state()}
	var metadata_equal:bool=rows.uncached.metadata==rows.cached.metadata
	var authority_equal:=true
	for name in before:
		if rows.uncached.fields[name]!=before[name].sha256 or rows.cached.fields[name]!=before[name].sha256:authority_equal=false
	var file:=FileAccess.open(output+"/metadata_cache.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"metadata_equal":metadata_equal,"authority_equal":authority_equal,"scope":"Same frozen coupled completed tick360, actual seal calls only; not full 60s cost or live restoration acceptance."},"\t"));file.close()
	if not metadata_equal or not authority_equal:_fail("cache changed metadata or authority")
