extends SceneTree

const Presentation=preload("res://scripts/simulation/unified_edit/presentation.gd")
const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Runtime=preload("res://scripts/simulation/unified_edit/domain_runtime.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
var output:=""
var manifest:=""
var checks: Array=[]
var failed:=false
var transition: Dictionary={}
var sources: Dictionary={}
var observations: Dictionary={}
var orphan_baseline:=0
var saved: Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--manifest="):manifest=arg.trim_prefix("--manifest=")
	call_deferred("_run")

func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"pass":ok});failed=failed or not ok;print("PRESENTATION_PROBE ",name," ",ok)

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified actual presentation probe")
	var read:=Presentation.read(manifest);check("manifest_valid",read.error.is_empty())
	if not read.error.is_empty():finish();return
	var data: Dictionary=read.metadata
	var packed=load(data.scene.path);var scene: Node=packed.instantiate()
	var plan:=Presentation.material_plan(scene,data);check("actual_material_plan",plan.error.is_empty())
	if not plan.error.is_empty():scene.free();finish();return
	var changed: Dictionary=data.duplicate(true);changed.bindings[0].material_id=0.5
	check("fractional_material_id_rejected",Presentation.material_plan(scene,changed).error==&"presentation_binding_invalid")
	changed=data.duplicate(true);changed.bindings[0].path="Missing:material_override"
	check("missing_material_node_rejected",Presentation.material_plan(scene,changed).error==&"presentation_binding_missing")
	var changed_document: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest))
	changed_document.metadata.seed.sha256="0".repeat(64)
	var invalid_path:=output+"/invalid_manifest.json"
	FileAccess.open(invalid_path,FileAccess.WRITE).store_string(JSON.stringify(changed_document))
	check("changed_seed_rejected",Presentation.read(invalid_path).error==&"presentation_artifact_changed")
	observations.materials=plan.materials;observations.bound_materials=plan.bindings.size()
	# This probe exercises shaders and publication only. Interface behavior is
	# deliberately not a formal entry claim; retain the baked controls visually.
	_disable_presentation_scripts(scene)
	root.add_child(scene)
	var runtime=scene.get_node("UnifiedEditRuntime")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	check("registry",created.error.is_empty())
	var seeded:=Presentation.initial_domain(data,1001);check("actual_seed",seeded.error.is_empty())
	if not seeded.error.is_empty():scene.queue_free();finish();return
	var domain=seeded.domain;var settings: Dictionary=data.settings
	var deps:=Presentation.dependencies(PackedStringArray([ProjectSettings.localize_path(data.scene.path),ProjectSettings.localize_path(data.seed.path),ProjectSettings.localize_path(manifest)]))
	check("resource_dependencies",deps.error.is_empty())
	if not deps.error.is_empty():scene.queue_free();finish();return
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES+Runtime.SOURCES+Presentation.SOURCES)
	extra.append_array(deps.sources);extra.append(get_script().resource_path)
	var gravel:=Pipeline.Visuals.Gravel.default_profile(settings.scene_key,int(settings.gravel_count));gravel.bed_reconstruction=settings.render_subdivision>1
	var simulation:={"enable_erosion":settings.enable_erosion,"enable_brush_water":settings.enable_brush_water,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":settings.local_front_history,"rise_front_history":false,"contact_history":false}
	var environment:={"engine":Engine.get_version_info().string,"boundary":Pipeline.Boundary.for_scene(domain.domain_id),"ordinary_cohesion_yield_height_m":settings.sand_cohesion_yield_height_m,"local_front_wide_field":settings.prototype_local_front_wide_field,"gravel_profile":gravel}
	var frozen:=Config.freeze(created.registry,domain.domain_id,simulation,{"foam_enabled":settings.foam_enabled,"gravel_enabled":settings.gravel_enabled},{},environment,extra)
	check("configuration",frozen.error.is_empty())
	if not frozen.error.is_empty():scene.queue_free();finish();return
	sources=frozen.value.sources.duplicate(true)
	var admitted: StringName=runtime.boot(created.registry,frozen.value,domain,plan.bindings,func(value: Dictionary):transition=value)
	check("boot_admitted",admitted.is_empty())
	var start:=Time.get_ticks_msec()
	while transition.is_empty() and Time.get_ticks_msec()-start<60000:await process_frame
	check("boot_ready",transition.get("error",&"missing")==&"" and runtime.ready_for_input())
	if runtime.current!=null:
		_validate_live_materials(runtime,plan.bindings,"boot")
		check("single_new_authority",runtime.current._generation==1001 and runtime.current.completed_state_seq==0 and not scene.has_node("GpuCollisionProxy"))
		await physics_frame;await physics_frame;await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
		check("actual_render_saved",root.get_texture().get_image().save_png(output+"/unified.png")==OK)
		observations.domain_id=String(domain.domain_id);observations.configuration_hash=frozen.value.configuration_hash;observations.runtime_events=runtime.events.duplicate(true)
		check("all_64_collision_chunks",runtime.surfaces[runtime.current_index].applied_revisions.size()==64)
		var selection:={"policy":3,"speed":0.25,"brush":{"tool":&"place_sand","parameters":{},"dig_amount_m3":0.1,"fill_amount_m3":0.1}}
		check("native_save_admitted",runtime.save_checkpoint(output+"/native.sandue",selection,func(value: Dictionary):saved=value).accepted)
		start=Time.get_ticks_msec()
		while saved.is_empty() and Time.get_ticks_msec()-start<20000:await process_frame
		check("native_save_completed",saved.get("error",&"missing")==&"")
		check("real_tick_admitted",runtime.request_tick(1.0/30.0).is_empty())
		start=Time.get_ticks_msec()
		while (runtime.current.active_count()!=0 or runtime.current.pending_count()!=0) and Time.get_ticks_msec()-start<15000:await process_frame
		check("real_tick_completed",runtime.current.completed_state_seq==1 and runtime.current.fault_reason().is_empty())
		await RenderingServer.frame_post_draw
		check("tick_render_saved",root.get_texture().get_image().save_png(output+"/unified_tick.png")==OK)
		var restored:=Pipeline.Checkpoint.load(output+"/native.sandue",frozen.value)
		check("native_loaded",restored.error.is_empty())
		if restored.error.is_empty():
			transition={};check("actual_material_restore_admitted",runtime.restore_checkpoint(restored.checkpoint,func(value: Dictionary):transition=value).is_empty())
			start=Time.get_ticks_msec()
			while (transition.is_empty() or not runtime.retired.is_empty()) and Time.get_ticks_msec()-start<30000:await process_frame
			check("actual_material_restore_ready",transition.get("error",&"missing")==&"" and runtime.generation()==1002 and runtime.retired.is_empty())
			_validate_live_materials(runtime,plan.bindings,"restore")
			await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
			check("restored_render_saved",root.get_texture().get_image().save_png(output+"/unified_restored.png")==OK)
	var owner=runtime.current
	runtime.shutdown();start=Time.get_ticks_msec()
	while not runtime.closed and Time.get_ticks_msec()-start<30000:await process_frame
	check("owner_closed",runtime.closed and owner!=null and owner.released)
	var detached:=true
	for binding in plan.bindings:
		for parameter in binding.parameters:detached=detached and binding.material.get_shader_parameter(parameter)==null
	check("all_actual_samplers_detached",detached)
	if runtime.closed:
		root.remove_child(scene);scene.free()
		check("presentation_nodes_freed",not is_instance_valid(scene))
		await process_frame;await process_frame
	# Drop packed resources and all local material references before exit.
	call_deferred("finish")

func _validate_live_materials(runtime, plan: Array, label: String) -> void:
	var valid:=true;var count:=0
	for binding in plan:
		for parameter in binding.parameters:
			var value: Variant=binding.material.get_shader_parameter(parameter)
			valid=valid and value is Texture2DRD and value.texture_rd_rid==runtime.current.views.textures[binding.parameters[parameter]]
			count+=1
	check(label+"_all_actual_samplers_owned",valid and count>0)
	observations[label+"_sampler_count"]=count

func _disable_presentation_scripts(node: Node) -> void:
	if node.name=="UnifiedEditRuntime":return
	if node.get_script()!=null:node.set_script(null)
	for child in node.get_children():_disable_presentation_scripts(child)

func finish() -> void:
	check("no_new_orphan_nodes",int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))<=orphan_baseline)
	if failed:Node.print_orphan_nodes()
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"sources":sources,"observations":observations,"scope":"actual extracted rendering, one tick and lifetime; excludes UI interaction and formal entry cutover"},"\t"))
	quit(1 if failed else 0)
