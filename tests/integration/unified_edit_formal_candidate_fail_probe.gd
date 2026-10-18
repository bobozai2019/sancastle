extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
var restore_done:=false
var restore_error: StringName=&""

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(Routes.FORMAL[scene_key]).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<180000:await process_frame
	observations.startup_ms=Time.get_ticks_msec()-start
	check("formal_candidate_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	var path:=output+"/baseline.sandue"
	check("formal_baseline_save",(await scene.save_gpu_checkpoint(path)).is_empty());await process_frame
	check("formal_edit_before_failed_restore",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish();await _idle()
	var old=scene.runtime.current
	start=Time.get_ticks_msec()
	while old.heights.active_count()!=0 or old.heights.hinted:
		if Time.get_ticks_msec()-start>15000:break
		await process_frame
	var seq: int=old.completed_state_seq
	var bindings:=_bindings();var height:=_ray()
	observations.failures=[]
	for failure in ["initialize","preflight","cancel"]:
		scene.runtime.inject_candidate_initialization_after=&"views" if failure=="initialize" else &""
		scene.runtime.inject_commit_validation_failure=failure=="preflight"
		restore_done=false;restore_error=&"";_start_restore(path)
		var staged=scene.runtime.candidate
		check(failure+"_candidate_exists_before_callback",staged!=null and not restore_done and scene._restoring)
		check(failure+"_common_input_gated",scene.runtime.submit_control("end",{}).error==&"transition_busy")
		if failure=="cancel":check("actual_candidate_cancelled",scene.runtime.cancel_restore())
		start=Time.get_ticks_msec()
		while not restore_done and Time.get_ticks_msec()-start<60000:await process_frame
		await process_frame;await process_frame
		check(failure+"_error_returned",restore_done and not restore_error.is_empty())
		check(failure+"_old_authority_and_epoch_preserved",scene.runtime.current==old and scene.generation==1001 and old.completed_state_seq==seq)
		check(failure+"_old_bindings_and_collision_preserved",_bindings()==bindings and is_equal_approx(_ray(),height))
		check(failure+"_candidate_owners_all_released",staged.released and _owned(staged)==0 and scene.runtime.candidate==null)
		check(failure+"_front_end_usable_after_failure",scene.ready_for_ticks and scene.last_error.is_empty() and scene.runtime.ready_for_input())
		observations.failures.append({"kind":failure,"generation":staged._generation,"error":String(restore_error),"released":staged.released,"owned":_owned(staged),"old_generation":scene.generation,"state_seq":old.completed_state_seq,"height":_ray()})
	scene.runtime.inject_candidate_initialization_after=&"";scene.runtime.inject_commit_validation_failure=false
	check("formal_restore_after_all_failures",(await scene.restore_gpu_checkpoint(path)).is_empty())
	start=Time.get_ticks_msec()
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-start<15000:await process_frame
	await process_frame
	check("successful_candidate_uses_fresh_epoch",scene.generation==1005 and scene.runtime.current.completed_state_seq==0 and old.released and _owned(old)==0)
	check("second_edit_after_recovery",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish();await _idle()
	check("recovered_edit_published",scene.runtime.current.completed_state_seq>0 and scene.last_error.is_empty())
	observations.events=scene.runtime.events.duplicate(true);observations.final_generation=scene.generation
	await _close()

func _start_restore(path: String) -> void:
	restore_error=await scene.restore_gpu_checkpoint(path);restore_done=true
func _owned(owner) -> int:
	var total:=0
	for member in [owner.transport,owner.state,owner.executor,owner.executor.response,owner.water,owner.coupled,owner.heights,owner.views]:total+=member.owned.size()
	return total
func _bindings() -> Array:
	var result: Array=[]
	for binding in scene.material_bindings:
		for parameter in binding.parameters:
			var texture: Texture2DRD=binding.material.get_shader_parameter(parameter)
			result.append(texture.texture_rd_rid.get_id())
	return result
func _ray() -> float:
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(3,40,0),Vector3(3,-20,0)))
	return float(hit.get("position",Vector3(0,-100,0)).y)
func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Formal candidate partial init/preflight/cancel failures preserve authority/material/collision, free all staged owners, then recover and edit"},"\t"))
	quit(1 if failed else 0)
