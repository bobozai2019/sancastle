extends "res://assets/water_material_natural_candidate/reflection_entry.gd"

@export_file("*.json") var style_profile_path:="res://assets/water_material_natural_candidate/style_baseline.json"
var style_profile:={}
var effective_style:={}
var rdc_material_profile:={}

func _ready() -> void:
	var p:Variant=JSON.parse_string(FileAccess.get_file_as_string(style_profile_path))
	var keys:=["style_schema_version","reflection_profile","reflection_profile_sha256","base_profile","bed_shader","bed_shader_sha256","source_bed_shader","source_bed_shader_sha256","caustics","glint","detail_gain_multiplier"]
	if p is Dictionary and (p.get("style_schema_version")==2 or p.get("style_schema_version")==3 or p.get("style_schema_version")==4):keys.append("macro_normal_mode")
	if p is Dictionary and (p.get("style_schema_version")==3 or p.get("style_schema_version")==4):keys.append("normal_frequency_multiplier")
	if p is Dictionary and p.get("style_schema_version")==4:keys.append_array(["rdc_material_profile","rdc_material_profile_sha256"])
	if not p is Dictionary or not _keys(p,keys):
		_reject("invalid_style_profile");return
	if not (_number(p.style_schema_version,1,1) or _number(p.style_schema_version,2,2) or _number(p.style_schema_version,3,3) or _number(p.style_schema_version,4,4)):_reject("invalid_style_version");return
	if p.style_schema_version>=2 and p.macro_normal_mode not in ["legacy_eta","height_surface"]:
		_reject("invalid_macro_normal_mode");return
	for name in ["reflection_profile","bed_shader","source_bed_shader"]:
		if not _resource_path(p[name]) or FileAccess.get_sha256(p[name])!=p[name+"_sha256"]:
			_reject("style_resource_hash_mismatch");return
	if not _resource_path(p.base_profile) or not load(p.bed_shader) is Shader:
		_reject("missing_style_resource");return
	if not p.caustics is Dictionary or not _keys(p.caustics,["enabled","strength","softness","uv_scale"]) or not p.glint is Dictionary or not _keys(p.glint,["gain","exponent"]):
		_reject("invalid_style_fields");return
	if typeof(p.caustics.enabled)!=TYPE_BOOL or not _number(p.caustics.strength,0,2) or not _number(p.caustics.softness,0,1) or not _number(p.caustics.uv_scale,.1,8) or not _number(p.glint.gain,0,2) or not _number(p.glint.exponent,4,2048 if p.style_schema_version==4 else 256) or not _number(p.detail_gain_multiplier,0,8):
		_reject("invalid_style_range");return
	if p.style_schema_version>=3 and not _number(p.normal_frequency_multiplier,1,4):
		_reject("invalid_normal_frequency_multiplier");return
	if p.style_schema_version==4 and not _load_rdc_material(p):return
	var reflection:Variant=JSON.parse_string(FileAccess.get_file_as_string(p.reflection_profile))
	if p.style_schema_version>=2:
		var candidate_shader:Resource=load(reflection.get("water_shader","")) if reflection is Dictionary else null
		var found:=false
		if candidate_shader is Shader:
			for u in candidate_shader.get_shader_uniform_list():
				if u.name=="natural_height_surface_normal":found=true
		if not found:_reject("missing_macro_normal_interface");return
	var expected:Variant=JSON.parse_string(FileAccess.get_file_as_string(reflection.get("base_profile",""))) if reflection is Dictionary else null
	var actual:Variant=JSON.parse_string(FileAccess.get_file_as_string(p.base_profile))
	if not expected is Dictionary or not actual is Dictionary or expected.resources.terrain_fixed_shader!=p.source_bed_shader or expected.resources.terrain_coupled_shader!=p.source_bed_shader:
		_reject("invalid_style_base");return
	expected.resources.terrain_fixed_shader=p.bed_shader;expected.resources.terrain_coupled_shader=p.bed_shader
	if expected!=actual:_reject("style_changed_nonvisual_inputs");return
	style_profile=p;reflection_profile_path=p.reflection_profile
	super._ready()

func _candidate_base_profile_path() -> String:
	return style_profile.base_profile

func _candidate_apply_expected_visual_paths(expected: Dictionary) -> void:
	expected.resources.terrain_fixed_shader=style_profile.bed_shader
	expected.resources.terrain_coupled_shader=style_profile.bed_shader

func _configure_scene() -> void:
	super._configure_scene()
	terrain_material.set_shader_parameter("natural_caustic_override",true)
	terrain_material.set_shader_parameter("natural_caustic_enabled",style_profile.caustics.enabled)
	terrain_material.set_shader_parameter("natural_caustic_strength",style_profile.caustics.strength)
	terrain_material.set_shader_parameter("natural_caustic_softness",style_profile.caustics.softness)
	terrain_material.set_shader_parameter("natural_caustic_uv_scale",style_profile.caustics.uv_scale)
	water_material.set_shader_parameter("natural_glint_gain",style_profile.glint.gain)
	water_material.set_shader_parameter("natural_glint_exponent",style_profile.glint.exponent)
	for i in range(2):
		var layer:Vector4=water_material.get_shader_parameter("natural_layer%d"%i)
		layer.z*=style_profile.detail_gain_multiplier
		if style_profile.style_schema_version>=3:layer.x*=style_profile.normal_frequency_multiplier
		if layer.z>.5:_fail("style_detail_gain_outside_source_range");return
		water_material.set_shader_parameter("natural_layer%d"%i,layer)
	if style_profile.style_schema_version>=2:
		if style_profile.macro_normal_mode=="height_surface":
			for name in ["prototype_curl_forward_m","prototype_local_overturn_m"]:
				var value:Variant=water_material.get_shader_parameter(name)
				if value==null:value=RenderingServer.shader_get_parameter_default(water_material.shader.get_rid(),name)
				if (not value is float and not value is int) or absf(float(value))>0.000001:
					_fail("height_macro_requires_height_surface");return
		water_material.set_shader_parameter("natural_height_surface_normal",style_profile.macro_normal_mode=="height_surface")
	if style_profile.style_schema_version==4:_configure_rdc_material()

var style_sun_transform: Transform3D

func _sync_sun() -> void:
	super._sync_sun()
	var transform: Transform3D = $SandFixtureSun.global_transform
	if transform != style_sun_transform:
		style_sun_transform = transform
		if not effective_style.is_empty():
			effective_style["sun_transform"] = var_to_str(transform)
			invalidate_effective_render_profile()

func set_visual_time(seconds: float) -> void:
	super.set_visual_time(seconds)
	if not effective_style.is_empty():
		effective_style["visual_time_s"] = seconds

func _seal_test1_effective_profile() -> void:
	super._seal_test1_effective_profile()
	effective_style={"schema":style_profile.style_schema_version,"profile":style_profile_path,"profile_sha256":_candidate_digest(style_profile_path),
		"base_profile":render_profile_path,"bed_shader":terrain_material.shader.resource_path,
		"bed_shader_sha256":_candidate_digest(terrain_material.shader.resource_path),
		"source_bed_shader":style_profile.source_bed_shader,"source_bed_sha256":style_profile.source_bed_shader_sha256,
		"sun_transform":var_to_str($SandFixtureSun.global_transform),"source_normal_profile":candidate_profile_path,
		"detail_gain_multiplier":style_profile.detail_gain_multiplier,"new_visual_history":false}
	if style_profile.style_schema_version>=2:
		effective_style["macro_normal_mode"]=style_profile.macro_normal_mode
		effective_style["natural_height_surface_normal"]=water_material.get_shader_parameter("natural_height_surface_normal")
		effective_style["water_shader"]=water_material.shader.resource_path
		effective_style["water_shader_sha256"]=_candidate_digest(water_material.shader.resource_path)
	if style_profile.style_schema_version>=3:
		effective_style["normal_frequency_multiplier"]=style_profile.normal_frequency_multiplier
	for name in ["natural_caustic_override","natural_caustic_enabled","natural_caustic_strength","natural_caustic_softness","natural_caustic_uv_scale","visual_time_s"]:
		effective_style[name]=terrain_material.get_shader_parameter(name)
	for name in ["natural_glint_enabled","natural_glint_gain","natural_glint_exponent","natural_layer0","natural_layer1"]:
		effective_style[name]=str(water_material.get_shader_parameter(name))
	if style_profile.style_schema_version==4:
		var volume:Variant=terrain_material.get_shader_parameter("rdc_caustic_volume")
		if not volume is Texture3D or volume.resource_path!=rdc_material_profile.caustic_texture or terrain_material.get_shader_parameter("rdc_phase_texture")!=water_material.get_shader_parameter("natural_normal_texture") or terrain_material.get_shader_parameter("rdc_momentum_x")!=momentum_x_texture or terrain_material.get_shader_parameter("rdc_momentum_z")!=momentum_z_texture:
			_fail("rdc_actual_texture_binding_mismatch");return
		var values:={}
		for name in rdc_material_profile.parameters:
			var material:ShaderMaterial=terrain_material if name.begins_with("rdc_caustic") else water_material
			var value:Variant=material.get_shader_parameter(name)
			if value!=_rdc_value(name):_fail("rdc_effective_parameter_mismatch: "+String(name));return
			values[name]=var_to_str(value)
		effective_style["rdc_material"]={"profile":style_profile.rdc_material_profile,"profile_sha256":style_profile.rdc_material_profile_sha256,"texture":rdc_material_profile.caustic_texture,"texture_sha256":rdc_material_profile.caustic_texture_sha256,"actual_uniforms":values,"scope":"Godot adaptation of captured PS; world meters/time/flow and local phase are project inputs."}

func _load_rdc_material(p: Dictionary) -> bool:
	if not _resource_path(p.rdc_material_profile) or FileAccess.get_sha256(p.rdc_material_profile)!=p.rdc_material_profile_sha256:
		_reject("rdc_profile_hash_mismatch");return false
	var q:Variant=JSON.parse_string(FileAccess.get_file_as_string(p.rdc_material_profile))
	if not q is Dictionary or not _keys(q,["rdc_schema_version","caustic_texture","caustic_texture_sha256","parameters"]) or q.rdc_schema_version!=1 or not q.parameters is Dictionary:
		_reject("invalid_rdc_profile");return false
	var ranges:={"rdc_distance_scale":[.05,8.],"rdc_normal_scale":[.05,1.],"rdc_normal_gain":[0.,1.],"rdc_time_scale":[.01,3.],"rdc_surface_gain":[0.,1.],"rdc_refraction_scale":[0.,.03],"rdc_caustic_scale":[.05,1.],"rdc_caustic_depth_decay":[.01,12.],"rdc_caustic_time_scale":[.01,3.]}
	var names:=ranges.keys();names.append_array(["rdc_optics_enabled","rdc_normal_enabled","rdc_refracted_path","rdc_caustics_enabled","rdc_absorption_rgb","rdc_transmission_tint","rdc_surface_color"])
	if not _keys(q.parameters,names):_reject("invalid_rdc_parameters");return false
	for name in ["rdc_optics_enabled","rdc_normal_enabled","rdc_refracted_path","rdc_caustics_enabled"]:
		if typeof(q.parameters[name])!=TYPE_BOOL:_reject("invalid_rdc_flag");return false
	for name in ranges:
		if not _number(q.parameters[name],ranges[name][0],ranges[name][1]):_reject("invalid_rdc_range");return false
	for name in ["rdc_absorption_rgb","rdc_transmission_tint","rdc_surface_color"]:
		var vector:Variant=q.parameters[name]
		if not vector is Array or vector.size()!=3:_reject("invalid_rdc_vector");return false
		for component in vector:
			if not _number(component,0.,20. if name=="rdc_absorption_rgb" else 1.):_reject("invalid_rdc_vector");return false
	if not _resource_path(q.caustic_texture) or FileAccess.get_sha256(q.caustic_texture)!=q.caustic_texture_sha256:
		_reject("rdc_texture_hash_mismatch");return false
	var texture:Resource=load(q.caustic_texture)
	if not texture is Texture3D or texture.get_width()!=256 or texture.get_height()!=256 or texture.get_depth()!=64 or not texture.has_mipmaps():
		_reject("invalid_rdc_volume");return false
	rdc_material_profile=q
	return true

func _rdc_value(name: String) -> Variant:
	var value:Variant=rdc_material_profile.parameters[name]
	return Vector3(value[0],value[1],value[2]) if value is Array else value

func _configure_rdc_material() -> void:
	for name in rdc_material_profile.parameters:
		var material:ShaderMaterial=terrain_material if name.begins_with("rdc_caustic") else water_material
		material.set_shader_parameter(name,_rdc_value(name))
	terrain_material.set_shader_parameter("rdc_caustic_volume",load(rdc_material_profile.caustic_texture))
	terrain_material.set_shader_parameter("rdc_phase_texture",water_material.get_shader_parameter("natural_normal_texture"))
	terrain_material.set_shader_parameter("rdc_momentum_x",momentum_x_texture)
	terrain_material.set_shader_parameter("rdc_momentum_z",momentum_z_texture)
