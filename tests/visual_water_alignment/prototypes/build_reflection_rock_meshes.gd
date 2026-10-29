@tool
extends SceneTree

const OUTPUT_PREFIX := "res://tests/visual_water_alignment/prototypes/reflection_rock_"
const SECTORS := 18
const RINGS := 9


func _init() -> void:
	call_deferred("_build")


func _build() -> void:
	for seed in 3:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.39, 0.43, 0.39)
		material.roughness = 0.96
		material.vertex_color_use_as_albedo = true
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		for ring in RINGS:
			for sector in SECTORS:
				var next_sector := (sector + 1) % SECTORS
				var a := _point(ring, sector, seed)
				var b := _point(ring + 1, sector, seed)
				var c := _point(ring + 1, next_sector, seed)
				var d := _point(ring, next_sector, seed)
				_triangle(surface, a, b, c, ring, sector, seed)
				_triangle(surface, a, c, d, ring, sector, seed)
		surface.generate_normals()
		var mesh := surface.commit()
		var path := OUTPUT_PREFIX + str(seed) + ".tres"
		if ResourceSaver.save(mesh, path) != OK:
			printerr("FAIL: reflection rock mesh " + path)
			quit(1)
			return
	print("PASS: reflection rock meshes")
	quit(0)


func _point(ring: int, sector: int, seed: int) -> Vector3:
	var latitude := PI * float(ring) / float(RINGS)
	var longitude := TAU * float(sector) / float(SECTORS)
	var noise := sin(float(sector * 17 + ring * 31 + seed * 83) * 1.723)
	var ridge := sin(longitude * 3.0 + float(seed) * 1.7) * cos(latitude * 2.0)
	var radius := 1.0 + 0.09 * noise + 0.13 * ridge
	var s := sin(latitude)
	return Vector3(cos(longitude) * s * radius,
		cos(latitude) * (0.88 + 0.08 * noise),
		sin(longitude) * s * radius)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ring: int, sector: int, seed: int) -> void:
	var shade := 0.80 + 0.13 * sin(float(ring * 13 + sector * 29 + seed * 47))
	surface.set_color(Color(shade, shade * 0.99, shade * 0.94))
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
