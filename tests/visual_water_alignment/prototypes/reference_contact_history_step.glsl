#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D history_in;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D water_now;
layout(rg32f, set = 0, binding = 2) uniform restrict readonly image2D foam_previous;
layout(rg32f, set = 0, binding = 3) uniform restrict readonly image2D local_front_now;
layout(r32f, set = 0, binding = 4) uniform restrict writeonly image2D history_out;

layout(push_constant, std430) uniform Params {
    float delta_s;
    float lifetime_s;
    float wet_epsilon_m;
    float reserved;
} params;

float depth_at(ivec2 cell) {
    return max(imageLoad(water_now,
        clamp(cell, ivec2(0), imageSize(water_now) - ivec2(1))).r, 0.0);
}

void main() {
    ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(cell, imageSize(water_now)))) {
        return;
    }
    float depth = depth_at(cell);
    if (depth <= params.wet_epsilon_m) {
        imageStore(history_out, cell, vec4(0.0));
        return;
    }
    bool near_dry = false;
    if (cell.x > 0) {
        near_dry = near_dry || depth_at(cell + ivec2(-1, 0)) <= params.wet_epsilon_m;
    }
    if (cell.x + 1 < imageSize(water_now).x) {
        near_dry = near_dry || depth_at(cell + ivec2(1, 0)) <= params.wet_epsilon_m;
    }
    if (cell.y > 0) {
        near_dry = near_dry || depth_at(cell + ivec2(0, -1)) <= params.wet_epsilon_m;
    }
    if (cell.y + 1 < imageSize(water_now).y) {
        near_dry = near_dry || depth_at(cell + ivec2(0, 1)) <= params.wet_epsilon_m;
    }
    float previous = max(imageLoad(history_in, cell).r, 0.0);
    float retained = previous * exp(-params.delta_s / params.lifetime_s);
    float earlier_depth = max(imageLoad(foam_previous, cell).g, 0.0);
    float front_peak = max(imageLoad(local_front_now, cell).g, 0.0);
    float rising = smoothstep(0.0006, 0.0020, depth - earlier_depth);
    float front_activity = smoothstep(0.0012, 0.0025, front_peak);
    float shallow = 1.0 - smoothstep(0.03, 0.09, depth);
    float source = near_dry ? rising * front_activity * shallow : 0.0;
    imageStore(history_out, cell, vec4(clamp(max(retained, source), 0.0, 1.0)));
}
