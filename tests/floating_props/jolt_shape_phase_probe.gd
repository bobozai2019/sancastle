extends SceneTree

var fixture
var output:=""
var frame:=0
var assigned_frame:=-1
var query_hit:=false
var query_travel_y:=0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_start")

func _start() -> void:
	fixture=load("res://tests/floating_props/jolt_shape_phase_fixture.tscn").instantiate();root.add_child(fixture)

func _physics_process(_delta: float) -> bool:
	if fixture==null:return false
	frame+=1
	if frame==10:
		var shape:=HeightMapShape3D.new();shape.map_width=2;shape.map_depth=2;shape.map_data=PackedFloat32Array([0,0,0,0])
		fixture.get_node("Floor/Shape").shape=shape
		assigned_frame=Engine.get_physics_frames()
		fixture.get_node("Body").freeze=false;fixture.get_node("Body").linear_velocity=Vector3(0,-1,0)
		var query:=PhysicsTestMotionParameters3D.new();query.from=Transform3D(Basis.IDENTITY,Vector3(0,0.5,0));query.motion=Vector3(0,-0.6,0)
		var hit:=PhysicsTestMotionResult3D.new();query_hit=PhysicsServer3D.body_test_motion(fixture.get_node("Body").get_rid(),query,hit);query_travel_y=hit.get_travel().y
	if frame==15:
		var steps: Array=fixture.get_node("Body").steps
		var contact_frame:=-1
		for step in steps:
			if step.contacts>0 and contact_frame<0:contact_frame=step.frame
		# Completion callbacks are observed in the next frame, as in the service
		# grant/observe logs. The FIRST released world quantum must see new bed.
		var passed: bool=not steps.is_empty() and steps[0].frame==assigned_frame+1 and steps[0].contacts>0 and steps[0].y>=0.098 and query_hit and absf(query_travel_y+0.4)<0.005
		var result:={"pass":passed,"engine":Engine.get_version_info(),"assigned_frame":assigned_frame,"first_contact_frame":contact_frame,"immediate_query_hit":query_hit,"immediate_query_travel_y":query_travel_y,"steps":steps,"checks":[{"name":"first_released_quantum_uses_replaced_height","pass":passed}],"scope":"Native HeightMap replacement before Jolt step, old bed -1m and new bed 0m; body released at new surface with downward velocity. Callback frame is grant frame+1. Immediate motion query must also see new bed. Independent phase mechanism, no GPU proof."}
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("JOLT_SHAPE_PHASE ",passed," assigned ",assigned_frame," contact ",contact_frame)
		root.remove_child(fixture);fixture.free();fixture=null;quit(0 if passed else 1)
	return false
