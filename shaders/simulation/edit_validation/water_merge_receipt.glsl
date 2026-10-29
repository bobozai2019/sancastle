#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Command { uint c[]; };
layout(set=0,binding=1,std430) readonly buffer WaterReceipt { uint w[]; };
layout(set=0,binding=2,std430) buffer EditReceipt { uint r[]; };
void main() {
    if(r[12]!=1u) return;
    float moved=uintBitsToFloat(w[4]),retained=uintBitsToFloat(w[5]);
    if(w[0]!=1u||w[1]!=0u||isnan(moved)||isinf(moved)||isnan(retained)||isinf(retained)||moved<0.0||retained<0.0) {
        r[12]=2u;r[13]=7u;r[22]=w[1]==16u?16u:4u;r[14]=0u;r[8]=c[8];r[9]=c[9];
        for(uint j=16u;j<=21u;j++) r[j]=0u;
        r[24]=0u;
        return;
    }
    r[25]=w[3];r[26]=w[4];r[27]=w[5];
    r[23]=w[21];r[28]=w[17];r[29]=w[18];
}
