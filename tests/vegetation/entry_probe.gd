extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
const Profile=preload("res://scripts/visual/vegetation_profile.gd")
var mode := "smoke"
var snapshots: Dictionary={}
var snapshot_serial:=0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):mode=arg.trim_prefix("--case=")
	super._initialize()

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(Routes.FORMAL[scene_key]).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-start<180000:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:observations.error=String(scene.last_error);await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	observations.configuration=scene.configuration.environment.vegetation_profile.duplicate(true)
	check("fixed_vegetation_layer",scene.has_node("VegetationLayer") and scene.vegetation_layer.get_child_count()==4 and scene.vegetation_layer.visible)
	var geometry_valid:=true
	for layer in scene.vegetation_layer.get_children():
		geometry_valid=geometry_valid and layer.multimesh.instance_count==Profile.CANDIDATES_PER_KIND and layer.multimesh.buffer.size()==Profile.CANDIDATES_PER_KIND*12 and absf(layer.multimesh.get_instance_transform(0).basis.determinant()-1.0)<0.00001
	check("authored_instance_transforms_are_nondegenerate",geometry_valid)
	check("typed_profile_valid",Profile.validate(observations.configuration).is_empty())
	var invalid: Dictionary=observations.configuration.duplicate(true);invalid.seed=16777216
	check("invalid_seed_rejected",Profile.validate(invalid)==&"invalid_vegetation_seed")
	invalid=observations.configuration.duplicate(true);invalid.species[0].flow_response=NAN
	check("nonfinite_response_rejected",not Profile.validate(invalid).is_empty())
	check("completed_state_material_bindings",_bindings_valid())
	var initial: Dictionary=await _snapshot("initial")
	var counts:=_counts(initial.roots)
	observations.initial_counts=counts
	check("each_habitat_has_plants",counts[0]>0 and counts[1]>0 and counts[2]>0 and counts[3]>0)
	check("finite_and_inside_spawn_bounds",_valid_roots(initial.roots))
	check("roots_reference_visible_bed",_roots_match_bed(initial))
	await _capture("initial")
	if mode=="behavior":await _behavior(initial)
	if mode=="cost":await _cost()
	if mode=="lifecycle":await _lifecycle()
	if mode=="soak":await _soak()
	if mode=="smoke":
		for tick in 12:
			check("tick_accepted_"+str(tick),scene.runtime.request_tick(1.0/30.0).is_empty());await _idle()
		await _capture("advanced")
		await _visual_contribution()
	await _close()

func _bindings_valid() -> bool:
	for binding in scene.material_bindings:
		for parameter in binding.parameters:
			var value: Variant=binding.material.get_shader_parameter(parameter)
			if not value is Texture2DRD or value.texture_rd_rid!=scene.runtime.current.views.textures[binding.parameters[parameter]]:return false
	return true

func _snapshot(label: String) -> Dictionary:
	snapshot_serial+=1;var serial:=snapshot_serial
	RenderingServer.call_on_render_thread(_snapshot_render.bind(scene.runtime.current,serial))
	var start:=Time.get_ticks_msec()
	while not snapshots.has(serial) and Time.get_ticks_msec()-start<20000:await process_frame
	if not snapshots.has(serial):check("snapshot_timeout_"+label,false);return {}
	var value: Dictionary=snapshots[serial];snapshots.erase(serial)
	var hashes: Dictionary={}
	for field in value:
		var bytes: PackedByteArray=value[field]
		var path: String=output+"/"+label+"_"+String(field)+".bin"
		FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes)
		hashes[field]={"path":path,"sha256":FileAccess.get_sha256(path),"bytes":bytes.size()}
	observations[label]=hashes
	return value

func _snapshot_render(owner, serial: int) -> void:
	var rd: RenderingDevice=owner.state.rd;var value: Dictionary={}
	for field in ["roots","motion"]:value[field]=rd.texture_get_data(owner.visuals.vegetation.published["vegetation_"+field],0)
	for field in ["rock","sand","water","momentum_x","momentum_z","sediment","wetness","compaction","mold_support","obstacle"]:
		var rid: RID=owner.state.textures[field] if field in ["rock","obstacle"] else owner.state.textures[field][0]
		value[field]=rd.texture_get_data(rid,0)
	call_deferred("_snapshot_received",serial,value)

func _snapshot_received(serial: int, value: Dictionary) -> void:
	snapshots[serial]=value

func _counts(bytes: PackedByteArray) -> Array:
	var counts: Array=[0,0,0,0]
	for index in Profile.CANDIDATES_PER_KIND*4:
		if bytes.decode_float(index*16+12)>0.0:counts[index/Profile.CANDIDATES_PER_KIND]+=1
	return counts

func _valid_roots(bytes: PackedByteArray) -> bool:
	if bytes.size()!=Profile.WIDTH*Profile.HEIGHT*16:return false
	var bounds: Array=observations.configuration.bounds_xz
	for index in Profile.CANDIDATES_PER_KIND*4:
		for k in 4:
			if not is_finite(bytes.decode_float(index*16+k*4)):return false
		if bytes.decode_float(index*16)<bounds[0] or bytes.decode_float(index*16)>bounds[2] or bytes.decode_float(index*16+8)<bounds[1] or bytes.decode_float(index*16+8)>bounds[3]:return false
	return true

func _bed_at(point: Vector2, fields: Dictionary) -> float:
	var p: Vector2=(point/32.0+Vector2(0.5,0.5))*256.0-Vector2(0.5,0.5)
	var low:=Vector2i(floori(p.x),floori(p.y));var f:=p-Vector2(low)
	var values: Array=[]
	for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
		var cell: Vector2i=(low+offset).clamp(Vector2i.ZERO,Vector2i(255,255))
		values.append(fields.rock.decode_float((cell.y*256+cell.x)*4)+fields.sand.decode_float((cell.y*256+cell.x)*4))
	if f.x+f.y<=1.0:return values[0]+f.x*(values[1]-values[0])+f.y*(values[2]-values[0])
	return values[3]+(1.0-f.x)*(values[2]-values[3])+(1.0-f.y)*(values[1]-values[3])

func _roots_match_bed(fields: Dictionary) -> bool:
	var raw: PackedByteArray=fields.roots
	for index in Profile.CANDIDATES_PER_KIND*4:
		if raw.decode_float(index*16+12)<=0.0:continue
		var point:=Vector2(raw.decode_float(index*16),raw.decode_float(index*16+8))
		if absf(raw.decode_float(index*16+4)-_bed_at(point,fields))>0.00001:return false
	return true

func _capture(label: String) -> void:
	var hidden: bool=scene.hide_hud;scene.hide_hud=true
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/"+label+".png")
	scene.hide_hud=hidden

func _visual_contribution() -> void:
	var hidden: bool=scene.hide_hud;scene.hide_hud=true
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var with_plants: Image=root.get_texture().get_image()
	with_plants.save_png(output+"/vegetation_on.png")
	scene.vegetation_layer.visible=false
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var without_plants: Image=root.get_texture().get_image()
	without_plants.save_png(output+"/vegetation_off.png")
	var first:=with_plants.get_data();var second:=without_plants.get_data();var changed:=0
	var stride:=4 if with_plants.get_format()==Image.FORMAT_RGBA8 else 3
	for index in range(0,mini(first.size(),second.size())-2,stride):
		if maxi(absi(int(first[index])-int(second[index])),maxi(absi(int(first[index+1])-int(second[index+1])),absi(int(first[index+2])-int(second[index+2]))))>8:changed+=1
	observations.visual_contribution={"changed_pixels_over_8":changed,"format":with_plants.get_format(),"dimensions":[with_plants.get_width(),with_plants.get_height()],"clock":scene.runtime.current.advanced_time_s}
	check("vegetation_changes_actual_visible_pixels",changed>300)
	scene.vegetation_layer.visible=true;scene.hide_hud=hidden

func _behavior(initial: Dictionary) -> void:
	# Test the optional consumer in isolation while authority is idle.
	RenderingServer.call_on_render_thread(func():scene.runtime.current.visuals.vegetation.record_edit();scene.runtime.current.visuals.vegetation.publish())
	await process_frame
	var isolated: Dictionary=await _snapshot("isolated")
	var unchanged:=true
	for field in initial:
		if field not in ["roots","motion"]:unchanged=unchanged and initial[field]==isolated[field]
	check("vegetation_does_not_write_authority",unchanged)
	var chosen:=-1;var raw: PackedByteArray=initial.roots
	for index in range(Profile.CANDIDATES_PER_KIND*2,Profile.CANDIDATES_PER_KIND*4):
		if raw.decode_float(index*16+12)>0.0:
			chosen=index;break
	check("editable_bank_plant_found",chosen>=0)
	if chosen<0:return
	var point:=Vector2(raw.decode_float(chosen*16),raw.decode_float(chosen*16+8))
	var time_before: float=scene.runtime.current.advanced_time_s
	check("dig_admitted",scene.input.begin(&"remove_sand",point,{},0.2,0,0.0).accepted);scene.input.finish();await _idle()
	var dug: Dictionary=await _snapshot("dug")
	check("dig_lowers_plant_root",dug.roots.decode_float(chosen*16+4)<raw.decode_float(chosen*16+4)-0.00001)
	check("dig_root_references_same_completed_bed",absf(dug.roots.decode_float(chosen*16+4)-_bed_at(point,dug))<0.00001)
	check("fill_admitted",scene.input.begin(&"place_sand",point,{},0.3,0,0.0).accepted);scene.input.finish();await _idle()
	var filled: Dictionary=await _snapshot("filled")
	check("fill_buries_without_lifting_root",filled.roots.decode_float(chosen*16+4)==dug.roots.decode_float(chosen*16+4) and _bed_at(point,filled)>_bed_at(point,dug)+0.00001)
	check("edit_preserves_plant_horizontal_identity",filled.roots.decode_float(chosen*16)==raw.decode_float(chosen*16) and filled.roots.decode_float(chosen*16+8)==raw.decode_float(chosen*16+8))
	check("paused_edits_do_not_advance_motion_or_clock",filled.motion==initial.motion and scene.runtime.current.advanced_time_s==time_before)
	for frame in 8:await process_frame
	var paused: Dictionary=await _snapshot("paused")
	check("pause_holds_plant_state",paused.roots==filled.roots and paused.motion==filled.motion)
	for tick in 24:
		if not scene.runtime.request_tick(1.0/30.0).is_empty():check("flow_tick_admitted_"+str(tick),false);break
		await _idle()
	var moving: Dictionary=await _snapshot("moving")
	var bend:=0.0
	for index in range(0,Profile.CANDIDATES_PER_KIND*2):
		if moving.roots.decode_float(index*16+12)>0.0:bend=maxf(bend,Vector2(moving.motion.decode_float(index*16),moving.motion.decode_float(index*16+4)).length())
	observations.max_water_plant_bend=bend
	check("flow_moves_water_plant姿态",bend>0.00001)
	check("state_stays_finite",_valid_roots(moving.roots))
	await _capture("moving")
	await _lifecycle()

func _lifecycle() -> void:
	var owner=scene.runtime.current
	var path:=output+"/vegetation.sandue"
	check("save_native_with_vegetation",(await scene.save_gpu_checkpoint(path)).is_empty())
	var before_rejection: Dictionary=await _snapshot("before_bad_restore")
	var corrupt:=FileAccess.get_file_as_bytes(path)
	if corrupt.size()<49:check("native_container_available_for_negative",false);return
	corrupt[48]^=1
	var bad_path:=output+"/vegetation_corrupt.sandue"
	FileAccess.open(bad_path,FileAccess.WRITE).store_buffer(corrupt)
	var rejected: StringName=await scene.restore_gpu_checkpoint(bad_path)
	check("corrupt_restore_rejected",not rejected.is_empty())
	var after_rejection: Dictionary=await _snapshot("after_bad_restore")
	check("failed_restore_keeps_current_vegetation",scene.runtime.current==owner and scene.generation==1001 and before_rejection.roots==after_rejection.roots and before_rejection.motion==after_rejection.motion)
	check("failed_restore_keeps_current_bindings",_bindings_valid())
	check("restore_native_with_vegetation",(await scene.restore_gpu_checkpoint(path)).is_empty())
	var start:=Time.get_ticks_msec()
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-start<45000:await process_frame
	check("old_generation_released",owner.released and scene.generation==1002)
	check("restored_materials_reference_new_generation",_bindings_valid())
	var restored: Dictionary=await _snapshot("restored")
	check("decorative_roots_regenerate_on_restored_bed",_roots_match_bed(restored))
	check("restored_state_finite",_valid_roots(restored.roots))
	await _capture("restored")

func _cost() -> void:
	# Visible complete scene. Rendering-only A/B leaves simulation paused.
	for tick in 30:scene.runtime.request_tick(1.0/30.0);await _idle()
	var measured:=RenderingServer.has_method("viewport_set_measure_render_time")
	if measured:RenderingServer.call("viewport_set_measure_render_time",root.get_viewport_rid(),true)
	var samples: Dictionary={}
	for visible in [true,false,true]:
		scene.vegetation_layer.visible=visible
		for frame in 20:await process_frame
		var data: Array=[]
		var previous_us:=Time.get_ticks_usec()
		for frame in 90:
			await process_frame
			var now_us:=Time.get_ticks_usec()
			data.append({"frame_ms":float(now_us-previous_us)/1000.0,"viewport_cpu_ms":RenderingServer.call("viewport_get_measured_render_time_cpu",root.get_viewport_rid()) if measured else -1.0,"viewport_gpu_ms":RenderingServer.call("viewport_get_measured_render_time_gpu",root.get_viewport_rid()) if measured else -1.0,"fps":Engine.get_frames_per_second(),"process_s":Performance.get_monitor(Performance.TIME_PROCESS),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
			previous_us=now_us
		samples[("on_" if visible else "off_")+str(samples.size())]=data
	observations.cost={"samples":samples,"renderer":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"viewport":root.size,"vsync":DisplayServer.window_get_vsync_mode(),"scope":"Paused complete scene, visible 1280x720 rendering A/B; not simulation throughput or GPU pass timing"}
	scene.vegetation_layer.visible=true
	await _capture("cost")

func _soak() -> void:
	var began:=Time.get_ticks_msec();var next_sample:=began;var paused:=false
	var initial_time: float=scene.runtime.current.advanced_time_s;var samples: Array=[]
	scene.playing=true
	while Time.get_ticks_msec()-began<60000 and scene.last_error.is_empty():
		await process_frame
		var now:=Time.get_ticks_msec()
		if now>=next_sample:
			samples.append({"elapsed_ms":now-began,"tick":scene.runtime.current.completed_tick,"time_s":scene.runtime.current.advanced_time_s,"pending":scene.runtime.current.pending_count(),"active":scene.runtime.current.active_count(),"fps":Engine.get_frames_per_second(),"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),"texture_memory":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)})
			next_sample=now+1000
		if not paused and now-began>=30000:
			paused=true;scene.playing=false;await _idle()
			var before: Dictionary=await _snapshot("soak_pause_before")
			var stopped_time: float=scene.runtime.current.advanced_time_s
			await create_timer(0.3).timeout
			var after: Dictionary=await _snapshot("soak_pause_after")
			check("continuous_run_pause_holds_vegetation",before.roots==after.roots and before.motion==after.motion and stopped_time==scene.runtime.current.advanced_time_s)
			await _capture("soak_midpoint");scene.playing=true
	scene.playing=false;await _idle()
	var final: Dictionary=await _snapshot("soak_final")
	var finite:=_valid_roots(final.roots)
	for number in final.motion.to_float32_array():finite=finite and is_finite(number)
	observations.soak={"elapsed_ms":Time.get_ticks_msec()-began,"samples":samples,"water_time_advanced_s":scene.runtime.current.advanced_time_s-initial_time,"water_error":String(scene.last_error),"props_error":String(scene.floating_props.last_error) if scene.floating_props!=null else ""}
	check("continuous_run_has_no_domain_fault",scene.last_error.is_empty() and scene.runtime.current.fault_reason().is_empty())
	check("continuous_run_advances_water",scene.runtime.current.advanced_time_s>initial_time+1.0)
	check("continuous_run_vegetation_stays_finite",finite)
	await _capture("soak_final")
