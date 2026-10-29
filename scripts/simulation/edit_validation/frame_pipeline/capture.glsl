#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Command { uint c[]; };
layout(set=0,binding=1,std430) readonly buffer Receipt { uint r[]; };
layout(set=0,binding=2,std430) buffer Receipts { uint receipts[]; };
layout(set=0,binding=3,std430) readonly buffer Meta { uint meta[]; };
void main() {
    uint offset=meta[3]*32u;
    if(meta[0]==1u) {
        for(uint j=0u;j<32u;j++) receipts[offset+j]=r[j];
    } else {
        // status=0 is an explicit not_executed tail record. Its speculative
        // input revision is retained; output names the accepted prefix.
        for(uint j=0u;j<32u;j++) receipts[offset+j]=0u;
        for(uint j=0u;j<6u;j++) receipts[offset+j]=c[j];
        receipts[offset+6u]=c[8];receipts[offset+7u]=c[9];
        receipts[offset+8u]=meta[1];receipts[offset+9u]=meta[2];
        receipts[offset+10u]=c[6];receipts[offset+11u]=c[7];
    }
}
