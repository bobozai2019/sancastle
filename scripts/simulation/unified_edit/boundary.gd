extends RefCounted

# Declarative boundary inputs. No authority, independent pump or CPU tick loop.
const I=preload("res://scripts/simulation/unified_edit/intent.gd")
const Geometry=preload("res://scripts/scenarios/test1_geometry_layout.gd")
const Capture=preload("res://scripts/scenarios/test1_playable_layout.gd")
const SOURCES=["res://scripts/simulation/unified_edit/boundary.gd","res://scripts/scenarios/test1_geometry_layout.gd","res://assets/test1_geometry/water_cycle.json","res://assets/test1_geometry/initial_state.f32","res://scripts/scenarios/test1_playable_layout.gd","res://assets/test1_water_motion/capture_state.rgba32f"]
const KEYS=["enabled","mode","mean_level_m","amplitude_m","omega_rad_s","phase_rad","period_s"]
const WAVE_KEYS=["domain_id","generation","request_id","start_tick","profile_id","amplitude_m","duration_s","seed"]
const MAX_WAVES:=128
var enabled:=false
var parameters: Dictionary={}
var requests: Array=[]
var start_times: Dictionary={}
var highwater:=0
var generation:=0
var domain_id:=""

static func for_scene(scene: String) -> Dictionary:
	var result:={"enabled":true,"mode":0,"mean_level_m":0.10,"amplitude_m":0.11,"omega_rad_s":0.35,"phase_rad":0.0,"period_s":16.0}
	if scene in ["main","main_beach"]:return result
	if scene in ["test1_capture","test1_backwash"]:
		result.merge({"mode":2 if scene=="test1_backwash" else 1,"mean_level_m":Capture.SEA_OFFSET,"amplitude_m":0.049701884388923645,"omega_rad_s":1.0,"phase_rad":284.71783447265625},true);return result
	if scene=="test1_geometry":
		var profile: Dictionary=Geometry.water_cycle()
		if profile.is_empty():return {}
		result.merge({"mode":3,"mean_level_m":profile.rest_level_m,"amplitude_m":profile.runup_height_m,"omega_rad_s":0.0,"phase_rad":0.0,"period_s":profile.period_s},true);return result
	return {}

static func number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(value) and value>=minimum and value<=maximum

static func configuration_error(config: Dictionary) -> StringName:
	var value: Variant=config.environment.get("boundary",{"enabled":false})
	if not value is Dictionary or typeof(value.get("enabled"))!=TYPE_BOOL:return &"invalid_runtime_boundary"
	if not value.enabled:return &"" if value.size()==1 else &"invalid_runtime_boundary"
	if value.size()!=KEYS.size():return &"invalid_runtime_boundary"
	for key in KEYS:
		if not value.has(key):return &"invalid_runtime_boundary"
	if typeof(value.mode)!=TYPE_INT or value.mode<0 or value.mode>3:return &"invalid_runtime_boundary"
	for key in ["mean_level_m","amplitude_m","omega_rad_s","phase_rad","period_s"]:
		var low: float={"mean_level_m":-16.0,"amplitude_m":0.0,"omega_rad_s":-100.0,"phase_rad":-1000000.0,"period_s":0.001}[key]
		var high: float={"mean_level_m":16.0,"amplitude_m":0.6,"omega_rad_s":100.0,"phase_rad":1000000.0,"period_s":3600.0}[key]
		if not number(value[key],low,high):return &"invalid_runtime_boundary"
	if value.mode==3 and (config.domain_id!="test1_geometry" or value!=for_scene("test1_geometry")):return &"geometry_boundary_profile_mismatch"
	return &""

func configure(config: Dictionary, epoch: int, restored: Dictionary={}) -> void:
	parameters=config.environment.get("boundary",{"enabled":false}).duplicate(true);enabled=parameters.enabled;generation=epoch;domain_id=config.domain_id
	requests=restored.get("wave_requests",[]).duplicate(true);start_times=restored.get("wave_start_times",{}).duplicate(true);highwater=restored.get("wave_highwater_id",0)
	for wave in requests:wave.generation=epoch

func initialize_render(water) -> bool:
	if not enabled:return true
	water.tide_mode=parameters.mode;water.tide_phase=parameters.phase_rad;water.tide_period=parameters.period_s
	return water.configure_boundary(Vector3(parameters.mean_level_m,parameters.amplitude_m,parameters.omega_rad_s),packets())

func prune(completed_time: float) -> void:
	for index in range(requests.size()-1,-1,-1):
		var wave: Dictionary=requests[index]
		if completed_time>=start_times[wave.request_id]+wave.duration_s:start_times.erase(wave.request_id);requests.remove_at(index)

func admit(request: Dictionary, completed_tick: int, accepted_tick_floor: int, completed_time: float) -> Dictionary:
	if not enabled:return {"accepted":false,"error":&"boundary_disabled"}
	if request.size()!=WAVE_KEYS.size():return {"accepted":false,"error":&"invalid_wave_request"}
	for key in WAVE_KEYS:
		if not request.has(key):return {"accepted":false,"error":&"invalid_wave_request"}
	if typeof(request.domain_id) not in [TYPE_STRING,TYPE_STRING_NAME] or String(request.domain_id)!=domain_id or not I.counter(request.generation,1) or request.generation!=generation:return {"accepted":false,"error":&"stale_generation_or_domain"}
	if not I.counter(request.request_id,1) or not I.counter(request.start_tick,1) or typeof(request.seed)!=TYPE_INT:return {"accepted":false,"error":&"invalid_wave_request"}
	if request.request_id<=highwater:return {"accepted":false,"error":&"non_monotonic_wave_id"}
	if request.start_tick<=accepted_tick_floor:return {"accepted":false,"error":&"past_tick"}
	if request.profile_id not in [&"small_packet",&"test_packet"]:return {"accepted":false,"error":&"invalid_wave_profile"}
	var small: bool=request.profile_id==&"small_packet"
	if not number(request.amplitude_m,0.0,0.06 if small else 0.20) or not number(request.duration_s,0.5,3.0 if small else 6.0):return {"accepted":false,"error":&"invalid_wave_request"}
	prune(completed_time)
	if requests.size()>=MAX_WAVES:return {"accepted":false,"error":&"wave_capacity"}
	var frozen: Dictionary=request.duplicate(true);frozen.domain_id=domain_id;frozen.profile_id=StringName(request.profile_id)
	requests.append(frozen);highwater=request.request_id
	# Preserve the existing nominal tick-to-clock phase mapping. The GPU
	# evaluates envelopes against actual simulation time, including CFL clamps.
	start_times[highwater]=completed_time+(float(request.start_tick-completed_tick)-1.5)/30.0
	return {"accepted":true,"error":&"","request_id":highwater,"effective_tick":request.start_tick}

func packets() -> Array:
	var result: Array=[]
	for wave in requests:result.append(Vector4(start_times[wave.request_id],wave.duration_s,wave.amplitude_m,float(wave.seed&1023)*TAU/1024.0))
	return result

static func encode_packets(values: Array) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(MAX_WAVES*16)
	for index in values.size():
		var value: Vector4=values[index]
		for channel in 4:bytes.encode_float(index*16+channel*4,value[channel])
	return bytes
