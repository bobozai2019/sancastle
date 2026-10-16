extends "res://scripts/beach/shape_brush_entry.gd"

const PreviewQuery=preload("res://scripts/simulation/brushes/brush_preview_query.gd")
@onready var brush_panel=$Interface/ShapeBrushPanel
@onready var brush_preview=$BrushPreview
var preview_query
var preview_request_in_flight:=false
var preview_cache_key:=""
var preview_cache:={}
var preview_next_ms:=0
var preview_baseline:=Texture2DRD.new()
var ui_tool:StringName=&"remove_sand"
var ui_pointer:=Vector2.ZERO
var ui_pressed:=false
var ui_pump_running:=false
var ui_closing:=false
var ui_stroke_identity:=0
var ui_preview_start:=Vector2.ZERO
var ui_preview_end:=Vector2.ZERO
var ui_last_failure:=""
var ui_brush_events:=[]
var preview_suspended:=false
var _restore_preview_query

func _runtime_configuration_signature() -> Dictionary:
	var signature:=super._runtime_configuration_signature()
	signature["brush_ui_version"]=1
	signature["suspended_sand_destination_version"] = 1
	signature.sources["res://shaders/visual/suspended_sand_cloud.gdshader"] = FileAccess.get_sha256("res://shaders/visual/suspended_sand_cloud.gdshader")
	_index_sources("res://assets/brushes",signature.sources)
	_index_sources("res://shaders/brushes",signature.sources)
	return signature

func _capture_brush_selection() -> Dictionary:
	return {"tool":String(ui_tool),"parameters":brush_panel.parameters(),"dig_amount_m3":brush_panel.dig_amount(),"fill_amount_m3":brush_panel.fill_amount()}

func _apply_brush_selection(selection:Dictionary) -> void:
	brush_panel.apply_selection(selection)
	_on_ui_tool_changed(StringName(selection.tool));_on_ui_parameters_changed()

func _ready() -> void:
	super._ready()
	_on_ui_parameters_changed()

func _mark_ready(token:int) -> void:
	if preview_query==null or not preview_query.initialized:return
	super._mark_ready(token)

func _render_setup(target:SandWaterDomain,token:int) -> void:
	super._render_setup(target,token)
	if solver==null or solver.rd==null or shape_gpu==null:return
	preview_query=PreviewQuery.new()
	if not preview_query.initialize(solver,shape_gpu.images.castle_template):call_deferred("_fail","brush preview initialize: "+preview_query.last_error)

func _is_shape_tool() -> bool:return ui_tool in [&"castle_v1",&"wall_v1",&"shovel_v1"]

func _on_ui_tool_changed(tool:StringName) -> void:
	_finish_ui_stroke(false);gpu_brush=&"";ui_tool=tool;ui_last_failure="";preview_cache_key=""
	if not _is_shape_tool():selected_sand_tool=tool
	get_viewport().gui_release_focus()
	brush_panel.show_status("左键使用选定工具" if ready_for_ticks else "等待沙场准备")

func _on_ui_parameters_changed() -> void:
	_finish_ui_stroke(false);gpu_brush=&"";ui_last_failure="";preview_cache_key=""
	if brush_panel!=null:dig_amount_m3=brush_panel.dig_amount();fill_amount_m3=brush_panel.fill_amount()

func _drain_input() -> void:
	await super._drain_input()
	if ui_tool != &"suspended_sand" or input_results.is_empty(): return
	var result: Dictionary = input_results[-1].result
	if result.get("status") == 1:
		brush_panel.show_status("已投放 %.3f m³ 悬沙" % result.actual_sand_m3)
	else:
		brush_panel.show_status("此处没有可投放的水域" if result.get("error_code") == 3 else "投放未应用，请稍后重试", &"invalid")

func _update_status() -> void:
	super._update_status()
	if brush_panel!=null:brush_panel.visible=not hide_hud

func _update_brush_indicator() -> void:
	if _is_shape_tool():
		if brush_indicator!=null:brush_indicator.hide_indicator()
		return
	if brush_indicator == null:
		return
	if not show_brush_indicator or not ready_for_ticks or preview_suspended or ui_closing or _scene_switch_busy() or _over_gui(get_viewport().get_mouse_position()) or player_camera.look_active:
		brush_indicator.hide_indicator()
		return
	# Aim at the same current collision bed used by the edit, including underwater.
	# The old y=0 plane could preview a different XZ position on sloping sand.
	var hit := pick(get_viewport().get_mouse_position())
	if hit.is_empty() or not _pick_current(hit):
		brush_indicator.hide_indicator()
		return
	var point: Vector3 = hit.position
	var radius := 0.45 if ui_tool == &"gravel_drop" else (0.75 if ui_tool == &"suspended_sand" else 0.3)
	brush_indicator.scale = Vector3(radius / 0.38, 1.0, radius / 0.38)
	brush_indicator.aim(point, point.y, &"place_sand" if ui_tool in [&"suspended_sand", &"gravel_drop"] else ui_tool)

func _over_gui(point:Vector2) -> bool:
	if brush_panel.visible and brush_panel.get_global_rect().has_point(point):return true
	if manual_edit_panel!=null and manual_edit_panel.visible and manual_edit_panel.get_global_rect().has_point(point):return true
	return get_viewport().gui_get_hovered_control()!=null

func _input(event:InputEvent) -> void:
	if event is InputEventMouseMotion:
		ui_pointer=event.position
		if ui_pressed and _over_gui(event.position):stroke_controller.interrupt_subpath()
	if event is InputEventMouseButton:
		ui_pointer=event.position
		if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:_finish_ui_stroke(true)
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:_finish_ui_stroke(false)
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:_finish_ui_stroke(false)
		if event.keycode==KEY_SPACE:_finish_ui_stroke(true)
	super._input(event)

func _unhandled_input(event:InputEvent) -> void:
	if preview_suspended:return
	if not _is_shape_tool():super._unhandled_input(event);return
	if event is InputEventKey:
		if event.pressed and not event.echo and ui_tool==&"castle_v1" and event.keycode in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:
			brush_panel.rotate_castle(-15.0 if event.keycode==KEY_BRACKETLEFT else 15.0);get_viewport().set_input_as_handled();return
		super._unhandled_input(event);return
	if ui_closing or closing or shutdown_requested or _scene_switch_busy():return
	if player_camera!=null and player_camera.look_active:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		if not ready_for_ticks or ui_pump_running:return
		var hit:=pick(event.position)
		if hit.is_empty() or not _pick_current(hit):_show_ui_status("等待有效沙面",&"waiting");return
		var pos:Vector3=hit.position;var point:=Vector2(pos.x,pos.z);var params:Dictionary=brush_panel.parameters()
		var error:=BrushProtocol.Spec.parameter_error(ui_tool,params)
		if not error.is_empty():_show_ui_status("参数无效，请核对宽度与高度",&"invalid");return
		ui_stroke_identity+=1
		error=stroke_controller.begin_stroke(ui_tool,params,point,ui_stroke_identity,generation)
		if not error.is_empty():_show_ui_status(String(error),&"invalid");return
		ui_pressed=true;ui_last_failure="";ui_preview_start=point;ui_preview_end=point;ui_pump_running=true
		get_viewport().gui_release_focus();call_deferred("_pump_ui_stroke",generation,ui_stroke_identity)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and ui_pressed and stroke_controller.state==&"capturing":
		var hit:=pick(event.position)
		if hit.is_empty() or not _pick_current(hit):stroke_controller.interrupt_subpath();return
		var pos:Vector3=hit.position;var point:=Vector2(pos.x,pos.z)
		ui_preview_start=ui_preview_end;ui_preview_end=point
		var error:=stroke_controller.append_path_sample(point)
		if not error.is_empty():ui_pressed=false;ui_last_failure=String(error)
		get_viewport().set_input_as_handled()

func _finish_ui_stroke(normal:bool) -> void:
	ui_pressed=false
	if stroke_controller.state in [&"capturing",&"draining"]:stroke_controller.end_stroke(normal)

func _ui_error_message(error:Variant) -> String:
	match error:
		&"out_of_domain":return "作用范围超出沙场，请缩小或换个位置"
		&"invalid_command":return "参数无效，请核对尺寸和宽度"
		&"backend_unavailable":return "正在处理上一笔，请稍后重试"
		&"inactive_generation",&"invalid_baseline":return "场景已改变，请重新开始这一笔"
		&"stroke_buffer_full":return "路径缓存已满，请松开后重新开始"
		8:return "此处存在障碍或没有有效沙面，请换个位置"
		9,&"budget_exceeded":return "本段沙量超过额度，请减小尺寸"
		17:return "此处有水，请移到干沙区域"
		16,18:return "本次操作未通过校验，沙面保持原状"
	return "本次操作未应用，请稍后重试"

func _pump_ui_stroke(epoch:int,identity:int) -> void:
	while (busy or input_running or not command_queue.pending.is_empty()) and last_error.is_empty() and not closing:
		if ui_closing:stroke_controller.end_stroke(false);ui_pump_running=false;return
		await get_tree().process_frame
	var error: StringName=await begin_shape_stroke(identity)
	if not error.is_empty():ui_last_failure=_ui_error_message(error);stroke_controller.end_stroke(false);ui_pump_running=false;return
	while epoch==generation and not closing and last_error.is_empty():
		stroke_controller.begin_frame(Engine.get_process_frames())
		var segment:Dictionary=stroke_controller.peek_segment()
		if segment.is_empty():
			if stroke_controller.state in [&"draining",&"settled"] and stroke_controller.outstanding==0:break
			await get_tree().process_frame;continue
		if busy or input_running:await get_tree().process_frame;continue
		var command:=BrushProtocol.make_command(stroke_controller.brush_id,stroke_controller.params,segment.start_xz_m,segment.end_xz_m,domain.domain_id,generation,command_queue.last_command_id+1,identity,segment.sample_index,completed_ticks,shape_baseline_token)
		command.material_profile_id=&"molded_v1" if stroke_controller.brush_id!=&"shovel_v1" else &"plain_sand_v1"
		error=input_scheduler.submit(command)
		if error==&"backend_unavailable":await get_tree().process_frame;continue
		if not error.is_empty():ui_last_failure=_ui_error_message(error);stroke_controller.end_stroke(false);break
		stroke_controller.acknowledge_admission(segment,command.command_id)
		if not input_running:input_running=true;call_deferred("_drain_input")
		var row:Dictionary={}
		while epoch==generation and not closing and last_error.is_empty():
			if not input_scheduler.terminal.is_empty() and input_scheduler.terminal[-1].command.command_id==command.command_id:row=input_scheduler.terminal[-1];break
			await get_tree().process_frame
		stroke_controller.settle_command(command.command_id,epoch)
		_record_diagnostic(ui_brush_events,{"command":command,"terminal":row,"buffer_points":stroke_controller.buffer_points(),"at_us":Time.get_ticks_usec()})
		if row.is_empty() or row.result.get("status",3)==3:
			ui_last_failure=_ui_error_message(row.get("result",{}).get("error_code",row.get("result",{}).get("error","后端失败")))
			stroke_controller.end_stroke(false);break
	if shape_stroke_id!=0 and epoch==generation and not closing:await end_shape_stroke()
	ui_pressed=false;ui_pump_running=false

func _start_tick() -> void:
	if ui_pump_running and (shape_stroke_id!=0 or command_queue.pending.is_empty()) and (shape_stroke_id==0 or stroke_controller.buffer_points()>0 or stroke_controller.outstanding>0):return
	super._start_tick()

func _show_ui_status(text:String,state:StringName=&"ready") -> void:
	if not ui_last_failure.is_empty():brush_panel.show_status(ui_last_failure,&"invalid")
	else:brush_panel.show_status(text,state)

func _process(delta:float) -> void:
	super._process(delta)
	if not is_node_ready():return
	if _scene_switch_busy():_finish_ui_stroke(true)
	if not ready_for_ticks or ui_closing or preview_suspended or beach_restore_running or gpu_save_running or not _is_shape_tool() or _over_gui(ui_pointer) or player_camera.look_active:
		brush_preview.hide_preview();return
	var hit:=pick(ui_pointer)
	if hit.is_empty():brush_preview.hide_preview();_show_ui_status("光标未指向有效沙面",&"invalid");return
	var pos:Vector3=hit.position;var point:=Vector2(pos.x,pos.z);var params:Dictionary=brush_panel.parameters()
	var state:StringName=&"waiting" if busy or not _pick_current(hit) else &"ready"
	var command:=BrushProtocol.make_command(ui_tool,params,point,point,domain.domain_id,generation,1,1,0,completed_ticks,1)
	if command.is_empty() or not BrushProtocol.command_error(command).is_empty():state=&"invalid"
	var base:float=0.0 if ui_tool==&"castle_v1" else pos.y
	if ui_tool==&"castle_v1" and state!=&"invalid":
		var key:=str([generation,solver.state_revision,point,params])
		if preview_cache_key==key and not preview_cache.is_empty():
			base=preview_cache.base;state=&"invalid" if preview_cache.flags!=0 or (preview_cache.water>0.0 and not enable_brush_water) else state
		else:
			state=&"waiting"
			if not busy and not preview_request_in_flight and Time.get_ticks_msec()>=preview_next_ms:
				preview_request_in_flight=true;preview_next_ms=Time.get_ticks_msec()+80
				RenderingServer.call_on_render_thread(_render_preview_query.bind(point,params,key,generation,solver.state_revision))
	preview_baseline.texture_rd_rid=shape_gpu.images.baseline
	brush_preview.bind_fields(rock_texture,sand_texture,preview_baseline)
	brush_preview.footprint.material_override.set_shader_parameter("use_stroke_baseline",shape_stroke_id!=0)
	var start:=point;var finish:=point
	if ui_pressed and ui_tool!=&"castle_v1":
		finish=ui_preview_end;var displacement:=finish-ui_preview_start;start=finish-displacement.normalized()*minf(displacement.length(),2.0)
	brush_preview.configure(ui_tool,params,point,base,start,finish,state)
	if ui_pump_running:_show_ui_status("待提交 %d 段 · 已提交 %d 段"%[stroke_controller.buffer_points(),stroke_controller.outstanding],&"waiting")
	else:_show_ui_status("位置或参数无效" if state==&"invalid" else ("等待完成态核对" if state==&"waiting" else "可操作"),state)

func _render_preview_query(point:Vector2,params:Dictionary,key:String,epoch:int,revision:int) -> void:
	if closing or epoch!=generation or preview_query==null or not preview_query.request(point,params,_on_preview_query.bind(key,epoch,revision)):
		call_deferred("_preview_query_ready",PackedByteArray(),key,epoch,revision)

func _on_preview_query(bytes:PackedByteArray,key:String,epoch:int,revision:int) -> void:
	call_deferred("_preview_query_ready",bytes,key,epoch,revision)

func _preview_query_ready(bytes:PackedByteArray,key:String,epoch:int,revision:int) -> void:
	preview_request_in_flight=false
	if bytes.size()!=64 or epoch!=generation or solver==null or solver.state_revision!=revision:return
	preview_cache_key=key;preview_cache={"base":bytes.decode_float(0),"minimum":bytes.decode_float(4),"flags":bytes.decode_u32(8),"water":bytes.decode_float(12),"count":bytes.decode_u32(16)}

func _on_camera_look_started() -> void:
	_finish_ui_stroke(false);super._on_camera_look_started()

func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:_finish_ui_stroke(false)
	super._notification(what)

func save_gpu_checkpoint(path:String) -> StringName:
	_finish_ui_stroke(true)
	while ui_pump_running:await get_tree().process_frame
	return await super.save_gpu_checkpoint(path)

func _render_beach_restore_build(checkpoint:Dictionary,candidate_domain) -> void:
	super._render_beach_restore_build(checkpoint,candidate_domain)
	if not beach_restore_candidate.error.is_empty():return
	_restore_preview_query=PreviewQuery.new()
	if not _restore_preview_query.initialize(beach_restore_candidate.solver,_restore_shape_candidate.images.castle_template):beach_restore_candidate.error=&"brush_preview_candidate_build_failed"

func _render_beach_restore_discard() -> void:
	if _restore_preview_query!=null:_restore_preview_query.release();_restore_preview_query=null
	super._render_beach_restore_discard()

func _render_beach_restore_commit() -> void:
	preview_baseline.texture_rd_rid=RID()
	if preview_query!=null:preview_query.release()
	super._render_beach_restore_commit()
	preview_query=_restore_preview_query;_restore_preview_query=null
	preview_cache_key=""

func restore_gpu_checkpoint_data(checkpoint:Dictionary) -> StringName:
	preview_suspended=true
	while preview_request_in_flight:await get_tree().process_frame
	var error:StringName=await super.restore_gpu_checkpoint_data(checkpoint)
	preview_suspended=false;return error

func shutdown() -> void:
	ui_closing=true;_finish_ui_stroke(_scene_switch_busy())
	while ui_pump_running or preview_request_in_flight:await get_tree().process_frame
	await super.shutdown()

func _render_release() -> void:
	preview_baseline.texture_rd_rid=RID()
	if preview_query!=null:preview_query.release();preview_query=null
	super._render_release()
