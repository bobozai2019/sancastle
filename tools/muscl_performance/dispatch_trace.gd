extends "res://tools/muscl_performance/formal_states.gd"

# Correctness-only instrumented recorder. Every counter follows an actual RD
# call; each indirect argument is read immediately before its dispatch. These
# synchronous reads invalidate performance use of this process.
var traces: Array=[]
var trace_installed:=false
var trace_error:=""

func _initialize() -> void:
	super._initialize()
	ticks=2

func install_trace_render() -> void:
	var source:=FileAccess.get_file_as_string("res://scripts/simulation/unified_edit/water_muscl.gd")
	var replacements:={"func record_tick(requested_dt: float) -> void:":"func record_tick(requested_dt: float) -> void:\n\ttrace_rows=[]", "var list:=rd.compute_list_begin()":"trace_pending_indirect=rd.buffer_get_data(stage.indirect,stage.offset,12) if stage.indirect_dispatch else PackedByteArray()\n\t\tvar list:=rd.compute_list_begin()","rd.compute_list_dispatch_indirect(list,stage.indirect,stage.offset)":"trace_indirect(list,stage.indirect,stage.offset,stage.diagnostic_label)","rd.compute_list_dispatch(list,stage.groups.x,stage.groups.y,stage.groups.z)":"trace_direct(list,stage.groups,stage.diagnostic_label)"}
	for token in replacements:
		if source.count(token)!=1:trace_error="trace_token_count:"+token;trace_ready.call_deferred();return
		source=source.replace(token,replacements[token])
	source+='''
var trace_rows: Array=[]
var trace_pending_indirect:=PackedByteArray()
func trace_direct(list: int, groups: Vector3i, label: String) -> void:
	rd.compute_list_dispatch(list,groups.x,groups.y,groups.z)
	trace_rows.append({"kind":"direct","label":label,"groups":[groups.x,groups.y,groups.z],"nonzero":groups.x>0 and groups.y>0 and groups.z>0})
func trace_indirect(list: int, args: RID, offset: int, label: String) -> void:
	var raw:=trace_pending_indirect
	rd.compute_list_dispatch_indirect(list,args,offset)
	trace_rows.append({"kind":"indirect","label":label,"offset":offset,"groups":[raw.decode_u32(0),raw.decode_u32(4),raw.decode_u32(8)],"nonzero":raw.decode_u32(0)>0 and raw.decode_u32(4)>0 and raw.decode_u32(8)>0})
'''
	var script:=GDScript.new();script.source_code=source
	if script.reload()!=OK:trace_error="trace_compile";trace_ready.call_deferred();return
	var old=owner.water.muscl;var recorder=script.new()
	for name in ["water","rd","images","buffers","sets"]:recorder.set(name,old.get(name))
	owner.water.muscl=recorder;old.water=null
	FileAccess.open(output.path_join("trace_source.txt"),FileAccess.WRITE).store_string(source)
	trace_ready.call_deferred()

func trace_ready() -> void:trace_installed=true

func before_tick(_tick: int) -> void:
	if trace_installed:return
	RenderingServer.call_on_render_thread(install_trace_render)
	while not trace_installed:await process_frame
	check("trace_compiled:"+trace_error,trace_error.is_empty())

func capture_render() -> void:
	var recorder=owner.water.muscl
	var callback_count:=0
	for stage in recorder._recording:
		if stage.callback_kind!=0:callback_count+=1
	var rows: Array=recorder.get("trace_rows")
	# sim_finish is the unconditional _dispatch call after this loop; boundary
	# callbacks are kept separate from counted direct/indirect RD loop calls.
	traces.append({"tick":owner.completed_tick,"descriptors":recorder._recording.size(),"loop_dispatch_calls":rows.size(),"nonzero_loop_calls":rows.filter(func(row):return row.nonzero).size(),"callback_descriptors":callback_count,"standard_coupling":recorder._standard_coupling,"sim_finish_calls":1,"boundary_calls":1 if owner.water.boundary_enabled else 0,"rows":rows.duplicate(true),"scope":"Instrumented loop calls and current indirect argument bytes; tail/render excluded; not performance data"})
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"traces":traces,"trace_source_sha256":FileAccess.get_sha256(output.path_join("trace_source.txt")),"trace_error":trace_error},"\t"))
	super.capture_render()
