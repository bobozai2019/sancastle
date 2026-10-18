extends Resource

const Stamp=preload("res://scripts/simulation/unified_edit/height_stamp.gd")
enum Operation { VOLUME_DELTA, TARGET_HEIGHT, TRANSFER, REDISTRIBUTE, FIELD_ADJUST }
enum Shape { DISK, SWEPT_CAPSULE, HEIGHT_STAMP }
enum Destination { BED_SAND, SUSPENDED_SAND, MATERIAL }
enum VolumeSign { NONE, ADD, REMOVE }
enum HeightReference { NONE, FIXED_WORLD, STROKE_BASELINE }
enum TargetRule { NONE, FILL_TO }
enum TransferPolicy { NONE, BALANCED_SHOULDERS }
enum MaterialPolicy { PLAIN, MOLDED, PRESERVE }
enum StrokePolicy { NONE, FIXED_BASELINE_COVERAGE }
const BED:=1
const SUSPENDED:=2
const MATERIAL:=4
const WATER:=8
const MOMENTUM:=16
const COVERAGE:=32

@export var profile_id: StringName
@export var version: int=1
@export var operation: Operation=Operation.VOLUME_DELTA
@export var shape: Shape=Shape.DISK
@export var destination: Destination=Destination.BED_SAND
@export var volume_sign: VolumeSign=VolumeSign.NONE
@export var height_reference: HeightReference=HeightReference.NONE
@export var target_rule: TargetRule=TargetRule.NONE
@export var transfer_policy: TransferPolicy=TransferPolicy.NONE
@export var material_policy: MaterialPolicy=MaterialPolicy.PLAIN
@export var water_policy: int=3
@export var allowed_water_policies: PackedInt32Array=[]
@export var allowed_material_policies: PackedInt32Array=[]
@export var stroke_policy: StrokePolicy=StrokePolicy.NONE
@export var shape_resource: Resource
@export var defaults: Dictionary={}
@export var ranges: Dictionary={}
@export var sample_spacing_m: float=0.125
@export var max_segment_m: float=2.0
@export var max_buffer_points: int=256
@export var display_name: String=""

static func finite_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):return false
	var narrowed: float=PackedFloat32Array([float(value)])[0]
	return is_finite(narrowed) and (float(value)==0.0 or narrowed!=0.0)

func parameter_keys() -> Array:
	match operation:
		Operation.VOLUME_DELTA:return ["radius_m","amount_m3","strength","speed_m_s"]
		Operation.TARGET_HEIGHT:
			return ["height_m","scale_xz","yaw_rad","speed_m_s"] if shape==Shape.HEIGHT_STAMP else ["height_m","bottom_width_m","top_width_m","speed_m_s"]
		Operation.TRANSFER:return ["depth_m","trench_width_m","shoulder_width_m","speed_m_s"]
		Operation.REDISTRIBUTE,Operation.FIELD_ADJUST:return ["radius_m","strength"]
	return []

func combination_error() -> StringName:
	if operation not in Operation.values() or shape not in Shape.values() or destination not in Destination.values():return &"unsupported_combination"
	if volume_sign not in VolumeSign.values() or height_reference not in HeightReference.values() or target_rule not in TargetRule.values() or transfer_policy not in TransferPolicy.values() or material_policy not in MaterialPolicy.values() or stroke_policy not in StrokePolicy.values() or water_policy not in [0,1,2,3]:return &"unsupported_combination"
	match operation:
		Operation.VOLUME_DELTA:
			if shape not in [Shape.DISK,Shape.SWEPT_CAPSULE] or destination not in [Destination.BED_SAND,Destination.SUSPENDED_SAND] or volume_sign not in [VolumeSign.ADD,VolumeSign.REMOVE] or material_policy!=MaterialPolicy.PLAIN:return &"unsupported_combination"
			if destination==Destination.SUSPENDED_SAND and (volume_sign!=VolumeSign.ADD or water_policy!=0):return &"unsupported_combination"
			if height_reference!=HeightReference.NONE or stroke_policy!=StrokePolicy.NONE or target_rule!=TargetRule.NONE or transfer_policy!=TransferPolicy.NONE:return &"unsupported_combination"
		Operation.TARGET_HEIGHT:
			if shape not in [Shape.SWEPT_CAPSULE,Shape.HEIGHT_STAMP] or destination!=Destination.BED_SAND or volume_sign!=VolumeSign.NONE or target_rule!=TargetRule.FILL_TO or transfer_policy!=TransferPolicy.NONE or material_policy not in [MaterialPolicy.PLAIN,MaterialPolicy.MOLDED] or stroke_policy!=StrokePolicy.FIXED_BASELINE_COVERAGE:return &"unsupported_combination"
			if height_reference!=(HeightReference.FIXED_WORLD if shape==Shape.HEIGHT_STAMP else HeightReference.STROKE_BASELINE):return &"unsupported_combination"
		Operation.TRANSFER:
			if shape!=Shape.SWEPT_CAPSULE or destination!=Destination.BED_SAND or volume_sign!=VolumeSign.NONE or target_rule!=TargetRule.NONE or transfer_policy!=TransferPolicy.BALANCED_SHOULDERS or material_policy!=MaterialPolicy.PRESERVE or stroke_policy!=StrokePolicy.FIXED_BASELINE_COVERAGE or height_reference!=HeightReference.STROKE_BASELINE:return &"unsupported_combination"
		Operation.REDISTRIBUTE,Operation.FIELD_ADJUST:
			if shape!=Shape.DISK or destination!=(Destination.BED_SAND if operation==Operation.REDISTRIBUTE else Destination.MATERIAL) or volume_sign!=VolumeSign.NONE or height_reference!=HeightReference.NONE or target_rule!=TargetRule.NONE or transfer_policy!=TransferPolicy.NONE or material_policy!=MaterialPolicy.PRESERVE or stroke_policy!=StrokePolicy.NONE or water_policy!=0:return &"unsupported_combination"
	if shape==Shape.HEIGHT_STAMP:
		if not shape_resource is Stamp or shape_resource.get_script()!=Stamp:return &"invalid_template_type"
	elif shape_resource!=null:return &"unexpected_template"
	return &""

func derived_fields() -> int:
	return fields_for(operation,destination,water_policy,stroke_policy)

static func fields_for(op: int, target: int, water: int, stroke: int) -> int:
	if op==Operation.FIELD_ADJUST:return MATERIAL
	if target==Destination.SUSPENDED_SAND:return SUSPENDED
	var mask:=BED|MATERIAL
	if water!=0:mask|=WATER|SUSPENDED|MOMENTUM
	if stroke==StrokePolicy.FIXED_BASELINE_COVERAGE:mask|=COVERAGE
	return mask

func parameter_error(values: Dictionary) -> StringName:
	if values.size()!=defaults.size():return &"invalid_parameters"
	for key in defaults:
		if not values.has(key) or not finite_number(values[key]):return &"invalid_parameters"
		var value: float=values[key]
		if value<float(ranges[key][0]) or value>float(ranges[key][1]):return &"invalid_parameters"
		if key in ["radius_m","amount_m3"] and value<=0.0:return &"invalid_parameters"
	if values.has("top_width_m") and values.top_width_m>values.bottom_width_m:return &"invalid_parameters"
	return &""

func validated_snapshot() -> Dictionary:
	if get_script()!=load("res://scripts/simulation/unified_edit/tool_profile.gd"):return {"error":&"invalid_profile_type"}
	if String(profile_id).is_empty() or version<1 or version>4294967295:return {"error":&"invalid_profile_identity"}
	var error:=combination_error()
	if not error.is_empty():return {"error":error}
	var waters: Array=Array(allowed_water_policies) if not allowed_water_policies.is_empty() else [water_policy]
	var materials: Array=Array(allowed_material_policies) if not allowed_material_policies.is_empty() else [material_policy]
	if waters.size()>4 or materials.size()>3 or not water_policy in waters or not material_policy in materials:return {"error":&"invalid_feature_choices"}
	var seen_water:={};var seen_material:={}
	for value in waters:
		if value not in [0,1,2,3] or seen_water.has(value):return {"error":&"invalid_feature_choices"}
		seen_water[value]=true
	for value in materials:
		if value not in MaterialPolicy.values() or seen_material.has(value):return {"error":&"invalid_feature_choices"}
		seen_material[value]=true
	for water in waters:
		for material in materials:
			var candidate=duplicate(true)
			candidate.water_policy=water;candidate.material_policy=material
			if not candidate.combination_error().is_empty():return {"error":&"unsupported_feature_choices"}
	# The legacy ordinary swept brush accepts a bounded whole-domain segment;
	# shape strokes retain their frozen two-metre segment limit.
	var segment_limit:=64.0 if operation==Operation.VOLUME_DELTA and shape==Shape.SWEPT_CAPSULE else 2.0
	if not finite_number(sample_spacing_m) or not finite_number(max_segment_m) or sample_spacing_m<=0.0 or sample_spacing_m>max_segment_m or max_segment_m>segment_limit or max_buffer_points<2 or max_buffer_points>256:return {"error":&"invalid_sampling"}
	var keys:=parameter_keys()
	if defaults.size()!=keys.size() or ranges.size()!=keys.size():return {"error":&"invalid_parameter_schema"}
	for key in keys:
		if not defaults.has(key) or not ranges.has(key) or not ranges[key] is Array or ranges[key].size()!=2:return {"error":&"invalid_parameter_schema"}
		if not finite_number(ranges[key][0]) or not finite_number(ranges[key][1]) or float(ranges[key][0])>float(ranges[key][1]):return {"error":&"invalid_parameter_schema"}
		var limits:=_capability_limits(key)
		if ranges[key][0]<limits[0] or ranges[key][1]>limits[1]:return {"error":&"unsupported_parameter_range"}
	error=parameter_error(defaults)
	if not error.is_empty():return {"error":error}
	if defaults.has("speed_m_s") and water_policy!=3 and defaults.speed_m_s!=0.0:return {"error":&"unsupported_combination"}
	var template: Dictionary={}
	if shape_resource!=null:
		var checked: Dictionary=shape_resource.validated_snapshot()
		if not checked.error.is_empty():return checked
		template=checked.value
	var value:={"schema":1,"profile_id":String(profile_id),"version":version,"operation":operation,"shape":shape,"destination":destination,"volume_sign":volume_sign,"height_reference":height_reference,"target_rule":target_rule,"transfer_policy":transfer_policy,"material_policy":material_policy,"water_policy":water_policy,"stroke_policy":stroke_policy,"derived_fields":derived_fields(),"defaults":defaults.duplicate(true),"ranges":ranges.duplicate(true),"sampling":{"spacing_m":sample_spacing_m,"max_segment_m":max_segment_m,"max_buffer_points":max_buffer_points},"template":template,"display_name":display_name}
	value.allowed_features={"water_policy":waters,"material_policy":materials}
	value.resource_identity={"path":resource_path,"sha256":FileAccess.get_sha256(resource_path) if not resource_path.is_empty() else "","model_sha256":get_script().source_code.sha256_text()}
	value.profile_hash=JSON.stringify(value,"",true).sha256_text()
	return {"error":&"","value":value}

func _capability_limits(key: String) -> Array:
	match key:
		"radius_m":return [0.0,4.0]
		"amount_m3":return [0.01,1.0]
		"strength":return [0.0,1.0]
		"speed_m_s":return [-1.0,1.0]
		"height_m":return [0.5,1.0] if shape==Shape.HEIGHT_STAMP else [0.15,0.6]
		"scale_xz":return [1.0,1.5]
		"yaw_rad":return [-PI,PI]
		"bottom_width_m":return [1.0,2.0]
		"top_width_m":return [0.5,1.5]
		"depth_m":return [0.05,0.3]
		"trench_width_m","shoulder_width_m":return [0.5,1.0]
	return []
