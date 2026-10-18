extends RefCounted

const CONTACT_TOLERANCE_M=0.005
const MAX_EDIT_CORRECTION_M=2.0
const QUERY_MARGIN_M=0.001

static func bounds(body: RigidBody3D) -> Dictionary:
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF);var count:=0
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled:continue
		var shape: Shape3D=child.shape;var transform: Transform3D=child.global_transform
		if transform.basis.get_scale().distance_to(Vector3.ONE)>1e-5:return {"error":&"unsupported_collider_scale"}
		var extent: Vector3
		if shape is BoxShape3D:
			var half: Vector3=shape.size*0.5
			extent=transform.basis.x.abs()*half.x+transform.basis.y.abs()*half.y+transform.basis.z.abs()*half.z
		elif shape is CapsuleShape3D:extent=Vector3.ONE*shape.radius+transform.basis.y.abs()*maxf(0.0,shape.height*0.5-shape.radius)
		elif shape is SphereShape3D:extent=Vector3.ONE*shape.radius
		else:return {"error":&"unsupported_collider"}
		low=low.min(transform.origin-extent);high=high.max(transform.origin+extent);count+=1
	return {"error":&"" if count>0 else &"invalid_collider","aabb":AABB(low,high-low)}

static func rect(box: AABB) -> Rect2:
	return Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).grow(QUERY_MARGIN_M)

static func project_above_support(body: RigidBody3D, rows: Array, heights, versions: Dictionary, epoch: int) -> Dictionary:
	var own:=bounds(body)
	if not own.error.is_empty():return own
	var footprint:=rect(own.aabb);var bed: Dictionary=heights.maximum_bed(footprint,versions,epoch)
	if not bed.error.is_empty():return bed
	var top: float=bed.maximum_m
	for row in rows:
		if row.body==body:continue
		var other:=bounds(row.body)
		if not other.error.is_empty():return other
		if footprint.intersects(rect(other.aabb)):top=maxf(top,other.aabb.end.y)
	var bottom_offset: float=body.global_position.y-own.aabb.position.y
	var start:=body.global_transform
	start.origin.y=maxf(start.origin.y,top+bottom_offset+0.02)
	var span:=start.origin.y-body.global_position.y
	if span<=CONTACT_TOLERANCE_M:return {"error":&"","delta_y":0.0}
	if span>MAX_EDIT_CORRECTION_M+0.02:return {"error":&"edit_correction_limit","requested_span_m":span}
	# Sweep from a proven upper bound toward the existing pose. This also finds
	# a terrain surface that has been filled entirely above the old body.
	var parameters:=PhysicsTestMotionParameters3D.new();parameters.from=start;parameters.motion=Vector3.DOWN*span;parameters.margin=QUERY_MARGIN_M;parameters.max_collisions=8;parameters.recovery_as_collision=true
	var result:=PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(),parameters,result):return {"error":&"","delta_y":0.0}
	var travel:=result.get_travel()
	if absf(travel.x)>CONTACT_TOLERANCE_M or absf(travel.z)>CONTACT_TOLERANCE_M:return {"error":&"nonvertical_edit_recovery"}
	var target: float=start.origin.y+travel.y;var delta:=target-body.global_position.y
	if delta<=CONTACT_TOLERANCE_M:return {"error":&"","delta_y":0.0}
	if delta>MAX_EDIT_CORRECTION_M:return {"error":&"edit_correction_limit","requested_span_m":delta}
	return {"error":&"","delta_y":delta,"target_y":target,"bed_max_m":bed.maximum_m,"query_span_m":span,"query_travel":travel,"vertices":bed.vertices}
