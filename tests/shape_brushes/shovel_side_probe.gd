extends "res://tests/shape_brushes/material_edit_probe.gd"
func read_cells() -> void:preview.solver.rd.buffer_get_data_async(preview.shape_gpu.buffers.cells,_record.bind("cells"))
func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/water_lab.tscn").instantiate();preview.brush_fixture="dry_flat";preview.playing=false;preview.hide_hud=true;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("side_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	_check("side_begin",(await preview.begin_shape_stroke(1002)).is_empty())
	var command:=BrushProtocol.make_command(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2(-0.5,-0.5),Vector2(-0.411611646413803,-0.411611646413803),preview.domain.domain_id,preview.generation,1,1002,0,0,preview.shape_baseline_token)
	await snapshot("side_before");var before:Dictionary=raw_index[-1]
	var result:=await submit(command);_check("side_applied",result.get("status")==1,result)
	await snapshot("side_after");var after:Dictionary=raw_index[-1]
	readbacks.clear();RenderingServer.call_on_render_thread(read_cells);deadline=Time.get_ticks_msec()+30000
	while readbacks.size()<1 and Time.get_ticks_msec()<deadline:await process_frame
	_check("side_cells_complete",readbacks.has("cells") and readbacks.cells.size()==65536*64)
	if readbacks.has("cells"):
		var ties:=0;var wrong:=0
		for i in 256:
			var flags:int=readbacks.cells.decode_u32((i*256+i)*64+60)
			if (flags&12)!=0:ties+=1;wrong+=1 if (flags&8)!=0 else 0
		_check("diagonal_zero_side_left",ties>0 and wrong==0,{"ties":ties,"wrong":wrong})
		var file:=FileAccess.open(output.path_join("side_cells.bin"),FileAccess.WRITE);file.store_buffer(readbacks.cells);file.close()
	var file:=FileAccess.open(output.path_join("side_case.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"before":before,"after":after,"command":command,"result":result,"statistics":preview.shape_gpu.statistics()},"\t"));file.close()
	await preview.end_shape_stroke();await preview.shutdown();preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
