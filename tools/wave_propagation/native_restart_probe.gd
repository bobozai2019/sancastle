extends "res://tools/wave_propagation/gpu_probe.gd"
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
var mode:="seed"
var input_file:=""
var save_result: Dictionary={}
var saved_rows: Array=[]
var probe_result: Dictionary={}
var initial_scratch: Dictionary={}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--input="):input_file=arg.trim_prefix("--input=")
	super._initialize()
func saved(value: Dictionary) -> void:save_result=value
func probe_received(value: Dictionary) -> void:probe_result=value
func save_state(label: String) -> void:
	await idle();save_result={}
	var path:=output.path_join(label+".sandue")
	var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"place_sand","parameters":{},"dig_amount_m3":0.05,"fill_amount_m3":0.05}}
	check("save_admitted:"+label,owner.save_checkpoint(path,selection,saved).accepted)
	while save_result.is_empty():await process_frame
	check("save_completed:"+label,save_result.error.is_empty())
	if not save_result.error.is_empty():return
	var loaded:=Codec.load(path,configuration)
	check("saved_container_valid:"+label,loaded.error.is_empty())
	saved_rows.append({"label":label,"path":path,"sha256":FileAccess.get_sha256(path),"time_s":owner.advanced_time_s,"tick":str(owner.completed_tick),"revision":str(owner.completed_revision),"state_seq":str(owner.completed_state_seq),"capture":owner.last_checkpoint_info.duplicate(true)})
func scratch_render() -> void:
	var values:={}
	for name in ["trial","audit","safety"]:
		var raw: PackedByteArray=owner.state.rd.buffer_get_data(owner.water.muscl.buffers[name]);var zero:=PackedByteArray();zero.resize(raw.size());values[name]={"bytes":raw.size(),"sha256":Codec.Old.digest(raw).hex_encode(),"zero":raw==zero}
	initial_scratch=values
func run() -> void:
	if output.is_empty() or mode not in ["seed","resume"] or DirAccess.dir_exists_absolute(output):quit(2);return
	DirAccess.make_dir_recursive_absolute(output);DisplayServer.window_set_size(Vector2i(1280,720));owner=Pipeline.new()
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	if mode=="resume":
		var loaded:=Codec.read_container(input_file);check("input_container",loaded.error.is_empty())
		if failed:finish();return
		configuration=loaded.checkpoint.configuration.duplicate(true)
		check("source_configuration_disk_identity",Config.validate(configuration,true).is_empty())
		check("resume_configure",owner.configure_restore(catalog.registry,configuration,1002,loaded.checkpoint).is_empty())
		RenderingServer.call_on_render_thread(owner.initialize_render.bind(owner.restore_domain()))
	else:
		var simulation:={"enable_erosion":true,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
		var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES);extra.append_array([get_script().resource_path,"res://tools/wave_propagation/gpu_probe.gd"])
		var environment:={"boundary":{"enabled":false},"water_numerics":{"schema":1,"solver_id":"muscl_mc_ssprk2_v1"},"gravel_profile":Pipeline.Visuals.Gravel.default_profile("main_beach",80)}
		var frozen:=Config.freeze(catalog.registry,"main_beach",simulation,{"foam_enabled":true,"gravel_enabled":true},{},environment,extra)
		check("configuration",frozen.error.is_empty());configuration=frozen.value
		check("configure",owner.configure(catalog.registry,configuration,1001).is_empty())
		var domain=Domain.new(256,.125);domain.domain_id=&"main_beach";domain.generation=1001;domain.sand.fill(.4)
		var qx:=PackedFloat32Array();qx.resize(65536)
		for z in 256:
			for x in 256:
				var phase:=(float(x)+.5-128)*.125*PI;var eta:=.001*sin(phase);var i:=z*256+x;domain.water[i]=.1+eta;domain.sediment[i]=.001;qx[i]=sqrt(9.81*.1)*eta
		domain.set_meta("edit_validation_initial_qx",qx)
		RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	while not owner.initialized and owner.initialization_error.is_empty():await process_frame
	check("initialized",owner.initialized and owner.fault_reason().is_empty())
	if failed:finish();return
	check("actual_muscl_and_both_visuals",owner.water.muscl!=null and owner.visuals.foam_enabled and owner.visuals.gravel_enabled)
	RenderingServer.call_on_render_thread(scratch_render)
	while initial_scratch.is_empty():await process_frame
	for name in initial_scratch:check("private_scratch_zero:"+name,initial_scratch[name].zero)
	if mode=="resume":await save_state("restored")
	else:
		for i in 3:check("seed_tick_admitted",owner.request_tick(1.0/30.0).is_empty());await idle()
		await save_state("seed")
	var paused: float=owner.advanced_time_s
	for frame in 8:await process_frame
	check("paused_clock_stable",owner.advanced_time_s==paused)
	await snapshot("before_continuation")
	var request:={"request_id":1,"owner_token":1,"generation":owner._generation,"pose_seq":1,"domain_id":"main_beach","minimum_state_seq":owner.completed_state_seq,"points":[{"body_id":1,"point_id":1,"position":Vector3(.0625,0,.0625)}],"footprints":[Rect2(-1,-1,2,2)]}
	check("public_probe_admitted",owner.views.request_probe(request,probe_received).accepted)
	while probe_result.is_empty():await process_frame
	check("probe_complete_identity",probe_result.error.is_empty() and probe_result.captured_time_s==owner.advanced_time_s and probe_result.captured_state_seq==owner.completed_state_seq and probe_result.captured_revision==owner.completed_revision)
	if probe_result.error.is_empty():
		var p: Dictionary=probe_result.points[0];var index:=128*256+128;var h: float=captured.water.decode_float(index*4);var bed: float=captured.rock.decode_float(index*4)+captured.sand.decode_float(index*4);var qx: float=captured.momentum_x.decode_float(index*4);var qz: float=captured.momentum_z.decode_float(index*4)
		check("probe_final_water_bed_momentum",absf(p.h-h)<2e-6 and absf(p.bed-bed)<2e-6 and absf(p.eta-bed-h)<2e-6 and (p.u_xz-Vector2(qx,qz)/maxf(h,.005)).length()<2e-5)
	for i in 3:check("continuation_tick_admitted",owner.request_tick(1.0/30.0).is_empty());await idle()
	await save_state("continuation")
	await snapshot("after_continuation",true)
	owner.close_admission();RenderingServer.call_on_render_thread(owner.release_render)
	while not owner.released:await process_frame
	check("all_owners_released",owner.ownership_counts().values().all(func(value):return value==0));finish()
func finish() -> void:
	var drift: Array=[]
	for path in configuration.get("sources",{}):
		if FileAccess.get_sha256(path)!=configuration.sources[path]:drift.append(path)
	check("source_identity",drift.is_empty())
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"schema":1,"outcome":"fail" if failed else "pass","mode":mode,"checks":checks,"saved":saved_rows,"configuration":configuration,"scratch":initial_scratch,"snapshots":snapshots,"probe":probe_result,"source_drift":drift,"scope":"Real main RD with foam/gravel, actual save capture, cold source/resume processes; compare native files separately"},"\t"));quit(1 if failed else 0)
