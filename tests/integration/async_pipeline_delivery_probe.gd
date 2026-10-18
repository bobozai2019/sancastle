extends "res://tests/integration/async_pipeline_restore_probe.gd"

const ENTRIES={"main":"res://scenes/main.tscn","test1_capture":"res://scenes/playable/test1_capture.tscn","test1_backwash":"res://scenes/playable/test1_backwash.tscn"}
var cycles:=[]
var active_operation_ms:=0
var pool_baselines:={}
var entry_evidence:={}
var screenshots:=[]
var requested_cycles:=10
var block_ms:=18000
var boundary_failure:={}

func delivery_collision_matches(value: Dictionary) -> bool:
	var bed: PackedFloat32Array=value.native.fields.rock.to_float32_array()
	var sand: PackedFloat32Array=value.native.fields.sand.to_float32_array()
	for i in bed.size():bed[i]+=sand[i]
	var collision=preview.async_controller.collision
	if collision.applied_state_seq.size()!=64:return false
	for chunk in 64:
		# Unchanged chunks may retain older labels. Exact sampled heights, not a
		# false global watermark, establish convergence after pending work drains.
		if collision.applied_state_seq[chunk]>value.state_seq or collision.applied_sim_tick[chunk]>value.sim_tick:return false
		var data: PackedFloat32Array=preview.collision_proxy.shapes[chunk].shape.map_data
		for z in 33:
			for x in 33:
				if data[z*33+x]!=bed[mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)]:return false
	return true

func pool_counts() -> Dictionary:
	var ctl=preview.async_controller
	return {"batch_capacity":ctl.slots.slots.size(),"transport_capacity":preview.solver.async_transport.resources.size(),"height_capacity":ctl.collision.gpu_slots.size(),"active_batches":ctl.slots.active_count(),"records":ctl.records.size(),"active_heights":ctl.collision.active_count(),"pending_heights":ctl.collision.pending.size(),"shadow_jobs":preview.async_shadow_jobs.size(),"capture_jobs":preview.async_capture_owners.size(),"water_rids":ctl.water.owned.size(),"editor_resources":preview.solver.async_resources.size(),"shape_rids":preview.shape_gpu.owned.size(),"preview_rids":preview.preview_query.owned.size(),"gravel_sets":preview.gravel_field.uniform_sets.size()}

func check_pools(label: String) -> void:
	var counts:=pool_counts()
	check(label+"_capacities",counts.batch_capacity==3 and counts.transport_capacity==3 and counts.height_capacity==2 and counts.editor_resources==3)
	check(label+"_quiescent",counts.active_batches==0 and counts.records==0 and counts.active_heights==0 and counts.pending_heights==0 and counts.shadow_jobs==0 and counts.capture_jobs==0)
	if not pool_baselines.has(preview.scene_key):pool_baselines[preview.scene_key]=counts.duplicate()
	check(label+"_resource_baseline",counts==pool_baselines[preview.scene_key])

func ordinary_input(serial: int) -> StringName:
	var wet:=serial%4>=2
	var point:=Vector3(-8 if wet else -2,0,-1.0+float(serial%5)*0.4)
	var value:=command(serial,point,serial%2==0)
	value.amount_m3=0.01
	if serial%3==0:
		value.shape=&"swept_segment"
		value.transform.end_position_m=point+Vector3(0.6,0,0.2)
	return preview.input_scheduler.submit(value)

func controlled_tool(index: int) -> void:
	var mode:=index%8
	if mode in [0,1,2]:
		var name: StringName=[&"wall_v1",&"castle_v1",&"shovel_v1"][mode]
		var params: Dictionary=[{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},{"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0},{"trench_width_m":0.5,"depth_m":0.05,"shoulder_width_m":0.5}][mode]
		var start:=Vector2(-3,-0.25)
		var finish:=start if mode==1 else Vector2(-3,0.25)
		var stock: float=preview.domain.tool_inventory_m3
		var mass: float=await total_sand() if mode==2 else 0.0
		check("cycle_%d_%s_begin"%[index,name],(await preview.begin_shape_stroke(2001+index)).is_empty())
		var value:=Brush.make_command(name,params,start,finish,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,2001+index,0,preview.completed_ticks,preview.shape_baseline_token)
		if mode!=2:value.material_profile_id=&"molded_v1"
		check("cycle_%d_%s_admit"%[index,name],preview.input_scheduler.submit(value).is_empty())
		preview.input_running=true;preview.call_deferred("_drain_input")
		check("cycle_%d_%s_settles"%[index,name],await idle() and preview.input_scheduler.terminal[-1].result.get("status")==1)
		check("cycle_%d_%s_end"%[index,name],(await preview.end_shape_stroke()).is_empty())
		if mode==2:check("cycle_%d_shovel_conserves"%index,absf((await total_sand())-mass)<0.00001 and preview.domain.tool_inventory_m3==stock)
	elif mode==3:
		var value:=command(4000+index,Vector3(-8,0,0));value.sand_destination="suspended_v1"
		var result: Dictionary=await preview.apply_gpu_command(value)
		check("cycle_%d_suspended_receipt"%index,result.get("status")==1 and not preview.async_legacy_running)
	elif mode==4:
		var before: int=preview.gravel_field.active_count
		check("cycle_%d_gravel"%index,(await preview.drop_gravel(Vector2(1,1),2)).get("active_count")==before+2)
	elif mode in [5,6]:
		var value:=command(4100+index,Vector3(-3,0,0));value.kind=&"compact" if mode==5 else &"smooth";value.strength=0.2
		var result: Dictionary=await preview.apply_legacy_command(value)
		check("cycle_%d_cpu_tool"%index,result.get("results",[]).size()==1 and preview.last_error.is_empty())
	else:
		preview.playing=true
		var result: Dictionary=await preview.apply_gpu_command(command(4200+index))
		check("cycle_%d_public_realtime"%index,result.get("gpu_complete",false) and preview.playing)
		preview.playing=false
	check("cycle_%d_tool_returns"%index,await idle() and not preview.async_controller.legacy and not preview.async_controller.transitioning and preview.last_error.is_empty())

func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var data:=root.get_texture().get_image()
	var path:=output.get_basename()+"_"+label+".png"
	check("screen_"+label,not data.is_empty() and data.save_png(path)==OK)
	screenshots.append({"path":path,"sha256":FileAccess.get_sha256(path),"scene":preview.scene_key,"generation":preview.generation,"state_seq":preview.async_controller.state_seq,"tick":preview.completed_ticks,"width":data.get_width(),"height":data.get_height()})

func mixed_block(index: int) -> Dictionary:
	var start:=Time.get_ticks_msec()
	var before_tick: int=preview.completed_ticks
	var before_time: float=preview.async_controller.actual_time
	var accepted:=0;var rejected:=0;var serial:=0;var next_input:=start
	preview.playing=true
	var wave_id: int=preview.wave_highwater_id
	preview._on_trigger_wave_pressed()
	check("cycle_%d_manual_wave"%index,preview.wave_highwater_id>wave_id)
	while Time.get_ticks_msec()<start+14000 and preview.last_error.is_empty():
		if Time.get_ticks_msec()>=next_input:
			for i in 2:
				var error:=ordinary_input(index*10000+serial);serial+=1
				if error.is_empty():accepted+=1
				elif error==&"queue_full":rejected+=1
				else:check("cycle_%d_unexpected_admission_%s"%[index,error],false)
			next_input=Time.get_ticks_msec()+500
		await process_frame
	preview.playing=false
	check("cycle_%d_realtime_drains"%index,await idle())
	check("cycle_%d_real_water_progress"%index,preview.completed_ticks>before_tick and preview.async_controller.actual_time>before_time and accepted>0)
	var paused_time: float=preview.async_controller.actual_time
	await controlled_tool(index)
	if index%8!=7:check("cycle_%d_controlled_pause_clock"%index,preview.async_controller.actual_time==paused_time)
	# The public-API case intentionally resumes real time; establish its new
	# completed pause boundary before checking subsequent paused edits.
	paused_time=preview.async_controller.actual_time
	while Time.get_ticks_msec()<start+block_ms and preview.last_error.is_empty():
		var error:=ordinary_input(index*10000+serial);serial+=1
		check("cycle_%d_paused_input_%d"%[index,serial],error.is_empty())
		check("cycle_%d_paused_drain_%d"%[index,serial],await idle())
		var until:=mini(start+block_ms,Time.get_ticks_msec()+500)
		while Time.get_ticks_msec()<until:await process_frame
	check("cycle_%d_paused_clock"%index,preview.async_controller.actual_time==paused_time and (await read("clock")).decode_float(0)==paused_time)
	var elapsed:=Time.get_ticks_msec()-start
	active_operation_ms+=elapsed
	return {"scene":preview.scene_key,"generation":preview.generation,"start_tick":before_tick,"end_tick":preview.completed_ticks,"active_operation_ms":elapsed,"accepted_realtime":accepted,"capacity_rejected":rejected,"window_visible":root.visible and DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_MINIMIZED,"pools":pool_counts()}

func switch_to(service, key: String) -> bool:
	check("delivery_switch_request_"+key,service.request_switch(key))
	var end:=Time.get_ticks_msec()+120000
	while service.busy and Time.get_ticks_msec()<end:await process_frame
	check("delivery_switch_result_"+key,not service.busy and service.last_error.is_empty())
	if service.busy or not service.last_error.is_empty():return false
	preview=service.active_scene
	check("delivery_switched_default_"+key,preview.async_pipeline_enabled and preview.ready_for_ticks and preview.last_error.is_empty())
	return preview.ready_for_ticks

func _run() -> void:
	for key in ENTRIES:
		var entry=load(ENTRIES[key]).instantiate()
		check("saved_default_"+key,entry.async_pipeline_enabled)
		entry.free()
	preview=load(scene_path).instantiate()
	check("delivery_no_forced_mode",preview.async_pipeline_enabled)
	preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("delivery_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	check("delivery_visible_backend",DisplayServer.get_name()!="headless" and root.visible and DisplayServer.window_get_size().x>0)
	var service=get_root().get_node("BeachScenes")
	service.attach(preview);current_scene=preview
	service.session_directory=output.get_basename()+"_sessions";DirAccess.make_dir_recursive_absolute(service.session_directory)
	if preview.ready_for_ticks:
		await ui_and_capacity()
		for index in requested_cycles:
			if failed or not preview.last_error.is_empty():break
			entry_evidence[preview.scene_key]={"configuration":preview.source_signature.duplicate(true),"loaded_scripts":loaded_code(),"effective_profile":preview.effective_render_profile.duplicate(true),"effective_profile_sha256":preview.effective_render_profile_sha256,"water_shader":preview.water_material.shader.resource_path,"terrain_shader":preview.terrain_material.shader.resource_path}
			var row:=await mixed_block(index)
			check("cycle_%d_visible_window"%index,row.window_visible)
			check_pools("cycle_%d_before_save"%index)
			var baseline: Dictionary=await preview.capture_async_checkpoint_data()
			check("cycle_%d_capture"%index,baseline.error.is_empty())
			if not baseline.error.is_empty():
				boundary_failure={"cycle":index,"scene":preview.scene_key,"error":String(baseline.error),"generation":preview.generation,"tick":preview.completed_ticks,"state_seq":preview.async_controller.state_seq}
				print("DELIVERY_BOUNDARY_FAILED ",JSON.stringify(boundary_failure))
				break
			check("cycle_%d_actual_collision"%index,delivery_collision_matches(baseline.checkpoint))
			var path:=output.get_basename()+"_cycle_%02d.sandgp"%index
			check("cycle_%d_save"%index,(await preview.save_gpu_checkpoint(path)).is_empty())
			var old_solver=preview.solver;var old_controller=preview.async_controller;var epoch: int=preview.generation
			check("cycle_%d_mutation"%index,preview.input_scheduler.submit(command(9000+index)).is_empty())
			preview._start_tick();check("cycle_%d_mutation_settles"%index,await idle())
			check("cycle_%d_restore"%index,(await preview.restore_gpu_checkpoint(path)).is_empty())
			check("cycle_%d_old_restore_owner_released"%index,old_solver.rd==null and old_controller.water.rd==null and old_controller.water.owned.is_empty() and old_controller.slots.can_release())
			check("cycle_%d_fresh_generation"%index,preview.generation>epoch and preview.async_controller.slots.generation==preview.generation)
			var restored: Dictionary=await preview.capture_async_checkpoint_data()
			check("cycle_%d_restored_capture"%index,restored.error.is_empty())
			if restored.error.is_empty():same_native("cycle_%d_exact"%index,baseline.checkpoint,restored.checkpoint,true)
			check_pools("cycle_%d_after_restore"%index)
			if index in [0,4,9]:await screenshot("cycle_%02d"%index)
			row.checkpoint={"path":path,"sha256":FileAccess.get_sha256(path),"state_seq":baseline.checkpoint.state_seq,"tick":baseline.checkpoint.sim_tick}
			old_solver=preview.solver;old_controller=preview.async_controller
			var old_guard=preview.async_terminal
			var next_key: String=["test1_capture","test1_backwash","main"][index%3]
			if not await switch_to(service,next_key):break
			check("cycle_%d_switch_owner_released"%index,old_solver.rd==null and old_controller.water.rd==null and old_controller.water.owned.is_empty() and old_controller.slots.can_release() and old_guard.rd==null)
			check("cycle_%d_switch_pool_idle"%index,await idle())
			check_pools("cycle_%d_after_switch"%index)
			row.next_scene=preview.scene_key;row.release=service.release_records[-1].duplicate();cycles.append(row)
			print("DELIVERY_CYCLE ",index+1," active_ms=",active_operation_ms," scene=",preview.scene_key)
	check("delivery_ten_complete_cycles",cycles.size()>=10 and cycles.all(func(row):return row.release.gpu_released and row.release.node_freed))
	check("delivery_three_entry_workflows",entry_evidence.size()==3)
	check("delivery_three_minutes_active_operations",active_operation_ms>=180000)
	check("delivery_no_runtime_failure",preview.last_error.is_empty())
	var final_config: Dictionary=preview.source_signature.duplicate(true)
	await preview.shutdown()
	check("delivery_final_release",preview.gpu_release_done and preview.solver.rd==null and preview.async_controller.water.rd==null and preview.async_terminal.rd==null and preview.async_shadow_jobs.is_empty())
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("delivery_no_engine_errors",not log_text.contains("SCRIPT ERROR:") and not log_text.contains("\nERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":{"configuration":final_config,"entries":entry_evidence,"cycles":cycles,"boundary_failure":boundary_failure,"active_operation_ms":active_operation_ms,"pool_baselines":pool_baselines,"screenshots":screenshots,"scene_releases":service.release_records,"engine":Engine.get_version_info(),"driver":RenderingServer.get_current_rendering_driver_name(),"adapter":RenderingServer.get_video_adapter_name(),"window":DisplayServer.window_get_size(),"performance_gate":false}},"\t"));file.close()
	quit(1 if failed else 0)
