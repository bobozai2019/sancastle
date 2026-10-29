extends "res://tests/integration/water_execution_exact_probe.gd"

# Each process constructs its own full pipelines/bindings. No foreign shaders
# are installed into another variant's private uniform layout.
var variant_rows: Array=[]
var state_zip:=ZIPPacker.new()
var case_name:=""
var capture_index:=0
var retry_cases_only:=false
const Upload=preload("res://tools/muscl_performance/fixture_upload.gd")
var injections: Array=[]
var observe:=false
var structures: Array=[]
const Observer=preload("res://tools/muscl_performance/diagnostic.gd")

func upload_field(name: String, slot: int, bytes: PackedByteArray, iteration: int) -> void:
	var result:=Upload.field_upload(owner.state.rd,owner.state.textures,name,slot,bytes)
	check("fixture_upload_verified:"+case_name+":"+name,result.pass)
	injections.append({"case":case_name,"iteration":iteration,"field":name,"result":result})

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--retry-cases-only":retry_cases_only=true
		if arg=="--case=observe":observe=true
	super._initialize()

func prepare_test_tick(spec: Dictionary, iteration: int) -> void:
	super.prepare_test_tick(spec,iteration)
	var rd: RenderingDevice=owner.state.rd
	if observe and owner.water.muscl.diagnostic==null:
		var observer:=Observer.new()
		check("observer_initialized",observer.initialize(rd));observer.stride=1;observer.enabled=true
		owner.water.muscl.diagnostic=observer
	if spec.name=="support_transitions":
		var values:=PackedFloat32Array();values.resize(131072)
		if iteration in [0,2,4]:
			for pos in [Vector2i(7,7),Vector2i(8,8),Vector2i(248,248)]:
				var i: int=pos.y*256+pos.x
				values[i*2]=0.15;values[i*2+1]=0.4
		for rid in owner.state.textures.mold_support:
			var result:=Upload.r32_256(rd,rid,values.to_byte_array(),RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,524288)
			check("support_upload_verified",result.pass)
			injections.append({"case":case_name,"iteration":iteration,"field":"mold_support","result":result})
	if spec.name=="poison_cache":
		# A disposable cache may contain arbitrary previous-tick data. New-tick
		# mode 0 must ignore it, including when the authoritative input changed.
		if owner.water.muscl.buffers.has("retry_cache"):
			rd.buffer_update(owner.water.muscl.buffers.retry_cache,0,16,PackedInt32Array([1,1,123,456]).to_byte_array())
		if iteration>0:
			for slot in 2:
				var bytes:=Upload.field_read(rd,owner.state.textures,"water",slot)
				bytes.encode_float((128*256+128)*4,0.03+float(iteration)*0.01)
				upload_field("water",slot,bytes,iteration)
	if spec.name in ["retry_chain","capacity_resume"] and iteration==0:
		for name in ["sand","water","momentum_x","momentum_z","sediment"]:
			var values:=PackedFloat32Array();values.resize(65536)
			for z in 256:
				for x in 256:
					values[z*256+x]=(0.4+float(x)*2.0 if spec.name=="retry_chain" else 0.4) if name=="sand" else ((0.005 if spec.name=="retry_chain" else 1000.0) if name=="water" else 0.0)
			for slot in 2:upload_field(name,slot,values.to_byte_array(),iteration)
	if not spec.name.begins_with("mixed_dry") or iteration!=0:return
	for name in ["water","momentum_x","momentum_z","sediment"]:
		for slot in 2:
			var bytes:=Upload.field_read(rd,owner.state.textures,name,slot)
			for z in 256:
				for x in 128:bytes.encode_float((z*256+x)*4,0.0)
			upload_field(name,slot,bytes,iteration)

func capture_render() -> void:
	var result: Dictionary={}
	for name in owner.state.textures:
		var value=owner.state.textures[name]
		if value is Array:
			for i in value.size():result[name+"_"+str(i)]=owner.state.rd.texture_get_data(value[i],0)
		else:result[name]=owner.state.rd.texture_get_data(value,0)
	for name in owner.views.FIELDS:result["view_"+name]=owner.state.rd.texture_get_data(owner.views.textures[name],0)
	result.published_sand=owner.state.rd.texture_get_data(owner.state.published_sand,0)
	result.published_water=owner.state.rd.texture_get_data(owner.state.published_water,0)
	result.published_stamp=owner.state.rd.buffer_get_data(owner.state.published_stamp)
	result.completed_clock=owner.state.rd.texture_get_data(owner.transport.clock_texture,0)
	if owner.state.surface_wetness.is_valid():result.surface_wetness=owner.state.rd.texture_get_data(owner.state.surface_wetness,0)
	for group in [["visual",owner.visuals.images],["visual_published",owner.visuals.published],["vegetation",owner.visuals.vegetation.images],["vegetation_published",owner.visuals.vegetation.published],["splash",owner.visuals.splash.images],["splash_published",owner.visuals.splash.published]]:
		for name in group[1]:result[group[0]+"_"+name]=owner.state.rd.texture_get_data(group[1][name],0)
	if owner.visuals.gravel_meta.is_valid():result.visual_gravel_meta=owner.state.rd.buffer_get_data(owner.visuals.gravel_meta)
	result.decision=owner.state.rd.buffer_get_data(owner.water.decision)
	result.accepted_indirect=owner.state.rd.buffer_get_data(owner.water.indirect)
	result.control=owner.state.rd.buffer_get_data(owner.transport.control)
	for name in owner.water.muscl.buffers:result["muscl_"+name]=owner.state.rd.buffer_get_data(owner.water.muscl.buffers[name])
	for name in owner.coupled.buffers:result["coupled_"+name]=owner.state.rd.buffer_get_data(owner.coupled.buffers[name])
	if owner.coupled.images.has("dirty"):result.coupled_dirty=owner.state.rd.texture_get_data(owner.coupled.images.dirty,0)
	var labels: Array=[]
	for stage in owner.water.muscl._recording:labels.append(stage.diagnostic_label)
	structures.append({"case":case_name,"capture":capture_index,"dispatch_descriptors":labels.size(),"labels":labels,"private_images":owner.water.muscl.images.keys(),"standard_callable":owner.water.coupled_recorder==Callable(owner.coupled,"record")})
	capture_received.call_deferred(result)

func capture_received(value: Dictionary) -> void:
	value.cpu_completion_and_ledger=var_to_bytes({"generation":owner._generation,"state_seq":owner.completed_state_seq,"sim_tick":owner.completed_tick,"revision":owner.completed_revision,"advanced_time_s":owner.advanced_time_s,"ledger":owner.ledger_snapshot()})
	var fields: Dictionary={}
	for name in value:
		var path: String="%s/%02d/%s.bin"%[case_name,capture_index,name]
		check("zip_start",state_zip.start_file(path)==OK)
		check("zip_write",state_zip.write_file(value[name])==OK)
		check("zip_close",state_zip.close_file()==OK)
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(value[name])
		fields[name]={"member":path,"bytes":value[name].size(),"sha256":hash.finish().hex_encode()}
	var d: PackedByteArray=value.decision
	var audit: PackedByteArray=value.muscl_audit
	var sequence: Array=[]
	for slot in 64:
		sequence.append("accepted" if audit.decode_u32(slot*32+8)!=0 else ("rejected" if audit.decode_u32(slot*32+4)!=0 and audit.decode_u32(slot*32+16)!=0 else "invalid"))
	var row:={"case":case_name,"capture":capture_index,"fields":fields,"accepted":d.decode_u32(4),"rejected":d.decode_u32(40),"status":d.decode_u32(16),"advanced_s":d.decode_float(12),"sequence":sequence}
	if case_name=="retry_chain" and capture_index==0:
		var run_length:=0;var longest:=0
		for s in sequence:
			run_length=run_length+1 if s=="rejected" else 0;longest=maxi(longest,run_length)
		check("real_consecutive_rejections",longest>=2)
	if case_name=="capacity_resume" and capture_index==0:check("capacity_really_exhausted",row.status==1 and row.accepted+row.rejected==64)
	if value.has("muscl_retry_cache"):
		var c: PackedByteArray=value.muscl_retry_cache
		row.cache={"valid":c.decode_u32(0),"enabled":c.decode_u32(4),"hits":c.decode_u32(8),"misses":c.decode_u32(12)}
		check("cache_hits_bound",row.cache.hits<=row.rejected)
		check("accepted_end_invalidates",row.status!=0 or row.cache.valid==0)
		check("disabled_cache_never_hits",row.cache.enabled!=0 or row.cache.hits==0)
	variant_rows.append(row);capture_index+=1
	super.capture_received(value)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	check("zip_open",state_zip.open(output.path_join("states.zip"))==OK)
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=catalog.registry
	var specs: Array=[{"name":"still","retention":0.0,"boundary":false,"erosion":false,"momentum":0.0},{"name":"coupled","retention":0.0,"boundary":false,"erosion":true,"momentum":0.1},{"name":"retention","retention":1.0,"boundary":false,"erosion":true,"momentum":0.3},{"name":"boundary","retention":0.5,"boundary":true,"erosion":true,"momentum":0.1},{"name":"high_velocity","retention":0.0,"boundary":false,"erosion":true,"momentum":100.0},{"name":"dry","retention":0.0,"boundary":false,"erosion":false,"momentum":0.0},{"name":"obstacle","retention":1.0,"boundary":false,"erosion":true,"momentum":0.3},{"name":"capacity","retention":0.5,"boundary":false,"erosion":true,"momentum":0.3}]
	for retention in [0.0,0.5,1.0]:specs.append({"name":"mixed_dry_"+str(retention),"retention":retention,"boundary":true,"erosion":true,"momentum":0.15})
	specs.append({"name":"support_transitions","retention":0.5,"boundary":false,"erosion":true,"momentum":0.1})
	if retry_cases_only:specs=[]
	for name in ["retry_chain","poison_cache","capacity_resume"]:specs.append({"name":name,"retention":1.0,"boundary":false,"erosion":false,"momentum":0.0})
	for spec in specs:
		case_name=spec.name;capture_index=0
		var states: Array=await fixture(spec,false)
		check(spec.name+"_state_count",states.size()==(1 if spec.name=="capacity" else 5))
		if failed:break
	check("zip_finish",state_zip.close()==OK)
	FileAccess.open(output.path_join("variant.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":variant_rows,"injections":injections,"structures":structures,"observer":observe,"engine":Engine.get_version_info(),"scope":"Single independently initialized variant; verified GPU input copies; byte equality is checked between archived ZIP members by compare_variant_states.py"},"\t"))
	quit(1 if failed else 0)
