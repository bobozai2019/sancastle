extends "res://tests/floating_props/lifecycle_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene)
	props=scene.get_node("FloatingProps/Service")
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("baseline_formal_ready",scene.ready_for_ticks and props.last_error.is_empty())
	await _wait_paused()
	var save_error: StringName=await scene.save_gpu_checkpoint(output.get_base_dir()+"/baseline.sandue")
	observations.save_error=save_error;print("BASELINE_SAVE ",save_error," output=",output)
	check("baseline_saved",save_error.is_empty())
	observations.configuration=scene.configuration.duplicate(true)
	await _close()
