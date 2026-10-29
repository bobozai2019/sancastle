extends SceneTree

const Numerics=preload("res://scripts/simulation/unified_edit/water_numerics.gd")

class FakeBeach extends Node:
	var scene_key:="main"
	var closing:=false
	var _saving:=false
	var _restoring:=false
	var _booting:=false
	var ready_for_ticks:=true
	var selected_sand_tool:=&"remove_sand"
	var water_solver_id:=""
	var wave_retention:=0.0
	var muscl_cfl:=0.2
	var muscl_max_attempts:=64

var output:="res://test_output/parameter_save_text"
var checks: Array=[]
var observations: Array=[]
var restart_only:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--restart-only":restart_only=true
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed});print("SAVE_TEXT ",label," ",passed)

func run() -> void:
	var service=root.get_node("Parameters")
	print("SPINBOX_APPLY ",ClassDB.class_has_method("SpinBox","apply"))
	var actual: Dictionary=service.read_file("user://parameters/startup.json")
	print("ACTUAL_CONFIG_LOAD ",actual.error)
	for key in actual.get("scenes",{}):
		var values: Dictionary=actual.scenes[key]
		print("ACTUAL_CONFIG ",key," cfl=",values.get("muscl_cfl")," attempts=",values.get("muscl_max_attempts")," solver=",values.get("solver"))
	var beach:=FakeBeach.new();root.add_child(beach)
	if restart_only:
		check("new_process_load",service.boot_values("main").get("muscl_cfl")==0.31 and service.boot_values("main").get("muscl_max_attempts")==32)
		check("prepare_boot",service.prepare_boot(beach,{},{},{}).is_empty())
		var numerical:=Numerics.selection(beach.water_solver_id,beach.wave_retention,beach.muscl_cfl,beach.muscl_max_attempts)
		check("typed_values_reach_numerics",numerical.schema==3 and numerical.cfl==0.31 and numerical.max_attempts==32 and Numerics.configuration_error({"water_numerics":numerical}).is_empty())
		beach.queue_free();finish();return
	service.scene=beach
	service.effective={"muscl_cfl":0.2,"muscl_max_attempts":64,"solver":1,"erosion_rate_per_s":0.7295628483661365}
	service.editing=service.effective.duplicate();service.defaults=service.effective.duplicate()
	service.available={"muscl_cfl":true,"muscl_max_attempts":true,"solver":true,"erosion_rate_per_s":true}
	service.changed.emit();service.open_window("water")
	for frame in 4:await process_frame
	var button: Button=service.get_node("water/Margin/Rows/Actions/Save")
	for spec in [["muscl_cfl","0.31",0.31],["muscl_max_attempts","32",32]]:
		var spin: SpinBox=service.get_node("water/Margin/Rows/Scroll/Fields/"+spec[0]+"/Line/Value")
		spin.get_line_edit().grab_focus()
		for frame in 2:await process_frame
		spin.get_line_edit().text=spec[1]
		var before:={"text":spin.get_line_edit().text,"value":spin.value,"editing":service.editing[spec[0]]}
		button.pressed.emit();await process_frame
		var saved: Dictionary=service.read_file(service._file_path)
		var written: Variant=saved.get("scenes",{}).get("main",{}).get(spec[0])
		observations.append({"id":spec[0],"before":before,"written":written,"message":service.message})
		check("typed_save_"+spec[0],written==spec[2])
		check("untouched_precision_"+spec[0],saved.scenes.main.erosion_rate_per_s==0.7295628483661365)
		check("restart_still_pending_"+spec[0],service.effective[spec[0]]!=spec[2])
	# Invalid cross-field input must not be reported as a successful save.
	service.effective.merge({"wall_top":0.5,"wall_bottom":1.0})
	service.editing.merge({"wall_top":0.5,"wall_bottom":1.0})
	service.defaults.merge({"wall_top":0.5,"wall_bottom":1.0})
	service.available.merge({"wall_top":true,"wall_bottom":true})
	service.changed.emit()
	var bytes_before:=FileAccess.get_file_as_bytes(service._file_path)
	var top: SpinBox=service.get_node("tools/Margin/Rows/Scroll/Fields/wall_top/Line/Value")
	top.get_line_edit().text="2.0"
	button.pressed.emit()
	check("invalid_input_blocks_save",service.message.begins_with("保存失败") and FileAccess.get_file_as_bytes(service._file_path)==bytes_before)
	service.scene=null;beach.queue_free()
	finish()

func finish() -> void:
	var passed:=checks.all(func(row):return row.pass)
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks,"observations":observations},"\t"))
	quit(0 if passed else 1)
