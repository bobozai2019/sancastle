extends RefCounted

const Profile=preload("res://scripts/simulation/unified_edit/tool_profile.gd")
const Layout=preload("res://scripts/simulation/unified_edit/layout.gd")
const MAX_PROFILES:=Layout.MAX_PROFILES
const MAX_TEMPLATES:=Layout.MAX_TEMPLATES
var _entries: Dictionary={}
var _templates: Dictionary={}
var _template_indices: Dictionary={}

func initialize(resources: Array) -> StringName:
	if not _entries.is_empty():return &"registry_already_initialized"
	if resources.is_empty():return &"empty_registry"
	if resources.size()>MAX_PROFILES:return &"profile_capacity"
	var pending:={}
	var templates:={}
	for resource in resources:
		if not resource is Profile or resource.get_script()!=Profile:return &"invalid_profile_type"
		var checked: Dictionary=resource.validated_snapshot()
		if not checked.error.is_empty():return checked.error
		var key: String=checked.value.profile_id
		if pending.has(key):return &"duplicate_profile"
		if not checked.value.template.is_empty():
			var info: Dictionary=checked.value.template
			var bytes:=FileAccess.get_file_as_bytes(info.payload_path)
			if Profile.Stamp.bytes_sha256(bytes)!=info.sha256:return &"template_changed_during_registration"
			templates[info.sha256]=bytes.duplicate()
		pending[key]=checked.value.duplicate(true)
	if templates.size()>MAX_TEMPLATES:return &"template_capacity"
	var hashes:=templates.keys();hashes.sort()
	for index in hashes.size():_template_indices[hashes[index]]=index+1
	_entries=pending
	_templates=templates
	return &""

func profile(id: StringName) -> Dictionary:
	return _entries.get(String(id),{}).duplicate(true)

func catalog_snapshot() -> Dictionary:
	return _entries.duplicate(true)

func template_bytes(hash: String) -> PackedByteArray:
	var bytes: PackedByteArray=_templates.get(hash,PackedByteArray())
	return bytes.duplicate()

func template_index(hash: String) -> int:
	return _template_indices.get(hash,0)

func resolve(id: Variant, version: Variant, hash: Variant, overrides: Dictionary={}, features: Dictionary={}) -> Dictionary:
	if typeof(id) not in [TYPE_STRING,TYPE_STRING_NAME] or typeof(version)!=TYPE_INT or typeof(hash)!=TYPE_STRING:return {"error":&"invalid_profile"}
	var frozen:=profile(id)
	if frozen.is_empty():return {"error":&"invalid_profile"}
	if frozen.version!=version or frozen.profile_hash!=hash:return {"error":&"profile_identity_mismatch"}
	for key in features:
		if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or not frozen.allowed_features.has(String(key)) or typeof(features[key])!=TYPE_INT or features[key] not in frozen.allowed_features[String(key)]:return {"error":&"unsupported_combination"}
		frozen[String(key)]=features[key]
	frozen.selected_features={"water_policy":frozen.water_policy,"material_policy":frozen.material_policy}
	frozen.derived_fields=Profile.fields_for(frozen.operation,frozen.destination,frozen.water_policy,frozen.stroke_policy)
	var values: Dictionary=frozen.defaults.duplicate(true)
	for key in overrides:
		if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or not values.has(String(key)) or not Profile.finite_number(overrides[key]):return {"error":&"invalid_parameters"}
		values[String(key)]=overrides[key]
	for key in values:
		var value: float=values[key]
		if value<frozen.ranges[key][0] or value>frozen.ranges[key][1] or (key in ["radius_m","amount_m3"] and value<=0.0):return {"error":&"invalid_parameters"}
	if values.has("top_width_m") and values.top_width_m>values.bottom_width_m:return {"error":&"invalid_parameters"}
	if values.has("speed_m_s") and frozen.water_policy not in [2,3] and values.speed_m_s!=0.0:return {"error":&"unsupported_combination"}
	frozen.parameters=values
	frozen.effective_hash=JSON.stringify(frozen,"",true).sha256_text()
	return {"error":&"","value":frozen}
