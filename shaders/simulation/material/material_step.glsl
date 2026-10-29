#[compute]
#version 450

// T05 wetness / compaction evolution.
//
// Wetness wets from standing water, spreads laterally by a bounded four-neighbour
// exchange, and drains towards a residual once the water is gone. Compaction
// rises asymptotically towards 1 under wetness and never decreases: compaction
// remembers that the sand was once packed. Neither field creates or removes sand
// mass; they only modulate the erosion strength curve in sediment_step.glsl.
//
// The water solver flips its ping-pong index every substep, so this pass reads
// the current slot and writes the other one; material_commit.glsl then copies
// the other slot back so both slots agree with the solver index at all times.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r16f, set = 0, binding = 0) uniform restrict readonly image2D wetness_in;
layout(r16f, set = 0, binding = 1) uniform restrict readonly image2D compaction_in;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D water_in;
layout(r32f, set = 0, binding = 3) uniform restrict readonly image2D sand_in;
layout(r8, set = 0, binding = 4) uniform restrict readonly image2D obstacle_state;
layout(r16f, set = 0, binding = 5) uniform restrict writeonly image2D wetness_out;
layout(r16f, set = 0, binding = 6) uniform restrict writeonly image2D compaction_out;

layout(push_constant, std430) uniform Params {
    float delta_s;
    float wet_rate_per_s;
    float dry_rate_per_s;
    float diffusion_per_s;
    float residual_wetness;
    float soak_depth_m;
    float dry_depth_m;
    float compact_rate_per_s;
} params;

float wetness_at(ivec2 p, ivec2 extent) {
    ivec2 clamped = clamp(p, ivec2(0), extent - ivec2(1));
    return imageLoad(wetness_in, clamped).r;
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(wetness_in);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    float wet = imageLoad(wetness_in, p).r;
    float compact = imageLoad(compaction_in, p).r;
    float depth = imageLoad(water_in, p).r;
    bool blocked = imageLoad(obstacle_state, p).r >= 0.5;

    float next = wet;
    float next_compact = compact;
    if (!blocked) {
        // Wetness moves at a fixed rate rather than a shrinking fraction of the
        // remaining distance. R16F cannot represent increments below one ulp, so
        // a shrinking gain stalls about 2% short of saturation; a constant-rate
        // front reaches the target exactly and is also easier to reason about.
        float target = clamp(depth / max(params.soak_depth_m, 0.000001), 0.0, 1.0);
        if (depth > params.dry_depth_m) {
            float advance = params.wet_rate_per_s * params.delta_s * target;
            next = min(max(wet, target), wet + advance);
        } else {
            next = max(params.residual_wetness, wet - params.dry_rate_per_s * params.delta_s);
        }
        // Capillary spread: a symmetric Laplacian, so it can neither create nor
        // destroy wetness, only redistribute it. The clamp keeps it stable.
        float neighbour_sum = wetness_at(p + ivec2(-1, 0), extent)
            + wetness_at(p + ivec2(1, 0), extent)
            + wetness_at(p + ivec2(0, -1), extent)
            + wetness_at(p + ivec2(0, 1), extent);
        float spread = clamp(params.diffusion_per_s * params.delta_s, 0.0, 0.5);
        next += spread * (neighbour_sum - 4.0 * wet) * 0.25;
        // Wet sand packs under its own weight. Only wetness above the residual
        // counts, so ambient dampness alone never packs the beach, and the
        // approach is asymptotic and monotone: compaction cannot stack without
        // bound and dry sand never loosens.
        float excess_wetness = max(next - params.residual_wetness, 0.0);
        next_compact = compact + excess_wetness * params.compact_rate_per_s
            * params.delta_s * (1.0 - compact);
    }
    next = clamp(next, 0.0, 1.0);
    next_compact = clamp(next_compact, 0.0, 1.0);
    imageStore(wetness_out, p, vec4(next, 0.0, 0.0, 1.0));
    imageStore(compaction_out, p, vec4(next_compact, 0.0, 0.0, 1.0));
}
