#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Commands { uint packed_commands[]; };
layout(set=0,binding=1,std430) buffer Command { uint c[]; };
layout(set=0,binding=2,std430) buffer Control { uint s[]; };
layout(set=0,binding=3,std430) readonly buffer Receipts { uint receipts[]; };
layout(set=0,binding=4,std430) buffer Indirect { uint dispatches[]; };
layout(set=0,binding=5,std430) buffer Meta { uint meta[]; };
layout(push_constant,std430) uniform Params { uint index; uint local_groups; uint full_groups; uint pad; } params;
void main() {
    uint offset=params.index*32u;
    for(uint j=0u;j<32u;j++) c[j]=packed_commands[offset+j];
    bool run_command=true;
    uint low=c[8],high=c[9];
    if(params.index>0u) {
        uint previous=(params.index-1u)*32u;
        run_command=receipts[previous+12u]==1u;
        low=receipts[previous+8u];high=receipts[previous+9u];
    }
    for(uint j=0u;j<16u;j++) s[j]=0u;
    s[8]=c[4];s[9]=c[5];s[10]=low;s[11]=high;
    meta[0]=run_command?1u:0u;meta[1]=low;meta[2]=high;meta[3]=params.index;
    dispatches[0]=run_command?1u:0u;dispatches[1]=1u;dispatches[2]=1u;
    dispatches[3]=run_command?params.local_groups:0u;dispatches[4]=1u;dispatches[5]=1u;
    dispatches[6]=run_command?params.full_groups:0u;dispatches[7]=1u;dispatches[8]=1u;
    dispatches[9]=run_command?params.pad:0u;dispatches[10]=params.pad;dispatches[11]=1u;
}
