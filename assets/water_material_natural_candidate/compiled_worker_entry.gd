extends "res://assets/water_material_natural_candidate/style_worker_entry.gd"

@export_file("*.json") var compiled_bundle_path:=""
@export var compiled_bundle_sha256:=""
var compiled_bundle:={}
var compiled_constants:=[]
var effective_compilation:={}

func _ready() -> void:
	if compiled_bundle_sha256.is_empty() or FileAccess.get_sha256(compiled_bundle_path)!=compiled_bundle_sha256:
		_reject("compiled_bundle_hash_mismatch");return
	var p:Variant=JSON.parse_string(FileAccess.get_file_as_string(compiled_bundle_path))
	if not p is Dictionary or not _keys(p,["bundle_schema_version","style_profile","style_profile_sha256","source_style_profile","source_style_profile_sha256","components"]) or p.bundle_schema_version!=1 or not p.components is Array or p.components.size()!=2:
		_reject("invalid_compiled_bundle");return
	if p.style_profile!=style_profile_path or FileAccess.get_sha256(p.style_profile)!=p.style_profile_sha256 or FileAccess.get_sha256(p.source_style_profile)!=p.source_style_profile_sha256:
		_reject("compiled_profile_identity_mismatch");return
	var names:=[]
	for component in p.components:
		if not component is Dictionary or not _keys(component,["material","shader","shader_sha256","index","index_sha256"]) or component.material not in ["water","bed"] or component.material in names:
			_reject("invalid_compiled_component");return
		names.append(component.material)
		if FileAccess.get_sha256(component.shader)!=component.shader_sha256 or FileAccess.get_sha256(component.index)!=component.index_sha256:
			_reject("compiled_component_hash_mismatch");return
		var index:Variant=JSON.parse_string(FileAccess.get_file_as_string(component.index))
		if not index is Dictionary or not index.get("constants") is Dictionary or index.get("generated_sha256")!=component.shader_sha256 or index.constants.is_empty():
			_reject("invalid_compiled_constants");return
		compiled_constants.append(index.constants)
	compiled_bundle=p
	super._ready()

func _configure_scene() -> void:
	super._configure_scene()
	_validate_compiled_inputs()

func _validate_compiled_inputs() -> bool:
	var actual_rows:=[]
	for i in compiled_bundle.components.size():
		var component:Dictionary=compiled_bundle.components[i]
		var material:ShaderMaterial=water_material if component.material=="water" else terrain_material
		if material.shader.resource_path!=component.shader:
			_fail("compiled_shader_path_mismatch");return false
		var values:={}
		for key in compiled_constants[i]:
			var value:Variant=material.get_shader_parameter(key)
			if value==null:value=RenderingServer.shader_get_parameter_default(material.shader.get_rid(),key)
			if value!=compiled_constants[i][key]:
				_fail("compiled_constant_mismatch: "+String(key));return false
			values[key]=value
		actual_rows.append({"material":component.material,"shader":component.shader,"shader_sha256":component.shader_sha256,"constants":values})
	effective_compilation={"bundle":compiled_bundle_path,"bundle_sha256":compiled_bundle_sha256,"components":actual_rows,"scope":"Fixed profile compiler variant; nonmatching constant changes rejected."}
	return true

func _seal_test1_effective_profile() -> void:
	if not _validate_compiled_inputs():return
	super._seal_test1_effective_profile()
