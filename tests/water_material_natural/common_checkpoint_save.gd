extends "res://tests/water_material_natural/full_cost_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	preview.playing=false
	preview.replay_target_tick=-1
	var path:=output+"/common.sandcp"
	var error: StringName=preview.request_checkpoint_save(path)
	if not error.is_empty():_fail("common save rejected: "+String(error));return
	var deadline:=Time.get_ticks_msec()+30000
	while preview.checkpoint_capture_pending or not preview.pending_save_path.is_empty():
		await process_frame
		if Time.get_ticks_msec()>deadline or not preview.last_error.is_empty():_fail("common save timeout/error");return
	if not preview.last_save_error.is_empty() or preview.last_save_path!=path:_fail("common save failed");return
	var file:=FileAccess.open(output+"/common_save.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"path":path,"sha256":FileAccess.get_sha256(path),"tick":preview.completed_ticks,"profile":preview.render_profile_path,"profile_sha256":preview.requested_render_profile_sha256,"scope":"Ordinary save API of formal coupled; measurement setup only, not cold continuation PASS."},"\t"));file.close()
