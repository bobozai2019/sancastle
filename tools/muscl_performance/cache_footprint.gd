extends "res://tests/integration/water_execution_exact_probe.gd"

var memory_rows: Array=[]
var last_owner
var coupled_enabled:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--case=coupled":coupled_enabled=true
	super._initialize()

func memory_render(label: String) -> void:
	var device:=RenderingServer.get_rendering_device()
	memory_received.call_deferred({"label":label,"texture_bytes":device.get_memory_usage(RenderingDevice.MEMORY_TEXTURES),"buffer_bytes":device.get_memory_usage(RenderingDevice.MEMORY_BUFFERS)})

func memory_received(row: Dictionary) -> void:memory_rows.append(row)

func capture_render() -> void:
	var device: RenderingDevice=owner.state.rd
	var unique: Dictionary={};var inventory: Array=[];var payload:=0
	var bpp:={RenderingDevice.DATA_FORMAT_R32_SFLOAT:4,RenderingDevice.DATA_FORMAT_R32G32_SFLOAT:8,RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:16,RenderingDevice.DATA_FORMAT_R16_SFLOAT:2,RenderingDevice.DATA_FORMAT_R8_UNORM:1,RenderingDevice.DATA_FORMAT_R32_UINT:4}
	for group in [["state",owner.state.textures],["muscl",owner.water.muscl.images],["coupled",owner.coupled.images],["views",owner.views.textures],["publication",{"sand":owner.state.published_sand,"water":owner.state.published_water}],["visuals",owner.visuals.images],["visual_published",owner.visuals.published]]:
		for name in group[1]:
			var value=group[1][name]
			for rid in (value if value is Array else [value]):
				if unique.has(rid):continue
				unique[rid]=true
				var fmt: RDTextureFormat=device.texture_get_format(rid)
				var bytes: int=fmt.width*fmt.height*int(bpp.get(fmt.format,0));payload+=bytes
				inventory.append({"rid_id":rid.get_id(),"owner_group":group[0],"name":name,"format":fmt.format,"width":fmt.width,"height":fmt.height,"payload_bytes":bytes})
	memory_received.call_deferred({"label":"live","texture_bytes":device.get_memory_usage(RenderingDevice.MEMORY_TEXTURES),"buffer_bytes":device.get_memory_usage(RenderingDevice.MEMORY_BUFFERS),"owners":owner.ownership_counts(),"solver_coupled_texture_objects":unique.size(),"logical_texture_payload":payload,"inventory":inventory,"shader_programs":{"state":owner.state.kernels.keys(),"water":owner.water.kernels.keys(),"coupled":owner.coupled.kernels.keys()},"dispatch_descriptors":owner.water.muscl._recording.size(),"inventory_scope":"State + MUSCL + Coupled + Views + state publication + Visuals, deduplicated by actual RID. Material wrappers borrow Views RIDs; engine render targets remain outside inventory. RD totals are separate. RD totals are separate."})
	super.capture_render()

func capture_received(value: Dictionary) -> void:
	last_owner=owner
	super.capture_received(value)

func run() -> void:
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=catalog.registry
	RenderingServer.call_on_render_thread(memory_render.bind("before"))
	while memory_rows.is_empty():await process_frame
	var spec:={"name":"footprint","retention":0.0,"boundary":false,"erosion":coupled_enabled,"momentum":0.0}
	var states: Array=await fixture(spec,false)
	check("state_count",states.size()==5)
	check("all_owners_released",last_owner!=null and last_owner.released and last_owner.ownership_counts().values().all(func(v):return v==0))
	for i in 3:await process_frame
	var count:=memory_rows.size()
	RenderingServer.call_on_render_thread(memory_render.bind("after_release"))
	while memory_rows.size()==count:await process_frame
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("footprint.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"memory":memory_rows,"engine":Engine.get_version_info(),"scope":"Actual RenderingDevice-accounted texture/buffer bytes and owned RID release. Driver physical residency is not inferred."},"\t"))
	last_owner=null
	quit(1 if failed else 0)
