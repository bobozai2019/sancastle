extends SceneTree

# Compare the retained numerical recorder with an exact pre-change source
# snapshot supplied by the runner. Both use real independent GPU resources.
const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
var output:=""
var reference_root:=""
var checks: Array=[]
var observations: Array=[]
var failed:=false
var owner
var fields: Dictionary={}
var remaining:=0
var registry
var reference_water: GDScript
var reference_coupled: GDScript
var source_hashes: Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--reference-root="):reference_root=arg.trim_prefix("--reference-root=")
	call_deferred("_run")

func check(label: String, ok: bool) -> void:
	checks.append({"name":label,"pass":ok});failed=failed or not ok
	print("RECORDING_CACHE ",label," ",ok)

func _process(_dt: float) -> bool:
	if owner!=null:owner.pump()
	return false

func _arrived(bytes: PackedByteArray, name: String) -> void:call_deferred("_stored",bytes,name)
func _stored(bytes: PackedByteArray, name: String) -> void:fields[name]=bytes;remaining-=1
func _capture() -> void:
	for name in owner.state.textures:
		var value: Variant=owner.state.textures[name]
		if value is Array:
			for index in value.size():owner.state.rd.texture_get_data_async(value[index],0,_arrived.bind(name+"_"+str(index)))
		else:owner.state.rd.texture_get_data_async(value,0,_arrived.bind(name))
	owner.state.rd.buffer_get_data_async(owner.water.decision,_arrived.bind("decision"))
	owner.state.rd.buffer_get_data_async(owner.transport.control,_arrived.bind("control"))

func _reference_script(name: String, methods: Array) -> GDScript:
	# Keep the current resource-owner type; replace only the recording methods
	# with their exact saved bodies. Initialization/resources are common.
	var saved:=FileAccess.get_file_as_string(reference_root.path_join(name+".gd"))
	var source:="extends \"res://scripts/simulation/unified_edit/"+name+".gd\"\n"
	for method in methods:
		var start:=saved.find("\nfunc "+method+"(")
		check("reference_method_"+method,start>=0)
		if start<0:return null
		var end:=saved.find("\nfunc ",start+1)
		source+=saved.substr(start,saved.length()-start if end<0 else end-start)+"\n"
	var script:=GDScript.new();script.source_code=source
	check("reference_compile_"+name,script.reload()==OK)
	return script

func _fixture(desired: int, boundary: bool, serial: bool) -> Dictionary:
	owner=Pipeline.new()
	if serial:
		owner.water=reference_water.new()
		owner.coupled=reference_coupled.new()
	var environment:={"engine":Engine.get_version_info().string,"probe":"recording_cache"}
	if boundary:environment.boundary=Pipeline.Boundary.for_scene("main_beach")
	var simulation:={"enable_erosion":true,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},environment,PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES))
	check("freeze_"+str(checks.size()),frozen.error.is_empty())
	if source_hashes.is_empty():source_hashes=frozen.value.sources.duplicate(true)
	check("configure_"+str(checks.size()),owner.configure(registry,frozen.value,1).is_empty())
	var domain:=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=1
	domain.sand.fill(0.4);domain.water.fill(0.1)
	var qx:=PackedFloat32Array();qx.resize(65536)
	qx.fill(maxf(0.0,(float(desired)-0.25)*0.35*0.125/0.001-sqrt(9.81*0.1))*0.1)
	domain.set_meta("edit_validation_initial_qx",qx)
	var tags:=PackedFloat32Array();tags.resize(65536)
	for z in range(96,160):
		for x in range(96,160):
			var i:=z*256+x
			domain.sand[i]+=0.04*sin(float(x)*0.2)*cos(float(z)*0.17)
			domain.sediment[i]=0.001;domain.wetness[i]=0.3;domain.compaction[i]=0.95;tags[i]=0.15
	domain.set_meta("brush_initial_mold_depth",tags)
	RenderingServer.call_on_render_thread(owner.initialize_render.bind(domain))
	var deadline:=Time.get_ticks_msec()+30000
	while not owner.initialized and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("initialize_"+str(checks.size()),owner.initialized and owner.fault_reason().is_empty())
	if not owner.initialized:return {}
	check("tick_"+str(checks.size()),owner.request_tick(0.001).is_empty())
	while (owner.pending_count()>0 or owner.active_count()>0) and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("completed_"+str(checks.size()),owner.completed_tick==1 and owner.fault_reason().is_empty())
	fields={};remaining=2
	for value in owner.state.textures.values():remaining+=value.size() if value is Array else 1
	RenderingServer.call_on_render_thread(_capture)
	while remaining>0 and Time.get_ticks_msec()<deadline:await process_frame
	check("capture_"+str(checks.size()),remaining==0 and fields.has("decision"))
	var result:=fields.duplicate(true)
	owner.close_admission();RenderingServer.call_on_render_thread(owner.release_render)
	while not owner.released and Time.get_ticks_msec()<deadline:await process_frame
	check("released_"+str(checks.size()),owner.released)
	owner=null
	return result

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,720))
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry
	check("reference_present",FileAccess.file_exists(reference_root.path_join("water.gd")) and FileAccess.file_exists(reference_root.path_join("coupled.gd")))
	if not failed:
		reference_water=_reference_script("water",["_dispatch","record_tick"])
		reference_coupled=_reference_script("coupled",["_static","record"])
	if not failed:
		for fixture in [[1,false],[2,false],[3,false],[64,false],[65,false],[3,true]]:
			var before: Dictionary=await _fixture(fixture[0],fixture[1],true)
			var after: Dictionary=await _fixture(fixture[0],fixture[1],false)
			var differences: Array=[];var hashes:={}
			for name in before:
				if not after.has(name) or before[name]!=after[name]:differences.append(name)
				var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(before[name]);hashes[name]=hash.finish().hex_encode()
			check("exact_bytes_"+str(fixture),not before.is_empty() and before.size()==after.size() and differences.is_empty())
			var decision: PackedByteArray=after.get("decision",PackedByteArray())
			if not fixture[1]:check("cfl_count_"+str(fixture[0]),decision.size()==64 and decision.decode_u32(4)==mini(64,fixture[0]))
			observations.append({"fixture":fixture,"fields":hashes,"differences":differences,"steps":decision.decode_u32(4) if decision.size()==64 else -1})
	var unchanged:=not source_hashes.is_empty()
	for path in source_hashes:unchanged=unchanged and FileAccess.get_sha256(path)==source_hashes[path]
	check("source_identity_unchanged",unchanged)
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"source_hashes":source_hashes,"probe_sha256":FileAccess.get_sha256(get_script().resource_path),"reference_root":reference_root,"reference_water_sha256":FileAccess.get_sha256(reference_root.path_join("water.gd")),"reference_coupled_sha256":FileAccess.get_sha256(reference_root.path_join("coupled.gd")),"scope":"Exact raw GPU bytes, including both field slots, CFL decision and control; erosion, molded material, odd/even/max/overload steps and prescribed boundary. Timing is not measured here."},"\t"))
	quit(1 if failed else 0)
