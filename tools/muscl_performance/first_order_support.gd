extends "res://tests/integration/water_execution_exact_probe.gd"

const Upload=preload("res://tools/muscl_performance/fixture_upload.gd")
var archive:=ZIPPacker.new()
var rows: Array=[]
var injections: Array=[]
var capture_index:=0

func probe_numerics(_spec: Dictionary) -> Dictionary:
	return Config.Numerics.selection(Config.Numerics.FIRST_ORDER,0.0)

func prepare_test_tick(_spec: Dictionary, iteration: int) -> void:
	var values:=PackedFloat32Array();values.resize(131072)
	if iteration in [0,2,4]:
		for pos: Vector2i in [Vector2i(7,7),Vector2i(8,8),Vector2i(248,248)]:
			var index:=pos.y*256+pos.x;values[index*2]=0.15;values[index*2+1]=0.4
	for rid in owner.state.textures.mold_support:
		var result:=Upload.r32_256(owner.state.rd,rid,values.to_byte_array(),RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,524288)
		check("first_order_support_upload",result.pass);injections.append({"iteration":iteration,"result":result})

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
	result.decision=owner.state.rd.buffer_get_data(owner.water.decision)
	result.accepted_indirect=owner.state.rd.buffer_get_data(owner.water.indirect)
	result.control=owner.state.rd.buffer_get_data(owner.transport.control)
	for name in owner.coupled.buffers:result["coupled_"+name]=owner.state.rd.buffer_get_data(owner.coupled.buffers[name])
	result.dirty=owner.state.rd.texture_get_data(owner.coupled.images.dirty,0)
	capture_received.call_deferred(result)

func capture_received(value: Dictionary) -> void:
	value.cpu_completion_and_ledger=var_to_bytes({"generation":owner._generation,"state_seq":owner.completed_state_seq,"sim_tick":owner.completed_tick,"revision":owner.completed_revision,"advanced_time_s":owner.advanced_time_s,"ledger":owner.ledger_snapshot()})
	var fields: Dictionary={}
	for name in value:
		var member: String="first_order/%02d/%s.bin"%[capture_index,name]
		check("zip_start",archive.start_file(member)==OK);check("zip_write",archive.write_file(value[name])==OK);check("zip_close",archive.close_file()==OK)
		fields[name]={"member":member,"bytes":value[name].size()}
	rows.append({"case":"first_order_support","capture":capture_index,"fields":fields});capture_index+=1
	super.capture_received(value)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output);check("archive_open",archive.open(output.path_join("states.zip"))==OK)
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=catalog.registry
	var states: Array=await fixture({"name":"first_order_support","retention":0.0,"boundary":false,"erosion":true,"momentum":0.15},false)
	check("five_states",states.size()==5);check("archive_close",archive.close()==OK)
	FileAccess.open(output.path_join("variant.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":rows,"injections":injections,"scope":"First-order shared-coupling support appear/disappear; complete double slots, control and ledger"},"\t"))
	quit(1 if failed else 0)
