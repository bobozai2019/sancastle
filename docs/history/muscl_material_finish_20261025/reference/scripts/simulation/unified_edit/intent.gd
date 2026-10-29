extends RefCounted

const Profile=preload("res://scripts/simulation/unified_edit/tool_profile.gd")
const Layout=preload("res://scripts/simulation/unified_edit/layout.gd")
const REQUIRED=["domain_id","generation","command_id","sim_tick","profile_id","profile_version","profile_hash","start_xz_m"]
const OPTIONAL=["end_xz_m","parameters","features","authorization","stroke_id","baseline_token","sample_index","seed","source_context"]
const SNAPSHOT_KEYS=["domain_id","domain_hash","generation","command_id","sim_tick","profile_id","profile_version","profile_hash","start_xz_m","end_xz_m","parameters","features","authorization","stroke_id","baseline_token","sample_index","seed","source_context","control_kind","configuration"]

static func counter(value: Variant, minimum: int=0) -> bool:
	return typeof(value)==TYPE_INT and value>=minimum

static func next_identity(value: Variant) -> Dictionary:
	if not counter(value):return {"error":&"invalid_identity"}
	if value==Layout.INT64_MAX:return {"error":&"identity_exhausted"}
	return {"error":&"","value":value+1}

static func domain_error(request: Dictionary, domain: Variant, generation: Variant) -> StringName:
	if typeof(domain) not in [TYPE_STRING,TYPE_STRING_NAME]:return &"invalid_domain"
	if typeof(request.get("domain_id")) not in [TYPE_STRING,TYPE_STRING_NAME] or String(request.domain_id).is_empty() or String(request.domain_id).length()>128 or String(request.domain_id)!=String(domain):return &"invalid_domain"
	if not counter(generation,1) or not counter(request.get("generation"),1) or request.generation!=generation:return &"stale_generation"
	if not counter(request.get("command_id"),1) or not counter(request.get("sim_tick")):return &"invalid_identity"
	return &""

static func freeze(registry, request: Dictionary, domain: Variant, generation: Variant) -> Dictionary:
	for key in REQUIRED:
		if not request.has(key):return {"error":&"invalid_intent"}
	for key in request:
		if key not in REQUIRED and key not in OPTIONAL:return {"error":&"invalid_intent"}
	var error:=domain_error(request,domain,generation)
	if not error.is_empty():return {"error":error}
	if typeof(request.profile_id) not in [TYPE_STRING,TYPE_STRING_NAME] or not counter(request.profile_version,1) or typeof(request.profile_hash)!=TYPE_STRING or not request.get("parameters",{}) is Dictionary or not request.get("features",{}) is Dictionary:return {"error":&"invalid_profile"}
	var resolved: Dictionary=registry.resolve(StringName(request.profile_id),request.profile_version,request.profile_hash,request.get("parameters",{}),request.get("features",{}))
	if not resolved.error.is_empty():return resolved
	var profile: Dictionary=resolved.value
	var a: Variant=request.start_xz_m
	var b: Variant=request.get("end_xz_m",a)
	if not a is Vector2 or not b is Vector2 or not a.is_finite() or not b.is_finite():return {"error":&"invalid_transform"}
	if profile.shape==Profile.Shape.DISK and a!=b:return {"error":&"invalid_transform"}
	if profile.shape==Profile.Shape.HEIGHT_STAMP and a!=b:return {"error":&"invalid_transform"}
	if a.distance_to(b)>profile.sampling.max_segment_m+1e-10:return {"error":&"invalid_transform"}
	var stroke: Variant=request.get("stroke_id",0)
	var baseline: Variant=request.get("baseline_token",0)
	var sample: Variant=request.get("sample_index",0)
	if not counter(stroke) or not counter(baseline) or not counter(sample):return {"error":&"invalid_stroke"}
	if profile.stroke_policy==Profile.StrokePolicy.FIXED_BASELINE_COVERAGE:
		if stroke==0 or baseline==0:return {"error":&"invalid_stroke"}
	elif stroke!=0 or baseline!=0 or sample!=0:return {"error":&"invalid_stroke"}
	if typeof(request.get("seed",101))!=TYPE_INT:return {"error":&"invalid_seed"}
	if typeof(request.get("source_context","api")) not in [TYPE_STRING,TYPE_STRING_NAME] or String(request.get("source_context","api")).length()>128:return {"error":&"invalid_source_context"}
	var radius:=footprint_radius(profile)
	if profile.stroke_policy==Profile.StrokePolicy.FIXED_BASELINE_COVERAGE:
		for point in [a,b]:
			if point.x-radius< -16.0 or point.y-radius< -16.0 or point.x+radius>16.0 or point.y+radius>16.0:return {"error":&"out_of_domain"}
	else:
		if maxf(a.x,b.x)+radius< -16.0 or minf(a.x,b.x)-radius>16.0 or maxf(a.y,b.y)+radius< -16.0 or minf(a.y,b.y)-radius>16.0:return {"error":&"out_of_domain"}
	if not request.get("authorization",{}) is Dictionary:return {"error":&"invalid_authorization"}
	var limits:=budget_limits(profile,a,b)
	var allowed: Array=[]
	match profile.operation:
		Profile.Operation.VOLUME_DELTA:allowed=["available_m3"]
		Profile.Operation.TARGET_HEIGHT:allowed=["add_budget_m3"]
		Profile.Operation.TRANSFER:allowed=["transfer_budget_m3"]
	var authorization:={}
	for key in allowed:authorization[key]=limits[key]
	for key in request.get("authorization",{}):
		var value: Variant=request.authorization[key]
		if key not in allowed or not Profile.finite_number(value) or value<0.0 or value>limits[key]:return {"error":&"invalid_authorization"}
		authorization[key]=value
	var frozen:={"domain_id":String(domain),"domain_hash":String(domain).sha256_text(),"generation":generation,"command_id":request.command_id,"sim_tick":request.sim_tick,"profile_id":String(request.profile_id),"profile_version":request.profile_version,"profile_hash":request.profile_hash,"start_xz_m":a,"end_xz_m":b,"parameters":profile.parameters.duplicate(true),"stroke_id":stroke,"baseline_token":baseline,"sample_index":sample,"seed":request.get("seed",101),"source_context":String(request.get("source_context","api")),"control_kind":Layout.ControlKind.NONE,"configuration":profile.duplicate(true)}
	frozen.features=profile.selected_features.duplicate(true)
	frozen.authorization=authorization
	return {"error":&"","value":frozen}

static func control(domain: Variant, generation: Variant, command_id: Variant, sim_tick: Variant, kind: Variant, stroke_id: Variant, baseline_token: Variant) -> Dictionary:
	if typeof(domain) not in [TYPE_STRING,TYPE_STRING_NAME]:return {"error":&"invalid_domain"}
	var base:={"domain_id":String(domain),"generation":generation,"command_id":command_id,"sim_tick":sim_tick}
	var error:=domain_error(base,domain,generation)
	if not error.is_empty():return {"error":error}
	if typeof(kind)!=TYPE_INT or kind not in [Layout.ControlKind.BEGIN,Layout.ControlKind.END,Layout.ControlKind.CANCEL] or not counter(stroke_id,1) or not counter(baseline_token,1):return {"error":&"invalid_stroke"}
	base.merge({"domain_hash":String(domain).sha256_text(),"profile_id":"","profile_version":0,"profile_hash":"","start_xz_m":Vector2.ZERO,"end_xz_m":Vector2.ZERO,"parameters":{},"features":{},"authorization":{},"stroke_id":stroke_id,"baseline_token":baseline_token,"sample_index":0,"seed":0,"source_context":"control","control_kind":kind,"configuration":{}})
	return {"error":&"","value":base}

static func revalidate(registry, frozen: Dictionary) -> StringName:
	if frozen.size()!=SNAPSHOT_KEYS.size():return &"invalid_snapshot"
	for key in SNAPSHOT_KEYS:
		if not frozen.has(key):return &"invalid_snapshot"
	if typeof(frozen.control_kind)!=TYPE_INT:return &"invalid_snapshot"
	var checked: Dictionary
	if frozen.control_kind!=Layout.ControlKind.NONE:
		for key in ["generation","command_id","sim_tick","control_kind","stroke_id","baseline_token"]:
			if typeof(frozen[key])!=TYPE_INT:return &"invalid_snapshot"
		if typeof(frozen.domain_id) not in [TYPE_STRING,TYPE_STRING_NAME]:return &"invalid_snapshot"
		checked=control(StringName(frozen.domain_id),frozen.generation,frozen.command_id,frozen.sim_tick,frozen.control_kind,frozen.stroke_id,frozen.baseline_token)
	else:
		var request:={}
		for key in REQUIRED+OPTIONAL:request[key]=frozen[key]
		if typeof(frozen.generation)!=TYPE_INT or typeof(frozen.domain_id) not in [TYPE_STRING,TYPE_STRING_NAME]:return &"invalid_snapshot"
		checked=freeze(registry,request,StringName(frozen.domain_id),frozen.generation)
	if not checked.error.is_empty():return checked.error
	return &"" if checked.value==frozen else &"snapshot_modified"

static func footprint_radius(profile: Dictionary) -> float:
	var params: Dictionary=profile.parameters
	if profile.shape==Profile.Shape.HEIGHT_STAMP:
		return 2.0*params.scale_xz*(absf(cos(params.yaw_rad))+absf(sin(params.yaw_rad)))
	if profile.operation==Profile.Operation.TRANSFER:return params.trench_width_m*0.5+params.shoulder_width_m
	if profile.operation==Profile.Operation.TARGET_HEIGHT:return params.bottom_width_m*0.5
	return params.radius_m

static func budget_limits(profile: Dictionary, start: Vector2, end: Vector2) -> Dictionary:
	var p: Dictionary=profile.parameters
	var distance:=start.distance_to(end)
	var add:=0.0;var transfer:=0.0;var available:=0.0
	if profile.operation==Profile.Operation.VOLUME_DELTA:
		var amount: float=p.amount_m3*p.strength
		available=amount+0.000001
		if profile.volume_sign==Profile.VolumeSign.ADD:add=amount
	elif profile.operation==Profile.Operation.TARGET_HEIGHT:
		add=48.0 if profile.shape==Profile.Shape.HEIGHT_STAMP else minf(8.0,(distance*p.bottom_width_m+PI*p.bottom_width_m*p.bottom_width_m/4.0)*(p.height_m+0.25))
	elif profile.operation==Profile.Operation.TRANSFER:
		transfer=minf(1.0,p.depth_m*(2.0*p.trench_width_m*distance/3.0+PI*p.trench_width_m*p.trench_width_m/8.0))
	return {"add_budget_m3":add,"transfer_budget_m3":transfer,"available_m3":available}

static func bounds(frozen: Dictionary) -> Rect2i:
	if frozen.control_kind!=Layout.ControlKind.NONE:return Rect2i()
	var radius:=footprint_radius(frozen.configuration)
	var a: Vector2=frozen.start_xz_m;var b: Vector2=frozen.end_xz_m
	var lo:=(a.min(b)-Vector2.ONE*radius+Vector2.ONE*16.0)/0.125-Vector2.ONE*0.5
	var hi:=(a.max(b)+Vector2.ONE*radius+Vector2.ONE*16.0)/0.125-Vector2.ONE*0.5
	var x0:=clampi(floori(lo.x)-1,0,255);var z0:=clampi(floori(lo.y)-1,0,255)
	var x1:=clampi(ceili(hi.x)+1,0,255);var z1:=clampi(ceili(hi.y)+1,0,255)
	return Rect2i(x0,z0,x1-x0+1,z1-z0+1)
