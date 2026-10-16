extends RefCounted

const Protocol = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
const MAX_PENDING := 64
var lab: Node3D
var generation := 0
var accepting := true
var pumping := false
var active_id := 0
var reservations := {}
var policies := {}
var terminal := []
var admissions := []
var max_pending := 0
var denied_tick_requests := 0
var history_limit := 0 # Zero retains complete history for investigation labs.

func _record(history: Array, item: Dictionary) -> void:
	history.append(item)
	if history_limit > 0 and history.size() > history_limit: history.pop_front()

func _init(entry: Node3D) -> void:
	lab=entry;generation=entry.generation

func reserved_total() -> float:
	var total := 0.0
	for amount in reservations.values(): total += float(amount)
	return total

func _external_sand() -> bool:
	return "unrestricted_sand_tools" in lab and lab.unrestricted_sand_tools

func submit(command: Dictionary, policy: int = -1, speed: float = NAN) -> StringName:
	if not accepting or lab.closed or not lab.ready_for_ticks or generation != lab.generation or not lab.last_error.is_empty(): return &"backend_unavailable"
	if lab.command_queue.pending.size() >= MAX_PENDING: return &"backend_unavailable"
	if not Protocol.finite_command(command) or command.get("kind") not in [&"place_sand",&"remove_sand"] or typeof(command.get("generation")) != TYPE_INT: return &"invalid_command"
	if command.get("sand_destination") == "suspended_v1" and (not _external_sand() or not lab.enable_erosion): return &"backend_unavailable"
	policy=lab.water_policy if policy<0 else policy
	speed=lab.signed_speed_m_s if is_nan(speed) else speed
	if policy not in [0,1,2,3] or not is_finite(speed) or absf(speed)>1.0: return &"invalid_command"
	var nominal: float = command.amount_m3 * command.strength if command.kind==&"place_sand" and not _external_sand() else 0.0
	var stock: float = lab.domain.tool_inventory_m3
	var previous_id: int = lab.command_queue.last_command_id
	var error: StringName = lab.command_queue.submit(command)
	if not error.is_empty(): return error
	if nominal>0.0 and (stock<0.0 or reserved_total()+nominal>stock+Protocol.LEGACY_EPS):
		for i in lab.command_queue.pending.size():
			if lab.command_queue.pending[i].command_id==command.command_id:
				lab.command_queue.pending.remove_at(i);break
		lab.command_queue.last_command_id=previous_id
		return &"insufficient_inventory"
	reservations[command.command_id]=nominal
	policies[command.command_id]={"policy":policy,"speed":speed}
	max_pending=maxi(max_pending,lab.command_queue.pending.size())
	_record(admissions, {"id":command.command_id,"tick":command.sim_tick,"generation":generation,"reserve":nominal,"at_us":Time.get_ticks_usec()})
	return &""

func drain_due() -> void:
	var pipeline: bool=lab.has_method("can_submit_frame_batch") and lab.can_submit_frame_batch()
	if pumping or (lab.busy and not pipeline) or lab.closed or generation!=lab.generation: return
	pumping=true
	if pipeline and not lab.command_queue.pending.is_empty():
		var selections:=[]
		var first_policy: int=policies[lab.command_queue.pending[0].command_id].policy
		for command in lab.command_queue.pending:
			if selections.size()>=lab.edit_frame_batch_limit or command.sim_tick>lab.completed_ticks or command.get("schema_version",1)!=1 or command.get("sand_destination","")!="" or policies[command.command_id].policy!=first_policy:break
			selections.append(policies[command.command_id].duplicate(true))
		if not selections.is_empty():
			var batch: Dictionary=await lab.execute_gpu_frame_batch(selections.size(),selections)
			for row in batch.results:
				_record(terminal,{"command":row.command,"result":row.result,"configuration":policies[row.command.command_id],"settle_us":Time.get_ticks_usec(),"publish_us":lab.publish_us,"stock":lab.domain.tool_inventory_m3})
				reservations.erase(row.command.command_id);policies.erase(row.command.command_id)
			if not batch.error.is_empty():cancel_pending("backend_failed")
			pumping=false;return
	# Shape/suspended commands keep their own transaction and collision boundary.
	while lab.busy and not lab.closed and generation==lab.generation and lab.last_error.is_empty():await lab.get_tree().process_frame
	while not lab.command_queue.pending.is_empty() and not lab.closed and generation==lab.generation and lab.last_error.is_empty():
		# A completed edit may leave one published-state simulation tick in
		# flight. Keep the next admitted edit queued until that tick completes.
		while lab.busy and not lab.closed and generation==lab.generation and lab.last_error.is_empty():
			await lab.get_tree().process_frame
		if lab.closed or generation!=lab.generation or not lab.last_error.is_empty() or lab.command_queue.pending.is_empty(): break
		var command: Dictionary = lab.command_queue.pending[0]
		if command.sim_tick>lab.completed_ticks: break
		active_id=command.command_id
		var configuration: Dictionary = policies[active_id]
		lab.water_policy=configuration.policy;lab.signed_speed_m_s=configuration.speed
		var others := reserved_total()-float(reservations[active_id])
		var available: float = lab.domain.tool_inventory_m3 if lab.domain.tool_inventory_m3<0.0 else maxf(0.0,lab.domain.tool_inventory_m3-others)
		if _external_sand(): available = lab.sand_command_available(command)
		var result: Dictionary = await lab.execute_admitted_gpu_command(command,available)
		if result.is_empty() and not lab.last_error.is_empty():
			result={"cancelled":true,"transport_failed":true,"error":lab.last_error}
		_record(terminal, {"command":command.duplicate(true),"result":result.duplicate(true),"configuration":configuration,
			"settle_us":lab.settle_us,"publish_us":lab.publish_us,"at_us":Time.get_ticks_usec(),"stock":lab.domain.tool_inventory_m3})
		reservations.erase(active_id);policies.erase(active_id);active_id=0
	if not lab.last_error.is_empty(): cancel_pending("backend_failed")
	pumping=false

func advance_ticks(count: int) -> void:
	if pumping or lab.busy or lab.closed:
		denied_tick_requests+=1
		return
	for i in count:
		await drain_due()
		if lab.closed or not lab.last_error.is_empty(): return
		await lab.advance_ticks(1)
		await drain_due()

func cancel_pending(reason: String) -> void:
	for command in lab.command_queue.pending:
		_record(terminal, {"command":command.duplicate(true),"result":{"cancelled":true,"error":reason},"at_us":Time.get_ticks_usec()})
		reservations.erase(command.command_id);policies.erase(command.command_id)
	lab.command_queue.pending.clear()

func close() -> void:
	accepting=false;cancel_pending("closed")
	await lab.shutdown()
	while pumping: await lab.get_tree().process_frame

func reset_domain() -> void:
	accepting=false;cancel_pending("reset")
	while pumping: await lab.get_tree().process_frame
	await lab.reset_domain()
	generation=lab.generation
	accepting=not lab.closed and lab.last_error.is_empty()
