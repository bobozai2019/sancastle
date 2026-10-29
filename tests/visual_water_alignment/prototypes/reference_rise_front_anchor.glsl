#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(rg32f, set = 0, binding = 0) uniform restrict readonly image2D front_raw;
layout(rg32f, set = 0, binding = 1) uniform restrict writeonly image2D front_anchored;

void main() {
    int row = int(gl_GlobalInvocationID.x);
    if (row >= 256) {
        return;
    }
    vec2 own = imageLoad(front_raw, ivec2(row, 0)).rg;
    const float active_peak = 0.003;
    float position = own.x;
    if (own.y < active_peak) {
        int before_row = -1;
        int after_row = -1;
        float before_x = 128.0;
        float after_x = 128.0;
        for (int z = row - 1; z >= 0; --z) {
            vec2 candidate = imageLoad(front_raw, ivec2(z, 0)).rg;
            if (candidate.y >= active_peak) {
                before_row = z;
                before_x = candidate.x;
                break;
            }
        }
        for (int z = row + 1; z < 256; ++z) {
            vec2 candidate = imageLoad(front_raw, ivec2(z, 0)).rg;
            if (candidate.y >= active_peak) {
                after_row = z;
                after_x = candidate.x;
                break;
            }
        }
        if (before_row >= 0 && after_row >= 0) {
            float t = float(row - before_row) / float(after_row - before_row);
            position = mix(before_x, after_x, t);
        } else if (before_row >= 0) {
            position = before_x;
        } else if (after_row >= 0) {
            position = after_x;
        } else {
            position = 128.0;
        }
    }
    imageStore(front_anchored, ivec2(row, 0), vec4(position, own.y, 0.0, 1.0));
}
