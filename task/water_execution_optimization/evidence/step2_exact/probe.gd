extends SceneTree

const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
var reference_root:="res://task/water_execution_optimization/baseline/"
var reference_coupled
var reference_done:=false
var reference_error:=""
var output:="res://test_output/water_execution_optimization/exact"
var owner
var registry
var reference: GDScript
var checks: Array=[]
var observations: Array=[]
var failed:=false
var captured: Dictionary={}
var capture_done:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--reference="):reference_root=arg.trim_prefix("--reference=")
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed});failed=failed or not passed
	print("MUSCL_CACHE ",label," ",passed)

func _process(_delta: float) -> bool:
	if owner!=null:owner.pump()
	return false

func reference_source(name: String) -> String:
	var base:=reference_root+"shaders/simulation/muscl/"
	var source:=FileAccess.get_file_as_string(base+name+".glsl").trim_prefix("#[compute]")
	for _pass in 4:
		for include in ["muscl_spatial.glslinc","muscl_math.glslinc","muscl_stats.glslinc"]:
			source=source.replace("#include \""+include+"\"",FileAccess.get_file_as_string(base+include))
	return source

func install_reference() -> void:
	var rd: RenderingDevice=owner.state.rd
	for name in ["rk_decide","rk_edge","rk_drain","rk_euler","rk_finalize","rk_normalize","rk_validate"]:
		var source:=RDShaderSource.new();source.source_compute=reference_source(name)
		var spirv:=rd.shader_compile_spirv_from_source(source)
		var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():reference_installed.call_deferred(error);return
		var shader: RID=owner.water._own(rd.shader_create_from_spirv(spirv))
		var pipeline: RID=owner.water._own(rd.compute_pipeline_create(shader))
		# All candidates preserve descriptor/push layouts. RD validates compatibility.
		owner.water.kernels[name].pipeline=pipeline
	var old=owner.water.muscl
	var recorder=reference.new()
	for name in ["water","rd","images","buffers","sets"]:recorder.set(name,old.get(name))
	owner.water.muscl=recorder;old.water=null
	if owner.water.coupled_recorder.is_valid():
		reference_coupled=load(reference_root+"scripts/simulation/unified_edit/coupled.gd").new()
		for name in ["water","state","rd","images","buffers","sets","kernels","_passes","_erosion_pushes","stage_transport"]:reference_coupled.set(name,owner.coupled.get(name))
		owner.water.coupled_recorder=reference_coupled.record
	reference_installed.call_deferred("")

func reference_installed(error: String) -> void:
	reference_error=error;reference_done=true

func capture_render() -> void:
	var result: Dictionary={}
	for name in owner.state.textures:
		var value=owner.state.textures[name]
		if value is Array:
			for i in value.size():result[name+"_"+str(i)]=owner.state.rd.texture_get_data(value[i],0)
		else:result[name]=owner.state.rd.texture_get_data(value,0)
	result.decision=owner.state.rd.buffer_get_data(owner.water.decision)
	result.control=owner.state.rd.buffer_get_data(owner.transport.control)
	for name in owner.water.muscl.buffers:result["muscl_"+name]=owner.state.rd.buffer_get_data(owner.water.muscl.buffers[name])
	capture_received.call_deferred(result)

func capture_received(value: Dictionary) -> void:captured=value;capture_done=true

func fixture(spec: Dictionary, original: bool) -> Array:
	owner=Pipeline.new()
	var environment: Dictionary={"engine":Engine.get_version_info().string,"probe":"muscl_recording_cache","water_numerics":Config.Numerics.selection(Config.Numerics.MUSCL,spec.retention)}
	if spec.boundary:environment.boundary=Pipeline.Boundary.for_scene("main_beach")
	var simulation:={"enable_erosion":spec.erosion,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},environment,PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES))
	check(spec.name+"_freeze",frozen.error.is_empty())
	if not frozen.error.is_empty():owner=null;return []
	check(spec.name+"_configure",owner.configure(registry,frozen.value,1).is_empty())
	var domain:=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1
	domain.sand.fill(0.4);domain.water.fill(0.1)
	var qx:=PackedFloat32Array();qx.resize(65536);qx.fill(spec.momentum)
	var tags:=PackedFloat32Array();tags.resize(65536)
	for z in range(96,160):
		for x in range(96,160):
			var i:=z*256+x
			domain.sand[i]+=0.04*sin(float(x)*0.2)*cos(float(z)*0.17)
			domain.water[i]=0.025 if x<128 else 0.2
			domain.sediment[i]=0.001;domain.wetness[i]=0.3;domain.compaction[i]=0.95;tags[i]=0.15
	if spec.name=="dry":domain.water.fill(0.0);domain.sediment.fill(0.0);qx.fill(0.0)
	if spec.name=="capacity":domain.water.fill(1000.0);domain.sand.fill(0.4);domain.sediment.fill(0.0);qx.fill(0.0)
	if spec.name=="obstacle":
		for z in range(96,160):domain.obstacle[z*256+128]=1.0
	domain.set_meta("edit_validation_initial_qx",qx);domain.set_meta("brush_initial_mold_depth",tags)
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	var deadline:=Time.get_ticks_msec()+45000
	while not owner.initialized and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(spec.name+"_initialized",owner.initialized and owner.fault_reason().is_empty())
	if not owner.initialized:return []
	if original:
		reference_done=false;RenderingServer.call_on_render_thread(install_reference)
		while not reference_done and Time.get_ticks_msec()<deadline:await process_frame
		check(spec.name+"_reference_installed:"+reference_error,reference_done and reference_error.is_empty())
	check(spec.name+"_invalid_dt_rejected",owner.request_tick(0.0)==&"invalid_dt" and owner.request_tick(NAN)==&"invalid_dt")
	var states: Array=[]
	for dt in ([1.0/30.0] if spec.name=="capacity" else [1.0/30.0,1.0/30.0,0.004,0.004,1.0/30.0]):
		var tick: int=owner.completed_tick
		check(spec.name+"_tick_admitted",owner.request_tick(dt).is_empty())
		deadline=Time.get_ticks_msec()+30000
		while (owner.pending_count()>0 or owner.active_count()>0) and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(spec.name+"_completed",owner.completed_tick==tick+1 and owner.fault_reason().is_empty())
		capture_done=false
		RenderingServer.call_on_render_thread(capture_render)
		while not capture_done and Time.get_ticks_msec()<deadline:await process_frame
		check(spec.name+"_captured",capture_done)
		states.append(captured)
	owner.close_admission();RenderingServer.call_on_render_thread(owner.release_render)
	deadline=Time.get_ticks_msec()+30000
	while not owner.released and Time.get_ticks_msec()<deadline:await process_frame
	check(spec.name+"_released",owner.released)
	if reference_coupled!=null:reference_coupled.water=null;reference_coupled.state=null;reference_coupled=null
	owner=null
	return states

func run() -> void:
	reference=load(reference_root+"scripts/simulation/unified_edit/water_muscl.gd")
	var inputs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(reference_root+"identity.json"))
	var source_hashes: Dictionary={}
	for path in inputs:source_hashes[path]=FileAccess.get_sha256("res://"+path)
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry
	var source_hash:=FileAccess.get_sha256("res://scripts/simulation/unified_edit/water_muscl.gd")
	for spec in [{"name":"still","retention":0.0,"boundary":false,"erosion":false,"momentum":0.0},{"name":"coupled","retention":0.0,"boundary":false,"erosion":true,"momentum":0.1},{"name":"retention","retention":1.0,"boundary":false,"erosion":true,"momentum":0.3},{"name":"boundary","retention":0.5,"boundary":true,"erosion":true,"momentum":0.1},{"name":"high_velocity","retention":0.0,"boundary":false,"erosion":true,"momentum":100.0},{"name":"dry","retention":0.0,"boundary":false,"erosion":false,"momentum":0.0},{"name":"obstacle","retention":1.0,"boundary":false,"erosion":true,"momentum":0.3},{"name":"capacity","retention":0.5,"boundary":false,"erosion":true,"momentum":0.3}]:
		var before: Array=await fixture(spec,true)
		var after: Array=await fixture(spec,false)
		check(spec.name+"_state_count",before.size()==(1 if spec.name=="capacity" else 5) and before.size()==after.size())
		for i in mini(before.size(),after.size()):
			var differences: Array=[];var hashes: Dictionary={}
			for name in before[i]:
				if not after[i].has(name) or before[i][name]!=after[i][name]:differences.append(name)
				var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(before[i][name]);hashes[name]=hash.finish().hex_encode()
			check(spec.name+"_exact_tick_"+str(i+1),not before[i].is_empty() and differences.is_empty() and before[i].size()==after[i].size())
			var d: PackedByteArray=after[i].decision
			if spec.name=="capacity":check("capacity_exercised",d.decode_u32(16)==1 and d.decode_u32(4)+d.decode_u32(40)==64)
			observations.append({"case":spec.name,"tick":i+1,"differences":differences,"hashes":hashes,"accepted":d.decode_u32(4),"rejected":d.decode_u32(40),"status":d.decode_u32(16),"advanced_s":d.decode_float(12)})
		if failed:break
	check("production_source_unchanged_during_probe",source_hash==FileAccess.get_sha256("res://scripts/simulation/unified_edit/water_muscl.gd"))
	for path in source_hashes:check("source_unchanged:"+path,source_hashes[path]==FileAccess.get_sha256("res://"+path))
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("source_hashes.json"),FileAccess.WRITE).store_string(JSON.stringify(source_hashes,"\t"))
	FileAccess.open(output.path_join("exact.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"reference_sha256":FileAccess.get_sha256(reference_root+"scripts/simulation/unified_edit/water_muscl.gd"),"candidate_sha256":source_hash,"engine":Engine.get_version_info(),"reference_root":reference_root,"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name()},"\t"))
	quit(1 if failed else 0)
