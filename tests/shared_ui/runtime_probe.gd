extends SceneTree
var beach
var checks: Array=[]
const OUT="res://test_output/shared_ui/"
func _initialize():call_deferred("run")
func check(label: String, passed: bool):
	checks.append({"check":label,"pass":passed})
	print("BEACH_UI ",label," ",passed)
func wait_ready():
	var deadline=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		if is_instance_valid(current_scene) and current_scene.get("ready_for_ticks")==true and not current_scene.get("_booting"):return true
		if is_instance_valid(current_scene) and not str(current_scene.get("last_error")).is_empty():return false
		await process_frame
	return false
func capture(name: String):
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
func inspect(label: String):
	var toggle=beach.get_node("UIVisibility/ToggleUI")
	toggle.pressed.emit()
	await process_frame
	check(label+"_hide",beach.hide_hud and not beach.get_node("Interface").visible and toggle.is_visible_in_tree())
	toggle.pressed.emit()
	await process_frame
	check(label+"_show",not beach.hide_hud and beach.get_node("Interface").visible)
	var pause=beach.get_node("Interface/EditPanel/Margin/Controls/Pause")
	var was_playing=beach.playing
	pause.pressed.emit()
	check(label+"_pause_once",beach.playing!=was_playing)
	pause.pressed.emit()
	var camera=beach.get_node("Interface/EditPanel/Margin/Controls/Camera")
	var was_camera=beach.use_player_camera
	camera.pressed.emit()
	check(label+"_camera_once",beach.use_player_camera!=was_camera)
	camera.pressed.emit()
	var menu=beach.get_node("Interface/EditPanel/Margin/Controls/ParameterWindows")
	menu.get_popup().id_pressed.emit(0)
	await process_frame
	check(label+"_parameter_window",root.get_node("Parameters/tools").visible)
	root.get_node("Parameters/tools").hide()
	check(label+"_one_tool_binding",beach.panel.tool_changed.get_connections().size()==1)
	var targets=beach.get_node("Interface/EditPanel/Margin/Controls/SceneSwitcher/Actions/Targets")
	check(label+"_route_labels",targets.item_count==load("res://scripts/beach/unified_scene_routes.gd").KEYS.size())
	var panel=beach.get_node("Interface/ShapeBrushPanel")
	var bounds=Rect2(Vector2.ZERO,root.get_visible_rect().size)
	for path in ["Interface/ShapeBrushPanel","Interface/FloatingPropsPanel","Interface/EditPanel"]:
		var control=beach.get_node(path)
		check(label+"_bounds_"+control.name,bounds.encloses(control.get_global_rect()))
	check(label+"_no_overlap",not panel.get_global_rect().intersects(beach.get_node("Interface/EditPanel").get_global_rect()))
	for button in panel.get_node("Margin/Controls/Tools").get_children():
		check(label+"_icon_"+button.name,button.icon!=null)
		button.pressed.emit()
		check(label+"_tool_"+button.name,beach.selected_sand_tool==panel._tool_for_button(button.name))
	panel.get_node("Margin/Controls/Tools/Dig").pressed.emit()
	var props=beach.get_node("Interface/FloatingPropsPanel")
	for id in [1,2,3]:
		props.get_node("Margin/Rows/Slots/Slot%d"%id).pressed.emit()
		check(label+"_prop_"+str(id),props.selected_body_id==id)
	props.get_node("Margin/Rows/Actions/Pickup").pressed.emit()
	check(label+"_pickup",props.pickup_mode)
	props.get_node("Margin/Rows/Actions/Cancel").pressed.emit()
	check(label+"_cancel",not props.has_world_mode())
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for path in ["res://scenes/unified_edit/presentation/main.tscn","res://scenes/unified_edit/presentation/test1_geometry.tscn"]:
		var packed=load(path)
		check(path+"_inherits_shared_ui",packed.get_state().get_base_scene_state().get_path()=="res://scenes/components/beach_ui.tscn")
	root.size=Vector2i(1280,720)
	beach=load("res://scenes/main.tscn").instantiate()
	root.add_child(beach);current_scene=beach
	check("main_ready",await wait_ready())
	if beach.ready_for_ticks:
		beach.playing=false
		await create_timer(0.5).timeout
		await inspect("main")
		await capture("main")
		var switcher=beach.get_node("Interface/EditPanel/Margin/Controls/SceneSwitcher")
		switcher.targets.select(1)
		switcher.switch_button.pressed.emit()
		var deadline=Time.get_ticks_msec()+90000
		while Time.get_ticks_msec()<deadline:
			await process_frame
			if is_instance_valid(current_scene) and current_scene.get("scene_key")=="test1_geometry" and current_scene.get("ready_for_ticks")==true:break
		beach=current_scene
		check("switch_to_test1",beach.scene_key=="test1_geometry" and beach.ready_for_ticks)
		if beach.scene_key=="test1_geometry" and beach.ready_for_ticks:
			beach.playing=false
			await create_timer(0.5).timeout
			await inspect("test1")
			await capture("test1")
	var file=FileAccess.open(OUT+"report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(checks,"  "));file.close()
	if is_instance_valid(beach):
		beach.shutdown()
		var deadline=Time.get_ticks_msec()+30000
		while not beach.gpu_release_done and Time.get_ticks_msec()<deadline:await process_frame
	quit(1 if checks.any(func(item): return not item.pass) else 0)

