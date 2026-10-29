#[compute]
#version 450

// T06 structural obstacle remap.
//
// The contract forbids changing the obstacle mask without remapping the water
// volume ("不得只改障碍 mask 而不重映射水体积"), and NUM-08 adds that water must
// not end up permanently invisible. This pass enforces both as an invariant
// rather than as a diff against the previous mask:
//
//   * a blocked cell must hold no water, and
//   * whatever it held is pushed onto its open neighbours instead of vanishing.
//
// Because the rule is stateless it is idempotent: running it after every
// structural event converges, and running it when nothing changed is a no-op.
// Each shared edge is evaluated from the same inputs by both of its cells, so
// the water and suspended-sand totals are unchanged by construction.
//
// A blocked cell with no open neighbour cannot drain. Its load is kept in place
// and its tile is flagged in `remap_tiles` so the caller can count it instead of
// silently losing it. The tile value distinguishes the two signals:
//   1 = this tile's water changed
//   2 = this tile still holds water inside a blocked pocket (needs attention)
// `imageAtomicMax` keeps the stronger signal when a tile has both.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r8, set = 0, binding = 0) uniform restrict readonly image2D obstacle_state;
layout(r32f, set = 0, binding = 1) uniform restrict readonly image2D water_in;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D momentum_x_in;
layout(r32f, set = 0, binding = 3) uniform restrict readonly image2D momentum_z_in;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D sediment_in;
layout(r32f, set = 0, binding = 5) uniform restrict writeonly image2D water_out;
layout(r32f, set = 0, binding = 6) uniform restrict writeonly image2D momentum_x_out;
layout(r32f, set = 0, binding = 7) uniform restrict writeonly image2D momentum_z_out;
layout(r32f, set = 0, binding = 8) uniform restrict writeonly image2D sediment_out;
layout(r32ui, set = 0, binding = 9) uniform restrict uimage2D remap_tiles;

const ivec2 OFFSETS[4] = {ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1)};

bool blocked_at(ivec2 p, ivec2 extent) {
    if (p.x < 0 || p.y < 0 || p.x >= extent.x || p.y >= extent.y) {
        return true;
    }
    return imageLoad(obstacle_state, p).r >= 0.5;
}

int open_neighbours(ivec2 p, ivec2 extent) {
    int count = 0;
    for (int direction = 0; direction < 4; ++direction) {
        if (!blocked_at(p + OFFSETS[direction], extent)) {
            count += 1;
        }
    }
    return count;
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    ivec2 extent = imageSize(water_in);
    if (p.x >= extent.x || p.y >= extent.y) {
        return;
    }
    float water = imageLoad(water_in, p).r;
    float sediment = imageLoad(sediment_in, p).r;
    float momentum_x = imageLoad(momentum_x_in, p).r;
    float momentum_z = imageLoad(momentum_z_in, p).r;

    if (blocked_at(p, extent)) {
        int open = open_neighbours(p, extent);
        if (open == 0) {
            // Nowhere to drain: keep the load so it stays accounted, and let the
            // caller count that it is still there.
            imageStore(water_out, p, vec4(water, 0.0, 0.0, 1.0));
            imageStore(sediment_out, p, vec4(sediment, 0.0, 0.0, 1.0));
            imageStore(momentum_x_out, p, vec4(momentum_x, 0.0, 0.0, 1.0));
            imageStore(momentum_z_out, p, vec4(momentum_z, 0.0, 0.0, 1.0));
            if (water > 0.0 || sediment > 0.0) {
                imageAtomicMax(remap_tiles, p / 32, 2u);
            }
            return;
        }
    }

    // Gather: start from what this cell already has, then take the share every
    // newly blocked neighbour owes it. A blocked cell gives everything away.
    float next_water = water;
    float next_sediment = sediment;
    float next_momentum_x = momentum_x;
    float next_momentum_z = momentum_z;
    if (blocked_at(p, extent)) {
        next_water = 0.0;
        next_sediment = 0.0;
        // A blocked cell has no coherent flow direction; its momentum is dropped
        // rather than redirected. Momentum is not one of the contract's ledger
        // quantities, and the water solver already zeroes it on dry cells.
        next_momentum_x = 0.0;
        next_momentum_z = 0.0;
    } else {
        for (int direction = 0; direction < 4; ++direction) {
            ivec2 neighbour = p + OFFSETS[direction];
            if (neighbour.x < 0 || neighbour.y < 0 || neighbour.x >= extent.x ||
                    neighbour.y >= extent.y) {
                continue;
            }
            if (!blocked_at(neighbour, extent)) {
                continue;
            }
            int donor_open = open_neighbours(neighbour, extent);
            if (donor_open == 0) {
                continue;
            }
            // The arriving water is treated as at rest, so an open cell keeps
            // its own momentum untouched.
            next_water += imageLoad(water_in, neighbour).r / float(donor_open);
            next_sediment += imageLoad(sediment_in, neighbour).r / float(donor_open);
        }
    }
    imageStore(water_out, p, vec4(next_water, 0.0, 0.0, 1.0));
    imageStore(sediment_out, p, vec4(next_sediment, 0.0, 0.0, 1.0));
    imageStore(momentum_x_out, p, vec4(next_momentum_x, 0.0, 0.0, 1.0));
    imageStore(momentum_z_out, p, vec4(next_momentum_z, 0.0, 0.0, 1.0));
    if (abs(next_water - water) > 0.0 || abs(next_sediment - sediment) > 0.0) {
        imageAtomicMax(remap_tiles, p / 32, 1u);
    }
}
