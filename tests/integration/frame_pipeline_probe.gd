extends SceneTree

const Main=preload("res://scenes/main.tscn")
const BrushProtocol=preload("res://scripts/simulation/brushes/brush_protocol.gd")
var preview
var output:=""
var checks:=[]
var failed:=false
var reads: Dictionary={}
var read_remaining:=0
var metrics:=[]
var frames:=[]
var collecting:=false
var batch_limit:=2

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--batch-limit="):batch_limit=clampi(arg.trim_prefix("--batch-limit=").to_int(),1,64)
	call_deferred("_run")

func check(name: String, pass_value: bool) -> void:
	checks.append({"name":name,"pass":pass_value});failed=failed or not pass_value
	print("FRAME_PIPELINE ",name," ",pass_value)

func _process(delta: float) -> bool:
	if collecting:frames.append(delta*1000.0)
	return false

func idle() -> bool:
	var deadline:=Time.get_ticks_msec()+25000
	while Time.get_ticks_msec()<deadline and preview.last_error.is_empty():
		if not preview.busy and not preview.input_running and not preview.input_scheduler.pumping and preview.command_queue.pending.is_empty() and not preview.collision_proxy.staging_texture.is_valid() and preview.collision_proxy.pending_revisions.is_empty() and not preview.collision_proxy.has_prepare_in_flight():return true
		await process_frame
	return false

func command(index: int) -> Dictionary:
	var point:=Vector3(-2.0+float(index%3)*0.07,0.0,float(index%2)*0.05)
	return {"domain_id":preview.domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":maxi(preview.input_serial,preview.command_queue.last_command_id)+1,"kind":&"remove_sand" if index%2==0 else &"place_sand","shape":&"circle","transform":{"position_m":point,"end_position_m":point},"radius_m":0.3,"strength":1.0,"amount_m3":0.015,"seed":101}

func snapshot() -> Dictionary:
	reads={};read_remaining=14
	RenderingServer.call_on_render_thread(_read_render)
	while read_remaining>0:await process_frame
	return reads.duplicate(true)

func _read_render() -> void:
	for field in ["sand","water","sediment","momentum_x","momentum_z","mold_support","compaction"]:
		for slot in 2:
			preview.solver.rd.texture_get_data_async(preview.solver.textures[field][slot],0,_read_ready.bind(field+str(slot)))

func _read_ready(bytes: PackedByteArray, key: String) -> void:
	call_deferred("_store_read",bytes,key)

func _store_read(bytes: PackedByteArray, key: String) -> void:
	reads[key]=bytes;read_remaining-=1

func scene(pipeline: bool) -> bool:
	preview=Main.instantiate();preview.playing=false;preview.edit_frame_pipeline_enabled=pipeline;preview.edit_frame_batch_limit=batch_limit
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+45000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("ready_"+str(pipeline),preview.ready_for_ticks and preview.last_error.is_empty())
	return not failed and await idle()

func shape() -> void:
	check("shape_begin",(await preview.begin_shape_stroke(801)).is_empty())
	var cmd:=BrushProtocol.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-2,-0.25),Vector2(-2,0.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,801,0,preview.completed_ticks,preview.shape_baseline_token)
	cmd.material_profile_id=&"molded_v1"
	check("shape_admission",preview.input_scheduler.submit(cmd).is_empty())
	preview.input_running=true;preview.call_deferred("_drain_input")
	check("shape_drain",await idle())
	check("shape_terminal",preview.input_scheduler.terminal[-1].result.get("status")==1)
	check("shape_end",(await preview.end_shape_stroke()).is_empty())

func edits(count: int, continuous: bool=false) -> void:
	var baseline: int=preview.input_scheduler.terminal.size()
	var started:=Time.get_ticks_usec();frames=[];collecting=true
	for index in count:
		check("admit_"+str(index),preview.input_scheduler.submit(command(index)).is_empty())
		if continuous and index==3:
			preview.input_running=true;preview.call_deferred("_drain_input")
			await process_frame;await process_frame
			check("capture_while_gpu_busy",preview.gpu_busy)
	if not preview.input_running:preview.input_running=true;preview.call_deferred("_drain_input")
	check("edits_drain",await idle());collecting=false
	var elapsed:=Time.get_ticks_usec()-started
	var rows: Array=preview.input_scheduler.terminal.slice(baseline)
	check("all_ordered_receipts",rows.size()==count and rows.all(func(row):return row.result.get("status")==1))
	metrics.append({"pipeline":preview.edit_frame_pipeline_enabled,"continuous":continuous,"commands":count,"elapsed_ms":float(elapsed)/1000.0,"frame_ms":frames.duplicate(),"batches":preview.frame_pipeline.history.duplicate(true) if preview.frame_pipeline!=null else [],"source":preview.domain.sand_source_m3,"sink":preview.domain.sand_sink_m3})

func close_scene() -> void:
	await preview.shutdown();check("release",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame

func rejection() -> void:
	var before: Dictionary=await snapshot()
	var water: PackedFloat32Array=before.water0.to_float32_array()
	var point:=Vector3.ZERO;var found:=false
	for z in range(8,248):
		for x in range(8,248):
			if water[z*256+x]>0.05:point=Vector3((x+0.5)*0.125-16,0,(z+0.5)*0.125-16);found=true;break
		if found:break
	check("wet_rejection_fixture",found)
	var start: int=preview.input_scheduler.terminal.size()
	RenderingServer.call_on_render_thread(_inject_water_failure)
	for index in 2:
		var cmd:=command(index);cmd.kind=&"place_sand";cmd.transform.position_m=point;cmd.transform.end_position_m=point
		check("reject_admit_"+str(index),preview.input_scheduler.submit(cmd).is_empty())
	preview.input_running=true;preview.call_deferred("_drain_input")
	check("reject_drain",await idle())
	var rows: Array=preview.input_scheduler.terminal.slice(start)
	check("rejected_then_unexecuted",rows.size()==2 and rows[0].result.get("status")==2 and rows[1].result.get("cancelled",false))
	var after: Dictionary=await snapshot()
	for field in before:check("reject_unchanged_"+field,before[field]==after[field])
	check("reservations_released",preview.input_scheduler.reserved_total()==0.0 and preview.input_scheduler.reservations.is_empty())

func _inject_water_failure() -> void:
	preview.solver.inject_water_loss_once=true

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var reference: Dictionary={}
	for enabled in [false,true]:
		if not await scene(enabled):break
		await shape()
		await edits(12)
		var fields: Dictionary=await snapshot()
		if not enabled:reference=fields
		else:
			for field in reference:check("exact_"+field,reference[field]==fields[field])
			check("batching_exercised",preview.frame_pipeline.history.size()==ceili(12.0/batch_limit) and preview.frame_pipeline.history[0].count==batch_limit)
			check("one_upload_and_readback_per_batch",preview.frame_pipeline.history.all(func(row):return row.metrics.command_upload_calls==1 and row.metrics.receipt_readback_calls==1 and row.metrics.cpu_ack_inside_batch==0))
			await edits(12,true)
			await rejection()
			var drop: Dictionary=await preview.drop_gravel(Vector2(1,1),2)
			check("gravel_preserved",drop.get("ok",false) and drop.active_count==514)
			preview.playing=true
			await create_timer(0.7).timeout;preview.playing=false
			check("simulation_continues",await idle() and preview.completed_ticks>0)
			check("no_collision_errors",preview.collision_proxy.invalid_readbacks==0 and preview.last_error.is_empty())
		await close_scene()
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"metrics":metrics,"scope":"Visible main 1080p short paired run, not formal performance gate; no checkpoints or raw fields saved"},"\t"));file.close()
	quit(1 if failed else 0)
