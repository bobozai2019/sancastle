extends "res://tests/integration/unified_edit_display_probe.gd"

var preview: Dictionary={}
var queries: Array=[]

func _run() -> void:
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=catalog.registry;check("registry",catalog.error.is_empty())
	var sources:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES+[get_script().resource_path,"res://tests/integration/unified_edit_display_probe.gd","res://tests/integration/unified_edit_visuals_probe.gd","res://tests/integration/unified_edit_restore_probe.gd","res://tests/integration/unified_edit_gpu_probe.gd"])
	var frozen:=Config.freeze(registry,"main_beach",{"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false},{"foam_enabled":false,"gravel_enabled":true},{},{"gravel_profile":Pipeline.Visuals.Gravel.default_profile("main",0)},sources)
	check("configuration",frozen.error.is_empty());configuration=frozen.value;source_hashes=configuration.sources.duplicate(true)
	check("configure",pipeline.configure(registry,configuration,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.rock.fill(0.05);domain.sand.fill(0.25);domain.water.fill(0.1);domain.compaction.fill(0.3);domain.obstacle[176*256+176]=1
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain));var start:=Time.get_ticks_msec()
	while not pipeline.initialized and Time.get_ticks_msec()-start<25000:await process_frame
	check("ready",pipeline._ready)
	if not pipeline._ready:await shutdown_visuals();finish();return
	var query:=request(100,&"fill_v1",Vector2.ZERO)
	pipeline.views.hold_delivery=true;preview={}
	check("snapshot_admitted",pipeline.views.request_preview(query,_received,0,Pipeline.Views.Freshness.SNAPSHOT).accepted)
	await _held()
	check("edit_while_query_held",pipeline.submit_intent(request(1,&"fill_v1",Vector2.ZERO)).accepted)
	check("tick_while_query_held",pipeline.request_tick(0.001).is_empty());await await_idle()
	pipeline.views.deliver_held();await _reply("snapshot_behind")
	check("older_complete_snapshot_is_usable",preview.get("error",&"missing")==&"" and preview.state_seq==0 and preview.state_lag==2 and preview.advisory)
	check("snapshot_cache_not_invalidated_by_new_completion",not pipeline.views.last_preview.is_empty())
	pipeline.views.hold_delivery=true;preview={}
	check("strict_admitted",pipeline.views.request_preview(query,_received,pipeline.completed_state_seq).accepted);await _held()
	check("strict_later_tick",pipeline.request_tick(0.001).is_empty());await await_idle()
	pipeline.views.deliver_held();await _reply("strict_behind")
	check("default_strict_still_rejects_older",preview.get("error")==&"stale_preview_version")
	check("strict_does_not_expose_old_snapshot_cache",pipeline.views.last_preview.is_empty())
	preview={};check("future_minimum_admitted",pipeline.views.request_preview(query,_received,pipeline.completed_state_seq+1,Pipeline.Views.Freshness.SNAPSHOT).accepted);await _reply("future_minimum")
	check("snapshot_keeps_request_minimum",preview.get("error")==&"stale_preview_version")
	check("invalid_freshness_rejected",not pipeline.views.request_preview(query,_received,0,99).accepted)
	pipeline.views.hold_delivery=true;preview={};check("context_query",pipeline.views.request_preview(query,_received,0,Pipeline.Views.Freshness.SNAPSHOT).accepted);await _held()
	pipeline.views.invalidate_preview();pipeline.views.deliver_held();await _reply("superseded")
	check("snapshot_keeps_context_guard",preview.get("error")==&"preview_superseded")
	pipeline.views.inject_readback_failure_once=true;preview={}
	check("unknown_query_admitted",pipeline.views.request_preview(query,_received,pipeline.completed_state_seq,Pipeline.Views.Freshness.SNAPSHOT).accepted)
	start=Time.get_ticks_msec()
	while not pipeline.views._query.get("unknown",false) and Time.get_ticks_msec()-start<10000:await process_frame
	check("unknown_query_retains_buffer",pipeline.views.pending and preview.is_empty())
	check("unknown_query_does_not_block_tick",pipeline.request_tick(0.001).is_empty());await await_idle()
	pipeline.views.retry_preview_readback();await _reply("retry")
	check("retry_reads_original_snapshot",preview.get("error",&"missing")==&"" and preview.state_seq==3 and preview.state_lag==1)
	var before=await snapshot(pipeline,"before_readonly")
	preview={};check("obstacle_query",pipeline.views.request_preview(request(101,&"fill_v1",Vector2(6.0625,6.0625)),_received,pipeline.completed_state_seq,Pipeline.Views.Freshness.SNAPSHOT).accepted);await _reply("obstacle")
	check("actual_obstacle_count",preview.get("error",&"missing")==&"" and preview.obstacles==1 and preview.count>0)
	var after=await snapshot(pipeline,"after_readonly")
	for key in before:check("readonly_keeps_"+key,before[key].sha256==after[key].sha256)
	var identity:={"domain_id":"main_beach","generation":pipeline._generation,"command_id":2,"sim_tick":pipeline.completed_tick,"stroke_id":2,"baseline_token":2}
	check("begin_actual_stroke",pipeline.submit_control("begin",identity).accepted);await await_idle()
	var profile: Dictionary=registry.profile(&"wall_v1")
	var wall:={"domain_id":"main_beach","generation":pipeline._generation,"command_id":102,"sim_tick":pipeline.completed_tick,"profile_id":&"wall_v1","profile_version":1,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(2,0),"end_xz_m":Vector2(3,0),"parameters":{},"features":{"water_policy":0},"stroke_id":2,"baseline_token":2,"sample_index":0}
	preview={};check("baseline_query",pipeline.views.request_preview(wall,_received,pipeline.completed_state_seq,Pipeline.Views.Freshness.SNAPSHOT).accepted);await _reply("baseline")
	check("snapshot_uses_actual_published_baseline",preview.get("error",&"missing")==&"" and preview.uses_baseline)
	identity.command_id=3;check("end_actual_stroke",pipeline.submit_control("end",identity).accepted);await await_idle()
	observations.queries=queries;observations.before=before;observations.after=after
	await shutdown_visuals();finish()

func _received(value: Dictionary) -> void:preview=value
func _held() -> void:
	var start:=Time.get_ticks_msec()
	while pipeline.views.held.is_empty() and Time.get_ticks_msec()-start<10000:await process_frame
	check("actual_query_held_"+str(checks.size()),not pipeline.views.held.is_empty())
func _reply(label: String) -> void:
	var start:=Time.get_ticks_msec()
	while preview.is_empty() and Time.get_ticks_msec()-start<10000:await process_frame
	check("reply_"+label,not preview.is_empty())
	var row:=preview.duplicate(true)
	if row.has("raw"):
		row.raw=save_fields({"query":row.raw},label).query
	queries.append({"label":label,"result":row})
