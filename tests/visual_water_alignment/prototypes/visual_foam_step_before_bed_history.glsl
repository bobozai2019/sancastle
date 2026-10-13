#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rg32f, set = 0, binding = 0) uniform restrict readonly image2D history_in;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D water_now;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D momentum_x_now;
layout(r32f, set = 0, binding = 3) uniform restrict readonly image2D momentum_z_now;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D rock_now;
layout(r32f, set = 0, binding = 5) uniform restrict readonly image2D sand_now;
layout(rg32f, set = 0, binding = 6) uniform restrict writeonly image2D history_out;

layout(push_constant, std430) uniform Params {
    float delta_s;
    float cell_size_m;
    float lifetime_s;
    float source_gain;
} params;

ivec2 bounded(ivec2 cell) {
    return clamp(cell, ivec2(0), imageSize(water_now) - ivec2(1));
}

float water_at(ivec2 cell) {
    return max(imageLoad(water_now, bounded(cell)).r, 0.0);
}

vec2 flux_at(ivec2 cell) {
    ivec2 p = bounded(cell);
    return vec2(imageLoad(momentum_x_now, p).r,
        imageLoad(momentum_z_now, p).r);
}

float foam_at(vec2 cell) {
    vec2 p = clamp(cell, vec2(0.0), vec2(imageSize(history_in) - ivec2(1)));
    ivec2 low = ivec2(floor(p));
    vec2 t = fract(p);
    float a = imageLoad(history_in, bounded(low)).r;
    float b = imageLoad(history_in, bounded(low + ivec2(1, 0))).r;
    float c = imageLoad(history_in, bounded(low + ivec2(0, 1))).r;
    float d = imageLoad(history_in, bounded(low + ivec2(1, 1))).r;
    return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

void main() {
    ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(cell, imageSize(water_now)))) {
        return;
    }
    float depth = water_at(cell);
    if (depth < 0.0015) {
        imageStore(history_out, cell, vec4(0.0, depth, 0.0, 1.0));
        return;
    }
    vec2 q = flux_at(cell);
    vec2 velocity = q / max(depth, 0.02);
    float speed = min(length(velocity), 4.0);
    vec2 origin = vec2(cell) - velocity * (params.delta_s / params.cell_size_m);
    float carried = foam_at(origin) * exp(-params.delta_s / params.lifetime_s);
    float previous_depth = imageLoad(history_in, cell).g;
    float rise_rate = max((depth - previous_depth) / params.delta_s, 0.0);
    float divergence = ((flux_at(cell + ivec2(1, 0)).x -
        flux_at(cell - ivec2(1, 0)).x) +
        (flux_at(cell + ivec2(0, 1)).y -
        flux_at(cell - ivec2(0, 1)).y)) / (2.0 * params.cell_size_m);
    float compression = max(-divergence, 0.0);
    float bed = imageLoad(rock_now, cell).r + imageLoad(sand_now, cell).r;
    float bed_x = imageLoad(rock_now, bounded(cell + ivec2(1, 0))).r +
        imageLoad(sand_now, bounded(cell + ivec2(1, 0))).r;
    float bed_z = imageLoad(rock_now, bounded(cell + ivec2(0, 1))).r +
        imageLoad(sand_now, bounded(cell + ivec2(0, 1))).r;
    float slope = length(vec2(bed_x - bed, bed_z - bed)) / params.cell_size_m;
    float shallow = 1.0 - smoothstep(0.07, 0.22, depth);
    float motion = smoothstep(0.18, 0.75, speed);
    // A rising, compressing wave or advancing wet front can seed whitewater.
    // Static fast current alone has no source, and foam has finite lifetime.
    float rising_front = smoothstep(0.025, 0.085, rise_rate);
    float forcing = (max(rise_rate - 0.025, 0.0) * 0.65 +
        max(compression - 0.06, 0.0) * 0.25) * rising_front;
    float contact = clamp(shallow + 0.35 * slope, 0.0, 1.0);
    float created = params.source_gain * forcing * motion * contact * params.delta_s;
    float next_foam = clamp(carried + created, 0.0, 1.0);
    imageStore(history_out, cell, vec4(next_foam, depth, 0.0, 1.0));
}
