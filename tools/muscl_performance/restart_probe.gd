extends "res://tools/wave_propagation/native_restart_probe.gd"

const FixtureUpload=preload("res://tools/muscl_performance/fixture_upload.gd")
var spare_patched:=false

func patch_spare_render() -> void:
	var fields: Dictionary=owner.state.textures
	var raw:=FixtureUpload.field_read(owner.state.rd,fields,"momentum_x",1)
	var offset: int=(128*256+128)*4
	raw.encode_u32(offset,raw.decode_u32(offset)^1)
	check("actual_spare_fixture_upload",FixtureUpload.field_upload(owner.state.rd,fields,"momentum_x",1,raw).pass)
	check("real_spare_differs",raw!=FixtureUpload.field_read(owner.state.rd,fields,"momentum_x",0))
	call_deferred("spare_ready")

func spare_ready() -> void:spare_patched=true

func prepare_restart_domain(domain) -> void:
	if case_id!="molded":return
	var tags:=PackedFloat32Array();tags.resize(65536)
	for z in range(96,160):
		for x in range(96,160):
			var i:=z*256+x
			domain.sand[i]+=0.04*sin(float(x)*0.2)*cos(float(z)*0.17)
			tags[i]=0.15
	domain.set_meta("brush_initial_mold_depth",tags)

func save_state(label: String) -> void:
	if mode=="seed" and label=="seed":
		spare_patched=false;RenderingServer.call_on_render_thread(patch_spare_render)
		while not spare_patched:await process_frame
	await super.save_state(label)
	if failed:return
	var loaded:=Codec.read_container(output.path_join(label+".sandue"))
	check("support_checkpoint_read",loaded.error.is_empty())
	if not loaded.error.is_empty():return
	if label in ["seed","restored"]:check("checkpoint_spare_differs",loaded.checkpoint.native.fields.momentum_x!=loaded.checkpoint.native.spare.momentum_x)
	var bytes: PackedByteArray=loaded.checkpoint.native.material.current_support
	var count:=0
	for i in 65536:
		if bytes.decode_float(i*8)>0.0:count+=1
	check("actual_support_tags:"+str(count),count>0 if case_id=="molded" else count==0)

func _initialize() -> void:
	super._initialize()
	output=output.path_join("data")

func scratch_render() -> void:
	super.scratch_render()
	if owner.water.muscl.buffers.has("retry_cache"):
		var raw: PackedByteArray=owner.state.rd.buffer_get_data(owner.water.muscl.buffers.retry_cache)
		var zero:=PackedByteArray();zero.resize(16)
		initial_scratch.retry_cache={"bytes":raw.size(),"sha256":Codec.Old.digest(raw).hex_encode(),"zero":raw==zero}
