extends SceneTree

const Water=preload("res://scripts/simulation/unified_edit/water.gd")
const Splash=preload("res://scripts/simulation/unified_edit/shore_splash.gd")
var output:=""
var report: Dictionary={"checks":[],"cases":[]}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	await process_frame
	RenderingServer.call_on_render_thread(_fixtures)

func _check(name: String, value: bool) -> void:report.checks.append({"name":name,"pass":value})

func _hash(bytes: PackedByteArray) -> String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()

func _texture(owner, format_id: int, bytes: PackedByteArray) -> RID:
	var format:=RDTextureFormat.new();format.width=256;format.height=256;format.format=format_id
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	return owner._own(owner.rd.texture_create(format,RDTextureView.new(),[bytes]))

func _alive(bytes: PackedByteArray) -> int:
	var values:=bytes.to_float32_array();var count:=0
	for i in values.size()/4:
		if values[i*4+3]>0.0:count+=1
	return count

func _upload_pool(owner, target: RID, bytes: PackedByteArray) -> void:
	var format:=RDTextureFormat.new();format.width=64;format.height=16;format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var source: RID=owner._own(owner.rd.texture_create(format,RDTextureView.new(),[bytes]))
	owner.rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(64,16,1),0,0,0,0)

func _fixtures() -> void:
	var rd:=RenderingServer.get_rendering_device()
	var owner=Water.new();owner.rd=rd
	var fields: Dictionary={}
	var data: Dictionary={}
	for key in ["rock","sand","water","momentum_x","momentum_z","obstacle"]:
		var bytes:=PackedByteArray();bytes.resize(65536 if key=="obstacle" else 65536*4)
		fields[key]=_texture(owner,RenderingDevice.DATA_FORMAT_R8_UNORM if key=="obstacle" else RenderingDevice.DATA_FORMAT_R32_SFLOAT,bytes)
	var control:=PackedByteArray();control.resize(128)
	var control_rid: RID=owner._own(rd.storage_buffer_create(128,control))
	owner.solver={"textures":{"rock":fields.rock,"sand":[fields.sand],"water":[fields.water],"momentum_x":[fields.momentum_x],"momentum_z":[fields.momentum_z],"obstacle":fields.obstacle},"async_transport":{"control":control_rid}}
	var splash=Splash.new()
	_check("initialize",splash.initialize(owner,{"domain_id":"main_beach","environment":{"shore_splash_enabled":true}}))
	for mode in ["impact","still","along_shore","receding","dry","deep","rock_only","obstacle"]:
		for key in fields:
			var bytes:=PackedByteArray();bytes.resize(65536 if key=="obstacle" else 65536*4)
			if key=="obstacle":
				if mode=="obstacle":bytes.fill(255)
			else:
				var values:=PackedFloat32Array();values.resize(65536)
				for i in 65536:
					var wet:=i%256<128
					match key:
						"rock":values[i]=0.48 if wet else 0.60
						"sand":values[i]=0.0 if mode=="rock_only" else 0.02+0.001
						"water":values[i]=(0.5 if mode=="deep" else (0.0 if mode=="dry" else 0.06)) if wet else 0.0
						"momentum_x":values[i]=(-0.06 if mode=="receding" else 0.06) if wet and mode not in ["still","along_shore"] else 0.0
						"momentum_z":values[i]=0.06 if wet and mode=="along_shore" else 0.0
				bytes=values.to_byte_array()
			data[key]=bytes;rd.texture_update(fields[key],0,bytes)
		var zeros:=PackedByteArray();zeros.resize(1024*16)
		for rid in splash.images.values():_upload_pool(owner,rid,zeros)
		for tick in 24:
			control.encode_u32(1*4,0);control.encode_u32(6*4,tick+1);control.encode_float(9*4,1.0/30.0)
			rd.buffer_update(control_rid,0,128,control);splash.publish()
		var position: PackedByteArray=rd.texture_get_data(splash.published.splash_position,0)
		var velocity: PackedByteArray=rd.texture_get_data(splash.published.splash_velocity,0)
		var count:=_alive(position)
		_check(mode+"_emission",count>0 if mode=="impact" else count==0)
		var exact:=true
		for key in fields:exact=exact and rd.texture_get_data(fields[key],0)==data[key]
		_check(mode+"_authority_read_only",exact)
		report.cases.append({"mode":mode,"alive":count,"position_sha256":_hash(position)})
	# Controlled live particle, isolated from emission and wall-clock time.
	var empty_obstacle:=PackedByteArray();empty_obstacle.resize(65536);rd.texture_update(fields.obstacle,0,empty_obstacle)
	var p:=PackedFloat32Array();p.resize(4096);p[0]=-2.0;p[1]=2.0;p[2]=0.0;p[3]=0.5
	var v:=PackedFloat32Array();v.resize(4096);v[0]=0.1;v[1]=0.5;v[3]=0.5
	_upload_pool(owner,splash.images.position,p.to_byte_array());_upload_pool(owner,splash.images.velocity,v.to_byte_array())
	control.encode_float(9*4,0.0);control.encode_u32(1*4,0);rd.buffer_update(control_rid,0,128,control);splash.publish()
	_check("zero_dt_exact_position",rd.texture_get_data(splash.published.splash_position,0)==p.to_byte_array())
	_check("zero_dt_exact_velocity",rd.texture_get_data(splash.published.splash_velocity,0)==v.to_byte_array())
	var before: PackedByteArray=rd.texture_get_data(splash.published.splash_position,0)
	control.encode_float(9*4,0.1);control.encode_u32(1*4,1);rd.buffer_update(control_rid,0,128,control);splash.publish()
	_check("fatal_work_does_not_publish",rd.texture_get_data(splash.published.splash_position,0)==before)
	control.encode_u32(1*4,0);control.encode_float(9*4,0.0);rd.buffer_update(control_rid,0,128,control)
	p[1]=0.0;_upload_pool(owner,splash.images.position,p.to_byte_array());splash.publish()
	_check("edited_bed_kills_particle",_alive(rd.texture_get_data(splash.published.splash_position,0))==0)
	p[0]=20.0;p[1]=2.0;p[3]=0.5;_upload_pool(owner,splash.images.position,p.to_byte_array());splash.publish()
	_check("out_of_domain_kills_particle",_alive(rd.texture_get_data(splash.published.splash_position,0))==0)
	# Every synchronous read here is probe-only and precedes resource release.
	splash.detach()
	for i in range(owner.owned.size()-1,-1,-1):rd.free_rid(owner.owned[i])
	owner.owned.clear();owner.kernels.clear();owner.solver=null;owner.rd=null
	call_deferred("_finish")

func _finish() -> void:
	report["pass"]=report.checks.all(func(row):return row["pass"])
	report.scope="Isolated GPU fixtures; exact before/after authority inputs, emission direction and gates, dt=0/fatal/landing/bounds. Not a whole-scene numerical replay or performance result."
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SPLASH_FIXTURE ",JSON.stringify(report))
	quit(0 if report["pass"] else 1)
