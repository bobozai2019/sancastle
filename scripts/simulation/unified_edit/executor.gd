extends "res://scripts/simulation/unified_edit/gpu.gd"
const Response=preload("res://scripts/simulation/unified_edit/water_response.gd")

var state
var transport
var buffers: Dictionary={}
var images: Dictionary={}
var sets: Array[RID]=[]
var recorded_commands:=0
var traces: Array[Dictionary]=[]
var response:=Response.new()

func initialize(bundle, channel, registry) -> bool:
	if rd!=null or bundle.rd==null:return false
	state=bundle;transport=channel;rd=bundle.rd
	for pair in [["command",L.COMMAND_BYTES],["cells",65536*L.CELL_BYTES],["summary",L.SUMMARY_BUFFER_BYTES],["decision",128],["allocation_steps",65536*4],["allocation_blocks",L.REDUCE_BLOCKS*16],["stroke",64],["transfer_prefix",65536*32],["transfer_state",128]]:
		var initial:=PackedByteArray()
		if pair[0]=="stroke":initial.resize(64)
		buffers[pair[0]]=own(rd.storage_buffer_create(pair[1],initial))
		if not buffers[pair[0]].is_valid():last_error="executor_buffer_create";return false
	var templates:={}
	for profile in registry.catalog_snapshot().values():
		if not profile.template.is_empty():templates[profile.template.sha256]=profile.template
	var hashes:=templates.keys();hashes.sort()
	var payload:=PackedByteArray();payload.resize(16);payload.encode_u32(0,hashes.size())
	for hash in hashes:
		var data: PackedByteArray=registry.template_bytes(hash)
		var mask_count:=0
		for index in 65*65:
			if data.decode_float(index*16+4)>0.5:mask_count+=1
		var header:=PackedByteArray();header.resize(16);header.encode_u32(0,mask_count)
		payload.append_array(header);payload.append_array(data)
	buffers.templates=own(rd.storage_buffer_create(payload.size(),payload))
	if not buffers.templates.is_valid():last_error="template_buffer_create";return false
	for pair in [["baseline",RenderingDevice.DATA_FORMAT_R32_SFLOAT],["coverage",RenderingDevice.DATA_FORMAT_R32G32_SFLOAT],["candidate_coverage",RenderingDevice.DATA_FORMAT_R32G32_SFLOAT],["candidate_compaction",RenderingDevice.DATA_FORMAT_R16_SFLOAT]]:
		# _create_texture registers on state; only state owns the image lifetime.
		images[pair[0]]=state._create_texture(pair[1],PackedByteArray())
	if not compile("edit","res://scripts/simulation/unified_edit/edit.glsl"):return false
	for slot in transport.resources:
		var uniform:=binding("edit",{0:slot.input,1:transport.control,2:buffers.command,3:buffers.cells,4:buffers.summary,5:buffers.decision,6:slot.output,14:buffers.allocation_steps,15:buffers.allocation_blocks,16:buffers.stroke,17:buffers.templates,24:buffers.transfer_prefix,25:buffers.transfer_state},{7:state.textures.sand[0],8:state.textures.sand[1],9:state.textures.rock,10:state.textures.water[0],11:state.textures.compaction[0],12:state.textures.mold_support[0],13:state.textures.mold_support[1],18:images.baseline,19:images.coverage,20:images.candidate_coverage,21:state.textures.compaction[1],22:state.textures.obstacle,23:images.candidate_compaction,26:state.textures.sediment[0],27:state.textures.sediment[1]})
		sets.append(uniform)
		if not uniform.is_valid():last_error="executor_uniform_create";return false
	if not response.initialize(self):last_error=response.last_error;return false
	return true

func record(input: RID, _control: RID, _output: RID, count: int, commands: Array) -> void:
	var slot_index:=-1
	for index in transport.resources.size():
		if transport.resources[index].input==input:slot_index=index;break
	assert(slot_index>=0 and commands.size()==count)
	for index in count:
		var command: Dictionary=commands[index]
		var groups:=ceili(float(command.rect_w*command.rect_h)/256.0)
		if command.operation==L.Profile.Operation.TARGET_HEIGHT or command.control_kind==L.ControlKind.BEGIN:groups=256
		groups=maxi(1,groups)
		var trace: Array=[]
		_pass(slot_index,index,0,groups,1,trace)
		_pass(slot_index,index,1,groups,groups,trace)
		_pass(slot_index,index,2,groups,groups,trace);_pass(slot_index,index,3,groups,1,trace)
		if command.operation==L.Profile.Operation.TRANSFER:
			# Private capped-weight allocation; all authority writes remain mode7.
			_pass(slot_index,index,9,groups,groups,trace)
			_pass(slot_index,index,4,groups,groups,trace)
			_pass(slot_index,index,2,groups,groups,trace,1);_pass(slot_index,index,3,groups,1,trace,1)
			_pass(slot_index,index,10,groups,1,trace)
			_pass(slot_index,index,4,groups,groups,trace,1)
			_pass(slot_index,index,11,groups,1,trace)
			_pass(slot_index,index,4,groups,groups,trace,2)
		elif command.volume_sign==L.Profile.VolumeSign.REMOVE:
			for iteration in 4:
				_pass(slot_index,index,4,groups,groups,trace)
				_pass(slot_index,index,2,groups,groups,trace);_pass(slot_index,index,3,groups,1,trace,1)
		else:_pass(slot_index,index,4,groups,groups,trace)
		if command.operation==L.Profile.Operation.REDISTRIBUTE:
			# Weighted proposal then one shared total correction; no private writer.
			_pass(slot_index,index,2,groups,groups,trace,1);_pass(slot_index,index,3,groups,1,trace,1)
			_pass(slot_index,index,4,groups,groups,trace,1)
		_pass(slot_index,index,12,groups,groups,trace)
		_pass(slot_index,index,5,groups,groups,trace);_pass(slot_index,index,6,groups,1,trace)
		var water_stages: Array=[]
		if command.water_policy>0:water_stages=response.record(command.water_policy)
		_before_commit()
		_pass(slot_index,index,7,groups,groups,trace)
		if command.water_policy>0:response.commit()
		_pass(slot_index,index,8,groups,1,trace)
		recorded_commands+=1
		traces.append({"command_id":command.command_id,"operation":command.operation,"phases":trace,"water_stages":water_stages})
		if traces.size()>128:traces.pop_front()

func _pass(slot: int, index: int, mode: int, groups: int, dispatches: int, trace: Array, phase: int=0) -> void:
	dispatch("edit",sets[slot],Vector3i(dispatches,1,1),PackedInt32Array([mode,index,groups,phase]).to_byte_array())
	trace.append(mode)

func _before_commit() -> void:pass

func release() -> void:
	if transport!=null and transport.has_owned():push_error("executor release while work owns scratch");return
	response.release();sets.clear();buffers.clear();images.clear();super.release()
