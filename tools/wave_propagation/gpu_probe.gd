extends SceneTree

const MomentumBytes=preload("res://scripts/simulation/unified_edit/momentum_bytes.gd")
const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
var owner
var output:=""
var solver_id:="muscl_mc_ssprk2_v1"
var case_id:="lake_flat"
var duration:=0.1
var tick_dt:=1.0/30.0
var mean_depth:=0.1
var amplitude:=0.0001
var captured: Dictionary={}
var reading:=false
var failed:=false
var checks: Array=[]
var snapshots: Array=[]
var configuration: Dictionary={}
var began:=0
var deep:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--solver="):solver_id=arg.trim_prefix("--solver=")
		if arg.begins_with("--case="):case_id=arg.trim_prefix("--case=")
		if arg.begins_with("--duration="):duration=arg.trim_prefix("--duration=").to_float()
		if arg.begins_with("--tick-dt="):tick_dt=arg.trim_prefix("--tick-dt=").to_float()
		if arg.begins_with("--depth="):mean_depth=arg.trim_prefix("--depth=").to_float()
		if arg.begins_with("--amplitude="):amplitude=arg.trim_prefix("--amplitude=").to_float()
	began=Time.get_ticks_msec();call_deferred("run")

func _process(_delta: float) -> bool:
	if owner!=null:owner.pump()
	if Time.get_ticks_msec()-began>600000:push_error("GPU probe timeout");quit(2)
	return false

func check(label: String,okay: bool) -> void:
	checks.append({"label":label,"pass":okay});failed=failed or not okay
	if not okay:push_error(label)

func idle() -> void:
	while owner.pending_count()>0 or owner.active_count()>0:
		if not owner.fault_reason().is_empty():check("idle:"+String(owner.fault_reason()),false);return
		await process_frame
	check("idle",owner.fault_reason().is_empty())

func read_render() -> void:
	var result:={}
	for name in ["rock","sand","water","sediment","flux"]:
		var rid: RID=owner.state.textures[name] if name=="rock" else owner.state.textures[name][0]
		result[name]=owner.state.rd.texture_get_data(rid,0)
	if owner.state.textures.has("momentum"):
		result.momentum=owner.state.rd.texture_get_data(owner.state.textures.momentum[0],0)
		var decoded:=MomentumBytes.split(result.momentum)
		result.momentum_x=decoded.momentum_x;result.momentum_z=decoded.momentum_z
	else:
		for name in ["momentum_x","momentum_z"]:result[name]=owner.state.rd.texture_get_data(owner.state.textures[name][0],0)
	result.control=owner.state.rd.buffer_get_data(owner.transport.control)
	result.decision=owner.state.rd.buffer_get_data(owner.water.decision)
	if owner.water.muscl!=null:
		for name in ["trial","audit","safety"]:result[name]=owner.state.rd.buffer_get_data(owner.water.muscl.buffers[name])
		if deep:
			for name in ["u1","u2","edge0_x","edge0_z","edge1_x","edge1_z","drain0","drain1"]:result[name]=owner.state.rd.texture_get_data(owner.water.muscl.images[name],0)
	var equal_views:=true
	for name in ["sand","water"]:equal_views=equal_views and result[name]==owner.state.rd.texture_get_data(owner.views.textures[name],0)
	if owner.state.textures.has("momentum"):equal_views=equal_views and result.momentum==owner.state.rd.texture_get_data(owner.views.textures.momentum,0)
	else:
		for name in ["momentum_x","momentum_z"]:equal_views=equal_views and result[name]==owner.state.rd.texture_get_data(owner.views.textures[name],0)
	result.published_matches=equal_views
	read_done.call_deferred(result)

func read_done(value: Dictionary) -> void:
	captured=value;reading=false

func snapshot(label: String,include_private: bool=false) -> void:
	await idle();deep=include_private;reading=true
	RenderingServer.call_on_render_thread(read_render)
	while reading:await process_frame
	var fields:={}
	for name in captured:
		if name=="published_matches":continue
		var path:=output.path_join(label+"_"+name+".bin")
		FileAccess.open(path,FileAccess.WRITE).store_buffer(captured[name])
		fields[name]={"path":path,"bytes":captured[name].size(),"sha256":FileAccess.get_sha256(path)}
	check("published:"+label,captured.published_matches)
	snapshots.append({"label":label,"advanced_time_s":owner.advanced_time_s,"generation":str(owner._generation),"tick":str(owner.completed_tick),"revision":str(owner.completed_revision),"state_seq":str(owner.completed_state_seq),"fields":fields})
	print("GPU_WAVE ",label," t=",owner.advanced_time_s," revision=",owner.completed_revision)

func run() -> void:
	if output.is_empty() or solver_id not in [Config.Numerics.FIRST_ORDER,Config.Numerics.MUSCL] or case_id not in ["lake_flat","lake_slope","lake_step","lake_shore","lake_obstacle","wave_0.5m","wave_1m","wave_2m","wave_4m","wave_z_2m","wave_diagonal_2m","dam_break","near_dry","cfl_capacity","concentration_001","concentration_005"] or not is_finite(duration) or duration<=0.0 or duration>6.0 or not is_finite(tick_dt) or tick_dt<=0.0 or tick_dt>1.0/30.0+1e-9 or not is_finite(mean_depth) or mean_depth<0.005 or mean_depth>1.0 or not is_finite(amplitude) or amplitude<=0.0 or amplitude>0.01:quit(2);return
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Water numerical probe - "+case_id)
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	var simulation:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	extra.append("res://tools/wave_propagation/gpu_probe.gd")
	var frozen:=Config.freeze(catalog.registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"boundary":{"enabled":false},"water_numerics":{"schema":1,"solver_id":solver_id}},extra)
	check("configuration",frozen.error.is_empty())
	if failed:write_result();return
	configuration=frozen.value;owner=Pipeline.new()
	check("configure",owner.configure(catalog.registry,configuration,1001).is_empty())
	if failed:write_result();return
	var domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1001
	if case_id=="cfl_capacity":mean_depth=1000.0
	domain.sand.fill(0.4);domain.water.fill(mean_depth)
	var qx:=PackedFloat32Array();qx.resize(65536)
	var qz:=PackedFloat32Array();qz.resize(65536)
	for z in 256:
		for x in 256:
			var px:=(float(x)+0.5-128.0)*0.125
			var pz:=(float(z)+0.5-128.0)*0.125
			var index:=z*256+x
			if case_id=="lake_slope":domain.sand[index]=0.4+0.003*px;domain.water[index]=maxf(0.0,0.5-domain.sand[index])
			if case_id=="lake_step":domain.sand[index]=0.4 if px<0.0 else 0.45;domain.water[index]=0.5-domain.sand[index]
			if case_id=="lake_shore":domain.sand[index]=0.4+0.02*px;domain.water[index]=maxf(0.0,0.5-domain.sand[index])
			if case_id=="lake_obstacle" and absf(px)<0.5 and absf(pz)<1.0:domain.obstacle[index]=1.0
			if case_id.begins_with("wave_"):
				var wavelength:=float(case_id.get_slice("_",case_id.get_slice_count("_")-1).trim_suffix("m"))
				var direction:=Vector2(0,1) if case_id.contains("_z_") else (Vector2.ONE.normalized() if case_id.contains("_diagonal_") else Vector2(1,0))
				var eta:=amplitude*sin(TAU*Vector2(px,pz).dot(direction)/wavelength)
				domain.water[index]+=eta;qx[index]=sqrt(9.81*mean_depth)*eta*direction.x;qz[index]=sqrt(9.81*mean_depth)*eta*direction.y
			if case_id in ["dam_break","near_dry"]:domain.water[index]=0.2 if px<0.0 else (0.0009 if case_id=="near_dry" else 0.0)
			if case_id.begins_with("concentration_"):
				domain.water[index]=0.1+0.0002*sin(PI*px)*cos(PI*pz);qx[index]=0.002
				domain.sediment[index]=domain.water[index]*(0.01 if case_id=="concentration_001" else 0.05)
	domain.set_meta("edit_validation_initial_qx",qx)
	domain.set_meta("edit_validation_initial_qz",qz)
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	while not owner.initialized and owner.initialization_error.is_empty():await process_frame
	check("initialized:"+String(owner.initialization_error),owner.initialized and owner.fault_reason().is_empty())
	if not failed:
		await snapshot("initial")
		while owner.advanced_time_s<duration-1e-7 and not failed:
			check("request",owner.request_tick(minf(tick_dt,duration-owner.advanced_time_s)).is_empty())
			await idle()
			if failed:break
			await snapshot("tick_%03d"%owner.completed_tick,owner.advanced_time_s>=duration-1e-7)
	owner.close_admission();RenderingServer.call_on_render_thread(owner.release_render)
	while not owner.released:await process_frame
	check("released",owner.released);write_result()

func write_result() -> void:
	var drift: Array=[]
	for path in configuration.get("sources",{}):
		if FileAccess.get_sha256(path)!=configuration.sources[path]:drift.append(path)
	check("source_integrity",drift.is_empty())
	var report:={"schema":1,"solver_id":solver_id,"case_id":case_id,"requested_time_s":duration,"input":{"mean_depth_m":mean_depth,"amplitude_m":amplitude,"grid_size":256,"cell_size_m":0.125},"configuration":configuration,"snapshots":snapshots,"checks":checks,"source_drift":drift,"outcome":"fail" if failed else "pass","engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"scope":"Fixed-bed GPU numerical fields. No performance or gameplay claim."}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));quit(1 if failed else 0)
