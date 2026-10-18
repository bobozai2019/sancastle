extends RefCounted

const PATH:="res://assets/water_material_natural_candidate/async_clock_variants_v1.json"
const MARKER:="uniform float visual_time_s = -1.0;"
const DECLARATION:="uniform float visual_time_s = -1.0;\nuniform bool use_async_clock = false;\nuniform sampler2D async_clock : filter_nearest, repeat_disable;"
const SOURCE_TIME:="visual_time_s >= 0.0 ? visual_time_s : TIME"
const GPU_TIME:="use_async_clock ? textureLod(async_clock, vec2(0.5), 0.0).r : (visual_time_s >= 0.0 ? visual_time_s : TIME)"

static func validate(owner) -> Dictionary:
	var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not manifest is Dictionary or manifest.get("schema_version")!=1 or manifest.get("transform")!="completed_gpu_clock_v1" or not manifest.get("variants") is Array or manifest.variants.size()!=2:return {"error":"clock_variant_manifest"}
	var actual:=[]
	for index in 2:
		var original: Dictionary=owner.compiled_bundle.components[index]
		var row: Dictionary=manifest.variants[index]
		var shader_material: ShaderMaterial=owner.water_material if row.material=="water" else owner.terrain_material
		if row.material!=original.material or row.source!=original.shader or row.source_sha256!=original.shader_sha256 or FileAccess.get_sha256(row.source)!=row.source_sha256:return {"error":"clock_original_identity"}
		if shader_material.shader.resource_path!=row.generated or FileAccess.get_sha256(row.generated)!=row.generated_sha256:return {"error":"clock_generated_identity"}
		var source:=FileAccess.get_file_as_string(row.source).replace("\r\n","\n")
		if source.count(MARKER)!=1 or source.count(SOURCE_TIME)!=row.time_sites:return {"error":"clock_transform_sites"}
		var expected:=source.replace(MARKER,DECLARATION).replace(SOURCE_TIME,GPU_TIME)
		if expected!=FileAccess.get_file_as_string(row.generated):return {"error":"clock_non_time_change"}
		var values:={}
		for key in owner.compiled_constants[index]:
			var value: Variant=shader_material.get_shader_parameter(key)
			if value==null:value=RenderingServer.shader_get_parameter_default(shader_material.shader.get_rid(),key)
			if value!=owner.compiled_constants[index][key]:return {"error":"clock_compiled_constant:"+str(key)}
			values[key]=value
		actual.append({"material":row.material,"shader":row.generated,"shader_sha256":row.generated_sha256,"source":row.source,"source_sha256":row.source_sha256,"constants":values})
	return {"error":"","manifest":PATH,"manifest_sha256":FileAccess.get_sha256(PATH),"components":actual,"scope":"Exact original compiled source plus optional completed-GPU clock; constants and all non-time code unchanged."}
