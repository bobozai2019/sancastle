#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Command { uint c[]; };
layout(set=0,binding=1,std430) readonly buffer Receipt { uint r[]; };
layout(set=0,binding=2,std430) buffer PipelineControl { uint control[]; };
layout(set=0,binding=3,std430) writeonly buffer Diagnostics { uint diagnostic[]; };
layout(push_constant,std430) uniform Params { uint index,diagnostics,pad0,pad1; } p;
void main() {
    if(control[1]!=0u) return;
    if(r[12]==1u) {
        control[10]=r[8];control[11]=r[9];control[18]++;
    } else if(r[12]==2u) {
        // Rejected command leaves the live revision and authority unchanged.
        control[19]++;
        // Nonfinite/negative authority, identity or corrupt material is not
        // ordinary capacity rejection. Stop subsequent work and report it.
        if((r[22] & (1u|2u|8u|256u))!=0u) control[1]|=8u;
    } else control[1]|=4u;
    if(p.diagnostics!=0u) for(uint j=0u;j<32u;j++) diagnostic[p.index*32u+j]=r[j];
}
