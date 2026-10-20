extends SceneTree

# Read-only diagnosis of the production solver; only diagnostic initial states
# and commands are supplied. Never patches production shaders or source files.
const Pipeline = preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Config = preload("res://scripts/simulation/unified_edit/configuration.gd")
const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Brush = preload("res://scripts/simulation/brushes/brush_protocol.gd")
var owner
var scene
var output := ""
var mode := "flat"
var cases: Array = []
var current: Dictionary = {}
var captured: Dictionary = {}
var reading := false
var failed := false
var checks: Array = []
var sources: Dictionary = {}
var started := 0
var fixture: Dictionary = {}
var selected: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://test_output/wave_propagation/g0_baseline_20261020/fixture.json"))
	started = Time.get_ticks_msec()
	call_deferred("run")

func _process(_delta: float) -> bool:
	if scene == null and owner != null: owner.pump()
	if Time.get_ticks_msec() - started > 900000:
		push_error("wave diagnostic timeout")
		quit(2)
	return false

func check(label: String, ok: bool) -> void:
	checks.append({"label":label,"pass":ok})
	failed = failed or not ok
	if not ok: push_error(label)

func idle() -> void:
	var began := Time.get_ticks_msec()
	while owner.pending_count() > 0 or owner.active_count() > 0 or (scene != null and not scene.input.waiting.is_empty()):
		if not owner.fault_reason().is_empty() or Time.get_ticks_msec() - began > 30000:
			check("idle:" + String(owner.fault_reason()),false)
			return
		await process_frame
	check("idle", owner.fault_reason().is_empty())

func read_render() -> void:
	var result: Dictionary = {}
	for field in ["rock","sand","water","momentum_x","momentum_z","sediment"]:
		var rid: RID = owner.state.textures[field] if field == "rock" else owner.state.textures[field][0]
		result[field] = owner.state.rd.texture_get_data(rid,0)
	var equal_views := true
	for field in ["sand","water","momentum_x","momentum_z"]:
		equal_views = equal_views and result[field] == owner.state.rd.texture_get_data(owner.views.textures[field],0)
	result["published_matches"] = equal_views
	result["control"] = owner.state.rd.buffer_get_data(owner.transport.control)
	result["decision"] = owner.state.rd.buffer_get_data(owner.water.decision)
	read_done.call_deferred(result)

func read_done(value: Dictionary) -> void:
	captured = value
	reading = false

func snapshot(label: String) -> void:
	await idle()
	reading = true
	RenderingServer.call_on_render_thread(read_render)
	while reading: await process_frame
	var folder: String = output.path_join(current.id)
	DirAccess.make_dir_recursive_absolute(folder)
	var record := {"label":label,"time_s":owner.advanced_time_s,"tick":str(owner.completed_tick),"revision":str(owner.completed_revision),"state_seq":str(owner.completed_state_seq),"generation":str(owner._generation),"published_matches":captured.published_matches,"fields":{}}
	for field in captured:
		if field == "published_matches": continue
		var path: String = folder.path_join(label + "_" + field + ".bin")
		FileAccess.open(path,FileAccess.WRITE).store_buffer(captured[field])
		record.fields[field] = {"path":path,"sha256":FileAccess.get_sha256(path),"bytes":captured[field].size()}
	current.snapshots.append(record)
	check("publication:" + current.id + ":" + label, captured.published_matches)
	print("WAVE_SNAPSHOT ",current.id," ",label," t=",owner.advanced_time_s)

func advance_and_capture() -> void:
	for target in fixture.sample_ticks:
		if target == 0: continue
		while owner.completed_tick < target:
			var count: int = mini(3,target-owner.completed_tick)
			for step in count: check("request_tick",owner.request_tick(1.0/30.0).is_empty())
			await idle()
			if failed: return
		await snapshot("tick_%03d" % target)

func boot_flat(kind: String, wavelength: float = 1.0) -> void:
	var catalog: Dictionary = load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	var simulation := {"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extra := PackedStringArray(Pipeline.SOURCE_PATHS + Pipeline.ADAPTER_SOURCES)
	extra.append("res://tools/wave_propagation/baseline_probe.gd")
	var config := Config.freeze(catalog.registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"boundary":{"enabled":false}},extra)
	check("configuration",config.error.is_empty())
	if failed: return
	sources.merge(config.value.sources)
	owner = Pipeline.new()
	check("configure",owner.configure(catalog.registry,config.value,1001).is_empty())
	var domain = Domain.new(256,0.125)
	domain.domain_id = &"main_beach"
	domain.generation = 1001
	domain.sand.fill(0.4)
	domain.water.fill(float(selected.get("depth", 0.1)))
	var qx := PackedFloat32Array()
	qx.resize(65536)
	for z in 256:
		for x in 256:
			var p := (Vector2(x,z) + Vector2.ONE*0.5 - Vector2.ONE*128.0)*0.125
			var eta := 0.0
			if kind == "sine": eta = float(selected.get("amplitude", 0.0001)) * sin(TAU*p.x/wavelength)
			if kind == "pulse": eta = -0.005 * exp(-p.length_squared()/(2.0*0.25*0.25))
			domain.water[z*256+x] += eta
			if kind == "sine": qx[z*256+x] = sqrt(9.81*float(selected.get("depth", 0.1)))*eta
	domain.set_meta("edit_validation_initial_qx",qx)
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	var began := Time.get_ticks_msec()
	while not owner.initialized and owner.initialization_error.is_empty() and Time.get_ticks_msec()-began<60000: await process_frame
	check("initialized:" + String(owner.initialization_error),owner.initialized and owner.fault_reason().is_empty())
	current.configuration = config.value
	current.fixture = selected.duplicate(true)
	current.initial_condition = {"kind":kind,"wavelength_m":wavelength,"mean_depth_m":float(selected.get("depth",0.1)),"amplitude_m":float(selected.get("amplitude",0.0001)) if kind=="sine" else 0.005,"sigma_m":0.25,"grid_size":256,"cell_size_m":0.125}

func flat_shovel(speed: float) -> void:
	var identity := {"domain_id":"main_beach","generation":1001,"command_id":1,"sim_tick":0,"stroke_id":7001,"baseline_token":7001}
	check("shovel_begin",owner.submit_control("begin",identity).accepted)
	var command := Brush.make_command(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2(0,-0.5),Vector2(0,0.5),&"main_beach",1001,2,7001,0,0,7001)
	command.material_profile_id = &"plain_sand_v1"
	# Schema-2 reads the envelope, not submit_legacy's schema-1 defaults.
	command.water_policy = 2
	command.speed_m_s = speed
	check("shovel_command",owner.submit_legacy(command,2,speed).accepted)
	identity.command_id = 3
	check("shovel_end",owner.submit_control("end",identity).accepted)
	await idle()
	current.tool = {"policy":2,"speed_m_s":speed,"command":command,"result":owner.result(2)}
	check("shovel_applied",owner.result(2).get("outcome",-1)==Pipeline.L.Outcome.APPLIED)
	check("shovel_no_connected_displacement",owner.result(2).get("displaced_water_m3",-1.0)==0.0)

func finish_flat() -> void:
	owner.close_admission()
	RenderingServer.call_on_render_thread(owner.release_render)
	var began := Time.get_ticks_msec()
	while not owner.released and Time.get_ticks_msec()-began<15000: await process_frame
	check("released",owner.released)
	owner = null

func run_flat() -> void:
	for spec in fixture.cases:
		selected = spec
		current = {"id":spec.id,"snapshots":[]}
		await boot_flat(spec.kind, float(spec.wavelength))
		if failed: return
		await snapshot("before")
		if spec.kind == "shovel":
			await flat_shovel(float(spec.speed))
			await snapshot("edited")
		await advance_and_capture()
		cases.append(current)
		await finish_flat()
		if failed: return

func run_main() -> void:
	var packed = load("res://scenes/main.tscn")
	check("main_scene_loaded", packed is PackedScene)
	if failed: return
	scene = packed.instantiate()
	scene.playing = false
	root.add_child(scene)
	var began := Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-began<90000: await process_frame
	check("main_ready:" + String(scene.last_error),scene.ready_for_ticks and scene.last_error.is_empty())
	if failed: return
	owner = scene.runtime.current
	sources.merge(scene.configuration.sources)
	var save_path := output.path_join("main_initial.sandue")
	check("save",(await scene.save_gpu_checkpoint(save_path)).is_empty())
	for kind in ["main_control","main_shovel"]:
		if kind != "main_control":
			check("restore",(await scene.restore_gpu_checkpoint(save_path)).is_empty())
			owner = scene.runtime.current
		current = {"id":kind,"snapshots":[],"configuration":scene.configuration,"camera":str(scene.player_camera.global_transform)}
		await snapshot("before")
		if kind == "main_shovel":
			var parameters := {"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5}
			check("main_begin",scene.input.begin(&"shovel_v1",Vector2(0,-0.5),parameters,0.1,2,0.25).accepted)
			check("main_move",scene.input.move(Vector2(0,0.5)).accepted)
			check("main_end",scene.input.finish().accepted)
			await idle()
			current.tool = {"start":[0,-0.5],"end":[0,0.5],"parameters":parameters,"policy":2,"speed_m_s":0.25,"terminals":scene.input.terminal.duplicate(true)}
			await snapshot("edited")
		await advance_and_capture()
		cases.append(current)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(kind+"_4s.png"))
		if failed: break
	await scene.shutdown()
	check("main_released",scene.unified_release_complete())
	var service = root.get_node("BeachScenes")
	if service.active_scene == scene: service.active_scene = null
	root.remove_child(scene)
	scene.free()
	scene = null
	owner = null

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_size(Vector2i(1280,720))
	DisplayServer.window_set_title("Water propagation diagnosis - " + mode)
	if mode == "main": await run_main()
	else: await run_flat()
	var drift: Array = []
	for path in sources:
		if FileAccess.get_sha256(path) != sources[path]: drift.append(path)
	check("source_integrity",drift.is_empty())
	FileAccess.open(output.path_join("diagnosis.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"mode":mode,"checks":checks,"cases":cases,"source_hashes":sources,"source_drift":drift,"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"fixture":fixture,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Production shader/pipeline numerical diagnosis, fixed initial state and manually requested ticks; diagnostic readbacks are not a performance measurement. Main case uses real scene and input adapter, props remain user-paused; no current user save is inspected or changed."},"\t"))
	quit(1 if failed else 0)
