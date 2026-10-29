extends RefCounted

const PREFIX_BYTES:=128
const SAMPLES:=1089
const MAX_CHUNKS:=16
const MAX_BYTES:=PREFIX_BYTES+MAX_CHUNKS*SAMPLES*4+4

# Packing rounds a nonnegative cumulative bound upward to a multiple of64
# float32 bit patterns. Recover the enclosing interval, never treat the upper
# endpoint as an exact earlier value when subtracting a newer observation.
static func lower_change_bound(upper: float) -> float:
	if not is_finite(upper) or upper<0.0:return -1.0
	var bits:=PackedFloat32Array([upper]).to_byte_array().decode_u32(0)
	return PackedInt32Array([maxi(0,bits-63)]).to_byte_array().decode_float(0)

static func decode(bytes: PackedByteArray, identity: Dictionary) -> Dictionary:
	if bytes.size()!=MAX_BYTES:return {"error":&"height_size"}
	if bytes.decode_u32(0)!=3 or bytes.decode_u32(4)!=0:return {"error":&"height_protocol_or_fatal"}
	if bytes.decode_s64(8)!=identity.generation or bytes.decode_s64(16)!=identity.snapshot_seq:return {"error":&"height_identity"}
	var state_seq:=bytes.decode_s64(24);var tick:=bytes.decode_s64(32)
	var count:=bytes.decode_u32(40)
	if state_seq<0 or tick<0 or count>MAX_CHUNKS:return {"error":&"height_counter_or_count"}
	if bytes.decode_u32(44)!=33 or bytes.decode_u32(48)!=256 or bytes.decode_float(52)!=0.125 or bytes.decode_u32(56)!=count*SAMPLES*4:return {"error":&"height_layout"}
	var revision:=int(bytes.decode_u32(60)) | (int(bytes.decode_u32(MAX_BYTES-4))<<32)
	if revision<0:return {"error":&"height_revision"}
	var chunks:=PackedInt32Array();var seen:={};var bounds:={}
	for index in count:
		var tag:=bytes.decode_u32(64+index*4);var chunk: int=tag&63;var bits: int=tag&0xffffffc0
		if bits>0x7f800000:return {"error":&"height_change_bound"}
		if seen.has(chunk):return {"error":&"height_chunks"}
		seen[chunk]=true;chunks.append(chunk)
		bounds[chunk]=PackedInt32Array([bits]).to_byte_array().decode_float(0) if bits<0x7f800000 else -1.0
	return {"error":&"","generation":identity.generation,"snapshot_seq":identity.snapshot_seq,"state_seq":state_seq,"sim_tick":tick,"revision":revision,"chunks":chunks,"change_bounds":bounds,"raw":bytes.slice(PREFIX_BYTES,PREFIX_BYTES+count*SAMPLES*4)}
