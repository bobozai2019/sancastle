extends SceneTree

## Offline authoring only. Runtime never rebuilds fixed meshes or node trees.
const Species=preload("res://scripts/visual/vegetation_species.gd")
const Profile=preload("res://scripts/visual/vegetation_profile.gd")
const NAMES=Profile.KINDS
var errors: Array=[]

func _initialize() -> void:
	call_deferred("_build")

func _save(resource: Resource,path: String) -> void:
	if ResourceSaver.save(resource,path)!=OK:errors.append(path)
	else:resource.take_over_path(path)

func _build() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/vegetation")
	var profile=Profile.new()
	# Scale factors for the original proxies; not physical leaf heights.
	var configuration=[
		["海草",0.015,1.8,0.90,1.55,0.98,0.58,1.7,0.24,1.0,6.0],
		["海带",0.35,3.0,1.10,1.85,0.46,0.85,1.5,0.36,0.90,4.5],
		["水牛草",0.0,0.018,0.85,1.45,0.92,0.45,1.2,0.28,1.0,7.0],
		["灰色丛草",0.0,0.012,0.90,1.35,0.55,0.6,1.3,0.38,0.85,5.5],
		["红藻",0.12,2.4,0.50,0.90,0.30,0.68,1.7,0.52,0.90,5.0],
		["柳枝稷",0.0,0.015,0.85,1.30,0.56,0.5,1.2,0.48,1.0,6.0],
		["麦草",0.0,0.012,0.70,1.05,0.22,0.5,1.1,0.65,1.0,6.0],
		["西洋蓍草",0.0,0.008,0.85,1.20,0.12,0.45,1.1,0.68,1.0,7.0],
		["一枝黄花",0.0,0.008,0.75,1.15,0.10,0.45,1.1,0.62,0.90,7.0]]
	for kind in NAMES.size():
		var row: Array=configuration[kind]
		var species=Species.new()
		species.label=row[0];species.depth_min_m=row[1];species.depth_max_m=row[2]
		species.scale_min=row[3];species.scale_max=row[4];species.density=row[5]
		species.flow_response=row[6];species.max_slope=row[7];species.patch_min=row[8]
		species.patch_max=row[9];species.response_hz=row[10]
		profile.species.append(species)
		_save(species,"res://assets/vegetation/"+NAMES[kind]+"_species.tres")
		var proxy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/vegetation/competitor/"+NAMES[kind]+"_proxy.json"))
		var pivot: Array=proxy.pivot
		var material_text:="[gd_resource type=\"ShaderMaterial\" load_steps=3 format=3]\n\n[ext_resource type=\"Shader\" path=\"res://shaders/visual/vegetation.gdshader\" id=\"1\"]\n[ext_resource type=\"Texture2D\" path=\"res://assets/vegetation/competitor/%s_atlas.png\" id=\"2\"]\n\n[resource]\nresource_local_to_scene = true\nshader = ExtResource(\"1\")\nshader_parameter/kind = %d\nshader_parameter/seed = 62143\nshader_parameter/atlas = ExtResource(\"2\")\nshader_parameter/atlas_grid = %d.0\nshader_parameter/pivot_offset = Vector4(%.9f, %.9f, %.9f, %.9f)\n"%[NAMES[kind],kind,proxy.atlas_grid,pivot[0],pivot[1],pivot[2],pivot[3]]
		FileAccess.open("res://assets/vegetation/"+NAMES[kind]+"_material.tres",FileAccess.WRITE).store_string(material_text)
		var mesh:=_mesh(kind)
		mesh.resource_name=NAMES[kind]+"_leaf_clump"
		_save(mesh,"res://assets/vegetation/"+NAMES[kind]+"_mesh.tres")
		# MultiMesh buffers are renderer-owned too. Explicit identity matrices
		# survive dummy-renderer authoring and cannot collapse the live mesh.
		var transforms:=PackedStringArray()
		for index in Profile.CANDIDATES_PER_KIND:transforms.append("1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0")
		var multi_text:="[gd_resource type=\"MultiMesh\" load_steps=2 format=3]\n\n[ext_resource type=\"ArrayMesh\" path=\"res://assets/vegetation/%s_mesh.tres\" id=\"1\"]\n\n[resource]\nresource_local_to_scene = true\ntransform_format = 1\nmesh = ExtResource(\"1\")\ninstance_count = %d\ncustom_aabb = AABB(-17, -2, -17, 34, 16, 34)\nbuffer = PackedFloat32Array(%s)\n"%[NAMES[kind],Profile.CANDIDATES_PER_KIND,", ".join(transforms)]
		FileAccess.open("res://assets/vegetation/"+NAMES[kind]+"_instances.tres",FileAccess.WRITE).store_string(multi_text)
	_save(profile,"res://assets/vegetation/default_profile.tres")
	var lines:=PackedStringArray(["[gd_scene load_steps=21 format=3]","",
		"[ext_resource type=\"Script\" path=\"res://scripts/visual/vegetation_layer.gd\" id=\"1\"]",
		"[ext_resource type=\"Resource\" path=\"res://assets/vegetation/default_profile.tres\" id=\"2\"]"])
	for kind in NAMES.size():
		lines.append("[ext_resource type=\"MultiMesh\" path=\"res://assets/vegetation/%s_instances.tres\" id=\"m%d\"]"%[NAMES[kind],kind])
		lines.append("[ext_resource type=\"Material\" path=\"res://assets/vegetation/%s_material.tres\" id=\"s%d\"]"%[NAMES[kind],kind])
	lines.append_array(PackedStringArray(["","[node name=\"VegetationLayer\" type=\"Node3D\"]","script = ExtResource(\"1\")","profile = ExtResource(\"2\")"]))
	for kind in NAMES.size():
		lines.append_array(PackedStringArray(["","[node name=\"%s\" type=\"MultiMeshInstance3D\" parent=\".\"]"%NAMES[kind],
			"layers = 5","cast_shadow = %d"% (0 if kind==0 else 1),
			"material_override = ExtResource(\"s%d\")"%kind,"multimesh = ExtResource(\"m%d\")"%kind]))
	FileAccess.open("res://scenes/components/vegetation_layer.tscn",FileAccess.WRITE).store_string("\n".join(lines)+"\n")
	var stats: Dictionary={"generator_sha256":FileAccess.get_sha256(get_script().resource_path),"profile":profile.snapshot("main"),"geometry":[]}
	for kind in NAMES.size():
		var mesh: ArrayMesh=load("res://assets/vegetation/"+NAMES[kind]+"_mesh.tres")
		stats.geometry.append({"kind":NAMES[kind],"vertices":mesh.surface_get_array_len(0),"sha256":FileAccess.get_sha256(mesh.resource_path)})
	FileAccess.open("res://assets/vegetation/geometry_manifest.json",FileAccess.WRITE).store_string(JSON.stringify(stats,"\t")+"\n")
	print("VEGETATION_ASSETS ",JSON.stringify({"errors":errors,"species":profile.species.size(),"capacity":Profile.CANDIDATES_PER_KIND*NAMES.size()}))
	quit(0 if errors.is_empty() else 1)

func _mesh(kind: int) -> ArrayMesh:
	var proxy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/vegetation/competitor/"+NAMES[kind]+"_proxy.json"))
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in proxy.triangles:
		for index in triangle:
			var v: Array=proxy.vertices[index];var n: Array=proxy.normals[index]
			tool.set_normal(Vector3(n[0],n[1],n[2]))
			tool.add_vertex(Vector3(v[0],v[1],v[2]))
	return tool.commit()
