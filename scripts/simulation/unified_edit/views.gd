extends "res://scripts/simulation/unified_edit/gpu.gd"

# Read-only consumers share the same sealed publication. No profile may choose
# another writer/query shader or own a private publication/readback loop.
const Intent=preload("res://scripts/simulation/unified_edit/intent.gd")
const Wire=preload("res://scripts/simulation/unified_edit/protocol.gd")
const Configuration=preload("res://scripts/simulation/unified_edit/configuration.gd")
const SOURCES=["res://scripts/simulation/unified_edit/views.gd","res://scripts/simulation/unified_edit/view_publish.glsl","res://scripts/simulation/unified_edit/view_query.glsl"]
const FIELDS=["sediment","momentum_x","momentum_z","wetness","compaction","mold_support","flux","baseline"]
enum Freshness { CURRENT, SNAPSHOT }
signal detach_finished(success: bool)
var state
var transport
var registry
var configuration: Dictionary={}
var generation:=0
var textures: Dictionary={}
var visual_textures: Dictionary={}
var wrappers: Dictionary={}
var bindings: Dictionary={}
var buffers: Dictionary={}
var sets: Dictionary={}
var pending:=false
var query_serial:=0
var context_version:=0
var completed_floor:=0
var last_preview: Dictionary={}
var closing:=false
var detached_confirmed:=true
var detach_pending:=false
var hold_delivery:=false
var held: Dictionary={}
var inject_readback_failure_once:=false
var inject_detach_failure_once:=false
var _query: Dictionary={}

func initialize(bundle, executor, channel, catalog, config: Dictionary, epoch: int) -> bool:
	state=bundle;transport=channel;registry=catalog;configuration=config.duplicate(true);generation=epoch;rd=channel.rd
	textures={"rock":state.textures.rock,"obstacle":state.textures.obstacle,"sand":state.published_sand,"water":state.published_water,"clock":transport.clock_texture}
	textures.merge(visual_textures)
	var images:={}
	for index in FIELDS.size():
		var field: String=FIELDS[index]
		var source: RID=executor.images.baseline if field=="baseline" else state.textures[field][0]
		var spec: RDTextureFormat=rd.texture_get_format(source)
		var texture:=own(rd.texture_create(spec,RDTextureView.new()))
		if not texture.is_valid() or rd.texture_copy(source,texture,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)!=OK:last_error="view_texture";return false
		textures[field]=texture;images[3+index*2]=source;images[4+index*2]=texture
	for pair in [["stroke",64],["command",512],["identity",16],["blocks",256*32],["result",96]]:
		var bytes:=PackedByteArray();bytes.resize(pair[1]);buffers[pair[0]]=own(rd.storage_buffer_create(pair[1],bytes))
	if not compile("publish",SOURCES[1]) or not compile("query",SOURCES[2]):return false
	sets.publish=binding("publish",{0:transport.control,1:executor.buffers.stroke,2:buffers.stroke},images)
	sets.query=binding("query",{0:buffers.command,1:state.published_stamp,2:executor.buffers.templates,3:buffers.blocks,4:buffers.result,5:buffers.identity,11:buffers.stroke},{6:textures.rock,7:textures.sand,8:textures.water,9:textures.obstacle,10:textures.baseline,12:textures.clock})
	for set in sets.values():
		if not set.is_valid():last_error="view_binding";return false
	return true

func publish() -> void:dispatch("publish",sets.publish,Vector3i(1024,1,1))

func validate_material(material: ShaderMaterial, parameters: Dictionary) -> StringName:
	if closing or rd==null or material==null:return &"view_closed"
	if material.shader==null:return &"invalid_view_material"
	var uniforms:={}
	for uniform in material.shader.get_shader_uniform_list():uniforms[uniform.name]=true
	for parameter in parameters:
		if not uniforms.has(parameter):return &"unknown_view_parameter"
	for field in parameters.values():
		if not textures.has(field):return &"unknown_view_field"
	return &""

func bind_material(material: ShaderMaterial, parameters: Dictionary) -> StringName:
	var error:=validate_material(material,parameters)
	if not error.is_empty():return error
	var key:=material.get_instance_id()
	if not bindings.has(key):bindings[key]={"material":material,"previous":{}}
	for parameter in parameters:
		var field: String=parameters[parameter]
		if not wrappers.has(field):
			var wrapper:=Texture2DRD.new();wrapper.texture_rd_rid=textures[field];wrappers[field]=wrapper
		if not bindings[key].previous.has(parameter):bindings[key].previous[parameter]=material.get_shader_parameter(parameter)
		material.set_shader_parameter(parameter,wrappers[field])
	detached_confirmed=false
	return &""

func invalidate_preview() -> void:
	if context_version==L.INT64_MAX:closing=true
	else:context_version+=1
	last_preview={}

func observe_complete(header: Dictionary) -> void:
	completed_floor=maxi(completed_floor,header.state_seq)
	if not last_preview.is_empty() and last_preview.get("freshness",Freshness.CURRENT)==Freshness.CURRENT and last_preview.state_seq<completed_floor:last_preview={}

func request_preview(request: Dictionary, callback: Callable, minimum_state_seq: int=0, freshness: int=Freshness.CURRENT) -> Dictionary:
	if closing or rd==null:return {"accepted":false,"error":&"view_closed"}
	if pending:return {"accepted":false,"error":&"preview_busy"}
	if not callback.is_valid() or minimum_state_seq<0 or freshness not in Freshness.values():return {"accepted":false,"error":&"invalid_preview_request"}
	if query_serial==L.INT64_MAX:return {"accepted":false,"error":&"preview_identity_exhausted"}
	var frozen:=Intent.freeze(registry,request,configuration.domain_id,generation)
	if not frozen.error.is_empty():return {"accepted":false,"error":frozen.error}
	var error:=Configuration.allows_intent(configuration,frozen.value)
	if not error.is_empty():return {"accepted":false,"error":error}
	if freshness==Freshness.CURRENT and not last_preview.is_empty() and last_preview.state_seq<maxi(minimum_state_seq,completed_floor):last_preview={}
	query_serial+=1;pending=true
	_query={"serial":query_serial,"context":context_version,"minimum":minimum_state_seq,"freshness":freshness,"callback":callback}
	RenderingServer.call_on_render_thread(_query_render.bind(Wire.encode_command(frozen.value,registry),query_serial))
	return {"accepted":true,"error":&"","query_serial":query_serial}

func _query_render(command: PackedByteArray, serial: int) -> void:
	var identity:=PackedByteArray();identity.resize(16);identity.encode_s64(0,generation);identity.encode_s64(8,serial)
	if rd.buffer_update(buffers.command,0,command.size(),command)!=OK or rd.buffer_update(buffers.identity,0,16,identity)!=OK:
		call_deferred("_unrecorded",serial);return
	dispatch("query",sets.query,Vector3i(256,1,1),PackedInt32Array([0,0,0,0]).to_byte_array())
	dispatch("query",sets.query,Vector3i.ONE,PackedInt32Array([1,0,0,0]).to_byte_array())
	_read_render(serial)

func _unrecorded(serial: int) -> void:
	if pending and _query.serial==serial:_complete({"error":&"preview_upload_failed","recorded":false})

func _read_render(serial: int) -> void:
	var error: Error=ERR_UNAVAILABLE
	if inject_readback_failure_once:inject_readback_failure_once=false
	else:error=rd.buffer_get_data_async(buffers.result,_arrived.bind(serial),0,96)
	if error!=OK:call_deferred("_unknown",serial)

func _unknown(serial: int) -> void:
	if pending and _query.serial==serial:_query.unknown=true

func retry_preview_readback() -> void:
	if pending and _query.get("unknown",false):
		_query.unknown=false;RenderingServer.call_on_render_thread(_read_render.bind(_query.serial))

func _arrived(bytes: PackedByteArray, serial: int) -> void:call_deferred("_received",bytes,serial)

func _received(bytes: PackedByteArray, serial: int) -> void:
	if not pending or _query.serial!=serial:return
	if hold_delivery:held={"bytes":bytes.duplicate(),"serial":serial};return
	var value:={"error":&"","raw":bytes.duplicate()}
	if bytes.size()!=96 or bytes.decode_u32(0)!=1 or bytes.decode_s64(8)!=serial or bytes.decode_s64(16)!=generation:
		value.error=&"invalid_preview_receipt"
	else:
		value.merge({"query_serial":serial,"generation":bytes.decode_s64(16),"state_seq":bytes.decode_s64(24),"revision":bytes.decode_s64(32),"tick":bytes.decode_s64(40),"flags":bytes.decode_u32(4),"base":bytes.decode_float(48),"minimum":bytes.decode_float(52),"maximum":bytes.decode_float(56),"water":bytes.decode_float(60),"count":bytes.decode_u32(64),"obstacles":bytes.decode_u32(68),"uses_baseline":bytes.decode_u32(72)==1,"time_s":bytes.decode_float(76)})
		if value.state_seq<0 or value.revision<0 or value.tick<0 or value.count>65536 or value.obstacles>value.count or value.time_s<0.0 or not is_finite(value.base) or not is_finite(value.minimum) or not is_finite(value.maximum) or not is_finite(value.water) or not is_finite(value.time_s):value.error=&"invalid_preview_receipt"
		elif closing:value.error=&"view_closed"
		elif _query.context!=context_version:value.error=&"preview_superseded"
		elif value.state_seq<(_query.minimum if _query.freshness==Freshness.SNAPSHOT else maxi(_query.minimum,completed_floor)):value.error=&"stale_preview_version"
		value.freshness=_query.freshness;value.state_lag=maxi(0,completed_floor-value.state_seq);value.advisory=true
	if value.error.is_empty():last_preview=value.duplicate(true)
	_complete(value)

func deliver_held() -> void:
	var packet:=held.duplicate(true);held={};hold_delivery=false
	if not packet.is_empty():_received(packet.bytes,packet.serial)

func _complete(value: Dictionary) -> void:
	var callback: Callable=_query.callback;pending=false;_query={}
	if callback.is_valid():callback.call(value)

func close_preview() -> void:closing=true;invalidate_preview()

# Restore all caller parameters, wait until render bindings pass a frame
# boundary, then obtain an ordered real-device proof before freeing resources.
func start_detach_bindings() -> bool:
	if detach_pending:return false
	close_preview()
	for entry in bindings.values():
		if is_instance_valid(entry.material):
			for parameter in entry.previous:entry.material.set_shader_parameter(parameter,entry.previous[parameter])
	bindings.clear()
	if wrappers.is_empty():detached_confirmed=true;return true
	detach_pending=true
	call_deferred("_detach_after_frame")
	return true

func detach_bindings() -> bool:
	if not start_detach_bindings():return false
	if detached_confirmed:return true
	return await detach_finished

func _detach_after_frame() -> void:
	await RenderingServer.frame_post_draw
	RenderingServer.call_on_render_thread(_detach_render)

func _detach_render() -> void:
	for wrapper in wrappers.values():wrapper.texture_rd_rid=RID()
	detach_pending=true
	var error: Error=ERR_UNAVAILABLE
	if inject_detach_failure_once:inject_detach_failure_once=false
	else:error=rd.buffer_get_data_async(state.published_stamp,_detach_arrived,0,32)
	if error!=OK:call_deferred("_detach_result",false)

func _detach_arrived(_bytes: PackedByteArray) -> void:call_deferred("_detach_result",true)
func _detach_result(success: bool) -> void:
	detach_pending=false;detached_confirmed=success
	if success:wrappers.clear()
	detach_finished.emit(success)

func can_release() -> bool:return not pending and bindings.is_empty() and detached_confirmed and not detach_pending

func release_if_idle() -> bool:
	if not can_release():return false
	sets.clear();buffers.clear();textures.clear();visual_textures.clear();state=null;transport=null;registry=null;super.release();return true
