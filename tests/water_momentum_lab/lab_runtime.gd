extends RefCounted
## Owned by the lab only. Every method is render-thread-only.
var rd: RenderingDevice
var n := 256
var index := 0
var tex := {}
var shaders := {}
var pipes := {}
var sets := {}
var owned: Array[RID] = []
var step_buffer: RID
var result_buffer: RID
var tile_buffer: RID
var serial := 0
var timestamp_frame := -1
var profile_detail := false
var identity := ""

func initialize(device: RenderingDevice, size: int, fixture: String) -> void:
	rd = device
	n = size
	var zero := PackedFloat32Array()
	zero.resize(n*n)
	var bed := zero.duplicate()
	var h := zero.duplicate()
	var obstacle := PackedByteArray()
	obstacle.resize(n*n)
	for z in n:
		for x in n:
			var i := z*n+x
			var p := (Vector2(x,z)+Vector2(.5,.5)-Vector2.ONE*n*.5)*.125
			bed[i] = .5
			h[i] = .3
			match fixture:
				"thin": h[i] = .0005 if p.x<0 else .006
				"islands":
					bed[i] = .85 if sin(p.x*1.7)*cos(p.y*1.7)>.1 else .5
					h[i] = maxf(0.,.8-bed[i])
				"platform20", "platform80":
					if absf(p.x)<1.5 and absf(p.y)<1.5:bed[i]+=.2 if fixture=="platform20" else .8
				"wall":
					if x==n/2:obstacle[i]=255
				"wave": h[i] += .04*exp(-pow((p.x+float(n)*.125*.3)/.5,2.))
	for name in ["rock","bed","sediment","drain"]:
		tex[name] = _texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, bed.to_byte_array() if name=="bed" else zero.to_byte_array())
	tex.obstacle = _texture(RenderingDevice.DATA_FORMAT_R8_UNORM,obstacle)
	for name in ["h","qx","qz"]:
		tex[name]=[]
		for i in 2:tex[name].append(_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,h.to_byte_array() if name=="h" else zero.to_byte_array()))
	var rgba := PackedByteArray()
	rgba.resize(n*n*16)
	for name in ["edge_x","edge_z","flux","coverage","edits","display"]:
		tex[name]=_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,rgba)
	step_buffer = _buffer(16)
	result_buffer = _buffer(128)
	tile_buffer = _buffer((n/8)*(n/8)*80)
	var paths := {"edge":"reference/shallow_edge_flux.glsl","drain":"shaders/shallow_drain_scale.glsl","update":"shaders/shallow_update_state.glsl"}
	for name in ["edit","audit","reduce","publish"]:paths[name]="shaders/"+name+".glsl"
	for name in paths:
		var file: RDShaderFile = load("res://tests/water_momentum_lab/"+paths[name])
		var shader := rd.shader_create_from_spirv(file.get_spirv())
		shaders[name]=shader
		owned.append(shader)
		pipes[name]=rd.compute_pipeline_create(shader)
		owned.append(pipes[name])
	for i in 2:
		var hq: Array = [tex.h[i],tex.qx[i],tex.qz[i]]
		_make_set("edit",i,[tex.bed]+hq+[tex.coverage,tex.edits])
		_make_set("audit",i,[tex.bed]+hq+[tex.edits,tile_buffer],[5])
		_make_set("publish",i,[tex.bed]+hq+[tex.display,result_buffer],[5])
		_make_set("edge",i,[tex.rock,tex.bed]+hq+[tex.obstacle,tex.edge_x,tex.edge_z])
		_make_set("drain",i,[tex.h[i],tex.edge_x,tex.edge_z,tex.drain,step_buffer],[15],[0,1,2,3,15])
		_make_set("update",i,[tex.rock,tex.bed]+hq+[tex.obstacle,tex.edge_x,tex.edge_z,tex.drain,tex.h[1-i],tex.qx[1-i],tex.qz[1-i],tex.flux,step_buffer],[15],[0,1,2,3,4,5,6,7,8,9,10,11,12,15])
	_make_set("reduce",0,[tile_buffer,result_buffer,step_buffer],[0,1,2])
	audit(false)
	_dispatch("publish",index)

func _texture(format: int, bytes: PackedByteArray) -> RID:
	var f := RDTextureFormat.new()
	f.width=n
	f.height=n
	f.format=format
	f.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var rid := rd.texture_create(f,RDTextureView.new(),[bytes])
	owned.append(rid)
	return rid

func _buffer(bytes: int) -> RID:
	var data := PackedByteArray()
	data.resize(bytes)
	var rid := rd.storage_buffer_create(bytes,data)
	owned.append(rid)
	return rid

func _make_set(name: String, i: int, resources: Array, buffers: Array=[], bindings: Array=[]) -> void:
	var uniforms: Array[RDUniform]=[]
	for j in resources.size():
		var u := RDUniform.new()
		u.binding=bindings[j] if not bindings.is_empty() else j
		u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER if u.binding in buffers else RenderingDevice.UNIFORM_TYPE_IMAGE
		u.add_id(resources[j])
		uniforms.append(u)
	var rid := rd.uniform_set_create(uniforms,shaders[name],0)
	sets[name+str(i)]=rid
	owned.append(rid)

func _dispatch(name: String, i: int, push: PackedByteArray=PackedByteArray()) -> void:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipes[name])
	rd.compute_list_bind_uniform_set(list,sets[name+str(i)],0)
	if not push.is_empty():rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch(list,1 if name=="reduce" else n/8,1 if name=="reduce" else n/8,1)
	rd.compute_list_end()

func audit(advance: bool) -> void:
	_dispatch("audit",index)
	_dispatch("reduce",0,PackedInt32Array([(n/8)*(n/8),int(advance),0,0]).to_byte_array())

func job(command: Dictionary, steps: int, callback: Callable, full: bool=false) -> void:
	serial+=1
	var start := Time.get_ticks_usec()
	var times := []
	var frame := rd.get_captured_timestamps_frame()
	if frame!=timestamp_frame:
		timestamp_frame=frame
		for k in rd.get_captured_timestamps_count():
			var name := rd.get_captured_timestamp_name(k)
			if name.begins_with("lab_"):times.append({"frame":frame,"name":name,"gpu_ns":rd.get_captured_timestamp_gpu_time(k),"cpu_us":rd.get_captured_timestamp_cpu_time(k)})
	var tag := "lab_"+identity+"j"+str(serial)+"_"
	rd.capture_timestamp(tag+"edit_start")
	if not command.is_empty():
		var a: Vector2=command.a
		var b: Vector2=command.b
		var push := PackedFloat32Array([a.x,a.y,b.x,b.y,command.radius,command.depth,command.gain,float(command.mode)]).to_byte_array()
		push.append_array(PackedInt32Array([n,int(command.first),command.operation,0]).to_byte_array())
		var origin: Vector2=command.origin_xz
		push.append_array(PackedFloat32Array([origin.x,origin.y,0.,0.]).to_byte_array())
		_dispatch("edit",index,push)
	else:
		# Clear transient accounting without touching physical state.
		rd.texture_clear(tex.edits,Color(0,0,0,0),0,1,0,1)
	rd.capture_timestamp(tag+"edit_end")
	rd.capture_timestamp(tag+"water_start")
	for k in steps:
		if profile_detail:rd.capture_timestamp(tag+str(k)+"_cfl_start")
		audit(true) # CFL is computed from the edited/current state on GPU.
		if profile_detail:rd.capture_timestamp(tag+str(k)+"_cfl_end")
		if profile_detail:rd.capture_timestamp(tag+str(k)+"_edge_start")
		_dispatch("edge",index)
		if profile_detail:rd.capture_timestamp(tag+str(k)+"_edge_end")
		if profile_detail:rd.capture_timestamp(tag+str(k)+"_drain_start")
		_dispatch("drain",index)
		if profile_detail:rd.capture_timestamp(tag+str(k)+"_drain_end")
		if profile_detail:rd.capture_timestamp(tag+str(k)+"_update_start")
		_dispatch("update",index)
		if profile_detail:rd.capture_timestamp(tag+str(k)+"_update_end")
		index=1-index
	rd.capture_timestamp(tag+"water_end")
	rd.capture_timestamp(tag+"audit_start")
	audit(false)
	rd.capture_timestamp(tag+"audit_end")
	rd.capture_timestamp(tag+"publish_start")
	_dispatch("publish",index)
	rd.capture_timestamp(tag+"publish_end")
	var recording_us := Time.get_ticks_usec()-start
	var data := {"recording_us":recording_us,"timestamps":times,"serial":serial,"submitted_us":start}
	if full:
		# Register both requests before either callback. RD callbacks must not
		# recursively register another readback under the completion lock.
		data.pending=3
		rd.texture_get_data_async(tex.display,0,_collect.bind("field",data,callback))
		rd.texture_get_data_async(tex.sediment,0,_collect.bind("sediment",data,callback))
		rd.buffer_get_data_async(result_buffer,_collect.bind("metric_bytes",data,callback),0,128)
	else:
		rd.buffer_get_data_async(result_buffer,func(bytes: PackedByteArray):callback.call(bytes,data),0,128)

func _collect(bytes: PackedByteArray,key: String,data: Dictionary,callback: Callable) -> void:
	data[key]=bytes
	data.pending-=1
	if data.pending==0:
		var metrics: PackedByteArray=data.metric_bytes
		data.erase("metric_bytes")
		data.erase("pending")
		callback.call(metrics,data)

func release() -> int:
	var count := owned.size()
	# Release sets and pipelines before their referenced textures/shaders.
	for i in range(owned.size()-1,-1,-1):
		rd.free_rid(owned[i])
	owned.clear()
	return count
