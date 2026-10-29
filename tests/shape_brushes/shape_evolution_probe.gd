extends "res://tests/shape_brushes/material_edit_probe.gd"

var evolution_mode:="castle_intact"
var evolution_samples:=[]
var evolution_phases:={}
func evolution_capture(tick:int) -> void:
	await snapshot("evolution_tick_%04d"%tick);evolution_samples.append(raw_index[-1])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("evolution_tick_%04d.png"%tick))

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):evolution_mode=arg.trim_prefix("--mode=")
	if evolution_mode not in ["castle_intact","castle_damaged","wet_wave"]:_check("evolution_mode",false);_finish();quit(1);return
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/evolution_lab.tscn").instantiate();preview.brush_fixture="submerged" if evolution_mode=="wet_wave" else "dry_flat";preview.dry_elevated=evolution_mode!="wet_wave";preview.playing=false;preview.visual_time_s=0.0;preview.sand_cohesion_yield_height_m=0.0;preview.hide_hud=true;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("evolution_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	preview.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed=false
	preview.player_camera.position=Vector3(-5,4,6);preview.player_camera.look_at(Vector3.ZERO,Vector3.UP)
	await snapshot("unformed");evolution_phases.initial=raw_index[-1]
	_check("evolution_castle_begin",(await preview.begin_shape_stroke(4000)).is_empty())
	var castle:=BrushProtocol.make_command(&"castle_v1",{"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0},Vector2.ZERO,Vector2.ZERO,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,4000,0,0,preview.shape_baseline_token);castle.material_profile_id=&"molded_v1"
	_check("evolution_castle_applied",(await submit(castle)).get("status")==1);await preview.end_shape_stroke()
	await snapshot("formed");evolution_phases.formed=raw_index[-1]
	if evolution_mode!="castle_intact":
		for pen in 3 if evolution_mode=="castle_damaged" else 1:
			var stroke:=4001+pen
			_check("evolution_cut_begin",(await preview.begin_shape_stroke(stroke)).is_empty())
			for i in 2:
				var command:=BrushProtocol.make_command(&"shovel_v1",{"trench_width_m":1.0,"depth_m":0.3,"shoulder_width_m":1.0},Vector2(-2+2*i,1.25),Vector2(2*i,1.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,stroke,i,0,preview.shape_baseline_token)
				_check("evolution_cut_applied",(await submit(command)).get("status")==1)
			await preview.end_shape_stroke()
	if evolution_mode=="wet_wave":
		preview.manual_wave_amplitude_m=0.1;preview._on_trigger_wave_pressed();_check("evolution_wave_admitted",preview.wave_requests.size()==1,preview.wave_requests.duplicate(true))
	var initial_meta:=metadata()
	await evolution_capture(0)
	for tick in range(1,901):
		await _ticks(1)
		if not preview.last_error.is_empty():break
		if evolution_mode=="wet_wave":preview.visual_time_s=preview.completed_ticks*preview.SIM_DELTA
		if tick%150==0:await evolution_capture(tick);print("SHAPE_EVOLUTION_PROGRESS ",evolution_mode," ",tick)
	_check("evolution_30_sim_seconds",preview.completed_ticks==900 and preview.last_error.is_empty(),preview.last_error)
	_check("evolution_no_implicit_sand_source",preview.domain.sand_source_m3==initial_meta.source and preview.domain.sand_sink_m3==initial_meta.sink and preview.domain.tool_inventory_m3==initial_meta.inventory)
	var file:=FileAccess.open(output.path_join("evolution.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"mode":evolution_mode,"phases":evolution_phases,"samples":evolution_samples,"metadata":metadata(),"initial_metadata":initial_meta,"tick_duration_rational":[1,30],"tick_duration_float64_hex":PackedFloat64Array([preview.SIM_DELTA]).to_byte_array().hex_encode(),"completed_ticks":preview.completed_ticks,"wave_requests":preview.wave_requests,"profile_sha256":preview.requested_render_profile_sha256,"source_signature":preview.source_signature,"presentation":"tick/30" if evolution_mode=="wet_wave" else "frozen0","scope":"Full coupled solver, final template and actual edits, fixed camera; functional retention/damage/wave observation only; no performance or ordinary strict verdict"},"\t"));file.close()
	var water=preview.shape_gpu.water_transaction;await preview.shutdown();_check("evolution_release",preview.gpu_release_done and water.rd==null and water.owned.is_empty());preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
