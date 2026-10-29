#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D water_now;
layout(rg32f, set = 0, binding = 1) uniform restrict readonly image2D foam_previous;
layout(rg32f, set = 0, binding = 2) uniform restrict writeonly image2D front_out;
layout(r32f, set = 0, binding = 3) uniform restrict readonly image2D rock_now;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D sand_now;
layout(r32f, set = 0, binding = 5) uniform restrict readonly image2D bed_previous;

void main() {
    int z = int(gl_GlobalInvocationID.x);
    if (z >= 256) {
        return;
    }
    float sum_weight = 0.0;
    float sum_x = 0.0;
    float peak = 0.0;
    // One scan per coastline row and tick, using free-surface rise rather
    // than depth rise so a moving bed cannot impersonate an advancing wave.
    // The estuary's wet branches extend to x=91 in the reference bed. The
    // former x=112 lower bound silently omitted its largest advancing front.
    for (int x = 80; x < 248; x++) {
        float depth = max(imageLoad(water_now, ivec2(x, z)).r, 0.0);
        float earlier = max(imageLoad(foam_previous, ivec2(x, z)).g, 0.0);
        float bed = imageLoad(rock_now, ivec2(x, z)).r +
            imageLoad(sand_now, ivec2(x, z)).r;
        float old_bed = imageLoad(bed_previous, ivec2(x, z)).r;
        float wet = smoothstep(0.01, 0.04, depth);
        float score = max(depth + bed - earlier - old_bed, 0.0) * wet;
        float weight = score * score;
        sum_weight += weight;
        sum_x += float(x) * weight;
        peak = max(peak, score);
    }
    float front_x = sum_weight > 1e-12 ? sum_x / sum_weight : 0.0;
    imageStore(front_out, ivec2(z, 0), vec4(front_x, peak, 0.0, 1.0));
}
