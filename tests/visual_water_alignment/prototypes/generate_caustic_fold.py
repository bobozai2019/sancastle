"""Build a seamless, deterministic display-only optical-fold candidate.

A band-limited random height field supplies local curvature. Near-zero ray-map
Jacobian contours form irregular light folds, without a regular cell lattice.
The generated image is only a W07 visual prototype, not simulation state.
"""

from pathlib import Path

import numpy as np
from PIL import Image


SIZE = 1024
SEED = 1702
OUT = Path(__file__).with_name("caustic_fold_v1.png")


def main() -> None:
    rng = np.random.default_rng(SEED)
    k = np.fft.fftfreq(SIZE).astype(np.float32) * SIZE
    kx, ky = np.meshgrid(k, k)
    kr = np.sqrt(kx * kx + ky * ky)
    band = np.exp(-0.5 * ((kr - 30.0) / 14.0) ** 2)
    band *= np.clip((kr - 6.0) / 6.0, 0.0, 1.0)
    spectrum = np.fft.fft2(rng.standard_normal((SIZE, SIZE))) * band
    hxx = np.fft.ifft2(spectrum * (-(2 * np.pi * kx) ** 2)).real
    hyy = np.fft.ifft2(spectrum * (-(2 * np.pi * ky) ** 2)).real
    hxy = np.fft.ifft2(spectrum * (-(2 * np.pi) ** 2 * kx * ky)).real
    curvature_scale = 0.91 / np.sqrt((hxx.var() + hyy.var()) * 0.5)
    determinant = (1.0 + curvature_scale * hxx) * (1.0 + curvature_scale * hyy)
    determinant -= (curvature_scale * hxy) ** 2

    # Smooth bright folds, with broader dim halos. A negative determinant still
    # marks a folded region; the border where it crosses zero is the bright line.
    narrow = np.exp(-((determinant / 0.17) ** 2))
    halo = np.exp(-((determinant / 0.48) ** 2))
    light = np.clip(0.78 * narrow + 0.22 * halo, 0.0, 1.0)
    image = np.rint(light * 255.0).astype(np.uint8)
    Image.fromarray(image, mode="L").save(OUT)
    print(f"{OUT}: {SIZE}x{SIZE}, seed {SEED}, curvature scale {curvature_scale:.6g}")


if __name__ == "__main__":
    main()
