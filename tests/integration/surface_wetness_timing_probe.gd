extends SceneTree
const GPU=preload("res://scripts/simulation/unified_edit/gpu.gd")
const Wet=preload("res://scripts/simulation/unified_edit/surface_wetness.gd")
var checks: Array=[]
func check(label: String, ok: bool) -> void:
 checks.append({"name":label,"pass":ok});print("WET_TIMING ",label," ",ok)
func texture(g, value: float) -> RID:
 var f:=RDTextureFormat.new();f.width=256;f.height=256;f.format=RenderingDevice.DATA_FORMAT_R32_SFLOAT
 f.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
 var a:=PackedFloat32Array();a.resize(65536);a.fill(value)
 return g.own(g.rd.texture_create(f,RDTextureView.new(),[a.to_byte_array()]))
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var g=GPU.new();g.rd=RenderingServer.create_local_rendering_device()
 check("compile",g.compile("wet","res://scripts/simulation/unified_edit/publish_wet_sand.glsl"))
 if g.kernels.is_empty():print(g.last_error);quit(1);return
 var c:=PackedByteArray();c.resize(128)
 var control=g.own(g.rd.storage_buffer_create(128,c));var stamp=g.own(g.rd.storage_buffer_create(32))
 var history=texture(g,1.0)
 var binding=g.binding("wet",{0:control,1:stamp},{2:texture(g,1.0),3:texture(g,0.0),4:texture(g,1.0),5:texture(g,0.0),6:history})
 # Analytic points include a step crossing the full-wet threshold and zero hold.
 for row in [[18.0,12.0,18.0,0.4],[18.0,12.0,24.0,0.2],[18.0,12.0,30.0,0.0],[2.0,3.0,3.5,0.2],[0.0,3.0,1.5,0.2],[0.0,0.1,0.1,0.0],[2.0,3.0,0.0,1.0]]:
  var a:=PackedFloat32Array();a.resize(65536);a.fill(1.0);g.rd.texture_update(history,0,a.to_byte_array())
  c.encode_float(36,row[2]);g.rd.buffer_update(control,0,128,c)
  g.dispatch("wet",binding,Vector3i(1024,1,1),PackedFloat32Array([row[0],row[1],0.0,0.0]).to_byte_array());g.rd.submit();g.rd.sync()
  var actual: float=g.rd.texture_get_data(history,0).decode_float(0)
  check(str(row),absf(actual-row[3])<0.00001)
 for field in ["hold_time_s","fade_time_s"]:
  for v in [NAN,INF,-1.0,301.0]:
   var profile=Wet.PROFILE.duplicate();profile[field]=v;check("reject_"+field+str(v),not Wet.valid_profile(profile))
 var device=g.rd;g.release();device.free()
 var passed:=true
 for row in checks:passed=passed and row["pass"]
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks},"  "))
 quit(0 if passed else 1)
