extends RefCounted

# One optional display stage in the common recorder. All RIDs (including
# history and published clones) belong to Water's existing lifetime owner.
const Gravel=preload("res://scripts/visual/gpu_gravel_field.gd")
const Vegetation=preload("res://scripts/simulation/unified_edit/vegetation.gd")
const SOURCES=["res://scripts/simulation/unified_edit/visuals.gd","res://scripts/simulation/unified_edit/visual_finish.glsl","res://scripts/simulation/unified_edit/visual_publish.glsl","res://scripts/visual/gpu_gravel_field.gd","res://shaders/simulation/visual_foam_step.glsl","res://shaders/simulation/visual_gravel_step.glsl","res://tests/visual_water_alignment/prototypes/reference_local_front_x.glsl","res://tests/visual_water_alignment/prototypes/reference_local_front_x_wide.glsl","res://tests/visual_water_alignment/prototypes/reference_local_front_z.glsl","res://scripts/simulation/unified_edit/visual_edit_finish.glsl"]+Vegetation.SOURCES
var vegetation:=Vegetation.new()
var water
var configuration: Dictionary={}
var foam_enabled:=false
var front_enabled:=false
var gravel_enabled:=false
var foam_index:=0
var gravel_index:=0
var active_count:=0
var profile: Dictionary={}
var images: Dictionary={}
var published: Dictionary={}
var bindings: Dictionary={}
var enabled:=false
var last_error:=""
var gravel_meta:=RID()
var display_bindings: Dictionary={}

static func profile_for(config: Dictionary) -> Dictionary:
	return config.environment.get("gravel_profile",Gravel.default_profile("main" if config.domain_id=="main_beach" else config.domain_id)).duplicate(true)

static func configuration_error(config: Dictionary) -> StringName:
	if typeof(config.environment.get("local_front_wide_field",false))!=TYPE_BOOL:return &"invalid_runtime_local_front_wide"
	var vegetation_error:=Vegetation.configuration_error(config)
	if not vegetation_error.is_empty():return vegetation_error
	if config.effects.gravel_enabled:
		if not config.environment.get("gravel_profile",{}) is Dictionary:return &"invalid_gravel_profile"
		return Gravel.validate_profile(profile_for(config),256,0.125)
	return &""

func _texture(format_id: int, bytes: PackedByteArray, width: int=256, height: int=256) -> RID:
	var fmt:=RDTextureFormat.new();fmt.width=width;fmt.height=height;fmt.format=format_id
	fmt.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return water._own(water.rd.texture_create(fmt,RDTextureView.new(),[bytes]))

func _clone(source: RID) -> RID:
	var fmt: RDTextureFormat=water.rd.texture_get_format(source)
	var copy: RID=water._own(water.rd.texture_create(fmt,RDTextureView.new()))
	if not copy.is_valid() or water.rd.texture_copy(source,copy,Vector3.ZERO,Vector3.ZERO,Vector3(fmt.width,fmt.height,1),0,0,0,0)!=OK:return RID()
	return copy

func initialize(recorder, config: Dictionary, domain, restored: Dictionary={}) -> bool:
	water=recorder;configuration=config.duplicate(true)
	front_enabled=config.simulation.local_front_history;foam_enabled=config.effects.foam_enabled or front_enabled;gravel_enabled=config.effects.gravel_enabled;enabled=foam_enabled or gravel_enabled
	if not vegetation.initialize(water,config):last_error=vegetation.last_error;return false
	published.merge(vegetation.published)
	if not enabled:
		if vegetation.enabled:water.tail_recorder=record
		return true
	var native: Dictionary=restored.get("native",{})
	var zero:=PackedByteArray()
	if foam_enabled:
		foam_index=native.get("foam",{}).get("current_index",0)
		zero.resize(65536*8)
		var bed: PackedFloat32Array=domain.rock.duplicate()
		for index in 65536:bed[index]+=domain.sand[index]
		for index in 2:
			images["foam_"+str(index)]=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,native.get("foam",{}).get("foam_"+str(index),zero))
			images["bed_"+str(index)]=_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,native.get("foam",{}).get("bed_"+str(index),bed.to_byte_array()))
	if front_enabled:
		zero=PackedByteArray();zero.resize(65536*16);images.front_x=_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,zero)
		zero=PackedByteArray();zero.resize(65536*8);images.local_front=_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,native.get("histories",{}).get("local_front",zero))
	if gravel_enabled:
		profile=profile_for(config);var ext: Dictionary=restored.get("visual_extensions",{}).get("gravel_v1",{})
		gravel_index=ext.get("current_index",0);active_count=ext.get("active_count",profile.count)
		var meta:=PackedByteArray();meta.resize(80);meta.encode_u32(0,active_count);meta.encode_u32(24,profile.capacity);meta.encode_u32(28,profile.seed&0xffffffff);meta.encode_s64(64,restored.get("highwater_id",0))
		var profile_hash: PackedByteArray=Gravel.profile_hash(profile).hex_decode()
		for index in 32:meta[32+index]=profile_hash[index]
		gravel_meta=water._own(water.rd.storage_buffer_create(meta.size(),meta))
		if not gravel_meta.is_valid():last_error="visual_meta_create";return false
		zero=PackedByteArray();zero.resize(16384)
		for index in 2:images["gravel_"+str(index)]=_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,ext.get("state_"+str(index),zero),64,16)
	for rid in images.values():
		if not rid.is_valid():last_error="visual_texture_create";return false
	var dt:="uintBitsToFloat(async_d[3])";var guard:={"void main() {":"void main() { if(async_d[4]==2u)return;"}
	var s=water.solver.textures
	if foam_enabled:
		var replacements: Dictionary=guard.duplicate();replacements["params.delta_s"]=dt
		if not water._compile("display_foam",SOURCES[4],replacements):return _compile_error()
		bindings.foam=water._make_binding(water.kernels.display_foam.shader,0,[images["foam_"+str(foam_index)],s.water[0],s.momentum_x[0],s.momentum_z[0],s.rock,s.sand[0],images["foam_"+str(1-foam_index)],images["bed_"+str(foam_index)],images["bed_"+str(1-foam_index)]],[])
	if front_enabled:
		if not water._compile("display_front_x",SOURCES[7] if config.environment.get("local_front_wide_field",false) else SOURCES[6],guard) or not water._compile("display_front_z",SOURCES[8],guard):return _compile_error()
		bindings.front_x=water._make_binding(water.kernels.display_front_x.shader,0,[s.water[0],images["foam_"+str(foam_index)],images.front_x,s.rock,s.sand[0],images["bed_"+str(foam_index)]],[])
		bindings.front_z=water._make_binding(water.kernels.display_front_z.shader,0,[images.front_x,images.local_front],[])
	if gravel_enabled:
		var distance: float=0.125*profile.max_step_cell_fraction
		var replacements: Dictionary=guard.duplicate();replacements["p.domain.z"]=dt
		var declaration:="#version 450\nlayout(set=2,binding=0,std430) readonly buffer DisplayMeta {uint display_meta[];};"
		replacements["#version 450"]=declaration;replacements["p.identity.x"]="display_meta[0]"
		replacements["p.domain.w"]="min(max(1.0,ceil(%s*%.16f*%.16f/%.16f)),%.1f)"%[dt,profile.response_max,profile.speed_cap_m_s,distance,float(profile.max_microsteps)]
		replacements["p.movement.w"]="min(p.movement[3],%.16f/max(%s*%.16f,1e-20))"%[distance*profile.max_microsteps,dt,profile.response_max]
		if not water._compile("display_gravel",SOURCES[5],replacements):return _compile_error()
		water.kernels.display_gravel.meta_set=water._make_binding(water.kernels.display_gravel.shader,2,[],[gravel_meta])
		var inputs: Array=[images["gravel_"+str(gravel_index)],images["gravel_"+str(1-gravel_index)],s.rock,s.sand[0],s.water[0],s.momentum_x[0],s.momentum_z[0]]
		bindings.gravel=water._make_binding(water.kernels.display_gravel.shader,0,inputs,[])
		if not water._compile("display_gravel_static",SOURCES[5],{"#version 450":declaration,"p.identity.x":"display_meta[0]"},[],false):return _compile_error()
		water.kernels.display_gravel_static.meta_set=water._make_binding(water.kernels.display_gravel_static.shader,2,[],[gravel_meta])
		bindings.gravel_static=water._make_binding(water.kernels.display_gravel_static.shader,0,inputs,[])
		if not water._compile("display_gravel_emit",SOURCES[5],{"#version 450":declaration,"p.identity.x":"display_meta[2]","p.options.y":"float(display_meta[1])","void main() {":"void main() { if(display_meta[3]==0u)return;"},[],false):return _compile_error()
		water.kernels.display_gravel_emit.meta_set=water._make_binding(water.kernels.display_gravel_emit.shader,2,[],[gravel_meta])
		bindings.gravel_emit=water._make_binding(water.kernels.display_gravel_emit.shader,0,inputs,[])
		if not water._compile("display_emit","res://scripts/simulation/unified_edit/display_emit.glsl",{"// UE_LAYOUT":water.solver.async_transport.L.shader_defines()},[],false):return _compile_error()
		for slot in water.solver.async_transport.resources:
			var binding: RID=water._make_binding(water.kernels.display_emit.shader,0,[inputs[1],inputs[0]],[slot.input,water.solver.async_transport.control,slot.output,gravel_meta])
			if not binding.is_valid():last_error="display_emit_binding";return false
			display_bindings[slot.input]=binding
		if not water._compile("display_edit_finish","res://scripts/simulation/unified_edit/visual_edit_finish.glsl",{},[],false):return _compile_error()
		bindings.edit_finish=water._make_binding(water.kernels.display_edit_finish.shader,0,[inputs[1],inputs[0]],[water.solver.async_transport.control])
		if restored.is_empty():
			_dispatch_gravel("display_gravel_static",bindings.gravel_static,1)
			if water.rd.texture_copy(inputs[1],inputs[0],Vector3.ZERO,Vector3.ZERO,Vector3(64,16,1),0,0,0,0)!=OK:last_error="visual_gravel_initial_copy";return false
	var definitions:="#define UE_FOAM %d\n#define UE_FRONT %d\n#define UE_GRAVEL %d\n#define UE_GBASE %d\n#define UE_FBASE %d\n#define UE_PGBASE %d\n#define UE_CONTROL %d"%[int(foam_enabled),int(front_enabled),int(gravel_enabled),4 if foam_enabled else 0,2 if foam_enabled else 0,(2 if foam_enabled else 0)+(2 if front_enabled else 0),(2 if foam_enabled else 0)+(2 if front_enabled else 0)+(2 if gravel_enabled else 0)]
	if not water._compile("display_finish",SOURCES[1],{"// UE_VISUAL_DEFINES":definitions}) or not water._compile("display_publish",SOURCES[2],{"// UE_VISUAL_DEFINES":definitions},[],false):return _compile_error()
	var finish: Array=[];var publication: Array=[]
	if foam_enabled:
		finish.append_array([images["foam_"+str(1-foam_index)],images["foam_"+str(foam_index)],images["bed_"+str(1-foam_index)],images["bed_"+str(foam_index)]])
		published.foam=_clone(images["foam_"+str(foam_index)]);publication.append_array([images["foam_"+str(foam_index)],published.foam])
	if front_enabled:published.local_front=_clone(images.local_front);publication.append_array([images.local_front,published.local_front])
	if gravel_enabled:
		finish.append_array([images["gravel_"+str(1-gravel_index)],images["gravel_"+str(gravel_index)]])
		published.gravel=_clone(images["gravel_"+str(gravel_index)]);publication.append_array([images["gravel_"+str(gravel_index)],published.gravel])
	bindings.finish=water._make_binding(water.kernels.display_finish.shader,0,finish,[])
	bindings.publish=water._make_binding(water.kernels.display_publish.shader,0,publication,[water.solver.async_transport.control])
	for rid in bindings.values():
		if not rid.is_valid():last_error="visual_uniform_create";return false
	for rid in published.values():
		if not rid.is_valid():last_error="visual_publication_create";return false
	water.tail_recorder=record;return true

func _compile_error() -> bool:last_error=water.last_error;return false

func _dispatch_gravel(kernel: String, binding: RID, mode: int, spawn: PackedFloat32Array=PackedFloat32Array()) -> void:
	var p: Dictionary=profile
	var push:=PackedInt32Array([active_count,p.capacity,p.seed,mode]).to_byte_array()
	push.append_array(PackedFloat32Array([256,0.125,0.0,1.0,p.h_on_m,p.h_off_m,p.speed_on_m_s,p.speed_off_m_s,p.response_min,p.response_max,p.h_epsilon_m,p.speed_cap_m_s]).to_byte_array())
	push.append_array((PackedFloat32Array(p.spawn_bounds_xz) if spawn.is_empty() else spawn).to_byte_array());push.append_array(PackedFloat32Array([1.0 if p.bed_reconstruction else 0.0,0,0,0]).to_byte_array())
	var rd: RenderingDevice=water.rd;var k: Dictionary=water.kernels[kernel];var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,k.pipeline);rd.compute_list_bind_uniform_set(list,binding,0)
	if k.has("decision_set"):rd.compute_list_bind_uniform_set(list,k.decision_set,1)
	if k.has("meta_set"):rd.compute_list_bind_uniform_set(list,k.meta_set,2)
	rd.compute_list_set_push_constant(list,push,push.size());rd.compute_list_dispatch(list,16,1,1);rd.compute_list_end()

func record(_decision: RID) -> void:
	vegetation.record_tick()
	if not enabled:return
	if front_enabled:
		water._dispatch("display_front_x",bindings.front_x,PackedByteArray());water._dispatch("display_front_z",bindings.front_z,PackedByteArray())
	if foam_enabled:water._dispatch("display_foam",bindings.foam,PackedFloat32Array([0,0.125,configuration.environment.get("foam_parameters",{}).get("foam_lifetime_s",1.8),configuration.environment.get("foam_parameters",{}).get("foam_source_gain",25)]).to_byte_array())
	if gravel_enabled:_dispatch_gravel("display_gravel",bindings.gravel,0)
	water._dispatch("display_finish",bindings.finish,PackedByteArray())

func publish() -> void:
	if enabled:water._dispatch("display_publish",bindings.publish,PackedByteArray())
	vegetation.publish()

func record_edit() -> void:
	vegetation.record_edit()
	# A completed edit batch also changes the visible bed. Reprojection uses
	# the original mode=2 kernel; it advances neither physics nor visual time.
	if not gravel_enabled:return
	_dispatch_gravel("display_gravel_static",bindings.gravel_static,2)
	water._dispatch("display_edit_finish",bindings.edit_finish,PackedByteArray())

func record_display(input: RID, command: Dictionary) -> void:
	var point: Vector2=command.point_xz_m
	_display_phase(input,0)
	_dispatch_gravel("display_gravel_emit",bindings.gravel_emit,3,PackedFloat32Array([point.x-0.45,point.y-0.45,point.x+0.45,point.y+0.45]))
	_display_phase(input,1);_display_phase(input,2)

func _display_phase(input: RID, phase: int) -> void:
	var rd: RenderingDevice=water.rd;var k: Dictionary=water.kernels.display_emit
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,k.pipeline);rd.compute_list_bind_uniform_set(list,display_bindings[input],0)
	var push:=PackedByteArray();push.resize(4);push.encode_u32(0,phase);rd.compute_list_set_push_constant(list,push,4)
	rd.compute_list_dispatch(list,1 if phase==0 else 16,1,1);rd.compute_list_end()

func capture_images() -> Dictionary:
	var result: Dictionary={}
	for key in images:
		if key!="front_x":result["visual/"+key]=images[key]
	return result

func gravel_extension(epoch: int, tick: int, revision: int, bytes: Dictionary={}) -> Dictionary:
	if not gravel_enabled:return {"version":2,"enabled":false}
	var scene: String="main" if configuration.domain_id=="main_beach" else configuration.domain_id
	return {"version":2,"enabled":true,"domain_id":configuration.domain_id,"profile_id":"gravel_v1/"+scene,"profile_sha256":Gravel.profile_hash(profile),"profile_values":profile.duplicate(true),"tick":tick,"revision":revision,"source_generation":epoch,"current_index":gravel_index,"state_0":bytes.get("visual/gravel_0",PackedByteArray()),"state_1":bytes.get("visual/gravel_1",PackedByteArray()),"width":64,"height":16,"count":profile.count,"capacity":1024,"active_count":active_count}

func detach() -> void:
	if water!=null:water.tail_recorder=Callable()
	vegetation.detach()
	water=null;images.clear();published.clear();bindings.clear()
	gravel_meta=RID();display_bindings.clear()
