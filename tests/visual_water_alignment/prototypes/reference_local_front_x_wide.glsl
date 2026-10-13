#[compute]
#version 450

// W09 display-only trial: wider per-cell support while retaining a local
// centroid, so separate wave branches are not collapsed into a row mean.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D water_now;
layout(rg32f, set = 0, binding = 1) uniform restrict readonly image2D foam_previous;
layout(rgba32f, set = 0, binding = 2) uniform restrict writeonly image2D x_out;
layout(r32f, set = 0, binding = 3) uniform restrict readonly image2D rock_now;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D sand_now;
layout(r32f, set = 0, binding = 5) uniform restrict readonly image2D bed_previous;

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p, ivec2(256)))) {
        return;
    }
    float sum_weight = 0.0;
    float sum_x_weight = 0.0;
    float peak = 0.0;
    for (int dx = -12; dx <= 12; dx++) {
        ivec2 q = clamp(p + ivec2(dx, 0), ivec2(0), ivec2(255));
        float depth = max(imageLoad(water_now, q).r, 0.0);
        float previous_depth = max(imageLoad(foam_previous, q).g, 0.0);
        float bed = imageLoad(rock_now, q).r + imageLoad(sand_now, q).r;
        float old_bed = imageLoad(bed_previous, q).r;
        float score = max(depth + bed - previous_depth - old_bed, 0.0) *
            smoothstep(0.01, 0.04, depth);
        float window = 1.0 - float(abs(dx)) / 13.0;
        float weight = score * score * window;
        sum_weight += weight;
        sum_x_weight += float(q.x) * weight;
        peak = max(peak, score * window);
    }
    imageStore(x_out, p, vec4(sum_weight, sum_x_weight, peak, 0.0));
}
