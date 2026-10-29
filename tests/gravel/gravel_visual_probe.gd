extends "res://tests/water_material_natural/rdc_main_smoke.gd"

const Gravel = preload("res://scripts/visual/gpu_gravel_field.gd")
var field
var wrapper := Texture2DRD.new()
var render_done := false
var target := Vector3.ZERO
var config := {}
var layer: MultiMeshInstance3D
var positions := []
var binding := {}

func _frames(count := 8) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw

func _setup_field() -> void:
	var source := RDShaderSource.new()
	source.source_compute = FileAccess.get_file_as_string("res://shaders/simulation/visual_gravel_step.glsl").replace("#[compute]", "")
	var code: RDShaderSPIRV = preview.solver.rd.shader_compile_spirv_from_source(source)
	field = Gravel.new()
	var values := PackedFloat32Array()
	values.resize(4096)
	values.fill(0.0)
	values[0] = target.x
	values[2] = target.z
	field.initialize(preview.solver,code,config,preview.generation,preview.completed_ticks,preview.solver.state_revision,{"state_0":values.to_byte_array(),"state_1":values.to_byte_array(),"current_index":0})
	field.reproject(preview.solver,preview.completed_ticks,preview.solver.state_revision,preview.generation)
	wrapper.texture_rd_rid = field.current_texture()
	field.capture_async(_field_data,1)

func _field_data(bytes: PackedByteArray, key: String, identity: Dictionary) -> void:
	if key == "state_%d" % field.current_index:
		var values := bytes.to_float32_array()
		_read_position.call_deferred(Array(values.slice(0,4)),identity)

func _read_position(values: Array, identity: Dictionary) -> void:
	target.y = values[1]
	binding = {"position":values,"version":identity,"material_shader":FileAccess.get_sha256("res://shaders/visual/gpu_gravel.gdshader"),"profile":config.duplicate(true)}
	render_done = true

func _release_field() -> void:
	if field.pending>0: _release_field.call_deferred(); return
	field.release()
	render_done = true

func _bind(point: Vector3) -> void:
	if field != null:
		wrapper.texture_rd_rid = RID()
		render_done = false
		RenderingServer.call_on_render_thread(_release_field)
		while not render_done: await process_frame
	target = point
	render_done = false
	RenderingServer.call_on_render_thread(_setup_field)
	while not render_done: await process_frame
	layer.material_override.set_shader_parameter("particle_state",wrapper)
	await _frames()

func _capture(name: String, offset: Vector3) -> void:
	preview.player_camera.position = target + offset
	preview.player_camera.look_at(target+Vector3(0,0.02,0))
	await _frames()
	var on := root.get_texture().get_image()
	on.save_png(output.path_join(name+"_on.png"))
	layer.visible = false
	await _frames()
	var off := root.get_texture().get_image()
	off.save_png(output.path_join(name+"_off.png"))
	var changed := 0
	for y in range(232,488):
		for x in range(512,768):
			var a := on.get_pixel(x,y)
			var b := off.get_pixel(x,y)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>0.02: changed += 1
	_check(name+"_color_depth",changed==0 if name=="buried_depth" else changed>100,{"changed_center_pixels":changed})
	layer.visible = true
	positions.append({"name":name,"camera":str(preview.player_camera.transform),"binding":binding.duplicate(true),"aabb":str(layer.multimesh.custom_aabb)})

func _run() -> void:
	if output.is_empty(): output = "res://test_output/gpu_gravel/visual_"+str(Time.get_unix_time_from_system()).replace(".","_")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280,720)
	preview = load("res://tests/gravel/gravel_visual_probe.tscn").instantiate()
	preview.playing = false
	preview.hide_hud = true
	root.add_child(preview)
	var deadline := Time.get_ticks_msec()+120000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("main_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks: _finish();quit(1);return
	preview.set_player_camera(true)
	preview.player_camera.set_process(false)
	preview.player_camera.fov = 55.0
	layer = preview.get_node("GravelLayer")
	# Independent per-scene material, never mutate the shared mesh's material.
	layer.material_override = load("res://assets/gravel/stone_material.tres").duplicate(true)
	layer.multimesh.visible_instance_count = 1
	config = Gravel.default_profile("main",1)
	var wet_point := Vector3.ZERO
	var dry_point := Vector3.ZERO
	var best_wet := INF
	var best_dry := INF
	for z in range(96,160):
		for x in range(64,192):
			var id: int = z*256+x
			var h: float = preview.shadow_domain.water[id]
			var xz := Vector2((x+0.5)*0.125-16,(z+0.5)*0.125-16)
			if h>0.025 and h<0.08 and absf(h-0.04)<best_wet:
				best_wet = absf(h-0.04)
				wet_point = Vector3(xz.x,0,xz.y)
			if h<=0.001 and xz.length()<best_dry:
				best_dry = xz.length()
				dry_point = Vector3(xz.x,0,xz.y)
	_check("shallow_and_dry_samples",is_finite(best_wet) and is_finite(best_dry),{"wet":str(wet_point),"dry":str(dry_point)})
	await _bind(dry_point)
	await _capture("dry_close",Vector3(0.16,0.18,0.28))
	await _capture("dry_top",Vector3(0.05,0.35,0.01))
	await _capture("dry_side",Vector3(0.2,0.08,0.24))
	await _bind(wet_point)
	await _capture("shallow",Vector3(0.16,0.24,0.28))
	preview.get_node("GpuWaterSurface").visible = false
	await _frames()
	root.get_texture().get_image().save_png(output.path_join("shallow_water_hidden.png"))
	preview.get_node("GpuWaterSurface").visible = true
	# An original unit sphere AABB is [-1,1]. Far field positions must remain visible.
	await _bind(Vector3(10,0,0))
	await _capture("far_aabb",Vector3(0.16,0.18,0.28))
	layer.position.y = -0.2
	await _capture("buried_depth",Vector3(0.16,0.18,0.28))
	layer.position.y = 0.0
	_check("reflection_layer",(layer.layers & preview.reflection_camera.cull_mask)!=0)
	_check("gpu_only_positions",field.dispatches==1 and field.readback_requests==2,{"diagnostic_readbacks":field.readback_requests,"dispatches":field.dispatches})
	FileAccess.open(output.path_join("bindings.json"),FileAccess.WRITE).store_string(JSON.stringify({"captures":positions,"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":[1280,720],"tick":preview.completed_ticks,"visual_review_required":true},"\t"))
	wrapper.texture_rd_rid = RID()
	render_done = false
	RenderingServer.call_on_render_thread(_release_field)
	while not render_done: await process_frame
	await preview.shutdown()
	_check("shutdown",preview.gpu_release_done)
	_finish()
	print("GRAVEL_VISUAL_OUTPUT ",output)
	quit()
