"""Generate the deterministic, seamless W07 caustic-shape prototype texture.

This is a display resource only. The water and sand simulation never consume it.
Run from the project root with Python, NumPy and Pillow installed.
"""

from pathlib import Path

import numpy as np
from PIL import Image


SIZE = 1024
CELLS = 64
SEED = 1701
OUT = Path(__file__).with_name("caustic_cells_v1.png")


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def main() -> None:
    rng = np.random.default_rng(SEED)
    jitter = rng.uniform(-0.36, 0.36, (CELLS, CELLS, 2)).astype(np.float32)
    pixel = (np.arange(SIZE, dtype=np.float32) + 0.5) / SIZE
    u, v = np.meshgrid(pixel, pixel)

    # Integer-frequency domain warps keep the tile's opposite edges continuous.
    px = u * CELLS + 0.34 * np.sin(2 * np.pi * (3 * v + 2 * u))
    px += 0.19 * np.sin(2 * np.pi * (7 * v - 5 * u))
    py = v * CELLS + 0.31 * np.cos(2 * np.pi * (4 * u - 3 * v))
    py += 0.17 * np.sin(2 * np.pi * (5 * u + 6 * v))

    cell_x = np.floor(px).astype(np.int32)
    cell_y = np.floor(py).astype(np.int32)
    nearest = np.full((SIZE, SIZE), np.inf, dtype=np.float32)
    second = np.full((SIZE, SIZE), np.inf, dtype=np.float32)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            sx = cell_x + dx
            sy = cell_y + dy
            key = jitter[sy % CELLS, sx % CELLS]
            dist = (px - (sx + 0.5 + key[..., 0])) ** 2
            dist += (py - (sy + 0.5 + key[..., 1])) ** 2
            second = np.minimum(second, np.maximum(nearest, dist))
            nearest = np.minimum(nearest, dist)

    # The first/second site distance gap shrinks along irregular cell borders.
    gap = np.sqrt(second) - np.sqrt(nearest)
    ridge = 1.0 - smoothstep(0.025, 0.18, gap)
    modulation = 0.82 + 0.18 * np.sin(2 * np.pi * (11 * u + 9 * v))
    result = np.rint(np.clip(ridge * modulation, 0.0, 1.0) * 255).astype(np.uint8)
    Image.fromarray(result, mode="L").save(OUT)
    print(f"{OUT}: {SIZE}x{SIZE}, {CELLS} cells, seed {SEED}")


if __name__ == "__main__":
    main()
