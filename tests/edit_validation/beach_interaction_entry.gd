extends "res://tests/edit_validation/beach_gpu_entry.gd"

const Scheduler=preload("res://scripts/simulation/edit_validation/gpu_edit_scheduler.gd")
var input_scheduler
var domain: SandWaterDomain:
	get: return shadow_domain
var busy: bool:
	get: return gpu_busy or tick_pending or checkpoint_capture_pending or sand_prefetch_in_flight or not shadow_sync_reason.is_empty()
var closed: bool:
	get: return closing
var settle_us := -1
var publish_us := -1
var input_running := false
var input_serial := 0
var input_events := []
var input_rejections := []
var input_results := []
var last_input_hit := Vector3.ZERO
var gpu_brush: StringName=&""

func _ready() -> void:
	super._ready()
	input_scheduler=Scheduler.new(self)
	get_tree().auto_accept_quit=false

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and not shutdown_requested: call_deferred("_close_window")

func _close_window() -> void:
	await shutdown();get_tree().quit()

func _process(delta: float) -> void:
	if not shutdown_requested and not input_running and not busy and not command_queue.pending.is_empty() and command_queue.pending[0].sim_tick<=completed_ticks:
		if playing: accumulator=minf(accumulator+delta,SIM_DELTA*4.0)
		input_running=true;call_deferred("_drain_input");return
	super._process(delta)

func _dispatch_paused_patch() -> void:
	# Tick/shadow callbacks in the inherited CPU controller also use this hook.
	# Scheduler-admitted GPU commands must retain their reservation and native path.
	if input_scheduler!=null and not command_queue.pending.is_empty():
		var command: Dictionary=command_queue.pending[0]
		if input_scheduler.reservations.has(command.command_id):
			if not shutdown_requested and not closing and not input_running and command.sim_tick<=completed_ticks:
				input_running=true;call_deferred("_drain_input")
			return
	super._dispatch_paused_patch()

func _start_tick() -> void:
	if input_scheduler!=null and (input_scheduler.pumping or (not command_queue.pending.is_empty() and command_queue.pending[0].sim_tick<=completed_ticks)): return
	# GPU commands need no stale CPU sand synchronization or tool patch upload.
	var pending: Array[Dictionary]=command_queue.pending
	command_queue.pending=[]
	super._start_tick()
	command_queue.pending=pending

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: return
		if not event.pressed: gpu_brush=&"";return
		if shutdown_requested or closing or not ready_for_ticks: return
		gpu_brush=&"remove_sand" if event.button_index==MOUSE_BUTTON_LEFT else &"place_sand"
		var hit:=pick(event.position)
		if hit.is_empty() or not _pick_current(hit): gpu_brush=&"";return
		if _submit_gpu_input(gpu_brush,hit.position,hit.position,&"circle",0.015): last_input_hit=hit.position
		else: gpu_brush=&""
	elif event is InputEventMouseMotion and not gpu_brush.is_empty():
		if shutdown_requested or closing or not ready_for_ticks: return
		var hit:=pick(event.position)
		if hit.is_empty() or not _pick_current(hit): return
		var position: Vector3=hit.position
		var distance:=last_input_hit.distance_to(position)
		if distance>=0.025 and _submit_gpu_input(gpu_brush,last_input_hit,position,&"swept_segment",maxf(0.0005,distance*0.02)): last_input_hit=position
	elif event is InputEventKey:
		# Existing view/pause controls remain available. Recovery keys require
		# the full native GPU prefix and are wired in the recovery controller.
		if event.keycode in [KEY_SPACE,KEY_V,KEY_F5,KEY_F6]: super._unhandled_input(event)

func pick(screen: Vector2) -> Dictionary:
	var camera:=get_viewport().get_camera_3d()
	if camera==null: return {}
	var origin:=camera.project_ray_origin(screen)
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*100.0))

func _pick_current(hit: Dictionary) -> bool:
	var p: Vector3=hit.position
	if hit.get("collider")!=collision_proxy.body or p.x< -16 or p.x>=16 or p.z< -16 or p.z>=16: return false
	var x:=clampi(int((p.x+16)/0.125),0,255);var z:=clampi(int((p.z+16)/0.125),0,255)
	var chunk: int=(z/32)*8+x/32
	var current: bool=int(collision_proxy.applied_revisions.get(chunk,-1))>=int(collision_needed.get(chunk,0))
	if not current: input_rejections.append({"error":"collision_pending","chunk":chunk,"at_us":Time.get_ticks_usec()})
	return current

func _submit_gpu_input(kind: StringName, start: Vector3, end: Vector3, shape: StringName, amount: float) -> bool:
	input_serial=maxi(input_serial,command_queue.last_command_id)+1
	var command: Dictionary={"domain_id":domain.domain_id,"generation":generation,"sim_tick":completed_ticks,"command_id":input_serial,"kind":kind,"shape":shape,"transform":{"position_m":start,"end_position_m":end},"radius_m":0.3,"strength":1.0,"amount_m3":amount,"seed":101}
	var error: StringName=input_scheduler.submit(command)
	input_events.append({"command":command.duplicate(true),"input_us":Time.get_ticks_usec(),"pick":"PhysicsRayQueryParameters3D","admission_error":String(error),"busy_at_capture":busy,"configuration":{"policy":water_policy,"speed":signed_speed_m_s}})
	if not error.is_empty(): return false
	if not input_running: input_running=true;call_deferred("_drain_input")
	return true

func _drain_input() -> void:
	while not closing and last_error.is_empty():
		if busy: await get_tree().process_frame;continue
		await input_scheduler.drain_due()
		if command_queue.pending.is_empty() or command_queue.pending[0].sim_tick>completed_ticks: break
	input_results=input_scheduler.terminal.duplicate(true)
	input_running=false

func execute_admitted_gpu_command(command: Dictionary, available_m3: float) -> Dictionary:
	settle_us=-1;publish_us=-1
	return await super.execute_admitted_gpu_command(command,available_m3)

func _settle_gpu_receipt(bytes: PackedByteArray, token: int) -> void:
	var was_settled:=gpu_settled
	super._settle_gpu_receipt(bytes,token)
	if not was_settled and gpu_settled: settle_us=Time.get_ticks_usec()

func _gpu_publication_done(token: int) -> void:
	super._gpu_publication_done(token)
	if gpu_published: publish_us=Time.get_ticks_usec()

func shutdown() -> void:
	if input_scheduler!=null: input_scheduler.accepting=false;input_scheduler.cancel_pending("closed")
	await super.shutdown()
	while input_running or (input_scheduler!=null and input_scheduler.pumping): await get_tree().process_frame
