extends SceneTree

## Offline authoring only. Runtime never rebuilds fixed meshes or node trees.
const Species=preload("res://scripts/visual/vegetation_species.gd")
const Profile=preload("res://scripts/visual/vegetation_profile.gd")
const NAMES=["seagrass","kelp","shore_grass","dune_grass"]
const COLORS=[
	[Color(0.12,0.23,0.065),Color(0.33,0.45,0.13)],
	[Color(0.16,0.23,0.065),Color(0.42,0.44,0.14)],
	[Color(0.20,0.25,0.065),Color(0.46,0.49,0.17)],
	[Color(0.25,0.27,0.09),Color(0.56,0.54,0.25)]]
var errors: Array=[]

func _initialize() -> void:
	call_deferred("_build")

func _save(resource: Resource,path: String) -> void:
	if ResourceSaver.save(resource,path)!=OK:errors.append(path)
	else:resource.take_over_path(path)

func _build() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/vegetation")
	var profile=Profile.new()
	var configuration=[
		["海草",0.025,1.5,0.32,0.62,0.88,0.58,1.7,0.30,1.0,6.0],
		["海带",0.18,2.8,0.65,1.15,0.64,0.85,1.5,0.42,0.85,4.5],
		["岸边矮草",0.0,0.025,0.20,0.40,0.9,0.45,1.2,0.35,1.0,7.0],
		["沙丘丛草",0.0,0.012,0.40,0.70,0.72,0.6,1.3,0.43,0.88,5.5]]
	for kind in 4:
		var row: Array=configuration[kind]
		var species=Species.new()
		species.label=row[0];species.depth_min_m=row[1];species.depth_max_m=row[2]
		species.height_min_m=row[3];species.height_max_m=row[4];species.density=row[5]
		species.flow_response=row[6];species.max_slope=row[7];species.patch_min=row[8]
		species.patch_max=row[9];species.response_hz=row[10]
		profile.species.append(species)
		_save(species,"res://assets/vegetation/"+NAMES[kind]+"_species.tres")
		# The dummy headless renderer cannot reflect shader uniforms. Author
		# their actual typed values directly instead of saving null defaults.
		var base: Color=COLORS[kind][0];var tip: Color=COLORS[kind][1]
		var material_text:="[gd_resource type=\"ShaderMaterial\" load_steps=2 format=3]\n\n[ext_resource type=\"Shader\" path=\"res://shaders/visual/vegetation.gdshader\" id=\"1\"]\n\n[resource]\nresource_local_to_scene = true\nshader = ExtResource(\"1\")\nshader_parameter/kind = %d\nshader_parameter/seed = 62143\nshader_parameter/base_color = Color(%.6f, %.6f, %.6f, 1)\nshader_parameter/tip_color = Color(%.6f, %.6f, %.6f, 1)\nshader_parameter/root_darkening = 0.25\n"%[kind,base.r,base.g,base.b,tip.r,tip.g,tip.b]
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
	var lines:=PackedStringArray(["[gd_scene load_steps=11 format=3]","",
		"[ext_resource type=\"Script\" path=\"res://scripts/visual/vegetation_layer.gd\" id=\"1\"]",
		"[ext_resource type=\"Resource\" path=\"res://assets/vegetation/default_profile.tres\" id=\"2\"]"])
	for kind in 4:
		lines.append("[ext_resource type=\"MultiMesh\" path=\"res://assets/vegetation/%s_instances.tres\" id=\"m%d\"]"%[NAMES[kind],kind])
		lines.append("[ext_resource type=\"Material\" path=\"res://assets/vegetation/%s_material.tres\" id=\"s%d\"]"%[NAMES[kind],kind])
	lines.append_array(PackedStringArray(["","[node name=\"VegetationLayer\" type=\"Node3D\"]","script = ExtResource(\"1\")","profile = ExtResource(\"2\")"]))
	for kind in 4:
		lines.append_array(PackedStringArray(["","[node name=\"%s\" type=\"MultiMeshInstance3D\" parent=\".\"]"%NAMES[kind],
			"layers = 5","cast_shadow = %d"% (0 if kind==0 else 1),
			"material_override = ExtResource(\"s%d\")"%kind,"multimesh = ExtResource(\"m%d\")"%kind]))
	FileAccess.open("res://scenes/components/vegetation_layer.tscn",FileAccess.WRITE).store_string("\n".join(lines)+"\n")
	var stats: Dictionary={"generator_sha256":FileAccess.get_sha256(get_script().resource_path),"profile":profile.snapshot("main"),"geometry":[]}
	for kind in 4:
		var mesh: ArrayMesh=load("res://assets/vegetation/"+NAMES[kind]+"_mesh.tres")
		stats.geometry.append({"kind":NAMES[kind],"vertices":mesh.surface_get_array_len(0),"sha256":FileAccess.get_sha256(mesh.resource_path)})
	FileAccess.open("res://assets/vegetation/geometry_manifest.json",FileAccess.WRITE).store_string(JSON.stringify(stats,"\t")+"\n")
	print("VEGETATION_ASSETS ",JSON.stringify({"errors":errors,"species":profile.species.size(),"capacity":Profile.CANDIDATES_PER_KIND*4}))
	quit(0 if errors.is_empty() else 1)

func _mesh(kind: int) -> ArrayMesh:
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades: int=[9,5,11,9][kind]
	var segments: int=[6,9,5,6][kind]
	for blade in blades:
		var angle:=float(blade)*2.39996323+float(kind)*0.63
		var outward:=Vector3(cos(angle),0,sin(angle))
		var width_axis:=Vector3(-sin(angle),0,cos(angle))
		var height:=0.58+0.42*float((blade*13+5)%17)/16.0
		if blade==0:height=1.0
		var lean: float=[0.48,0.21,0.66,0.42][kind]*(0.55+0.45*float((blade*7)%11)/10.0)
		var width: float=[0.045,0.105,0.025,0.032][kind]
		for segment in segments:
			var t0:=float(segment)/segments;var t1:=float(segment+1)/segments
			var vertices: Array[Vector3]=[];var normals: Array[Vector3]=[]
			for sample in [t0,t1]:
				var t: float=sample
				var ripple: float=sin(t*15.0+blade)*t*0.06 if kind==1 else 0.0
				var center: Vector3=Vector3.UP*height*t+outward*(lean*t*t+0.025)
				center+=width_axis*ripple
				var half_width:=width*pow(maxf(0.0,1.0-t),0.65)*(0.3+0.7*sin(PI*minf(t*1.25+0.15,1.0)))
				var normal:=width_axis.cross(Vector3.UP*height+outward*2.0*lean*t).normalized()
				vertices.append(center-width_axis*half_width);vertices.append(center+width_axis*half_width)
				normals.append(normal);normals.append(normal)
			for corner in [0,1,2,1,3,2]:
				tool.set_normal(normals[corner]);tool.set_uv(Vector2(float(corner%2),t0 if corner<2 else t1))
				tool.add_vertex(vertices[corner])
	return tool.commit()
