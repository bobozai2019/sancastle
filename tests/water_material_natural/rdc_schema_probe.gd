extends "res://tests/water_material_natural/capture.gd"

const Style := preload("res://assets/water_material_natural_candidate/style_entry.gd")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/rdc_style_v1.json"))
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(original.rdc_material_profile))
	var rows:=[]
	for id in ["missing_parameter","extra_parameter","bool_type","negative_absorption","vector_size","time_zero","refraction_high","texture_hash","unmipped_texture","profile_hash","exponent_high"]:
		var p:=original.duplicate(true);var q:=config.duplicate(true)
		var expected:="invalid_rdc_parameters"
		match id:
			"missing_parameter":q.parameters.erase("rdc_distance_scale")
			"extra_parameter":q.parameters.extra=true
			"bool_type":q.parameters.rdc_optics_enabled=1;expected="invalid_rdc_flag"
			"negative_absorption":q.parameters.rdc_absorption_rgb[0]=-1.;expected="invalid_rdc_vector"
			"vector_size":q.parameters.rdc_surface_color=[.2,.3];expected="invalid_rdc_vector"
			"time_zero":q.parameters.rdc_time_scale=0.;expected="invalid_rdc_range"
			"refraction_high":q.parameters.rdc_refraction_scale=.031;expected="invalid_rdc_range"
			"texture_hash":q.caustic_texture_sha256="bad";expected="rdc_texture_hash_mismatch"
			"unmipped_texture":q.caustic_texture="res://assets/water_material_natural_candidate/rdc_caustic_1105.res";q.caustic_texture_sha256=FileAccess.get_sha256(q.caustic_texture);expected="invalid_rdc_volume"
			"profile_hash":expected="rdc_profile_hash_mismatch"
			"exponent_high":p.glint.exponent=2049.;expected="invalid_style_range"
		var qpath:String=output+"/"+id+"_rdc.json"
		var qfile:=FileAccess.open(qpath,FileAccess.WRITE);qfile.store_string(JSON.stringify(q));qfile.close()
		p.rdc_material_profile=ProjectSettings.localize_path(qpath.replace("\\","/"));p.rdc_material_profile_sha256="bad" if id=="profile_hash" else FileAccess.get_sha256(qpath)
		var path:String=output+"/"+id+"_style.json"
		var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(p));f.close()
		var node:Node3D=load(scene_path).instantiate();node.set_script(Style);node.style_profile_path=path;node._ready()
		var passed:bool=node.candidate_error==expected and node.solver==null and not node.ready_for_ticks
		rows.append({"id":id,"expected":expected,"actual":node.candidate_error,"pass":passed,"solver_null":node.solver==null});node.free()
		if not passed:_fail("RDC rejection mismatch: "+id);return
	var report:=FileAccess.open(output+"/rdc_schema.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"pass":true,"cases":rows,"scope":"Eleven exact expected rejection errors before initialization; not an error-free ordinary run."},"\t"));report.close()
	quit(0)
