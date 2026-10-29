extends RefCounted

const Layout=preload("res://scripts/simulation/edit_validation/frame_pipeline/layout.gd")
const Validation=preload("res://scripts/simulation/edit_validation/frame_pipeline/validation.gd")
var owner
var pending: Array[Dictionary]=[]
var history: Array[Dictionary]=[]
var reply: Dictionary={}
var finish: Dictionary={}
var serial:=0
var submitting:=false

func _init(entry) -> void:
	owner=entry

func poll() -> void:
	for index in range(pending.size()-1,-1,-1):
		var item: Dictionary=pending[index]
		var ready:=true
		for chunk in item.targets:
			if int(owner.collision_proxy.applied_revisions.get(chunk,-1))<int(item.targets[chunk]):ready=false;break
		if not ready:continue
		if item.collision_ready_us<0:
			item.collision_ready_us=Time.get_ticks_usec();item.physics_frame=Engine.get_physics_frames()
			item.collision_applied_us=0
			for chunk in item.targets:item.collision_applied_us=maxi(item.collision_applied_us,int(owner.collision_proxy.applied_usec.get(chunk,0)))
		elif Engine.get_physics_frames()>item.physics_frame:
			item.done_us=Time.get_ticks_usec();history.append(item);pending.remove_at(index)
			if history.size()>128:history.pop_front()

func execute(count: int, configurations: Array) -> Dictionary:
	var encode_start_us:=Time.get_ticks_usec()
	var commands:=[];var envelopes:=[];var selections:=[]
	var execution_tick: int=owner.completed_ticks
	var revision: int=owner.solver.state_revision
	var first_ticket: int=owner.ticket_id+1
	for index in count:
		var command: Dictionary=owner.command_queue.pending[index]
		var selection: Dictionary=configurations[index]
		commands.append(command.duplicate(true));selections.append(selection.duplicate(true))
		var wire_command:=command.duplicate(true);wire_command.sim_tick=execution_tick
		envelopes.append(owner._encode_gpu_command(wire_command,first_ticket+index,revision+index,selection,owner.sand_command_available(command)))
	var plan:=Layout.pack(envelopes,owner.edit_frame_batch_limit,owner.generation,revision,execution_tick)
	if not plan.error.is_empty():return {"error":plan.error,"results":[]}
	for index in count:owner.command_queue.pending.pop_front()
	serial+=1;submitting=true;reply={};finish={}
	owner.gpu_busy=true;owner.edit_overlap_window_open=false
	owner.ticket_id+=count;owner.gpu_settled=false;owner.gpu_published=false
	owner.pending_gpu_command=commands[0];owner.pending_gpu_revision=revision
	var epoch: int=owner.generation
	var item:={"batch":serial,"generation":epoch,"count":count,"submitted_us":Time.get_ticks_usec(),"submitted_frame":Engine.get_process_frames(),"collision_ready_us":-1,"physics_frame":-1,"done_us":-1,"targets":{},"metrics":{}}
	if owner.solver.profile_passes:
		item.command_ids=commands.map(func(command):return command.command_id)
		item.encode_cpu_us=Time.get_ticks_usec()-encode_start_us
	RenderingServer.call_on_render_thread(_submit_render.bind(envelopes,execution_tick,epoch,serial))
	var deadline:=Time.get_ticks_msec()+15000
	while reply.is_empty() and Time.get_ticks_msec()<deadline:await owner.get_tree().process_frame
	var validated: Dictionary=Validation.validate(reply.get("raw",PackedByteArray()),plan) if reply.get("error","").is_empty() else {"error":reply.error}
	if not validated.get("error","").is_empty():
		owner._fail("frame batch: "+str(validated.error));await _finish(false)
		owner.gpu_busy=false;owner.pending_gpu_command={};submitting=false
		return {"error":owner.last_error,"results":[]}
	item.receipt_us=Time.get_ticks_usec();item.metrics=reply.metrics
	if owner.solver.profile_passes:item.callback_us=reply.get("callback_us",0)
	var settle_start_us:=Time.get_ticks_usec()
	var results:=[];var union_receipt: Dictionary={}
	# Keep every original packet and the current v4 checkpoint prefix format.
	var targets: Dictionary=owner.collision_needed.duplicate()
	for index in count:
		var receipt: Dictionary=validated.receipts[index]
		if receipt.status==0:
			results.append({"command":commands[index],"result":{"cancelled":true,"error":"batch_prefix_rejected"}});continue
		owner.pending_gpu_command=commands[index];owner.pending_gpu_revision=revision+index
		owner.ticket_id=first_ticket+index;owner.gpu_settled=false
		var stock: float=owner.shadow_domain.tool_inventory_m3
		owner._settle_gpu_receipt(reply.raw.slice(index*128,(index+1)*128),epoch)
		if not owner.gpu_settled or not owner.last_error.is_empty():break
		var record:={"command":commands[index].duplicate(true),"result":receipt.duplicate(true),"policy":selections[index].policy,"speed":selections[index].speed,"stock_before":stock,"available_m3":owner.sand_command_available(commands[index]),"execution_tick":execution_tick,"sand_accounting":"external_v1"}
		owner.gpu_prefix.append(owner._prepare_prefix_record(record))
		results.append({"command":commands[index],"result":receipt.duplicate(true)})
		if receipt.status==1:
			union_receipt=receipt.duplicate(true)
			for chunk in owner._gpu_chunks(receipt):targets[chunk]=receipt.output_revision
	if not owner.last_error.is_empty():
		await _finish(false)
	else:
		owner.collision_needed=targets
		if owner.solver.profile_passes:item.settle_cpu_us=Time.get_ticks_usec()-settle_start_us
		if validated.accepted_count>0:
			owner.gpu_receipt=union_receipt
			owner.gpu_receipt.dirty_mask=validated.dirty_mask;owner.gpu_receipt.dirty_rect=validated.dirty_rect
			owner.ticket_id=first_ticket+validated.accepted_count-1;owner.gpu_settled=true
			# Snapshot collision heights on the GPU before a later batch writes sand.
			# Its CPU preparation/application may run alongside the later batch.
			RenderingServer.call_on_render_thread(_publish_render.bind(epoch))
			deadline=Time.get_ticks_msec()+15000
			while not owner.gpu_published and Time.get_ticks_msec()<deadline:await owner.get_tree().process_frame
			if not owner.gpu_published:owner._fail("frame batch publication timeout")
			item.published_us=Time.get_ticks_usec()
			item.targets=targets.duplicate();pending.append(item)
		if validated.accepted_count==0:await _finish(true)
		elif finish.is_empty():
			deadline=Time.get_ticks_msec()+15000
			while finish.is_empty() and Time.get_ticks_msec()<deadline:await owner.get_tree().process_frame
		if not finish.get("error","").is_empty():owner._fail("frame batch cleanup: "+str(finish.error))
		if owner.solver.profile_passes:item.finish_profile=finish.get("profile",{})
	owner.ticket_id=first_ticket+count-1;owner.pending_gpu_command={};owner.gpu_busy=false
	owner.edit_overlap_window_open=false;submitting=false
	return {"error":owner.last_error,"results":results}

func _submit_render(envelopes: Array, tick: int, epoch: int, request: int) -> void:
	var begin_us:=Time.get_ticks_usec()
	var started: Dictionary=owner.solver.dispatch_receipt_batch(envelopes,owner.edit_frame_batch_limit,tick,true,_arrived.bind(epoch,request))
	if owner.solver.profile_passes:
		owner.solver.receipt_batch_metrics.record_begin_us=begin_us
		owner.solver.receipt_batch_metrics.record_end_us=Time.get_ticks_usec()
	if not started.get("error","").is_empty():_arrived(started,epoch,request)

func _publish_render(epoch: int) -> void:
	var begin_us:=Time.get_ticks_usec()
	owner._render_gpu_publish(epoch)
	var published_us:=Time.get_ticks_usec()
	var result: Dictionary=owner.solver.complete_receipt_batch()
	if owner.solver.profile_passes:result.profile={"publish_begin_us":begin_us,"publish_end_us":published_us,"cleanup_end_us":Time.get_ticks_usec()}
	_finished(result)

func _arrived(result: Dictionary, epoch: int, request: int) -> void:
	call_deferred("_receive",result,epoch,request)

func _receive(result: Dictionary, epoch: int, request: int) -> void:
	if epoch==owner.generation and request==serial and submitting and reply.is_empty():reply=result

func _finish(commit: bool) -> void:
	finish={};RenderingServer.call_on_render_thread(_finish_render.bind(commit))
	var deadline:=Time.get_ticks_msec()+15000
	while finish.is_empty() and Time.get_ticks_msec()<deadline:await owner.get_tree().process_frame
	if finish.is_empty():finish={"error":"timeout"}

func _finish_render(commit: bool) -> void:
	if commit:_finished(owner.solver.complete_receipt_batch())
	elif owner.solver.receipt_batch_open:owner.solver.abort_receipt_batch(_finished)
	else:_finished({"error":""})

func _finished(result: Dictionary) -> void:
	call_deferred("_receive_finish",result)

func _receive_finish(result: Dictionary) -> void:
	finish=result
