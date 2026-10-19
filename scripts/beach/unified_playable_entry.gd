extends Node3D

const Presentation=preload("res://scripts/simulation/unified_edit/presentation.gd")
const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Runtime=preload("res://scripts/simulation/unified_edit/domain_runtime.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const PlayerInput=preload("res://scripts/simulation/unified_edit/player_input.gd")
const CheckpointRouter=preload("res://scripts/simulation/unified_edit/checkpoint_router.gd")
const SceneRoutes=preload("res://scripts/beach/unified_scene_routes.gd")
const SOURCES=["res://scripts/beach/unified_playable_entry.gd","res://scripts/beach/unified_performance_panel.gd","res://scripts/simulation/unified_edit/player_input.gd","res://scripts/beach/beach_scene_service.gd","res://scripts/beach/scene_switch_panel.gd","res://scripts/beach/free_camera.gd","res://scripts/beach/ui_visibility.gd","res://scripts/beach/ui_drag.gd","res://scripts/sand/brushes/brush_tool_panel.gd","res://scripts/sand/brushes/brush_preview_view.gd","res://scripts/visual/brush_indicator.gd","res://scripts/visual/water_boundary_sides.gd","res://assets/water_sides/geometry_manifest.json"]
@export var presentation_manifest: String
@export_enum("main","test1_capture","test1_backwash","test1_geometry") var scene_key:="main"
var generation:=1
var playing:=true
var hide_hud:=false
var use_player_camera:=true
var selected_sand_tool: StringName=&"remove_sand"
var gpu_brush: StringName=&""
var dig_amount_m3:=0.1
var fill_amount_m3:=0.1
var manual_wave_amplitude_m:=0.1
var water_policy:=3
var signed_speed_m_s:=0.25
var ready_for_ticks:=false
var closing:=false
var shutdown_requested:=false
var gpu_release_done:=false
var last_error: StringName=&""
var action_message:="正在准备沙场"
var effective_profile_revision:=0
var registry
var configuration: Dictionary={}
var material_bindings: Array=[]
var input:=PlayerInput.new()
var _accumulator:=0.0
var _status_time:=0.0
var _saving:=false
var _restoring:=false
var _transition_result: Dictionary={}
var _saved: Dictionary={}
var _booting:=true
var _last_pointer:=Vector2.ZERO
var _reflection_materials: Array[ShaderMaterial]=[]
var _last_reported_id:=0
var preview_result: Dictionary={}
var preview_received_count:=0
var preview_message:=""
var _preview_state: StringName=&"waiting"
var _preview_target:=Vector2.ZERO
var _preview_has_target:=false
var _preview_screen:=Vector2.ZERO
var _preview_screen_valid:=false
var _preview_key:=""
var _preview_context:=0
var _preview_serial:=0
var _preview_pending:=0
var _preview_elapsed:=0.0
var _preview_retry_elapsed:=0.0
var _preview_exhausted:=false
var _reported_props_error: StringName
@onready var runtime=$UnifiedEditRuntime
@onready var player_camera: Camera3D=$GpuPlayerCamera
@onready var panel=$Interface/ShapeBrushPanel
@onready var floating_props=get_node_or_null("FloatingProps/Service")
@onready var props_panel=get_node_or_null("Interface/FloatingPropsPanel")

func _domain_id() -> StringName:return &"main_beach" if scene_key=="main" else StringName(scene_key)
func playable_scene_family() -> String:return SceneRoutes.family(scene_file_path,scene_key)
func playable_scene_path(key: String) -> String:return SceneRoutes.scene_path(playable_scene_family(),key)

func _ready() -> void:
	get_tree().auto_accept_quit=false
	$GravelLayer.visible=false
	var read:=Presentation.read(presentation_manifest)
	if not read.error.is_empty():_fail(read.error);return
	var data: Dictionary=read.metadata
	if data.settings.scene_key!=scene_key:_fail(&"presentation_scene_mismatch");return
	var plan:=Presentation.material_plan(self,data,get_script())
	if not plan.error.is_empty():_fail(plan.error);return
	material_bindings=plan.bindings
	for binding in material_bindings:
		for uniform in binding.material.shader.get_shader_uniform_list():
			if uniform.name==&"prototype_planar_view_projection":_reflection_materials.append(binding.material)
	var side_error: String=$WaterSides.bind_surface($GpuWaterSurface.material_override,$GpuSandTerrain.material_override)
	if not side_error.is_empty():_fail(StringName(side_error));return
	var seed:=Presentation.initial_domain(data,generation)
	if not seed.error.is_empty():_fail(seed.error);return
	if seed.domain.domain_id!=_domain_id():_fail(&"presentation_domain_mismatch");return
	var settings: Dictionary=data.settings
	for key in ["hide_hud","use_player_camera","dig_amount_m3","fill_amount_m3","manual_wave_amplitude_m","water_policy","signed_speed_m_s"]:set(key,settings[key])
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	if not catalog.error.is_empty():_fail(catalog.error);return
	registry=catalog.registry
	var dependencies:=Presentation.dependencies(PackedStringArray([scene_file_path,presentation_manifest,data.scene.path,data.seed.path]))
	if not dependencies.error.is_empty():_fail(dependencies.error);return
	var sources:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES+Runtime.SOURCES+Presentation.SOURCES+SOURCES)
	sources.append_array(dependencies.sources)
	if floating_props!=null:sources.append_array(PackedStringArray(floating_props.SOURCES))
	sources.append_array(CheckpointRouter.SOURCES)
	sources.append("res://scripts/beach/unified_scene_routes.gd")
	sources.append("res://project.godot")
	var gravel:=Pipeline.Visuals.Gravel.default_profile(scene_key,int(settings.gravel_count));gravel.bed_reconstruction=settings.render_subdivision>1
	var simulation:={"enable_erosion":settings.enable_erosion,"enable_brush_water":settings.enable_brush_water,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":settings.local_front_history,"rise_front_history":false,"contact_history":false}
	var environment:={"engine":Engine.get_version_info().string,"boundary":Pipeline.Boundary.for_scene(_domain_id()),"ordinary_cohesion_yield_height_m":settings.sand_cohesion_yield_height_m,"local_front_wide_field":settings.prototype_local_front_wide_field,"gravel_profile":gravel}
	var frozen:=Config.freeze(registry,_domain_id(),simulation,{"foam_enabled":settings.foam_enabled,"gravel_enabled":settings.gravel_enabled},{},environment,sources)
	if not frozen.error.is_empty():_fail(frozen.error);return
	configuration=frozen.value;input.configure(runtime,registry,_domain_id())
	var error: StringName=runtime.boot(registry,configuration,seed.domain,material_bindings,_transition)
	if not error.is_empty():_fail(error);return
	_apply_brush_selection({"tool":selected_sand_tool,"parameters":{},"dig_amount_m3":dig_amount_m3,"fill_amount_m3":fill_amount_m3})
	set_player_camera(use_player_camera);_update_status()

func _transition(value: Dictionary) -> void:
	if value.error.is_empty():
		if props_panel!=null:props_panel.cancel_mode()
		last_error=&""
		generation=runtime.generation();input.restored();action_message="沙场已就绪";_accumulator=0.0;_last_reported_id=0
		_sync_gravel_count()
		_invalidate_preview()
		if floating_props!=null:
			var prop_result: Dictionary
			if floating_props.active:prop_result=await floating_props.reset(floating_props.authored_layout() if floating_props.layout.is_empty() else floating_props.layout,_domain_id(),generation)
			else:prop_result=await floating_props.attach(runtime,floating_props.authored_registry(),floating_props.authored_layout())
			if not prop_result.error.is_empty():
				value=value.duplicate();value.error=prop_result.error;action_message="道具准备失败："+String(prop_result.error)
			elif not playing:await _props_hold(true,&"user")
	elif _booting:_fail(value.error)
	else:action_message="恢复失败："+String(value.error)
	_booting=false
	_transition_result=value

func _props_hold(paused: bool, reason: StringName) -> StringName:
	if floating_props==null:return &""
	while floating_props.busy and not closing:await get_tree().physics_frame
	if closing:return &"closing"
	if not floating_props.active:return &""
	var result: Dictionary=await floating_props.set_paused(paused,reason)
	# Props are not serialized and never write authority. A latched consumer
	# fault must not prevent preserving sand/water or restoring a clean domain.
	# Accept only an independently confirmed held world boundary, including the
	# registered read terminal proof required by restore.
	if paused and not result.error.is_empty() and result.error==floating_props.last_error and floating_props.holds.has(reason):
		for frame in 3:
			await get_tree().physics_frame
			if floating_props.is_held_at_boundary(reason):return &""
	return result.error

func _sync_props_user_hold() -> void:
	if floating_props==null or not floating_props.active or floating_props.busy or _booting or _restoring:return
	if floating_props.holds.has(&"user")!=not playing:await _props_hold(not playing,&"user")

func _fail(error: StringName) -> void:
	last_error=error;ready_for_ticks=false;playing=false;action_message="沙场准备失败："+String(error);_update_status()

func _process(delta: float) -> void:
	if closing:return
	_sync_props_user_hold()
	if floating_props!=null and floating_props.last_error!=_reported_props_error:
		_reported_props_error=floating_props.last_error
		if not _reported_props_error.is_empty():action_message="漂浮物已保持，可保存或恢复沙场："+String(_reported_props_error)
	ready_for_ticks=not _saving and not _restoring and runtime.ready_for_input() and last_error.is_empty()
	if registry!=null:
		input.poll()
		for result in input.terminal:
			if result.get("generation",generation)==generation and result.get("command_id",0)>_last_reported_id and result.get("profile_version",0)>0:
				_last_reported_id=result.command_id
				action_message="已应用" if result.outcome==Pipeline.L.Outcome.APPLIED else ("未改变沙场" if result.outcome==Pipeline.L.Outcome.NO_CHANGE else "GPU拒绝："+str(result.error_code))
	if runtime.current!=null and not runtime.current.fault_reason().is_empty():_fail(runtime.current.fault_reason())
	_sync_gravel_count()
	if ready_for_ticks and playing:
		_accumulator=minf(_accumulator+delta,0.25)
		while _accumulator>=1.0/30.0 and runtime.current.pending_count()<4:
			if not runtime.request_tick(1.0/30.0).is_empty():break
			_accumulator-=1.0/30.0
	else:_accumulator=0.0
	_update_reflection()
	_update_preview(delta)
	_status_time+=delta
	if _status_time>=0.1:_status_time=0.0;_update_status()

func _sync_gravel_count() -> void:
	if runtime.current==null:$GravelLayer.visible=false;return
	var visuals=runtime.current.visuals
	# This consumer follows validated common receipts. It never gates recording
	# or predicts successful population growth from admission.
	$GravelLayer.multimesh.visible_instance_count=visuals.active_count
	$GravelLayer.visible=visuals.gravel_enabled and visuals.active_count>0

func _update_status() -> void:
	var drainage=get_node_or_null("Interface/ShapeBrushPanel/Margin/Controls/ConnectedDrainage")
	if drainage!=null:
		drainage.set_pressed_no_signal((water_policy&1)!=0)
		drainage.disabled=not ready_for_ticks
	var label=get_node_or_null("Interface/StatusLabel")
	if label==null:return
	var phase:="运行" if playing else "暂停"
	var tick:=0;var time:=0.0
	if runtime!=null and runtime.current!=null:tick=runtime.current.completed_tick;time=runtime.current.advanced_time_s
	label.text="沙滩 · %s · %s\nTick %d · 模拟 %.2f s\n左键使用工具 · 右键转向 · WASD移动 · 空格暂停 · F5视角 · F6隐藏UI\n%s"%[scene_key,phase,tick,time,action_message]
	panel.show_status(preview_message if not preview_message.is_empty() else action_message,_preview_state if not preview_message.is_empty() else (&"invalid" if not last_error.is_empty() else (&"ready" if ready_for_ticks else &"waiting")))

func _capture_brush_selection() -> Dictionary:
	return {"tool":selected_sand_tool,"parameters":panel.parameters(),"dig_amount_m3":dig_amount_m3,"fill_amount_m3":fill_amount_m3}
func _apply_brush_selection(value: Dictionary) -> void:
	selected_sand_tool=StringName(value.tool);dig_amount_m3=value.dig_amount_m3;fill_amount_m3=value.fill_amount_m3;panel.apply_selection(value)
	_invalidate_preview()
func _on_tool_changed(tool: StringName) -> void:
	if props_panel!=null and props_panel.has_world_mode():props_panel.cancel_mode()
	_finish_ui_stroke(false);selected_sand_tool=tool
	if panel.selected_tool!=tool:
		var profile: Dictionary=registry.profile(PlayerInput._profile_id(tool,false))
		panel.apply_selection({"tool":tool,"parameters":profile.get("defaults",{}),"dig_amount_m3":dig_amount_m3,"fill_amount_m3":fill_amount_m3})
	_update_status()
func _on_parameters_changed() -> void:
	_finish_ui_stroke(false);dig_amount_m3=panel.dig_amount();fill_amount_m3=panel.fill_amount()
func _on_connected_drainage_toggled(enabled: bool) -> void:
	# Policy is frozen into each queued command and its effective hash. Finish
	# the gesture so a toggle cannot change an already submitted stroke.
	_finish_ui_stroke(false)
	water_policy=(water_policy|1) if enabled else (water_policy&~1)
	action_message="连通排水已开启" if enabled else "连通排水已关闭 · 保留推水与水流模拟"
	_update_status()
func _on_dig_tool_pressed() -> void:_on_tool_changed(&"remove_sand")
func _on_fill_tool_pressed() -> void:_on_tool_changed(&"place_sand")
func _on_dig_amount_changed(value: float) -> void:dig_amount_m3=value
func _on_fill_amount_changed(value: float) -> void:fill_amount_m3=value
func _on_wave_amount_changed(value: float) -> void:manual_wave_amplitude_m=value
func _on_camera_look_started() -> void:_finish_ui_stroke(false)

func _on_prop_mode_changed() -> void:
	_finish_ui_stroke(false)
	if props_panel!=null and props_panel.has_world_mode():$BrushIndicator.hide_indicator()

func _on_trigger_wave_pressed() -> void:
	if not ready_for_ticks:return
	var boundary=runtime.current.boundary
	var next:=Pipeline.I.next_identity(boundary.highwater)
	if not next.error.is_empty():action_message=String(next.error);return
	# Pending and recorded water work all precede the declared future packet.
	var tick: int=runtime.current._scheduled_tick+runtime.current.pending_count()+2
	var result: Dictionary=runtime.request_wave({"domain_id":_domain_id(),"generation":generation,"request_id":next.value,"start_tick":tick,"profile_id":&"test_packet","amplitude_m":manual_wave_amplitude_m,"duration_s":3.0,"seed":int(next.value*17+31)})
	action_message="波浪已排队" if result.accepted else String(result.error)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:_finish_ui_stroke(false)

func _unhandled_input(event: InputEvent) -> void:
	if props_panel!=null and props_panel.handle_world_input(event):return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:playing=not playing;_update_status();get_viewport().set_input_as_handled()
			KEY_F5:set_player_camera(not use_player_camera)
			KEY_F6:hide_hud=not hide_hud
			KEY_BRACKETLEFT:if selected_sand_tool==&"castle_v1":panel.rotate_castle(-15)
			KEY_BRACKETRIGHT:if selected_sand_tool==&"castle_v1":panel.rotate_castle(15)
	if not ready_for_ticks or player_camera.look_active:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var hit:=pick(event.position)
		if hit.is_empty():return
		var position: Vector3=hit.position
		var amount:=dig_amount_m3 if selected_sand_tool==&"remove_sand" else fill_amount_m3
		var result:=input.begin(selected_sand_tool,Vector2(position.x,position.z),panel.parameters(),amount,water_policy,signed_speed_m_s)
		_invalidate_preview()
		gpu_brush=selected_sand_tool if result.accepted else &""
		if not result.accepted:input.finish()
		action_message="已排队，等待GPU校验" if result.accepted else String(result.error)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var hit:=pick(event.position)
		if hit.is_empty():_invalidate_preview();$BrushIndicator.hide_indicator();return
		var position: Vector3=hit.position;var xz:=Vector2(position.x,position.z)
		$BrushIndicator.aim(position,position.y,selected_sand_tool)
		if not gpu_brush.is_empty():
			var result:=input.move(xz)
			if not result.accepted and result.error not in [&"below_sample_spacing",&"single_stamp"]:action_message=String(result.error)
		preview_at(xz);_preview_screen=event.position;_preview_screen_valid=true
		_last_pointer=xz

func _finish_ui_stroke(cancel: bool) -> void:
	gpu_brush=&""
	if registry!=null:input.finish(cancel)
	_invalidate_preview()

func _invalidate_preview() -> void:
	var next:=Pipeline.I.next_identity(_preview_context)
	if next.error.is_empty():_preview_context=next.value
	else:_preview_exhausted=true
	_preview_pending=0;_preview_key="";_preview_has_target=false;_preview_screen_valid=false
	preview_result={};preview_message=""
	if runtime!=null:runtime.invalidate_preview()
	if is_node_ready():$BrushPreview.hide_preview()

func preview_at(point: Vector2) -> void:
	_preview_target=point;_preview_has_target=true;_preview_screen_valid=false
	_refresh_preview_geometry()

func _preview_descriptor() -> Dictionary:
	var amount:=dig_amount_m3 if selected_sand_tool==&"remove_sand" else fill_amount_m3
	return input.preview_request(selected_sand_tool,_preview_target,panel.parameters(),amount,water_policy,signed_speed_m_s)

func _refresh_preview_geometry() -> Dictionary:
	if not ready_for_ticks or registry==null:return {"error":&"not_ready"}
	var descriptor:=_preview_descriptor()
	if not descriptor.error.is_empty():
		$BrushPreview.hide_preview();preview_message="";return descriptor
	var key:=Config.digest_data(descriptor.geometry)
	if key!=_preview_key:
		_preview_key=key;preview_result={};preview_message="正在查询完成态 · 仅供参考";_preview_state=&"waiting"
		_draw_preview(descriptor.geometry,0.0,false,&"waiting")
	return descriptor

func _draw_preview(geometry: Dictionary, base: float, baseline: bool, state: StringName) -> void:
	$BrushPreview/Footprint.material_override.set_shader_parameter("use_stroke_baseline",baseline)
	$BrushPreview.configure(geometry.tool,geometry.parameters,geometry.point,base,geometry.start,geometry.end,state)

func _update_preview(delta: float) -> void:
	_preview_retry_elapsed+=delta
	if _preview_retry_elapsed>=1.0:
		_preview_retry_elapsed=0.0;runtime.retry_preview_readback();runtime.retry_retirement()
	_preview_elapsed=minf(_preview_elapsed+delta,0.2)
	if _preview_exhausted or not ready_for_ticks or not _preview_has_target or _preview_elapsed<0.1 or _preview_pending!=0:return
	if _preview_screen_valid:
		var hit:=pick(_preview_screen)
		if hit.is_empty():_invalidate_preview();return
		_preview_target=Vector2(hit.position.x,hit.position.z)
	var descriptor:=_refresh_preview_geometry()
	if not descriptor.error.is_empty() or _preview_pending!=0:return
	var identity:=Pipeline.I.next_identity(_preview_serial)
	if not identity.error.is_empty():return
	_preview_serial=identity.value;_preview_pending=_preview_serial;_preview_elapsed=0.0
	var admitted: Dictionary=runtime.request_preview(descriptor.request,_preview_received.bind(_preview_pending,_preview_context,_preview_key,descriptor.geometry),Pipeline.Views.Freshness.SNAPSHOT)
	if not admitted.accepted:
		_preview_pending=0
		if admitted.error not in [&"preview_busy",&"transition_busy"]:
			preview_message="此位置无法预览";_preview_state=&"invalid";_draw_preview(descriptor.geometry,0.0,false,&"invalid")

func _preview_received(value: Dictionary, serial: int, context: int, key: String, geometry: Dictionary) -> void:
	if serial!=_preview_pending:return
	_preview_pending=0
	if closing or context!=_preview_context or key!=_preview_key or geometry.tool!=selected_sand_tool:return
	if not value.get("error",&"missing").is_empty():return
	preview_result=value.duplicate(true);preview_received_count+=1
	var invalid: bool=value.flags!=0 or value.obstacles>0 or value.count==0
	var waiting: bool=geometry.stroke_id!=0 and geometry.tool in [&"wall_v1",&"shovel_v1"] and not value.uses_baseline
	_preview_state=&"invalid" if invalid else (&"waiting" if waiting else &"ready")
	preview_message="完成态 %d · 仅供参考%s"%[value.state_seq," · 有障碍或无有效范围" if invalid else (" · 正在建立笔画基准" if waiting else "")]
	_draw_preview(geometry,value.base,value.uses_baseline,_preview_state)

func pick(screen: Vector2) -> Dictionary:
	if runtime.current==null or runtime.current_index<0:return {}
	var camera:=get_viewport().get_camera_3d()
	var origin:=camera.project_ray_origin(screen)
	var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*100.0,1))
	if hit.get("collider")!=runtime.surfaces[runtime.current_index].get_node("Terrain"):return {}
	return hit

func set_player_camera(enabled: bool) -> void:
	use_player_camera=enabled
	if not is_node_ready():return
	$GpuPlayerCamera.current=enabled;$GpuOverviewCamera.current=not enabled
	if not enabled:player_camera._release_mouse()

func _update_reflection() -> void:
	if not is_node_ready():return
	var camera:=get_viewport().get_camera_3d()
	if camera==null:return
	var reflection: Camera3D=$ReflectionViewport/ReflectionCamera
	var position:=camera.global_position;position.y=-position.y
	var forward: Vector3=-camera.global_basis.z;forward.y=-forward.y
	var up: Vector3=camera.global_basis.y;up.y=-up.y
	reflection.fov=camera.fov;reflection.near=camera.near;reflection.far=camera.far
	reflection.projection=camera.projection;reflection.keep_aspect=camera.keep_aspect;reflection.size=camera.size
	reflection.frustum_offset=camera.frustum_offset;reflection.h_offset=camera.h_offset;reflection.v_offset=camera.v_offset
	reflection.global_position=position;reflection.look_at(position+forward,up)
	for material in _reflection_materials:
		material.set_shader_parameter("prototype_planar_view_projection",reflection.get_camera_projection()*Projection(reflection.global_transform.affine_inverse()))

func save_gpu_checkpoint(path: String) -> StringName:
	if _booting or _saving or _restoring or not ready_for_ticks:return &"transition_busy"
	if floating_props!=null and floating_props.active and not floating_props.has_operation_room(3):return &"identity_exhausted"
	_saving=true;_finish_ui_stroke(false);_saved={}
	var start:=Time.get_ticks_msec()
	while not input.end_requested.is_empty() and Time.get_ticks_msec()-start<30000:await get_tree().process_frame
	if not input.end_requested.is_empty():_saving=false;return &"stroke_end_timeout"
	var hold_error:=await _props_hold(true,&"save")
	if not hold_error.is_empty():_saving=false;return hold_error
	var admitted: Dictionary=runtime.save_checkpoint(path,{"policy":water_policy,"speed":signed_speed_m_s,"brush":_capture_brush_selection()},func(value: Dictionary):_saved=value)
	if not admitted.accepted:
		await _props_hold(false,&"save");_saving=false;return admitted.error
	while _saved.is_empty() and Time.get_ticks_msec()-start<60000:await get_tree().process_frame
	await _props_hold(false,&"save");_saving=false
	return _saved.get("error",&"checkpoint_wait_timeout")

func restore_gpu_checkpoint(path: String) -> StringName:
	if _booting or _saving or _restoring or closing or runtime.current==null:return &"transition_busy"
	if floating_props!=null and floating_props.active and not floating_props.has_operation_room(5,true):return &"identity_exhausted"
	var loaded:=CheckpointRouter.load_file(path,configuration)
	if not loaded.error.is_empty():return loaded.error
	_restoring=true;_finish_ui_stroke(false);_transition_result={}
	var hold_error:=await _props_hold(true,&"restore")
	if not hold_error.is_empty():_restoring=false;return hold_error
	var error: StringName=runtime.restore_checkpoint(loaded.checkpoint,_transition)
	if not error.is_empty():
		await _props_hold(false,&"restore");_restoring=false;return error
	var start:=Time.get_ticks_msec()
	while _transition_result.is_empty() and Time.get_ticks_msec()-start<60000:await get_tree().process_frame
	await _props_hold(false,&"restore");_restoring=false
	error=_transition_result.get("error",&"restore_wait_timeout")
	if error.is_empty():
		var selection: Dictionary=loaded.checkpoint.selection
		water_policy=selection.policy;signed_speed_m_s=selection.speed;_apply_brush_selection(selection.brush)
	return error

func shutdown() -> void:
	if gpu_release_done:return
	if closing:
		while not gpu_release_done:await get_tree().process_frame
		return
	shutdown_requested=true;closing=true;playing=false;ready_for_ticks=false
	_invalidate_preview()
	player_camera._release_mouse()
	if floating_props!=null and floating_props.active:await floating_props.shutdown()
	runtime.shutdown()
	var retry_at:=Time.get_ticks_msec()
	while not runtime.closed:
		if Time.get_ticks_msec()-retry_at>=500:runtime.retry_retirement();retry_at=Time.get_ticks_msec()
		await get_tree().process_frame
	input.poll();gpu_release_done=true
func unified_release_complete() -> bool:return gpu_release_done and runtime.closed

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		await shutdown();get_tree().quit()
