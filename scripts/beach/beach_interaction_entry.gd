extends "res://scripts/beach/beach_gpu_entry.gd"

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
var selected_sand_tool: StringName=&"remove_sand"
@export_range(0.01, 1.0, 0.01) var dig_amount_m3 := 0.10
@export_range(0.01, 1.0, 0.01) var fill_amount_m3 := 0.10
@export_range(0.01, 0.20, 0.01) var manual_wave_amplitude_m := 0.10
var manual_wave_message := "点击触发一波；暂停时等待继续"

func _on_dig_tool_pressed() -> void:
	get_viewport().gui_release_focus()
	selected_sand_tool=&"remove_sand";gpu_brush=&""

func _on_fill_tool_pressed() -> void:
	get_viewport().gui_release_focus()
	selected_sand_tool=&"place_sand";gpu_brush=&""

func _on_wave_amount_changed(value: float) -> void:
	manual_wave_amplitude_m=value

func _manual_wave_available() -> bool:
	return ready_for_ticks and not closing and not shutdown_requested and not checkpoint_capture_pending and not ("gpu_save_running" in self and get("gpu_save_running")) and not ("beach_restore_running" in self and get("beach_restore_running"))

func _on_trigger_wave_pressed() -> void:
	get_viewport().gui_release_focus()
	gpu_brush=&""
	if not _manual_wave_available():
		manual_wave_message="正在准备或保存恢复，请稍后重试"
		_update_manual_wave_ui()
		return
	var request_id: int=wave_highwater_id+1
	var result:=request_wave({"domain_id":shadow_domain.domain_id,"generation":generation,"request_id":request_id,"start_tick":completed_ticks+2,"profile_id":&"test_packet","amplitude_m":manual_wave_amplitude_m,"duration_s":3.0,"seed":request_id*17+31})
	manual_wave_message=("已触发 %.2f m 波浪%s" % [manual_wave_amplitude_m,"，继续后推进" if not playing else ""]) if result.ok else "触发失败，请检查波幅或稍后重试"
	_update_manual_wave_ui()

func _update_manual_wave_ui() -> void:
	var button:=get_node_or_null("Interface/EditPanel/Margin/Controls/TriggerWave")
	if button!=null: button.disabled=not _manual_wave_available()
	var message:=get_node_or_null("Interface/EditPanel/Margin/Controls/WaveStatus")
	if message!=null: message.text=manual_wave_message

func _on_dig_amount_changed(value: float) -> void:
	dig_amount_m3=value
	if ready_for_ticks: _update_status()

func _on_fill_amount_changed(value: float) -> void:
	fill_amount_m3=value
	if ready_for_ticks: _update_status()

func _brush_amount(kind: StringName, distance_m: float = -1.0) -> float:
	var amount: float=dig_amount_m3 if kind==&"remove_sand" else fill_amount_m3
	# Preserve the previous drag rate at the default 0.015 m3 click volume.
	return amount if distance_m<0.0 else maxf(amount/30.0,distance_m*amount/0.75)

func _on_camera_look_started() -> void:
	gpu_brush=&""

func _input(event: InputEvent) -> void:
	# GUI can consume a release after a world drag; always end that stroke.
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		gpu_brush=&""

func _update_status() -> void:
	super._update_status()
	_update_manual_wave_ui()
	var panel:=get_node_or_null("Interface/EditPanel")
	if panel!=null: panel.visible=not hide_hud
	if status_label!=null:
		status_label.text=status_label.text.replace("左键挖沙 右键放沙", "左键使用选定工具 右键转向 WASD移动").replace("F5 玩家视角", "F5 自由视角").replace("；暂停后 Z/Y 撤销/重做。", "。")
		if unrestricted_sand_tools:
			status_label.text = status_label.text.replace("  桶 %.4f m³" % shadow_domain.tool_inventory_m3, "").replace("连桶 ", "合计 ")

func _ready() -> void:
	super._ready()
	# The inherited beach fixture selects its fixed camera during setup.
	if player_camera!=null and "look_active" in player_camera:
		set_player_camera(true)
	input_scheduler=Scheduler.new(self)
	get_tree().auto_accept_quit=false

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and not shutdown_requested: call_deferred("_close_window")

func _close_window() -> void:
	await shutdown();get_tree().quit()

func _process(delta: float) -> void:
	_update_manual_wave_ui()
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
	if player_camera!=null and "look_active" in player_camera and player_camera.look_active:
		gpu_brush=&""
		return
	if event is InputEventMouseButton:
		if event.button_index!=MOUSE_BUTTON_LEFT: return
		if not event.pressed: gpu_brush=&"";return
		if shutdown_requested or closing or not ready_for_ticks: return
		get_viewport().gui_release_focus()
		gpu_brush=selected_sand_tool
		var hit:=pick(event.position)
		if hit.is_empty() or not _pick_current(hit): gpu_brush=&"";return
		if _submit_gpu_input(gpu_brush,hit.position,hit.position,&"circle",_brush_amount(gpu_brush)): last_input_hit=hit.position
		else: gpu_brush=&""
	elif event is InputEventMouseMotion and not gpu_brush.is_empty():
		if get_viewport().gui_get_hovered_control()!=null: gpu_brush=&"";return
		if shutdown_requested or closing or not ready_for_ticks: return
		var hit:=pick(event.position)
		if hit.is_empty() or not _pick_current(hit): return
		var position: Vector3=hit.position
		var distance:=last_input_hit.distance_to(position)
		if distance>=0.025 and _submit_gpu_input(gpu_brush,last_input_hit,position,&"swept_segment",_brush_amount(gpu_brush,distance)): last_input_hit=position
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
	_update_status()

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
