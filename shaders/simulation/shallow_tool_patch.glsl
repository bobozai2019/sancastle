#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct ToolEdit {
    int index;
    float sand_m;
    float compaction;
    float reserved;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer ToolEdits {
    ToolEdit edits[];
} edit_buffer;
layout(r32f, set = 0, binding = 1) uniform restrict writeonly image2D sand_state_0;
layout(r32f, set = 0, binding = 2) uniform restrict writeonly image2D sand_state_1;
layout(r16f, set = 0, binding = 3) uniform restrict writeonly image2D compaction_state_0;
layout(r16f, set = 0, binding = 4) uniform restrict writeonly image2D compaction_state_1;

layout(push_constant, std430) uniform Params {
    int count;
    int grid_size;
    int reserved_0;
    int reserved_1;
} params;

void main() {
    uint edit_index = gl_GlobalInvocationID.x;
    if (edit_index >= uint(params.count)) {
        return;
    }
    ToolEdit edit = edit_buffer.edits[edit_index];
    ivec2 cell = ivec2(edit.index % params.grid_size, edit.index / params.grid_size);
    imageStore(sand_state_0, cell, vec4(edit.sand_m));
    imageStore(sand_state_1, cell, vec4(edit.sand_m));
    imageStore(compaction_state_0, cell, vec4(edit.compaction));
    imageStore(compaction_state_1, cell, vec4(edit.compaction));
}
