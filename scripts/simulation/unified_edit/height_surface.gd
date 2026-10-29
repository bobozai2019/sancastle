extends Node3D

# Fixed scene hierarchy; only data-driven HeightMapShape resources change.
# No solver, RD, tool queue, or alternate height readback belongs here.
var shapes: Dictionary={}
var applied_revisions: Dictionary={}
var shape_allocations:=0
var shape_updates:=0
var unchanged_skips:=0
var consumer
var generation:=0
@export var collision_enabled:=true

func _ready() -> void:
	for index in 64:shapes[index]=get_node("Terrain/Chunk_%d"%index)
	set_collision_enabled(collision_enabled)

func set_collision_enabled(enabled: bool) -> void:
	collision_enabled=enabled
	var terrain: StaticBody3D=get_node("Terrain")
	terrain.collision_layer=1 if enabled else 0;terrain.collision_mask=1 if enabled else 0

func prepare_consumer(value) -> bool:
	if collision_enabled or consumer!=null or value==null:return false
	generation=value.generation;consumer=value;applied_revisions.clear()
	return generation>0

func clear_consumer() -> bool:
	if collision_enabled or (consumer!=null and consumer.active_count()!=0):return false
	consumer=null;return true

func _physics_process(_delta: float) -> void:
	if consumer!=null:consumer.physics_consume()

func _replace_chunk_shape(chunk: int, revision: int, heights: PackedFloat32Array, epoch: int) -> bool:
	if generation==0:generation=epoch
	if epoch!=generation or chunk<0 or chunk>=64 or heights.size()!=1089 or revision<int(applied_revisions.get(chunk,-1)):return false
	var node: CollisionShape3D=shapes[chunk]
	var shape: HeightMapShape3D=node.shape
	if shape!=null and shape.map_data==heights:
		unchanged_skips+=1;applied_revisions[chunk]=revision;return true
	if shape==null:
		shape=HeightMapShape3D.new();shape.map_width=33;shape.map_depth=33;shape_allocations+=1
	shape.map_data=heights;node.shape=shape
	shape_updates+=1;applied_revisions[chunk]=revision
	return true
