extends "res://tests/visual_water_alignment/foam_authority_switch_probe.gd"

const ITEMS=[["visual_foam_detail_scale_per_m","foam_detail_scale_per_m"],["visual_foam_hole_strength","foam_hole_strength"],["visual_foam_flow_cycle_s","foam_flow_cycle_s"]]
var values_by_scene:={"main":[1.4,0.65,3.0],"test1_geometry":[1.7,0.8,5.0]}

func _ui(label: String, expected: Array, edit: bool=false) -> void:
	var service=root.get_node("Parameters")
	var water: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	for i in ITEMS.size():
		var item: Array=ITEMS[i]
		var row=service.get_node_or_null("water/Margin/Rows/Scroll/Fields/"+item[0])
		check(label+"_row_"+str(i),row!=null)
		if row==null:continue
		var control: SpinBox=row.get_node("Line/Value")
		check(label+"_editable_"+str(i),control.editable)
		if edit:control.value=expected[i]
		check(label+"_control_"+str(i),is_equal_approx(control.value,float(expected[i])))
		check(label+"_material_"+str(i),is_equal_approx(float(water.get_shader_parameter(item[1])),float(expected[i])))

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate()
	scene.playing=false;scene.generation=1001;root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+90000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	await process_frame
	check("props_hold",(await scene._props_hold(true,&"user")).is_empty())
	await _advance(30)
	_ui("main_initial_edit",values_by_scene.main,true)
	var first:=await _snapshot("main_start")
	var expected:={"main":first}
	var service=root.get_node("BeachScenes")
	service.session_directory=output+"/switch_sessions"
	DirAccess.make_dir_recursive_absolute(service.session_directory)
	service.attach(scene)
	var resources_by_scene:={}
	for index in 5:
		var key: String="test1_geometry" if scene.scene_key=="main" else "main"
		var old_id: int=scene.get_instance_id()
		check("switch_admitted_"+str(index),service.request_switch(key))
		check("duplicate_refused_"+str(index),not service.request_switch(key))
		deadline=Time.get_ticks_msec()+120000
		while service.busy and Time.get_ticks_msec()<deadline:await process_frame
		scene=service.active_scene
		check("switch_ready_"+str(index),not service.busy and service.last_error.is_empty() and is_instance_valid(scene) and scene.scene_key==key and scene.ready_for_ticks)
		if not is_instance_valid(scene):quit(1);return
		if not service.last_error.is_empty() or scene.scene_key!=key:await _close();return
		await process_frame
		check("previous_scene_freed_"+str(index),not is_instance_id_valid(old_id))
		check("mode1_"+str(index),scene.get_node("GpuWaterSurface").material_override.get_shader_parameter("foam_detail_mode")==1)
		check("texture_"+str(index),scene.get_node("GpuWaterSurface").material_override.get_shader_parameter("foam_detail_texture").resource_path=="res://assets/water_foam/foam_detail.png")
		check("props_held_"+str(index),(await scene._props_hold(true,&"user")).is_empty())
		if not expected.has(key):
			_ui("new_scene_defaults_"+str(index),[1.0,1.0,4.0])
			_ui("new_scene_edit_"+str(index),values_by_scene[key],true)
		else:_ui("return_scene_values_"+str(index),values_by_scene[key])
		var actual:=await _snapshot("switch"+str(index))
		if expected.has(key):_same("restored_"+str(index),expected[key],actual)
		else:expected[key]=actual
		var counts:={"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}
		if resources_by_scene.has(key):check("nodes_stable_"+str(index),resources_by_scene[key].nodes==counts.nodes)
		else:resources_by_scene[key]=counts
		observations["switch_counts_"+str(index)]=counts
		await _capture("switch"+str(index))
	observations.release_records=service.release_records.duplicate(true)
	observations.scope="Latest authored UI: five scene switches, per-scene real SpinBox values and material consumers, exact saved authority/history/time on return, owner/node release. No repeated evolution or performance acceptance claim."
	await _close()
