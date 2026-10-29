extends SceneTree
const Store = preload("res://scripts/simulation/checkpoint_store.gd")
var output := ""
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")
func _run() -> void:
	var rows:=[]
	var passed:=true
	for stage in ["preparing","prepared","submitted"]:
		var folder: String="res://test_output/physics_threading/t03_edit_explicit_windows/edit_"+stage+"_save"
		var initial: Dictionary=Store.load(folder.path_join("origin.scgpu")).checkpoint
		var saved: Dictionary=Store.load(folder.path_join("saved.scgpu")).checkpoint
		# Command positions came from actual current Jolt ray picks, before GPU editing.
		var point: Vector3=saved.gpu_beach_edit.prefix[0].command.transform.position_m
		var fx: float=(point.x+16.0)/0.125-0.5
		var fz: float=(point.z+16.0)/0.125-0.5
		var x:=clampi(int(floor(fx)),0,254);var z:=clampi(int(floor(fz)),0,254)
		var fields: Dictionary=initial.gpu_beach_native.fields
		var water: float=fields.water.decode_float((z*256+x)*4)
		var heights:=[]
		for index in [z*256+x,z*256+x+1,(z+1)*256+x,(z+1)*256+x+1]:
			heights.append(fields.rock.decode_float(index*4)+fields.sand.decode_float(index*4))
		var low: float=heights.min();var high: float=heights.max()
		var ok:=water>0.001 and point.y>=low-0.00001 and point.y<=high+0.00001
		passed=passed and ok
		rows.append({"stage":stage,"pass":ok,"initial_checkpoint_sha256":FileAccess.get_sha256(folder.path_join("origin.scgpu")),
			"saved_checkpoint_sha256":FileAccess.get_sha256(folder.path_join("saved.scgpu")),"picked_position":point,
			"cell":Vector2i(x,z),"authoritative_water_depth_m":water,"bed_corner_range_m":[low,high]})
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":passed,"rows":rows,"scope":"offline original ten-field checkpoint vs recorded real Jolt-picked command positions; not new rendering or performance"},"\t"));file.close()
	print("UNDERWATER_PICK_EVIDENCE ",passed)
	quit(0 if passed else 1)
