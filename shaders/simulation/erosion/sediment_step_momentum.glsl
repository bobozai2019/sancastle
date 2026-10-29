#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D sediment_in;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D water_before;
layout(rgba32f, set = 0, binding = 2) uniform restrict readonly image2D outgoing_flux;
layout(r8, set = 0, binding = 3) uniform restrict readonly image2D obstacle_state;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D sand_in;
layout(rg32f, set = 0, binding = 5) uniform restrict readonly image2D momentum_after;

layout(r32f, set = 0, binding = 6) uniform restrict readonly image2D water_after;
layout(r32f, set = 0, binding = 7) uniform restrict writeonly image2D sand_out;
layout(r32f, set = 0, binding = 8) uniform restrict writeonly image2D sediment_out;
layout(r32ui, set = 0, binding = 9) uniform restrict uimage2D dirty_max_um;

layout(push_constant, std430) uniform Params {
    float delta_s;
    float cell_area_m2;
    float capacity_per_speed_s;
    float erosion_fraction;
    float deposition_fraction;
    float dry_depth_m;
    float capacity_saturation_depth_m;
    float ocean_boundary_enabled;
} params;

// Flux channels are -X/+X/-Z/+Z, each in m3/s. Every transfer is
// evaluated from the donor's old concentration by both adjacent cells.
float transferred_sand(ivec2 donor, int direction) {
    float depth = imageLoad(water_before, donor).r;
    if (depth <= 0.00000001) {
        return 0.0;
    }
    float suspended = imageLoad(sediment_in, donor).r;
    vec4 flux = max(imageLoad(outgoing_flux, donor), vec4(0.0));
    float total_out_depth = dot(flux, vec4(1.0)) * params.delta_s / params.cell_area_m2;
    float direction_out_depth = flux[direction] * params.delta_s / params.cell_area_m2;
    // The water solver limits outflow. This second bound is defensive and
    // shared by donor and receiver, so it cannot manufacture or lose sand.
    return suspended * direction_out_depth / max(depth, total_out_depth);
}

float retained_sand(ivec2 donor) {
    float depth = imageLoad(water_before, donor).r;
    float suspended = imageLoad(sediment_in, donor).r;
    if (depth <= 0.00000001) {
        return suspended;
    }
    vec4 flux = max(imageLoad(outgoing_flux, donor), vec4(0.0));
    float total_out_depth = dot(flux, vec4(1.0)) * params.delta_s / params.cell_area_m2;
    return suspended * max(0.0, 1.0 - total_out_depth / max(depth, total_out_depth));
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(sediment_in);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    float bed_sand = imageLoad(sand_in, p).r;
    float previous_bed_sand = bed_sand;
    float suspended = imageLoad(sediment_in, p).r;
    float next_suspended = suspended;
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
        float depth_after = imageLoad(water_after, p).r;
        // Competitor SAND-EROSION-01: capacity uses speed magnitude and a
        // saturating effective-water weight, without material-strength scaling.
        // Our water already stores effective depth; do not subtract its encoded
        // amount's 0.05 bias again. The meter scale is a Godot adaptation.
        float capacity_m = 0.0;
        if (depth_after > params.dry_depth_m) {
            vec2 momentum = imageLoad(momentum_after,p).rg;
            float speed_m_s = length(momentum) / max(depth_after, 0.005);
            float water_weight = min(depth_after / params.capacity_saturation_depth_m, 1.0);
            capacity_m = water_weight * params.capacity_per_speed_s * speed_m_s;
        }
        // Protect only our actual forced reservoir (x=0). We do not have the
        // original packed, graded sea mask. Closed/injection domains are free.
        float exchange_weight = params.ocean_boundary_enabled > 0.5 && p.x == 0 ? 0.0 : 1.0;
        if (next_suspended < capacity_m) {
            float eroded = min(bed_sand, (capacity_m - next_suspended)
                * params.erosion_fraction * exchange_weight);
            bed_sand -= eroded;
            next_suspended += eroded;
        } else {
            // Dry cells have zero capacity and settle gradually by this same
            // rule; retaining residual suspended stock preserves the ledger.
            float deposited = min(next_suspended, (next_suspended - capacity_m)
                * params.deposition_fraction * exchange_weight);
            bed_sand += deposited;
            next_suspended -= deposited;
        }
    }
    imageStore(sand_out, p, vec4(bed_sand, 0.0, 0.0, 1.0));
    imageStore(sediment_out, p, vec4(next_suspended, 0.0, 0.0, 1.0));
    uint delta_um = uint(ceil(abs(bed_sand - previous_bed_sand) * 1000000.0));
    if (delta_um > 0u) {
        imageAtomicMax(dirty_max_um, p / 32, delta_um);
    }
}
