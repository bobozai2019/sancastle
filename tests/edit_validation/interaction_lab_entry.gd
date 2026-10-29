extends "res://tests/edit_validation/gpu_water_lab_entry.gd"

const Scheduler = preload("res://scripts/simulation/edit_validation/gpu_edit_scheduler.gd")
var input_scheduler
var reported_terminal := 0
var collision_needed := {}
var input_rejections := []
var last_input_mapping := {}
var reset_in_progress := false

func _ready() -> void:
	super._ready()
	get_tree().auto_accept_quit=false

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and not closed: call_deferred("_close_window")

func _close_window() -> void:
	await shutdown()
	get_tree().quit()

var active_brush: StringName = &""
var last_hit := Vector3.ZERO
var input_serial := 0
var input_running := false
var input_results := []
var input_events := []
var collision_chunks := PackedInt32Array()

func pick(screen: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 100.0)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _collision_current(hit: Dictionary) -> bool:
	var half: float=profile.grid_size*profile.cell_size_m*0.5
	var p: Vector3=hit.position
	if p.x < -half or p.x >= half or p.z < -half or p.z >= half: return false
	var x: int=clampi(int((p.x+half)/profile.cell_size_m),0,profile.grid_size-1)
	var z: int=clampi(int((p.z+half)/profile.cell_size_m),0,profile.grid_size-1)
	var chunk: int=(z/32)*(profile.grid_size/32)+x/32
	return int(collision_proxy.applied_revisions.get(chunk,-1))>=int(collision_needed.get(chunk,0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		last_input_mapping={"position":event.position,"global_position":event.global_position,"viewport_size":get_viewport().get_visible_rect().size,"window_size":get_window().size,"window_position":get_window().position,"final_transform":get_viewport().get_final_transform(),"screen_transform":get_viewport().get_screen_transform()}
	if event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: return
		if not event.pressed:
			active_brush = &""
			return
		if closed or not ready_for_ticks: return
		active_brush = &"remove_sand" if event.button_index == MOUSE_BUTTON_LEFT else &"place_sand"
		var hit := pick(event.position)
		if hit.is_empty():
			active_brush = &""
			return
		if not _collision_current(hit):
			input_rejections.append({"error":"collision_pending_or_out_of_domain","at_us":Time.get_ticks_usec()})
			active_brush=&"";return
		last_hit = hit.position
		_start_input(active_brush, last_hit, last_hit, &"circle", 0.015)
	elif event is InputEventMouseMotion and not active_brush.is_empty():
		if closed or not ready_for_ticks: return
		var hit := pick(event.position)
		if hit.is_empty(): return
		if not _collision_current(hit):
			input_rejections.append({"error":"collision_pending_or_out_of_domain","at_us":Time.get_ticks_usec()});return
		var position: Vector3 = hit.position
		var distance := last_hit.distance_to(position)
		if distance < 0.025: return
		if _start_input(active_brush, last_hit, position, &"swept_segment", maxf(0.0005, distance * 0.02)): last_hit = position

func _start_input(kind: StringName, start: Vector3, end: Vector3, shape: StringName, amount: float) -> bool:
	if input_scheduler==null: input_scheduler=Scheduler.new(self)
	if "--profile-edit-passes" in OS.get_cmdline_user_args(): solver.profile_passes = true
	input_serial = maxi(input_serial,command_queue.last_command_id)+1
	var command := {"domain_id": domain.domain_id,"generation":generation,"sim_tick":completed_ticks,
		"command_id":input_serial,"kind":kind,"shape":shape,"transform":{"position_m":start,"end_position_m":end},
		"radius_m":0.3,"strength":1.0,"amount_m3":amount,"seed":101}
	var error: StringName=input_scheduler.submit(command)
	input_events.append({"command":command.duplicate(true),"input_us":Time.get_ticks_usec(),"pick":"PhysicsRayQueryParameters3D","admission_error":String(error),"busy_at_capture":busy})
	if not error.is_empty(): return false
	if not input_running:
		input_running=true;call_deferred("_execute_input",command)
	return true

func _chunks_for_receipt(result: Dictionary) -> PackedInt32Array:
	var chunks:=PackedInt32Array()
	var per_row: int=profile.grid_size/32
	for chunk in per_row*per_row:
		if (int(result.dirty_mask[0])&(1<<chunk) if chunk<32 else int(result.dirty_mask[1])&(1<<(chunk-32)))==0: continue
		for dz in range(-1,2):
			for dx in range(-1,2):
				var x: int=chunk%per_row+dx
				var z: int=chunk/per_row+dz
				var neighbor:=z*per_row+x
				if x>=0 and x<per_row and z>=0 and z<per_row and neighbor not in chunks: chunks.append(neighbor)
	chunks.sort();return chunks

func _settle_receipt(data: PackedByteArray, token: int) -> void:
	var was_settled:=transaction_settled
	super._settle_receipt(data,token)
	if not was_settled and transaction_settled and not closed and token==generation and receipt.get("status")==1:
		for chunk in _chunks_for_receipt(receipt): collision_needed[chunk]=receipt.output_revision

func _render_publish_command(token: int) -> void:
	super._render_publish_command(token)
	if closed or token != generation or solver.publication_pending: return
	collision_chunks=_chunks_for_receipt(receipt)
	if not collision_proxy.request_chunks_render(collision_chunks,solver.state_revision,token): call_deferred("_fail","input collision dispatch failed")

func _execute_input(_command: Dictionary) -> void:
	while not closed and last_error.is_empty():
		await input_scheduler.drain_due()
		var started:=Time.get_ticks_usec()
		while not closed and last_error.is_empty():
			var complete := true
			for chunk in collision_needed: complete=complete and int(collision_proxy.applied_revisions.get(chunk,-1))>=int(collision_needed[chunk])
			if complete: break
			if Time.get_ticks_usec() - started > 1000000:
				_fail("input collision completion timeout"); break
			await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		while reported_terminal<input_scheduler.terminal.size():
			var item: Dictionary=input_scheduler.terminal[reported_terminal]
			var result: Dictionary=item.result
			input_results.append({"receipt":result,"collision_chunks":Array(_chunks_for_receipt(result)) if result.get("status")==1 else [],"collision_complete_us":Time.get_ticks_usec(),"settle_us":item.get("settle_us",-1),"publish_us":item.get("publish_us",-1)})
			reported_terminal+=1
		if command_queue.pending.is_empty() or command_queue.pending[0].sim_tick>completed_ticks: break
	input_running = false

func shutdown() -> void:
	if input_scheduler!=null:
		input_scheduler.accepting=false;input_scheduler.cancel_pending("closed")
	await super.shutdown()
	while input_running: await get_tree().process_frame

func reset_domain() -> void:
	if reset_in_progress or closed: return
	reset_in_progress=true
	ready_for_ticks=false
	active_brush=&""
	if input_scheduler!=null:
		input_scheduler.accepting=false
		input_scheduler.cancel_pending("reset")
	# Finish the admitted transaction and collision callbacks before replacing
	# their resources. Pending commands have already received cancellation.
	while busy or input_running or (input_scheduler!=null and input_scheduler.pumping) or collision_proxy.staging_texture.is_valid():
		if closed:
			reset_in_progress=false;return
		await get_tree().process_frame
	await super.reset_domain()
	if ready_for_ticks:
		input_scheduler=Scheduler.new(self)
		input_serial=0;reported_terminal=0
		collision_needed.clear();collision_chunks.clear()
		input_events.clear();input_results.clear();input_rejections.clear()
	reset_in_progress=false

