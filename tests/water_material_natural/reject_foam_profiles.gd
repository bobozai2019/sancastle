extends SceneTree

func _initialize() -> void:
	var output:="res://test_output/water_material_natural/t04_profile_rejections"
	DirAccess.make_dir_recursive_absolute(output)
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/foam_combination.json"))
	var rows:=[]
	for id in ["version","fractional_version","optics_hash","size_order","gain","cluster","jitter","direct","separation","shape","shape_scale","bindings","schema1_new_fields","schema2_new_fields"]:
		var p:=source.duplicate(true)
		match id:
			"version":p.foam_schema_version=99
			"fractional_version":p.foam_schema_version=1.5
			"optics_hash":p.optics_profile_sha256="bad"
			"size_order":p.fine.size_range=[2.2,.65]
			"gain":p.fine.gain=-1.
			"cluster":p.fine.clustering_strength=1.1
			"jitter":p.fine.jitter_m=.21
			"direct":p.fine.direct_fraction=2.
			"separation":p.contact.separation_m=.02
			"shape":p.contact.shape_mode="placeholder"
			"shape_scale":p.contact.shape_scale_per_m=0.
			"bindings":p.geometry_bindings="res://missing_geometry.json"
			"schema1_new_fields":p.foam_schema_version=1
			"schema2_new_fields":p.foam_schema_version=2
		var path:String=output+"/"+id+".json"
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(p));file.close()
		var node:Node3D=load("res://scenes/water_material_natural_candidate/foam_combination.tscn").instantiate()
		node.foam_profile_path=path;node._ready()
		var rejected:bool=not node.candidate_error.is_empty() and not node.ready_for_ticks
		rows.append({"case":id,"rejected":rejected,"code":node.candidate_error});node.free()
		if not rejected:push_error("invalid foam reached initialization");quit(1);return
	var file:=FileAccess.open(output+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":true,"cases":rows,"scope":"Pre-initialization rejection; expected reject errors, no simulation."},"\t"));file.close()
	print("PASS: fourteen malformed foam profiles rejected");quit(0)
