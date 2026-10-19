extends "res://tests/integration/unified_edit_playable_probe.gd"
var pixels: Dictionary={}
var reading:=false
var snapshot_index:=0
func snapshot() -> Dictionary:
 reading=true
 RenderingServer.call_on_render_thread(_read.bind(scene.runtime.current))
 while reading:await process_frame
 for name in pixels:FileAccess.open(output+"/snapshot_%d_%s.bin"%[snapshot_index,name],FileAccess.WRITE).store_buffer(pixels[name])
 snapshot_index+=1
 return pixels.duplicate()
func _read(owner) -> void:
 var result: Dictionary={}
 for name in ["sand","water","sediment","momentum_x","momentum_z"]:
  result[name]=owner.state.rd.texture_get_data(owner.state.textures[name][0],0)
 _read_done.call_deferred(result)
func _read_done(result: Dictionary) -> void:
 pixels=result;reading=false
func _run() -> void:
 orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
 DisplayServer.window_set_size(Vector2i(1280,720))
 scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene)
 var start:=Time.get_ticks_msec()
 while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
 check("main_momentum_ready",scene.ready_for_ticks and scene.last_error.is_empty())
 if not scene.ready_for_ticks:observations.error=scene.last_error;await _close();return
 var toggle=scene.get_node("Interface/ShapeBrushPanel/Margin/Controls/ConnectedDrainage")
 scene._update_status()
 check("default_B",not toggle.button_pressed and scene.water_policy==2)
 check("production_backend",scene.runtime.get_script().resource_path=="res://scripts/simulation/unified_edit/domain_runtime.gd" and scene.runtime.current.executor.response.get_script().resource_path=="res://scripts/simulation/unified_edit/water_response.gd")
 var gain=scene.get_node("Interface/ShapeBrushPanel/Margin/Controls/MomentumGain")
 gain.value=1.0
 check("gain_control",scene.signed_speed_m_s==1.0)
 var before: Dictionary=await snapshot()
 check("B_fill_admitted",scene.input.begin(&"place_sand",Vector2(0,0),{},0.5,2,1.0).accepted)
 scene.input.finish();await _idle()
 var after: Dictionary=await snapshot()
 check("B_water_unchanged",before.water==after.water)
 check("B_sediment_unchanged",before.sediment==after.sediment)
 check("B_momentum_changed",before.momentum_x!=after.momentum_x or before.momentum_z!=after.momentum_z)
 var traces=scene.runtime.current.executor.traces.duplicate(true)
 var found:=false
 for trace in traces:
  if trace.water_stages.has("momentum_B"):
   found=true;check("B_no_connected_drainage",not trace.water_stages.has("packed") and not trace.water_stages.has("displace"))
 check("B_shader_executed",found)
 before=after
 check("B_dig_admitted",scene.input.begin(&"remove_sand",Vector2(0,0),{},0.1,2,1.0).accepted)
 scene.input.finish();await _idle()
 after=await snapshot()
 check("B_dig_water_sediment_unchanged",before.water==after.water and before.sediment==after.sediment)
 check("B_dig_momentum_changed",before.momentum_x!=after.momentum_x or before.momentum_z!=after.momentum_z)
 check("shovel_begin",scene.input.begin(&"shovel_v1",Vector2(0,-1),{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},0.1,2,1.0).accepted)
 check("shovel_sweep",scene.input.move(Vector2(0.5,-1)).accepted)
 scene.input.finish();await _idle()
 before=after;after=await snapshot()
 check("shovel_sweep_momentum",before.momentum_x!=after.momentum_x or before.momentum_z!=after.momentum_z)
 check("shovel_sweep_conserves_water_sediment",before.water==after.water and before.sediment==after.sediment)
 check("live_stroke_before_toggle",scene.input.begin(&"place_sand",Vector2(-1,0),{},0.1,2,1.0).accepted)
 toggle.button_pressed=true
 check("toggle_finishes_stroke",scene.input.gesture.is_empty())
 await _idle()
 check("original_mode_selected",scene.water_policy==3)
 check("original_fill_admitted",scene.input.begin(&"place_sand",Vector2(0,1),{},0.5,3,1.0).accepted)
 scene.input.finish();await _idle()
 found=false
 for trace in scene.runtime.current.executor.traces:
  if trace.water_stages.has("packed"):found=true
 check("original_connected_executed",found)
 toggle.button_pressed=false
 var path:=output+"/main_momentum.sandue"
 check("save",(await scene.save_gpu_checkpoint(path)).is_empty())
 toggle.button_pressed=true;gain.value=0.25
 check("restore",(await scene.restore_gpu_checkpoint(path)).is_empty())
 scene._update_status()
 check("restore_policy_and_gain",scene.water_policy==2 and not toggle.button_pressed and scene.signed_speed_m_s==1.0 and gain.value==1.0)
 check("gain_stroke_begin",scene.input.begin(&"remove_sand",Vector2(-1,0),{},0.1,2,1.0).accepted)
 gain.value=0.5
 check("gain_finishes_stroke",scene.input.gesture.is_empty() and scene.signed_speed_m_s==0.5)
 await _idle()
 var owner=scene.runtime.current
 scene.playing=true;start=Time.get_ticks_msec()
 while owner.completed_tick<30 and Time.get_ticks_msec()-start<15000:await process_frame
 scene.playing=false;await _idle()
 check("real_water_solver_advances",owner.completed_tick>=30)
 var valid:=true
 for row in scene.input.terminal:valid=valid and row.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE]
 check("no_rejected_edits",valid)
 scene.panel.get_node("Margin/Controls/Tools/Shovel").pressed.emit()
 await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
 check("screenshot",root.get_texture().get_image().save_png(output+"/main_momentum.png")==OK)
 observations.sources=scene.configuration.sources.duplicate(true)
 observations.traces=traces
 await _close()
