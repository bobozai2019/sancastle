extends SceneTree

const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
var checks:=[]
var output:=""

func check(label: String, passed: bool) -> void:checks.append({"name":label,"pass":passed})

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var registry=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry().registry
	var simulation:={"enable_erosion":true,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES);extra.append(get_script().resource_path)
	var hashes:=[];var frozen_sources: Dictionary={}
	for value in [-0.01,2.01,"0.0",true,0.0,0.025,2.0]:
		var configuration:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"ordinary_cohesion_yield_height_m":value},extra)
		check("typed_container_"+str(value),configuration.error.is_empty())
		if not configuration.error.is_empty():continue
		frozen_sources=configuration.value.sources
		var pipeline:=Pipeline.new();var error:=pipeline.configure(registry,configuration.value,1)
		var valid: bool=typeof(value)==TYPE_FLOAT and value>=0.0 and value<=2.0
		check("runtime_parameter_"+str(value),error.is_empty() if valid else error==&"invalid_runtime_ordinary_cohesion")
		var empty:=true
		for count in pipeline.ownership_counts().values():empty=empty and count==0
		check("no_resources_before_validation_"+str(value),empty and not pipeline.initialization_started)
		if valid:hashes.append(configuration.value.configuration_hash)
	check("different_coefficients_change_configuration_identity",hashes.size()==3 and hashes[0]!=hashes[1] and hashes[1]!=hashes[2])
	for value in [false,true,"wide",1]:
		var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":true,"gravel_enabled":false},{},{"local_front_wide_field":value},extra)
		check("visual_wide_container_"+str(value),frozen.error.is_empty())
		var subject:=Pipeline.new();var error:=subject.configure(registry,frozen.value,1)
		check("visual_wide_type_"+str(value),error.is_empty() if typeof(value)==TYPE_BOOL else error==&"invalid_runtime_local_front_wide")
		check("visual_wide_no_allocation_"+str(value),not subject.initialization_started and subject.ownership_counts().values().all(func(n):return n==0))
	for count in [-1,0,512,1024,1025]:
		var profile: Dictionary=Pipeline.Visuals.Gravel.default_profile("main",count)
		var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":true,"gravel_enabled":true},{},{"gravel_profile":profile},extra)
		check("visual_profile_container_"+str(count),frozen.error.is_empty())
		var subject:=Pipeline.new();var error:=subject.configure(registry,frozen.value,1)
		check("visual_profile_capacity_"+str(count),error.is_empty() if count>=0 and count<=1024 else error==&"invalid_gravel_profile")
		check("visual_profile_no_allocation_"+str(count),not subject.initialization_started and subject.ownership_counts().values().all(func(n):return n==0))
	for key in ["main_beach","test1_capture","test1_backwash","test1_geometry"]:
		var boundary: Dictionary=Pipeline.Boundary.for_scene(key)
		var frozen:=Config.freeze(registry,key,simulation,{"foam_enabled":true,"gravel_enabled":true},{},{"boundary":boundary},extra)
		check("boundary_scene_container_"+key,frozen.error.is_empty())
		var subject:=Pipeline.new();check("boundary_scene_valid_"+key,subject.configure(registry,frozen.value,1).is_empty())
		check("boundary_scene_no_allocation_"+key,not subject.initialization_started and subject.ownership_counts().values().all(func(n):return n==0))
	var invalid_boundaries: Array=[{"enabled":"yes"},{"enabled":false,"mode":0}]
	for key in ["mode","period_s"]:
		var boundary: Dictionary=Pipeline.Boundary.for_scene("main_beach");boundary[key]=7 if key=="mode" else 0.0;invalid_boundaries.append(boundary)
	var geometry: Dictionary=Pipeline.Boundary.for_scene("test1_geometry");invalid_boundaries.append(geometry)
	geometry=Pipeline.Boundary.for_scene("test1_geometry");geometry.period_s=21.0;invalid_boundaries.append(geometry)
	for index in invalid_boundaries.size():
		var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":true,"gravel_enabled":true},{},{"boundary":invalid_boundaries[index]},extra)
		check("boundary_bad_container_"+str(index),frozen.error.is_empty())
		var subject:=Pipeline.new();check("boundary_bad_rejected_"+str(index),not subject.configure(registry,frozen.value,1).is_empty())
		check("boundary_bad_no_allocation_"+str(index),not subject.initialization_started and subject.ownership_counts().values().all(func(n):return n==0))
	var passed:=true
	for item in checks:passed=passed and item.pass
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks,"sources":frozen_sources,"engine":Engine.get_version_info(),"scope":"Runtime ordinary cohesion typed range, configuration identity and rejection before any RD resource allocation; no GPU coefficient effect claim"},"\t"))
	print("UNIFIED_RUNTIME_CONFIGURATION ",passed," ",checks.size());quit(0 if passed else 1)
