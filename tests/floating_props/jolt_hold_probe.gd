extends SceneTree

# Mechanism experiment only; final G2 must combine the public GPU clock/sample.
var fixture
var body
var output:=""
var checks: Array=[]
var observations: Array=[]
var failed:=false
var produced:=0.0
var reserved:=0.0
var frame:=0
var active:=false
var saved_linear:=Vector3.ZERO
var saved_angular:=Vector3.ZERO

func check(name: String, value: bool) -> void:checks.append({"name":name,"pass":value});failed=failed or not value;print("JOLT_HOLD ",name," ",value)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_start")

func _start() -> void:
	fixture=load("res://tests/floating_props/jolt_hold_fixture.tscn").instantiate();root.add_child(fixture);body=fixture.get_node("Body");active=true

func _physics_process(delta: float) -> bool:
	if not active:return false
	frame+=1
	if frame in [10,25,40]:produced+=0.025
	var allowed:=reserved+delta<=produced+1e-9
	if allowed:
		if body.freeze:
			body.freeze=false;body.linear_velocity=saved_linear;body.angular_velocity=saved_angular;body.sleeping=false
		reserved+=delta
	elif not body.freeze:
		saved_linear=body.linear_velocity;saved_angular=body.angular_velocity;body.freeze=true
	observations.append({"frame":frame,"delta":delta,"allowed":allowed,"produced":produced,"reserved":reserved,"actual":body.total_time,"freeze":body.freeze,"position":body.position,"velocity":body.linear_velocity,"saved_velocity":saved_linear})
	if frame==9:check("initial_hold_no_gravity_or_steps",body.total_time==0.0 and body.position==Vector3(0,2,0))
	if frame==80:
		active=false
		check("four_actual_jolt_steps",body.steps.size()==4 and absf(body.total_time-4.0/60.0)<1e-7)
		check("bounded_clock_error",produced-body.total_time>=-1e-8 and produced-body.total_time<delta+1e-8 and absf(reserved-body.total_time)<1e-7)
		var gravity: float=ProjectSettings.get_setting("physics/3d/default_gravity",9.8)
		check("velocity_preserved_without_hidden_gravity",absf(saved_linear.y+gravity*body.total_time)<1e-5)
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"actual_steps":body.steps,"engine":Engine.get_version_info(),"scope":"real Jolt local freeze/gravity/step mechanism experiment; synthetic producer budget, no G2 GPU synchronization acceptance"},"\t"))
		root.remove_child(fixture);fixture.free();quit(1 if failed else 0)
	return false
