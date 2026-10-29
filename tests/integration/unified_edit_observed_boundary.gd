extends "res://scripts/simulation/unified_edit/water.gd"

# Probe-only ordered async snapshots, before/after the existing boundary kernel.
# Recording continues without waiting for any callback or CPU authorization.
var stages: Dictionary={}
var pending:=0
var serial:=0
var last_packets: Array=[]
var registration_errors:=0

func configure_boundary(parameters: Vector3, packets: Array) -> bool:
	var ok:=super.configure_boundary(parameters,packets)
	if ok:last_packets=packets.duplicate()
	return ok

func _dispatch(name: String, binding: RID, push: PackedByteArray, step: int=-1) -> void:
	if name!="boundary":super._dispatch(name,binding,push,step);return
	serial+=1;var id:=serial
	call_deferred("_stage_started",id,push.duplicate(),last_packets.duplicate())
	_capture(id,"before")
	super._dispatch(name,binding,push,step)
	_capture(id,"after")

func _capture(id: int, phase: String) -> void:
	for field in ["water","momentum_x","momentum_z","rock","sand"]:
		var image: RID=solver.textures[field] if field=="rock" else solver.textures[field][0]
		if rd.texture_get_data_async(image,0,_arrived.bind(id,phase+"/"+field))!=OK:call_deferred("_registration_failed")
	if rd.buffer_get_data_async(solver.async_transport.control,_arrived.bind(id,phase+"/control"),0,128)!=OK:call_deferred("_registration_failed")

func _stage_started(id: int, push: PackedByteArray, packets: Array) -> void:
	stages[id]={"push":push,"packets":packets,"fields":{}};pending+=12

func _arrived(bytes: PackedByteArray, id: int, field: String) -> void:call_deferred("_received",bytes,id,field)
func _received(bytes: PackedByteArray, id: int, field: String) -> void:
	stages[id].fields[field]=bytes;pending-=1
func _registration_failed() -> void:registration_errors+=1;pending-=1
