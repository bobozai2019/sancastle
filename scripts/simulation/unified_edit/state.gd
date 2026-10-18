extends "res://scripts/simulation/unified_edit/gpu.gd"

# Physical resource bundle only. It has no CPU patch or old editor entry point.
const COURANT:=0.35
const MaterialCodec=preload("res://scripts/simulation/brushes/brush_material_state_codec.gd")
const UnitHalf=preload("res://scripts/simulation/unified_edit/unit_half.gd")
var grid_size:=256
var cell_size_m:=0.125
var current_index:=0
var state_revision:=0
var prescribed_tide_boundary:=false
var cohesion_yield_height_m:=0.0
var profile_passes:=false
var async_active:=true
var async_transport
var textures: Dictionary={}
var pipelines: Array[RID]=[]
var uniform_sets: Array=[]
var published_sand:=RID()
var published_water:=RID()
var published_stamp:=RID()
var publish_set:=RID()
var publication_count:=0

func _create_texture(format_id: int, data: PackedByteArray, width: int=256, height: int=256) -> RID:
	var strides:={RenderingDevice.DATA_FORMAT_R32_SFLOAT:4,RenderingDevice.DATA_FORMAT_R32_UINT:4,RenderingDevice.DATA_FORMAT_R32G32_SFLOAT:8,RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:16,RenderingDevice.DATA_FORMAT_R16_SFLOAT:2,RenderingDevice.DATA_FORMAT_R8_UNORM:1}
	if data.is_empty():data.resize(width*height*int(strides[format_id]))
	var format:=RDTextureFormat.new();format.width=width;format.height=height;format.format=format_id
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return own(rd.texture_create(format,RDTextureView.new(),[data]))

func initialize(device: RenderingDevice, domain, transport, native: Dictionary={}) -> bool:
	if rd!=null or device==null or domain==null or domain.grid_size!=256 or domain.cell_size_m!=0.125:return false
	if not is_finite(cohesion_yield_height_m) or cohesion_yield_height_m<0.0 or cohesion_yield_height_m>2.0:last_error="initial_cohesion_value";return false
	rd=device;async_transport=transport
	for field in ["rock","sand","water","sediment","wetness","compaction","obstacle"]:
		var values: PackedFloat32Array=domain.get(field)
		if values.size()!=65536:last_error="initial_field_size";return false
		for value in values:
			if not is_finite(value) or (field!="rock" and value<0.0) or (field in ["wetness","compaction","obstacle"] and value>1.0):last_error="initial_field_value";return false
		var format_id: int=RenderingDevice.DATA_FORMAT_R32_SFLOAT
		var bytes:=values.to_byte_array()
		if field in ["wetness","compaction"]:
			format_id=RenderingDevice.DATA_FORMAT_R16_SFLOAT
			var encoded:=UnitHalf.encode(values)
			if not encoded.error.is_empty():last_error=String(encoded.error);return false
			bytes=encoded.value
		if field=="obstacle":
			format_id=RenderingDevice.DATA_FORMAT_R8_UNORM;bytes.resize(65536)
			for index in 65536:bytes[index]=255 if values[index]>=0.5 else 0
		if not native.is_empty():bytes=native.fields[field]
		textures[field]=_create_texture(format_id,bytes) if field in ["rock","obstacle"] else [_create_texture(format_id,bytes),_create_texture(format_id,bytes if native.is_empty() else native.spare[field])]
	for field in ["momentum_x","momentum_z"]:
		var data:=PackedByteArray()
		var key: String="edit_validation_initial_qx" if field=="momentum_x" else "edit_validation_initial_qz"
		if domain.has_meta(key):
			var values: Variant=domain.get_meta(key)
			if not values is PackedFloat32Array or values.size()!=65536:last_error="initial_momentum_size";return false
			for value in values:
				if not is_finite(value):last_error="initial_momentum_value";return false
			data=values.to_byte_array()
		if not native.is_empty():data=native.fields[field]
		textures[field]=[_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,data),_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,data if native.is_empty() else native.spare[field])]
	for field in ["flux","mold_support"]:
		var format_id: int=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT if field=="flux" else RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
		var bytes:=PackedByteArray()
		if field=="mold_support":
			bytes=MaterialCodec.initial_values(domain.get_meta("brush_initial_mold_depth",PackedFloat32Array()),domain.sand)
			if bytes.is_empty():last_error="initial_material_value";return false
		var spare:=bytes
		if not native.is_empty():
			bytes=native.material.current_support if field=="mold_support" else native.fields[field]
			spare=native.material.spare_support if field=="mold_support" else native.spare[field]
		textures[field]=[_create_texture(format_id,bytes),_create_texture(format_id,spare)]
	for field in ["edge_x","edge_z","drain","cfl_tiles"]:
		textures[field]=_create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT if field in ["edge_x","edge_z"] else RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray(),32 if field=="cfl_tiles" else 256,32 if field=="cfl_tiles" else 256)
	for collection in textures.values():
		for rid in (collection if collection is Array else [collection]):
			if not rid.is_valid():last_error="physical_texture_create";return false
	for name in ["edge_flux","drain_scale","update_state"]:
		if not compile(name,"res://shaders/simulation/shallow_"+name+".glsl"):return false
		pipelines.append(kernels[name].pipeline)
	for index in 2:
		var edge:=[textures.rock,textures.sand[index],textures.water[index],textures.momentum_x[index],textures.momentum_z[index],textures.obstacle,textures.edge_x,textures.edge_z]
		var drain:=[textures.water[index],textures.edge_x,textures.edge_z,textures.drain]
		var update:=[textures.rock,textures.sand[index],textures.water[index],textures.momentum_x[index],textures.momentum_z[index],textures.obstacle,textures.edge_x,textures.edge_z,textures.drain,textures.water[1-index],textures.momentum_x[1-index],textures.momentum_z[1-index],textures.flux[1-index]]
		var sets: Array=[]
		for pair in [["edge_flux",edge],["drain_scale",drain],["update_state",update]]:
			var images:={}
			for image_index in pair[1].size():images[image_index]=pair[1][image_index]
			var uniform:=binding(pair[0],{},images);sets.append(uniform)
			if not uniform.is_valid():last_error="physical_uniform_create";return false
		uniform_sets.append(sets)
	published_sand=_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,domain.sand.to_byte_array())
	published_water=_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,domain.water.to_byte_array())
	var stamp:=PackedByteArray();stamp.resize(32);stamp.encode_s64(0,domain.generation)
	if not native.is_empty():
		stamp.encode_s64(8,native.control.decode_s64(16));stamp.encode_s64(16,native.control.decode_s64(40));stamp.encode_s64(24,native.control.decode_s64(24))
	published_stamp=own(rd.storage_buffer_create(32,stamp))
	if not compile("publish","res://scripts/simulation/unified_edit/publish.glsl"):return false
	publish_set=binding("publish",{0:transport.control,1:published_stamp},{2:textures.sand[0],3:textures.water[0],4:published_sand,5:published_water})
	return published_sand.is_valid() and published_water.is_valid() and published_stamp.is_valid() and publish_set.is_valid()

func publish_sand() -> void:
	# Called only after work_seal. The GPU guard preserves the previous complete
	# public view on fatal, including a fatal after a valid earlier batch command.
	dispatch("publish",publish_set,Vector3i(1024,1,1))
	# Recording attempts; the GPU stamp is the actual publication identity.
	publication_count+=1

func release() -> void:
	if async_transport!=null and async_transport.has_owned():push_error("state release while unified work owns resources");return
	textures.clear();pipelines.clear();uniform_sets.clear();super.release()
