extends RefCounted

# Native wetness/compaction fields are finite unit-range binary16. Preserve the
# host encoder's normal-value behavior, but do not flush legal subnormal bits.
const MIN_NORMAL:=0.00006103515625
const SUBNORMAL_SCALE:=16777216.0

static func encode(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():return {"error":&"empty_unit_half"}
	var bytes:=PackedByteArray();bytes.resize(values.size()*2)
	var source_bits:=values.to_byte_array()
	for index in values.size():
		var value: float=values[index]
		if not is_finite(value) or value<0.0 or value>1.0:return {"error":&"invalid_unit_half"}
		if value==0.0:bytes.encode_u16(index*2,(source_bits.decode_u32(index*4)>>16)&0x8000)
		elif value<MIN_NORMAL:bytes.encode_u16(index*2,int(value*SUBNORMAL_SCALE))
		else:bytes.encode_half(index*2,value)
	return {"error":&"","value":bytes}

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size()%2!=0:return {"error":&"invalid_unit_half_length"}
	var values:=PackedFloat32Array();values.resize(bytes.size()/2)
	for index in values.size():
		var bits:=bytes.decode_u16(index*2)
		if bits==0x8000:values[index]=-0.0;continue
		if bits>0x3c00:return {"error":&"invalid_unit_half"}
		var exponent:=bits>>10;var fraction:=bits&1023
		values[index]=float(fraction)/SUBNORMAL_SCALE if exponent==0 else (1.0+float(fraction)/1024.0)*pow(2.0,exponent-15)
	return {"error":&"","value":values}
