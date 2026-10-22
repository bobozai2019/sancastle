extends SceneTree

# Static instantiated nodes, never added to the tree: no _ready, solver or RD.
# This is entry retirement evidence; the full G7 writer audit remains separate.
const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
const ENTRY="res://scripts/beach/unified_playable_entry.gd"
const RUNTIME="res://scripts/simulation/unified_edit/domain_runtime.gd"
const ALLOWED=[ENTRY,RUNTIME,"res://scripts/simulation/unified_edit/height_surface.gd","res://scripts/beach/unified_performance_panel.gd","res://scripts/beach/free_camera.gd","res://scripts/beach/ui_visibility.gd","res://scripts/beach/ui_drag.gd","res://scripts/beach/scene_switch_panel.gd","res://scripts/sand/brushes/brush_tool_panel.gd","res://scripts/sand/brushes/brush_preview_view.gd","res://scripts/visual/brush_indicator.gd","res://scripts/visual/water_boundary_sides.gd","res://scripts/visual/vegetation_layer.gd"]
var output:=""
var checks: Array=[]
var entries: Array=[]
var failed:=false

func check(name: String, passed: bool) -> void:
	checks.append({"name":name,"pass":passed});failed=failed or not passed
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")
func _scripts(node: Node, paths: Dictionary) -> void:
	if node.get_script()!=null:paths[String(node.get_path()) if node.is_inside_tree() else String(node.name)+":"+str(node.get_instance_id())]=node.get_script().resource_path
	for child in node.get_children():_scripts(child,paths)
func _run() -> void:
	check("project_main_is_formal",ProjectSettings.get_setting("application/run/main_scene")==Routes.FORMAL.main)
	check("main_uid_preserved",FileAccess.get_file_as_string(Routes.FORMAL.main).split("\n")[0].contains("uid=\"uid://bovjuhcrpaoaf\""))
	for key in Routes.KEYS:
		var path: String=Routes.FORMAL[key]
		var entry=load(path).instantiate()
		var paths:={};_scripts(entry,paths)
		var runtimes:=0;var authorized:=true
		for script in paths.values():
			authorized=authorized and (script in ALLOWED or (key=="main" and script in ["res://scripts/props/floating_prop.gd","res://scripts/props/floating_props_service.gd","res://scripts/beach/floating_props_panel.gd"]))
			if script==RUNTIME:runtimes+=1
		check(key+"_exact_root",entry.get_script().resource_path==ENTRY and entry.get_script().get_base_script()==null and entry.scene_file_path==path)
		check(key+"_one_scene_authored_runtime",runtimes==1 and entry.has_node("UnifiedEditRuntime"))
		check(key+"_no_legacy_node_scripts",authorized)
		check(key+"_no_old_collision_proxy",not entry.has_node("GpuCollisionProxy"))
		var vegetation=entry.get_node_or_null("VegetationLayer")
		check(key+"_four_authored_vegetation_kinds",vegetation!=null and vegetation.get_child_count()==4 and vegetation.profile.get_script()==preload("res://scripts/visual/vegetation_profile.gd"))
		if vegetation!=null:
			# Scene-local resource duplicates have no resource_path. Inspect the
			# fixed asset named by the authored child, never a runtime factory.
			check(key+"_vegetation_authored_meshes",vegetation.get_children().all(func(node):return node is MultiMeshInstance3D and node.multimesh.instance_count==768 and FileAccess.get_file_as_string("res://assets/vegetation/"+String(node.name)+"_instances.tres").contains("buffer = PackedFloat32Array")))
		if key=="main":
			var props=entry.get_node_or_null("FloatingProps/Service")
			var rows: Array=props.authored_registry() if props!=null else []
			var local_layout:={}
			for row in rows:local_layout[row.body_id]=row.body.transform
			check("main_three_static_props",rows.size()==3 and props.get_script().resource_path=="res://scripts/props/floating_props_service.gd" and props._validate(rows,local_layout).is_empty())
			check("main_exact_profile_bindings",rows.map(func(row):return row.profile.resource_path)==["res://assets/props/bottle_profile.tres","res://assets/props/wood_plank_profile.tres","res://assets/props/wood_stick_profile.tres"])
			check("main_prop_layers",rows.all(func(row):return row.body.collision_layer==2 and row.body.collision_mask==3 and row.body.scale==Vector3.ONE))
		else:check(key+"_no_props",not entry.has_node("FloatingProps"))
		check(key+"_no_old_execution_flags_or_solver",not "async_pipeline_enabled" in entry and not "solver" in entry)
		check(key+"_same_family_routes",entry.playable_scene_family()=="formal" and entry.playable_scene_path("main")==Routes.FORMAL.main)
		var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(entry.presentation_manifest))
		check(key+"_promoted_presentation_identity",FileAccess.get_sha256(manifest.metadata.scene.path)==manifest.metadata.scene.sha256 and FileAccess.get_sha256(manifest.metadata.seed.path)==manifest.metadata.seed.sha256)
		entries.append({"key":key,"path":path,"sha256":FileAccess.get_sha256(path),"scripts":paths,"presentation":manifest.metadata.scene.duplicate(),"seed":manifest.metadata.seed.duplicate()})
		entry.free()
	var service:=FileAccess.get_file_as_string("res://scripts/beach/beach_scene_service.gd")
	check("service_no_old_flags_ownership_or_solver_fallback",not service.contains("async_pipeline_enabled") and not service.contains("_async_") and not service.contains("scene.solver") and not service.contains("collision_proxy"))
	check("service_no_path_fallback",not service.contains("else SCENES["))
	check("unknown_family_path_empty",Routes.scene_path("unknown","main").is_empty() and Routes.family("res://unknown.tscn","main").is_empty())
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"entries":entries,"auditor_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Formal static node scripts, one authored unified runtime, source identity and removed scene-service fallback; not the full G7 executable writer audit"},"\t"))
	print("FORMAL_SCENE_AUDIT ",not failed," checks=",checks.size());quit(1 if failed else 0)
