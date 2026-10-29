extends "res://scripts/simulation/unified_edit/gpu.gd"

# Probe-only original numerical kernels on private, already verified inputs.
const SOURCES=["res://tests/integration/unified_edit_legacy_response_reference.gd","res://shaders/simulation/edit_validation/water_velocity_apply.glsl","res://shaders/simulation/brushes/water_velocity.glsl","res://scripts/simulation/edit_validation/edit_protocol.gd"]
var buffers: Dictionary={}
var sets: Dictionary={}

func initialize(device: RenderingDevice, input: PackedByteArray, cells: PackedByteArray, wire: Dictionary) -> bool:
	rd=device
	for pair in [["input",input],["cells",cells],["command",PackedByteArray()],["ordinary",PackedByteArray()],["candidate",PackedByteArray()],["scratch",PackedByteArray()],["receipt",PackedByteArray()]]:
		var data: PackedByteArray=pair[1]
		if pair[0]=="command":
			data.resize(256);data.encode_u32(20*4,256);data.encode_float(19*4,0.125);data.encode_u32(21*4,wire.water_policy);data.encode_float(41*4,wire.speed_m_s)
			for key in ["start_x","start_z","end_x","end_z","strength"]:
				var word: int={"start_x":12,"start_z":13,"end_x":14,"end_z":15,"strength":17}[key];data.encode_float(word*4,wire[key])
			data.encode_u32(11*4,1 if wire.shape==1 else 0);data.encode_float(27*4,wire.speed_m_s)
		elif pair[0]=="ordinary":
			data.resize(65536*16)
			for index in 65536:data.encode_float(index*16,cells.decode_float(index*64+48))
		elif pair[0]=="candidate":data.resize(65536*16)
		elif pair[0]=="scratch":data.resize(65536*20)
		elif pair[0]=="receipt":data.resize(128)
		buffers[pair[0]]=own(rd.storage_buffer_create(data.size(),data))
	for pair in [["displace","res://shaders/simulation/edit_validation/water_displace_compensated.glsl"],["packed","res://shaders/simulation/edit_validation/water_packed_cached.glsl"],["reduce","res://shaders/simulation/edit_validation/water_velocity_prefetch.glsl"],["ordinary",SOURCES[1]],["shape",SOURCES[2]]]:
		if not compile(pair[0],pair[1]):return false
	for name in ["displace","packed"]:sets[name]=binding(name,{0:buffers.input,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt})
	sets.reduce=binding("reduce",{0:buffers.command,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt})
	sets.ordinary=binding("ordinary",{0:buffers.command,1:buffers.ordinary,2:buffers.candidate,3:buffers.scratch,4:buffers.receipt})
	sets.shape=binding("shape",{0:buffers.command,1:buffers.cells,2:buffers.candidate,3:buffers.scratch,4:buffers.receipt})
	return true

func record(wire: Dictionary) -> void:
	var push:=PackedFloat32Array([0,0.125,0,0]).to_byte_array();push.encode_u32(0,256)
	if wire.water_policy!=2:dispatch("packed",sets.packed,Vector3i.ONE,push)
	push.encode_u32(12,1 if wire.water_policy==2 else 2);dispatch("displace",sets.displace,Vector3i.ONE,push)
	if wire.operation==0:
		dispatch("ordinary",sets.ordinary,Vector3i(1024,1,1),PackedInt32Array([256,wire.rect_x,wire.rect_z,wire.rect_w,wire.rect_h,0,0,0]).to_byte_array())
	else:dispatch("shape",sets.shape,Vector3i(1024,1,1),PackedInt32Array([256,0,0,wire.water_policy,0,0,0,0]).to_byte_array())
	dispatch("reduce",sets.reduce,Vector3i.ONE)
