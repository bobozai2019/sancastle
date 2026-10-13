#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D rock_state;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D sand_state;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D water_in;
layout(r32f, set = 0, binding = 3) uniform restrict readonly image2D momentum_x_in;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D momentum_z_in;
layout(r32f, set = 0, binding = 5) uniform restrict writeonly image2D water_out;
layout(r32f, set = 0, binding = 6) uniform restrict writeonly image2D momentum_x_out;
layout(r32f, set = 0, binding = 7) uniform restrict writeonly image2D momentum_z_out;
layout(r32f, set = 0, binding = 8) uniform restrict writeonly image2D tide_delta_out;

layout(push_constant, std430) uniform Params {
    float level_m;
    float cell_area_m2;
    float reserved_0;
    float incoming_wave_m;
} params;

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(water_in);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    float old_h = imageLoad(water_in, p).r;
    float next_h = old_h;
    float next_qx = imageLoad(momentum_x_in, p).r;
    float next_qz = imageLoad(momentum_z_in, p).r;
    float delta_m3 = 0.0;
    if (p.x == 0) {
        if (params.reserved_0 > 0.5) {
            // Closed-domain inlet: add a prescribed depth, preserving momentum.
            next_h = old_h + max(0.0, params.level_m);
        } else {
            float bed = imageLoad(rock_state, p).r + imageLoad(sand_state, p).r;
            next_h = max(0.0, params.level_m - bed);
            // Linear shallow-water packet: eta perturbation A travels inland
            // with c = sqrt(g * h_background), so depth-integrated q = A*c.
            float background_h = max(0.0,
                params.level_m - max(params.incoming_wave_m, 0.0) - bed);
            next_qx = next_h > 0.0 ? max(params.incoming_wave_m, 0.0) *
                sqrt(9.81 * max(background_h, 0.01)) : 0.0;
            next_qz = 0.0;
        }
        delta_m3 = (next_h - old_h) * params.cell_area_m2;
    }
    imageStore(water_out, p, vec4(next_h, 0.0, 0.0, 1.0));
    imageStore(momentum_x_out, p, vec4(next_qx, 0.0, 0.0, 1.0));
    imageStore(momentum_z_out, p, vec4(next_qz, 0.0, 0.0, 1.0));
    if (p.x == 0) {
        imageStore(tide_delta_out, ivec2(0, p.y), vec4(delta_m3, 0.0, 0.0, 1.0));
    }
}
