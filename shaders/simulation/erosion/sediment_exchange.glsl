#[compute]
#version 450

// RK transport has already produced sediment_in at the final water state.
// Keep the existing capacity and bed exchange once per accepted physical dt.
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,r32f) uniform restrict readonly image2D sediment_in;
layout(set=0,binding=1,r32f) uniform restrict readonly image2D sand_in;
layout(set=0,binding=2,r32f) uniform restrict readonly image2D momentum_x_after;
layout(set=0,binding=3,r32f) uniform restrict readonly image2D momentum_z_after;
layout(set=0,binding=4,r32f) uniform restrict readonly image2D water_after;
layout(set=0,binding=5,r8) uniform restrict readonly image2D obstacle_state;
layout(set=0,binding=6,r32f) uniform restrict writeonly image2D sand_out;
layout(set=0,binding=7,r32f) uniform restrict writeonly image2D sediment_out;
layout(set=0,binding=8,r32ui) uniform restrict uimage2D dirty_max_um;
layout(push_constant,std430) uniform Params {
 float delta_s,cell_area_m2,capacity_per_speed_s,erosion_fraction;
 float deposition_fraction,dry_depth_m,capacity_saturation_depth_m,ocean_boundary_enabled;
}params;

void main() {
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);
 if(any(greaterThanEqual(p,imageSize(sediment_in))))return;
 float bed_sand=imageLoad(sand_in,p).r,previous_bed_sand=bed_sand;
 float suspended=imageLoad(sediment_in,p).r;
 if(imageLoad(obstacle_state,p).r<0.5){
  float depth=imageLoad(water_after,p).r,capacity=0.0;
  if(depth>params.dry_depth_m){
   vec2 momentum=vec2(imageLoad(momentum_x_after,p).r,imageLoad(momentum_z_after,p).r);
   float speed=length(momentum)/max(depth,0.005);
   capacity=min(depth/params.capacity_saturation_depth_m,1.0)*params.capacity_per_speed_s*speed;
  }
  float exchange_weight=params.ocean_boundary_enabled>0.5&&p.x==0?0.0:1.0;
  if(suspended<capacity){
   float eroded=min(bed_sand,(capacity-suspended)*params.erosion_fraction*exchange_weight);
   bed_sand-=eroded;suspended+=eroded;
  }else{
   float deposited=min(suspended,(suspended-capacity)*params.deposition_fraction*exchange_weight);
   bed_sand+=deposited;suspended-=deposited;
  }
 }
 imageStore(sand_out,p,vec4(bed_sand));imageStore(sediment_out,p,vec4(suspended));
 uint delta_um=uint(ceil(abs(bed_sand-previous_bed_sand)*1000000.0));
 if(delta_um>0u)imageAtomicMax(dirty_max_um,p/32,delta_um);
}
