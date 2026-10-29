extends "res://tests/shape_brushes/material_edit_probe.gd"

var seeded:=false
func settle() -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("water_fault_reported",preview.last_error in ["shape GPU dispatch failed","shape GPU receipt mismatch"],preview.last_error)
func seed_water_spares() -> void:
	var ok:=true;var value:=0.03125
	for field in ["water","sediment","momentum_x","momentum_z"]:
		var data:=PackedFloat32Array();data.resize(65536);data.fill(value);value*=0.5
		var texture:RID=preview.solver._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,data.to_byte_array())
		ok=preview.shape_gpu._copy(texture,preview.solver.textures[field][1-preview.solver.current_index]) and ok
		preview.solver.rd.free_rid(texture)
	call_deferred("seed_done",ok)
func seed_done(ok:bool) -> void:_check("water_spares_seeded",ok);seeded=true

func read_candidate() -> void:
	preview.solver.rd.buffer_get_data_async(preview.shape_gpu.buffers.receipt,_record.bind("receipt"))
	preview.solver.rd.buffer_get_data_async(preview.solver.water_candidate,_record.bind("water_candidate"))

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	for brush in [&"wall_v1",&"castle_v1",&"shovel_v1"]:
		for fault in ["transport","identity"]:
			preview=load("res://tests/shape_brushes/water_lab.tscn").instantiate();preview.brush_fixture="shallow_water";preview.water_fixture_mode="loaded";preview.playing=false;preview.hide_hud=true;root.add_child(preview)
			var deadline:=Time.get_ticks_msec()+90000
			while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
			_check(String(brush)+fault+"_ready",preview.ready_for_ticks,preview.last_error)
			if not preview.ready_for_ticks:_finish();quit(1);return
			seeded=false;RenderingServer.call_on_render_thread(seed_water_spares)
			while not seeded:await process_frame
			var begin_error:StringName=await preview.begin_shape_stroke(2000)
			_check("water_fault_begin",begin_error.is_empty(),String(begin_error))
			if not begin_error.is_empty():await preview.shutdown();_finish();quit(1);return
			var before:=await snapshot(String(brush)+fault+"_before");var before_meta:=metadata()
			for field in ["water","sediment","momentum_x","momentum_z"]:_check(field+"_distinct",before[field]!=before["spare_"+field])
			var params:Dictionary
			match brush:
				&"wall_v1":params={"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5}
				&"castle_v1":params={"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0}
				&"shovel_v1":params={"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5}
			var start:=Vector2.ZERO if brush==&"castle_v1" else Vector2(-0.5,0)
			var finish:=Vector2.ZERO if brush==&"castle_v1" else Vector2(0.5,0)
			var command:=BrushProtocol.make_command(brush,params,start,finish,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,2000,0,preview.completed_ticks,preview.shape_baseline_token)
			command.material_profile_id=&"plain_sand_v1" if brush==&"shovel_v1" else &"molded_v1"
			if fault=="transport":preview.shape_gpu.inject_transport_failure_once=true
			else:preview.shape_gpu.inject_wrong_receipt_once=true
			var admission:StringName=preview.input_scheduler.submit(command)
			_check("water_fault_admitted",admission.is_empty(),String(admission));await settle()
			_check(String(brush)+fault+"_all27_atomic",exact(before,await snapshot(String(brush)+fault+"_after")),preview.last_error)
			_check("water_fault_writer_released",not preview.solver.receipt_pending)
			# A failed admitted command consumes its ID; it cannot be replayed.
			before_meta.highwater=command.command_id
			_check("water_fault_metadata",metadata()==before_meta,{"before":before_meta,"after":metadata()})
			readbacks.clear();RenderingServer.call_on_render_thread(read_candidate)
			deadline=Time.get_ticks_msec()+30000
			while readbacks.size()<2 and Time.get_ticks_msec()<deadline:await process_frame
			_check("water_fault_positive_candidate",readbacks.size()==2 and readbacks.receipt.decode_u32(12)==1)
			var changed:=false
			if readbacks.has("water_candidate"):
				var candidate:PackedFloat32Array=readbacks.water_candidate.to_float32_array();var old:PackedFloat32Array=before.water.to_float32_array()
				for i in 65536:changed=changed or candidate[4*i]!=old[i]
			_check("water_fault_displacement_executed",changed)
			var water=preview.shape_gpu.water_transaction;await preview.shutdown();_check("water_fault_released",water.rd==null and water.owned.is_empty());preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
