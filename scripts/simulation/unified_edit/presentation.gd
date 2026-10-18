extends RefCounted

# Loads an offline extracted, scene-authored presentation. This component never
# constructs a legacy entry or writes simulation state.
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const SOURCES=["res://scripts/simulation/unified_edit/presentation.gd"]

static func read(path: String) -> Dictionary:
	var document: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not document is Dictionary or document.get("pass")!=true:return {"error":&"invalid_presentation_manifest"}
	var data: Variant=document.get("metadata")
	if not data is Dictionary or data.get("version")!=1:return {"error":&"invalid_presentation_version"}
	for key in ["scene","seed"]:
		if not data.get(key) is Dictionary:return {"error":&"invalid_presentation_artifact"}
		var item: Dictionary=data[key]
		if not item.get("path") is String or not FileAccess.file_exists(item.path) or FileAccess.get_sha256(item.path)!=item.get("sha256"):return {"error":&"presentation_artifact_changed"}
	if not data.get("materials") is Array or not data.get("bindings") is Array or not data.get("settings") is Dictionary or data.get("unknown_dynamic",[true])!=[]:return {"error":&"invalid_presentation_layout"}
	for material in data.materials:
		if not material is Dictionary or not material.get("fields") is Dictionary or FileAccess.get_sha256(material.get("shader",""))!=material.get("shader_sha256"):return {"error":&"presentation_shader_changed"}
	return {"error":&"","metadata":data.duplicate(true)}

static func initial_domain(data: Dictionary, epoch: int) -> Dictionary:
	var bytes:=FileAccess.get_file_as_bytes(data.seed.path)
	if bytes.size()>32*1024*1024:return {"error":&"presentation_seed_size"}
	var value: Variant=bytes_to_var(bytes)
	if not value is Dictionary or value.get("grid_size")!=256 or value.get("cell_size_m")!=0.125:return {"error":&"presentation_seed_invalid"}
	var domain=Domain.new(256,0.125)
	if not domain.restore(value):return {"error":&"presentation_seed_invalid"}
	domain.generation=epoch
	for key in value.get("metadata",{}):domain.set_meta(key,value.metadata[key])
	return {"error":&"","domain":domain}

static func material_plan(scene: Node, data: Dictionary, root_script: Script=null) -> Dictionary:
	if scene.get_script()!=root_script or scene.has_node("GpuCollisionProxy"):return {"error":&"presentation_legacy_root"}
	if root_script!=null and (root_script.get_base_script()!=null or root_script.get_instance_base_type()!=&"Node3D"):return {"error":&"presentation_legacy_root"}
	var plans: Dictionary={};var identities: Dictionary={}
	for binding in data.bindings:
		if not binding is Dictionary or not binding.get("path") is String or not binding.get("material_id") is float and not binding.get("material_id") is int:return {"error":&"presentation_binding_invalid"}
		var index:=int(binding.material_id)
		if binding.material_id!=index or index<0 or index>=data.materials.size():return {"error":&"presentation_binding_invalid"}
		var parts: PackedStringArray=binding.path.rsplit(":",true,1)
		if parts.size()!=2:return {"error":&"presentation_binding_invalid"}
		var node:=scene.get_node_or_null(parts[0]);var material: Material
		if node==null:return {"error":&"presentation_binding_missing"}
		if parts[1] in ["material_override","material_overlay"] and node is GeometryInstance3D:material=node.get(parts[1])
		elif parts[1].begins_with("surface_") and node is MeshInstance3D:material=node.get_surface_override_material(int(parts[1].trim_prefix("surface_")))
		if not material is ShaderMaterial or material.shader.resource_path!=data.materials[index].shader:return {"error":&"presentation_binding_material"}
		if identities.has(index) and identities[index]!=material.get_instance_id():return {"error":&"presentation_shared_material_changed"}
		identities[index]=material.get_instance_id()
		for uniform in data.materials[index].fields:
			if material.get_shader_parameter(uniform)!=null:return {"error":&"presentation_sampler_already_owned"}
		if not data.materials[index].fields.is_empty():plans[index]={"material":material,"parameters":data.materials[index].fields.duplicate(true)}
	return {"error":&"","bindings":plans.values(),"materials":identities.size()}

static func dependencies(paths: PackedStringArray) -> Dictionary:
	var visited: Dictionary={};var pending: Array=Array(paths)
	while not pending.is_empty():
		var path: String=pending.pop_back()
		if visited.has(path):continue
		if not path.begins_with("res://") or not FileAccess.file_exists(path):return {"error":&"presentation_dependency_missing","path":path}
		visited[path]=true
		if visited.size()>2048:return {"error":&"presentation_dependency_limit"}
		# Pin import settings and the produced resource binaries too. A source
		# PNG/font hash alone cannot identify what ResourceLoader consumes.
		var import_path:=path+".import"
		if FileAccess.file_exists(import_path):
			pending.append(import_path)
			var imported:=ConfigFile.new()
			if imported.load(import_path)!=OK:return {"error":&"presentation_import_invalid","path":import_path}
			if imported.has_section("remap"):
				for key in imported.get_section_keys("remap"):
					if key=="path" or key.begins_with("path."):
						var target: Variant=imported.get_value("remap",key)
						if target is String and FileAccess.file_exists(target):pending.append(target)
		if path.get_extension() in ["tscn","tres","res","scn"]:
			for dependency in ResourceLoader.get_dependencies(path):
				var resolved: String=dependency.split("::")[-1]
				if resolved.begins_with("uid://"):resolved=ResourceUID.get_id_path(ResourceUID.text_to_id(resolved))
				pending.append(resolved)
	return {"error":&"","sources":PackedStringArray(visited.keys())}
