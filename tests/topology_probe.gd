extends SceneTree

## Gate 0 geometry risk probe: one height per XZ cannot represent an arch
## opening, whereas the same ground plus three predefined solid pieces can.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var terrain := StaticBody3D.new()
	terrain.position.x = -6.0
	world.add_child(terrain)
	var height_shape := HeightMapShape3D.new()
	height_shape.map_width = 9
	height_shape.map_depth = 9
	var heights := PackedFloat32Array()
	heights.resize(81)
	heights.fill(0.0)
	for z in [4, 5]:
		for x in 9:
			heights[z * 9 + x] = 2.0
	height_shape.map_data = heights
	var terrain_collision := CollisionShape3D.new()
	terrain_collision.shape = height_shape
	terrain.add_child(terrain_collision)
	var arch := StaticBody3D.new()
	arch.position.x = 6.0
	world.add_child(arch)
	_add_box(arch, Vector3(-1.25, 0.7, 0.0), Vector3(0.5, 1.4, 0.5))
	_add_box(arch, Vector3(1.25, 0.7, 0.0), Vector3(0.5, 1.4, 0.5))
	_add_box(arch, Vector3(0.0, 1.65, 0.0), Vector3(3.0, 0.5, 0.5))
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var heightmap_low := _ray_hit(space, Vector3(-6.0, 0.7, -2.0), Vector3(-6.0, 0.7, 2.0))
	var arch_low := _ray_hit(space, Vector3(6.0, 0.7, -2.0), Vector3(6.0, 0.7, 2.0))
	var arch_high := _ray_hit(space, Vector3(6.0, 1.65, -2.0), Vector3(6.0, 1.65, 2.0))
	print("TOPOLOGY heightmap_low_hit=%s arch_low_hit=%s arch_high_hit=%s" % [
		heightmap_low, arch_low, arch_high])
	if not heightmap_low or arch_low or not arch_high:
		push_error("topology collision probe did not distinguish heightfield from arch")
		quit(1)
	else:
		print("PASS: predefined arch passes below lintel and blocks above; heightfield wall blocks below")
		quit(0)


func _add_box(parent: StaticBody3D, position: Vector3, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = position
	parent.add_child(collision)


func _ray_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return not space.intersect_ray(query).is_empty()
