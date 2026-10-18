#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Control {uint control[];};
layout(push_constant,std430) uniform Params {uvec2 revision;uvec2 pad;}p;
void main(){control[10]=p.revision.x;control[11]=p.revision.y;}
