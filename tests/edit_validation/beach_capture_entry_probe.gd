extends "res://tests/edit_validation/beach_edit_process_probe.gd"

var capture_armed := false

func _ticks(count: int) -> void:
	if preview.completed_ticks==17 and not capture_armed:
		capture_armed=true
		var file:=FileAccess.open(output.path_join("capture_ready.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"pid":OS.get_process_id(),"tick":preview.completed_ticks,"revision":preview.solver.state_revision,"process_frame":Engine.get_process_frames()}));file.close()
		var started:=Time.get_ticks_msec()
		while not FileAccess.file_exists(output.path_join("capture_go.json")):
			if Time.get_ticks_msec()-started>60000: preview._fail("capture coordination timeout");return
			await process_frame
		var released:=FileAccess.open(output.path_join("capture_released.json"),FileAccess.WRITE)
		released.store_string(JSON.stringify({"pid":OS.get_process_id(),"tick":preview.completed_ticks,"process_frame":Engine.get_process_frames()}));released.close()
	await super._ticks(count)
