extends "res://tests/water_material_natural/capture.gd"

const Style=preload("res://assets/water_material_natural_candidate/style_entry.gd")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/style_reference_v1.json"))
	var rows:=[]
	for id in ["missing","extra","string","bool","null","below","above"]:
		var p:Dictionary=original.duplicate(true)
		var expected:="invalid_normal_frequency_multiplier"
		match id:
			"missing":p.erase("normal_frequency_multiplier");expected="invalid_style_profile"
			"extra":p.unsupported=true;expected="invalid_style_profile"
			"string":p.normal_frequency_multiplier="2"
			"bool":p.normal_frequency_multiplier=true
			"null":p.normal_frequency_multiplier=null
			"below":p.normal_frequency_multiplier=0.99
			"above":p.normal_frequency_multiplier=4.01
		var path:String=output+"/"+String(id)+".json"
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(p));file.close()
		var entry:Node3D=load(scene_path).instantiate()
		entry.set_script(Style)
		entry.style_profile_path=path
		entry._ready()
		var passed:bool=entry.candidate_error==expected and entry.solver==null and not entry.ready_for_ticks
		rows.append({"id":id,"expected":expected,"actual":entry.candidate_error,"solver_null":entry.solver==null,"ready":entry.ready_for_ticks,"pass":passed})
		entry.free()
		if not passed:_fail("reference schema negative mismatch: "+id);return
	var file:=FileAccess.open(output+"/reference_schema_guard.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"negative_acceptance_pass":true,"rows":rows,"scope":"New schema3 frequency field rejects unsupported keys/types/range before parent initialization; seven exact expected ERROR messages. Not an ordinary error-free run or GPU/performance test."},"\t"));file.close()
	quit(0)
