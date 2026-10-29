#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Input { uint input_words[]; };
layout(set=0,binding=1,std430) buffer Command { uint c[]; };
layout(set=0,binding=2,std430) buffer SandControl { uint s[]; };
layout(set=0,binding=3,std430) buffer Indirect { uint dispatches[]; };
layout(set=0,binding=4,std430) buffer PipelineControl { uint control[]; };
layout(push_constant,std430) uniform Params { uint index,local_groups,full_groups,material_groups; } p;
void main() {
    uint offset=16u+p.index*32u;
    for(uint j=0u;j<32u;j++) c[j]=input_words[offset+j];
    bool valid=input_words[0]==1u && input_words[2]==control[2] && input_words[3]==control[3]
        && c[4]==control[2] && c[5]==control[3];
    if(!valid) control[1]|=2u;
    // Never predict revision from input index or previous-command success.
    c[6]=control[6];c[7]=control[7];c[8]=control[10];c[9]=control[11];
    for(uint j=0u;j<16u;j++) s[j]=0u;
    s[8]=control[2];s[9]=control[3];s[10]=control[10];s[11]=control[11];
    bool run_command=valid && control[1]==0u;
    dispatches[0]=run_command?1u:0u;dispatches[1]=1u;dispatches[2]=1u;
    dispatches[3]=run_command?p.local_groups:0u;dispatches[4]=1u;dispatches[5]=1u;
    dispatches[6]=run_command?p.full_groups:0u;dispatches[7]=1u;dispatches[8]=1u;
    dispatches[9]=run_command?p.material_groups:0u;dispatches[10]=p.material_groups;dispatches[11]=1u;
    if(p.index==0u) control[9]=0u;
}
