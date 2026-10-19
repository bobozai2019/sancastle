extends Node3D
const Runtime = preload("res://tests/water_momentum_lab/lab_runtime.gd")
var runtime
var display := Texture2DRD.new()
var busy := true
var paused := false
var closing := false
var generation := 1
var mode := 2
var fixture := "flat"
var grid := 256
var gain := 1.0
var radius := .75
var depth := .2
var operation := 0
var commands: Array[Dictionary] = []
var accepted: Array = []
var rejected: Array = []
var rows: Array = []
var frames: Array = []
var latest := PackedFloat32Array()
var last_field := PackedByteArray()
var last_sediment := PackedByteArray()
var requested_mode := -1
var requested_fixture := ""
var profile := {}
var template_id := ""
var template_hash := ""
var manual_input_us := 0
var command_id := 0
var last_id := 0
var stroke_id := 0
var sample_id := 0
var last_sample := -1
var dragging := false
var stroke_start := Vector2.ZERO
var stroke_previous := Vector2.ZERO
var active_origin := Vector2.ZERO
var manual_pending := Vector2.INF
var reset_pending := false
var step_pending := 0
var snapshot_pending := false
var export_pending := false
var run_dir := ""
var last_error := ""
var release_count := 0
var auto := ""
var test_runner
var job_started_us := 0
var command_age_us := 0
signal completed
signal reset_done

func _ready() -> void:
	get_tree().auto_accept_quit=false
	profile=JSON.parse_string(FileAccess.get_file_as_string("res://tests/water_momentum_lab/profiles/default.json"))
	template_id=profile.template_id
	template_hash=FileAccess.get_sha256("res://tests/water_momentum_lab/shaders/edit.glsl")
	gain=profile.impulse_gain_m_s
	radius=profile.radius_m
	depth=profile.edit_depth_m
	grid=profile.grid
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-auto="):auto=arg.get_slice("=",1)
		if arg.begins_with("--lab-grid="):grid=int(arg.get_slice("=",1))
		if arg.begins_with("--lab-out="):run_dir=arg.get_slice("=",1)
	if grid not in [64,256]:
		push_error("invalid grid: lab supports 64 or 256")
		get_tree().quit(2)
		return
	if run_dir.is_empty():run_dir="res://test_output/water_momentum_lab/manual_"+Time.get_datetime_string_from_system().replace(":","_")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir))
	$Sand.material_override.set_shader_parameter("state",display)
	$Water.material_override.set_shader_parameter("state",display)
	if not auto.is_empty():paused=true
	RenderingServer.call_on_render_thread(_initialize)

func _initialize() -> void:
	runtime=Runtime.new()
	var device := RenderingServer.get_rendering_device()
	if device==null:
		call_deferred("_failure","RenderingDevice unavailable")
		return
	runtime.initialize(device,grid,fixture)
	runtime.profile_detail=auto=="cost_detail"
	runtime.identity="g%d_m%d_"%[generation,mode]
	call_deferred("_initialized",runtime.tex.display)

func _initialized(texture: RID) -> void:
	display.texture_rd_rid=texture
	$Sand.material_override.set_shader_parameter("state",display)
	$Water.material_override.set_shader_parameter("state",display)
	$Interface/Panel/Rows/Mode.select(mode)
	$Interface/Panel/Rows/Fixture.select(["flat","thin","islands","wall","platform20","platform80","wave"].find(fixture))
	busy=false
	reset_done.emit()
	if not auto.is_empty() and not has_meta("auto_started"):
		set_meta("auto_started",true)
		test_runner=load("res://tests/water_momentum_lab/tests/suite.gd").new()
		test_runner.run(self,auto)

func _process(delta: float) -> void:
	frames.append({"at_us":Time.get_ticks_usec(),"ms":delta*1000.,"generation":generation,"mode":mode,"queue":commands.size()})
	if frames.size()>40000:frames.pop_front()
	$Interface/Panel/Rows/Status.text="%s | %s | gen %d | t %.3fs | tick %d\nwater %.4fm³ | speed %.3fm/s | queue %d | %s" % [["A0 natural","A1 raised-bed formula","B signed impulse"][mode],fixture,generation,latest[20] if latest.size()>20 else 0.,int(latest[21]) if latest.size()>21 else 0,latest[0] if latest.size()>0 else 0.,latest[5] if latest.size()>5 else 0.,commands.size(),last_error if not last_error.is_empty() else ("paused" if paused else "running")]
	if busy:return
	if closing:
		_shutdown()
		return
	if reset_pending:
		reset_pending=false
		_reset()
		return
	if export_pending:
		export_pending=false
		export_run()
	if not last_error.is_empty():return
	if manual_pending.is_finite():
		var point := manual_pending
		manual_pending=Vector2.INF
		_queue_manual(point)
	if commands.is_empty() and paused and step_pending==0 and not snapshot_pending:return
	var command: Dictionary = {} if commands.is_empty() else commands.pop_front()
	if not command.is_empty() and command.operation==2 and latest.size()>15 and -latest[15]<absf(command.depth):
		rejected.append({"error":"insufficient_sand_at_execution","id":command.id,"generation":generation})
		command={}
	var steps := mini(step_pending,1) if paused else 4
	step_pending=maxi(0,step_pending-steps)
	var full := snapshot_pending
	snapshot_pending=false
	_submit(command,steps,full)

func _submit(command: Dictionary, steps: int, full: bool) -> void:
	busy=true
	job_started_us=Time.get_ticks_usec()
	command_age_us=0 if command.is_empty() else job_started_us-int(command.queued_us)
	var gen := generation
	RenderingServer.call_on_render_thread(func():runtime.job(command,steps,func(bytes,info):call_deferred("_finished",bytes,info,gen,command),full))

func _finished(bytes: PackedByteArray, info: Dictionary, gen: int, command: Dictionary) -> void:
	if gen!=generation:
		_failure("stale_generation callback")
		return
	latest=bytes.to_float32_array()
	if info.has("field"):last_field=info.field
	if info.has("sediment"):last_sediment=info.sediment
	info.erase("field")
	info.erase("sediment")
	info.merge({"generation":generation,"mode":mode,"fixture":fixture,"completed_us":Time.get_ticks_usec(),"latency_us":Time.get_ticks_usec()-job_started_us,"command_age_us":command_age_us,"queue":commands.size(),"command_id":command.get("id",0),"metrics":Array(latest)})
	rows.append(info)
	busy=false
	if latest.size()!=32 or latest[3]!=0.:
		_failure("nonfinite_state")
	completed.emit()

func enqueue(command: Dictionary) -> String:
	var error := ""
	for key in ["generation","id","stroke","sample","target_tick","mode","operation","input_us"]:
		if not command.has(key) or not command[key] is int or command[key]<0:error="invalid_input"
	if not error.is_empty():pass
	elif closing or reset_pending:error="reset_pending"
	elif command.get("generation",-1)!=generation:error="stale_generation"
	elif command.get("id",-1)<=last_id:error="out_of_order"
	elif command.get("stroke",-1)<stroke_id:error="out_of_order"
	elif command.get("stroke",-1)==stroke_id and command.get("sample",-1)<=last_sample:error="duplicate_sample"
	elif commands.size()>=64:error="queue_full"
	else:
		for key in ["a","b","origin_xz"]:
			if not command.has(key) or not command[key] is Vector2 or not command[key].is_finite():error="invalid_input"
		for key in ["radius","depth","gain"]:
			if not command.has(key) or typeof(command[key]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(command[key])):error="invalid_input"
		if error.is_empty():
			if command.get("template_id","")!=template_id or command.get("template_hash","")!=template_hash:error="invalid_template"
			elif command.stroke==stroke_id and command.origin_xz!=active_origin:error="invalid_input"
			elif command.radius<.25 or command.radius>2. or absf(command.depth)>.2 or command.gain<0. or command.gain>4. or command.mode!=mode or command.operation not in [0,1,2]:error="invalid_input"
			elif command.target_tick>(int(latest[21]) if latest.size()>21 else 0):error="future_tick"
			elif command.operation==2:
				var margin: float = command.radius*3.
				var limit: float = grid*.125*.5-margin
				if absf(command.a.x)>limit or absf(command.a.y)>limit or absf(command.b.x)>limit or absf(command.b.y)>limit or not is_equal_approx(command.radius/.125,round(command.radius/.125)):error="invalid_input"
				elif not commands.is_empty():error="transfer_backpressure"
				elif latest.size()>15 and -latest[15]<absf(command.depth):error="insufficient_sand"
	if not error.is_empty():
		rejected.append({"error":error,"id":command.get("id",-1),"generation":generation})
		return error
	last_id=command.id
	if command.stroke!=stroke_id:
		stroke_id=command.stroke
		last_sample=-1
		active_origin=command.origin_xz
	command.first=last_sample==-1
	last_sample=command.sample
	command.queued_us=Time.get_ticks_usec()
	command.a_m=[command.a.x,command.a.y]
	command.b_m=[command.b.x,command.b.y]
	command.origin_m=[command.origin_xz.x,command.origin_xz.y]
	commands.append(command.duplicate())
	accepted.append(command.duplicate())
	return ""

func make_command(a: Vector2,b: Vector2,op: int=0,first: bool=true) -> Dictionary:
	command_id=maxi(command_id,last_id)+1
	if first:sample_id=0
	else:sample_id+=1
	return {"generation":generation,"id":command_id,"stroke":stroke_id+int(first),"sample":sample_id,"a":a,"b":b,"origin_xz":a if first else active_origin,"radius":radius,"depth":depth if op!=0 else -depth,"gain":gain,"mode":mode,"operation":op,"target_tick":int(latest[21]) if latest.size()>21 else 0,"template_id":template_id,"template_hash":template_hash,"input_us":Time.get_ticks_usec(),"a_m":[a.x,a.y],"b_m":[b.x,b.y],"origin_m":[a.x,a.y] if first else [active_origin.x,active_origin.y]}

func _queue_manual(point: Vector2) -> void:
	if not dragging:return
	var first := sample_id==-1
	var command := make_command(stroke_start if first else stroke_previous,point,operation,first)
	command.input_us=manual_input_us
	command.origin="engine_injected" if has_meta("engine_injected") else "desktop_input"
	var error := enqueue(command)
	if error.is_empty():stroke_previous=point
	if not error.is_empty():$Interface/Panel/Rows/Hint.text=error
	if not error.is_empty() and first:sample_id=-1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			manual_input_us=Time.get_ticks_usec()
			operation=1 if event.button_index==MOUSE_BUTTON_RIGHT else $Interface/Panel/Rows/Operation.selected
			dragging=true
			sample_id=-1
			stroke_start=_pick(event.position)
			stroke_previous=stroke_start
			manual_pending=stroke_start
		else:
			# Flush the last accepted position before ending; no control-packet impulse.
			if manual_pending.is_finite():_queue_manual(manual_pending)
			manual_pending=Vector2.INF
			dragging=false
	if event is InputEventMouseMotion and dragging:
		manual_input_us=Time.get_ticks_usec()
		manual_pending=_pick(event.position)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_SPACE:_on_pause()
		if event.keycode==KEY_R:_on_reset()
		if event.keycode==KEY_N:_on_step()

func _pick(screen: Vector2) -> Vector2:
	var camera: Camera3D=$Camera
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var p := origin+direction*((.5-origin.y)/direction.y)
	return Vector2(p.x,p.z)

func _on_pause() -> void:paused=not paused
func _on_step() -> void:
	paused=true
	step_pending+=1
func _on_reset() -> void:reset_pending=true
func _on_mode(i: int) -> void:
	requested_mode=i
	reset_pending=true
func _on_fixture(i: int) -> void:
	requested_fixture=["flat","thin","islands","wall","platform20","platform80","wave"][i]
	reset_pending=true
func _on_view(i: int) -> void:
	$Interface/Panel/Rows/View.select(i)
	$Sand.material_override.set_shader_parameter("view_mode",i)
	$Water.material_override.set_shader_parameter("view_mode",i)
	$Water.visible=i!=3
func _on_arrows(value: bool) -> void:$Water.material_override.set_shader_parameter("arrows",value)
func _on_gain(value: float) -> void:gain=value
func _on_radius(value: float) -> void:
	radius=snappedf(value,.125)
	$Interface/Panel/Rows/Radius.set_value_no_signal(radius)
func _on_replay() -> void:
	if busy or reset_pending:return
	var gen := generation
	var op: int=$Interface/Panel/Rows/Operation.selected
	for i in 17:
		while busy or not commands.is_empty():await get_tree().process_frame
		if gen!=generation or closing or reset_pending:return
		var a := Vector2(0,-2.)
		var b := Vector2(0,-2.+i*.25)
		var error := enqueue(make_command(a,b,op,i==0))
		if not error.is_empty():
			$Interface/Panel/Rows/Hint.text=error
			return
func _on_export() -> void:
	export_pending=true
	snapshot_pending=true

func _reset() -> void:
	busy=true
	if requested_mode>=0:
		mode=requested_mode
		requested_mode=-1
	if not requested_fixture.is_empty():
		fixture=requested_fixture
		requested_fixture=""
	display.texture_rd_rid=RID()
	generation+=1
	_cancel_queued("cancelled_reset")
	last_id=0
	last_sample=-1
	latest=PackedFloat32Array()
	last_field=PackedByteArray()
	last_sediment=PackedByteArray()
	step_pending=0
	dragging=false
	manual_pending=Vector2.INF
	RenderingServer.call_on_render_thread(func():
		release_count+=runtime.release()
		_initialize())

func export_run() -> void:
	var path := ProjectSettings.globalize_path(run_dir)
	var file := FileAccess.open(path+"/metrics.jsonl",FileAccess.WRITE)
	for row in rows:file.store_line(JSON.stringify(row))
	file=FileAccess.open(path+"/commands.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"accepted":accepted,"rejected":rejected},"\t"))
	file=FileAccess.open(path+"/frames.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(frames))
	file=FileAccess.open(path+"/effective_profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"base":profile,"grid":grid,"fixture":fixture,"mode":mode,"gain":gain,"radius":radius,"depth":depth},"\t"))
	if not last_field.is_empty():
		file=FileAccess.open(path+"/field.rgba32f",FileAccess.WRITE)
		file.store_buffer(last_field)
	get_viewport().get_texture().get_image().save_png(path+"/window.png")
	file=FileAccess.open(path+"/environment.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"godot":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),"driver":RenderingServer.get_video_adapter_api_version(),"backend":RenderingServer.get_current_rendering_driver_name(),"window_size":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"visible":not DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED,"grid":grid,"cell_size_m":.125,"run_dir":path,"error":last_error,"release_count":release_count},"\t"))

func _failure(message: String) -> void:
	last_error=message
	paused=true
	busy=false
	push_error(message)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:closing=true

func _shutdown() -> void:
	busy=true
	_cancel_queued("cancelled_shutdown")
	display.texture_rd_rid=RID()
	export_run()
	RenderingServer.call_on_render_thread(func():
		var count: int=runtime.release()
		call_deferred("_released",count))

func _released(count: int) -> void:
	release_count+=count
	var file := FileAccess.open(ProjectSettings.globalize_path(run_dir)+"/release.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"released_rids":release_count,"inflight":false,"generation":generation}))
	get_tree().quit(0 if last_error.is_empty() else 1)

func _cancel_queued(reason: String) -> void:
	for command in commands:rejected.append({"error":reason,"id":command.id,"generation":command.generation})
	commands.clear()
