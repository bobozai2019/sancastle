extends "res://tests/floating_props/lifecycle_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene);props=scene.floating_props
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("fault_main_ready",not scene._booting and props.active and props.last_error.is_empty())
	if scene._booting:await _close();return
	await _run_for(0.2)
	var path:=output.get_base_dir()+"/before_fault.sandue"
	check("fault_baseline_saved",(await scene.save_gpu_checkpoint(path)).is_empty())
	var old_generation: int=props.generation;var old_owner: int=props.owner_token
	props.last_error=&"speed_limit";props.holds[&"fault"]=true;props._hold_all()
	var before_time: float=scene.runtime.current.advanced_time_s
	scene.playing=true;deadline=Time.get_ticks_msec()+20000
	while scene.runtime.current.advanced_time_s<before_time+0.2 and Time.get_ticks_msec()<deadline:await process_frame
	scene.playing=false
	check("fault_does_not_stop_water",scene.runtime.current.advanced_time_s>=before_time+0.2 and props.last_error==&"speed_limit")
	var fault_save:=output.get_base_dir()+"/during_fault.sandue"
	var error: StringName=await scene.save_gpu_checkpoint(fault_save)
	check("fault_still_allows_core_save",error.is_empty() and props.last_error==&"speed_limit" and not props.holds.has(&"save"))
	error=await scene.restore_gpu_checkpoint(path)
	check("fault_restore_reinitializes_consumer",error.is_empty() and props.generation>old_generation and props.owner_token==old_owner+1 and props.last_error.is_empty() and not props.holds.has(&"fault") and props.admitted_time_s==0.0)
	await process_frame
	var generation: int=scene.runtime.generation();var current=scene.runtime.current;var operation: int=props.operation_id
	props.operation_id=9223372036854775805
	check("save_identity_preflight",await scene.save_gpu_checkpoint(output.get_base_dir()+"/must_not_exist.sandue")==&"identity_exhausted")
	check("restore_identity_preflight",await scene.restore_gpu_checkpoint(path)==&"identity_exhausted")
	check("preflight_preserves_authority",scene.runtime.generation()==generation and scene.runtime.current==current and not FileAccess.file_exists(output.get_base_dir()+"/must_not_exist.sandue"))
	props.operation_id=operation
	var radius: float=props.registry[0].body.footprint_radius_m
	props.registry[0].body.footprint_radius_m=0.001
	check("collider_outside_footprint_rejected",props._validate(props.registry,props.layout)==&"invalid_registry")
	props.registry[0].body.footprint_radius_m=radius
	check("plank_full_orientation_budget",props._orientation_error(props.profiles[2],Basis.IDENTITY,Basis(Vector3(1,0,1).normalized(),0.36))>props.profiles[2].max_pose_angle_rad)
	check("line_axial_roll_does_not_move_sampling_cloud",props._orientation_error(props.profiles[1],Basis.IDENTITY,Basis(Vector3.RIGHT,1.0))<1e-6)
	observations.sources=scene.configuration.sources.duplicate(true)
	await _close()

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"G6 latched prop fault preserves water production and core save/restore; identity exhaustion rejects before authority commit; collider envelope and sampling orientation guards."},"\t"));quit(1 if failed else 0)
