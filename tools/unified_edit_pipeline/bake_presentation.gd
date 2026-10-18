extends SceneTree

# Offline extraction only. The resulting scene has no legacy root/authority
# script and retains the actually configured presentation, UI and fixed nodes.
var output:=""
var scene_path:="res://scenes/main.tscn"
var scene
var checks: Array=[]
var failed:=false
var material_ids: Dictionary={}
var materials: Array=[]
var bindings: Array=[]
var unknown_dynamic: Array=[]
var wrappers: Dictionary={}

func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"pass":ok});failed=failed or not ok;print("PRESENTATION_BAKE ",name," ",ok)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--scene="):scene_path=arg.trim_prefix("--scene=")
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified presentation extraction")
	scene=load(scene_path).instantiate();scene.playing=false;root.add_child(scene)
	var begin:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-begin<90000:await process_frame
	check("original_ready_without_ticks",scene.ready_for_ticks and scene.last_error.is_empty() and scene.completed_ticks==0)
	if not scene.ready_for_ticks or not scene.last_error.is_empty():await _close();finish({"initialization_error":scene.last_error});return
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	var png:=output+"/original.png";check("original_render_saved",root.get_texture().get_image().save_png(png)==OK)
	for pair in [["rock_texture","rock"],["sand_texture","sand"],["water_texture","water"],["momentum_x_texture","momentum_x"],["momentum_z_texture","momentum_z"],["wetness_texture","wetness"],["compaction_texture","compaction"],["sediment_texture","sediment"],["obstacle_texture","obstacle"],["flux_texture","flux"],["foam_texture","foam"],["local_front_texture","local_front"],["gravel_wrapper","gravel"],["preview_baseline","baseline"],["async_clock_wrapper","clock"]]:
		var value: Variant=scene.get(pair[0])
		if value is Texture2DRD and value.texture_rd_rid.is_valid():wrappers[value.texture_rd_rid]=pair[1]
	var settings: Dictionary={}
	for key in ["scene_key","preset_index","enable_erosion","sand_cohesion_yield_height_m","enable_brush_water","gravel_enabled","gravel_count","render_subdivision","use_player_camera","hide_hud","water_policy","signed_speed_m_s","dig_amount_m3","fill_amount_m3","manual_wave_amplitude_m","prototype_local_front_wide_field"]:settings[key]=scene.get(key)
	settings.local_front_history=scene.local_front_field!=null;settings.foam_enabled=scene.foam_field!=null
	var seed: Dictionary=scene.shadow_domain.snapshot()
	seed["metadata"]={}
	for key in ["edit_validation_initial_qx","edit_validation_initial_qz","brush_initial_mold_depth"]:
		if scene.shadow_domain.has_meta(key):seed.metadata[key]=scene.shadow_domain.get_meta(key)
	var seed_path:=output+"/initial_seed.variant";FileAccess.open(seed_path,FileAccess.WRITE).store_buffer(var_to_bytes(seed))
	var copy: Node=scene.duplicate(Node.DUPLICATE_GROUPS|Node.DUPLICATE_SCRIPTS|Node.DUPLICATE_SIGNALS)
	copy.set_script(null);copy.scene_file_path=""
	# The live reflection viewport shares the root viewport's World3D. Serializing
	# that runtime world or its anonymous ViewportTexture captures the wrong
	# ownership. Store a scene-local path and inherit the new root's world instead.
	var reflection:=copy.get_node_or_null("ReflectionViewport")
	if reflection is SubViewport:reflection.world_3d=null
	for name in ["GpuCollisionProxy","EditorPreviewController","VisualEditorPreview"]:
		var child:=copy.get_node_or_null(name)
		if child!=null:child.free()
	# Performance HUD is kept as fixed controls; its old solver-specific reader
	# is replaced by the unified entry's informational sampler during integration.
	var profiler:=copy.get_node_or_null("Interface/PerformancePanel")
	if profiler!=null:profiler.set_script(null)
	# These presentation fields are now fixed materials. The old cloud script
	# would clone/rebind them after the domain's ownership plan was registered.
	var cloud:=copy.get_node_or_null("SuspendedSandCloud")
	if cloud!=null:cloud.set_script(null)
	_clear_root_signals(copy)
	_materials(copy,copy)
	var runtime=load("res://scenes/unified_edit_runtime.tscn").instantiate();copy.add_child(runtime)
	_set_owners(copy,copy)
	var nodes: Array=[]
	for node in _all_nodes(copy):nodes.append({"path":String(copy.get_path_to(node)),"class":node.get_class(),"script":"" if node.get_script()==null else node.get_script().resource_path})
	check("all_dynamic_samplers_mapped",unknown_dynamic.is_empty())
	check("no_legacy_root_script",copy.get_script()==null and not copy.has_node("GpuCollisionProxy"))
	var packed:=PackedScene.new();check("static_scene_packed",packed.pack(copy)==OK)
	var target:=output+"/presentation.tscn";check("static_scene_saved",ResourceSaver.save(packed,target)==OK)
	copy.free()
	var metadata:={"version":1,"source_scene":scene_path,"source_scene_sha256":FileAccess.get_sha256(scene_path),"source_script":scene.get_script().resource_path,"baker_sha256":FileAccess.get_sha256(get_script().resource_path),"configuration":scene.source_signature.duplicate(true),"effective_compilation":scene.effective_compilation.duplicate(true),"effective_profile":scene.effective_render_profile.duplicate(true) if "effective_render_profile" in scene else {},"settings":settings,"seed":{"path":seed_path,"sha256":FileAccess.get_sha256(seed_path)},"scene":{"path":target,"sha256":FileAccess.get_sha256(target)},"original_png":{"path":png,"sha256":FileAccess.get_sha256(png)},"bindings":bindings,"materials":materials,"nodes":nodes,"unknown_dynamic":unknown_dynamic}
	await _close();finish(metadata)

func _close() -> void:
	var profiler=scene.get_node_or_null("Interface/PerformancePanel")
	if profiler!=null and profiler.has_method("stop_sampling"):await profiler.stop_sampling()
	await scene.shutdown();check("original_gpu_released",scene.gpu_release_done)
	scene.queue_free();await process_frame

func _all_nodes(node: Node) -> Array:
	var result: Array=[node]
	for child in node.get_children():result.append_array(_all_nodes(child))
	return result

func _clear_root_signals(top: Node) -> void:
	for node in _all_nodes(top):
		for signal_info in node.get_signal_list():
			for connection in node.get_signal_connection_list(signal_info.name):
				if (connection.flags&Object.CONNECT_PERSIST)!=0 and (connection.callable.get_object()==top or connection.callable.get_object()==top.get_node_or_null("Interface/PerformancePanel")):node.disconnect(signal_info.name,connection.callable)

func _set_owners(node: Node, top: Node) -> void:
	# Flatten every nested instance together with ownership. Retaining its source
	# scene while also serializing its children creates duplicate orphan nodes on
	# load (notably UI subscenes and the two collision slots).
	node.scene_file_path=""
	for child in node.get_children():child.owner=top;_set_owners(child,top)

func _materials(node: Node, top: Node) -> void:
	if node is GeometryInstance3D:
		if node.material_override is ShaderMaterial:node.material_override=_material(node.material_override,String(top.get_path_to(node))+":material_override")
		if node.material_overlay is ShaderMaterial:node.material_overlay=_material(node.material_overlay,String(top.get_path_to(node))+":material_overlay")
	if node is MeshInstance3D and node.mesh!=null:
		for index in node.mesh.get_surface_count():
			var value: Material=node.get_surface_override_material(index)
			if value==null:value=node.mesh.surface_get_material(index)
			if value is ShaderMaterial:node.set_surface_override_material(index,_material(value,String(top.get_path_to(node))+":surface_"+str(index)))
	for child in node.get_children():_materials(child,top)

func _material(source: ShaderMaterial, path: String) -> ShaderMaterial:
	var id:=source.get_instance_id()
	if material_ids.has(id):
		bindings.append({"path":path,"material_id":material_ids[id].index});return material_ids[id].value
	var result:=ShaderMaterial.new();result.shader=source.shader;result.render_priority=source.render_priority
	var index:=materials.size();var frozen: Dictionary={};var fields: Dictionary={}
	for uniform in source.shader.get_shader_uniform_list():
		var name: String=uniform.name;var value: Variant=source.get_shader_parameter(name)
		if value==null:value=RenderingServer.shader_get_parameter_default(source.shader.get_rid(),name)
		var standard:={"rock_state":"rock","sand_state":"sand","water_state":"water","sediment_state":"sediment","suspended_sand_state":"sediment","wetness_state":"wetness","compaction_state":"compaction","momentum_x_state":"momentum_x","momentum_z_state":"momentum_z","rdc_momentum_x":"momentum_x","rdc_momentum_z":"momentum_z","flux_state":"flux","obstacle_state":"obstacle","foam_state":"foam","local_front_state":"local_front","async_clock":"clock","particle_state":"gravel","stroke_baseline":"baseline"}
		if standard.has(name):
			fields[name]=standard[name];result.set_shader_parameter(name,null)
		elif value is Texture2DRD:
			if wrappers.has(value.texture_rd_rid):fields[name]=wrappers[value.texture_rd_rid]
			else:unknown_dynamic.append({"path":path,"parameter":name,"rid_valid":value.texture_rd_rid.is_valid()})
			result.set_shader_parameter(name,null)
		else:
			if value is ViewportTexture:
				var texture:=ViewportTexture.new();texture.resource_local_to_scene=true;texture.viewport_path=NodePath("ReflectionViewport");value=texture
			result.set_shader_parameter(name,value)
			frozen[name]="resource:"+value.resource_path if value is Resource else value
	materials.append({"id":index,"shader":source.shader.resource_path,"shader_sha256":FileAccess.get_sha256(source.shader.resource_path),"parameters":frozen,"fields":fields})
	material_ids[id]={"index":index,"value":result};bindings.append({"path":path,"material_id":index});return result

func finish(metadata: Dictionary) -> void:
	var arguments:=OS.get_cmdline_args()
	for index in arguments.size()-1:
		if arguments[index]=="--log-file":check("clean_engine_log",not FileAccess.get_file_as_string(arguments[index+1]).contains("ERROR:"))
	FileAccess.open(output+"/bake.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"metadata":metadata,"scope":"Offline actual effective presentation extraction; no formal cutover or runtime readiness claim"},"\t"))
	quit(1 if failed else 0)
