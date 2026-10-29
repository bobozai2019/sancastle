extends "res://tools/wave_propagation/gpu_probe.gd"
const BrushProto=preload("res://scripts/simulation/brushes/brush_protocol.gd")

var initial_public:=PackedByteArray()
var expected_fault:=false
var injecting:=false
var injected:=false
var fault_evidence: Dictionary={}

func read_render() -> void:
	var result:={}
	for name in ["rock","sand","water","sediment","flux","obstacle"]:
		var rid: RID=owner.state.textures[name] if name in ["rock","obstacle"] else owner.state.textures[name][0]
		result[name]=owner.state.rd.texture_get_data(rid,0)
	if owner.state.textures.has("momentum"):
		result.momentum=owner.state.rd.texture_get_data(owner.state.textures.momentum[0],0)
		var decoded:=MomentumBytes.split(result.momentum)
		result.momentum_x=decoded.momentum_x;result.momentum_z=decoded.momentum_z
	else:
		for name in ["momentum_x","momentum_z"]:result[name]=owner.state.rd.texture_get_data(owner.state.textures[name][0],0)
	# Fatal paths retain both authority slots, not only the published current slot.
	for name in owner.state.textures:
		var value=owner.state.textures[name]
		if value is Array:
			for slot in value.size():result["slot_"+name+"_"+str(slot)]=owner.state.rd.texture_get_data(value[slot],0)
		else:result["slot_"+name]=owner.state.rd.texture_get_data(value,0)
	result.public_water=owner.state.rd.texture_get_data(owner.views.textures.water,0)
	result.control=owner.state.rd.buffer_get_data(owner.transport.control)
	result.decision=owner.state.rd.buffer_get_data(owner.water.decision)
	for name in ["trial","audit","safety"]:result[name]=owner.state.rd.buffer_get_data(owner.water.muscl.buffers[name])
	read_done.call_deferred(result)

func capture(label: String) -> void:
	reading=true;RenderingServer.call_on_render_thread(read_render)
	while reading:await process_frame
	var fields:={}
	for name in captured:
		var path:=output.path_join(label+"_"+name+".bin")
		FileAccess.open(path,FileAccess.WRITE).store_buffer(captured[name])
		fields[name]={"path":path,"bytes":captured[name].size(),"sha256":FileAccess.get_sha256(path)}
	snapshots.append({"label":label,"advanced_time_s":owner.advanced_time_s,"generation":str(owner._generation),"tick":str(owner.completed_tick),"revision":str(owner.completed_revision),"state_seq":str(owner.completed_state_seq),"fields":fields})
	print("SPECIAL_WAVE ",label," t=",owner.advanced_time_s)

func inject_render() -> void:
	var rd: RenderingDevice=owner.state.rd
	var source:=RDShaderSource.new()
	source.source_compute="#version 450\nlayout(local_size_x=1) in;layout(r32f,set=0,binding=0) uniform image2D h;layout(push_constant,std430) uniform P{uint bits,a,b,c;}p;void main(){imageStore(h,ivec2(128),vec4(uintBitsToFloat(p.bits)));}"
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():inject_done.call_deferred(false);return
	var shader: RID=owner.water._own(rd.shader_create_from_spirv(spirv))
	var pipeline: RID=owner.water._own(rd.compute_pipeline_create(shader))
	var uniform: RID=owner.water._make_binding(shader,0,[owner.state.textures.water[0]],[])
	var push:=PackedByteArray();push.resize(16);push.encode_float(0,NAN if case_id=="nonfinite" else -0.001)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniform,0)
	rd.compute_list_set_push_constant(list,push,16);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end()
	inject_done.call_deferred(true)

func inject_done(okay: bool) -> void:
	injected=okay;injecting=false

func run() -> void:
	expected_fault=case_id in ["negative","nonfinite"]
	if case_id not in ["negative","nonfinite","obstacle_pulse","velocity_cap","strong_shovel"] or solver_id!=Config.Numerics.MUSCL or output.is_empty():quit(2);return
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	var simulation:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	extra.append_array(["res://tools/wave_propagation/gpu_probe.gd","res://scripts/simulation/unified_edit/momentum_bytes.gd",get_script().resource_path])
	var frozen:=Config.freeze(catalog.registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"boundary":{"enabled":false},"water_numerics":{"schema":1,"solver_id":solver_id}},extra)
	check("configuration",frozen.error.is_empty())
	if failed:write_result();return
	configuration=frozen.value;owner=Pipeline.new()
	check("configure",owner.configure(catalog.registry,configuration,1001).is_empty())
	var domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1001;domain.sand.fill(.4);domain.water.fill(.1)
	var qx:=PackedFloat32Array();qx.resize(65536)
	if case_id=="velocity_cap":qx.fill(.4)
	if case_id=="strong_shovel":domain.water.fill(.005)
	if case_id=="obstacle_pulse":
		for z in 256:
			for x in 256:
				var px:=(float(x)+.5-128)*.125;var pz:=(float(z)+.5-128)*.125;var index:=z*256+x
				if absf(px)<.25 and absf(pz)<4:domain.obstacle[index]=1.0
				var eta:=.003*exp(-((px+.8)*(px+.8)+pz*pz)/(2*.2*.2))
				if domain.obstacle[index]<.5:domain.water[index]+=eta;qx[index]=sqrt(9.81*.1)*eta
	domain.set_meta("edit_validation_initial_qx",qx)
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	while not owner.initialized and owner.initialization_error.is_empty():await process_frame
	check("initialized:"+String(owner.initialization_error),owner.initialized and owner.fault_reason().is_empty())
	if failed:write_result();return
	await capture("initial");initial_public=captured.public_water
	if expected_fault:
		injecting=true;RenderingServer.call_on_render_thread(inject_render)
		while injecting:await process_frame
		check("injection_uploaded",injected)
		await capture("injected")
		var actual_value: float=captured.water.decode_float((128*256+128)*4)
		check("injection_verified",is_nan(actual_value) if case_id=="nonfinite" else actual_value<0.0)
		check("injection_not_published",captured.public_water==initial_public)
		check("request",owner.request_tick(1.0/30.0).is_empty())
		var deadline:=Time.get_ticks_msec()+15000
		while owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check("expected_numeric_fault",not owner.fault_reason().is_empty())
		await capture("after_fault")
		check("public_view_preserved",captured.public_water==initial_public)
		check("no_time_or_revision",owner.advanced_time_s==0.0 and owner.completed_tick==0 and owner.completed_revision==0 and owner.completed_state_seq==0)
		check("no_accepted_trial",captured.decision.decode_u32(4)==0 and captured.decision.decode_float(12)==0.0 and captured.decision.decode_u32(16)==2)
		fault_evidence={"reason":String(owner.fault_reason()),"control_flags":captured.control.decode_u32(4),"trial_flags":captured.trial.decode_u32(56)}
		check("precise_numeric_reason",fault_evidence.trial_flags==(1 if case_id=="nonfinite" else 2))
		while owner.active_count()>0 and Time.get_ticks_msec()<deadline:
			owner.cleanup_fault();await process_frame
		check("terminal_cleanup",owner.active_count()==0 and owner.pending_count()==0)
	else:
		if case_id=="strong_shovel":
			var identity:={"domain_id":"main_beach","generation":1001,"command_id":1,"sim_tick":0,"stroke_id":7001,"baseline_token":7001}
			check("shovel_begin",owner.submit_control("begin",identity).accepted)
			var command:=BrushProto.make_command(&"shovel_v1",{"trench_width_m":.5,"depth_m":.15,"shoulder_width_m":.5},Vector2(0,-.5),Vector2(0,.5),&"main_beach",1001,2,7001,0,0,7001)
			command.material_profile_id=&"plain_sand_v1";command.water_policy=2;command.speed_m_s=.25
			check("shovel_command",owner.submit_legacy(command,2,.25).accepted)
			identity.command_id=3;check("shovel_end",owner.submit_control("end",identity).accepted)
			await idle();check("shovel_applied",owner.result(2).get("outcome",-1)==Pipeline.L.Outcome.APPLIED)
			check("no_connected_displacement",owner.result(2).get("displaced_water_m3",-1.0)==0.0)
			fault_evidence={"tool":owner.result(2)};await capture("edited")
		while owner.advanced_time_s<duration-1e-7 and not failed:
			check("request",owner.request_tick(minf(1.0/30.0,duration-owner.advanced_time_s)).is_empty())
			await idle()
			if failed:break
			await capture("tick_%03d"%owner.completed_tick)
			check("published",captured.public_water==captured.water)
	owner.close_admission();RenderingServer.call_on_render_thread(owner.release_render)
	var deadline:=Time.get_ticks_msec()+15000
	while not owner.released and Time.get_ticks_msec()<deadline:await process_frame
	check("released",owner.released);write_result()

func write_result() -> void:
	var drift: Array=[]
	for path in configuration.get("sources",{}):
		if FileAccess.get_sha256(path)!=configuration.sources[path]:drift.append(path)
	check("source_integrity",drift.is_empty())
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"outcome":"fail" if failed else "pass","case_id":case_id,"solver_id":solver_id,"expected_fault":expected_fault,"fault":fault_evidence,"checks":checks,"snapshots":snapshots,"configuration":configuration,"source_drift":drift,"scope":"Fixed-bed reflection or deliberate invalid-input rejection, not gameplay/cost"},"\t"))
	quit(1 if failed else 0)
