extends RefCounted

# Material subrecord v1 belongs in the planned gpu_beach_native v2 envelope.
# It does not make the old envelope support material or new command prefixes.
const CELL_COUNT := 65536
const FORMAT := "RG32F_tagged_depth_reference_sand"
const KEYS := ["version","format","grid_size","cell_size_m","profile_id","profile_sha256","ever_used","current_support","spare_support"]

static func initial_values(tagged: Variant, sand: PackedFloat32Array) -> PackedByteArray:
	if not tagged is PackedFloat32Array or sand.size()!=CELL_COUNT: return PackedByteArray()
	var tags: PackedFloat32Array=tagged
	if not tags.is_empty() and tags.size()!=CELL_COUNT: return PackedByteArray()
	var values:=PackedFloat32Array();values.resize(CELL_COUNT*2)
	for i in CELL_COUNT:
		var tag: float=0.0 if tags.is_empty() else tags[i]
		if not is_finite(tag) or not is_finite(sand[i]) or tag<0.0 or tag>sand[i] or sand[i]<0.0: return PackedByteArray()
		values[i*2]=tag if tag>0.0 else 0.0
		values[i*2+1]=sand[i] if tag>0.0 else 0.0
	return values.to_byte_array()

static func make_record(current: PackedByteArray, spare: PackedByteArray, ever_used: bool, profile_sha256: String) -> Dictionary:
	return {"version":1,"format":FORMAT,"grid_size":256,"cell_size_m":0.125,"profile_id":&"molded_v1","profile_sha256":profile_sha256,"ever_used":ever_used,"current_support":current,"spare_support":spare}

static func validate(record: Variant, current_sand: Variant, spare_sand: Variant, expected_profile_sha256: String) -> StringName:
	if not record is Dictionary or record.size()!=KEYS.size(): return &"invalid_material_header"
	for key in KEYS:
		if not record.has(key): return &"invalid_material_header"
	if typeof(record.version)!=TYPE_INT or record.version!=1 or typeof(record.grid_size)!=TYPE_INT or record.grid_size!=256 or typeof(record.ever_used)!=TYPE_BOOL:
		return &"invalid_material_header"
	if record.format!=FORMAT or typeof(record.cell_size_m) not in [TYPE_FLOAT,TYPE_INT] or record.cell_size_m!=0.125: return &"invalid_material_format"
	if typeof(record.profile_id) not in [TYPE_STRING,TYPE_STRING_NAME] or record.profile_id!=&"molded_v1" or typeof(record.profile_sha256)!=TYPE_STRING or record.profile_sha256!=expected_profile_sha256 or expected_profile_sha256.length()!=64:
		return &"material_profile_mismatch"
	var any_tag:=false
	for pair in [[record.current_support,current_sand],[record.spare_support,spare_sand]]:
		if not pair[0] is PackedByteArray or not pair[1] is PackedByteArray or pair[0].size()!=CELL_COUNT*8 or pair[1].size()!=CELL_COUNT*4:
			return &"invalid_material_field_size"
		var bytes: PackedByteArray=pair[0]
		var values: PackedFloat32Array=bytes.to_float32_array()
		var sand: PackedFloat32Array=pair[1].to_float32_array()
		for i in CELL_COUNT:
			var tag: float=values[i*2];var reference: float=values[i*2+1]
			if not is_finite(sand[i]) or sand[i]<0.0: return &"invalid_material_sand"
			if not is_finite(tag) or not is_finite(reference) or tag<0.0 or tag>sand[i]: return &"invalid_material_values"
			if tag>0.0:
				any_tag=true
				if reference!=sand[i]: return &"invalid_material_reference"
			elif bytes.decode_u32(i*8)!=0 or bytes.decode_u32(i*8+4)!=0: return &"invalid_material_reference"
	if record.current_support!=record.spare_support: return &"invalid_material_pair"
	if any_tag and not record.ever_used: return &"invalid_material_ever_used"
	return &""
