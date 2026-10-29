extends RefCounted

# Low-frequency CPU/disk bridge only. Integer copies preserve all Float32 bits;
# validation of finite physical values remains at the existing caller boundary.
const CELLS:=65536
const SCALAR_BYTES:=CELLS*4
const PACKED_BYTES:=CELLS*8

static func pack(x: PackedByteArray, z: PackedByteArray) -> Dictionary:
	if x.size()!=SCALAR_BYTES or z.size()!=SCALAR_BYTES:return {"error":&"momentum_component_size"}
	var bytes:=PackedByteArray();bytes.resize(PACKED_BYTES)
	for i in CELLS:
		bytes.encode_u32(i*8,x.decode_u32(i*4));bytes.encode_u32(i*8+4,z.decode_u32(i*4))
	return {"error":&"","value":bytes}

static func split(bytes: PackedByteArray) -> Dictionary:
	if bytes.size()!=PACKED_BYTES:return {"error":&"momentum_packed_size"}
	var x:=PackedByteArray();var z:=PackedByteArray();x.resize(SCALAR_BYTES);z.resize(SCALAR_BYTES)
	for i in CELLS:
		x.encode_u32(i*4,bytes.decode_u32(i*8));z.encode_u32(i*4,bytes.decode_u32(i*8+4))
	return {"error":&"","momentum_x":x,"momentum_z":z}
