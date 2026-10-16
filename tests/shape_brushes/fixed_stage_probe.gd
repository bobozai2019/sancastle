extends "res://tests/water_material_natural/rdc_main_smoke.gd"

const INPUT_ROOT: String="res://test_output/shape_brushes/20261014_121806_continuation_84a9544b/continuation"
const DELTA: float=1.0/90.0
const REPEATS: int=24
var device:RenderingDevice
var owned:Array[RID]=[]
var images:Dictionary={}
var programs:Dictionary={}
var identities:Dictionary={}
var setup_done:=false
var setup_error:=""
var records:Array=[]

func own(rid:RID) -> RID:
	if rid.is_valid():owned.append(rid)
	return rid

func texture(format_id:int,data:PackedByteArray,width:int=256) -> RID:
	var format:=RDTextureFormat.new();format.texture_type=RenderingDevice.TEXTURE_TYPE_2D
	format.width=width;format.height=width;format.format=format_id
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return own(device.texture_create(format,RDTextureView.new(),[data] if not data.is_empty() else []))

func setup() -> void:
	device=RenderingServer.get_rendering_device()
	if device==null:setup_error="RenderingDevice missing";call_deferred("setup_ready");return
	for name in ["sand","spare_sand","sediment","spare_sediment","water","spare_water","wetness","compaction","spare_wetness","spare_compaction","flux","obstacle"]:
		var path:String=INPUT_ROOT.path_join("direct_238_"+name+".bin")
		var bytes:=FileAccess.get_file_as_bytes(path)
		var format_id:int=RenderingDevice.DATA_FORMAT_R32_SFLOAT
		var stride:int=4
		if "wetness" in name or "compaction" in name:format_id=RenderingDevice.DATA_FORMAT_R16_SFLOAT;stride=2
		elif name=="flux":format_id=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT;stride=16
		elif name=="obstacle":format_id=RenderingDevice.DATA_FORMAT_R8_UNORM;stride=1
		if bytes.size()!=256*256*stride:setup_error="invalid input size: "+name;break
		images[name]=texture(format_id,bytes)
		identities[name]={"path":path,"sha256":FileAccess.get_sha256(path),"bytes":bytes.size(),"rid":images[name].get_id()}
	if setup_error.is_empty():
		for stage in ["sediment","material"]:
			var path:String="res://shaders/simulation/erosion/sediment_step.glsl" if stage=="sediment" else "res://shaders/simulation/material/material_step.glsl"
			var source:RDShaderFile=load(path)
			var spirv:RDShaderSPIRV=source.get_spirv()
			var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE))
			var program:Dictionary={"pipelines":[],"sets":[],"outputs":[],"binding_maps":[],"shader_source":path,"source_sha256":FileAccess.get_sha256(path),"spirv_sha256":hash.finish().hex_encode()}
			# Create two independent shader/pipeline objects from identical SPIR-V.
			for branch in 2:
				var shader:=own(device.shader_create_from_spirv(spirv));program.pipelines.append(own(device.compute_pipeline_create(shader)))
				var outputs:Dictionary={}
				var resources:Array[RID]=[]
				if stage=="sediment":
					outputs.sand=texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray())
					outputs.sediment=texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray())
					outputs.dirty=texture(RenderingDevice.DATA_FORMAT_R32_UINT,PackedByteArray(),8)
					resources=[images.spare_sediment,images.spare_water,images.flux,images.obstacle,images.spare_sand,images.spare_wetness,images.spare_compaction,images.water,outputs.sand,outputs.sediment,outputs.dirty]
				else:
					outputs.wetness=texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT,PackedByteArray())
					outputs.compaction=texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT,PackedByteArray())
					resources=[images.wetness,images.compaction,images.water,images.sand,images.obstacle,outputs.wetness,outputs.compaction]
				var uniforms:Array[RDUniform]=[];var map:Array=[]
				for binding in resources.size():
					var uniform:=RDUniform.new();uniform.binding=binding;uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;uniform.add_id(resources[binding]);uniforms.append(uniform)
					map.append(resources[binding].get_id())
				program.sets.append(own(device.uniform_set_create(uniforms,shader,0)));program.outputs.append(outputs);program.binding_maps.append(map)
			programs[stage]=program
	for rid in owned:
		if not rid.is_valid():setup_error="resource create failed"
	call_deferred("setup_ready")

func setup_ready() -> void:setup_done=true

func dispatch(stage:String,iteration:int) -> void:
	var program:Dictionary=programs[stage]
	var push:PackedByteArray=PackedFloat32Array([DELTA,0.015625,0.08,0.35,0.45,0.001,0,0]).to_byte_array() if stage=="sediment" else PackedFloat32Array([DELTA,1.5,0.07,4,0.05,0.06,0.001,0.05]).to_byte_array()
	for branch in 2:
		var list:=device.compute_list_begin();device.compute_list_bind_compute_pipeline(list,program.pipelines[branch]);device.compute_list_bind_uniform_set(list,program.sets[branch],0)
		device.compute_list_set_push_constant(list,push,32);device.compute_list_dispatch(list,32,32,1);device.compute_list_end()
		for field in program.outputs[branch]:
			if field!="dirty":device.texture_get_data_async(program.outputs[branch][field],0,_record.bind(stage+"_"+str(branch)+"_"+field))

func read_inputs() -> void:
	for name in images:device.texture_get_data_async(images[name],0,_record.bind(name))

func release() -> void:
	for index in range(owned.size()-1,-1,-1):device.free_rid(owned[index])
	owned.clear();images.clear();call_deferred("released")

func released() -> void:setup_done=true

func _run() -> void:
	root.size=Vector2i(1280,720)
	RenderingServer.call_on_render_thread(setup)
	while not setup_done:await process_frame
	_check("fixed_stage_setup",setup_error.is_empty(),setup_error)
	var baseline:Dictionary={}
	if setup_error.is_empty():
		for stage in ["sediment","material"]:
			for iteration in REPEATS:
				readbacks.clear();RenderingServer.call_on_render_thread(dispatch.bind(stage,iteration))
				var deadline:=Time.get_ticks_msec()+30000
				while readbacks.size()<4 and Time.get_ticks_msec()<deadline:await process_frame
				_check(stage+"_readbacks_"+str(iteration),readbacks.size()==4)
				var record:Dictionary={"stage":stage,"iteration":iteration,"outputs":{}}
				for field in readbacks:
					var bytes:PackedByteArray=readbacks[field]
					var canonical:String=field.replace(stage+"_1_",stage+"_0_")
					if not baseline.has(canonical):
						baseline[canonical]=bytes
						var file:=FileAccess.open(output.path_join(canonical+".bin"),FileAccess.WRITE);file.store_buffer(bytes);file.close()
					_check(field+"_repeat_"+str(iteration),bytes==baseline[canonical])
					var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
					record.outputs[field]={"bytes":bytes.size(),"sha256":hash.finish().hex_encode()}
				records.append(record)
		readbacks.clear();RenderingServer.call_on_render_thread(read_inputs)
		var deadline:=Time.get_ticks_msec()+30000
		while readbacks.size()<images.size() and Time.get_ticks_msec()<deadline:await process_frame
		for name in identities:_check(name+"_immutable",readbacks.has(name) and readbacks[name]==FileAccess.get_file_as_bytes(identities[name].path))
	var metadata:Dictionary={}
	for stage in programs:
		var program:Dictionary=programs[stage];metadata[stage]={"shader_source":program.shader_source,"source_sha256":program.source_sha256,"spirv_sha256":program.spirv_sha256,"binding_maps":program.binding_maps}
	var file:=FileAccess.open(output.path_join("fixed_stage.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"inputs":identities,"programs":metadata,"delta_s":DELTA,"iterations":REPEATS,"records":records,"adapter":RenderingServer.get_video_adapter_name(),"api":RenderingServer.get_video_adapter_api_version(),"scope":"Completed tick238 fixture bytes with explicitly fixed 1/90 delta; two independent pipelines, no input feedback, original imported shaders. Not reconstruction of the first divergent stage, not ordinary/continuation gate or performance acceptance"},"\t"));file.close()
	setup_done=false;RenderingServer.call_on_render_thread(release)
	while not setup_done:await process_frame
	_check("fixed_stage_release",owned.is_empty());_finish()
	var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)
