extends "res://tests/shape_brushes/checkpoint_v4_probe.gd"

var poison_done:=false
var poison_resources:Dictionary={}
var branches:Dictionary={}
var scratch_reads:Dictionary={}
var scratch_index:Dictionary={}
var poison_shader:=RID()
var poison_pipeline:=RID()
var poison_compile_done:=false
var poison_compile_error:=""

func compile_poison() -> void:
	var rd:RenderingDevice=preview.solver.rd
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://tests/shape_brushes/poison_simulation_scratch.glsl").replace("#[compute]","")
	var code:=rd.shader_compile_spirv_from_source(source)
	poison_compile_error=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if poison_compile_error.is_empty():
		poison_shader=rd.shader_create_from_spirv(code);poison_pipeline=rd.compute_pipeline_create(poison_shader)
	call_deferred("poison_compiled")

func poison_compiled() -> void:poison_compile_done=true

func release_poison() -> void:
	var rd:RenderingDevice=RenderingServer.get_rendering_device()
	if poison_pipeline.is_valid():rd.free_rid(poison_pipeline)
	if poison_shader.is_valid():rd.free_rid(poison_shader)
	poison_pipeline=RID();poison_shader=RID();call_deferred("poison_released")

func poison() -> void:
	var rd:RenderingDevice=preview.solver.rd
	var uniforms:Array[RDUniform]=[]
	var resources:Array[RID]=[preview.solver.textures.edge_x,preview.solver.textures.edge_z,preview.solver.textures.drain,preview.solver.textures.cfl_tiles,preview.material_coupler.result_buffer,preview.material_coupler.support_result,preview.material_coupler.support_flags,preview.material_coupler.support_indirect]
	var names:Array=["edge_x","edge_z","drain","cfl_tiles","slope_result","mold_result","support_flags","support_indirect"]
	for binding in resources.size():
		var uniform:=RDUniform.new();uniform.binding=binding;uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if binding<4 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.add_id(resources[binding]);uniforms.append(uniform)
		poison_resources[names[binding]]=resources[binding].get_id()
	var set_id:=rd.uniform_set_create(uniforms,poison_shader,0)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,poison_pipeline);rd.compute_list_bind_uniform_set(list,set_id,0);rd.compute_list_dispatch(list,32,32,1);rd.compute_list_end()
	rd.free_rid(set_id)
	# Every target is read back; a single cfl pixel cannot prove eight writes.
	read_scratch()

func read_scratch() -> void:
	var rd:RenderingDevice=preview.solver.rd
	for name in ["edge_x","edge_z","drain","cfl_tiles"]:
		rd.texture_get_data_async(preview.solver.textures[name],0,scratch_received.bind(name))
	for pair in [["slope_result",preview.material_coupler.result_buffer],["mold_result",preview.material_coupler.support_result],["support_flags",preview.material_coupler.support_flags],["support_indirect",preview.material_coupler.support_indirect]]:
		rd.buffer_get_data_async(pair[1],scratch_received.bind(pair[0]))

func scratch_received(bytes:PackedByteArray,name:String) -> void:call_deferred("scratch_stored",bytes,name)
func scratch_stored(bytes:PackedByteArray,name:String) -> void:scratch_reads[name]=bytes

func capture_scratch(tag:String) -> Dictionary:
	scratch_reads.clear();RenderingServer.call_on_render_thread(read_scratch)
	return await finish_scratch_capture(tag)

func finish_scratch_capture(tag:String) -> Dictionary:
	var deadline:=Time.get_ticks_msec()+30000
	while scratch_reads.size()<8 and Time.get_ticks_msec()<deadline:await process_frame
	_check(tag+"_all8_workspaces",scratch_reads.size()==8)
	var state:Dictionary=scratch_reads.duplicate(true);var index:Dictionary={}
	for name in state:
		var path:String=output.path_join(tag+"_"+name+".bin")
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(state[name]);file.close()
		index[name]={"path":path,"bytes":state[name].size(),"sha256":FileAccess.get_sha256(path)}
	scratch_index[tag]=index
	return state

func poison_released() -> void:
	_check("scratch_poison_resources_released",not poison_pipeline.is_valid() and not poison_shader.is_valid());poison_done=true

func finish_poison() -> void:
	poison_done=false;RenderingServer.call_on_render_thread(release_poison)
	while not poison_done:await process_frame

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/water_lab.tscn").instantiate();preview.brush_fixture="dry_flat";preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("scratch_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	RenderingServer.call_on_render_thread(compile_poison)
	while not poison_compile_done:await process_frame
	_check("scratch_shader_compiled_before_ticks",poison_compile_error.is_empty() and poison_pipeline.is_valid(),poison_compile_error)
	if not poison_compile_error.is_empty() or not poison_pipeline.is_valid():
		await finish_poison();await preview.shutdown();_finish();quit(1);return
	preview.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed=false
	_check("scratch_castle",(await stamp(&"castle_v1",{"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0},Vector2.ZERO,Vector2.ZERO,8100)).get("status")==1)
	_check("scratch_shovel",(await stamp(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2(-0.5,1.25),Vector2(0.5,1.25),8101)).get("status")==1)
	await _ticks(238)
	var anchor:=await snapshot("scratch_anchor_238")
	var checkpoint_path:String=output.path_join("scratch_238.scp")
	var error:StringName=await preview.save_gpu_checkpoint(checkpoint_path)
	_check("scratch_actual_disk_save",error.is_empty(),String(error))
	if not error.is_empty():await finish_poison();await preview.shutdown();_finish();quit(1);return
	for branch in ["direct","restored","restored_poisoned"]:
		if branch!="direct":
			error=await preview.restore_gpu_checkpoint(checkpoint_path)
			_check(branch+"_restore",error.is_empty(),String(error))
			_check(branch+"_anchor_all27",exact(anchor,await snapshot(branch+"_anchor")))
		if branch=="restored_poisoned":
			var before_meta:Dictionary=metadata()
			poison_done=false;scratch_reads.clear();RenderingServer.call_on_render_thread(poison)
			var written:Dictionary=await finish_scratch_capture("poison_written")
			_check("scratch_poison_completed",written.size()==8)
			_check("scratch_poison_authority_unchanged",exact(anchor,await snapshot("poisoned_authority")))
			_check("scratch_poison_metadata_unchanged",metadata()==before_meta)
		var states:Dictionary={};var indices:Dictionary={}
		for tick in range(239,301):
			await _ticks(1)
			if not preview.last_error.is_empty():break
			if tick in [239,240,248,260,280,300]:
				states[tick]=await snapshot(branch+"_"+str(tick));indices[tick]=raw_index[-1]
			if tick==239:await capture_scratch(branch+"_239_work")
		branches[branch]={"states":states,"indices":indices}
	for tick in [239,240,248,260,280,300]:
		for branch in ["restored","restored_poisoned"]:
			var changed:Array=[]
			if not branches.direct.states.has(tick) or not branches[branch].states.has(tick):changed.append("missing_sample")
			else:
				for field in branches.direct.states[tick]:
					if branches.direct.states[tick][field]!=branches[branch].states[tick][field]:changed.append(field)
			_check(branch+"_exact_"+str(tick),changed.is_empty(),changed)
	var compact:Dictionary={}
	for branch in branches:compact[branch]=branches[branch].indices
	var file:=FileAccess.open(output.path_join("scratch_restore.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"anchor_tick":238,"end_tick":300,"branches":compact,"raw_index":raw_index,"scratch_index":scratch_index,"poison_resources":poison_resources,"source_signature":preview.source_signature,"scope":"Sentinel overwrite of eight non-checkpoint work resources; all 27 authority fields and metadata checked unchanged before next tick; direct/ordinary-restore/poisoned-restore actual checkpoint238 continuation. Reads all poisoned targets and first next-tick scratch. No timing or cost measurements; does not prove all missing hidden state absent."},"\t"));file.close()
	await finish_poison()
	await preview.shutdown();_check("scratch_release",preview.gpu_release_done);preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
