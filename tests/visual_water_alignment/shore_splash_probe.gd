extends "res://docs/competitor/tools/probe_material_quality.gd"

var particle_pending:=false
var particle_result: Dictionary={}

func _read_particles_render() -> void:
	var splash=scene.runtime.current.visuals.splash
	var rd: RenderingDevice=scene.runtime.current.state.rd
	var bytes:=rd.texture_get_data(splash.published.splash_position,0)
	var motion:=rd.texture_get_data(splash.published.splash_velocity,0)
	call_deferred("_particles_arrived",bytes,motion)

func _particles_arrived(bytes: PackedByteArray, motion: PackedByteArray) -> void:
	var positions:=bytes.to_float32_array();var velocities:=motion.to_float32_array()
	var alive:=0;var valid:=positions.size()==4096 and velocities.size()==4096
	var maximum_y:=-1000.0
	var points: Array[Vector3]=[]
	for value in positions:valid=valid and is_finite(value)
	for value in velocities:valid=valid and is_finite(value)
	for i in positions.size()/4:
		if positions[i*4+3]>0.0:
			alive+=1;maximum_y=maxf(maximum_y,positions[i*4+1])
			points.append(Vector3(positions[i*4],positions[i*4+1],positions[i*4+2]))
	particle_result={"alive":alive,"finite":valid,"position_sha256":_hash(bytes),"velocity_sha256":_hash(motion),"maximum_y":maximum_y}
	if not points.is_empty():
		var best:=points[0];var best_count:=0
		for candidate in points:
			var count:=0
			for point in points:
				if point.distance_squared_to(candidate)<4.0:count+=1
			if count>best_count:best_count=count;best=candidate
		particle_result.cluster_center=best;particle_result.cluster_count=best_count
	particle_pending=false

func _hash(bytes: PackedByteArray) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()

func _particles() -> Dictionary:
	particle_pending=true
	RenderingServer.call_on_render_thread(_read_particles_render)
	while particle_pending:await process_frame
	return particle_result.duplicate()

func _advance(count: int) -> void:
	for i in count:
		var error: StringName=scene.runtime.request_tick(1.0/30.0)
		if not error.is_empty():check("tick_request_"+str(i),false);return
		await _idle()

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn" if scene_key=="main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing=false;scene.generation=1001
	if "--splash-off" in OS.get_cmdline_user_args():scene.shore_splash_enabled=false
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+90000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:observations.error=String(scene.last_error);await _close();return
	await process_frame
	check("props_hold",(await scene._props_hold(true,&"user")).is_empty())
	scene.hide_hud=true
	# Capture-only input isolation: mouse focus must not move the camera or
	# draw a brush ring over the splash. Production input remains unchanged.
	scene.set_process_input(false);scene.set_process_unhandled_input(false)
	for camera_path in ["GpuPlayerCamera","GpuOverviewCamera"]:
		var capture_camera: Camera3D=scene.get_node(camera_path)
		capture_camera.set_process(false);capture_camera.set_process_input(false);capture_camera.set_process_unhandled_input(false)
	scene.get_node("BrushIndicator").layers=0
	for mesh in scene.get_node("BrushPreview").find_children("*","GeometryInstance3D",true,false):mesh.layers=0
	observations.configuration=scene.configuration.duplicate(true)
	observations.render={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"size":var_to_str(root.size),"vsync":DisplayServer.window_get_vsync_mode()}
	var material: ShaderMaterial=scene.get_node("ShoreSplash").material_override
	check("authored_pool_1024",scene.get_node("ShoreSplash").multimesh.instance_count==1024)
	check("published_binding",material.get_shader_parameter("splash_position") is Texture2DRD and material.get_shader_parameter("splash_velocity") is Texture2DRD)
	var size_control: SpinBox=root.get_node("Parameters/water/Margin/Rows/Scroll/Fields/visual_shore_splash_size/Line/Value")
	size_control.value=1.3
	check("actual_ui_size_consumed",is_equal_approx(float(material.get_shader_parameter("splash_size")),1.3))
	size_control.value=1.0
	var initial:=await _particles();check("initial_transient_empty",initial.alive==0 and initial.finite)
	observations.frames=[]
	var peak:=0;var captured_peak:=false
	var closeup: bool="--closeup" in OS.get_cmdline_user_args()
	if closeup:
		var target:=Vector3(2.86,1.15,-6.8) if scene_key=="test1_geometry" else Vector3(0.0,1.0,0.0)
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--target="):
				var numbers:=argument.trim_prefix("--target=").split(",")
				target=Vector3(float(numbers[0]),float(numbers[1]),float(numbers[2]))
		var camera: Camera3D=scene.get_viewport().get_camera_3d()
		camera.look_at_from_position(target+Vector3(1.2,2.1,3.2),target)
		await _advance(210)
	for frame in (60 if closeup else 40):
		await _advance(2 if closeup else 12)
		var sample:=await _particles()
		check("finite_"+str(frame),sample.finite and sample.alive<=1024)
		sample.tick=scene.runtime.current.completed_tick;sample.simulation_time_s=scene.runtime.current.advanced_time_s
		sample.camera_transform=var_to_str(scene.get_viewport().get_camera_3d().global_transform)
		sample.file="frame_%03d.png"%frame
		await _capture(sample.file.trim_suffix(".png"));observations.frames.append(sample)
		if sample.alive>peak:
			peak=sample.alive
			await _capture("peak_wide")
			var camera: Camera3D=scene.get_viewport().get_camera_3d()
			var original_transform:=camera.global_transform
			var target: Vector3=sample.cluster_center
			var direction: Vector3=(original_transform.origin-target).normalized()
			camera.look_at_from_position(target+direction*4.0,target)
			await _capture("peak_near")
			material.set_shader_parameter("splash_visible",false)
			await _capture("peak_near_off")
			material.set_shader_parameter("splash_visible",true)
			camera.global_transform=original_transform
			observations.peak_frame=sample.duplicate()
		if sample.alive>0 and not captured_peak:
			captured_peak=true
			await _capture("splash_on")
			var before:=await _particles()
			await create_timer(0.5).timeout
			await _capture("splash_paused")
			var after:=await _particles()
			check("pause_exact_gpu_state",before.position_sha256==after.position_sha256 and before.velocity_sha256==after.velocity_sha256)
			check("pause_exact_image",FileAccess.get_sha256(output+"/splash_on.png")==FileAccess.get_sha256(output+"/splash_paused.png"))
			var row=root.get_node("Parameters/water/Margin/Rows/Scroll/Fields/visual_shore_splash_enabled/Line/Value")
			row.button_pressed=false
			check("actual_ui_hides",material.get_shader_parameter("splash_visible")==false)
			await _capture("splash_off")
			row.button_pressed=true
			check("actual_ui_shows",material.get_shader_parameter("splash_visible")==true)
			await _capture("splash_restored")
			check("toggle_restores_exact_image",FileAccess.get_sha256(output+"/splash_on.png")==FileAccess.get_sha256(output+"/splash_restored.png"))
	observations.peak_alive=peak
	check("natural_impact_produces_splash",peak>0 if scene.shore_splash_enabled else peak==0)
	var checkpoint:=output+"/transient_checkpoint.bin"
	check("save_success",(await scene.save_gpu_checkpoint(checkpoint)).is_empty())
	check("restore_success",(await scene.restore_gpu_checkpoint(checkpoint)).is_empty())
	await process_frame
	var restored:=await _particles();check("restore_clears_transient",restored.alive==0 and restored.finite)
	check("restored_binding",material.get_shader_parameter("splash_position").texture_rd_rid==scene.runtime.current.views.textures.splash_position)
	observations.scope="Natural authored waves, completed-time GPU splash pool and real static UI, paused exact state/image, transient reset on restore and normal owner release. Particle diagnostic readback exists only in this probe; no performance claim."
	await _close()
