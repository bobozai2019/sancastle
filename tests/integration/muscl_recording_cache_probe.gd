extends SceneTree

const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const REFERENCE="res://task/muscl_recording_optimization/reference/water_muscl.gd"
var output:="res://test_output/muscl_recording_cache"
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
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed});failed=failed or not passed
	print("MUSCL_CACHE ",label," ",passed)

func _process(_delta: float) -> bool:
	if owner!=null:owner.pump()
	return false

func install_reference() -> void:
	var old=owner.water.muscl
	var recorder=reference.new()
	for name in ["water","rd","images","buffers","sets"]:recorder.set(name,old.get(name))
	owner.water.muscl=recorder;old.water=null

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
	domain.set_meta("edit_validation_initial_qx",qx);domain.set_meta("brush_initial_mold_depth",tags)
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	var deadline:=Time.get_ticks_msec()+45000
	while not owner.initialized and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(spec.name+"_initialized",owner.initialized and owner.fault_reason().is_empty())
	if not owner.initialized:return []
	if original:RenderingServer.call_on_render_thread(install_reference)
	check(spec.name+"_invalid_dt_rejected",owner.request_tick(0.0)==&"invalid_dt" and owner.request_tick(NAN)==&"invalid_dt")
	var states: Array=[]
	for dt in [1.0/30.0,1.0/30.0,0.004,0.004,1.0/30.0]:
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
	owner=null
	return states

func run() -> void:
	reference=load(REFERENCE)
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry
	var source_hash:=FileAccess.get_sha256("res://scripts/simulation/unified_edit/water_muscl.gd")
	for spec in [{"name":"still","retention":0.0,"boundary":false,"erosion":false,"momentum":0.0},{"name":"coupled","retention":0.0,"boundary":false,"erosion":true,"momentum":0.1},{"name":"retention","retention":1.0,"boundary":false,"erosion":true,"momentum":0.3},{"name":"boundary","retention":0.5,"boundary":true,"erosion":true,"momentum":0.1},{"name":"high_velocity","retention":0.0,"boundary":false,"erosion":true,"momentum":100.0}]:
		var before: Array=await fixture(spec,true)
		var after: Array=await fixture(spec,false)
		check(spec.name+"_state_count",before.size()==5 and after.size()==5)
		for i in mini(before.size(),after.size()):
			var differences: Array=[];var hashes: Dictionary={}
			for name in before[i]:
				if not after[i].has(name) or before[i][name]!=after[i][name]:differences.append(name)
				var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(before[i][name]);hashes[name]=hash.finish().hex_encode()
			check(spec.name+"_exact_tick_"+str(i+1),not before[i].is_empty() and differences.is_empty() and before[i].size()==after[i].size())
			var d: PackedByteArray=after[i].decision
			observations.append({"case":spec.name,"tick":i+1,"differences":differences,"hashes":hashes,"accepted":d.decode_u32(4),"rejected":d.decode_u32(40),"status":d.decode_u32(16),"advanced_s":d.decode_float(12)})
		if failed:break
	check("production_source_unchanged_during_probe",source_hash==FileAccess.get_sha256("res://scripts/simulation/unified_edit/water_muscl.gd"))
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("exact.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"reference_sha256":FileAccess.get_sha256(REFERENCE),"candidate_sha256":source_hash,"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name()},"\t"))
	quit(1 if failed else 0)
