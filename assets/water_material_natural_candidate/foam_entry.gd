extends "res://assets/water_material_natural_candidate/optics_entry.gd"

@export_file("*.json") var foam_profile_path := "res://assets/water_material_natural_candidate/foam_baseline.json"
var foam_profile := {}
var effective_foam := {}
var contact_geometry := {}
var contact_geometry_defaults := {}
var contact_geometry_origins := {}

func _ready() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(foam_profile_path))
	if not p is Dictionary:
		_reject("invalid_foam_profile");return
	var root_keys:=["foam_schema_version","optics_profile","optics_profile_sha256","base_profile","water_shader","fine_shader","contact_shader","main","fine","contact"]
	if p.get("foam_schema_version",0)==3:root_keys.append("geometry_bindings")
	if not _keys(p,root_keys):_reject("invalid_foam_profile");return
	foam_profile=p
	if not _number(p.foam_schema_version,1,3) or not is_equal_approx(float(p.foam_schema_version),round(float(p.foam_schema_version))) or not _resource_path(p.optics_profile) or FileAccess.get_sha256(p.optics_profile)!=p.optics_profile_sha256:
		_reject("invalid_foam_identity");return
	for key in ["base_profile","water_shader","fine_shader","contact_shader"]:
		if not _resource_path(p[key]): _reject("missing_foam_resource");return
	for key in ["water_shader","fine_shader","contact_shader"]:
		if not load(p[key]) is Shader: _reject("invalid_foam_shader");return
	var contact_keys:=["enabled","gain","surface_offset_m"]
	if p.foam_schema_version>=2:contact_keys.append_array(["surface_mode","separation_m"])
	if p.foam_schema_version==3:contact_keys.append_array(["shape_mode","shape_scale_per_m"])
	if not p.main is Dictionary or not _keys(p.main,["enabled","gain"]) or not p.contact is Dictionary or not _keys(p.contact,contact_keys) or not p.fine is Dictionary or not _keys(p.fine,["enabled","size_mode","size_range","gain","clustering_strength","clustering_scale_per_m","jitter_m","direct_fraction"]):
		_reject("invalid_foam_fields");return
	if p.foam_schema_version==3:
		if p.contact.shape_mode not in ["legacy","multiscale"] or not _number(p.contact.shape_scale_per_m,1,80) or not _resource_path(p.geometry_bindings):
			_reject("invalid_contact_shape");return
	if p.foam_schema_version>=2:
		if p.contact.surface_mode not in ["legacy","shared_water"] or not _number(p.contact.separation_m,0,.01):
			_reject("invalid_contact_surface");return
		var bindings_path:String=p.geometry_bindings if p.foam_schema_version==3 else "res://assets/water_material_natural_candidate/contact_geometry_bindings.json"
		var geometry:Variant=JSON.parse_string(FileAccess.get_file_as_string(bindings_path))
		if not geometry is Dictionary or geometry.source_water_shader!=p.water_shader or geometry.source_sha256!=FileAccess.get_sha256(p.water_shader) or geometry.generated_shader_sha256!=FileAccess.get_sha256(p.contact_shader):
			_reject("invalid_contact_geometry_identity");return
		contact_geometry=geometry
	for layer in [p.main,p.fine,p.contact]:
		if typeof(layer.enabled)!=TYPE_BOOL or not _number(layer.gain,0,2): _reject("invalid_foam_layer");return
	var f: Dictionary=p.fine
	if f.size_mode not in ["legacy","weighted"] or not f.size_range is Array or f.size_range.size()!=2:
		_reject("invalid_foam_size");return
	if not _number(f.size_range[0],.1,3) or not _number(f.size_range[1],.1,3) or f.size_range[0]>f.size_range[1] or not _number(f.clustering_strength,0,1) or not _number(f.clustering_scale_per_m,.05,4) or not _number(f.jitter_m,0,.2) or not _number(f.direct_fraction,0,1) or not _number(p.contact.surface_offset_m,0,.03):
		_reject("invalid_foam_range");return
	optics_profile_path=p.optics_profile
	super._ready()

func _candidate_base_profile_path() -> String:
	return foam_profile.base_profile

func _candidate_water_shader_path() -> String:
	return foam_profile.water_shader

func _configure_scene() -> void:
	super._configure_scene()
	var f: Dictionary=foam_profile.fine
	water_material.set_shader_parameter("natural_main_foam_gain",foam_profile.main.gain if foam_profile.main.enabled else 0.0)
	var fine: ShaderMaterial=$PrototypeFrontFoamDense.material_override
	fine.shader=load(foam_profile.fine_shader)
	fine.set_shader_parameter("natural_fine_enabled",f.enabled)
	fine.set_shader_parameter("natural_fine_size_mode",0 if f.size_mode=="legacy" else 1)
	fine.set_shader_parameter("natural_fine_size_range",Vector2(f.size_range[0],f.size_range[1]))
	fine.set_shader_parameter("natural_fine_gain",f.gain)
	fine.set_shader_parameter("natural_cluster_strength",f.clustering_strength)
	fine.set_shader_parameter("natural_cluster_scale_per_m",f.clustering_scale_per_m)
	fine.set_shader_parameter("splat_jitter_m",f.jitter_m)
	fine.set_shader_parameter("natural_foam_direct_fraction",f.direct_fraction)
	var contact: ShaderMaterial=$ShoreContactOverlay.material_override
	contact.shader=load(foam_profile.contact_shader)
	contact.set_shader_parameter("natural_contact_enabled",foam_profile.contact.enabled)
	contact.set_shader_parameter("natural_contact_gain",foam_profile.contact.gain)
	contact.set_shader_parameter("surface_offset_m",foam_profile.contact.surface_offset_m)
	if foam_profile.foam_schema_version>=2:
		contact.set_shader_parameter("natural_contact_shared_surface",foam_profile.contact.surface_mode=="shared_water")
		contact.set_shader_parameter("natural_contact_separation_m",foam_profile.contact.separation_m)
		_sync_contact_geometry()
	if foam_profile.foam_schema_version==3:
		contact.set_shader_parameter("natural_contact_shape_mode",1 if foam_profile.contact.shape_mode=="multiscale" else 0)
		contact.set_shader_parameter("natural_contact_shape_scale_per_m",foam_profile.contact.shape_scale_per_m)

func _sync_contact_geometry() -> void:
	if foam_profile.get("foam_schema_version",1)<2 or water_material==null:return
	var contact:ShaderMaterial=$ShoreContactOverlay.material_override
	for name in contact_geometry.geometry_uniforms:
		var value:Variant=water_material.get_shader_parameter(name)
		var origin:="water_material"
		if value==null:
			if not contact_geometry_defaults.has(name):
				contact_geometry_defaults[name]=RenderingServer.shader_get_parameter_default(water_material.shader.get_rid(),name)
			value=contact_geometry_defaults[name]
			origin="water_shader_default"
		contact.set_shader_parameter(name,value)
		contact_geometry_origins[name]={"origin":origin,"value":str(value)}

func _seal_test1_effective_profile() -> void:
	super._seal_test1_effective_profile()
	_sync_contact_geometry()
	var fine: ShaderMaterial=$PrototypeFrontFoamDense.material_override
	var contact: ShaderMaterial=$ShoreContactOverlay.material_override
	var mesh: ArrayMesh=$PrototypeFrontFoamDense.mesh
	var counts:=_candidate_mesh_counts(mesh)
	effective_foam={"schema":foam_profile.foam_schema_version,"profile":foam_profile_path,"profile_sha256":_candidate_digest(foam_profile_path),
		"main_gain":water_material.get_shader_parameter("natural_main_foam_gain"),"source_main_gain":water_material.get_shader_parameter("test1_whitewater_gain"),
		"fine_shader":fine.shader.resource_path,"fine_shader_sha256":_candidate_digest(fine.shader.resource_path),
		"contact_shader":contact.shader.resource_path,"contact_shader_sha256":_candidate_digest(contact.shader.resource_path),
		"mesh":mesh.resource_path,"mesh_sha256":_candidate_digest(mesh.resource_path),
		"mesh_vertices":counts.x,"mesh_indices":counts.y,"new_visual_history":false}
	for name in ["natural_fine_enabled","natural_fine_size_mode","natural_fine_size_range","natural_fine_gain","natural_cluster_strength","natural_cluster_scale_per_m","splat_jitter_m","natural_foam_direct_fraction"]:
		effective_foam[name]=str(fine.get_shader_parameter(name))
	for name in ["natural_contact_enabled","natural_contact_gain","surface_offset_m"]:
		effective_foam[name]=contact.get_shader_parameter(name)
	if foam_profile.foam_schema_version>=2:
		effective_foam["surface_mode"]=foam_profile.contact.surface_mode
		effective_foam["natural_contact_shared_surface"]=contact.get_shader_parameter("natural_contact_shared_surface")
		effective_foam["natural_contact_separation_m"]=contact.get_shader_parameter("natural_contact_separation_m")
		effective_foam["contact_geometry_bindings"]=contact_geometry_origins.duplicate(true)
	if foam_profile.foam_schema_version==3:
		effective_foam["natural_contact_shape_mode"]=contact.get_shader_parameter("natural_contact_shape_mode")
		effective_foam["natural_contact_shape_scale_per_m"]=contact.get_shader_parameter("natural_contact_shape_scale_per_m")
		effective_foam["geometry_bindings_resource"]=foam_profile.geometry_bindings
