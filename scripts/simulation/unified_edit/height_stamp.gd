extends Resource

@export var template_id: StringName
@export var payload_path: String
@export var payload_sha256: String
@export var width: int=65
@export var height: int=65
@export var spacing_m: float=0.0625

func validated_snapshot() -> Dictionary:
	if get_script()!=load("res://scripts/simulation/unified_edit/height_stamp.gd"):return {"error":&"invalid_template_type"}
	if String(template_id).is_empty() or width!=65 or height!=65 or spacing_m!=0.0625:return {"error":&"unsupported_template_layout"}
	if not payload_path.begins_with("res://assets/") or ".." in payload_path or not payload_path.ends_with(".rgba32f"):return {"error":&"invalid_template_path"}
	if payload_sha256.length()!=64 or not payload_sha256.is_valid_hex_number(false):return {"error":&"invalid_template_hash"}
	if not FileAccess.file_exists(payload_path):return {"error":&"missing_template"}
	var bytes:=FileAccess.get_file_as_bytes(payload_path)
	if bytes.size()!=width*height*16:return {"error":&"invalid_template_size"}
	if bytes_sha256(bytes)!=payload_sha256:return {"error":&"template_hash_mismatch"}
	var error:=payload_error(bytes,width,height)
	if not error.is_empty():return {"error":error}
	return {"error":&"","value":{"template_id":String(template_id),"payload_path":payload_path,"sha256":payload_sha256,"width":width,"height":height,"spacing_m":spacing_m,"resource_path":resource_path,"resource_sha256":FileAccess.get_sha256(resource_path) if not resource_path.is_empty() else "","model_sha256":get_script().source_code.sha256_text()}}

static func bytes_sha256(bytes: PackedByteArray) -> String:
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256);context.update(bytes)
	return context.finish().hex_encode()

static func payload_error(bytes: PackedByteArray, width: int=65, height: int=65) -> StringName:
	if width!=65 or height!=65 or bytes.size()!=width*height*16:return &"invalid_template_size"
	var values:=bytes.to_float32_array()
	for index in width*height:
		var offset:=index*4
		if not is_finite(values[offset]) or values[offset]<0.0 or values[offset]>1.0 or values[offset+1] not in [0.0,1.0] or values[offset+2] not in [0.0,1.0] or values[offset+3]!=0.0:return &"invalid_template_payload"
	return &""
