"""Leaf and needle masks for assets/desert/foliage.gdshader.

Draws, once, what the shader would otherwise draw per pixel: small pointed
leaflets thinning toward the card's edge (leaves.png) and a pine sprig, a
twig with needles slanting off it (needles.png). Red is coverage, green a
per-leaf number for colour variation, blue the twig.

Run with any Python 3 that has numpy:
    python3 Sources/make_foliage_masks.py
"""

import struct
import zlib
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parents[1] / "assets/desert"
SIZE = 512
SUPER = 3


def hash2(x, y):
    return np.modf(np.abs(np.sin(x * 127.1 + y * 311.7) * 43758.5453))[0]


def grid(n):
    t = (np.arange(n) + 0.5) / n
    return np.meshgrid(t, t)


def leaflets(cells=13.0, density=0.9):
    u, v = grid(SIZE * SUPER)
    c = np.stack([u - 0.5, v - 0.5])
    a = 0.52
    gx = (np.cos(a) * c[0] - np.sin(a) * c[1]) * cells
    gy = (np.sin(a) * c[0] + np.cos(a) * c[1]) * cells
    cx, cy = np.floor(gx), np.floor(gy)
    best = np.full(gx.shape, -1.0)
    ident = np.zeros(gx.shape)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx, ny = cx + ox, cy + oy
            h = hash2(nx, ny)
            h2 = hash2(nx + 17.3, ny + 17.3)
            px = nx + 0.5 + (h - 0.5) * 0.7
            py = ny + 0.5 + (h2 - 0.5) * 0.7
            r = np.hypot(px, py) / cells
            keep = (1.0 - np.clip((r - 0.18) / 0.3, 0, 1) ** 2 * (3 - 2 * np.clip((r - 0.18) / 0.3, 0, 1))) * density
            ang = h * 6.2831
            dx, dy = gx - px, gy - py
            rx = np.cos(ang) * dx + np.sin(ang) * dy
            ry = -np.sin(ang) * dx + np.cos(ang) * dy
            size = 0.34 + 0.16 * hash2(nx + 3.1, ny + 3.1)
            along = rx / size
            leaf = 0.36 * (1 - along * along) - np.abs(ry) / size
            leaf = np.where(h2 > keep, -1.0, leaf)
            better = leaf > best
            best = np.where(better, leaf, best)
            ident = np.where(better, h, ident)
    inside = np.hypot(c[0], c[1]) < 0.5
    cover = ((best > 0) & inside).astype(float)
    return cover, ident, np.zeros_like(cover)


def needles():
    u, v = grid(SIZE * SUPER)
    s = u - 0.5
    along = v + np.abs(s) * 0.85
    row = along * 34.0
    k = np.floor(row)
    jitter = hash2(k, np.sign(s))
    lane = np.abs(np.modf(row + jitter * 0.4)[0] - 0.5)
    ramp = lambda x, a, b: np.clip((x - a) / (b - a), 0, 1)
    reach = 0.44 * ramp(v, 0.0, 0.18) * (1 - ramp(v, 0.62, 1.0)) * (0.75 + 0.25 * jitter)
    needle = (lane < 0.19) & (np.abs(s) < reach) & (v > 0.02)
    twig = (np.abs(s) < 0.02) & (v < 0.92)
    cover = (needle | twig).astype(float)
    return cover, jitter, twig.astype(float)


def shrink(a):
    n = SIZE
    return a.reshape(n, SUPER, n, SUPER).mean(axis=(1, 3))


def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(data)
    print("wrote", path)


for name, make in (("leaves", leaflets), ("needles", needles)):
    cover, ident, twig = make()
    # Coverage is averaged for soft edges; the leaf number is taken from the
    # middle sample so it stays one value per leaf.
    mid = SUPER // 2
    rgb = np.stack([shrink(cover), ident[mid::SUPER, mid::SUPER], shrink(twig)], axis=-1)
    write_png(OUT / f"foliage_{name}.png", (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8))
