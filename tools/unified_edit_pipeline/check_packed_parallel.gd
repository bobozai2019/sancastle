extends SceneTree
# Private old/new kernel comparison. No authority textures and no performance claim.
const GPU=preload("res://scripts/simulation/unified_edit/gpu.gd")
const Response=preload("res://scripts/simulation/unified_edit/water_response.gd")
var old=GPU.new()
var candidate=Response.new()
var old_buffers: Dictionary={}
var old_sets: Dictionary={}
var output:=""
var input_dir:=""
var ready:=false
var checks: Array=[]
var results: Dictionary={}
var rows: Array=[]
var pins: Dictionary={}
var failed:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--input-dir="):input_dir=arg.trim_prefix("--input-dir=")
	call_deferred("run")

func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"pass":ok});failed=failed or not ok
	print("PACKED_PAIR ",name," ",ok)

func setup_render() -> void:
	old.rd=RenderingServer.get_rendering_device();candidate.rd=old.rd
	for pair in [["input",65536*32],["candidate",65536*16],["scratch",65536*20],["receipt",128],["indirect",36],["components",16+32*96],["parallel_work",65536*48]]:
		var data:=PackedByteArray();data.resize(pair[1])
		if pair[0]=="indirect":
			for i in 9:data.encode_u32(i*4,1)
		candidate.buffers[pair[0]]=candidate.own(candidate.rd.storage_buffer_create(data.size(),data,RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT if pair[0]=="indirect" else 0))
		if pair[0] in ["input","candidate","scratch","receipt"]:old_buffers[pair[0]]=old.own(old.rd.storage_buffer_create(data.size(),data))
	var ok:=true
	for pair in [["packed",Response.SOURCES[5]],["packed_math",Response.SOURCES[6]],["displace",Response.SOURCES[2]]]:ok=candidate.compile(pair[0],pair[1]) and ok
	if ok:ok=candidate._initialize_packed_phases()
	for pair in [["packed",Response.SOURCES[3]],["displace",Response.SOURCES[2]]]:ok=old.compile(pair[0],pair[1]) and ok
	if ok:
		candidate.sets.packed=candidate.binding("packed",{0:candidate.buffers.input,1:candidate.buffers.candidate,2:candidate.buffers.scratch,3:candidate.buffers.receipt,4:candidate.buffers.components})
		candidate.sets.packed_math=candidate.binding("packed_math",{0:candidate.buffers.input,1:candidate.buffers.candidate,2:candidate.buffers.scratch,3:candidate.buffers.receipt,4:candidate.buffers.components,5:candidate.buffers.parallel_work})
		candidate.sets.displace=candidate.binding("displace",{0:candidate.buffers.input,1:candidate.buffers.candidate,2:candidate.buffers.scratch,3:candidate.buffers.receipt})
		for name in ["packed","displace"]:old_sets[name]=old.binding(name,{0:old_buffers.input,1:old_buffers.candidate,2:old_buffers.scratch,3:old_buffers.receipt})
	call_deferred("setup_done",ok,old.last_error+candidate.last_error)

func setup_done(ok: bool, error: String) -> void:
	check("compile_and_initialize",ok);if not error.is_empty():print(error)
	ready=true

func record_render(bytes: PackedByteArray, repeat_only: bool) -> void:
	var push:=PackedFloat32Array([0,0.125,0,0]).to_byte_array();push.encode_u32(0,256)
	candidate.rd.buffer_update(candidate.buffers.input,0,bytes.size(),bytes)
	if not repeat_only:
		old.rd.buffer_update(old_buffers.input,0,bytes.size(),bytes)
		old.dispatch("packed",old_sets.packed,Vector3i.ONE,push)
		push.encode_u32(12,2);old.dispatch("displace",old_sets.displace,Vector3i.ONE,push);push.encode_u32(12,0)
	candidate._legacy_dispatch("packed",push)
	push.encode_u32(12,2);candidate._legacy_dispatch("displace",push)
	for key in ["candidate","receipt"]:
		if not repeat_only:
			var error: int=old.rd.buffer_get_data_async(old_buffers[key],receive_render.bind("old_"+key))
			if error!=OK:call_deferred("read_error",error)
		var error: int=candidate.rd.buffer_get_data_async(candidate.buffers[key],receive_render.bind(("repeat_" if repeat_only else "new_")+key))
		if error!=OK:call_deferred("read_error",error)

func receive_render(bytes: PackedByteArray, key: String) -> void:call_deferred("receive",key,bytes)
func receive(key: String, bytes: PackedByteArray) -> void:results[key]=bytes
func read_error(error: int) -> void:check("read_registration_"+str(error),false)
func release_render() -> void:
	old_sets.clear();old_buffers.clear();old.release();candidate.release();call_deferred("released")
func released() -> void:ready=true

func run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Packed water exact numerical comparison")
	for path in Response.SOURCES+["res://tools/unified_edit_pipeline/check_packed_parallel.gd"]:pins[path]=FileAccess.get_sha256(path)
	RenderingServer.call_on_render_thread(setup_render)
	while not ready:await process_frame
	if not failed:
		var fixtures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input_dir.path_join("manifest.json")))
		for fixture in fixtures.cases:
			var path:=input_dir.path_join(fixture.file)
			check(fixture.name+"_input_hash",FileAccess.get_sha256(path)==fixture.sha256)
			var bytes:=FileAccess.get_file_as_bytes(path);results.clear()
			RenderingServer.call_on_render_thread(record_render.bind(bytes,false))
			var deadline:=Time.get_ticks_msec()+30000
			while results.size()<4 and not failed and Time.get_ticks_msec()<deadline:await process_frame
			check(fixture.name+"_readbacks",results.size()==4)
			if failed:break
			RenderingServer.call_on_render_thread(record_render.bind(bytes,true))
			deadline=Time.get_ticks_msec()+30000
			while results.size()<6 and not failed and Time.get_ticks_msec()<deadline:await process_frame
			check(fixture.name+"_repeat_readbacks",results.size()==6)
			if failed:break
			var row:={"name":fixture.name,"input":fixture,"outputs":{}}
			for key in results:
				var destination:=output.get_base_dir().path_join(fixture.name+"_"+key+".bin")
				var file:=FileAccess.open(destination,FileAccess.WRITE);file.store_buffer(results[key]);file.close()
				row.outputs[key]={"path":destination,"bytes":results[key].size(),"sha256":FileAccess.get_sha256(destination)}
			for key in ["candidate","receipt"]:
				check(fixture.name+"_exact_"+key,results["old_"+key]==results["new_"+key])
				check(fixture.name+"_repeat_"+key,results["new_"+key]==results["repeat_"+key])
			rows.append(row)
	ready=false;RenderingServer.call_on_render_thread(release_render)
	while not ready:await process_frame
	for path in pins:check("source_"+path,FileAccess.get_sha256(path)==pins[path])
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"cases":rows,"sources":pins,"engine":Engine.get_version_info(),"device":RenderingServer.get_video_adapter_name()},"\t"));file.close()
	quit(1 if failed else 0)
