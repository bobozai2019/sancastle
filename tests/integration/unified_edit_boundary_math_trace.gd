extends "res://scripts/simulation/unified_edit/gpu.gd"

# Read-only, post-hoc math diagnostic using captured inputs on private buffers.
const SOURCES=["res://tests/integration/unified_edit_boundary_math_trace.gd","res://tests/fixtures/unified_edit/boundary_math_trace.glsl"]
var requests: Dictionary={}
var pending:=0
var serial:=0
var results: Dictionary={}

func initialize(device: RenderingDevice) -> bool:
	rd=device;return compile("trace",SOURCES[1])

func capture(waves: PackedByteArray, control: PackedByteArray, count: int) -> void:
	serial+=1;var id:=serial;var zero:=PackedByteArray();zero.resize(129*16)
	var input:=own(rd.storage_buffer_create(2048,waves));var clock:=own(rd.storage_buffer_create(128,control));var output:=own(rd.storage_buffer_create(zero.size(),zero))
	var set:=binding("trace",{0:input,1:clock,2:output})
	requests[id]=true;call_deferred("_started")
	dispatch("trace",set,Vector3i.ONE,PackedInt32Array([count]).to_byte_array())
	if rd.buffer_get_data_async(output,_arrived.bind(id),0,zero.size())!=OK:call_deferred("_received",PackedByteArray(),id)

func _started() -> void:pending+=1
func _arrived(bytes: PackedByteArray, id: int) -> void:call_deferred("_received",bytes,id)
func _received(bytes: PackedByteArray, id: int) -> void:results[id]=bytes;pending-=1
