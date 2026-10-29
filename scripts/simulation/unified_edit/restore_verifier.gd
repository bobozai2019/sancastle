extends RefCounted

# A bounded initialization reader. It never owns/writes authority and never
# admits work before every registered readback has returned and matched.
const MomentumBytes=preload("res://scripts/simulation/unified_edit/momentum_bytes.gd")
const Half=preload("res://scripts/simulation/unified_edit/unit_half.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
var started:=false
var pending:=0
var passed:=false
var error: StringName=&""
var records: Dictionary={}
var raw_fields: Dictionary={}
var capture_bytes:=false
var inject_registration_failure_once:=false
var inject_corruption_once:=false
var hold_delivery:=false
var held: Dictionary={}
var _expected: Dictionary={}
var _callback: Callable
var _submitting:=false

static func domain_from(checkpoint: Dictionary, epoch: int):
	var domain=Domain.new(256,0.125);domain.domain_id=StringName(checkpoint.domain_id);domain.generation=epoch;domain.sim_tick=checkpoint.sim_tick
	for field in ["rock","sand","water","sediment"]:domain.set(field,checkpoint.native.fields[field].to_float32_array())
	for field in ["wetness","compaction"]:domain.set(field,Half.decode(checkpoint.native.fields[field]).value)
	var obstacle:=PackedFloat32Array();obstacle.resize(65536)
	for index in 65536:obstacle[index]=float(checkpoint.native.fields.obstacle[index])/255.0
	domain.obstacle=obstacle
	return domain

func verify_render(state, executor, views, transport, native: Dictionary, callback: Callable, visuals=null, extensions: Dictionary={}, boundary=null) -> void:
	if started:return
	started=true;_callback=callback;_submitting=true
	var images:={}
	var momentum:=MomentumBytes.pack(native.fields.get("momentum_x",PackedByteArray()),native.fields.get("momentum_z",PackedByteArray()))
	var spare_momentum:=MomentumBytes.pack(native.spare.get("momentum_x",PackedByteArray()),native.spare.get("momentum_z",PackedByteArray()))
	if not momentum.error.is_empty() or not spare_momentum.error.is_empty():
		error=&"restore_readback_mismatch";_submitting=false;_finish_if_complete();return
	images["field/momentum"]=state.textures.momentum[0];_expected["field/momentum"]=momentum.value
	images["spare/momentum"]=state.textures.momentum[1];_expected["spare/momentum"]=spare_momentum.value
	for field in native.fields:
		if field in ["momentum_x","momentum_z"]:continue
		var rid: RID=state.textures[field] if field in ["rock","obstacle"] else state.textures[field][0]
		images["field/"+field]=rid;_expected["field/"+field]=native.fields[field]
	for field in native.spare:
		if field in ["momentum_x","momentum_z"]:continue
		images["spare/"+field]=state.textures[field][1];_expected["spare/"+field]=native.spare[field]
	for index in 2:
		var key: String="material/"+str(index);images[key]=state.textures.mold_support[index];_expected[key]=native.material["current_support" if index==0 else "spare_support"]
	for field in ["sand","water"]:images["published/"+field]=state.published_sand if field=="sand" else state.published_water;_expected["published/"+field]=native.fields[field]
	for field in views.FIELDS:
		images["view/"+field]=views.textures[field]
		if field=="baseline":var zero:=PackedByteArray();zero.resize(65536*4);_expected["view/"+field]=zero
		elif field=="momentum":_expected["view/"+field]=momentum.value
		else:_expected["view/"+field]=native.material.current_support if field=="mold_support" else native.fields[field]
	if state.surface_wetness.is_valid():
		images.surface_wetness=state.surface_wetness;_expected.surface_wetness=extensions.wet_sand_v1.state
	images.clock=transport.clock_texture;_expected.clock=native.control.slice(32,36)
	if visuals!=null and visuals.foam_enabled:
		for index in 2:
			for prefix in ["foam_","bed_"]:
				var key: String=prefix+str(index);images["visual/"+key]=visuals.images[key];_expected["visual/"+key]=native.foam[key]
		images["visual_view/foam"]=views.textures.foam;_expected["visual_view/foam"]=native.foam["foam_"+str(visuals.foam_index)]
	if visuals!=null and visuals.front_enabled:
		images["visual/local_front"]=visuals.images.local_front;_expected["visual/local_front"]=native.histories.local_front
		images["visual_view/local_front"]=views.textures.local_front;_expected["visual_view/local_front"]=native.histories.local_front
	if visuals!=null and visuals.gravel_enabled:
		for index in 2:
			var key: String="gravel_"+str(index);images["visual/"+key]=visuals.images[key];_expected["visual/"+key]=extensions.gravel_v1["state_"+str(index)]
		images["visual_view/gravel"]=views.textures.gravel;_expected["visual_view/gravel"]=extensions.gravel_v1["state_"+str(visuals.gravel_index)]
	var stamp:=PackedByteArray();stamp.resize(32)
	for pair in [[0,8],[8,16],[16,40],[24,24]]:stamp.encode_s64(pair[0],native.control.decode_s64(pair[1]))
	var zero_stroke:=PackedByteArray();zero_stroke.resize(64)
	var buffers:={"control":[transport.control,native.control],"publication_stamp":[state.published_stamp,stamp],"executor_stroke":[executor.buffers.stroke,zero_stroke],"view_stroke":[views.buffers.stroke,zero_stroke]}
	if visuals!=null and visuals.gravel_enabled:
		var active:=PackedByteArray();active.resize(4);active.encode_u32(0,extensions.gravel_v1.active_count)
		buffers.display_active_count=[visuals.gravel_meta,active]
	if boundary!=null and boundary.enabled:buffers.boundary_waves=[visuals.water.waves,boundary.encode_packets(boundary.packets())]
	for key in buffers:_expected[key]=buffers[key][1]
	for key in images:
		pending+=1
		var status: Error=ERR_UNAVAILABLE
		if inject_registration_failure_once:inject_registration_failure_once=false
		else:status=transport.rd.texture_get_data_async(images[key],0,_arrived.bind(key))
		if status!=OK:pending-=1;error=&"restore_readback_registration"
	for key in buffers:
		pending+=1
		if transport.rd.buffer_get_data_async(buffers[key][0],_arrived.bind(key),0,_expected[key].size())!=OK:pending-=1;error=&"restore_readback_registration"
	_submitting=false;_finish_if_complete()

func _arrived(bytes: PackedByteArray, key: String) -> void:
	if not _expected.has(key) or records.has(key) or held.has(key):return
	if hold_delivery:held[key]=bytes;return
	if inject_corruption_once:
		inject_corruption_once=false;bytes=bytes.duplicate()
		if not bytes.is_empty():bytes[0]^=1
	var expected: PackedByteArray=_expected[key]
	var matched:=bytes==expected
	records[key]={"bytes":bytes.size(),"expected_sha256":_sha(expected),"actual_sha256":_sha(bytes),"matched":matched}
	if capture_bytes:raw_fields[key]=bytes.duplicate()
	if not matched:error=&"restore_readback_mismatch"
	pending-=1;_finish_if_complete()

func release_held_render() -> void:
	hold_delivery=false
	var data:=held;held={}
	for key in data:_arrived(data[key],key)

func _finish_if_complete() -> void:
	if _submitting or pending!=0:return
	passed=error.is_empty() and records.size()==_expected.size()
	_expected.clear()
	var callback:=_callback;_callback=Callable();callback.call(error)

func _sha(bytes: PackedByteArray) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
