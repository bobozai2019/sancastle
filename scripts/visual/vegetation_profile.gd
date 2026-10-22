extends Resource

const Species = preload("res://scripts/visual/vegetation_species.gd")
const CANDIDATES_PER_KIND := 768
const WIDTH := 128
const HEIGHT := 24
const KEYS := ["version","enabled","seed","candidates_per_kind","bounds_xz","species"]
const SPECIES_KEYS := ["label","depth_min_m","depth_max_m","height_min_m","height_max_m","bed_min_m","bed_max_m","density","flow_response","max_slope","patch_min","patch_max","response_hz"]
@export var enabled := true
@export var seed := 62143
@export var species: Array[Resource] = []

func snapshot(scene_key: String) -> Dictionary:
	var values: Array = []
	for item in species:
		if item == null or item.get_script() != Species:return {}
		values.append(item.snapshot())
	return {"version":1,"enabled":enabled,"seed":seed,"candidates_per_kind":CANDIDATES_PER_KIND,
		"bounds_xz":[-14.8,-14.8,14.8,14.8] if scene_key == "main" else [-14.7,-7.2,14.7,7.2],"species":values}

static func validate(value: Variant) -> StringName:
	if not value is Dictionary or value.size() != KEYS.size():return &"invalid_vegetation_profile"
	for key in KEYS:
		if not value.has(key):return &"invalid_vegetation_profile"
	if typeof(value.enabled) != TYPE_BOOL or typeof(value.version) != TYPE_INT or value.version != 1:return &"invalid_vegetation_profile"
	if typeof(value.seed) != TYPE_INT or value.seed < 0 or value.seed > 16777215:return &"invalid_vegetation_seed"
	if typeof(value.candidates_per_kind) != TYPE_INT or value.candidates_per_kind != CANDIDATES_PER_KIND:return &"invalid_vegetation_capacity"
	if not value.bounds_xz is Array or value.bounds_xz.size() != 4:return &"invalid_vegetation_bounds"
	for number in value.bounds_xz:
		if typeof(number) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(number)) or absf(number) > 15.9:return &"invalid_vegetation_bounds"
	if value.bounds_xz[0] >= value.bounds_xz[2] or value.bounds_xz[1] >= value.bounds_xz[3]:return &"invalid_vegetation_bounds"
	if not value.species is Array or value.species.size() != 4:return &"invalid_vegetation_species"
	for row in value.species:
		if not row is Dictionary or row.size() != SPECIES_KEYS.size():return &"invalid_vegetation_species"
		for key in SPECIES_KEYS:
			if not row.has(key):return &"invalid_vegetation_species"
			if key == "label":
				if not row[key] is String or row[key].is_empty() or row[key].length() > 64:return &"invalid_vegetation_species"
			elif typeof(row[key]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(row[key])):return &"invalid_vegetation_species"
		if row.depth_min_m < 0.0 or row.depth_max_m < row.depth_min_m or row.depth_max_m > 8.0:return &"invalid_vegetation_depth"
		if row.height_min_m <= 0.0 or row.height_max_m < row.height_min_m or row.height_max_m > 2.0:return &"invalid_vegetation_height"
		if row.bed_min_m < -16.0 or row.bed_max_m > 16.0 or row.bed_min_m > row.bed_max_m:return &"invalid_vegetation_bed"
		if row.density < 0.0 or row.density > 1.0 or row.patch_min < 0.0 or row.patch_max > 1.0 or row.patch_min >= row.patch_max:return &"invalid_vegetation_density"
		if row.flow_response < 0.0 or row.flow_response > 4.0 or row.max_slope <= 0.0 or row.max_slope > 8.0 or row.response_hz < 0.1 or row.response_hz > 20.0:return &"invalid_vegetation_response"
	return &""
