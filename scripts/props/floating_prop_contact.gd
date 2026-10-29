extends RefCounted

const CONTACT_TOLERANCE_M=0.005
const MAX_EDIT_CORRECTION_M=2.0
const QUERY_MARGIN_M=0.001

static func enclosing_radius(body: RigidBody3D) -> Dictionary:
	var radius:=0.0;var count:=0
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled:continue
		var transform: Transform3D=child.transform;var shape: Shape3D=child.shape
		if transform.basis.get_scale().distance_to(Vector3.ONE)>1e-5:return {"error":&"unsupported_collider_scale"}
		if shape is BoxShape3D:
			for x in [-1,1]:
				for y in [-1,1]:
					for z in [-1,1]:radius=maxf(radius,(transform*(shape.size*Vector3(x,y,z)*0.5)).length())
		elif shape is CapsuleShape3D:
			var half:=maxf(0.0,shape.height*0.5-shape.radius)
			radius=maxf(radius,maxf((transform.origin+transform.basis.y*half).length(),(transform.origin-transform.basis.y*half).length())+shape.radius)
		elif shape is SphereShape3D:radius=maxf(radius,transform.origin.length()+shape.radius)
		else:return {"error":&"unsupported_collider"}
		count+=1
	return {"error":&"" if count>0 else &"invalid_collider","radius_m":radius}

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
	if own.aabb.position.y>top+QUERY_MARGIN_M:return {"error":&"","delta_y":0.0,"needed_delta_m":0.0}
	var bottom_offset: float=body.global_position.y-own.aabb.position.y
	var start:=body.global_transform
	start.origin.y=maxf(start.origin.y,top+bottom_offset+0.02)
	var span:=start.origin.y-body.global_position.y
	if span<=CONTACT_TOLERANCE_M:return {"error":&"","delta_y":0.0,"needed_delta_m":0.0}
	if span>MAX_EDIT_CORRECTION_M+0.02:return {"error":&"edit_correction_limit","requested_span_m":span}
	# Sweep from a proven upper bound toward the existing pose. This also finds
	# a terrain surface that has been filled entirely above the old body.
	var parameters:=PhysicsTestMotionParameters3D.new();parameters.from=start;parameters.motion=Vector3.DOWN*span;parameters.margin=QUERY_MARGIN_M;parameters.max_collisions=8;parameters.recovery_as_collision=true
	# Other props are obstacles to an upward correction, never evidence that
	# terrain has risen. A sweep from above otherwise mistakes a floating prop
	# for the bed and creates an unbounded leapfrog between neighbouring bodies.
	var excluded: Array[RID]=[]
	for row in rows:
		if row.body!=body:excluded.append(row.body.get_rid())
	parameters.exclude_bodies=excluded
	var result:=PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(),parameters,result):return {"error":&"","delta_y":0.0,"needed_delta_m":0.0}
	var travel:=result.get_travel()
	if absf(travel.x)>CONTACT_TOLERANCE_M or absf(travel.z)>CONTACT_TOLERANCE_M:return {"error":&"nonvertical_edit_recovery"}
	var target: float=start.origin.y+travel.y;var delta:=target-body.global_position.y
	if delta<=CONTACT_TOLERANCE_M:return {"error":&"","delta_y":0.0,"needed_delta_m":maxf(0.0,delta)}
	if delta>MAX_EDIT_CORRECTION_M:return {"error":&"edit_correction_limit","requested_span_m":delta}
	return {"error":&"","delta_y":delta,"needed_delta_m":delta,"target_y":target,"bed_max_m":bed.maximum_m,"query_span_m":span,"query_travel":travel,"vertices":bed.vertices}

static func recovery_plan(rows: Array, eligible: Dictionary, heights, versions: Dictionary, epoch: int) -> Dictionary:
	var plan:={};var completed: Array=[];var queue: Array=[];var by_rid:={};var by_id:={}
	for row in rows:by_rid[row.body.get_rid()]=row.body_id;by_id[row.body_id]=row
	for row in rows:
		if not eligible.has(row.body_id):continue
		var projection:=project_above_support(row.body,rows,heights,versions,epoch)
		if not projection.error.is_empty():return {"error":projection.error,"detail":projection}
		completed.append(row.body_id)
		if projection.delta_y<=0.0:continue
		plan[row.body_id]={"delta_y":projection.delta_y,"reason":&"terrain","query":projection};queue.append(row.body_id)
	var terrain: RID=heights.proxy.get_node("Terrain").get_rid();var cursor:=0
	while cursor<queue.size():
		var id: int=queue[cursor];cursor+=1
		var body: RigidBody3D=by_id[id].body;var delta: float=plan[id].delta_y
		# At most three bodies and three distinct terrain displacements. Propagate
		# an actual upward obstruction, keeping a stack's relative separation.
		for attempt in rows.size()+1:
			var excluded: Array[RID]=[terrain]
			for other in rows:
				if other.body_id==id or float(plan.get(other.body_id,{}).get("delta_y",0.0))>=delta:excluded.append(other.body.get_rid())
			var parameters:=PhysicsTestMotionParameters3D.new();parameters.from=body.global_transform;parameters.motion=Vector3.UP*delta;parameters.margin=QUERY_MARGIN_M;parameters.max_collisions=8;parameters.recovery_as_collision=true;parameters.exclude_bodies=excluded
			var hit:=PhysicsTestMotionResult3D.new()
			if not PhysicsServer3D.body_test_motion(body.get_rid(),parameters,hit):break
			var expanded:=false
			for index in hit.get_collision_count():
				var rid: RID=hit.get_collider_rid(index)
				if not by_rid.has(rid):return {"error":&"unsupported_support_obstacle"}
				var other_id: int=by_rid[rid]
				if other_id==id or float(plan.get(other_id,{}).get("delta_y",0.0))>=delta:continue
				plan[other_id]={"delta_y":delta,"reason":&"stack_push","pushed_by":id};queue.append(other_id);expanded=true
			if not expanded:return {"error":&"edit_recovery_obstructed"}
		if cursor>rows.size()*rows.size():return {"error":&"edit_recovery_cycle"}
	return {"error":&"","corrections":plan,"completed":completed}
