extends "res://tests/edit_validation/beach_feedback_probe.gd"

var roi := Rect2i()
var pixel_rows := []
var image_geometry := {}
var roi_result := {}
var roi_results := []
var roi_pending := 0

func _write() -> void:
	var file := FileAccess.open(output.path_join("beach_pixel_feedback_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"rows":pixel_rows,"image_geometry":image_geometry,"roi":[roi.position.x,roi.position.y,roi.size.x,roi.size.y],"scope":"paused full beach, fixed visual clock/camera, asynchronous GPU ROI copy observation upper bound includes callback latency; no physical display timestamp or formal cost"},"\t"))

func _sample_pixels() -> Dictionary:
	await RenderingServer.frame_post_draw
	roi_result.clear()
	var start := Time.get_ticks_usec()
	var frame := Engine.get_process_frames()
	roi_pending+=1
	RenderingServer.call_on_render_thread(_copy_roi.bind(root.get_texture().get_rid(),start,frame))
	while roi_result.is_empty(): await process_frame
	return roi_result.duplicate()

func _copy_roi(viewport_texture: RID, start: int, frame: int) -> void:
	var rd: RenderingDevice=preview.solver.rd
	var source: RID=RenderingServer.texture_get_rd_texture(viewport_texture)
	if not source.is_valid(): call_deferred("_roi_failure","viewport RD texture unavailable");return
	var source_format := rd.texture_get_format(source)
	var format := RDTextureFormat.new()
	format.width=roi.size.x;format.height=roi.size.y;format.texture_type=RenderingDevice.TEXTURE_TYPE_2D
	format.format=source_format.format
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var target := rd.texture_create(format,RDTextureView.new())
	if not target.is_valid(): call_deferred("_roi_failure","ROI texture unavailable");return
	var error := rd.texture_copy(source,target,Vector3(roi.position.x,roi.position.y,0),Vector3.ZERO,Vector3(roi.size.x,roi.size.y,1),0,0,0,0)
	if error!=OK: rd.free_rid(target);call_deferred("_roi_failure","ROI copy error %d" % error);return
	error=rd.texture_get_data_async(target,0,_roi_callback.bind(target,format.format,start,frame))
	if error!=OK: rd.free_rid(target);call_deferred("_roi_failure","ROI request error %d" % error)

func _roi_callback(bytes: PackedByteArray, target: RID, format: int, start: int, frame: int) -> void:
	preview.solver.rd.free_rid(target)
	call_deferred("_roi_record",bytes,format,start,frame,Time.get_ticks_usec())

func _roi_record(bytes: PackedByteArray, format: int, start: int, frame: int, callback_us: int) -> void:
	var image_format := Image.FORMAT_RGBA8
	match format:
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT: image_format=Image.FORMAT_RGBAH
		RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: image_format=Image.FORMAT_RGBAF
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB: pass
		RenderingDevice.DATA_FORMAT_B8G8R8A8_UNORM, RenderingDevice.DATA_FORMAT_B8G8R8A8_SRGB:
			for i in range(0,bytes.size(),4):
				var red := bytes[i];bytes[i]=bytes[i+2];bytes[i+2]=red
		_: _roi_failure("unsupported viewport format %d" % format);return
	var cropped := Image.create_from_data(roi.size.x,roi.size.y,false,image_format,bytes)
	cropped.convert(Image.FORMAT_RGBA8)
	image_geometry["roi_rd_format"]=format
	roi_pending-=1
	roi_result={"start_us":start,"end_us":Time.get_ticks_usec(),"callback_us":callback_us,"frame":frame,"bytes":cropped.get_data(),"image":cropped}
	roi_results.append(roi_result)

func _roi_failure(message: String) -> void:
	_error(message)
	roi_pending-=1
	var empty := Image.create_empty(roi.size.x,roi.size.y,false,Image.FORMAT_RGBA8)
	roi_result={"start_us":Time.get_ticks_usec(),"end_us":Time.get_ticks_usec(),"frame":Engine.get_process_frames(),"bytes":empty.get_data(),"image":empty}

func _changed_bytes(a: PackedByteArray,b: PackedByteArray) -> int:
	var count := 0
	for i in a.size():
		if a[i]!=b[i]: count+=1
	return count

func _run() -> void:
	root.size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview = load("res://tests/edit_validation/edit_beach_interaction_lab.tscn").instantiate()
	preview.playing = false
	preview.hide_hud=true;preview.show_brush_indicator=false
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty():
		_error(preview.last_error); _write(); finished=true; quit(1); return
	await _ticks(15)
	while preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty(): await process_frame
	await physics_frame; await physics_frame
	preview.set_visual_time(float(preview.completed_ticks)/30.0)
	preview.brush_indicator.hide_indicator()
	var initial: Dictionary = await _snapshot("initial")
	var sand: PackedFloat32Array = initial.sand.to_float32_array()
	var rock: PackedFloat32Array = initial.rock.to_float32_array()
	var water: PackedFloat32Array = initial.water.to_float32_array()
	var screen := Vector2.ZERO
	var chosen := -1
	for z in range(32,224,4):
		for x in range(32,224,4):
			var index: int = z*256+x
			if sand[index]<0.1 or water[index]<0.005: continue
			var point := Vector3((x+0.5)*0.125-16,rock[index]+sand[index],(z+0.5)*0.125-16)
			var projected: Vector2 = preview.get_viewport().get_camera_3d().unproject_position(point)
			if not preview.get_viewport().get_visible_rect().has_point(projected): continue
			var hit: Dictionary = preview.pick(projected)
			if hit.is_empty() or not preview._pick_current(hit): continue
			if Vector2(hit.position.x,hit.position.z).distance_to(Vector2(point.x,point.z))>0.001: continue
			screen=projected; chosen=index; break
		if chosen>=0: break
	if chosen<0:
		_error("no visible current wet sand point"); _write(); await preview.shutdown(); finished=true; quit(1); return

	preview.domain.tool_inventory_m3=0.2
	Input.use_accumulated_input=false
	await RenderingServer.frame_post_draw
	var setup_image := root.get_texture().get_image()
	setup_image.save_png(output.path_join("setup_full.png"))
	var image_size := Vector2(setup_image.get_size())
	var logical_size: Vector2=preview.get_viewport().get_visible_rect().size
	var image_point: Vector2=screen*image_size/logical_size
	image_geometry={"image_size":[image_size.x,image_size.y],"logical_size":[logical_size.x,logical_size.y],"logical_point":[screen.x,screen.y],"image_point":[image_point.x,image_point.y],"input_point":str(preview.get_viewport().get_final_transform()*screen)}
	roi=Rect2i(Vector2i(image_point)-Vector2i(64,64),Vector2i(128,128)).intersection(Rect2i(Vector2i.ZERO,setup_image.get_size()))
	for policy in [1,3]:
		preview.water_policy=policy;preview.signed_speed_m_s=0.25 if policy==3 else 0.0
		for i in 12: await process_frame
		var baseline: Dictionary=await _sample_pixels()
		baseline.image.save_png(output.path_join("policy%d_before.png" % policy))
		var stable := true
		var controls := []
		for i in 3:
			var sample: Dictionary=await _sample_pixels()
			var changed := _changed_bytes(baseline.bytes,sample.bytes)
			controls.append({"changed_bytes":changed,"start_us":sample.start_us,"end_us":sample.end_us})
			stable=stable and changed==0
		_check("policy%d_no_edit_pixels_stable" % policy,stable,controls)
		if not stable: _error("unattributable pixel background");break
		var prior: int=preview.input_results.size()
		var event := InputEventMouseButton.new();event.position=preview.get_viewport().get_final_transform()*screen;event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=true
		Input.parse_input_event(event)
		if preview.input_events.is_empty() or not preview.input_events[-1].admission_error.is_empty(): _error("input not admitted");break
		roi_results.clear()
		var input_us: int=preview.input_events[-1].input_us
		var first := {}
		var observations := []
		var deadline := Time.get_ticks_msec()+5000
		while (first.is_empty() or preview.input_running) and Time.get_ticks_msec()<deadline and preview.last_error.is_empty():
			await RenderingServer.frame_post_draw
			if roi_pending<8:
				roi_pending+=1
				RenderingServer.call_on_render_thread(_copy_roi.bind(root.get_texture().get_rid(),Time.get_ticks_usec(),Engine.get_process_frames()))
			for sample in roi_results:
				var changed := _changed_bytes(baseline.bytes,sample.bytes)
				observations.append({"changed_bytes":changed,"start_us":sample.start_us,"end_us":sample.end_us,"frame":sample.frame})
				if changed>=32 and (first.is_empty() or sample.end_us<first.end_us): first=sample
			roi_results.clear()
			if observations.size()>120: break
		while roi_pending>0: await process_frame
		for sample in roi_results:
			var changed := _changed_bytes(baseline.bytes,sample.bytes)
			observations.append({"changed_bytes":changed,"start_us":sample.start_us,"end_us":sample.end_us,"frame":sample.frame})
			if changed>=32 and (first.is_empty() or sample.end_us<first.end_us): first=sample
		roi_results.clear()
		event.pressed=false;Input.parse_input_event(event)
		var observed_ms := -1.0 if first.is_empty() else float(first.end_us-input_us)/1000.0
		var applied: bool=preview.input_results.size()==prior+1 and preview.input_results[-1].result.get("status")==1
		var within: bool=not first.is_empty() and observed_ms<=100.0
		if not first.is_empty(): first.image.save_png(output.path_join("policy%d_first_observed.png" % policy))
		pixel_rows.append({"policy":policy,"input":preview.input_events[-1],"terminal":preview.input_results[-1] if applied else {},"pass":applied and within,"observation_upper_ms":observed_ms,"within_100ms_proven":within,"samples":observations,"completed_ticks":preview.completed_ticks,"pending_at_finish":roi_pending})
		_check("policy%d_pixel_observation" % policy,applied and within,pixel_rows[-1])
		var edited: Dictionary=await _snapshot("policy%d_edit" % policy)
		_check("policy%d_edit_publication_collision" % policy,await _published_exact(edited) and _chunks_exact(edited))
		await _ticks(2)
		while preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty(): await process_frame
		await physics_frame;await physics_frame
		preview.set_visual_time(float(preview.completed_ticks)/30.0)
	var final_state: Dictionary=await _snapshot("final")
	_check("final_continued_publication",await _published_exact(final_state))
	for item in checks: failed=failed or not item.pass
	failed=failed or pixel_rows.size()!=2 or not preview.last_error.is_empty()
	await preview.shutdown();_write();preview.queue_free();finished=true
	print("BEACH_PIXEL_FEEDBACK_COMPLETE pass=%s" % str(not failed));quit(1 if failed else 0)
