extends RefCounted

# Transient, read-only water/sand consumer. Water owns all four RIDs; Views
# borrows only the two published images. No CPU particle updates or readback.
const SOURCES=["res://scripts/simulation/unified_edit/shore_splash.gd","res://shaders/simulation/shore_splash.glsl","res://shaders/visual/shore_splash.gdshader"]
const WIDTH:=64
const HEIGHT:=16
const CAPACITY:=WIDTH*HEIGHT
var water
var enabled:=false
var published: Dictionary={}
var images: Dictionary={}
var binding:=RID()
var last_error:=""
var bounds:=PackedFloat32Array()

static func configuration_error(config: Dictionary) -> StringName:
	if config.environment.has("shore_splash_enabled") and typeof(config.environment.shore_splash_enabled)!=TYPE_BOOL:return &"invalid_shore_splash_enabled"
	return &""

func _texture() -> RID:
	var format:=RDTextureFormat.new();format.width=WIDTH;format.height=HEIGHT
	format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var bytes:=PackedByteArray();bytes.resize(CAPACITY*16)
	return water._own(water.rd.texture_create(format,RDTextureView.new(),[bytes]))

func initialize(recorder, config: Dictionary) -> bool:
	water=recorder
	if not config.environment.has("shore_splash_enabled"):return true
	enabled=config.environment.shore_splash_enabled
	bounds=PackedFloat32Array([-15.0,-7.5,15.0,7.5] if config.domain_id=="test1_geometry" else [-15.75,-15.75,15.75,15.75])
	for key in ["position","velocity"]:
		images[key]=_texture();published["splash_"+key]=_texture()
	for rid in images.values()+published.values():
		if not rid.is_valid():last_error="shore_splash_texture";return false
	if not water._compile("shore_splash",SOURCES[1],{},[],false):last_error=water.last_error;return false
	var fields: Dictionary=water.solver.textures
	var inputs: Array=[images.position,images.velocity,published.splash_position,published.splash_velocity,fields.rock,fields.sand[0],fields.water[0],fields.momentum[0],fields.obstacle]
	binding=water._make_binding(water.kernels.shore_splash.shader,0,inputs,[water.solver.async_transport.control])
	if not binding.is_valid():last_error="shore_splash_binding";return false
	return true

func publish() -> void:
	if not enabled:return
	var rd: RenderingDevice=water.rd
	var kernel: Dictionary=water.kernels.shore_splash
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,kernel.pipeline)
	rd.compute_list_bind_uniform_set(list,binding,0)
	var push:=bounds.to_byte_array()
	rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch(list,WIDTH/8,HEIGHT/8,1)
	rd.compute_list_end()

func detach() -> void:
	water=null;images.clear();published.clear();binding=RID();enabled=false
