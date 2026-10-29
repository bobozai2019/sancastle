#[compute]
#version 450
#include "muscl_spatial.glslinc"
shared float sx[64],sz[64];
void main(){
 // Uniform dispatch-wide predicate. Validity is written only by decision
 // passes, never by one workgroup racing other groups in this dispatch.
 if(p.phase==0u&&retry_cache[1]!=0u&&retry_cache[0]!=0u){
  if(all(equal(gl_GlobalInvocationID,uvec3(0))))tr[15]=1u;
  return;
 }
 ivec2 q=ivec2(gl_GlobalInvocationID.xy);uint lane=gl_LocalInvocationIndex;
 vec4 xm,xp,zm,zp;cell_faces(q,xm,xp,zm,zp);
 vec2 cx,cz;vec4 fx=evaluate_edge(q,ivec2(1,0),xp,cx),fz=evaluate_edge(q,ivec2(0,1),zp,cz);
 if(!finite4(fx)||!finite4(fz))atomicOr(tr[14],1u);
 imageStore(edge_x,q,fx);imageStore(edge_z,q,fz);imageStore(correction,q,vec4(cx,cz));
 float dx=uintBitsToFloat(tr[11]);
 vec2 source=-0.5*G*vec2((xm.x+xp.x)*((xp.y-xp.x)-(xm.y-xm.x)),(zm.x+zp.x)*((zp.y-zp.x)-(zm.y-zm.x)))/dx;
 imageStore(bed_source,q,vec4(source,0.0,0.0));
 sx[lane]=fx.w;sz[lane]=fz.w;barrier();
 for(uint stride=32u;stride>0u;stride>>=1u){if(lane<stride){sx[lane]=max(sx[lane],sx[lane+stride]);sz[lane]=max(sz[lane],sz[lane+stride]);}barrier();}
 if(lane==0u)imageStore(speed_tiles,ivec2(gl_WorkGroupID.xy),vec4(sx[0],sz[0],0.0,0.0));
 if(all(equal(q,ivec2(0))))tr[15]=1u+p.phase*4u;
}
