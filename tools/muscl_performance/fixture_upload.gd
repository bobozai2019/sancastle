extends RefCounted

const Momentum=preload("res://scripts/simulation/unified_edit/momentum_bytes.gd")

static func field_read(rd: RenderingDevice, fields: Dictionary, name: String, slot: int) -> PackedByteArray:
	if name in ["momentum_x","momentum_z"] and fields.has("momentum"):
		var decoded:=Momentum.split(rd.texture_get_data(fields.momentum[slot],0))
		return decoded[name] if decoded.error.is_empty() else PackedByteArray()
	return rd.texture_get_data(fields[name][slot],0)

static func field_upload(rd: RenderingDevice, fields: Dictionary, name: String, slot: int, bytes: PackedByteArray) -> Dictionary:
	if name not in ["momentum_x","momentum_z"] or not fields.has("momentum"):
		return r32_256(rd,fields[name][slot],bytes)
	var decoded:=Momentum.split(rd.texture_get_data(fields.momentum[slot],0))
	if not decoded.error.is_empty():return {"pass":false,"error":ERR_INVALID_DATA}
	decoded[name]=bytes
	var encoded:=Momentum.pack(decoded.momentum_x,decoded.momentum_z)
	if not encoded.error.is_empty():return {"pass":false,"error":ERR_INVALID_DATA}
	var uploaded:=r32_256(rd,fields.momentum[slot],encoded.value,RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,Momentum.PACKED_BYTES)
	var actual:=field_read(rd,fields,name,slot)
	var expected_hash:=HashingContext.new();expected_hash.start(HashingContext.HASH_SHA256);expected_hash.update(bytes)
	var actual_hash:=HashingContext.new();actual_hash.start(HashingContext.HASH_SHA256);actual_hash.update(actual)
	return {"pass":uploaded.pass and actual==bytes,"error":uploaded.error,"expected_sha256":expected_hash.finish().hex_encode(),"actual_sha256":actual_hash.finish().hex_encode()}

# Correctness fixtures only: upload through a temporary copy source because
# production storage textures do not declare CAN_UPDATE. Verify actual bytes.
static func r32_256(rd: RenderingDevice, target: RID, bytes: PackedByteArray, data_format: int=RenderingDevice.DATA_FORMAT_R32_SFLOAT, expected_bytes: int=262144) -> Dictionary:
	var format:=RDTextureFormat.new();format.width=256;format.height=256;format.format=data_format
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var source:=rd.texture_create(format,RDTextureView.new(),[bytes])
	var error:=ERR_CANT_CREATE
	var actual:=PackedByteArray()
	if source.is_valid():
		error=rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
		if error==OK:actual=rd.texture_get_data(target,0)
		rd.free_rid(source)
	var expected_hash:=HashingContext.new();expected_hash.start(HashingContext.HASH_SHA256);expected_hash.update(bytes)
	var actual_hash:=HashingContext.new();actual_hash.start(HashingContext.HASH_SHA256);actual_hash.update(actual)
	return {"pass":error==OK and actual==bytes and bytes.size()==expected_bytes,"error":error,"expected_sha256":expected_hash.finish().hex_encode(),"actual_sha256":actual_hash.finish().hex_encode()}
