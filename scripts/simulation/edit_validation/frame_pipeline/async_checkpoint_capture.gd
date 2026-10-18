extends RefCounted

const Codec=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd")
const MaterialCodec=preload("res://scripts/simulation/brushes/brush_material_state_codec.gd")
const Gravel=preload("res://scripts/visual/gravel_checkpoint_codec.gd")
var owner
var expected:={}
var received:={}
var submitted:=false
var error: StringName=&""
var metadata:={}
var material_metadata:={}
var foam_index:=0
var gravel_metadata:={}
var terminal_done:=false
var terminal_pending:=false
var unconfirmed_ownership:=false
var registration_failed:=false
var inject_registration_failures:=0
var terminal_proofs:=0
var hold_results:=false
var held_results:=[]

func _init(entry) -> void:
	owner=entry

func capture() -> Dictionary:
	owner.async_capture_owners.append(self)
	var controller=owner.async_controller
	metadata={"version":5,"pipeline_protocol_version":1,"grid_size":256,"cell_size_m":0.125,"domain_id":String(owner._domain_id()),"generation":owner.generation,"state_seq":controller.state_seq,"sim_tick":owner.completed_ticks,"revision":owner.solver.state_revision,"advanced_time_s":controller.actual_time,"highwater_id":maxi(owner.input_serial,owner.command_queue.last_command_id),"ticket_id":owner.ticket_id,"configuration":owner.source_signature.duplicate(true),"ledger_precision":"approximate","ledger":{},"initial_sand_total_m3":owner.initial_sand_total_m3,"nominal_upper_supply":controller.nominal_upper_supply,"selection":{"policy":owner.water_policy,"speed":owner.signed_speed_m_s},"cohesion_yield_height_m":owner.material_coupler.cohesion_yield_height_m,"wave_requests":owner.wave_requests.duplicate(true),"wave_highwater_id":owner.wave_highwater_id,"wave_start_times":controller.wave_start_times.duplicate(true)}
	for key in Codec.LEDGER:metadata.ledger[key]=owner.shadow_domain.get(key)
	metadata.ledger.water_source_m3=owner.solver.water_source_m3
	metadata.ledger.water_sink_m3=owner.solver.water_sink_m3
	metadata.simulation=owner._async_snapshot_simulation_configuration()
	metadata.selection.brush=owner._capture_brush_selection()
	# Retain only active request clocks, not an unbounded expired request history.
	var active:={}
	for request in metadata.wave_requests:
		if metadata.wave_start_times.has(request.request_id):active[request.request_id]=metadata.wave_start_times[request.request_id]
	metadata.wave_start_times=active
	RenderingServer.call_on_render_thread(_render_capture)
	while not unconfirmed_ownership and (not submitted or received.size()<expected.size() or not terminal_done):await owner.get_tree().process_frame
	if unconfirmed_ownership:return {"error":&"checkpoint_ownership_unconfirmed"}
	_release_owner_if_drained()
	if not error.is_empty():return {"error":error}
	var fields:={};var spare:={};var foam:={"current_index":foam_index}
	for field in Codec.FIELD_BYTES:fields[field]=received["field/"+field]
	for field in Codec.SPARE:spare[field]=received["spare/"+field]
	for key in ["foam_0","foam_1","bed_0","bed_1"]:foam[key]=received[key]
	material_metadata.current_support=received.material_current
	material_metadata.spare_support=received.material_spare
	var histories:={}
	if metadata.simulation.local_front_history:histories.local_front=received.local_front
	metadata.native={"version":3,"current_index":0,"fields":fields,"spare":spare,"material":material_metadata,"foam":foam,"histories":histories,"control":received.control}
	if gravel_metadata.get("enabled",false):
		gravel_metadata.state_0=received.gravel_0
		gravel_metadata.state_1=received.gravel_1
	metadata.visual_extensions={"gravel_v1":gravel_metadata}
	var validation:=Codec.validate(metadata,owner.source_signature)
	return {"error":validation,"checkpoint":metadata} if validation.is_empty() else {"error":validation}

func _render_capture() -> void:
	var solver=owner.solver
	if solver.current_index!=0:
		call_deferred("_registration_done",{},&"unsettled_pipeline_slots")
		call_deferred("_terminal_confirmed")
		return
	var requests:={}
	for field in Codec.FIELD_BYTES:requests["field/"+field]=solver.current_texture(field)
	for field in Codec.SPARE:requests["spare/"+field]=solver.textures[field][1]
	requests.material_current=solver.textures.mold_support[0]
	requests.material_spare=solver.textures.mold_support[1]
	material_metadata=MaterialCodec.make_record(PackedByteArray(),PackedByteArray(),solver.mold_field_ever_used,owner.material_coupler.profile_sha256)
	foam_index=owner.foam_field.current_index
	for index in 2:
		requests["foam_%d"%index]=owner.foam_field.textures[index]
		requests["bed_%d"%index]=owner.foam_field.bed_textures[index]
	if owner.local_front_field!=null:requests.local_front=owner.local_front_field.texture
	gravel_metadata={"version":2,"enabled":false}
	if owner.gravel_field!=null:
		gravel_metadata=Gravel.extension(owner.gravel_field,metadata.domain_id,{"state_0":PackedByteArray(),"state_1":PackedByteArray()})
		for index in 2:requests["gravel_%d"%index]=owner.gravel_field.textures[index]
	var sizes:={"control":128}
	for key in requests:
		if key.begins_with("field/"):sizes[key]=65536*Codec.FIELD_BYTES[key.trim_prefix("field/")]
		elif key.begins_with("spare/"):sizes[key]=65536*Codec.FIELD_BYTES[key.trim_prefix("spare/")]
		elif key.begins_with("bed_"):sizes[key]=65536*4
		elif key.begins_with("gravel_"):sizes[key]=16384
		else:sizes[key]=65536*8
	# Publish registration before deferred results, so even a partial API failure
	# waits for every successfully registered final consumer before returning.
	call_deferred("_registration_done",sizes,&"")
	for key in requests:
		var status: Error=ERR_UNAVAILABLE
		if inject_registration_failures>0:inject_registration_failures-=1
		else:status=solver.rd.texture_get_data_async(requests[key],0,_arrived.bind(key))
		if status!=OK:
			registration_failed=true
			call_deferred("_registration_failed",key)
	var control_status: Error=ERR_UNAVAILABLE
	if inject_registration_failures>0:inject_registration_failures-=1
	else:control_status=solver.rd.buffer_get_data_async(solver.async_transport.control,_arrived.bind("control"),0,128)
	if control_status!=OK:
		registration_failed=true
		call_deferred("_registration_failed","control")
	if registration_failed:_request_terminal_render()
	else:call_deferred("_terminal_confirmed")

func retry_terminal() -> void:
	if unconfirmed_ownership and not terminal_pending:
		RenderingServer.call_on_render_thread(_request_terminal_render)

func _request_terminal_render() -> void:
	terminal_pending=true
	if owner.solver.async_transport.request_fence(_terminal_arrived)!=OK:
		call_deferred("_terminal_unavailable")

func _terminal_arrived(_bytes: PackedByteArray) -> void:
	call_deferred("_terminal_confirmed")

func _terminal_unavailable() -> void:
	terminal_pending=false
	unconfirmed_ownership=true
	owner._fail("GPU pipeline fatal: checkpoint terminal ownership unavailable")

func _terminal_confirmed() -> void:
	terminal_pending=false
	terminal_done=true
	unconfirmed_ownership=false
	if registration_failed:terminal_proofs+=1
	_release_owner_if_drained()

func _release_owner_if_drained() -> void:
	# Native callbacks also defer a CPU record. Keep the Node and every RID until
	# both the ordered GPU proof and those registered CPU consumers have drained.
	if submitted and terminal_done and received.size()==expected.size():
		owner.async_capture_owners.erase(self)

func _registration_done(sizes: Dictionary, failure: StringName) -> void:
	expected=sizes
	error=failure
	submitted=true

func _registration_failed(key: String) -> void:
	error=&"checkpoint_readback_registration_failed"
	received[key]=PackedByteArray()
	_release_owner_if_drained()

func _arrived(bytes: PackedByteArray, key: String) -> void:
	call_deferred("_record",bytes,key)

func _record(bytes: PackedByteArray, key: String) -> void:
	if hold_results:
		held_results.append([bytes,key]);return
	if received.has(key):return
	if not expected.has(key) or bytes.size()!=expected[key]:error=&"checkpoint_readback_size"
	received[key]=bytes
	_release_owner_if_drained()

func release_held_results() -> void:
	hold_results=false
	for row in held_results:_record(row[0],row[1])
	held_results.clear()
