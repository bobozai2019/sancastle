#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D rock_state;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D sand_state;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D water_state;
layout(r32f, set = 0, binding = 3) uniform restrict readonly image2D momentum_x_state;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D momentum_z_state;
layout(r8, set = 0, binding = 5) uniform restrict readonly image2D obstacle_state;
// Each invocation owns only the +X and +Z edge originating at its cell.
// vec4 = signed water, X momentum, Z momentum, reserved.
layout(rgba32f, set = 0, binding = 6) uniform restrict writeonly image2D edge_x_out;
layout(rgba32f, set = 0, binding = 7) uniform restrict writeonly image2D edge_z_out;

const float GRAVITY = 9.81;
const float DRY_DEPTH = 0.001;
const float VELOCITY_DEPTH = 0.005;

struct Cell {
    float bed;
    float h;
    float qx;
    float qz;
    bool blocked;
};

Cell read_cell(ivec2 p) {
    Cell c;
    c.bed = imageLoad(rock_state, p).r + imageLoad(sand_state, p).r;
    c.h = imageLoad(water_state, p).r;
    c.qx = imageLoad(momentum_x_state, p).r;
    c.qz = imageLoad(momentum_z_state, p).r;
    c.blocked = imageLoad(obstacle_state, p).r >= 0.5;
    return c;
}

vec4 x_flux(Cell left, Cell right) {
    if (left.blocked || right.blocked) {
        return vec4(0.0);
    }
    float zmax = max(left.bed, right.bed);
    float hl = max(0.0, left.bed + left.h - zmax);
    float hr = max(0.0, right.bed + right.h - zmax);
    float ul = left.h > DRY_DEPTH ? left.qx / max(left.h, VELOCITY_DEPTH) : 0.0;
    float ur = right.h > DRY_DEPTH ? right.qx / max(right.h, VELOCITY_DEPTH) : 0.0;
    float vl = left.h > DRY_DEPTH ? left.qz / max(left.h, VELOCITY_DEPTH) : 0.0;
    float vr = right.h > DRY_DEPTH ? right.qz / max(right.h, VELOCITY_DEPTH) : 0.0;
    float qxl = hl * ul;
    float qxr = hr * ur;
    float qzl = hl * vl;
    float qzr = hr * vr;
    float wavespeed = max(abs(ul) + sqrt(GRAVITY * hl), abs(ur) + sqrt(GRAVITY * hr));
    float fh = 0.5 * (qxl + qxr) - 0.5 * wavespeed * (hr - hl);
    float fqx = 0.5 * (qxl * ul + qxr * ur + 0.5 * GRAVITY * (hl * hl + hr * hr)) - 0.5 * wavespeed * (qxr - qxl);
    float fqz = 0.5 * (qzl * ul + qzr * ur) - 0.5 * wavespeed * (qzr - qzl);
    return vec4(fh, fqx, fqz, 0.0);
}

vec4 z_flux(Cell top, Cell bottom) {
    if (top.blocked || bottom.blocked) {
        return vec4(0.0);
    }
    float zmax = max(top.bed, bottom.bed);
    float ht = max(0.0, top.bed + top.h - zmax);
    float hb = max(0.0, bottom.bed + bottom.h - zmax);
    float ut = top.h > DRY_DEPTH ? top.qx / max(top.h, VELOCITY_DEPTH) : 0.0;
    float ub = bottom.h > DRY_DEPTH ? bottom.qx / max(bottom.h, VELOCITY_DEPTH) : 0.0;
    float vt = top.h > DRY_DEPTH ? top.qz / max(top.h, VELOCITY_DEPTH) : 0.0;
    float vb = bottom.h > DRY_DEPTH ? bottom.qz / max(bottom.h, VELOCITY_DEPTH) : 0.0;
    float qxt = ht * ut;
    float qxb = hb * ub;
    float qzt = ht * vt;
    float qzb = hb * vb;
    float wavespeed = max(abs(vt) + sqrt(GRAVITY * ht), abs(vb) + sqrt(GRAVITY * hb));
    float fh = 0.5 * (qzt + qzb) - 0.5 * wavespeed * (hb - ht);
    float fqz = 0.5 * (qzt * vt + qzb * vb + 0.5 * GRAVITY * (ht * ht + hb * hb)) - 0.5 * wavespeed * (qzb - qzt);
    float fqx = 0.5 * (qxt * vt + qxb * vb) - 0.5 * wavespeed * (qxb - qxt);
    return vec4(fh, fqx, fqz, 0.0);
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(water_state);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    Cell center = read_cell(p);
    vec4 fx = p.x + 1 < extent.x ? x_flux(center, read_cell(p + ivec2(1, 0))) : vec4(0.0);
    vec4 fz = p.y + 1 < extent.y ? z_flux(center, read_cell(p + ivec2(0, 1))) : vec4(0.0);
    imageStore(edge_x_out, p, fx);
    imageStore(edge_z_out, p, fz);
}
