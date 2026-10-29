extends SceneTree
var output:=""
var checks: Array=[]
func _initialize() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--scan-output="):output=arg.trim_prefix("--scan-output=")
 call_deferred("run")
func run() -> void:
 var input: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("input.json")))
 for path in input.resources:
  print("SCAN_BEGIN ",path)
  var value=load(path)
  var row:={"path":path,"loaded":value!=null}
  if value is PackedScene:
   var first=value.instantiate();var second=value.instantiate()
   row.instances_valid=first!=null and second!=null
   if first!=null:first.free()
   if second!=null:second.free()
  checks.append(row)
 if input.live:
  for path in ["res://scenes/main.tscn","res://scenes/playable/test1_geometry.tscn"]:
   for cycle in 2:
    print("LIVE_BEGIN ",path," cycle=",cycle)
    var beach=load(path).instantiate();root.add_child(beach);current_scene=beach
    var deadline: int=Time.get_ticks_msec()+90000
    while not beach.ready_for_ticks and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
    var ready: bool=beach.ready_for_ticks
    var start: int=beach.runtime.current.completed_tick if ready else -1
    while ready and beach.runtime.current.completed_tick<start+10 and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
    var advanced: bool=ready and beach.runtime.current.completed_tick>=start+10
    var last_error: String=beach.last_error
    await beach.shutdown();beach.queue_free();await process_frame
    checks.append({"path":path,"cycle":cycle,"live":true,"ready":ready,"advanced":advanced,"error":last_error})
 print("SCAN_DONE")
 FileAccess.open(output.path_join("runtime.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"user_data_dir":OS.get_user_data_dir(),"engine":Engine.get_version_info()},"\t"))
 quit()
