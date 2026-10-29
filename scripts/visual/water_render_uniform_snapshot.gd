extends RefCounted
class_name SandcastleWaterRenderUniformSnapshot

## Normalize effective material parameters for staging/capture comparison.
static func material_values(material: ShaderMaterial) -> Dictionary:
	var values := {}
	if material == null or material.shader == null:
		return values
	for uniform in material.shader.get_shader_uniform_list():
		var name := String(uniform.get("name", ""))
		if name.is_empty():
			continue
		var value: Variant = material.get_shader_parameter(name)
		if value is Texture2D:
			var texture: Texture2D = value
			values[name] = {"class": texture.get_class(),
				"width": texture.get_width(), "height": texture.get_height()}
		elif typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			values[name] = value
		else:
			values[name] = str(value)
	return values
