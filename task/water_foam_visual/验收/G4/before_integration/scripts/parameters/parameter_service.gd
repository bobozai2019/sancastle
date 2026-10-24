extends Node

signal changed
const Schema=preload("res://scripts/parameters/parameter_schema.gd")
const FILE="user://parameters/startup.json"
const LAYOUT="user://parameters/windows.cfg"
const GROUPS=["tools","water","sand","props","environment","diagnostics"]
var scene: Node
var startup: Dictionary={}
var saved: Dictionary={}
var sessions: Dictionary={}
var defaults: Dictionary={}
var effective: Dictionary={}
var editing: Dictionary={}
var available: Dictionary={}
var message:="修改仅用于本次运行；需要沿用时请保存。"
var sampling:=true
var samples: Array[float]=[]
var elapsed:=0.0
var _window_layout:=ConfigFile.new()
var _layout_dirty:=false
var _layout_time:=0.0
var _startup_error: StringName=&""
var _programmatic_layout:=false
var _file_path:=FILE
var _layout_path:=LAYOUT
var _last_busy:=true
var _layout_restored:=false
var authored_defaults: Dictionary={}

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--parameter-config="):
			_file_path=argument.trim_prefix("--parameter-config=")
			_layout_path=_file_path.get_base_dir().path_join("windows.cfg")
	# freeze once per process: saving a restart value never changes a later scene boot in this run.
	var loaded:=read_file(_file_path)
	_startup_error=loaded.error
	startup=loaded.get("scenes",{}).duplicate(true);saved=startup.duplicate(true)
	if not _startup_error.is_empty():message="启动配置未加载："+String(_startup_error)
	_window_layout.load(_layout_path)
	for group in GROUPS:
		var window: Window=get_node(group)
		_programmatic_layout=true
		var size_value: Variant=_window_layout.get_value(group,"size",Vector2i(780,660))
		var position_value: Variant=_window_layout.get_value(group,"position",Vector2i(100,100))
		if size_value is Vector2i:window.size=Vector2i(clampi(size_value.x,640,4096),clampi(size_value.y,360,4096))
		if position_value is Vector2i:window.position=position_value
		_clamp_window(window)
		_programmatic_layout=false

static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {"error":&"","scenes":{}}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>262144:return {"error":&"parameter_file_unreadable"}
	var parsed: Variant=JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.size()!=2 or parsed.get("version")!=1 or not parsed.get("scenes") is Dictionary:return {"error":&"invalid_parameter_file"}
	for key in parsed.scenes:
		if key not in ["main","test1_capture","test1_backwash","test1_geometry"]:return {"error":&"invalid_parameter_scene"}
		var error:=Schema.validate_values(parsed.scenes[key])
		if not error.is_empty():return {"error":error}
	return {"error":&"","scenes":parsed.scenes}

func boot_values(key: String) -> Dictionary:
	if "--ignore-parameter-config" in OS.get_cmdline_user_args():return {}
	return startup.get(key,{}).duplicate(true)

func prepare_boot(beach, settings: Dictionary, environment: Dictionary, simulation: Dictionary) -> StringName:
	var values:=boot_values(beach.scene_key)
	if beach.has_meta("parameter_boot_values"):values=beach.get_meta("parameter_boot_values").duplicate(true)
	var error:=Schema.validate_values(values)
	if not error.is_empty():return error
	var coupling: Dictionary={}
	for id in values:
		var row: Dictionary=Schema.rows()[id]
		match row.target:
			"coupling":coupling[id]=float(values[id])
			"environment":environment[id]=float(values[id])
			"simulation":simulation[id]=values[id]
			"boundary":
				if beach.scene_key=="test1_geometry" and float(values[id])!=float(environment.boundary[row.field]):return &"geometry_boundary_is_fixed"
				if row.field=="period_s" and environment.boundary.mode not in [2,3] and float(values[id])!=float(environment.boundary.period_s):return &"boundary_period_not_used_by_mode"
				environment.boundary[row.field]=float(values[id])
	if not coupling.is_empty():environment.coupling_parameters=coupling
	var props: Dictionary={}
	for id in values:
		if Schema.rows()[id].target=="prop":props[id]=values[id]
	if not props.is_empty():environment.prop_parameters=props
	var foam: Dictionary={}
	for id in values:
		if Schema.rows()[id].target=="foam":foam[id]=float(values[id])
	if not foam.is_empty():environment.foam_parameters=foam
	if values.has("solver"):beach.water_solver_id="rusanov_first_order_v1" if int(values.solver)==0 else "muscl_mc_ssprk2_v1"
	if values.has("wave_retention"):beach.wave_retention=values.wave_retention
	beach.set_meta("parameter_boot_values",values)
	return &""

func bind_scene(beach) -> void:
	if is_instance_valid(scene) and scene!=beach:unbind_scene(scene)
	scene=beach;effective={};defaults={};editing={};available={};samples.clear()
	# Snapshot before applying UI overrides. Frozen restart values are read from the actual configuration.
	for id in Schema.rows():
		var row: Dictionary=Schema.rows()[id]
		var value: Variant=_read(row)
		available[id]=value!=null and not (row.target=="boundary" and beach.scene_key=="test1_geometry")
		if row.target=="boundary" and row.field=="period_s" and beach.configuration.environment.boundary.mode not in [2,3]:available[id]=false
		if row.target=="coupling" and not beach.configuration.simulation.enable_erosion:available[id]=false
		defaults[id]=_default(row,value)
		effective[id]=value if value!=null else defaults[id]
		editing[id]=effective[id]
	if not authored_defaults.has(beach.scene_key):authored_defaults[beach.scene_key]=defaults.duplicate(true)
	else:defaults=authored_defaults[beach.scene_key].duplicate(true)
	var boot: Dictionary=beach.get_meta("parameter_boot_values",{})
	for id in boot:
		if Schema.rows()[id].mode!="restart" and available.get(id,false):
			var error:=_apply(Schema.rows()[id],boot[id])
			if error.is_empty():effective[id]=boot[id];editing[id]=boot[id]
	var pending: Dictionary=sessions.get(beach.scene_key,{})
	for id in pending:
		if not Schema.rows().has(id) or not available.get(id,false):continue
		var row: Dictionary=Schema.rows()[id]
		if row.mode=="restart":editing[id]=pending[id]
		elif row.target!="tool":
			if _apply(row,pending[id]).is_empty():effective[id]=_read(row);editing[id]=pending[id]
	if not _startup_error.is_empty():message="启动配置未加载："+String(_startup_error)
	if not _layout_restored:
		_layout_restored=true
		for group in GROUPS:
			if _window_layout.get_value(group,"visible",false):get_node(group).show()
	changed.emit()

func unbind_scene(beach) -> void:
	if scene!=beach:return
	sessions[beach.scene_key]=editing.duplicate(true)
	scene=null;samples.clear();available={};changed.emit()

func _busy() -> bool:
	if not is_instance_valid(scene):return true
	var scenes=get_node_or_null("/root/BeachScenes")
	return scene.closing or scene._saving or scene._restoring or scene._booting or not scene.ready_for_ticks or (scenes!=null and scenes.busy)

func describe(id: String) -> Dictionary:
	if not is_instance_valid(scene) or not editing.has(id):return {}
	var row: Dictionary=Schema.rows()[id]
	var status: String={"live":"实时生效","next":"下次操作生效","restart":"需重建／重启"}[row.mode]
	if row.mode=="restart" and editing[id]!=effective[id]:
		status+=" · 待重启生效（已保存）" if saved.get(scene.scene_key,{}).get(id)!=null and saved[scene.scene_key][id]==editing[id] else " · 尚未保存"
	status+=" · 有效："+str(effective[id])
	if not _enabled(id):status="当前场景不适用／当前材质路径不消费此项"
	return {"value":editing[id],"effective":effective[id],"default":defaults[id],"available":_enabled(id) and not _busy(),"status":status}

func _enabled(id: String) -> bool:
	if not available.get(id,false) or not is_instance_valid(scene):return false
	var row: Dictionary=Schema.rows()[id]
	if row.target!="uniform":return true
	if row.get("node","")=="PrototypeFrontFoamDense" and not scene.get_node("PrototypeFrontFoamDense").is_visible_in_tree():return false
	var material=_material(row)
	if material==null:return false
	match row.field:
		"natural_scatter_gain":return _uniform(material,"rdc_optics_enabled")!=true
		"natural_caustic_softness","natural_caustic_uv_scale":return _uniform(material,"rdc_caustics_enabled")!=true and _uniform(material,"natural_caustic_override")==true and _uniform(material,"prototype_texture_caustics")==true
		"rdc_caustic_scale","rdc_caustic_depth_decay","rdc_caustic_time_scale":return _uniform(material,"rdc_caustics_enabled")==true
		"splat_half_width_m":return float(_uniform(material,"target_diameter_px"))<=0.0
		"natural_contact_shape_scale_per_m":return _uniform(material,"natural_contact_shape_mode")==1
	return true

func row_visible(id: String) -> bool:
	if not is_instance_valid(scene) or Schema.rows()[id].group!="tools":return true
	var related: Array=[]
	match scene.selected_sand_tool:
		&"remove_sand":related=["dig_amount_m3","radius_m","strength"]
		&"place_sand",&"suspended_sand":related=["fill_amount_m3","radius_m","strength"]
		&"castle_v1":related=["castle_height","castle_scale","castle_yaw"]
		&"wall_v1":related=["wall_height","wall_bottom","wall_top"]
		&"shovel_v1":related=["shovel_depth","shovel_width","shovel_shoulder"]
		&"smooth_v1",&"compact_v1":related=["adjust_radius","adjust_strength"]
	if scene.selected_sand_tool not in [&"suspended_sand",&"smooth_v1",&"compact_v1",&"gravel_drop"]:related.append_array(["water_policy","signed_speed_m_s"])
	return id in related

func set_value(id: String, value: Variant) -> StringName:
	if _busy():return &"scene_busy"
	if not _enabled(id):return &"parameter_unavailable"
	if not Schema.valid(id,value):return &"invalid_parameter"
	var candidate: Dictionary={}
	for key in editing:
		if available.get(key,false):candidate[key]=editing[key]
	candidate[id]=value
	var error:=Schema.validate_values(candidate)
	if not error.is_empty():return error
	var row: Dictionary=Schema.rows()[id]
	if row.mode!="restart":
		error=_apply(row,value)
		if not error.is_empty():return error
		effective[id]=_read(row)
	editing[id]=value
	message="已修改；需沿用时请保存。" if row.mode!="restart" else "需重建／重启：请先保存，再自行重启游戏。"
	changed.emit();return &""

func _tool_value(id: String) -> Variant:
	match id:
		"dig_amount_m3","fill_amount_m3","signed_speed_m_s","water_policy":return scene.get(id)
		_:return scene.tool_parameter_values.get(id,Schema.rows()[id].default)

func _read(row: Dictionary) -> Variant:
	match row.target:
		"tool":return _tool_value(row.id)
		"entry":return scene.get(row.id)
		"numerics":return (0 if scene.configuration.environment.water_numerics.solver_id=="rusanov_first_order_v1" else 1) if row.id=="solver" else scene.wave_retention
		"foam":return scene.configuration.environment.get("foam_parameters",{}).get(row.id,row.default)
		"coupling":return scene.configuration.environment.get("coupling_parameters",{}).get(row.id,row.default)
		"environment":return scene.configuration.environment.get(row.id,row.default)
		"simulation":return scene.configuration.simulation.get(row.id,row.default)
		"boundary":return scene.configuration.environment.boundary.get(row.field)
		"sampling":return sampling
		"property":
			var node=scene.get_node_or_null(row.node)
			return node.get(row.field) if node!=null else null
		"sun":
			var sun=_sun()
			return _encode(sun.get(row.field)) if sun!=null else null
		"ambient":
			var env=scene.get_node_or_null("WorldEnvironment")
			return _encode(env.environment.get(row.field)) if env!=null and env.environment!=null else null
		"uniform","uniform_component":
			var material=_material(row)
			if material==null:return null
			var value: Variant=_uniform(material,row.field)
			if value==null:return null
			return value[int(row.component)] if row.target=="uniform_component" else _encode(value)
		"prop":
			var body=_body(row.body)
			return body.profile.get(row.field) if body!=null else null
	return null

func _default(row: Dictionary, actual: Variant) -> Variant:
	if scene.parameter_defaults.has(row.id):return scene.parameter_defaults[row.id]
	if row.target=="boundary":return scene.parameter_defaults.boundary.get(row.field,row.default)
	# Authored scene values are authoritative for material, camera, boundary and body defaults.
	return actual if row.target in ["uniform","uniform_component","sun","ambient","property","prop","boundary"] and actual!=null else row.default

func _material(row: Dictionary):
	var node=scene.get_node_or_null(row.node)
	return node.material_override if node is GeometryInstance3D and node.material_override is ShaderMaterial else null

static func _uniform(material: ShaderMaterial, field: String) -> Variant:
	var value: Variant=material.get_shader_parameter(field)
	return RenderingServer.shader_get_parameter_default(material.shader.get_rid(),field) if value==null else value

func _sun():
	for child in scene.get_children():
		if child is DirectionalLight3D:return child
	return null

func _body(type_name: String):
	if scene.floating_props==null:return null
	for entry in scene.floating_props.authored_registry():
		if String(entry.profile.type_id)==type_name:return entry.body
	return null

static func _encode(value: Variant) -> Variant:
	if value is Color:return [value.r,value.g,value.b,1.0]
	if value is Vector3:return [value.x,value.y,value.z,1.0]
	return value

func _apply(row: Dictionary, value: Variant) -> StringName:
	match row.target:
		"tool":
			scene._finish_ui_stroke(false)
			if row.id in ["dig_amount_m3","fill_amount_m3","signed_speed_m_s","water_policy"]:scene.set(row.id,int(value) if row.id=="water_policy" else value)
			else:scene.tool_parameter_values[row.id]=value
		"entry":scene.set(row.id,value)
		"sampling":sampling=value;samples.clear()
		"property":scene.get_node(row.node).set(row.field,value)
		"sun":_sun().set(row.field,Color(value[0],value[1],value[2]) if row.kind=="color" else value)
		"ambient":scene.get_node("WorldEnvironment").environment.set(row.field,Color(value[0],value[1],value[2]) if row.kind=="color" else value)
		"uniform","uniform_component":
			var original=_material(row)
			var shader_value: Variant=value
			if row.target=="uniform_component":
				shader_value=_uniform(original,row.field);shader_value[int(row.component)]=float(value)
			elif row.kind=="color":shader_value=Vector3(value[0],value[1],value[2])
			# Water sides, suspended sand and contact share scalar optical inputs.
			for binding in scene.material_bindings:
				var material: ShaderMaterial=binding.material
				if material==original or (row.node=="GpuWaterSurface" and _uniform(material,row.field)!=null):material.set_shader_parameter(row.field,shader_value)
			original.set_shader_parameter(row.field,shader_value)
			scene.effective_profile_revision+=1
		_:return &"parameter_requires_restart"
	scene._invalidate_preview()
	return &""

func prepare_props(beach) -> void:
	var values: Dictionary=beach.get_meta("parameter_boot_values",{})
	if beach.floating_props==null:return
	for entry in beach.floating_props.authored_registry():
		var profile: Resource=entry.profile.duplicate(true)
		for id in Schema.rows():
			var row: Dictionary=Schema.rows()[id]
			if row.target=="prop" and String(profile.type_id)==row.body:beach.parameter_defaults[id]=profile.get(row.field)
		for id in values:
			var row: Dictionary=Schema.rows()[id]
			if row.target=="prop" and String(profile.type_id)==row.body:profile.set(row.field,values[id])
		entry.body.profile=profile
		entry.body.physics_material_override=entry.body.physics_material_override.duplicate()
		entry.body.physics_material_override.friction=profile.friction

func save_parameters() -> void:
	if _busy():return
	var values: Dictionary={}
	for id in editing:
		if _enabled(id):values[id]=editing[id]
	var error:=Schema.validate_values(values)
	if not error.is_empty():message=String(error);changed.emit();return
	var candidate:=saved.duplicate(true);candidate[scene.scene_key]=values
	DirAccess.make_dir_recursive_absolute(_file_path.get_base_dir())
	var file:=FileAccess.open(_file_path+".tmp",FileAccess.WRITE)
	if file==null:message="保存失败：无法写入参数文件";changed.emit();return
	file.store_string(JSON.stringify({"version":1,"scenes":candidate},"\t",true,true));file.flush()
	var write_error:=file.get_error();file.close()
	if write_error!=OK or DirAccess.rename_absolute(_file_path+".tmp",_file_path)!=OK:message="保存失败：参数文件未替换"
	else:saved=candidate;message="已保存。需重建项待用户重启后生效。"
	changed.emit()

func load_parameters() -> void:
	if _busy():return
	var loaded:=read_file(_file_path)
	if not loaded.error.is_empty():message=String(loaded.error);changed.emit();return
	var values: Dictionary=loaded.scenes.get(scene.scene_key,{})
	# Validate the complete set first, then apply as a group (no per-control intermediate combinations).
	for id in values:
		if available.get(id,false) and Schema.rows()[id].mode!="restart":_apply(Schema.rows()[id],values[id])
	for id in values:
		if available.get(id,false):editing[id]=values[id];effective[id]=_read(Schema.rows()[id])
	saved=loaded.scenes.duplicate(true);message="已加载参数；需重建项仍等待用户重启。";changed.emit()

func reset_defaults(group: String) -> void:
	if _busy():return
	for id in defaults:
		if Schema.rows()[id].group!=group or not available.get(id,false):continue
		var row: Dictionary=Schema.rows()[id]
		editing[id]=defaults[id]
		if row.mode!="restart":_apply(row,defaults[id]);effective[id]=_read(row)
	message="本窗口已恢复默认；尚未保存。";changed.emit()

func open_window(group: String) -> void:
	if group not in GROUPS:return
	var window: Window=get_node(group)
	_clamp_window(window);window.show();window.grab_focus();_layout_changed()

func _close_group(group: String) -> void:get_node(group).hide();_layout_changed()
func _layout_changed() -> void:
	if not _programmatic_layout:_layout_dirty=true

func _clamp_window(window: Window) -> void:
	if DisplayServer.get_name()=="headless":return
	var screen:=DisplayServer.get_screen_from_rect(Rect2i(window.position,window.size))
	if screen<0:screen=DisplayServer.get_primary_screen()
	var rect:=DisplayServer.screen_get_usable_rect(screen)
	window.position=Vector2i(clampi(window.position.x,rect.position.x,maxi(rect.position.x,rect.end.x-200)),clampi(window.position.y,rect.position.y,maxi(rect.position.y,rect.end.y-100)))

func _refresh_headers() -> void:
	for group in GROUPS:
		var window=get_node(group)
		window.get_node("Margin/Rows/Scene").text="当前场景："+scene.scene_key if is_instance_valid(scene) else "等待场景"
		if group=="tools" and is_instance_valid(scene):
			window.get_node("Margin/Rows/Scene").text+=" · 当前工具："+{&"remove_sand":"挖沙",&"place_sand":"填沙",&"suspended_sand":"投流沙",&"castle_v1":"城堡",&"wall_v1":"沙墙",&"shovel_v1":"铲子",&"smooth_v1":"平滑",&"compact_v1":"压实",&"gravel_drop":"投碎石（数量在道具窗口）"}.get(scene.selected_sand_tool,"")
		window.get_node("Margin/Rows/Message").text=message
		for button in window.get_node("Margin/Rows/Actions").get_children():button.disabled=_busy()

func sampling_snapshot() -> String:
	if not is_instance_valid(scene):return "等待场景"
	var prefix:="帧统计已暂停"
	if not samples.is_empty():
		var sorted:=samples.duplicate();sorted.sort();var total:=0.0
		for sample in sorted:total+=sample
		prefix="进程帧 %.1f FPS · 均值 %.2f ms · P95 %.2f ms"%[1000.0/(total/sorted.size()),total/sorted.size(),sorted[mini(sorted.size()-1,int(sorted.size()*.95))]]
	if scene.runtime.current==null:return prefix
	var pipeline=scene.runtime.current
	return prefix+"\n多窗口共享进程统计，不代表单个窗口 GPU 成本。\n模拟 %.2f s · tick %d · seq %d\n排队 %d · 在途 %d · 未消费 %d\n%s"%[pipeline.advanced_time_s,pipeline.completed_tick,pipeline.completed_state_seq,pipeline.pending_count(),pipeline.active_count(),scene.runtime.result_reservations(),scene.action_message]

func _process(delta: float) -> void:
	var busy:=_busy()
	if busy!=_last_busy:_last_busy=busy;changed.emit()
	if is_instance_valid(scene) and sampling:
		samples.append(maxf(delta,.000001)*1000.0)
		if samples.size()>120:samples.pop_front()
	elapsed+=delta;_layout_time+=delta
	if elapsed>.25:
		elapsed=0;_refresh_headers()
		if $diagnostics.visible:$diagnostics/Margin/Rows/Scroll/Fields/Statistics.text=sampling_snapshot()
	if _layout_dirty and _layout_time>1:
		_layout_dirty=false;_layout_time=0
		for group in GROUPS:
			var window: Window=get_node(group)
			_window_layout.set_value(group,"position",window.position);_window_layout.set_value(group,"size",window.size);_window_layout.set_value(group,"visible",window.visible)
		DirAccess.make_dir_recursive_absolute(_layout_path.get_base_dir());_window_layout.save(_layout_path)
	if _layout_time>1:
		for group in GROUPS:
			var window: Window=get_node(group)
			if window.position!=_window_layout.get_value(group,"position",Vector2i(-1,-1)):_layout_dirty=true
