extends PanelContainer

signal mode_changed

const NAMES={1:"水瓶",2:"木板",3:"木棍"}
var selected_body_id:=0
var pickup_mode:=false
var yaw_rad:=0.0
var working:=false
var message:="选择道具后点击水面或沙地摆放"
var last_result: Dictionary={}
var _status_elapsed:=0.0
var _observed_water_level:=NAN
@onready var beach=get_parent().get_parent()
@onready var marker: MeshInstance3D=beach.get_node_or_null("FloatingProps/PlacementPreview")
@onready var status: Label=$Margin/Rows/Status

func _ready() -> void:
	# All beaches share this panel; beaches without prop services keep it dormant.
	if marker==null or beach.get_node_or_null("FloatingProps/Service")==null:
		hide()
		process_mode=Node.PROCESS_MODE_DISABLED

func has_world_mode() -> bool:return selected_body_id!=0 or pickup_mode

func _input(event: InputEvent) -> void:
	if has_world_mode() and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		beach.player_camera._release_mouse();cancel_mode();get_viewport().set_input_as_handled()

func select_body(id: int) -> void:
	if working or not NAMES.has(id):return
	selected_body_id=id;pickup_mode=false;yaw_rad=0.0
	message="点击水面或沙地摆放%s；[ / ]旋转"%NAMES[id]
	_sync_buttons();mode_changed.emit()

func select_pickup() -> void:
	if working:return
	selected_body_id=0;pickup_mode=true
	message="点击场景中的道具，拾取回槽位"
	_sync_buttons();mode_changed.emit()

func cancel_mode() -> void:
	selected_body_id=0;pickup_mode=false
	if marker!=null:marker.hide()
	_sync_buttons();mode_changed.emit()

func _sync_buttons() -> void:
	for id in NAMES:
		get_node("Margin/Rows/Slots/Slot%d"%id).set_pressed_no_signal(selected_body_id==id)
	$Margin/Rows/Actions/Pickup.set_pressed_no_signal(pickup_mode)

func _process(delta: float) -> void:
	_status_elapsed+=delta
	if _status_elapsed<0.1:return
	_status_elapsed=0.0
	var service=beach.floating_props
	if service!=null:
		var total:=0.0;var count:=0
		for point in service.latest_sample.get("points",[]):
			if point.h>0.001:total+=point.eta;count+=1
		if count>0:_observed_water_level=total/float(count)
	var enabled: bool=service!=null and service.active and beach.ready_for_ticks and not service.busy and not working and not beach.closing and service.last_error.is_empty()
	for id in NAMES:
		var button: Button=get_node("Margin/Rows/Slots/Slot%d"%id)
		var body=null if service==null else service.body_for_id(id)
		button.disabled=not enabled
		button.text=NAMES[id]+("\n槽位中" if body!=null and body.in_inventory else "\n已摆放")
	$Margin/Rows/Actions/Pickup.disabled=not enabled
	status.text="正在摆放 / 拾取…" if working else message
	if service!=null and not service.last_error.is_empty():status.text="道具已保持，请恢复沙场后继续"

func _physics_process(_delta: float) -> void:
	if selected_body_id==0 or working or not beach.ready_for_ticks or beach.player_camera.look_active or beach.hide_hud:
		marker.hide();return
	if beach.get_viewport().gui_get_hovered_control()!=null:marker.hide();return
	var aim:=aim_at(beach.get_viewport().get_mouse_position())
	if aim.is_empty():marker.hide();return
	marker.global_position=aim.position+Vector3.UP*0.025
	var body=beach.floating_props.body_for_id(selected_body_id)
	var radius: float=body.footprint_radius_m
	marker.scale=Vector3(radius*2.0,1.0,radius*2.0)
	var material: StandardMaterial3D=marker.material_override
	material.albedo_color=Color(0.25,0.95,0.65,0.65) if aim.error.is_empty() else Color(1,0.3,0.25,0.65)
	marker.show()

func aim_at(screen: Vector2) -> Dictionary:
	var terrain: Dictionary=beach.pick(screen)
	if terrain.is_empty() or selected_body_id==0:return {}
	var position: Vector3=terrain.position
	# Aiming intersects the latest observed water level first. The service then
	# samples the actual destination and clears both bed and water before release.
	var service=beach.floating_props
	var sum:=0.0;var count:=0
	for point in service.latest_sample.get("points",[]):
		if point.h>0.001:sum+=point.eta;count+=1
	var level: float=sum/float(count) if count>0 else _observed_water_level
	if is_finite(level) and level>position.y:
		var camera: Camera3D=beach.get_viewport().get_camera_3d()
		var intersection: Variant=Plane(Vector3.UP,level).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
		if intersection is Vector3:position=intersection
	var error: StringName=service.placement_error(selected_body_id,Vector2(position.x,position.z))
	return {"position":position,"error":error}

func pick_prop(screen: Vector2) -> int:
	var camera: Camera3D=beach.get_viewport().get_camera_3d()
	var origin:=camera.project_ray_origin(screen)
	var query:=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*100.0,2)
	var hit: Dictionary=beach.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():return 0
	var terrain: Dictionary=beach.pick(screen)
	if not terrain.is_empty() and origin.distance_to(terrain.position)+0.01<origin.distance_to(hit.position):return 0
	var body=hit.collider
	if not body is RigidBody3D or body.service!=beach.floating_props:return 0
	return body.body_id

func handle_world_input(event: InputEvent) -> bool:
	if not has_world_mode():return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:cancel_mode();beach.get_viewport().set_input_as_handled();return true
		if selected_body_id!=0 and event.keycode in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:
			yaw_rad+=deg_to_rad(-15.0 if event.keycode==KEY_BRACKETLEFT else 15.0)
			message="%s · 朝向 %d° · 点击摆放"%[NAMES[selected_body_id],roundi(rad_to_deg(yaw_rad))]
			beach.get_viewport().set_input_as_handled();return true
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:cancel_mode();beach.get_viewport().set_input_as_handled();return true
		if event.button_index==MOUSE_BUTTON_LEFT:
			beach.get_viewport().set_input_as_handled()
			if event.pressed and not working and beach.ready_for_ticks and not beach.player_camera.look_active:
				if pickup_mode:
					var id:=pick_prop(event.position)
					if id!=0:perform_action(id,Vector2.ZERO,true)
					else:message="这里没有可拾取的道具"
				else:
					var aim:=aim_at(event.position)
					if aim.is_empty():message="请点击沙滩范围内的水面或沙地"
					elif not aim.error.is_empty():_show_error(aim.error)
					else:perform_action(selected_body_id,Vector2(aim.position.x,aim.position.z),false)
			return true
	# Placement owns mouse motion too; it must never start/update a sand gesture.
	if event is InputEventMouseMotion:return true
	return false

func perform_action(id: int, point: Vector2, pickup: bool) -> Dictionary:
	if working:return {"error":&"busy"}
	if not beach.ready_for_ticks or beach.closing or beach._saving or beach._restoring or beach._booting:return {"error":&"transition_busy"}
	working=true;marker.hide()
	last_result=await beach.floating_props.manipulate_body(id,point,yaw_rad,pickup)
	working=false
	if last_result.error.is_empty():
		message="%s已拾取，可从槽位重新投放"%NAMES[id] if pickup else "%s已摆放，可继续选择位置移动"%NAMES[id]
	else:_show_error(last_result.error)
	return last_result

func _show_error(error: StringName) -> void:
	var messages={&"occupied":"离其他道具太近，请换一个位置",&"out_of_domain":"请在沙滩范围内摆放",&"busy":"请等待当前操作完成",&"already_picked_up":"道具已在槽位中"}
	message=messages.get(error,"暂时无法操作："+String(error))
