extends "res://tests/shape_brushes/shovel_probe.gd"
func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27;var negatives:=[]
	for name in ["left_blocked","donor_blocked","low","high","boundary"]:
		preview=load("res://tests/shape_brushes/shovel_edge_lab.tscn").instantiate();preview.edge_mode=name;preview.brush_fixture="dry_flat";preview.playing=false;preview.hide_hud=true;root.add_child(preview)
		var deadline:=Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		_check(name+"_ready",preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks:_finish();quit(1);return
		_check(name+"_begin",(await preview.begin_shape_stroke(3000)).is_empty());sample_index=0
		var a:=Vector2(-0.5,0);var b:=Vector2(0.5,0)
		if name=="boundary":a=Vector2(15,0);b=Vector2(15.25,0)
		var command:=shovel_command(a,b);var before:=await snapshot(name+"_before");var before_index:Dictionary=raw_index[-1];var ledger:=metadata()
		var result:=await submit(command);var after:=await snapshot(name+"_after")
		var status:=2 if name=="left_blocked" else (3 if name=="donor_blocked" else 1)
		_check(name+"_status",result.get("status")==status,result)
		_check(name+"_ledger",preview.domain.sand_source_m3==ledger.source and preview.domain.sand_sink_m3==ledger.sink and preview.domain.tool_inventory_m3==ledger.inventory)
		if status!=1:_check(name+"_full_atomic",exact(before,after))
		cases.append({"name":name,"start":[a.x,a.y],"end":[b.x,b.y],"command":command,"result":result,"before":before_index,"after":raw_index[-1],"before_metadata":ledger,"after_metadata":metadata()})
		if name=="boundary":
			for bad in ["outside","nan","infinity"]:
				var value:Dictionary=command.duplicate(true);value.command_id=preview.command_queue.last_command_id+1;value.sample_index=sample_index
				if bad=="outside":value.end_xz_m=Vector2(15.375,0)
				elif bad=="nan":value.depth_m=NAN
				else:value.transfer_budget_m3=INF
				var before_bad:=metadata();var error:StringName=preview.input_scheduler.submit(value)
				_check(bad+"_admission_rejected",not error.is_empty(),String(error))
				_check(bad+"_authority_unchanged",metadata()==before_bad and exact(after,await snapshot(bad+"_after")))
				negatives.append({"name":bad,"error":String(error)})
		await preview.end_shape_stroke();await preview.shutdown();preview.queue_free();await process_frame
	var file:=FileAccess.open(output.path_join("shovel_cases.json"),FileAccess.WRITE);file.store_string(JSON.stringify(cases,"\t"));file.close()
	file=FileAccess.open(output.path_join("admission_negatives.json"),FileAccess.WRITE);file.store_string(JSON.stringify(negatives,"\t"));file.close()
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
