#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Input { uint input_words[]; };
layout(set=0,binding=1,std430) buffer Control { uint control[]; };
void main() {
    // Test-only shared-state consumer. Real sand edits are added in P02.
    for(uint i=0u;i<input_words[1];i++) control[10]+=input_words[16u+i*32u];
}
