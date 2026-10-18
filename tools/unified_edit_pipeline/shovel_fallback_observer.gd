extends "res://tools/unified_edit_pipeline/shovel_water_observer.gd"

var witness_buffer: RID
var witness_set: RID
var witness_bytes:=PackedByteArray()
var witness_done:=false
var witness_error:=OK

func adopt(value) -> void:
	super.adopt(value)
	var zero:=PackedByteArray();zero.resize(144+65536*32)
	witness_buffer=own(rd.storage_buffer_create(zero.size(),zero))
	if not compile("fallback_witness","res://tools/unified_edit_pipeline/shovel_fallback_witness.glsl"):
		push_error(last_error);return
	witness_set=binding("fallback_witness",{0:buffers.input,1:buffers.receipt,2:buffers.indirect,3:witness_buffer})

func _legacy_dispatch(name: String, push: PackedByteArray) -> void:
	super._legacy_dispatch(name,push)
	if name!="packed":return
	for mode in 2:
		var data:=PackedInt32Array([mode,serial,0,0]).to_byte_array()
		var list:=rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,kernels.fallback_witness.pipeline)
		rd.compute_list_bind_uniform_set(list,witness_set,0)
		rd.compute_list_set_push_constant(list,data,data.size())
		rd.compute_list_dispatch(list,1 if mode==0 else 2048,1,1);rd.compute_list_end()

func collect_render() -> void:
	witness_error=rd.buffer_get_data_async(witness_buffer,_arrived)
	if witness_error!=OK:call_deferred("_stored",PackedByteArray())

func _arrived(bytes: PackedByteArray) -> void:call_deferred("_stored",bytes)
func _stored(bytes: PackedByteArray) -> void:witness_bytes=bytes;witness_done=true
