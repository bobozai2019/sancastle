extends RefCounted

# Preserve the effective profile's local front, foam and gravel algorithms.
# Local front summarizes current water against the previous foam/bed snapshot.
var water
var foam
var gravel
var local_front

func initialize(recorder, foam_field, gravel_field, local_front_field=null, wide_front: bool=false) -> bool:
	if foam_field==null or gravel_field==null:return false
	water=recorder
	foam=foam_field
	gravel=gravel_field
	local_front=local_front_field
	var dt:="uintBitsToFloat(async_d[3])"
	if not water._compile("foam","res://shaders/simulation/visual_foam_step.glsl",{"params.delta_s":dt,"void main() {":"void main() { if(async_d[4]==2u)return;"}):return false
	var max_distance: float=water.solver.cell_size_m*gravel.profile.max_step_cell_fraction
	var micro:="min(max(1.0,ceil(%s*%.16f*%.16f/%.16f)),%.1f)"%[dt,gravel.profile.response_max,gravel.profile.speed_cap_m_s,max_distance,float(gravel.profile.max_microsteps)]
	var cap:="min(p.movement[3],%.16f/max(%s*%.16f,1e-20))"%[max_distance*gravel.profile.max_microsteps,dt,gravel.profile.response_max]
	if not water._compile("gravel","res://shaders/simulation/visual_gravel_step.glsl",{"p.domain.z":dt,"p.domain.w":micro,"p.movement.w":cap,"void main() {":"void main() { if(async_d[4]==2u)return;"}):return false
	if not water._compile("visual_normalize","res://scripts/simulation/edit_validation/frame_pipeline/async_visual_normalize.glsl"):return false
	if local_front!=null:
		var directory:="res://tests/visual_water_alignment/prototypes/"
		if not water._compile("local_front_x",directory+("reference_local_front_x_wide.glsl" if wide_front else "reference_local_front_x.glsl"),{"void main() {":"void main() { if(async_d[4]==2u)return;"}):return false
		if not water._compile("local_front_z",directory+"reference_local_front_z.glsl",{"void main() {":"void main() { if(async_d[4]==2u)return;"}):return false
		water.kernels.local_front_z.binding=water._make_binding(water.kernels.local_front_z.shader,0,[local_front.x_texture,local_front.texture],[])
	rebind_slots()
	water.tail_recorder=record
	return true

func rebind_slots() -> void:
	if local_front!=null:
		if water.kernels.local_front_x.has("binding"):
			var previous: RID=water.kernels.local_front_x.binding
			water.owned.erase(previous)
			water.rd.free_rid(previous)
		water.kernels.local_front_x.binding=water._make_binding(water.kernels.local_front_x.shader,0,[water.solver.textures.water[0],foam.textures[foam.current_index],local_front.x_texture,water.solver.textures.rock,water.solver.textures.sand[0],foam.bed_textures[foam.current_index]],[])
	if water.kernels.visual_normalize.has("binding"):
		var old: RID=water.kernels.visual_normalize.binding
		water.owned.erase(old)
		water.rd.free_rid(old)
	var a: int=foam.current_index
	var b: int=gravel.current_index
	water.kernels.visual_normalize.binding=water._make_binding(water.kernels.visual_normalize.shader,0,[foam.textures[1-a],foam.textures[a],foam.bed_textures[1-a],foam.bed_textures[a],gravel.textures[1-b],gravel.textures[b]],[])

func record(_decision: RID) -> void:
	if local_front!=null:
		water._dispatch("local_front_x",water.kernels.local_front_x.binding,PackedByteArray())
		water._dispatch("local_front_z",water.kernels.local_front_z.binding,PackedByteArray())
	water._dispatch("foam",foam.uniform_sets[0][foam.current_index],PackedFloat32Array([0.0,water.solver.cell_size_m,1.8,25.0]).to_byte_array())
	var p: Dictionary=gravel.profile
	var push:=PackedInt32Array([gravel.active_count,p.capacity,p.seed,0]).to_byte_array()
	push.append_array(PackedFloat32Array([water.solver.grid_size,water.solver.cell_size_m,0.0,1.0,p.h_on_m,p.h_off_m,p.speed_on_m_s,p.speed_off_m_s,p.response_min,p.response_max,p.h_epsilon_m,p.speed_cap_m_s]).to_byte_array())
	push.append_array(PackedFloat32Array(p.spawn_bounds_xz).to_byte_array())
	push.append_array(PackedFloat32Array([1.0 if p.bed_reconstruction else 0.0,0.0,0.0,0.0]).to_byte_array())
	var device: RenderingDevice=water.rd
	var list:=device.compute_list_begin()
	device.compute_list_bind_compute_pipeline(list,water.kernels.gravel.pipeline)
	device.compute_list_bind_uniform_set(list,gravel.uniform_sets[0][gravel.current_index],0)
	device.compute_list_bind_uniform_set(list,water.kernels.gravel.decision_set,1)
	device.compute_list_set_push_constant(list,push,push.size())
	device.compute_list_dispatch(list,16,1,1)
	device.compute_list_end()
	water._dispatch("visual_normalize",water.kernels.visual_normalize.binding,PackedByteArray())

func detach() -> void:
	if water!=null:water.tail_recorder=Callable()
	water=null
	foam=null
	gravel=null
	local_front=null
