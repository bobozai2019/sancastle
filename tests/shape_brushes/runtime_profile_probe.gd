extends "res://tests/shape_brushes/checkpoint_v4_probe.gd"

var changed_during_capture:=false

func change_capture_profile() -> void:
	preview.sediment_coupler.capacity_per_speed_s*=1.25
	changed_during_capture=true

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/checkpoint_v4_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("profile_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	var anchor:=await snapshot("profile_anchor");var anchor_meta:=metadata()
	var names:Array=["capacity_per_speed_s","erosion_rate_per_s","deposition_rate_per_s"]
	var observations:Array=[]
	for name in names:
		for entrance in ["awaited","requested"]:
			var original:float=preview.sediment_coupler.get(name)
			var changed:float=original*1.25
			preview.sediment_coupler.set(name,changed)
			var path:String=output.path_join(name+"_"+entrance+".scp")
			var error:StringName
			if entrance=="awaited":error=await preview.save_gpu_checkpoint(path)
			else:
				error=preview.request_checkpoint_save(path)
				deadline=Time.get_ticks_msec()+30000
				while preview.brush_save_request_pending and Time.get_ticks_msec()<deadline:await process_frame
				_check(name+"_request_settled",not preview.brush_save_request_pending)
				if error.is_empty():error=preview.last_save_error
			var row:Dictionary={"parameter":name,"entrance":entrance,"original":original,"changed":changed,"error":String(error),"file_written":FileAccess.file_exists(path)}
			_check(name+"_"+entrance+"_rejects_unrepresented_profile",error==&"unsupported_checkpoint_erosion_profile" and not FileAccess.file_exists(path),row)
			if error.is_empty() and FileAccess.file_exists(path):
				var restored:StringName=await preview.restore_gpu_checkpoint(path)
				row.restore_error=String(restored);row.restored_value=preview.sediment_coupler.get(name)
				row.parameter_lost=row.restored_value!=changed
			preview.sediment_coupler.set(name,original)
			observations.append(row)
			_check(name+"_"+entrance+"_authority_atomic",exact(anchor,await snapshot(name+"_"+entrance)) and metadata()==anchor_meta)
	# Submission is observed before async texture readbacks finish. A late change
	# must also be rejected by the final pre-write audit, not only at admission.
	preview.observe_beach_capture=true
	preview.beach_capture_submitted.connect(change_capture_profile,CONNECT_ONE_SHOT)
	var late_path:String=output.path_join("changed_during_capture.scp")
	var late_error:StringName=await preview.save_gpu_checkpoint(late_path)
	_check("profile_late_change_observed",changed_during_capture)
	_check("profile_late_change_rejected_before_write",late_error==&"unsupported_checkpoint_erosion_profile" and not FileAccess.file_exists(late_path),String(late_error))
	preview.sediment_coupler.capacity_per_speed_s=SandcastleGpuSedimentCoupler.CAPACITY_PER_SPEED_S
	preview.observe_beach_capture=false
	_check("profile_late_change_atomic",exact(anchor,await snapshot("late_profile_rejected")) and metadata()==anchor_meta)
	var valid_path:String=output.path_join("default_profile.scp")
	var error:StringName=await preview.save_gpu_checkpoint(valid_path)
	_check("default_profile_save",error.is_empty(),String(error))
	if error.is_empty():
		error=await preview.restore_gpu_checkpoint(valid_path)
		_check("default_profile_restore",error.is_empty(),String(error))
		_check("default_profile_all27",exact(anchor,await snapshot("default_restored")) and metadata()==anchor_meta)
	var file:=FileAccess.open(output.path_join("runtime_profile.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"observations":observations,"raw_index":raw_index,"scope":"Three mutable erosion coefficients, both actual save entrances, rejection before file write and unchanged 27 authority fields/ledger; default actual disk save/restore."},"\t"));file.close()
	await preview.shutdown();_check("profile_released",preview.gpu_release_done);preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
