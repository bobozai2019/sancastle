#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D sediment_in;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D water_before;
layout(rgba32f, set = 0, binding = 2) uniform restrict readonly image2D outgoing_flux;
layout(r8, set = 0, binding = 3) uniform restrict readonly image2D obstacle_state;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D sand_in;
layout(r16f, set = 0, binding = 5) uniform restrict readonly image2D wetness_state;
layout(r16f, set = 0, binding = 6) uniform restrict readonly image2D compaction_state;
layout(r32f, set = 0, binding = 7) uniform restrict readonly image2D water_after;
layout(r32f, set = 0, binding = 8) uniform restrict writeonly image2D sand_out;
layout(r32f, set = 0, binding = 9) uniform restrict writeonly image2D sediment_out;
layout(r32ui, set = 0, binding = 10) uniform restrict uimage2D dirty_max_um;

layout(push_constant, std430) uniform Params {
    float delta_s;
    float cell_area_m2;
    float capacity_scale_s_per_m;
    float erosion_rate_per_s;
    float deposition_rate_per_s;
    float dry_depth_m;
    float reserved_0;
    float reserved_1;
} params;

// Flux channels are -X/+X/-Z/+Z, each in m3/s. Every transfer is
// evaluated from the donor's old concentration by both adjacent cells.
float transferred_sand(ivec2 donor, int direction) {
    precise float depth = imageLoad(water_before, donor).r;
    if (depth <= 0.00000001) {
        return 0.0;
    }
    precise float suspended = imageLoad(sediment_in, donor).r;
    precise vec4 flux = max(imageLoad(outgoing_flux, donor), vec4(0.0));
    precise float total_out_depth = dot(flux, vec4(1.0)) * params.delta_s / params.cell_area_m2;
    precise float direction_out_depth = flux[direction] * params.delta_s / params.cell_area_m2;
    // The water solver limits outflow. This second bound is defensive and
    // shared by donor and receiver, so it cannot manufacture or lose sand.
    precise float transfer_result = suspended * direction_out_depth / max(depth, total_out_depth);
    return transfer_result;
}

float retained_sand(ivec2 donor) {
    precise float depth = imageLoad(water_before, donor).r;
    precise float suspended = imageLoad(sediment_in, donor).r;
    if (depth <= 0.00000001) {
        return suspended;
    }
    precise vec4 flux = max(imageLoad(outgoing_flux, donor), vec4(0.0));
    precise float total_out_depth = dot(flux, vec4(1.0)) * params.delta_s / params.cell_area_m2;
    precise float retained_result = suspended * max(0.0, 1.0 - total_out_depth / max(depth, total_out_depth));
    return retained_result;
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(sediment_in);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    precise float bed_sand = imageLoad(sand_in, p).r;
    precise float previous_bed_sand = bed_sand;
    precise float suspended = imageLoad(sediment_in, p).r;
    precise float next_suspended = suspended;
    if (imageLoad(obstacle_state, p).r < 0.5) {
        next_suspended = retained_sand(p);
        if (p.x > 0) {
            next_suspended += transferred_sand(p + ivec2(-1, 0), 1);
        }
        if (p.x + 1 < extent.x) {
            next_suspended += transferred_sand(p + ivec2(1, 0), 0);
        }
        if (p.y > 0) {
            next_suspended += transferred_sand(p + ivec2(0, -1), 3);
        }
        if (p.y + 1 < extent.y) {
            next_suspended += transferred_sand(p + ivec2(0, 1), 2);
        }
        precise float depth_after = imageLoad(water_after, p).r;
        if (depth_after <= params.dry_depth_m) {
            bed_sand += next_suspended;
            next_suspended = 0.0;
        } else {
            precise vec4 flux = max(imageLoad(outgoing_flux, p), vec4(0.0));
            precise float speed_m_s = dot(flux, vec4(1.0)) / params.cell_area_m2;
            precise float strength = mix(0.7, 1.8, imageLoad(compaction_state, p).r)
                * mix(1.0, 1.25, imageLoad(wetness_state, p).r);
            precise float capacity_m = speed_m_s * depth_after
                * params.capacity_scale_s_per_m / strength;
            if (next_suspended < capacity_m) {
                precise float eroded = min(bed_sand, (capacity_m - next_suspended)
                    * params.erosion_rate_per_s * params.delta_s);
                bed_sand -= eroded;
                next_suspended += eroded;
            } else {
                precise float deposited = min(next_suspended, (next_suspended - capacity_m)
                    * params.deposition_rate_per_s * params.delta_s);
                bed_sand += deposited;
                next_suspended -= deposited;
            }
        }
    }
    imageStore(sand_out, p, vec4(bed_sand, 0.0, 0.0, 1.0));
    imageStore(sediment_out, p, vec4(next_suspended, 0.0, 0.0, 1.0));
    uint delta_um = uint(ceil(abs(bed_sand - previous_bed_sand) * 1000000.0));
    if (delta_um > 0u) {
        imageAtomicMax(dirty_max_um, p / 32, delta_um);
    }
}
