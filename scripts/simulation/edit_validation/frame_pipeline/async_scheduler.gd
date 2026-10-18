extends "res://scripts/simulation/brushes/brush_scheduler.gd"

func submit(command: Dictionary, policy: int=-1, speed: float=NAN) -> StringName:
	if lab.async_pipeline_enabled and lab.async_controller!=null:
		if command.has("async_operation"):return &"invalid_input"
		if lab.shutdown_requested or lab.closing:return &"closing"
		var owned_shape: bool=lab.async_controller.legacy and command.get("schema_version")==2 and lab.shape_stroke_id!=0
		if (lab.async_checkpoint_running or lab.beach_restore_running) and not owned_shape:return &"transition_busy"
		if (lab.async_controller.transitioning and not owned_shape) or lab.async_controller.frozen:return &"transition_busy"
		if lab.command_queue.pending.size()>=MAX_PENDING:return &"queue_full"
		if command.get("kind") in [&"smooth",&"compact"]:
			if not accepting or not lab.ready_for_ticks or generation!=lab.generation:return &"backend_unavailable"
			var value:=command.duplicate(true)
			if not value.has("amount_m3"):value.amount_m3=0.0
			if not Protocol.finite_command(value):return &"invalid_input"
			var error: StringName=lab.command_queue.submit(value)
			if not error.is_empty():return error
			reservations[value.command_id]=0.0;policies[value.command_id]={"policy":0,"speed":0.0}
			return &""
	var result:=super.submit(command,policy,speed)
	if lab.async_pipeline_enabled and command.get("schema_version",1)==1 and result==&"invalid_command":return &"invalid_input"
	return result

func drain_due() -> void:
	if not lab.async_pipeline_enabled or lab.async_controller==null:
		await super.drain_due()
		return
	# The frame pump submits every supported command; CPU drain never authorizes
	# the next GPU edit or acquires the old transaction writer.
