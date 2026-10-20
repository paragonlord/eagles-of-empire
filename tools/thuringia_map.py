#!/usr/bin/env python3
"""Draw the Thuringian campaign's parchment map: build/art/out/thuringia.png (1024 x 890).

Stdlib only. The map frame matches src/client/UI/CampaignScreen.luau: a region at map (x, z),
0..1000, sits at (0.08 + 0.84 x / 1000, 0.08 + 0.84 z / 1000) of the frame, aspect 1.15.
Rivers, hills and woods follow the real lie of the land round Jena (north up).
Upload the PNG in Studio (upload_image) and put the id in Assets.paintings.thuringia.
"""
import math
import pathlib
import random
import struct
import zlib

W, H = 1024, 890
OUT = pathlib.Path(__file__).resolve().parent.parent / "build" / "art" / "out" / "thuringia.png"

PARCH = (228, 214, 178)
INK = (74, 58, 40)
WATER = (104, 136, 168)
HILL = (150, 120, 84)
WOOD = (88, 98, 62)

# map units (x east, z south, 0..1000)
RIVERS = [
    ("Saale", 4, [(130, 1110), (300, 820), (400, 720), (470, 630), (500, 520), (510, 420), (560, 300), (640, 180), (700, 90), (790, -110)]),
    ("Ilm", 2, [(40, 820), (110, 730), (220, 560), (320, 380), (350, 250), (470, 175), (640, 165)]),
    ("Weisse Elster", 3, [(920, 1110), (870, 700), (850, 450), (800, 250), (850, -110)]),
    ("Orla", 1, [(760, 760), (640, 690), (480, 640)]),
]
HILLS = [((140, 900), 170), ((60, 780), 110), ((470, 390), 55), ((640, 720), 90), ((300, 560), 70), ((900, 860), 90)]
WOODS = [((200, 860), 90), ((90, 640), 60), ((420, 470), 45), ((620, 560), 60), ((280, 120), 70), ((760, 640), 50), ((940, 300), 60)]


def px(x, z):
    return (0.08 + 0.84 * x / 1000) * W, (0.08 + 0.84 * z / 1000) * H


img = bytearray(W * H * 3)


def get(x, y):
    i = (y * W + x) * 3
    return img[i], img[i + 1], img[i + 2]


def blend(x, y, c, a):
    if 0 <= x < W and 0 <= y < H and a > 0:
        i = (y * W + x) * 3
        for k in range(3):
            img[i + k] = int(img[i + k] * (1 - a) + c[k] * a)


# parchment: value noise in two octaves, darker toward the edges
rng = random.Random(1806)
G = 9
grid = [[rng.random() for _ in range(G + 1)] for _ in range(G + 1)]
fine = [[rng.random() for _ in range(33)] for _ in range(33)]


def vnoise(g, n, u, v):
    fx, fy = u * n, v * n
    ix, iy = int(fx), int(fy)
    tx, ty = fx - ix, fy - iy
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a = g[iy][ix] * (1 - tx) + g[iy][ix + 1] * tx
    b = g[iy + 1][ix] * (1 - tx) + g[iy + 1][ix + 1] * tx
    return a * (1 - ty) + b * ty


for y in range(H):
    for x in range(W):
        u, v = x / W, y / H
        n = 0.65 * vnoise(grid, G, u, v) + 0.35 * vnoise(fine, 32, u * 0.999, v * 0.999)
        edge = min(u, 1 - u, v, 1 - v)
        vign = max(0.0, 0.16 - edge) / 0.16
        k = 0.9 + 0.14 * n - 0.22 * vign * vign
        i = (y * W + x) * 3
        img[i], img[i + 1], img[i + 2] = (min(255, int(c * k)) for c in PARCH)

# hills: soft brown relief with hachures (short strokes falling away from the crest)
for (cx, cz), r in HILLS:
    ox, oy = px(cx, cz)
    rr = r * 0.84 * W / 1000
    for y in range(int(oy - rr), int(oy + rr) + 1):
        for x in range(int(ox - rr), int(ox + rr) + 1):
            d = math.hypot(x - ox, (y - oy) * 1.2) / rr
            if d < 1:
                blend(x, y, HILL, 0.22 * (1 - d) ** 1.5)
    for _ in range(int(rr * 1.2)):
        a = rng.uniform(0, 2 * math.pi)
        d0 = rng.uniform(0.3, 0.8) * rr
        for t in range(6):
            x = int(ox + math.cos(a) * (d0 + t))
            y = int(oy + math.sin(a) * (d0 + t) / 1.2)
            blend(x, y, INK, 0.22)

# woods: clusters of little tree marks
for (cx, cz), r in WOODS:
    ox, oy = px(cx, cz)
    rr = r * 0.84 * W / 1000
    for _ in range(int(rr * 1.6)):
        a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0, 1) ** 0.5 * rr
        tx, ty = ox + math.cos(a) * d, oy + math.sin(a) * d * 0.8
        for yy in range(-4, 5):
            for xx in range(-4, 5):
                q = math.hypot(xx, yy)
                if q <= 4:
                    blend(int(tx + xx), int(ty + yy), WOOD, 0.55 if q > 3 else 0.25)
        for yy in range(4, 7):
            blend(int(tx), int(ty + yy), INK, 0.5)

# rivers: stamped discs along each course, a darker bank line under the water
def meander(ps):
    """Subdivide each leg and swing it from side to side, as a river runs."""
    out = [ps[0]]
    for (ax, ay), (bx, by) in zip(ps, ps[1:]):
        L = math.hypot(bx - ax, by - ay)
        nx, ny = -(by - ay) / L, (bx - ax) / L
        n = max(2, int(L / 14))
        amp = rng.uniform(3, 7)
        for k in range(1, n + 1):
            t = k / n
            w = math.sin(t * math.pi * rng.choice((1, 2))) * amp * (1 if k < n else 0)
            out.append((ax + (bx - ax) * t + nx * w, ay + (by - ay) * t + ny * w))
    return out


for _, width, pts in RIVERS:
    ps = meander([px(x, z) for x, z in pts])
    for (ax, ay), (bx, by) in zip(ps, ps[1:]):
        steps = int(math.hypot(bx - ax, by - ay))
        for s in range(steps + 1):
            t = s / max(1, steps)
            cx, cy = ax + (bx - ax) * t, ay + (by - ay) * t
            for yy in range(-width - 1, width + 2):
                for xx in range(-width - 1, width + 2):
                    q = math.hypot(xx, yy)
                    if q <= width + 1:
                        blend(int(cx + xx), int(cy + yy), INK if q > width else WATER, 0.18 if q > width else 0.7)

# a double ink frame
for y in range(H):
    for x in range(W):
        e = min(x, y, W - 1 - x, H - 1 - y)
        if e in (6, 7, 12):
            blend(x, y, INK, 0.8)


def png(path):
    raw = b"".join(b"\x00" + bytes(img[y * W * 3:(y + 1) * W * 3]) for y in range(H))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


png(OUT)
print(f"wrote {OUT}")
