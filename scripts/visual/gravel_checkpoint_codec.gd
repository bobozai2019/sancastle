extends RefCounted

const Field = preload("res://scripts/visual/gpu_gravel_field.gd")
const KEYS := ["version","enabled","domain_id","profile_id","profile_sha256","profile_values","tick","revision","source_generation","current_index","state_0","state_1","width","height","count","capacity"]

static func validate(checkpoint: Dictionary, expected_profile := {}, expected_domain := "") -> StringName:
	if not checkpoint.has("visual_extensions"): return &""
	if not checkpoint.visual_extensions is Dictionary: return &"gravel_state_invalid"
	if not checkpoint.visual_extensions.has("gravel_v1"): return &""
	var ext: Variant = checkpoint.visual_extensions.gravel_v1
	if not ext is Dictionary or typeof(ext.get("version"))!=TYPE_INT: return &"gravel_state_invalid"
	if ext.version not in [1,2]: return &"unsupported_gravel_version"
	if typeof(ext.get("enabled"))!=TYPE_BOOL: return &"gravel_state_invalid"
	if not ext.enabled: return &"" if ext.size()==2 else &"gravel_state_invalid"
	if not checkpoint.get("shadow") is Dictionary: return &"gravel_state_invalid"
	if ext.size()!=KEYS.size()+(1 if ext.version==2 else 0): return &"gravel_state_invalid"
	for key in KEYS:
		if not ext.has(key): return &"gravel_state_invalid"
	var active: Variant = ext.get("active_count", ext.get("count"))
	if ext.version == 2 and not ext.has("active_count"): return &"gravel_state_invalid"
	for key in ["tick","revision","source_generation","current_index","width","height","count","capacity"]:
		if typeof(ext[key])!=TYPE_INT: return &"gravel_state_invalid"
	if typeof(active) != TYPE_INT or active < ext.count or active > 1024: return &"gravel_state_invalid"
	for key in ["domain_id","profile_id","profile_sha256"]:
		if typeof(ext[key])!=TYPE_STRING: return &"gravel_state_invalid"
	if not ext.profile_values is Dictionary: return &"invalid_gravel_profile"
	var error := Field.validate_profile(ext.profile_values,256,0.125)
	if not error.is_empty(): return error
	var domain: String = checkpoint.get("shadow",{}).get("domain_id","")
	if ext.domain_id!=domain or (not expected_domain.is_empty() and domain!=expected_domain): return &"gravel_profile_mismatch"
	var scene := "main" if domain=="main_beach" else domain
	if ext.profile_id!="gravel_v1/"+scene or ext.profile_sha256!=Field.profile_hash(ext.profile_values) or (not expected_profile.is_empty() and ext.profile_values!=expected_profile): return &"gravel_profile_mismatch"
	if ext.tick!=checkpoint.get("tick") or ext.revision!=checkpoint.get("revision") or ext.source_generation!=checkpoint.get("shadow",{}).get("generation") or ext.current_index not in [0,1] or ext.width!=64 or ext.height!=16 or ext.capacity!=1024 or ext.count!=ext.profile_values.count: return &"gravel_state_invalid"
	for key in ["state_0","state_1"]:
		if not ext[key] is PackedByteArray or ext[key].size()!=16384: return &"gravel_state_invalid"
		var values: PackedFloat32Array = ext[key].to_float32_array()
		for id in 1024:
			for k in 4:
				if not is_finite(values[id*4+k]): return &"gravel_state_invalid"
			if absf(values[id*4])>16.0 or absf(values[id*4+2])>16.0 or values[id*4+3] not in [0.0,1.0]: return &"gravel_state_invalid"
			if id>=active:
				for k in 4:
					if values[id*4+k]!=0.0: return &"gravel_state_invalid"
	return &""

static func extension(field, domain: String, states: Dictionary) -> Dictionary:
	var scene := "main" if domain=="main_beach" else domain
	return {"version":2,"enabled":true,"domain_id":domain,"profile_id":"gravel_v1/"+scene,"profile_sha256":Field.profile_hash(field.profile),"profile_values":field.profile.duplicate(true),"tick":field.completed_tick,"revision":field.revision,"source_generation":field.generation,"current_index":field.current_index,"state_0":states.state_0,"state_1":states.state_1,"width":64,"height":16,"count":field.profile.count,"capacity":1024,"active_count":field.active_count}
