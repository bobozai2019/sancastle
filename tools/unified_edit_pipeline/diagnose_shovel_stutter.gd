extends "res://tools/unified_edit_pipeline/current_cost_probe.gd"

# Diagnostic only. Product source and algorithms stay unchanged.
class TimedCollision extends RefCounted:
 var original
 var records: Array=[]
 func _get(property: StringName) -> Variant:
  # Consumers also read proxy state (for example floating-prop shape bounds).
  return original.get(property)
 func get_node(path: NodePath) -> Node:return original.get_node(path)
 func _replace_chunk_shape(chunk,version,heights,generation) -> bool:
  var started:=Time.get_ticks_usec()
  var accepted: bool=original._replace_chunk_shape(chunk,version,heights,generation)
  records.append({"frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"start_us":started,"elapsed_us":Time.get_ticks_usec()-started,"chunk":chunk,"version":version,"accepted":accepted})
  return accepted

var phase:="startup"
var collision_observer
var samples: Array=[]
var milestones: Array=[]

func _run() -> void:
 DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Shovel stutter diagnostic")
 var boot:=Time.get_ticks_usec()
 scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene)
 while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_usec()-boot<180000000:await process_frame
 check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
 if not scene.ready_for_ticks:finish();return
 var data:=Presentation.read(scene.presentation_manifest);var initial:=Presentation.initial_domain(data.metadata,scene.generation)
 check("dry_target",_target(initial.domain))
 RenderingServer.call_on_render_thread(_configure_render)
 while not configured:await process_frame
 var owner=scene.runtime.current
 collision_observer=TimedCollision.new();collision_observer.original=owner.heights.proxy;owner.heights.proxy=collision_observer
 hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"configuration":scene.configuration.duplicate(true)}
 scene.panel._on_tool_pressed(&"shovel_v1")
 for i in 30:await process_frame
 process_frame.connect(_observe)
 await _exercise()
 scene.playing=false;phase="drain";await _settle()
 for i in 30:await process_frame
 process_frame.disconnect(_observe)
 while collecting:await process_frame
 observations.collision_calls=collision_observer.records.duplicate(true)
 observations.sample_calls=samples;observations.results=scene.input.terminal.duplicate(true)
 observations.cpu_records=observer.cpu_records.duplicate(true) if sampling else []
 observations.heights=owner.heights.events.duplicate(true)
 owner.heights.proxy=collision_observer.original
 await scene.shutdown();check("released",scene.unified_release_complete())
 var service=root.get_node("BeachScenes")
 if service.active_scene==scene:service.active_scene=null
 root.remove_child(scene);scene.free();scene=null
 finish()

func _observe() -> void:
 super._observe()
 var row: Dictionary=frames.back();row.phase=phase
 row.main_cpu_s=Performance.get_monitor(Performance.TIME_PROCESS)
 row.physics_cpu_s=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
 row.render_cpu_ms=RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) if sampling else -1.0
 row.render_gpu_ms=RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()) if sampling else -1.0
 row.waiting_results=scene.input.waiting.size()

func finish() -> void:
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"sampling":sampling,"runtime":hardware,"target":target_witness,"frames":frames,"gpu_samples":gpu_samples,"observations":observations,"scope":_capture_scope()},"\t"));quit(1 if failed else 0)

func _exercise() -> void:
 phase="paused_idle"
 for i in 60:await process_frame
 phase="playing_idle";scene.playing=true
 for i in 120:await process_frame
 for live in [true,false]:
  phase="playing_drag" if live else "paused_drag";scene.playing=live
  for stroke in 2:
   var point:=start_point+Vector2(stroke*0.35,-1.5)
   var before:=Time.get_ticks_usec();var admitted: Dictionary=scene.input.begin(&"shovel_v1",point,scene.panel.parameters(),0.1,scene.water_policy,scene.signed_speed_m_s)
   samples.append({"phase":phase,"action":"begin","cpu_us":Time.get_ticks_usec()-before,"at_us":before,"frame":Engine.get_process_frames(),"response":admitted})
   for step in 80:
    point=start_point+Vector2(stroke*0.35,-1.5+3.0*float(step+1)/80.0)
    var camera:=root.get_camera_3d();var screen: Vector2=camera.unproject_position(Vector3(point.x,1.0,point.y))
    before=Time.get_ticks_usec();var hit: Dictionary=scene.pick(screen);var pick_us:=Time.get_ticks_usec()-before
    before=Time.get_ticks_usec();var result: Dictionary=scene.input.move(point);var move_us:=Time.get_ticks_usec()-before
    before=Time.get_ticks_usec();scene.preview_at(point);var preview_us:=Time.get_ticks_usec()-before
    samples.append({"phase":phase,"action":"move","frame":Engine.get_process_frames(),"at_us":before,"move_cpu_us":move_us,"pick_cpu_us":pick_us,"preview_submit_cpu_us":preview_us,"pick_hit":not hit.is_empty(),"response":result})
    await process_frame
   scene.input.finish()
   # No completion/collision wait between samples or strokes.
  phase+="_tail"
  for i in 60:await process_frame

func _capture_scope() -> String:
 if observations.get("diagnostic_options",{}).get("manual",false):return "Manual main scene with live water; actual user input, F8 markers, bounded capture duration. Automated target metadata is not the user path."
 return "Automated main/default shovel, initial footprint in target metadata, paused/live phases, input adapter + preview path; timed pick does not choose path. Two strokes of 80 samples per phase, no receipt/collision wait. Not an old/new cost gate or exact user reproduction."
