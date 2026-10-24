extends "res://docs/competitor/tools/probe_foam_comparison.gd"

const Presentation=preload("res://scripts/simulation/unified_edit/presentation.gd")
const ParameterSchema=preload("res://scripts/parameters/parameter_schema.gd")
var lifecycle_ran:=false

func _resource_plan_case(mode: int, texture: Texture2D) -> StringName:
	var fresh: Node3D=load("res://scenes/main.tscn" if scene_key=="main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	var document: Dictionary=Presentation.read(fresh.presentation_manifest)
	var materials:={}
	for binding in document.metadata.bindings:
		var index:=int(binding.material_id)
		var parts: PackedStringArray=binding.path.rsplit(":",true,1)
		var node=fresh.get_node(parts[0])
		if not materials.has(index):
			var original: ShaderMaterial=node.get(parts[1]) if parts[1] in ["material_override","material_overlay"] else node.get_surface_override_material(int(parts[1].trim_prefix("surface_")))
			materials[index]=original.duplicate()
			for field in document.metadata.materials[index].fields:materials[index].set_shader_parameter(field,null)
		if parts[1] in ["material_override","material_overlay"]:node.set(parts[1],materials[index])
		else:node.set_surface_override_material(int(parts[1].trim_prefix("surface_")),materials[index])
	var water: ShaderMaterial=fresh.get_node("GpuWaterSurface").material_override
	water.set_shader_parameter("foam_detail_mode",mode);water.set_shader_parameter("foam_detail_texture",texture)
	var result: Dictionary=Presentation.material_plan(fresh,document.metadata,fresh.get_script())
	fresh.free()
	return result.error

func _initialize() -> void:
	super._initialize()
	RenderingServer.frame_pre_draw.connect(_hide_brush)

func _hide_brush() -> void:
	if not is_instance_valid(scene):return
	for path in ["BrushIndicator","BrushPreview"]:
		var node: Node3D=scene.get_node_or_null(path)
		if node!=null:node.hide()

func _capture(label: String) -> void:
	await super._capture(label)
	if label!="t360_restored" or lifecycle_ran:return
	lifecycle_ran=true
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var service=root.get_node("Parameters")
	var ids:=["visual_foam_detail_scale_per_m","visual_foam_hole_strength","visual_foam_flow_cycle_s"]
	var fields:=["foam_detail_scale_per_m","foam_hole_strength","foam_flow_cycle_s"]
	var boot_values:=[1.4,0.65,3.0]
	var live_values:=[2.0,0.7,3.5]
	for i in 3:
		var row=service.get_node_or_null("water/Margin/Rows/Scroll/Fields/"+ids[i])
		check("static_ui_row_"+ids[i],row!=null and row.parameter_id==ids[i])
		if row==null:continue
		var editor: SpinBox=row.get_node("Line/Value")
		var definition: Dictionary=ParameterSchema.rows()[ids[i]]
		check("ui_range_"+ids[i],is_equal_approx(editor.min_value,float(definition.min)) and is_equal_approx(editor.max_value,float(definition.max)) and is_equal_approx(editor.step,float(definition.step)))
		check("ui_boot_value_"+ids[i],editor.editable and is_equal_approx(editor.value,boot_values[i]))
		check("saved_boot_"+ids[i],is_equal_approx(float(material.get_shader_parameter(fields[i])),boot_values[i]))
		editor.value=live_values[i]
		check("live_set_"+ids[i],is_equal_approx(float(service.editing[ids[i]]),live_values[i]))
		check("live_consumed_"+ids[i],is_equal_approx(float(material.get_shader_parameter(fields[i])),live_values[i]))
		for invalid in [NAN,INF,-1.0,"bad"]:check("reject_"+ids[i]+"_"+str(invalid),not service.set_value(ids[i],invalid).is_empty())
		check("invalid_did_not_mutate_"+ids[i],is_equal_approx(float(material.get_shader_parameter(fields[i])),live_values[i]))
	service.open_window("water")
	for frame in 8:await process_frame
	var window: Window=service.get_node("water")
	var scroll: ScrollContainer=window.get_node("Margin/Rows/Scroll")
	scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value)
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	check("parameter_window_visible",window.visible)
	check("parameter_window_image",window.get_texture().get_image().save_png(output+"/foam_parameter_window.png")==OK)
	window.hide();root.grab_focus()
	service.save_parameters()
	var loaded: Dictionary=service.read_file(service._file_path)
	check("isolated_parameter_file_saved",loaded.error.is_empty())
	if loaded.error.is_empty():
		for i in 3:check("saved_file_value_"+ids[i],is_equal_approx(float(loaded.scenes[scene_key][ids[i]]),live_values[i]))
	material.set_shader_parameter("foam_detail_mode",0)
	service.bind_scene(scene)
	for id in ids:
		check("legacy_parameter_unavailable_"+id,not service.available[id] and service.set_value(id,1.0)==&"parameter_unavailable")
		check("legacy_ui_disabled_"+id,not service.get_node("water/Margin/Rows/Scroll/Fields/"+id+"/Line/Value").editable)
	material.set_shader_parameter("foam_detail_mode",1);service.bind_scene(scene)
	for i in 3:check("restore_live_value_"+ids[i],service.set_value(ids[i],live_values[i]).is_empty())
	var probe_material: ShaderMaterial=material.duplicate()
	probe_material.set_shader_parameter("foam_detail_texture",null)
	check("missing_texture_error",Presentation.foam_detail_error(probe_material)==&"presentation_foam_detail_texture_missing")
	probe_material.set_shader_parameter("foam_detail_mode",0)
	check("legacy_without_texture_valid",Presentation.foam_detail_error(probe_material).is_empty())
	probe_material.set_shader_parameter("foam_detail_mode",1)
	var tiny:=Image.create(1,1,false,Image.FORMAT_RGBA8);tiny.fill(Color.WHITE)
	probe_material.set_shader_parameter("foam_detail_texture",ImageTexture.create_from_image(tiny))
	check("invalid_import_error",Presentation.foam_detail_error(probe_material)==&"presentation_foam_detail_texture_invalid")
	probe_material.set_shader_parameter("foam_detail_texture",material.get_shader_parameter("foam_detail_texture"))
	probe_material.set_shader_parameter("foam_flow_cycle_s",NAN)
	check("invalid_static_parameter_error",Presentation.foam_detail_error(probe_material)==&"presentation_foam_detail_parameter_invalid")
	check("formal_plan_missing_texture_error",_resource_plan_case(1,null)==&"presentation_foam_detail_texture_missing")
	check("formal_plan_mode0_without_texture",_resource_plan_case(0,null).is_empty())
	observations.parameter_values=_material(material)
	await _capture("before_save")
	var path:=output+"/saved.sandue"
	check("checkpoint_save",(await scene.save_gpu_checkpoint(path)).is_empty())
	var saved:=Codec.load(path,scene.configuration)
	check("checkpoint_codec",saved.error.is_empty())
	if not saved.error.is_empty():return
	var before: Dictionary=saved.checkpoint
	check("edit_after_save",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted)
	scene.input.finish();await _idle()
	var old_owner=scene.runtime.current
	check("checkpoint_restore_public",(await scene.restore_gpu_checkpoint(path)).is_empty())
	var deadline:=Time.get_ticks_msec()+30000
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("previous_owner_released",old_owner.released)
	check("restored_completed_time",scene.runtime.current.advanced_time_s==before.advanced_time_s)
	check("restored_props_hold",(await scene._props_hold(true,&"user")).is_empty())
	await _idle()
	await _capture("after_restore")
	var path2:=output+"/restored.sandue"
	check("save_restored_checkpoint",(await scene.save_gpu_checkpoint(path2)).is_empty())
	var after:=Codec.load(path2,scene.configuration)
	check("restored_codec",after.error.is_empty())
	if after.error.is_empty():
		for field in before.native.fields:check("authority_restored_"+field,before.native.fields[field]==after.checkpoint.native.fields[field])
		for field in before.native.foam:
			if before.native.foam[field] is PackedByteArray:check("foam_history_restored_"+field,before.native.foam[field]==after.checkpoint.native.foam[field])
		check("local_front_restored",before.native.histories==after.checkpoint.native.histories)
	for i in 3:check("visual_parameter_survives_restore_"+ids[i],is_equal_approx(float(material.get_shader_parameter(fields[i])),live_values[i]))
	check("detail_texture_survives_restore",material.get_shader_parameter("foam_detail_texture").resource_path=="res://assets/water_foam/foam_detail.png")
	var old_path:="res://task/wet_sand_visual/evidence/scene2_integration/"+("main_v4" if scene_key=="main" else "geometry_v2")+"/saved.sandue"
	if FileAccess.file_exists(old_path):
		var owner=scene.runtime.current
		var error: StringName=await scene.restore_gpu_checkpoint(old_path)
		check("old_source_checkpoint_rejected",not error.is_empty())
		check("failed_restore_kept_current_owner",scene.runtime.current==owner and scene.last_error.is_empty())
		observations.old_checkpoint_rejection={"path":old_path,"sha256":FileAccess.get_sha256(old_path),"error":String(error)}
	else:check("old_source_fixture_available",false)
	observations.lifecycle={"saved_tick":before.sim_tick,"saved_time_s":before.advanced_time_s,"restored_generation":scene.generation,"configuration_hash":scene.configuration.configuration_hash,"parameter_file":service._file_path}
