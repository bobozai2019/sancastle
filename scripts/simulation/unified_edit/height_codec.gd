extends RefCounted

const PREFIX_BYTES:=128
const SAMPLES:=1089
const MAX_CHUNKS:=16
const MAX_BYTES:=PREFIX_BYTES+MAX_CHUNKS*SAMPLES*4+4

static func decode(bytes: PackedByteArray, identity: Dictionary) -> Dictionary:
	if bytes.size()!=MAX_BYTES:return {"error":&"height_size"}
	if bytes.decode_u32(0)!=2 or bytes.decode_u32(4)!=0:return {"error":&"height_protocol_or_fatal"}
	if bytes.decode_s64(8)!=identity.generation or bytes.decode_s64(16)!=identity.snapshot_seq:return {"error":&"height_identity"}
	var state_seq:=bytes.decode_s64(24);var tick:=bytes.decode_s64(32)
	var count:=bytes.decode_u32(40)
	if state_seq<0 or tick<0 or count>MAX_CHUNKS:return {"error":&"height_counter_or_count"}
	if bytes.decode_u32(44)!=33 or bytes.decode_u32(48)!=256 or bytes.decode_float(52)!=0.125 or bytes.decode_u32(56)!=count*SAMPLES*4:return {"error":&"height_layout"}
	var revision:=int(bytes.decode_u32(60)) | (int(bytes.decode_u32(MAX_BYTES-4))<<32)
	if revision<0:return {"error":&"height_revision"}
	var chunks:=PackedInt32Array();var seen:={}
	for index in count:
		var chunk:=bytes.decode_u32(64+index*4)
		if chunk>=64 or seen.has(chunk):return {"error":&"height_chunks"}
		seen[chunk]=true;chunks.append(chunk)
	return {"error":&"","generation":identity.generation,"snapshot_seq":identity.snapshot_seq,"state_seq":state_seq,"sim_tick":tick,"revision":revision,"chunks":chunks,"raw":bytes.slice(PREFIX_BYTES,PREFIX_BYTES+count*SAMPLES*4)}
