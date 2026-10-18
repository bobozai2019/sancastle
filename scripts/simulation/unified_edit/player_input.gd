extends RefCounted

# A declaration adapter only: common Runtime owns recording, publication and
# results. BEGIN, samples and END may all enter the queue before any receipt.
const I=preload("res://scripts/simulation/unified_edit/intent.gd")
var runtime
var registry
var domain_id: StringName
var gesture: Dictionary={}
var waiting: Array[Dictionary]=[]
var terminal: Array[Dictionary]=[]
var end_requested:=""
var last_error: StringName=&""

func configure(owner, catalog, domain: StringName) -> void:
	runtime=owner;registry=catalog;domain_id=domain

func _id() -> Dictionary:return I.next_identity(runtime.highwater())
func _tick() -> int:return runtime.current.completed_tick
func _remember(value: Dictionary) -> Dictionary:
	last_error=value.get("error",&"")
	if value.get("accepted",false):waiting.append({"generation":runtime.generation(),"id":value.command_id})
	return value

func begin(tool: StringName, point: Vector2, parameters: Dictionary, amount: float, policy: int, speed: float) -> Dictionary:
	if not gesture.is_empty():return {"accepted":false,"error":&"stroke_busy"}
	if tool==&"gravel_drop":
		gesture={"tool":tool,"last":point,"parameters":parameters.duplicate(true),"stroke_id":0,"sample":0,"generation":runtime.generation()}
		return _sample(point,false)
	var profile_id:=_profile_id(tool,false)
	var profile: Dictionary=registry.profile(profile_id)
	if profile.is_empty():return {"accepted":false,"error":&"invalid_profile"}
	var stroke_id:=0
	if profile.stroke_policy!=0:
		var next:=_id()
		if not next.error.is_empty():return {"accepted":false,"error":next.error}
		stroke_id=next.value
		var result:=_control("begin",stroke_id)
		if not result.accepted:return result
	gesture={"tool":tool,"last":point,"parameters":parameters.duplicate(true),"amount":amount,"policy":policy,"speed":speed,"stroke_id":stroke_id,"sample":0,"generation":runtime.generation()}
	return _sample(point,false)

func move(point: Vector2) -> Dictionary:
	if gesture.is_empty() or not end_requested.is_empty():return {"accepted":false,"error":&"no_active_stroke"}
	if gesture.tool==&"castle_v1":return {"accepted":false,"error":&"single_stamp"}
	var distance: float=gesture.last.distance_to(point)
	if distance<0.025:return {"accepted":false,"error":&"below_sample_spacing"}
	var start: Vector2=gesture.last
	if gesture.tool==&"gravel_drop":return _sample(point,false)
	var max_segment:=2.0
	if gesture.tool in [&"remove_sand",&"place_sand",&"suspended_sand"]:max_segment=minf(max_segment,0.75/maxf(gesture.amount,0.01))
	var segments:=ceili(distance/max_segment)
	var result: Dictionary={}
	for index in segments:
		result=_sample(start.lerp(point,float(index+1)/segments),true)
		if not result.accepted:return result
	return result

func finish(cancel: bool=false) -> Dictionary:
	if gesture.is_empty():return {"accepted":true,"error":&""}
	if gesture.stroke_id==0:gesture={};return {"accepted":true,"error":&""}
	end_requested="cancel" if cancel else "end"
	return _try_end()

func _try_end() -> Dictionary:
	if runtime.generation()!=gesture.generation:return {"accepted":false,"error":&"stale_generation"}
	var result:=_control(end_requested,gesture.stroke_id)
	if result.accepted:gesture={};end_requested=""
	return result

func _control(mode: String, stroke: int) -> Dictionary:
	var next:=_id()
	if not next.error.is_empty():return {"accepted":false,"error":next.error}
	return _remember(runtime.submit_control(mode,{"domain_id":domain_id,"generation":runtime.generation(),"command_id":next.value,"sim_tick":_tick(),"stroke_id":stroke,"baseline_token":stroke}))

static func _profile_id(tool: StringName, swept: bool) -> StringName:
	match tool:
		&"remove_sand":return &"dig_sweep_v1" if swept else &"dig_v1"
		&"place_sand":return &"fill_sweep_v1" if swept else &"fill_v1"
		&"suspended_sand":return &"suspended_sweep_v1" if swept else &"suspended_v1"
	return tool

func _sample(point: Vector2, swept: bool) -> Dictionary:
	if runtime.generation()!=gesture.generation:return {"accepted":false,"error":&"stale_generation"}
	if gesture.tool==&"gravel_drop":
		var identity:=_id()
		if not identity.error.is_empty():return {"accepted":false,"error":identity.error}
		var emitted:=_remember(runtime.submit_display_intent({"domain_id":domain_id,"generation":runtime.generation(),"command_id":identity.value,"sim_tick":_tick(),"point_xz_m":point,"count":gesture.parameters.get("count",0)}))
		if emitted.accepted:gesture.last=point;gesture.sample+=1
		return emitted
	var profile_id:=_profile_id(gesture.tool,swept)
	var profile: Dictionary=registry.profile(profile_id)
	var next:=_id()
	if not next.error.is_empty():return {"accepted":false,"error":next.error}
	var params: Dictionary=gesture.parameters.duplicate(true)
	if profile.operation==0:
		var amount: float=gesture.amount if not swept else maxf(gesture.amount/30.0,gesture.last.distance_to(point)*gesture.amount/0.75)
		# The public UI drag rate can be below the profile's 0.01 m3 amount
		# minimum. Its existing strength parameter expresses the same volume.
		params={"radius_m":0.75,"amount_m3":maxf(0.01,amount),"strength":minf(1.0,amount/0.01),"speed_m_s":0.0 if gesture.tool==&"suspended_sand" else gesture.speed}
	elif profile.operation in [1,2]:params.speed_m_s=gesture.speed
	# Disk profiles stamp at the current point even during a drag. Only the
	# registered capsule shape describes a segment between successive points.
	var start: Vector2=gesture.last if swept and profile.shape==I.Profile.Shape.SWEPT_CAPSULE else point
	var request:={"domain_id":domain_id,"generation":runtime.generation(),"command_id":next.value,"sim_tick":_tick(),"profile_id":profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":start,"end_xz_m":point,"parameters":params,"features":{"water_policy":0 if gesture.tool in [&"suspended_sand",&"smooth_v1",&"compact_v1"] else gesture.policy},"source_context":"player_ui","seed":101}
	if gesture.stroke_id!=0:request.merge({"stroke_id":gesture.stroke_id,"baseline_token":gesture.stroke_id,"sample_index":gesture.sample})
	var result:=_remember(runtime.submit_intent(request))
	if result.accepted:gesture.last=point;gesture.sample+=1
	return result

func poll() -> void:
	for index in range(waiting.size()-1,-1,-1):
		var item: Dictionary=waiting[index]
		var value: Dictionary=runtime.take_result(item.generation,item.id)
		if not value.is_empty():
			terminal.append(value);waiting.remove_at(index)
			if terminal.size()>128:terminal.pop_front()
	if not end_requested.is_empty() and not gesture.is_empty() and runtime.ready_for_input():_try_end()

func preview_request(tool: StringName, point: Vector2, parameters: Dictionary, amount: float, policy: int, speed: float) -> Dictionary:
	if tool==&"gravel_drop":return {"error":&"display_footprint_only"}
	var active: bool=not gesture.is_empty() and gesture.tool==tool and end_requested.is_empty()
	var swept: bool=active and tool in [&"wall_v1",&"shovel_v1"]
	var profile_id:=_profile_id(tool,swept);var profile: Dictionary=registry.profile(profile_id)
	if profile.is_empty():return {"error":&"invalid_profile"}
	var next:=_id()
	if not next.error.is_empty():return next
	var params: Dictionary=gesture.parameters.duplicate(true) if active else parameters.duplicate(true)
	var selected_policy: int=gesture.policy if active else policy
	var selected_speed: float=gesture.speed if active else speed
	if profile.operation==0:params={"radius_m":0.75,"amount_m3":maxf(0.01,amount),"strength":minf(1.0,amount/0.01),"speed_m_s":0.0 if tool==&"suspended_sand" else selected_speed}
	elif profile.operation in [1,2]:params.speed_m_s=selected_speed
	var start: Vector2=gesture.last if swept else point
	var stroke: int=gesture.stroke_id if active else 0
	var request:={"domain_id":domain_id,"generation":runtime.generation(),"command_id":next.value,"sim_tick":_tick(),"profile_id":profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":start,"end_xz_m":point,"parameters":params,"features":{"water_policy":0 if tool in [&"suspended_sand",&"smooth_v1",&"compact_v1"] else selected_policy},"source_context":"readonly_player_preview","seed":101}
	if profile.stroke_policy!=0:
		var token: int=stroke if stroke!=0 else next.value
		request.merge({"stroke_id":token,"baseline_token":token,"sample_index":gesture.sample if active else 0})
	return {"error":&"","request":request,"geometry":{"tool":tool,"parameters":params,"point":point,"start":start,"end":point,"stroke_id":stroke}}

func restored() -> void:
	gesture={};end_requested="";last_error=&""
