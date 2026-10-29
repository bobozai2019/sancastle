#[compute]
#version 450
#include "muscl_spatial.glslinc"
void main(){
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);
 float outgoing=max(imageLoad(edge_x,q).x,0.0)+max(imageLoad(edge_z,q).x,0.0);
 if(q.x>0)outgoing+=max(-imageLoad(edge_x,q-ivec2(1,0)).x,0.0);
 if(q.y>0)outgoing+=max(-imageLoad(edge_z,q-ivec2(0,1)).x,0.0);
 float ratio=uintBitsToFloat(tr[3])/uintBitsToFloat(tr[11]);
 float theta=outgoing>0.0?min(1.0,state_at(q).x/(ratio*outgoing)):1.0;
 imageStore(drain,q,vec4(theta));
 if(all(equal(q,ivec2(0))))tr[15]=2u+p.phase*4u;
}
