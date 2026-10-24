extends "res://tools/wave_propagation/gpu_probe.gd"

const REVERSAL="res://tools/wave_propagation/fixtures/reversal_v2.rgba32f"
const BrushProto=preload("res://scripts/simulation/brushes/brush_protocol.gd")
const MaterialState=preload("res://scripts/simulation/brushes/brush_material_state_codec.gd")
const CASES=["erosion","deposition","transport_forward","transport_backward","constant_001_off","constant_005_off","reversal","near_dry","obstacle","boundary","support","molded_edit"]
var coupling_enabled:=true
var actual_stage_transport:=false
var initial_ledger: Dictionary={}
var final_ledger: Dictionary={}
var setup_result: Dictionary={}

func validate_material(label: String) -> void:
	if case_id not in ["support","molded_edit"]:return
	var record:=MaterialState.make_record(captured.mold_support,captured.mold_support_spare,owner.accounting.material_ever_used,configuration.material.sha256)
	check("material_layout:"+label,MaterialState.validate(record,captured.sand,captured.sand_spare,configuration.material.sha256).is_empty())

func read_render() -> void:
	var result:={}
	for name in ["rock","sand","water","momentum_x","momentum_z","sediment","flux","obstacle","wetness","compaction","mold_support"]:
		var rid: RID=owner.state.textures[name] if name in ["rock","obstacle"] else owner.state.textures[name][0]
		result[name]=owner.state.rd.texture_get_data(rid,0)
	for name in ["sand","sediment","wetness","compaction","mold_support"]:result[name+"_spare"]=owner.state.rd.texture_get_data(owner.state.textures[name][1],0)
	result.control=owner.state.rd.buffer_get_data(owner.transport.control)
	result.decision=owner.state.rd.buffer_get_data(owner.water.decision)
	if owner.water.muscl!=null:
		for name in ["trial","audit","safety"]:result[name]=owner.state.rd.buffer_get_data(owner.water.muscl.buffers[name])
		if deep:
			for name in ["u1","u2","edge0_x","edge0_z","edge1_x","edge1_z","drain0","drain1"]:result[name]=owner.state.rd.texture_get_data(owner.water.muscl.images[name],0)
			if coupling_enabled:result.exchange_sediment=owner.state.rd.texture_get_data(owner.water.muscl.images.exchange_sediment,0)
	if coupling_enabled:
		result.coupled_dirty=owner.state.rd.texture_get_data(owner.coupled.images.dirty,0)
		result.coupled_flags=owner.state.rd.buffer_get_data(owner.coupled.buffers.flags)
		result.coupled_support=owner.state.rd.buffer_get_data(owner.coupled.buffers.support)
	var equal_views:=true
	for name in ["sand","water","momentum_x","momentum_z","sediment","wetness","compaction","mold_support"]:equal_views=equal_views and result[name]==owner.state.rd.texture_get_data(owner.views.textures[name],0)
	result.published_matches=equal_views;read_done.call_deferred(result)

func run() -> void:
	if output.is_empty() or case_id not in CASES or solver_id not in [Config.Numerics.FIRST_ORDER,Config.Numerics.MUSCL] or not is_finite(duration) or duration<=0.0 or duration>6 or not is_finite(tick_dt) or tick_dt<=0.0 or tick_dt>1.0/30.0+1e-9:quit(2);return
	coupling_enabled=not case_id.ends_with("_off") and case_id!="reversal"
	if not coupling_enabled and solver_id!=Config.Numerics.MUSCL:quit(2);return
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Coupled RK water - "+case_id)
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	var flags:={"enable_erosion":coupling_enabled,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var boundary:={"enabled":false}
	if case_id=="boundary":boundary={"enabled":true,"mode":0,"mean_level_m":0.52,"amplitude_m":0.0,"omega_rad_s":0.0,"phase_rad":0.0,"period_s":16.0}
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	extra.append_array(["res://tools/wave_propagation/gpu_probe.gd",get_script().resource_path])
	if case_id=="reversal":extra.append(REVERSAL)
	var frozen:=Config.freeze(catalog.registry,"main_beach",flags,{"foam_enabled":false,"gravel_enabled":false},{},{"boundary":boundary,"water_numerics":{"schema":1,"solver_id":solver_id}},extra)
	check("configuration",frozen.error.is_empty())
	if failed:write_result();return
	configuration=frozen.value;owner=Pipeline.new()
	check("configure",owner.configure(catalog.registry,configuration,1001).is_empty())
	if failed:write_result();return
	var domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1001;domain.sand.fill(.4);domain.water.fill(.1)
	var qx:=PackedFloat32Array();qx.resize(65536)
	var qz:=PackedFloat32Array();qz.resize(65536)
	var tags:=PackedFloat32Array();tags.resize(65536)
	var seed:=PackedFloat32Array()
	if case_id=="reversal":seed=FileAccess.get_file_as_bytes(REVERSAL).to_float32_array()
	for z in 256:
		for x in 256:
			var px:=(float(x)+.5-128)*.125;var pz:=(float(z)+.5-128)*.125;var i:=z*256+x
			if case_id in ["erosion","support"]:qx[i]=.01
			if case_id=="deposition":domain.sediment[i]=.001
			if case_id in ["transport_forward","transport_backward"]:
				qx[i]=.002 if case_id=="transport_forward" else -.002
				domain.sediment[i]=.001+.0002*sin(PI*px)*cos(PI*pz)
			if case_id.ends_with("_off"):
				domain.water[i]=.1+.0002*sin(PI*px)*cos(PI*pz);qx[i]=.002
				domain.sediment[i]=domain.water[i]*(.01 if case_id=="constant_001_off" else .05)
			if case_id=="reversal":
				domain.water[i]=seed[i*4];qx[i]=seed[i*4+1];qz[i]=seed[i*4+2];domain.sediment[i]=seed[i*4+3]
			if case_id=="near_dry":
				domain.water[i]=.02 if px<0 else .0009;domain.sediment[i]=.01*domain.water[i]
			if case_id=="obstacle":
				qx[i]=.002;domain.sediment[i]=.001+.0002*sin(PI*px)*cos(PI*pz)
				if absf(px)<.25 and absf(pz)<1:domain.obstacle[i]=1
			if case_id=="boundary":domain.sediment[i]=.001
			if case_id=="support" and px*px+pz*pz<4:tags[i]=.1
	domain.set_meta("edit_validation_initial_qx",qx);domain.set_meta("edit_validation_initial_qz",qz)
	if case_id=="support":domain.set_meta("brush_initial_mold_depth",tags)
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	while not owner.initialized and owner.initialization_error.is_empty():await process_frame
	check("initialized:"+String(owner.initialization_error),owner.initialized and owner.fault_reason().is_empty())
	if not failed:
		actual_stage_transport=owner.water.muscl!=null
		check("actual_coupling_capability",not coupling_enabled or owner.coupled.stage_transport==actual_stage_transport)
		initial_ledger=owner.ledger_snapshot()
		await snapshot("initial")
		validate_material("initial")
		if case_id=="molded_edit":
			var identity:={"domain_id":"main_beach","generation":1001,"command_id":1,"sim_tick":0,"stroke_id":7001,"baseline_token":7001}
			check("castle_begin",owner.submit_control("begin",identity).accepted)
			var command:=BrushProto.make_command(&"castle_v1",{"scale_xz":1.0,"height_m":.7,"yaw_rad":0.0},Vector2.ZERO,Vector2.ZERO,&"main_beach",1001,2,7001,0,0,7001)
			command.water_policy=3;command.speed_m_s=0.0
			check("castle_command",owner.submit_legacy(command,3,0.0).accepted)
			identity.command_id=3;check("castle_end",owner.submit_control("end",identity).accepted)
			await idle();setup_result=owner.result(2)
			check("castle_applied",setup_result.get("outcome",-1)==Pipeline.L.Outcome.APPLIED)
			await snapshot("edited");validate_material("edited")
		while owner.advanced_time_s<duration-1e-7 and not failed:
			check("request",owner.request_tick(minf(tick_dt,duration-owner.advanced_time_s)).is_empty())
			await idle()
			if failed:break
			await snapshot("tick_%03d"%owner.completed_tick,owner.advanced_time_s>=duration-1e-7)
			validate_material("tick_%03d"%owner.completed_tick)
		final_ledger=owner.ledger_snapshot()
	owner.close_admission();RenderingServer.call_on_render_thread(owner.release_render)
	while not owner.released:await process_frame
	check("released",owner.released and owner.water.owned.is_empty() and owner.coupled.rd==null);write_result()

func write_result() -> void:
	var drift: Array=[]
	for path in configuration.get("sources",{}):
		if FileAccess.get_sha256(path)!=configuration.sources[path]:drift.append(path)
	check("source_integrity",drift.is_empty())
	var result:={"schema":1,"suite":"coupling","outcome":"fail" if failed else "pass","case_id":case_id,"solver_id":solver_id,"coupling_enabled":coupling_enabled,"transport_in_rk":actual_stage_transport,"requested_time_s":duration,"configuration":configuration,"snapshots":snapshots,"checks":checks,"initial_ledger":initial_ledger,"final_ledger":final_ledger,"setup_result":setup_result,"source_drift":drift,"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"scope":"Actual GPU stage transport and once-per-accepted-step exchange/material; no gameplay or performance acceptance"}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));quit(1 if failed else 0)
