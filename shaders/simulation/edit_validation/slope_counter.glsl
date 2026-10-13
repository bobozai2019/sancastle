#[compute]
#version 450

// T05 conservative slope relaxation (sand slumping).
//
// Every shared edge is evaluated from the same input state by both of its cells,
// so the donor and the receiver always agree on the transferred depth and the
// global sand total is unchanged by construction. There is no height filtering:
// a cell only moves sand to a lower neighbour when its surface exceeds that
// neighbour's by more than the wetness/compaction-dependent angle of repose, so
// the surface settles onto the repose slope and stops on its own.
//
// Per-edge motion is additionally capped at a quarter of the donor's available
// sand, which bounds the sum over a cell's four edges by its whole stock and
// therefore keeps the donor non-negative without any clamping.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D sand_in;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D rock_state;
layout(r16f, set = 0, binding = 2) uniform restrict readonly image2D wetness_in;
layout(r16f, set = 0, binding = 3) uniform restrict readonly image2D compaction_in;
layout(r8, set = 0, binding = 4) uniform restrict readonly image2D obstacle_state;
layout(r32f, set = 0, binding = 5) uniform restrict writeonly image2D sand_out;
// Slumping moves the bed without any water, so it must feed the same 32² dirty
// summary the erosion pass uses or the collision proxy would miss it.
layout(r32ui, set = 0, binding = 6) uniform restrict uimage2D dirty_max_um;

layout(set=0,binding=7,std430) buffer DebugSlope { uint hits[4]; uint records[]; } debug_slope;
layout(push_constant, std430) uniform Params {
    float delta_s;
    float cell_size_m;
    float relax_rate_per_s;
    float dry_repose_tan;
    float wet_repose_tan;
    float compaction_repose_gain;
    float min_drop_m;
    float cohesion_yield_height_m;
} params;

const ivec2 OFFSETS[4] = {ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1)};

// The angle of repose depends on both cells of the edge, so both of them derive
// the same threshold from the same shared inputs.
float repose_drop(ivec2 a, ivec2 b) {
    float wetness = 0.5 * (imageLoad(wetness_in, a).r + imageLoad(wetness_in, b).r);
    float compaction = 0.5 * (imageLoad(compaction_in, a).r
        + imageLoad(compaction_in, b).r);
    float tan_angle = mix(params.dry_repose_tan, params.wet_repose_tan, wetness);
    tan_angle += params.compaction_repose_gain * compaction;
    float donor_compaction = imageLoad(compaction_in, a).r;
    float donor_wetness = imageLoad(wetness_in, a).r;
    float moisture_factor = 0.8 + 0.2 * smoothstep(0.05, 0.35, donor_wetness)
        - 0.6 * smoothstep(0.65, 1.0, donor_wetness);
    float cohesion = params.cohesion_yield_height_m
        * clamp((donor_compaction - 0.6) / 0.35, 0.0, 1.0) * moisture_factor;
    return max(tan_angle * params.cell_size_m, params.min_drop_m) + cohesion;
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(sand_in);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    float sand = imageLoad(sand_in, p).r;
    float next_sand = sand;
    if (imageLoad(obstacle_state, p).r < 0.5) {
        float surface = imageLoad(rock_state, p).r + sand;
        float blend = clamp(params.relax_rate_per_s * params.delta_s, 0.0, 1.0);
        for (int direction = 0; direction < 4; ++direction) {
            ivec2 q = p + OFFSETS[direction];
            if (q.x < 0 || q.y < 0 || q.x >= extent.x || q.y >= extent.y) {
                continue;
            }
            if (imageLoad(obstacle_state, q).r >= 0.5) {
                continue;
            }
            float neighbour_sand = imageLoad(sand_in, q).r;
            float neighbour_surface = imageLoad(rock_state, q).r + neighbour_sand;
            bool p_is_donor = surface >= neighbour_surface;
            ivec2 donor = p_is_donor ? p : q;
            ivec2 receiver = p_is_donor ? q : p;
            float drop = abs(surface - neighbour_surface);
            float excess = drop - repose_drop(donor, receiver);
            if (excess <= 0.0) {
                continue;
            }
            float donor_sand = p_is_donor ? sand : neighbour_sand;
            float moved = min(excess * 0.5 * blend, donor_sand * 0.25);
            if (moved <= 0.0) {
                continue;
            }
            // Both cells evaluate this edge identically; p adds what it receives
            // and subtracts what it gives away, so the pair nets to zero.
            next_sand += p_is_donor ? -moved : moved;
        }
    }
    imageStore(sand_out, p, vec4(max(next_sand, 0.0), 0.0, 0.0, 1.0));
    uint delta_um = uint(ceil(abs(next_sand - sand) * 1000000.0));
    if (delta_um > 0u) {
        imageAtomicMax(dirty_max_um, p / 32, delta_um);
    }
    uint cell=uint(p.y*extent.x+p.x);
    const uint ids[4]=uint[4](25525u,27334u,28096u,40900u);
    for(uint slot=0u;slot<4u;slot++) if(cell==ids[slot]) atomicAdd(debug_slope.hits[slot],1u);
}
