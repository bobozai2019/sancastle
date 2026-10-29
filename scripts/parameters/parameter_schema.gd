extends RefCounted

const PATH="res://assets/parameters/catalog.json"
const SOURCES=["res://scripts/parameters/parameter_schema.gd",PATH,"res://scripts/parameters/parameter_service.gd","res://scripts/parameters/parameter_row.gd","res://scenes/parameters/parameter_windows.tscn"]
static var _rows: Dictionary={}

static func rows() -> Dictionary:
	if _rows.is_empty():
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Array:
			for row in parsed:_rows[row.id]=row
	return _rows

static func valid(id: String, value: Variant) -> bool:
	var row: Dictionary=rows().get(id,{})
	if row.is_empty():return false
	match row.kind:
		"bool":return typeof(value)==TYPE_BOOL
		"color":
			if not value is Array or value.size()!=4:return false
			for channel in value:
				if typeof(channel) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(channel)) or channel<0 or channel>1:return false
			return true
		_:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):return false
			if value<row.min or value>row.max:return false
			return row.kind not in ["choice","int"] or float(value)==floorf(float(value))

static func validate_values(values: Variant) -> StringName:
	if not values is Dictionary:return &"invalid_parameter_values"
	for id in values:
		if not valid(id,values[id]):return StringName("invalid_parameter:"+String(id))
	if values.get("wall_top",0.5)>values.get("wall_bottom",1.0):return &"wall_top_exceeds_bottom"
	if values.get("solver",1)==0 and values.get("wave_retention",0.0)!=0:return &"retention_requires_muscl"
	return &""

static func coupling_error(values: Variant) -> StringName:
	if not values is Dictionary:return &"invalid_coupling_parameters"
	for id in values:
		if not rows().has(id) or rows()[id].target!="coupling" or not valid(id,values[id]):return &"invalid_coupling_parameters"
	return &""

static func typed_parameters_error(values: Variant, target: String) -> StringName:
	if not values is Dictionary:return &"invalid_tuning_parameters"
	for id in values:
		if not rows().has(id) or rows()[id].target!=target or not valid(id,values[id]):return &"invalid_tuning_parameters"
	return &""

static func selection_error(selection: Variant) -> StringName:
	var original=load("res://scripts/simulation/brushes/brush_checkpoint_codec.gd")
	if not original.keys(selection,["tool","parameters","dig_amount_m3","fill_amount_m3"]):return &"invalid_brush_selection"
	if not valid("dig_amount_m3",selection.dig_amount_m3) or not valid("fill_amount_m3",selection.fill_amount_m3):return &"invalid_brush_selection"
	if not selection.parameters is Dictionary:return &"invalid_brush_selection"
	if selection.tool in [&"remove_sand",&"place_sand",&"suspended_sand",&"smooth_v1",&"compact_v1"]:
		if selection.parameters.is_empty() and selection.tool in [&"remove_sand",&"place_sand",&"suspended_sand"]:return &""
		if not original.keys(selection.parameters,["radius_m","strength"]):return &"invalid_brush_selection"
		return &"" if valid("radius_m",selection.parameters.radius_m) and valid("strength",selection.parameters.strength) else &"invalid_brush_selection"
	return original.selection_error(selection)
