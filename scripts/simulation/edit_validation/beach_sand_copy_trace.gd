extends RefCounted
var records := []
var pending := 0
var data := {}

func capture(solver, tick: int) -> void:
	var rid: RID=solver._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray())
	assert(rid.is_valid())
	assert(solver.rd.texture_copy(solver.current_texture("sand"),rid,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)==OK)
	records.append({"tick":tick,"revision":solver.state_revision,"index":solver.current_index,"rid":rid})

func read(owner, solver, callback_method: StringName=&"_sand_trace_record") -> void:
	for record in records:
		pending+=1
		assert(solver.rd.texture_get_data_async(record.rid,0,_on_data.bind(owner,record.get("key",record.tick),callback_method))==OK)

func _on_data(bytes: PackedByteArray, owner, key: Variant, callback_method: StringName) -> void: owner.call_deferred(callback_method,bytes,key)

func record_data(bytes: PackedByteArray, key: Variant) -> void:
	data[key]=bytes;pending-=1

func capture_native(owner, tick: int) -> void:
	var solver=owner.solver
	var formats: Dictionary={"rock":RenderingDevice.DATA_FORMAT_R32_SFLOAT,"sand":RenderingDevice.DATA_FORMAT_R32_SFLOAT,"water":RenderingDevice.DATA_FORMAT_R32_SFLOAT,"momentum_x":RenderingDevice.DATA_FORMAT_R32_SFLOAT,"momentum_z":RenderingDevice.DATA_FORMAT_R32_SFLOAT,"sediment":RenderingDevice.DATA_FORMAT_R32_SFLOAT,"wetness":RenderingDevice.DATA_FORMAT_R16_SFLOAT,"compaction":RenderingDevice.DATA_FORMAT_R16_SFLOAT,"obstacle":RenderingDevice.DATA_FORMAT_R8_UNORM,"flux":RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT}
	for field in formats:
		_copy(solver,solver.current_texture(field),formats[field],"tick_%d_fields_%s"%[tick,field])
		if field not in ["rock","obstacle"]: _copy(solver,solver.textures[field][1-solver.current_index],formats[field],"tick_%d_spare_%s"%[tick,field])
	for index in 2:
		_copy(solver,owner.foam_field.textures[index],RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,"tick_%d_foam_%d"%[tick,index])
		_copy(solver,owner.foam_field.bed_textures[index],RenderingDevice.DATA_FORMAT_R32_SFLOAT,"tick_%d_bed_%d"%[tick,index])
	_copy(solver,owner.local_front_field.texture,RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,"tick_%d_front"%tick)

func _copy(solver, source: RID, format: int, key: String) -> void:
	var rid: RID=solver._create_texture(format,PackedByteArray())
	assert(rid.is_valid())
	assert(solver.rd.texture_copy(source,rid,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)==OK)
	records.append({"tick":-1,"key":key,"rid":rid})

func release(solver) -> void:
	assert(pending==0)
	for record in records: solver.rd.free_rid(record.rid)
	records.clear()
