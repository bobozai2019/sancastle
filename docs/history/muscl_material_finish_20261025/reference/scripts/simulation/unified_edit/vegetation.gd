extends RefCounted

# Decorative GPU consumer recorded by Visuals. Water owns every RID and its
# release proof. No private device, CPU readback, or water/sand writer exists.
const Profile = preload("res://scripts/visual/vegetation_profile.gd")
const SOURCES = ["res://scripts/simulation/unified_edit/vegetation.gd",
	"res://scripts/visual/vegetation_profile.gd","res://scripts/visual/vegetation_species.gd",
	"res://scripts/visual/vegetation_layer.gd","res://shaders/simulation/vegetation_step_momentum.glsl",
	"res://shaders/simulation/vegetation_publish.glsl","res://shaders/visual/vegetation.gdshader"]
var water
var profile: Dictionary = {}
var images: Dictionary = {}
var published: Dictionary = {}
var sets: Dictionary = {}
var enabled := false
var last_error := ""

static func configuration_error(config: Dictionary) -> StringName:
	if not config.environment.has("vegetation_profile"):return &""
	return Profile.validate(config.environment.vegetation_profile)

func _texture() -> RID:
	var format := RDTextureFormat.new()
	format.width = Profile.WIDTH;format.height = Profile.HEIGHT
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var bytes := PackedByteArray();bytes.resize(Profile.WIDTH * Profile.HEIGHT * 16)
	return water._own(water.rd.texture_create(format,RDTextureView.new(),[bytes]))

func initialize(recorder, config: Dictionary) -> bool:
	water = recorder
	if not config.environment.has("vegetation_profile"):return true
	profile = config.environment.vegetation_profile.duplicate(true);enabled = profile.enabled
	for key in ["roots","motion"]:
		images[key] = _texture();published["vegetation_"+key] = _texture()
	for rid in images.values() + published.values():
		if not rid.is_valid():last_error = "vegetation_texture";return false
	var parameters := PackedFloat32Array(profile.bounds_xz)
	parameters.append_array(PackedFloat32Array([float(profile.seed),Profile.CANDIDATES_PER_KIND,0.0,0.0]))
	for item in profile.species:
		parameters.append_array(PackedFloat32Array([item.depth_min_m,item.depth_max_m,item.scale_min,item.scale_max,
			item.bed_min_m,item.bed_max_m,item.density,item.flow_response,
			item.max_slope,item.patch_min,item.patch_max,item.response_hz]))
	var bytes := parameters.to_byte_array()
	var settings: RID = water._own(water.rd.storage_buffer_create(bytes.size(),bytes))
	if not settings.is_valid():last_error = "vegetation_parameters";return false
	if not water._compile("vegetation_tick",SOURCES[4],{"float dt = 0.0; // VEG_DT":"float dt = uintBitsToFloat(async_d[3]);","// VEG_GUARD":"if(async_d[4]==2u)return;"}):return _compile_error()
	if not water._compile("vegetation_edit",SOURCES[4],{"// VEG_GUARD":"if(control[1]!=0u)return;"},[],false):return _compile_error()
	if not water._compile("vegetation_publish",SOURCES[5],{},[],false):return _compile_error()
	var fields: Dictionary = water.solver.textures
	var inputs: Array = [images.roots,images.motion,fields.rock,fields.sand[0],fields.water[0],fields.momentum[0],fields.obstacle]
	for name in ["vegetation_tick","vegetation_edit"]:
		sets[name] = water._make_binding(water.kernels[name].shader,0,inputs,[water.solver.async_transport.control,settings])
	sets.vegetation_publish = water._make_binding(water.kernels.vegetation_publish.shader,0,[images.roots,images.motion,published.vegetation_roots,published.vegetation_motion],[water.solver.async_transport.control])
	for rid in sets.values():
		if not rid.is_valid():last_error = "vegetation_binding";return false
	if enabled:
		_dispatch("vegetation_edit",1)
		_dispatch("vegetation_publish")
	return true

func _compile_error() -> bool:
	last_error = water.last_error
	return false

func _dispatch(name: String, mode: int = 0) -> void:
	var rd: RenderingDevice = water.rd
	var kernel: Dictionary = water.kernels[name]
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,kernel.pipeline)
	rd.compute_list_bind_uniform_set(list,sets[name],0)
	if kernel.has("decision_set"):rd.compute_list_bind_uniform_set(list,kernel.decision_set,1)
	if name != "vegetation_publish":rd.compute_list_set_push_constant(list,PackedInt32Array([mode]).to_byte_array(),4)
	rd.compute_list_dispatch(list,Profile.WIDTH/8,Profile.HEIGHT/8,1)
	rd.compute_list_end()

func record_tick() -> void:
	if enabled:_dispatch("vegetation_tick")

func record_edit() -> void:
	if enabled:_dispatch("vegetation_edit")

func publish() -> void:
	if enabled:_dispatch("vegetation_publish")

func detach() -> void:
	water = null;images.clear();published.clear();sets.clear();enabled = false
