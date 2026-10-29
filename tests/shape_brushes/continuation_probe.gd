extends "res://tests/shape_brushes/checkpoint_v4_probe.gd"
var branches:={}
func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/water_lab.tscn").instantiate();preview.brush_fixture="dry_flat";preview.playing=false;preview.hide_hud=true;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("continuation_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	preview.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed=false
	_check("continuation_castle",(await stamp(&"castle_v1",{"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0},Vector2.ZERO,Vector2.ZERO,7000)).get("status")==1)
	_check("continuation_shovel",(await stamp(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2(-0.5,1.25),Vector2(0.5,1.25),7001)).get("status")==1)
	await _ticks(10)
	var anchor:=await snapshot("continuation_anchor");var anchor_meta:=metadata()
	var path:=output.path_join("continuation_v4.scp");var error:StringName=await preview.save_gpu_checkpoint(path)
	_check("continuation_actual_disk_save",error.is_empty(),String(error))
	if not error.is_empty():await preview.shutdown();_finish();quit(1);return
	for branch in ["direct","restored"]:
		if branch=="restored":
			error=await preview.restore_gpu_checkpoint(path)
			_check("continuation_restore",error.is_empty(),String(error))
			_check("continuation_anchor_all27",exact(anchor,await snapshot("continuation_restored_anchor")))
		var states:={};var prefix:={}
		for tick in range(11,311):
			await _ticks(1)
			if not preview.last_error.is_empty():break
			if tick in [11,30,150,238,300,310]:
				var state:=await snapshot(branch+"_"+str(tick));states[tick]=state;prefix[tick]=raw_index[-1]
				print("CONTINUATION_PROGRESS ",branch," ",tick)
		branches[branch]={"states":states,"index":prefix,"metadata":metadata()}
	for tick in [11,30,150,238,300,310]:
		var changed:=[]
		if branches.direct.states.has(tick) and branches.restored.states.has(tick):
			for field in branches.direct.states[tick]:
				if branches.direct.states[tick][field]!=branches.restored.states[tick][field]:changed.append(field)
		else:changed.append("missing_sample")
		_check("strict_all27_tick_"+str(tick),changed.is_empty(),changed)
	var file:=FileAccess.open(output.path_join("continuation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"anchor_metadata":anchor_meta,"direct":branches.direct.index,"restored":branches.restored.index,"direct_metadata":branches.direct.metadata,"restored_metadata":branches.restored.metadata,"source_signature":preview.source_signature,"scope":"same-build actual mixed v4 disk restore and 300-tick continuation; strict 27-field comparison"},"\t"));file.close()
	await preview.shutdown();_check("continuation_release",preview.gpu_release_done);preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
