extends SceneTree

const Gravel = preload("res://scripts/visual/gpu_gravel_field.gd")
class InputField extends RefCounted:
	var rd: RenderingDevice
	var grid_size := 32
	var cell_size_m := 0.125
	var current_index := 0
	var textures := {}

var solver := InputField.new()
var gravel
var spirv: RDShaderSPIRV
var finished := false
var captured := {}
var action_result: Variant
var checks := []
var traces := []
var output := "res://test_output/gpu_gravel/transport_" + str(Time.get_unix_time_from_system()).replace(".","_")
var current_profile := {}

func _initialize() -> void:
	_run.call_deferred()

func _complete(value: Variant) -> void:
	action_result = value
	finished = true

func _render_action(operation: String, args: Array) -> void:
	var result: Variant = true
	match operation:
		"setup":
			solver.rd = RenderingServer.get_rendering_device()
			var source := RDShaderSource.new()
			source.source_compute = FileAccess.get_file_as_string("res://shaders/simulation/visual_gravel_step.glsl").replace("#[compute]", "")
			spirv = solver.rd.shader_compile_spirv_from_source(source)
			var compile_error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
			if not compile_error.is_empty():
				_complete.call_deferred(compile_error)
				return
			for field in ["rock","sand","water","momentum_x","momentum_z"]:
				var format := RDTextureFormat.new()
				format.width = solver.grid_size
				format.height = solver.grid_size
				format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
				format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
				var data := PackedFloat32Array()
				data.resize(solver.grid_size*solver.grid_size)
				data.fill(0.0)
				var rid := solver.rd.texture_create(format,RDTextureView.new(),[data.to_byte_array()])
				solver.textures[field] = rid if field == "rock" else [rid,rid]
		"inputs":
			for field in ["rock","sand","water","momentum_x","momentum_z"]:
				var data := PackedFloat32Array()
				data.resize(solver.grid_size*solver.grid_size)
				data.fill(float(args[0].get(field,0.0)))
				if args[0].get("dry_band",false) and field == "water":
					for z in solver.grid_size:
						# Two fully dry cells beyond x=0.0625; max step = 0.0625.
						for x in range(17,19): data[z*solver.grid_size+x] = 0.0
				if args[0].get("slope",false) and field == "rock":
					for z in solver.grid_size:
						for x in solver.grid_size: data[z*solver.grid_size+x] = (x+0.5)*0.125-2.0
				var rid: RID = solver.textures[field] if field == "rock" else solver.textures[field][0]
				solver.rd.texture_update(rid,0,data.to_byte_array())
		"new":
			if gravel != null: gravel.release()
			gravel = Gravel.new()
			var restore := {}
			if args.size() > 1:
				var state := PackedFloat32Array()
				state.resize(4096)
				state.fill(0.0)
				for id in args[0].count:
					for k in 4: state[id*4+k] = args[1][k]
				restore = {"state_0":state.to_byte_array(),"state_1":state.to_byte_array(),"current_index":0}
			result = gravel.initialize(solver,spirv,args[0],1,0,0,restore)
		"advance": result = gravel.advance(solver,args[0],args[1],args[2],args[3])
		"reproject": result = gravel.reproject(solver,args[0],args[1],args[2])
		"snapshot":
			captured.clear()
			gravel.capture_async(_capture,1)
			return
		"release":
			result = gravel.release()
			for field in solver.textures:
				var rid: RID = solver.textures[field] if field == "rock" else solver.textures[field][0]
				solver.rd.free_rid(rid)
	_complete.call_deferred(result)

func _capture(bytes: PackedByteArray, key: String, identity: Dictionary) -> void:
	_receive.call_deferred(bytes,key,identity)

func _receive(bytes: PackedByteArray, key: String, identity: Dictionary) -> void:
	captured[key] = bytes
	if captured.size() == 2:
		_complete({"state_0":captured.state_0,"state_1":captured.state_1,"current_index":gravel.current_index,"tick":identity.tick,"revision":identity.revision,"generation":identity.generation,"microsteps":gravel.last_microsteps,"cap":gravel.last_effective_cap,"cap_events":gravel.cap_events,"pending":gravel.pending})

func _action(operation: String, args := []) -> Variant:
	finished = false
	RenderingServer.call_on_render_thread(_render_action.bind(operation,args))
	var deadline := Time.get_ticks_msec()+15000
	while not finished and Time.get_ticks_msec()<deadline: await process_frame
	if not finished: push_error("GPU probe timed out: "+operation); quit(2)
	return action_result

func _snapshot(label: String) -> Dictionary:
	var state: Dictionary = await _action("snapshot")
	var values: PackedFloat32Array = state["state_%d" % state.current_index].to_float32_array()
	state["p"] = Array(values.slice(0,4))
	traces.append({"label":label,"p":state.p,"tick":state.tick,"revision":state.revision,"generation":state.generation,"microsteps":state.microsteps,"cap":state.cap,"cap_events":state.cap_events})
	return state

func _check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"pass":passed,"detail":detail})
	print("GRAVEL_CHECK ",label," ",passed)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var setup: Variant = await _action("setup")
	if setup is String: print(setup); quit(1); return
	current_profile = Gravel.default_profile("main",1)
	current_profile.spawn_bounds_xz = [-0.1,-0.1,0.1,0.1]
	current_profile.response_min = 0.5
	current_profile.response_max = 0.5
	await _action("inputs",[{"rock":0.5,"sand":0.2,"water":0.1,"momentum_x":0.1}])
	_check("create",await _action("new",[current_profile,[0.0,0.7,0.0,0.0]]))
	_check("advance",await _action("advance",[1,0,1,1.0/30.0]))
	var state := await _snapshot("uniform_flow")
	_check("known_displacement",absf(state.p[0]-0.5/30.0)<1e-5 and absf(state.p[1]-0.7)<1e-5 and state.p[3]==1.0,state.p)
	for tick in range(2,31): await _action("advance",[tick,0,1,1.0/30.0])
	state = await _snapshot("one_second")
	_check("accumulated_displacement",absf(state.p[0]-0.5)<1e-4,state.p)
	var held := state.duplicate(true)
	_check("duplicate_advance",await _action("advance",[30,0,1,1.0/30.0]))
	state = await _snapshot("duplicate")
	_check("duplicate_bytes",held.state_0==state.state_0 and held.state_1==state.state_1)
	_check("old_generation_rejected",not await _action("advance",[31,0,0,1.0/30.0]))
	await _action("inputs",[{"rock":0.9,"sand":0.2,"water":0.0,"momentum_x":0.1}])
	await _action("advance",[31,1,1,1.0/30.0])
	state = await _snapshot("dry_residual_q")
	_check("dry_stops_and_follows_bed",state.p[0]==held.p[0] and state.p[3]==0.0 and absf(state.p[1]-1.1)<1e-5,state.p)
	held = state.duplicate(true)
	await _action("inputs",[{"water":0.1,"momentum_x":0.0}])
	await _action("advance",[32,1,1,1.0/30.0])
	state = await _snapshot("wet_zero_flow")
	_check("rewet_zero_flow_stops",state.p[0]==held.p[0] and state.p[3]==1.0)
	await _action("inputs",[{"water":0.1,"momentum_x":-0.1}])
	await _action("advance",[33,1,1,1.0/30.0])
	state = await _snapshot("rewet_reverse")
	_check("rewet_reverse_moves",absf(state.p[0]-(held.p[0]-0.5/30.0))<1e-5,state.p)
	held = state.duplicate(true)
	await _action("inputs",[{"rock":1.2,"water":0.009,"momentum_x":0.1}])
	await _action("reproject",[33,2,1])
	state = await _snapshot("paused_edit")
	_check("edit_no_time_step",state.p[0]==held.p[0] and state.tick==33 and absf(state.p[1]-1.2)<1e-5)
	_check("wet_hysteresis",state.p[3]==1.0)
	await _action("inputs",[{"water":0.005,"momentum_x":0.1}])
	await _action("reproject",[33,3,1])
	await _action("inputs",[{"water":0.009,"momentum_x":0.1}])
	await _action("reproject",[33,4,1])
	state = await _snapshot("dry_hysteresis")
	_check("dry_hysteresis",state.p[3]==0.0)
	await _action("inputs",[{"water":0.1,"momentum_x":0.006}])
	await _action("new",[current_profile,[0.0,0.0,0.0,1.0]])
	await _action("advance",[1,0,1,1.0/30.0])
	state = await _snapshot("speed_ramp")
	_check("speed_smooth_midpoint",absf(state.p[0]-0.5*0.06*0.5/30.0)<1e-5,state.p)
	await _action("inputs",[{"water":0.1,"momentum_x":0.003}])
	await _action("advance",[2,0,1,1.0/30.0])
	var slow := await _snapshot("speed_below_off")
	_check("speed_below_off_stops",slow.p[0]==state.p[0])
	await _action("inputs",[{"water":0.1,"momentum_x":100.0,"slope":true}])
	await _action("new",[current_profile,[1.99,0.0,0.0,1.0]])
	await _action("advance",[1,0,1,1.0/30.0])
	state = await _snapshot("boundary_slope")
	_check("boundary_and_moved_bed",state.p[0]==2.0 and absf(state.p[1]-1.9375)<1e-5)
	await _action("new",[current_profile,[0.0,0.0,0.0,1.0]])
	await _action("advance",[1,0,1,1.0])
	state = await _snapshot("large_dt_cap")
	_check("microstep_cap_accounted",state.microsteps==8 and state.cap_events==1 and absf(state.cap-1.0)<1e-5 and absf(state.p[0]-0.5)<1e-5,state.p)
	await _action("inputs",[{"water":0.1,"momentum_x":100.0,"dry_band":true}])
	await _action("new",[current_profile,[0.0,0.0,0.0,1.0]])
	await _action("advance",[1,0,1,1.0])
	state = await _snapshot("thin_dry_band")
	_check("microsteps_stop_in_dry_band",state.p[0] < 0.375 and state.p[3]==0.0,state.p)
	await _action("inputs",[{"water":0.1,"momentum_x":0.1}])
	for count in [0,512,1024]:
		var values := Gravel.default_profile("main",count)
		values.spawn_bounds_xz = [-1.0,-1.0,1.0,1.0]
		_check("capacity_create_%d" % count,await _action("new",[values]))
		var initial := await _snapshot("capacity_init_%d" % count)
		_check("initial_ping_pong_equal_%d" % count,initial.state_0==initial.state_1)
		await _action("advance",[1,0,1,1.0/30.0])
		state = await _snapshot("capacity_step_%d" % count)
		var floats: PackedFloat32Array = state["state_%d" % state.current_index].to_float32_array()
		var valid := true
		for id in 1024:
			for k in 4: valid = valid and is_finite(floats[id*4+k])
			valid = valid and absf(floats[id*4])<=2.0 and absf(floats[id*4+2])<=2.0 and floats[id*4+3] in [0.0,1.0]
			if id>=count:
				for k in 4: valid = valid and floats[id*4+k]==0.0
		_check("capacity_finite_%d" % count,valid)
		await _action("new",[values])
		var repeated := await _snapshot("capacity_repeat_%d" % count)
		_check("seed_determinism_%d" % count,initial.state_0==repeated.state_0 and initial.state_1==repeated.state_1)
	var invalid := current_profile.duplicate(true)
	invalid.h_epsilon_m = 0.0
	_check("invalid_profile_rejected",not Gravel.validate_profile(invalid,32,0.125).is_empty())
	_check("pending_drained",gravel.pending==0)
	_check("release",await _action("release"))
	var passed := true
	for check in checks: passed = passed and check.pass
	var report := {"pass":passed,"checks":checks,"driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"profile":current_profile,"shader_sha256":FileAccess.get_sha256("res://shaders/simulation/visual_gravel_step.glsl"),"field_sha256":FileAccess.get_sha256("res://scripts/visual/gpu_gravel_field.gd"),"probe_sha256":FileAccess.get_sha256("res://tests/gravel/gravel_transport_probe.gd"),"single_step_tolerance_m":1e-5,"accumulated_tolerance_m":1e-4,"grid":32,"cell_m":0.125,"authoritative_solver_advanced":false}
	var compiled: PackedByteArray=spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(compiled)
	report.compiled_compute_sha256=hash.finish().hex_encode()
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	var trace := FileAccess.open(output.path_join("trace.jsonl"),FileAccess.WRITE)
	for row in traces: trace.store_line(JSON.stringify(row))
	print("GRAVEL_TRANSPORT_COMPLETE ",passed," OUTPUT ",output)
	quit(0 if passed else 1)
