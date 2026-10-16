extends "res://tests/shape_brushes/material_edit_probe.gd"

var operator_records := []
var kernel_done := false
var case_name := ""
var stage_name := ""

func kernel_result(ok: bool) -> void:
	_check(case_name+"_"+stage_name+"_dispatched",ok);kernel_done=true

func upload_flow() -> void:
	var flux:=PackedFloat32Array();flux.resize(65536*4);flux.fill(0.0)
	for z in 256:
		for x in 255: flux[(z*256+x)*4+1]=0.01
	var source: RID=preview.solver._create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,flux.to_byte_array())
	var ok: bool=preview.shape_gpu._copy(source,preview.solver.textures.flux[preview.solver.current_index])
	preview.solver.rd.free_rid(source);call_deferred("kernel_result",ok)

func run_operator() -> void:
	var ok: bool=preview.sediment_coupler.dispatch_after_water_substep(1.0/30.0) if stage_name=="sediment" else preview.material_coupler.dispatch_after_erosion(1.0/30.0)
	call_deferred("kernel_result",ok)

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	for selected in ["erosion","deposition","slope_dry","slope_wet","slope_thin","slope_obstacle"]:
		case_name=selected
		preview=load("res://tests/shape_brushes/material_operator_lab.tscn").instantiate()
		preview.operator_case=selected;preview.playing=false;preview.visual_time_s=0.0;root.add_child(preview)
		var deadline:=Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
		_check(selected+"_ready",preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks: break
		preview.sediment_coupler.observe_pushes=true
		if selected in ["erosion","deposition"]:
			stage_name="controlled_flow";kernel_done=false;RenderingServer.call_on_render_thread(upload_flow)
			while not kernel_done: await process_frame
		await snapshot(selected+"_input");var input: Dictionary=raw_index[-1]
		if selected in ["erosion","deposition"]:
			stage_name="sediment";kernel_done=false;RenderingServer.call_on_render_thread(run_operator)
			while not kernel_done: await process_frame
		await snapshot(selected+"_pre_material");var pre_material: Dictionary=raw_index[-1]
		stage_name="material";kernel_done=false;RenderingServer.call_on_render_thread(run_operator)
		while not kernel_done: await process_frame
		await snapshot(selected+"_output");var after: Dictionary=raw_index[-1]
		operator_records.append({"name":selected,"input":input,"pre_material":pre_material,"output":after,"slope_pushes":preview.material_coupler.local_pushes.duplicate(true),"sediment_pushes":preview.sediment_coupler.bound_pushes.duplicate(true),"profile_sha256":preview.material_coupler.profile_sha256,"source_signature":preview.source_signature,"initial_index":0,"scope":"Controlled upstream flow and one actual kernel dispatch, no tick/publication. Intermediate state is not a completed checkpoint."})
		_check(selected+"_no_tick_or_external_ledger",preview.completed_ticks==0 and preview.shadow_domain.sand_source_m3==0.0 and preview.shadow_domain.sand_sink_m3==0.0)
		await preview.shutdown();_check(selected+"_released",preview.gpu_release_done);preview.queue_free();await process_frame
	var file:=FileAccess.open(output.path_join("operator_evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":operator_records},"\t"));file.close()
	_finish();var passed:=true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)
