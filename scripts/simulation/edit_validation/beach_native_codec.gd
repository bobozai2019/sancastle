extends RefCounted

const Native=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")
const SPARE=["sand","water","momentum_x","momentum_z","sediment","wetness","compaction","flux"]

static func validate(checkpoint: Dictionary) -> StringName:
	var native: Variant=checkpoint.get("gpu_beach_native")
	if not native is Dictionary or native.get("version")!=1 or native.get("current_index") not in [0,1] or not native.get("fields") is Dictionary or not native.get("spare") is Dictionary or not native.get("foam") is Dictionary: return &"invalid_beach_header"
	if native.fields.size()!=10 or native.spare.size()!=8 or native.foam.size()!=5 or native.foam.get("current_index") not in [0,1]: return &"invalid_beach_history"
	for group in [native.fields,native.spare]:
		var keys: Array=Native.FIELD_BYTES.keys() if group==native.fields else SPARE
		for field in keys:
			var bytes: Variant=group.get(field)
			if not bytes is PackedByteArray or bytes.size()!=65536*int(Native.FIELD_BYTES[field]): return &"invalid_beach_field_size"
			if field=="obstacle":
				for value in bytes:
					if value not in [0,255]: return &"invalid_beach_obstacle"
			elif field in ["wetness","compaction"]:
				for i in 65536:
					var value: float=bytes.decode_half(i*2)
					if not is_finite(value) or value<0.0 or value>1.0: return &"invalid_beach_half"
			else:
				for value in bytes.to_float32_array():
					if not is_finite(value) or (field in ["sand","water","sediment"] and value<0.0): return &"invalid_beach_float"
	for key in ["foam_0","foam_1","bed_0","bed_1"]:
		var bytes: Variant=native.foam.get(key)
		if not bytes is PackedByteArray or bytes.size()!=65536*(4 if key.begins_with("bed") else 8): return &"invalid_beach_foam_size"
		var values: PackedFloat32Array=bytes.to_float32_array()
		for i in values.size():
			var value: float=values[i]
			if not is_finite(value) or (key.begins_with("foam") and (value<0.0 or (i%2==0 and value>1.0))): return &"invalid_beach_foam"
	for field in ["water","momentum_x","momentum_z"]:
		if not checkpoint.get("fields") is Dictionary or not checkpoint.fields.get(field) is PackedFloat32Array or checkpoint.fields[field].to_byte_array()!=native.fields[field]: return &"invalid_beach_projection"
	if not checkpoint.get("foam_history") is PackedFloat32Array or checkpoint.foam_history.to_byte_array()!=native.foam["foam_%d" % native.foam.current_index]: return &"invalid_beach_foam_projection"
	return &""
