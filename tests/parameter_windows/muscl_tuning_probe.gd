extends SceneTree

const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const Schema=preload("res://scripts/parameters/parameter_schema.gd")
var output:="res://test_output/muscl_gui_tuning/gpu"
var baseline:=""
var checks: Array=[]
var observations: Array=[]
var owner
var registry
var captured: Dictionary={}
var ready_capture:=false
var reference_done:=false
var reference_error:=""
var configuration_only:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--baseline="):baseline=arg.trim_prefix("--baseline=")
		if arg=="--configuration-only":configuration_only=true
	call_deferred("run")

func _process(_delta: float) -> bool:
	if owner!=null:owner.pump()
	return false

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed});print("MUSCL_TUNING ",label," ",passed)

func configuration_checks() -> void:
	for legacy in [{"schema":1,"solver_id":Config.Numerics.MUSCL},{"schema":2,"solver_id":Config.Numerics.MUSCL,"wave_retention":0.4}]:
		var env:={"water_numerics":legacy}
		check("legacy_defaults_"+str(legacy.schema),Config.Numerics.configuration_error(env).is_empty() and Config.Numerics.cfl(env)==0.2 and Config.Numerics.max_attempts(env)==64)
	var selected:=Config.Numerics.selection(Config.Numerics.MUSCL,0.4,0.3,32)
	check("schema3_valid",selected.schema==3 and Config.Numerics.configuration_error({"water_numerics":selected}).is_empty())
	for field in ["cfl","max_attempts"]:
		var invalids: Array=[0.0,-1.0,0.51,NAN,INF,true,"0.2"] if field=="cfl" else [0,65,1.5,32.0,true,"32"]
		for value in invalids:
			var invalid:=selected.duplicate();invalid[field]=value
			check("invalid_"+field+"_"+str(value),not Config.Numerics.configuration_error({"water_numerics":invalid}).is_empty())
	var extra:=selected.duplicate();extra.unknown=1
	check("unknown_numerics_key",not Config.Numerics.configuration_error({"water_numerics":extra}).is_empty())
	selected.solver_id=Config.Numerics.FIRST_ORDER
	check("schema3_muscl_only",not Config.Numerics.configuration_error({"water_numerics":selected}).is_empty())
	check("ui_ranges",Schema.valid("muscl_cfl",0.05) and Schema.valid("muscl_cfl",0.5) and not Schema.valid("muscl_cfl",0.51) and Schema.valid("muscl_max_attempts",1) and Schema.valid("muscl_max_attempts",64) and not Schema.valid("muscl_max_attempts",32.5))
	var flags:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var target:=Config.freeze(registry,"main_beach",flags,{"foam_enabled":false,"gravel_enabled":false},{},{"water_numerics":Config.Numerics.selection(Config.Numerics.MUSCL,0.0,0.3,32)},PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES))
	var migration=load("res://scripts/simulation/unified_edit/numerics_checkpoint_sources.gd")
	for source in [{},{"environment":false},{"environment":{"water_numerics":{"schema":3,"solver_id":Config.Numerics.MUSCL,"wave_retention":0.0,"cfl":"bad","max_attempts":32}}}]:
		check("invalid_migration_source",not migration.project({"configuration":source},target.value,"").error.is_empty())
	for field in ["cfl","max_attempts"]:
		var source: Dictionary=target.value.duplicate(true)
		source.environment.water_numerics[field]=0.4 if field=="cfl" else 48
		check("migration_rejects_"+field,migration.project({"configuration":source},target.value,"").error==&"numerics_tuning_mismatch")

func install_reference() -> void:
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string(baseline).trim_prefix("#[compute]")
	for name in ["muscl_math.glslinc","muscl_stats.glslinc"]:
		source.source_compute=source.source_compute.replace('#include "'+name+'"',FileAccess.get_file_as_string("res://shaders/simulation/muscl/"+name))
	var spirv: RDShaderSPIRV=owner.state.rd.shader_compile_spirv_from_source(source)
	reference_error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if reference_error.is_empty():
		var shader: RID=owner.water._own(owner.state.rd.shader_create_from_spirv(spirv))
		owner.water.kernels.rk_decide.pipeline=owner.water._own(owner.state.rd.compute_pipeline_create(shader))
	set_deferred("reference_done",true)

func capture_render() -> void:
	var result: Dictionary={}
	for name in ["water","momentum","sand","sediment","wetness","compaction","flux","mold_support"]:
		for i in 2:result[name+str(i)]=owner.state.rd.texture_get_data(owner.state.textures[name][i],0)
	result.decision=owner.state.rd.buffer_get_data(owner.water.decision)
	result.control=owner.state.rd.buffer_get_data(owner.transport.control)
	result.audit=owner.state.rd.buffer_get_data(owner.water.muscl.buffers.audit)
	result.trial_groups=owner.state.rd.buffer_get_data(owner.water.muscl.buffers.trial_indirect)
	result.accept_groups=owner.state.rd.buffer_get_data(owner.water.indirect)
	result.recorded_attempts=owner.water.muscl._recording.filter(func(stage):return stage.diagnostic_label=="decision_1").size()
	result.recorded_passes=owner.water.muscl._recording.size()
	capture_received.call_deferred(result)

func capture_received(value: Dictionary) -> void:
	captured=value;ready_capture=true

func fixture(label: String, cfl: float, attempts: int, original: bool=false, dynamic: bool=false) -> Dictionary:
	owner=Pipeline.new()
	var env:={"water_numerics":Config.Numerics.selection(Config.Numerics.MUSCL,0.0,cfl,attempts)}
	var flags:={"enable_erosion":dynamic,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var frozen:=Config.freeze(registry,"main_beach",flags,{"foam_enabled":false,"gravel_enabled":false},{},env,PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES))
	check(label+"_freeze",frozen.error.is_empty())
	if not frozen.error.is_empty():owner=null;return {}
	check(label+"_configure",owner.configure(registry,frozen.value,1).is_empty())
	var domain:=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1
	domain.sand.fill(0.4);domain.water.fill(0.5)
	if dynamic:
		for z in range(96,160):
			for x in range(96,160):
				var i:=z*256+x
				domain.sand[i]+=0.04*sin(float(x)*0.2)*cos(float(z)*0.17)
				domain.water[i]=0.025 if x<128 else 0.2
				domain.sediment[i]=0.001;domain.wetness[i]=0.3;domain.compaction[i]=0.95
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	var deadline:=Time.get_ticks_msec()+45000
	while not owner.initialized and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(label+"_initialized",owner.initialized and owner.fault_reason().is_empty())
	if not owner.initialized:return {}
	check(label+"_frozen_values",owner.state.muscl_cfl==cfl and owner.state.muscl_max_attempts==attempts)
	if original:
		reference_done=false;RenderingServer.call_on_render_thread(install_reference)
		while not reference_done and Time.get_ticks_msec()<deadline:await process_frame
		check(label+"_reference_compiled",reference_done and reference_error.is_empty())
	for tick in 3:
		check(label+"_admit_"+str(tick),owner.request_tick(1.0/30.0).is_empty())
		deadline=Time.get_ticks_msec()+30000
		while (owner.pending_count()>0 or owner.active_count()>0) and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(label+"_complete_"+str(tick),owner.completed_tick==tick+1 and owner.fault_reason().is_empty())
	ready_capture=false;RenderingServer.call_on_render_thread(capture_render)
	while not ready_capture and Time.get_ticks_msec()<deadline:await process_frame
	check(label+"_captured",ready_capture)
	var result:=captured.duplicate()
	check(label+"_recorded_budget",result.recorded_attempts==attempts)
	var d: PackedByteArray=result.decision
	check(label+"_bounded_attempts",d.decode_u32(4)+d.decode_u32(40)<=attempts)
	var tail_zero:=true
	for step in range(attempts,64):
		for word in 8:tail_zero=tail_zero and result.audit.decode_u32(step*32+word*4)==0
		for word in 3:tail_zero=tail_zero and result.trial_groups.decode_u32(step*12+word*4)==0 and result.accept_groups.decode_u32(step*12+word*4)==0
	check(label+"_unused_slots_reset",tail_zero)
	observations.append({"case":label,"cfl":cfl,"max_attempts":attempts,"accepted":d.decode_u32(4),"rejected":d.decode_u32(40),"status":d.decode_u32(16),"actual_dt":d.decode_float(12),"recorded_passes":result.recorded_passes,"configuration_hash":frozen.value.configuration_hash})
	owner.close_admission();RenderingServer.call_on_render_thread(owner.release_render)
	deadline=Time.get_ticks_msec()+30000
	while not owner.released and Time.get_ticks_msec()<deadline:await process_frame
	check(label+"_released",owner.released);owner=null
	return result

func run() -> void:
	registry=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry().registry
	configuration_checks()
	if configuration_only:
		finish();return
	if not baseline.is_empty():
		var before: Dictionary=await fixture("original",0.2,64,true,true)
		var after: Dictionary=await fixture("default",0.2,64,false,true)
		check("default_exact",not before.is_empty() and before==after)
	var normal: Dictionary=await fixture("flat_default",0.2,64)
	var smaller: Dictionary=await fixture("flat_cfl_010",0.1,64)
	var larger: Dictionary=await fixture("flat_cfl_040",0.4,64)
	check("cfl_controls_actual_substeps",smaller.decision.decode_u32(4)>normal.decision.decode_u32(4) and larger.decision.decode_u32(4)<normal.decision.decode_u32(4))
	var capped: Dictionary=await fixture("budget_1",0.2,1)
	check("budget_exhaustion_partial_time",capped.decision.decode_u32(16)==1 and capped.decision.decode_float(12)<1.0/30.0 and capped.decision.decode_u32(4)==1)
	var reduced: Dictionary=await fixture("budget_32",0.2,32)
	check("sufficient_budget_same_state",normal.water0==reduced.water0 and normal.momentum0==reduced.momentum0 and normal.control==reduced.control)
	check("budget_reduces_cpu_recording",capped.recorded_passes<reduced.recorded_passes and reduced.recorded_passes<normal.recorded_passes)
	finish()

func finish() -> void:
	var passed:=checks.all(func(row):return row.pass)
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks,"observations":observations,"engine":Engine.get_version_info().string,"driver":RenderingServer.get_current_rendering_driver_name(),"adapter":RenderingServer.get_video_adapter_name()},"\t"))
	quit(0 if passed else 1)
