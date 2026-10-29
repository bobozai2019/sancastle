extends "res://tools/muscl_performance/formal_states.gd"

var queries: Array=[]
var query_result: Dictionary={}
var inventory: Array=[]
var initial_snapshot:=false

func _initialize() -> void:
	super._initialize()
	ticks=2

func query_arrived(value: Dictionary) -> void:query_result=value

func inspect_render() -> void:
	var unique:={};var items: Array=[]
	for group in [["authority",owner.state.textures],["views",owner.views.textures]]:
		for name in ["momentum_x","momentum_z","momentum"]:
			if not group[1].has(name):continue
			var value=group[1][name]
			for rid in (value if value is Array else [value]):
				check("momentum_rid_unique",not unique.has(rid));unique[rid]=true
				var format: RDTextureFormat=owner.state.rd.texture_get_format(rid)
				items.append({"owner":group[0],"field":name,"rid":rid.get_id(),"format":format.format,"width":format.width,"height":format.height,"bytes":owner.state.rd.texture_get_data(rid,0).size()})
	call_deferred("inventory_arrived",items)

func inventory_arrived(items: Array) -> void:inventory=items

func before_tick(tick: int) -> void:
	if tick==0:
		capture_done=false;RenderingServer.call_on_render_thread(capture_render)
		while not capture_done:await process_frame
		initial_snapshot=true
		RenderingServer.call_on_render_thread(inspect_render)
		while inventory.is_empty():await process_frame
		var expected:=3 if owner.state.textures.has("momentum") else 6
		check("actual_momentum_resource_count",inventory.size()==expected)
		check("same_logical_payload",inventory.reduce(func(total,item):return total+item.bytes,0)==1572864)
		for binding in beach.material_bindings:
			for parameter in binding.parameters:
				var field: String=binding.parameters[parameter]
				var texture: Texture2DRD=binding.material.get_shader_parameter(parameter)
				check("actual_material_wrapper:"+str(parameter),texture!=null and texture.texture_rd_rid==owner.views.textures[field])
	var held_tick: int=owner.completed_tick;var held_time: float=owner.advanced_time_s
	for frame in 4:await process_frame
	check("frozen_completed_identity",owner.completed_tick==held_tick and owner.advanced_time_s==held_time and not beach.playing)
	if scene_path=="res://scenes/main.tscn":
		# Main's floating props already own the shared Probe context. Keep their
		# ownership; explicit numerical queries are tested in test1_geometry.
		write_report();return
	query_result={}
	var request:={"request_id":tick+1,"owner_token":1,"generation":owner._generation,"pose_seq":1,"domain_id":owner._configuration.domain_id,"minimum_state_seq":owner.completed_state_seq,"points":[{"body_id":1,"point_id":1,"position":Vector3(0.0625,0.0,0.0625)}],"footprints":[Rect2(-1,-1,2,2)]}
	var admitted: Dictionary=owner.views.request_probe(request,query_arrived)
	check("query_admitted",admitted.accepted)
	if not admitted.accepted:write_report();return
	var deadline:=Time.get_ticks_msec()+30000
	while query_result.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("query_arrived",not query_result.is_empty())
	if query_result.is_empty():write_report();return
	check("query_completed_identity",query_result.error.is_empty() and query_result.captured_time_s==owner.advanced_time_s and query_result.captured_state_seq==owner.completed_state_seq and query_result.captured_tick==owner.completed_tick and query_result.captured_revision==owner.completed_revision)
	# Same exact cell as native_restart_probe: world +0.0625 maps to (128,128).
	if query_result.error.is_empty():
		var x: PackedByteArray;var z: PackedByteArray
		if captured.has("momentum_0"):
			var split:=Upload.Momentum.split(captured.momentum_0);x=split.momentum_x;z=split.momentum_z
		else:x=captured.momentum_x_0;z=captured.momentum_z_0
		var i:=128*256+128;var h: float=captured.water_0.decode_float(i*4)
		var bed: float=captured.rock.decode_float(i*4)+captured.sand_0.decode_float(i*4)
		var q:=Vector2(x.decode_float(i*4),z.decode_float(i*4))
		var point: Dictionary=query_result.points[0]
		var velocity:=q/maxf(h,0.005) if h>0.001 else Vector2.ZERO
		check("query_matches_completed_state",absf(point.h-h)<2e-6 and absf(point.bed-bed)<2e-6 and (point.u_xz-velocity).length()<2e-5)
	queries.append(query_result.duplicate(true))
	write_report()

func write_report() -> void:
	var materials: Array=[]
	for binding in beach.material_bindings:materials.append({"shader":binding.material.shader.resource_path,"fields":binding.parameters})
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"queries":queries,"momentum_inventory":inventory,"materials":materials,"initial_snapshot":initial_snapshot,"scene":scene_path,"scope":"Actual authority/publication RID formats, initial and completed Probe, frozen state, actual material Texture2DRD mappings; no cost claim"},"\t"))
