extends "res://tools/muscl_performance/variant_states.gd"

const Recorder=preload("res://scripts/simulation/unified_edit/water.gd")
class InlineMaterial:
	extends RefCounted
	var rd: RenderingDevice
	var passes: Array=[]
	func muscl_recording_passes(_live: int) -> Array:return passes
	# Deliberately no material-slots-synced capability: only slot 1 is written.
	func record(_decision: RID, indirect: RID, step: int, _live: int) -> void:
		for stage in passes:
			var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,stage.pipeline);rd.compute_list_bind_uniform_set(list,stage.uniform,0);rd.compute_list_dispatch_indirect(list,indirect,step*12);rd.compute_list_end()

var provider
var initial_wet:=PackedByteArray()

func prepare_test_tick(_spec: Dictionary, iteration: int) -> void:
	if iteration!=0:return
	var rd: RenderingDevice=owner.state.rd
	initial_wet=rd.texture_get_data(owner.state.textures.wetness[0],0)
	var source:=RDShaderSource.new()
	source.source_compute="#version 450\nlayout(local_size_x=8,local_size_y=8)in;layout(r16f,set=0,binding=0)uniform image2D wet;void main(){ivec2 q=ivec2(gl_GlobalInvocationID.xy);imageStore(wet,q,vec4(min(1.0,imageLoad(wet,q).r+0.125)));}"
	var spirv:=rd.shader_compile_spirv_from_source(source)
	check("custom_compile",spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty())
	var shader: RID=owner.water._own(rd.shader_create_from_spirv(spirv))
	var pipeline: RID=owner.water._own(rd.compute_pipeline_create(shader))
	var binding: RID=owner.water._make_binding(shader,0,[owner.state.textures.wetness[1]],[])
	provider=InlineMaterial.new();provider.rd=rd;provider.passes=[Recorder.RecordingPass.new(pipeline,binding)]
	owner.water.coupled_recorder=provider.record

func capture_received(value: Dictionary) -> void:
	if capture_index==0:check("custom_inline_material_write_visible",value.wetness_0!=initial_wet)
	super.capture_received(value)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	check("zip_open",state_zip.open(output.path_join("states.zip"))==OK)
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=catalog.registry
	case_name="inline_custom_material";capture_index=0
	var spec:={"name":case_name,"retention":0.5,"boundary":false,"erosion":false,"momentum":0.1}
	var states: Array=await fixture(spec,false)
	check("custom_state_count",states.size()==5)
	check("zip_finish",state_zip.close()==OK)
	FileAccess.open(output.path_join("variant.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":variant_rows,"injections":[],"scope":"Unwrapped inline provider without sync capability changes only material slot 1; normalize must still copy it to slot 0"},"\t"))
	provider=null
	quit(1 if failed else 0)
