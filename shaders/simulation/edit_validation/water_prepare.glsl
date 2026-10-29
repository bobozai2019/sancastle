#[compute]
#version 450
layout(local_size_x=64) in;
struct InputCell { vec4 bed_water; vec4 flow; };
layout(set=0,binding=0,std430) buffer Input { InputCell input_cells[]; };
layout(set=0,binding=1,std430) readonly buffer SandCandidate { vec4 sand_cells[]; };
layout(set=0,binding=2,std430) readonly buffer EditReceipt { uint r[]; };
layout(r32f,set=0,binding=3) uniform readonly image2D rock;
layout(r32f,set=0,binding=4) uniform readonly image2D sand;
layout(r32f,set=0,binding=5) uniform readonly image2D water;
layout(r32f,set=0,binding=6) uniform readonly image2D sediment;
layout(r32f,set=0,binding=7) uniform readonly image2D qx;
layout(r32f,set=0,binding=8) uniform readonly image2D qz;
layout(r8,set=0,binding=9) uniform readonly image2D obstacle;
layout(push_constant,std430) uniform Params { uint size; uint x; uint z; uint width; uint height; uint pad0; uint pad1; uint pad2; } params;
void main() {
    uint i=gl_GlobalInvocationID.x,n=params.size;
    if(i>=n*n) return;
    ivec2 p=ivec2(i%n,i/n);
    float old_sand=imageLoad(sand,p).r,new_sand=old_sand;
    bool inside=uint(p.x)>=params.x&&uint(p.y)>=params.z&&uint(p.x)<params.x+params.width&&uint(p.y)<params.z+params.height;
    if(r[12]==1u&&inside&&sand_cells[i].x>0.0) { old_sand=sand_cells[i].z; new_sand=sand_cells[i].y; }
    float bed=imageLoad(rock,p).r;
    input_cells[i].bed_water=vec4(bed+old_sand,bed+new_sand,imageLoad(water,p).r,imageLoad(sediment,p).r);
    input_cells[i].flow=vec4(imageLoad(qx,p).r,imageLoad(qz,p).r,imageLoad(obstacle,p).r,0.0);
}
