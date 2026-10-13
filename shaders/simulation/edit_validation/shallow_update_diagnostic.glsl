#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D rock_state;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D sand_state;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D water_in;
layout(r32f, set = 0, binding = 3) uniform restrict readonly image2D momentum_x_in;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D momentum_z_in;
layout(r8, set = 0, binding = 5) uniform restrict readonly image2D obstacle_state;
layout(rgba32f, set = 0, binding = 6) uniform restrict readonly image2D edge_x_state;
layout(rgba32f, set = 0, binding = 7) uniform restrict readonly image2D edge_z_state;
layout(r32f, set = 0, binding = 8) uniform restrict readonly image2D drain_scale_state;
layout(r32f, set = 0, binding = 9) uniform restrict writeonly image2D water_out;
layout(r32f, set = 0, binding = 10) uniform restrict writeonly image2D momentum_x_out;
layout(r32f, set = 0, binding = 11) uniform restrict writeonly image2D momentum_z_out;
layout(rgba32f, set = 0, binding = 12) uniform restrict writeonly image2D outgoing_flux_out;

struct StepDiagnostic { vec4 loss; uvec4 events; };
layout(set=0,binding=13,std430) buffer Diagnostics { StepDiagnostic diagnostic[]; };
void record_loss(ivec2 p,vec2 raw,vec2 result,float depth,uint kind) {
    vec2 removed=raw-result;
    if(all(equal(removed,vec2(0.0)))) return;
    uint i=uint(p.y*imageSize(water_in).x+p.x);
    diagnostic[i].loss.xy+=removed;
    diagnostic[i].loss.w+=abs(removed.x)+abs(removed.y);
    diagnostic[i].events[kind]++;
    if(depth>0.0) diagnostic[i].loss.z+=0.5*(dot(raw,raw)-dot(result,result))/depth;
    else diagnostic[i].events.w++;
}
void record_state(ivec2 p,float depth,vec2 q) {
    uint i=uint(p.y*imageSize(water_in).x+p.x);
    uint flags=0u;
    if(isnan(depth)||isinf(depth)||any(isnan(q))||any(isinf(q))) flags|=1u;
    if(depth<0.0) flags|=2u;
    if(depth<=0.001&&any(notEqual(q,vec2(0.0)))) flags|=4u;
    diagnostic[i].events.w|=flags<<24u;
}
layout(push_constant, std430) uniform Params {
    float delta_over_cell_size;
    float cell_size_m;
    float ocean_boundary_enabled;
    float reserved;
} params;

const float GRAVITY = 9.81;
const float DRY_DEPTH = 0.001;

float bed_at(ivec2 p) {
    return imageLoad(rock_state, p).r + imageLoad(sand_state, p).r;
}

bool blocked(ivec2 p) {
    return imageLoad(obstacle_state, p).r >= 0.5;
}

float scaled_edge_mass(vec4 edge, ivec2 first, ivec2 second) {
    float donor_scale = imageLoad(drain_scale_state, edge.r > 0.0 ? first : second).r;
    return edge.r * donor_scale;
}

float scaled_edge_momentum(vec4 edge, ivec2 first, ivec2 second, int component) {
    float donor_scale = imageLoad(drain_scale_state, edge.r > 0.0 ? first : second).r;
    return edge[component] * donor_scale;
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(water_in);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    float h = imageLoad(water_in, p).r;
    if (blocked(p)) {
        record_loss(p,vec2(imageLoad(momentum_x_in,p).r,imageLoad(momentum_z_in,p).r),vec2(0.0),h,2u);
        record_state(p,h,vec2(0.0));
        imageStore(water_out, p, vec4(h, 0.0, 0.0, 1.0));
        imageStore(momentum_x_out, p, vec4(0.0));
        imageStore(momentum_z_out, p, vec4(0.0));
        imageStore(outgoing_flux_out, p, vec4(0.0));
        return;
    }
    float bed = bed_at(p);
    float qx = imageLoad(momentum_x_in, p).r;
    float qz = imageLoad(momentum_z_in, p).r;
    float ratio = params.delta_over_cell_size;
    float pressure = 0.5 * GRAVITY * h * h;
    float left_mass = 0.0;
    float right_mass = 0.0;
    float top_mass = 0.0;
    float bottom_mass = 0.0;
    float left_qx = 0.0;
    float right_qx = 0.0;
    float top_qx = 0.0;
    float bottom_qx = 0.0;
    float left_qz = 0.0;
    float right_qz = 0.0;
    float top_qz = 0.0;
    float bottom_qz = 0.0;
    float left_pressure = pressure;
    float right_pressure = pressure;
    float top_pressure = pressure;
    float bottom_pressure = pressure;
    if (p.x > 0 && !blocked(p + ivec2(-1, 0))) {
        ivec2 neighbor = p + ivec2(-1, 0);
        vec4 edge = imageLoad(edge_x_state, neighbor);
        left_mass = scaled_edge_mass(edge, neighbor, p);
        left_qx = scaled_edge_momentum(edge, neighbor, p, 1);
        left_qz = scaled_edge_momentum(edge, neighbor, p, 2);
        float reconstructed = max(0.0, bed + h - max(bed, bed_at(neighbor)));
        left_pressure = 0.5 * GRAVITY * (h * h - reconstructed * reconstructed);
    }
    if (p.x + 1 < extent.x && !blocked(p + ivec2(1, 0))) {
        ivec2 neighbor = p + ivec2(1, 0);
        vec4 edge = imageLoad(edge_x_state, p);
        right_mass = scaled_edge_mass(edge, p, neighbor);
        right_qx = scaled_edge_momentum(edge, p, neighbor, 1);
        right_qz = scaled_edge_momentum(edge, p, neighbor, 2);
        float reconstructed = max(0.0, bed + h - max(bed, bed_at(neighbor)));
        right_pressure = 0.5 * GRAVITY * (h * h - reconstructed * reconstructed);
    }
    if (p.y > 0 && !blocked(p + ivec2(0, -1))) {
        ivec2 neighbor = p + ivec2(0, -1);
        vec4 edge = imageLoad(edge_z_state, neighbor);
        top_mass = scaled_edge_mass(edge, neighbor, p);
        top_qx = scaled_edge_momentum(edge, neighbor, p, 1);
        top_qz = scaled_edge_momentum(edge, neighbor, p, 2);
        float reconstructed = max(0.0, bed + h - max(bed, bed_at(neighbor)));
        top_pressure = 0.5 * GRAVITY * (h * h - reconstructed * reconstructed);
    }
    if (p.y + 1 < extent.y && !blocked(p + ivec2(0, 1))) {
        ivec2 neighbor = p + ivec2(0, 1);
        vec4 edge = imageLoad(edge_z_state, p);
        bottom_mass = scaled_edge_mass(edge, p, neighbor);
        bottom_qx = scaled_edge_momentum(edge, p, neighbor, 1);
        bottom_qz = scaled_edge_momentum(edge, p, neighbor, 2);
        float reconstructed = max(0.0, bed + h - max(bed, bed_at(neighbor)));
        bottom_pressure = 0.5 * GRAVITY * (h * h - reconstructed * reconstructed);
    }
    float next_h = max(0.0, h + ratio * (left_mass - right_mass + top_mass - bottom_mass));
    float next_qx = qx + ratio * ((left_qx + left_pressure) - (right_qx + right_pressure) + top_qx - bottom_qx);
    float next_qz = qz + ratio * ((top_qz + top_pressure) - (bottom_qz + bottom_pressure) + left_qz - right_qz);
    vec2 diagnostic_raw=vec2(next_qx,next_qz);
    uint diagnostic_kind=0u;
    if (next_h <= DRY_DEPTH || (params.ocean_boundary_enabled > 0.5 && p.x == 0)) {
        next_qx = 0.0;
        next_qz = 0.0;
    } else {
        float momentum_length = length(vec2(next_qx, next_qz));
        float max_velocity = max(1.5, 3.0 * sqrt(GRAVITY * next_h));
        float max_momentum = max_velocity * next_h;
        if (momentum_length > max_momentum) {
            diagnostic_kind=1u;
            float scale = max_momentum / momentum_length;
            next_qx *= scale;
            next_qz *= scale;
        }
    }
    record_loss(p,diagnostic_raw,vec2(next_qx,next_qz),next_h,diagnostic_kind);
    record_state(p,next_h,vec2(next_qx,next_qz));
    imageStore(water_out, p, vec4(next_h, 0.0, 0.0, 1.0));
    imageStore(momentum_x_out, p, vec4(next_qx, 0.0, 0.0, 1.0));
    imageStore(momentum_z_out, p, vec4(next_qz, 0.0, 0.0, 1.0));
    imageStore(outgoing_flux_out, p, vec4(max(-left_mass, 0.0), max(right_mass, 0.0),
        max(-top_mass, 0.0), max(bottom_mass, 0.0)) * params.cell_size_m);
}


