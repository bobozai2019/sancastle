extends "res://tests/water_material_natural/capture.gd"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var scene:PackedScene=load(scene_path)
	var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/compiled_v1_bundle.json"))
	var rows:=[]
	for id in ["empty_bundle_hash","wrong_bundle_hash","wrong_style_path","schema","extra_key","duplicate_material","shader_hash","index_hash","empty_constants"]:
		var node:Node3D=scene.instantiate()
		var expected:=""
		match id:
			"empty_bundle_hash":node.compiled_bundle_sha256="";expected="compiled_bundle_hash_mismatch"
			"wrong_bundle_hash":node.compiled_bundle_sha256="0".repeat(64);expected="compiled_bundle_hash_mismatch"
			"wrong_style_path":node.style_profile_path="res://assets/water_material_natural_candidate/style_height.json";expected="compiled_profile_identity_mismatch"
			_:
				var p:Dictionary=original.duplicate(true)
				match id:
					"schema":p.bundle_schema_version=2;expected="invalid_compiled_bundle"
					"extra_key":p["unsupported"]=true;expected="invalid_compiled_bundle"
					"duplicate_material":p.components[1].material="water";expected="invalid_compiled_component"
					"shader_hash":p.components[0].shader_sha256="0".repeat(64);expected="compiled_component_hash_mismatch"
					"index_hash":p.components[0].index_sha256="0".repeat(64);expected="compiled_component_hash_mismatch"
					"empty_constants":
						var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(p.components[0].index))
						index.constants={}
						var index_path:=output+"/empty_index.json"
						var file:=FileAccess.open(index_path,FileAccess.WRITE);file.store_string(JSON.stringify(index));file.close()
						p.components[0].index=index_path;p.components[0].index_sha256=FileAccess.get_sha256(index_path);expected="invalid_compiled_constants"
				var path:String=output+"/"+String(id)+".json"
				var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(p));file.close()
				node.compiled_bundle_path=path;node.compiled_bundle_sha256=FileAccess.get_sha256(path)
		node._ready()
		var actual:String=node.last_error
		var no_solver:bool=node.solver==null and not node.ready_for_ticks
		rows.append({"case":id,"expected":expected,"actual":actual,"rejected":actual==expected,"before_solver_initialization":no_solver})
		node.free()
		if actual!=expected or not no_solver:_fail("startup compiled guard failed");return
	var file:=FileAccess.open(output+"/startup_guard.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"scope":"Actual scene script ready metadata rejection outside tree, before solver initialization; not complete positive startup or GPU runtime acceptance."},"\t"));file.close()
	quit(0)
