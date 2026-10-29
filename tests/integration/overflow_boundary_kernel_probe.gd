extends SceneTree
# Private fixed-input shader checks; does not mutate any running scene owner.
const Boundary=preload("res://scripts/simulation/unified_edit/boundary.gd")
var rd: RenderingDevice
var owned: Array[RID]=[]
var textures: Array[RID]=[]
var programs: Dictionary={}
var buffers: Array[RID]=[]
var checks: Array=[]
var failed:=false
var output:="res://test_output/overflow/kernel"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func own(rid: RID) -> RID:owned.append(rid);return rid
func check(label: String, value: bool) -> void:
	checks.append({"name":label,"pass":value});failed=failed or not value;print("OVERFLOW_KERNEL ",label," ",value)

func run() -> void:
	rd=RenderingServer.create_local_rendering_device()
	for index in 6:
		var format:=RDTextureFormat.new();format.width=256;format.height=256;format.format=RenderingDevice.DATA_FORMAT_R32_SFLOAT;format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		textures.append(own(rd.texture_create(format,RDTextureView.new(),[])))
	for size in [128,64,2048]:buffers.append(own(rd.storage_buffer_create(size)))
	for key in ["old","new"]:
		var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://scripts/simulation/"+("edit_validation/frame_pipeline/async_boundary.glsl" if key=="old" else "unified_edit/boundary.glsl")).trim_prefix("#[compute]")
		var spirv:=rd.shader_compile_spirv_from_source(source)
		check(key+"_compile",spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty())
		var shader:=own(rd.shader_create_from_spirv(spirv));var pipeline:=own(rd.compute_pipeline_create(shader))
		var uniforms: Array[RDUniform]=[]
		for rid in textures.slice(0,5 if key=="old" else 6)+buffers:
			var uniform:=RDUniform.new();uniform.binding=uniforms.size();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if rid in textures else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.add_id(rid);uniforms.append(uniform)
		programs[key]={"pipeline":pipeline,"set":own(rd.uniform_set_create(uniforms,shader,0))}
	var old:=execute("old",1.1,false,0,1.0,0.0)
	var disabled:=execute("new",1.1,false,0,1.0,0.0)
	check("disabled_exact_legacy",old==disabled)
	var low:=execute("new",.95,true,0,1.0,0.0)
	check("low_level_inactive",low.control.decode_u32(104)==0 and low.control.decode_u32(116)==1)
	var high:=execute("new",1.1,true,0,1.0,0.0)
	check("high_level_active",high.control.decode_u32(104)==1 and high.control.decode_u32(116)==1)
	var fresh_high:=execute("new",1.1,true,0,.1,0.0,false,true)
	check("fresh_high_state_drains_gradually",fresh_high.water.to_float32_array()[100*256]>1.08)
	var before:=execute("old",1.1,false,0,1.0,0.0)
	var baseline: PackedFloat32Array=before.water.to_float32_array()
	var h: PackedFloat32Array=high.water.to_float32_array()
	var q: PackedFloat32Array=high.qx.to_float32_array()
	var removed:=0.0;var bounded:=true;var localized:=true;var velocity:=true
	for z in 256:
		for x in 256:
			var i:=z*256+x;var delta:=baseline[i]-h[i];removed+=delta*.015625
			if x>0:
				bounded=bounded and delta>=-1e-6 and delta<=.012001
				if x>=24 or z<68 or z>=188:localized=localized and absf(delta)<1e-6
				velocity=velocity and absf(q[i]/h[i]-.2/1.1)<1e-6
	check("sink_only_right_edge_strip",localized)
	check("continuous_drop_rate_bounded",bounded and h[100*256+8]<1.1)
	check("momentum_scales_with_depth",velocity)
	check("removed_volume_matches_sink",absf(removed-high.control.decode_float(92))<.00002 and high.control.decode_float(120)>0)
	var held:=execute("new",1.01,true,1,1.0,1.5)
	check("no_resample_before_interval",held.control.decode_u32(116)==1 and held.control.decode_u32(104)==1)
	var middle_on:=execute("new",1.01,true,1,1.5,1.5)
	var middle_off:=execute("new",1.01,true,0,1.5,1.5)
	check("hysteresis_between_thresholds",middle_on.control.decode_u32(104)==1 and middle_off.control.decode_u32(104)==0)
	var stopped:=execute("new",.97,true,1,1.5,1.5)
	check("stops_below_low_threshold",stopped.control.decode_u32(104)==0)
	var floor_result:=execute("new",.905,true,1,1.0,1.5)
	check("drain_floor",floor_result.water.to_float32_array()[100*256+1]>=.9-1e-6)
	var rejected:=execute("new",1.1,true,0,1.0,0.0,true)
	check("rejected_tick_has_no_effect",rejected.control.decode_u32(116)==0 and rejected.water.to_float32_array()[100*256+1]==PackedFloat32Array([1.1])[0])
	var profile: Dictionary=Boundary.for_scene("test1_geometry").overflow.duplicate(true)
	profile.stop_level_m=profile.start_level_m
	check("reject_inverted_thresholds",Boundary.overflow_error(profile)==&"invalid_overflow_profile")
	profile=Boundary.for_scene("test1_geometry").overflow.duplicate(true);profile.strip_cells=256
	check("reject_unbounded_strip",Boundary.overflow_error(profile)==&"invalid_overflow_profile")
	for index in range(owned.size()-1,-1,-1):rd.free_rid(owned[index])
	rd.free();DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"scope":"Private fixed-input boundary kernel: legacy parity, sink volume, localization, cadence, hysteresis, floor, momentum and rejection. Not a whole-scene performance measurement."},"\t"))
	quit(1 if failed else 0)

func execute(key: String, level: float, enabled: bool, active: int, time: float, next: float, reject: bool=false, empty_outlet: bool=false) -> Dictionary:
	for index in 6:
		var values:=PackedFloat32Array();values.resize(65536)
		values.fill(level if index==2 else (.2 if index in [3,4] else 0.0))
		rd.texture_update(textures[index],0,values.to_byte_array())
	var control:=PackedByteArray();control.resize(128);control.encode_float(32,time);control.encode_float(96,0.0 if empty_outlet else level)
	if active!=0 or next>0:
		control.encode_u32(104,active);control.encode_float(108,next);control.encode_u32(116,1)
	if enabled:control.encode_float(124,time-.1)
	rd.buffer_update(buffers[0],0,128,control)
	var decision:=PackedByteArray();decision.resize(64);decision.encode_u32(16,2 if reject else 0);rd.buffer_update(buffers[1],0,64,decision)
	var push:=PackedFloat32Array([.015625,level,0,0,0,0,0,20]).to_byte_array();push.encode_u32(20,3)
	if key=="new":
		push.resize(64);push.encode_u32(32,1 if enabled else 0);push.encode_float(36,.5);push.encode_float(40,1.04);push.encode_float(44,.98);push.encode_float(48,.12);push.encode_float(52,.9);push.encode_u32(56,24)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,programs[key].pipeline);rd.compute_list_bind_uniform_set(list,programs[key].set,0);rd.compute_list_set_push_constant(list,push,push.size());rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end();rd.submit();rd.sync()
	return {"water":rd.texture_get_data(textures[2],0),"qx":rd.texture_get_data(textures[3],0),"qz":rd.texture_get_data(textures[4],0),"control":rd.buffer_get_data(buffers[0])}
