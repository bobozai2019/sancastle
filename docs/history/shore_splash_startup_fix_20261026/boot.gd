extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var beach=load("res://scenes/main.tscn").instantiate();root.add_child(beach);current_scene=beach
 var deadline=Time.get_ticks_msec()+90000
 while not beach.ready_for_ticks and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
 if not beach.ready_for_ticks:push_error("STARTUP_FAILED "+str(beach.last_error));quit(1);return
 var first_tick: int=beach.runtime.current.completed_tick
 while beach.runtime.current.completed_tick<first_tick+10 and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
 var passed: bool=beach.last_error.is_empty() and beach.runtime.current.completed_tick>=first_tick+10
 print("STARTUP_CHECK ",passed," splash_instances=",beach.get_node("ShoreSplash").multimesh.instance_count)
 await beach.shutdown()
 quit(0 if passed else 1)
