extends RefCounted

const MAX_CHUNKS:=16
const SAMPLES:=33*33
const PREFIX_BYTES:=128 # 64B header + fixed 16 chunk-ID words
const MAX_BYTES:=PREFIX_BYTES+MAX_CHUNKS*SAMPLES*4

static func decode(bytes: PackedByteArray, expected: Dictionary) -> Dictionary:
	if bytes.size()<PREFIX_BYTES:return {"error":"snapshot_size"}
	if bytes.decode_u32(0)!=1 or bytes.decode_u32(4)!=0:return {"error":"snapshot_protocol_or_gpu_error"}
	if bytes.decode_u64(8)!=expected.generation or bytes.decode_u64(16)!=expected.snapshot_seq:return {"error":"snapshot_identity"}
	var count:=bytes.decode_u32(40)
	if count<1 or count>MAX_CHUNKS or count!=expected.chunks.size():return {"error":"snapshot_count"}
	if bytes.decode_u32(44)!=33 or bytes.decode_u32(48)!=256 or bytes.decode_float(52)!=0.125 or bytes.decode_u32(56)!=count*SAMPLES*4 or bytes.size()!=PREFIX_BYTES+count*SAMPLES*4:return {"error":"snapshot_layout"}
	var state_seq:=bytes.decode_u64(24)
	var sim_tick:=bytes.decode_u64(32)
	if state_seq<0 or sim_tick<0:return {"error":"snapshot_counter"}
	var seen:={}
	var chunks:=PackedInt32Array()
	for index in count:
		var chunk:=bytes.decode_u32(64+index*4)
		if chunk>=64 or seen.has(chunk) or chunk!=expected.chunks[index]:return {"error":"snapshot_chunks"}
		seen[chunk]=true
		chunks.append(chunk)
	var raw:=bytes.slice(PREFIX_BYTES)
	# Finiteness validation is also performed by the existing immutable worker.
	return {"error":"","generation":expected.generation,"snapshot_seq":expected.snapshot_seq,"state_seq":state_seq,"sim_tick":sim_tick,"chunks":chunks,"raw":raw}
