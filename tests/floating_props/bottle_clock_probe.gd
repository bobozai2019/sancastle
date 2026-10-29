extends SceneTree

const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
var fixture
var runtime
var service
var body
var output:=""
var probe_case:="normal"
var ready:=false
var boot_error: StringName
var checks: Array=[]
var failed:=false
var observations: Dictionary={}
var producing:=false
var accumulator:=0.0
var slow_frame_injected:=false

func check(name: String, value: bool) -> void:checks.append({"name":name,"pass":value});failed=failed or not value;print("BOTTLE_CLOCK ",name," ",value)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--case="):probe_case=arg.trim_prefix("--case=")
	call_deferred("_run")

func _process(delta: float) -> bool:
	if producing and runtime!=null and runtime.ready_for_input():
		if probe_case=="slow_frame" and not slow_frame_injected and runtime.current.advanced_time_s>=1.0:OS.delay_msec(120);slow_frame_injected=true
		accumulator=minf(accumulator+delta,0.25)
		while accumulator>=1.0/30.0 and runtime.current.pending_count()<4:
			if not runtime.request_tick(1.0/30.0).is_empty():break
			accumulator-=1.0/30.0
	return false

func _booted(result: Dictionary) -> void:ready=true;boot_error=result.error

func _fixture_path() -> String:return "res://tests/floating_props/bottle_fixture.tscn"
func _extra_sources() -> PackedStringArray:return PackedStringArray()
func _configure_domain(_domain) -> void:pass
func _target_time() -> float:return 6.0 if probe_case in ["normal","deep","tipped"] else 4.0
func _extra_final_checks() -> void:pass
func _environment() -> Dictionary:return {"engine":Engine.get_version_info().string,"probe":probe_case}
func _configure_flags(flags: Dictionary) -> Dictionary:return flags
func _after_attach() -> void:pass
func _scenario_extension() -> Dictionary:return {}
func _capture_events() -> Array:return service.events.duplicate(true)
func _clock_error_budget() -> float:
	# Actual Jolt step is float32; admission delta is double 1/60. Allow its
	# accumulated representation error, independently reconstructed per quantum.
	return maxf(1e-6,service.admitted_time_s*1e-7)

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,720))
	fixture=load(_fixture_path()).instantiate();root.add_child(fixture)
	runtime=fixture.get_node("Runtime");service=fixture.get_node("Props");body=fixture.get_node("Bottle")
	check("CPU_GPU_dry_cutoff_exact",service.ProbeCodec.DRY_DEPTH_M==PackedFloat32Array([0.001])[0])
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	var flags:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	flags=_configure_flags(flags)
	var paths:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES+runtime.SOURCES)
	paths.append_array(PackedStringArray(["res://tests/floating_props/bottle_fixture.tscn","res://tests/floating_props/fixture_surface.gdshader","res://tests/floating_props/fixture_bed.gdshader","res://scenes/props/bottle.tscn","res://assets/props/bottle_profile.tres","res://scripts/props/floating_prop.gd","res://scripts/props/floating_prop_profile.gd","res://scripts/props/floating_props_service.gd"]))
	paths.append_array(_extra_sources())
	paths.append_array(PackedStringArray(service.SOURCES))
	var config:=Config.freeze(created.registry,"main_beach",flags,{"foam_enabled":false,"gravel_enabled":false},{},_environment(),paths)
	check("configuration",config.error.is_empty())
	if not config.error.is_empty():finish();return
	observations.sources=config.value.sources.duplicate(true)
	var domain:=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1;domain.sand.fill(0.4);domain.water.fill(0.8)
	if probe_case=="dry":domain.water.fill(0.0)
	if probe_case=="thin_dry":domain.water.fill(0.0005)
	if probe_case=="dry_cutoff":domain.water.fill(0.001)
	var q:=PackedFloat32Array();q.resize(65536)
	if probe_case=="flow_positive":q.fill(0.24)
	if probe_case=="flow_negative":q.fill(-0.24)
	if probe_case=="cfl":q[0]=10000.0
	domain.set_meta("edit_validation_initial_qx",q)
	_configure_domain(domain)
	var bindings: Array=[]
	for name in ["Bed","Water"]:bindings.append({"material":fixture.get_node(name).material_override,"parameters":{"rock_state":"rock","sand_state":"sand","water_state":"water"}})
	check("boot_admitted",runtime.boot(created.registry,config.value,domain,bindings,_booted).is_empty())
	var deadline:=Time.get_ticks_msec()+60000
	while not ready and Time.get_ticks_msec()<deadline:await process_frame
	check("real_RD_height_Jolt_ready",ready and boot_error.is_empty() and runtime.ready_for_input())
	if not runtime.ready_for_input():await _close();return
	var attach: Dictionary=await service.attach(runtime,service.authored_registry(),service.authored_layout())
	check("attach_and_initial_sample",attach.error.is_empty() and service._initialized_pose and body.freeze)
	if not attach.error.is_empty():await _close();return
	# Initial-condition fixtures change pose only while held, before any step.
	if probe_case=="deep":body.position.y-=0.1;service.sample={}
	if probe_case=="tipped":body.rotation.z=1.0;service.sample={}
	_after_attach()
	observations.profile=service.profiles.duplicate(true)
	observations.initial={"position":body.position,"rotation":body.rotation,"velocity":body.linear_velocity}
	if probe_case=="cfl":
		observations.cfl_clocks=[]
		for index in 20:
			check("CFL_tick_admitted_"+str(index),runtime.request_tick(1.0/30.0).is_empty())
			await _idle()
			observations.cfl_clocks.append({"tick":runtime.current.completed_tick,"time_s":runtime.current.advanced_time_s})
		check("actual_CFL_reduces_first_water_step",observations.cfl_clocks[0].time_s<1.0/30.0*0.5 and observations.cfl_clocks[0].time_s>0)
	else:
		producing=true
		var target:=_target_time()
		deadline=Time.get_ticks_msec()+45000
		while runtime.current.advanced_time_s<target and service.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		producing=false;accumulator=0.0
		check("real_water_target_reached",runtime.current.advanced_time_s>=target and service.last_error.is_empty())
	await _idle()
	if probe_case=="delay":await _delayed_window()
	if probe_case=="collision_delay":await _delayed_collision()
	if probe_case=="slow_frame":check("real_slow_frame_injected",slow_frame_injected)
	await _scenario_extension()
	var paused: Dictionary=await service.set_paused(true,&"user")
	await physics_frame;await physics_frame
	check("common_pause_boundary",paused.error.is_empty() and runtime.current.advanced_time_s-service.origin_time_s-service.admitted_time_s<1.0/60.0+1e-6)
	check("actual_Jolt_time_matches_admission",absf(service.actual_time[1]-service.admitted_time_s)<_clock_error_budget())
	check("no_ungranted_or_mismatched_physics_step",service.last_error.is_empty())
	var time_before: float=service.actual_time[1];var pose_before: Transform3D=body.global_transform
	for frame in 15:await physics_frame
	check("pause_no_hidden_gravity_or_wall_time_catchup",service.actual_time[1]==time_before and body.global_transform==pose_before)
	check("resume_accepted",(await service.set_paused(false,&"user")).error.is_empty())
	for frame in 10:await physics_frame
	check("resume_does_not_spend_pause_wall_time",service.actual_time[1]==time_before)
	check("post_pause_water_tick",runtime.request_tick(1.0/30.0).is_empty());await _idle()
	check("post_pause_common_boundary",(await service.set_paused(true,&"user")).error.is_empty())
	check("pause_result_settles_all_granted_records",service.expected_steps.is_empty() and absf(service.actual_time[1]-service.admitted_time_s)<_clock_error_budget())
	check("post_pause_only_real_budget_consumed",service.actual_time[1]-time_before<=1.0/30.0+1e-6)
	observations.final={"position":body.position,"rotation":body.rotation,"velocity":body.linear_velocity,"saved":service.saved.duplicate(true),"actual_time_s":service.actual_time.duplicate(true),"admitted_time_s":service.admitted_time_s,"advanced_time_s":runtime.current.advanced_time_s,"state_seq":runtime.current.completed_state_seq,"tick":runtime.current.completed_tick}
	var start: Transform3D=service.layout[1]
	if probe_case=="flow_positive":check("follows_positive_flow",body.position.x-start.origin.x>0.15 and service.saved[1].linear.x>0.08)
	elif probe_case=="flow_negative":check("follows_negative_flow",body.position.x-start.origin.x< -0.15 and service.saved[1].linear.x< -0.08)
	elif probe_case in ["normal","deep","tipped"]:check("stable_static_waterline",absf(body.position.y-1.245)<0.04 and absf(service.saved[1].linear.y)<0.08 and absf(body.rotation.z)<0.2)
	elif probe_case in ["dry","thin_dry","dry_cutoff"]:check("dry_settles_on_actual_sand_collision",body.position.y>0.47 and body.position.y<0.55 and absf(service.saved[1].linear.y)<0.05)
	_extra_final_checks()
	await RenderingServer.frame_post_draw
	check("visible_fixture_capture",root.get_texture().get_image().save_png(output.get_base_dir()+"/bottle.png")==OK)
	await _close()

func _delayed_window() -> void:
	var probe=runtime.current.views.probe;probe.hold_delivery=true
	var deadline:=Time.get_ticks_msec()+15000
	while probe.held.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("delayed_sample_really_inflight",probe.pending and not probe.held.is_empty())
	var old_time: float=service.last_sample_time_s
	for index in 10:
		check("producer_ignores_delayed_prop_"+str(index),runtime.request_tick(1.0/30.0).is_empty());await _idle()
	for frame in 15:await physics_frame
	check("delay_cannot_integrate_beyond_captured_time",service.actual_time[1]<=old_time-service.origin_time_s+1e-6 and body.freeze)
	var before: float=service.actual_time[1];var pose: Transform3D=body.global_transform
	for frame in 5:await physics_frame
	check("delay_hold_has_no_hidden_contact_or_gravity",service.actual_time[1]==before and body.global_transform==pose)
	probe.deliver_held()

func _delayed_collision() -> void:
	var heights=runtime.current.heights;heights.hold_physics=true
	var profile: Dictionary=runtime.registry.profile(&"fill_v1")
	var command:={"domain_id":String(runtime.configuration.domain_id),"generation":runtime.generation(),"command_id":runtime.highwater()+1,"sim_tick":runtime.current.completed_tick,"profile_id":&"fill_v1","profile_version":1,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(body.position.x,body.position.z),"parameters":{"amount_m3":0.01,"radius_m":0.75},"features":{"water_policy":0}}
	check("bed_edit_admitted_with_collision_held",runtime.submit_intent(command).accepted);await _idle()
	check("bed_edit_really_applied",runtime.current.result(command.command_id).get("outcome")==1)
	for index in 2:check("water_admitted_with_collision_held_"+str(index),runtime.request_tick(1.0/30.0).is_empty())
	await _idle()
	var waiting:=false;var deadline:=Time.get_ticks_msec()+15000
	while not waiting and Time.get_ticks_msec()<deadline:
		if not service.sample.is_empty():
			for chunk in service.sample.footprint_versions:
				if heights.applied_state_seq.get(chunk,-1)<service.sample.footprint_versions[chunk]:waiting=true
		if not waiting:await process_frame
	check("sample_requires_unapplied_relevant_bed_chunk",waiting)
	for frame in 5:await physics_frame
	var before: float=service.actual_time[1];var pose: Transform3D=body.global_transform
	for frame in 5:await physics_frame
	check("collision_delay_holds_physics_without_blocking_water",body.freeze and service.actual_time[1]==before and body.global_transform==pose and runtime.current.completed_tick>120)
	observations.collision_delay={"required":service.sample.get("footprint_versions",{}).duplicate(),"applied_before":heights.applied_state_seq.duplicate(),"state_seq":runtime.current.completed_state_seq}
	heights.hold_physics=false

func _idle() -> void:
	var deadline:=Time.get_ticks_msec()+15000
	while (runtime.current.active_count()!=0 or runtime.current.pending_count()!=0) and Time.get_ticks_msec()<deadline:await process_frame
	check("producer_idle_"+str(checks.size()),runtime.current.active_count()==0 and runtime.current.pending_count()==0)

func _close() -> void:
	if service.active:
		var result: Dictionary=await service.shutdown();check("service_reader_shutdown",result.error.is_empty() and service.closed and not service.pending)
	observations.events=_capture_events()
	runtime.shutdown()
	var deadline:=Time.get_ticks_msec()+20000;var retry_at:=Time.get_ticks_msec()
	while not runtime.closed and Time.get_ticks_msec()<deadline:
		if Time.get_ticks_msec()-retry_at>500:runtime.retry_retirement();retry_at=Time.get_ticks_msec()
		await process_frame
	check("public_runtime_closed",runtime.closed)
	root.remove_child(fixture);fixture.free();finish()

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"observations":observations,"engine":Engine.get_version_info(),"scope":"G2 development fixture; only individual executed checks apply"},"\t"));quit(1 if failed else 0)
