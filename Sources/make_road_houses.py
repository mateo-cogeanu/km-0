"""The house at the end of the road and the stranger's cabin, board by board.
Exported to assets/desert/: road_house.glb (the outside: lapped siding,
casings and louvered shutters round the windows, the porch, a shingled roof
with fascia, gutters and downpipes, a brick chimney, a fieldstone
foundation), road_house_inside.glb (wainscot, chair rail, joists, stair
nosings) and cabin.glb.

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_road_houses.py

Coordinates are Godot's and match scripts/road_end_house.gd and
scripts/stranger_house.gd. Those scripts keep their own walls, floors,
colliders, the glass the ending lights up, the doors and everything the
story uses; these models dress the outsides and insides around them.
"""

import sys
from math import atan, cos, pi, radians, sin, tan
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from desert_kit import V, Kit, build_all, clapboards, plank_wall, drum

# --- The house at the end of the road -------------------------------------------

HX = 3.65          # outside face of the side walls
HZ_FRONT = 3.78    # outside face of the front wall
HZ_BACK = -3.775   # outside face of the back wall
WALL_TOP = 5.24
PITCH = 0.23
ROOF_TOP_AT_RIDGE = 6.06 + 0.06   # a little above the code roof's top face
EAVE_X = 3.95
EAVE_Z = 4.0
WINDOW_W, WINDOW_H = 1.02, 0.91
FRONT_WINDOWS = [(x, y) for x in (-2.04, 2.04) for y in (1.28, 3.56)]
SIDE_WINDOWS = [(z, y) for z in (-1.65, 1.65) for y in (1.28, 3.56)]
BACK_WINDOWS = [(x, y) for x in (-2.046, 2.046) for y in (1.28, 3.56)]


def roof_y(x):
    return ROOF_TOP_AT_RIDGE - abs(x) * tan(PITCH)


def casing(k, center, normal, w=WINDOW_W, h=WINDOW_H, shutters=False, askew=False, sill=True):
    """Trim round a window whose glass the game draws, proud of the siding."""
    n = V(*normal)
    across = V(0, 1, 0).cross(n).normalized()
    c = V(*center)

    def at(u, v, y):
        return c + across * u + n * v + V(0, y, 0)

    def size(su, sv, sy):
        return (abs(across.x) * su + abs(n.x) * sv, sy, abs(across.z) * su + abs(n.z) * sv)

    t = 0.1
    for su, sy, u, y in ((w + 2 * t, t, 0, h / 2 + t / 2), (t, h, -w / 2 - t / 2, 0), (t, h, w / 2 + t / 2, 0)):
        k.box("Trim", at(u, 0.06, y), size(su, 0.07, sy))
    # The sash: stiles and rails round the glass, a meeting rail, a muntin.
    for su, sy, u, y in ((w, 0.05, 0, h / 2 - 0.025), (w, 0.07, 0, -h / 2 + 0.035), (0.05, h, -w / 2 + 0.025, 0), (0.05, h, w / 2 - 0.025, 0)):
        k.box("Trim", at(u, 0.12, y), size(su, 0.03, sy))
    k.box("Trim", at(0, 0.13, 0.02), size(w, 0.035, 0.04))
    k.box("Trim", at(0, 0.13, 0), size(0.03, 0.03, h))
    # Head with a drip cap, and the sill.
    k.box("Trim", at(0, 0.08, h / 2 + t + 0.03), size(w + 2 * t + 0.08, 0.1, 0.05))
    k.box("Trim", at(0, 0.1, h / 2 + t + 0.07), size(w + 2 * t + 0.12, 0.13, 0.025))
    if sill:
        k.box("Trim", at(0, 0.1, -h / 2 - 0.05), size(w + 0.3, 0.16, 0.05))
        k.box("Trim", at(0, 0.06, -h / 2 - 0.1), size(w + 0.1, 0.07, 0.06))
    if shutters:
        for side in (-1, 1):
            hang = askew and side > 0
            u = side * (w / 2 + t + 0.17)
            tilt = radians(-8 if hang else 0)
            base = at(u + (0.04 if hang else 0), 0.06, -0.06 if hang else 0)
            rot = (0, 0, tilt) if abs(n.z) > 0.5 else (tilt, 0, 0)
            leaf_h = h + 0.18
            for su, sy, du, dy in ((0.32, 0.05, 0, leaf_h / 2 - 0.025), (0.32, 0.05, 0, -leaf_h / 2 + 0.025), (0.05, leaf_h, -0.135, 0), (0.05, leaf_h, 0.135, 0)):
                k.box("Boards", base + across * du + V(0, dy, 0), size(su, 0.035, sy), rot)
            for s in range(11):
                if hang and s in (3, 7):
                    continue
                y = -leaf_h / 2 + 0.08 + s * (leaf_h - 0.16) / 10
                k.box("Boards", base + V(0, y, 0) + n * 0.005, size(0.23, 0.012, 0.055), (radians(30), 0, 0) if abs(n.z) > 0.5 else (0, 0, radians(-30)))


def road_house():
    k = Kit(500)
    rng = k.rng
    base = 0.34
    # Lapped siding on all four walls, round the windows and the door.
    win = lambda cu, cy: (cu - WINDOW_W / 2 - 0.1, cu + WINDOW_W / 2 + 0.1, cy - WINDOW_H / 2 - 0.1, cy + WINDOW_H / 2 + 0.15)
    clapboards(k, -HX, HX, base, WALL_TOP, HZ_FRONT, 1, "x", skip=[(-0.86, 0.86, 0, 2.62)] + [win(x, y) for x, y in FRONT_WINDOWS])
    clapboards(k, -HX, HX, base, WALL_TOP, HZ_BACK, -1, "x", skip=[win(x, y) for x, y in BACK_WINDOWS])
    for side in (-1, 1):
        clapboards(k, HZ_BACK, HZ_FRONT, base, WALL_TOP, side * HX, side, "z", skip=[win(z, y) for z, y in SIDE_WINDOWS])
    # Gables, boards up into the triangle under the roof, a louvered vent.
    for z, out in ((HZ_FRONT, 1), (HZ_BACK, -1)):
        y = WALL_TOP
        while True:
            half = (roof_y(0) - 0.2 - (y + 0.2)) / tan(PITCH)
            if half < 0.15:
                break
            k.box("Boards", V(0, y + 0.1, z + out * 0.016), (2 * half, 0.218, 0.022), (radians(4 * out), 0, 0))
            y += 0.2
        k.box("Trim", V(0, 5.5, z + out * 0.05), (0.66, 0.4, 0.05))
        k.box("Dark interior", V(0, 5.5, z + out * 0.08), (0.5, 0.26, 0.01))
        for s in range(5):
            k.box("Trim", V(0, 5.4 + s * 0.05, z + out * 0.09), (0.5, 0.012, 0.04), (radians(-35 * out), 0, 0))
        # A frieze board where the wall meets the gable.
        k.box("Trim", V(0, WALL_TOP + 0.02, z + out * 0.04), (2 * HX + 0.1, 0.16, 0.04))
    for side in (-1, 1):
        k.box("Trim", V(side * (HX + 0.04), WALL_TOP - 0.08, 0), (0.04, 0.2, 2 * HZ_FRONT + 0.1))
    # Corner boards.
    for x in (-1, 1):
        for z in (HZ_FRONT, HZ_BACK):
            zs = 1 if z > 0 else -1
            k.box("Trim", V(x * (HX + 0.035), (base + WALL_TOP) / 2, z + zs * 0.035 - zs * 0.07), (0.07, WALL_TOP - base, 0.17))
            k.box("Trim", V(x * (HX + 0.035) - x * 0.05, (base + WALL_TOP) / 2, z + zs * 0.035), (0.17, WALL_TOP - base, 0.07))
    # Fieldstone foundation: courses of irregular stones, mortar behind.
    for z0, z1, plane, axis, out in ((-HX - 0.06, HX + 0.06, HZ_FRONT, "x", 1), (-HX - 0.06, HX + 0.06, HZ_BACK, "x", -1),
                                    (HZ_BACK - 0.06, HZ_FRONT + 0.06, -HX, "z", -1), (HZ_BACK - 0.06, HZ_FRONT + 0.06, HX, "z", 1)):
        if axis == "x":
            k.box("Concrete", V(0, 0.12, plane + out * 0.04), (z1 - z0, 0.44, 0.06))
        else:
            k.box("Concrete", V(plane + out * 0.04, 0.12, 0), (0.06, 0.44, z1 - z0))
        for row, (y0, h) in enumerate(((-0.08, 0.2), (0.14, 0.18))):
            u = z0 + (0.15 if row else 0.0)
            while u < z1 - 0.1:
                w = rng.uniform(0.25, 0.5)
                b = min(u + w, z1)
                if axis == "x" and abs(plane - HZ_FRONT) < 0.01 and -0.86 < (u + b) / 2 < 0.86:
                    u = b + 0.025
                    continue
                c = (u + b) / 2
                hh = h * rng.uniform(0.85, 1.0)
                d = rng.uniform(0.04, 0.07)
                if axis == "x":
                    k.box("Stone", V(c, y0 + hh / 2, plane + out * (0.06 + d / 2)), (b - u - 0.025, hh, d), (0, rng.uniform(-0.05, 0.05), rng.uniform(-0.04, 0.04)))
                else:
                    k.box("Stone", V(plane + out * (0.06 + d / 2), y0 + hh / 2, c), (d, hh, b - u - 0.025), (rng.uniform(-0.04, 0.04), rng.uniform(-0.05, 0.05), 0))
                u = b + 0.025
        # Water table board along the top of the stone.
        if axis == "x":
            k.box("Trim", V(0, base + 0.03, plane + out * 0.05), (z1 - z0, 0.08, 0.06))
        else:
            k.box("Trim", V(plane + out * 0.05, base + 0.03, 0), (0.06, 0.08, z1 - z0))
    # Windows.
    for i, (x, y) in enumerate(FRONT_WINDOWS):
        casing(k, (x, y, HZ_FRONT + 0.01), (0, 0, 1), shutters=True, askew=(i == 3))
    for x, y in BACK_WINDOWS:
        casing(k, (x, y, HZ_BACK - 0.01), (0, 0, -1))
    for side in (-1, 1):
        for z, y in SIDE_WINDOWS:
            casing(k, (side * (HX + 0.01), y, z), (side, 0, 0))
    # The front door's casing, with a head, and a sill plate at the threshold.
    for x in (-0.86, 0.86):
        k.box("Trim", V(x, 1.31, HZ_FRONT + 0.04), (0.14, 2.62, 0.08))
        k.box("Trim", V(x * 0.97, 0.1, HZ_FRONT + 0.06), (0.17, 0.2, 0.1))
    k.box("Trim", V(0, 2.68, HZ_FRONT + 0.05), (1.98, 0.14, 0.1))
    k.box("Trim", V(0, 2.77, HZ_FRONT + 0.07), (2.06, 0.04, 0.14))
    k.box("Wood", V(0, 0.01, HZ_FRONT - 0.02), (1.6, 0.02, 0.3))
    # The roof: courses of shingles down both slopes, each strip a little
    # askew, a few missing; ridge cap; fascia, rakes, soffit, gutters.
    run = EAVE_X / cos(PITCH)
    courses = int(run / 0.19)
    for side in (-1, 1):
        for r in range(courses):
            t = (r + 0.5) / courses
            x = side * EAVE_X * (1 - t)
            y = roof_y(x) + 0.02
            zz = -EAVE_Z - (0.7 if r % 2 else 0.0)
            while zz < EAVE_Z:
                a, b = max(zz, -EAVE_Z), min(zz + 1.4, EAVE_Z)
                if b - a > 0.2 and rng.random() > 0.035:
                    k.box("Shingles", V(x, y, (a + b) / 2), (0.22, 0.025, b - a - 0.012), (0, 0, -side * (PITCH + radians(3)) + rng.uniform(-0.01, 0.01)))
                zz += 1.4
        # Sheathing under the shingles, so no gaps show sky.
        k.box("Wood", V(side * EAVE_X / 2, (roof_y(0) + roof_y(EAVE_X)) / 2 - 0.01, 0), (run + 0.02, 0.03, 2 * EAVE_Z), (0, 0, -side * PITCH))
        k.box("Trim", V(side * (EAVE_X + 0.01), roof_y(EAVE_X) - 0.09, 0), (0.04, 0.2, 2 * EAVE_Z + 0.08))
        k.box("Trim", V(side * (HX + EAVE_X) / 2, roof_y(EAVE_X) - 0.18, 0), (EAVE_X - HX, 0.02, 2 * EAVE_Z))
        k.cyl("Steel", V(side * (EAVE_X + 0.09), roof_y(EAVE_X) - 0.16, -EAVE_Z), V(side * (EAVE_X + 0.09), roof_y(EAVE_X) - 0.18, EAVE_Z), 0.065, 8)
        for z in (EAVE_Z - 0.15, -EAVE_Z + 0.15):
            k.cyl("Steel", V(side * (EAVE_X + 0.09), roof_y(EAVE_X) - 0.2, z), V(side * (HX + 0.12), roof_y(EAVE_X) - 0.55, z - (0.12 if z > 0 else -0.12)), 0.045, 8)
            k.cyl("Steel", V(side * (HX + 0.12), roof_y(EAVE_X) - 0.55, z - (0.12 if z > 0 else -0.12)), V(side * (HX + 0.12), 0.3, z - (0.12 if z > 0 else -0.12)), 0.045, 8)
            for y in (1.2, 2.8, 4.2):
                k.box("Steel", V(side * (HX + 0.07), y, z - (0.12 if z > 0 else -0.12)), (0.06, 0.03, 0.1))
        # Rake boards up the gable ends.
        for z, out in ((EAVE_Z, 1), (-EAVE_Z, -1)):
            k.box("Trim", V(side * EAVE_X / 2, (roof_y(0) + roof_y(EAVE_X)) / 2 - 0.08, z + out * 0.01), (run + 0.05, 0.22, 0.04), (0, 0, -side * PITCH))
    for i in range(int(2 * EAVE_Z / 0.3)):
        k.box("Shingles", V(0, roof_y(0) + 0.05, -EAVE_Z + 0.15 + i * 0.3), (0.34, 0.03, 0.29), (rng.uniform(-0.02, 0.02), 0, 0))
    # Brick chimney through the roof, a concrete cap, two clay pots.
    cx, cz = 2.3, -1.9
    y = roof_y(cx + 0.31) - 0.2
    while y < 7.0:
        offset = 0.1 if int(y / 0.075) % 2 else 0.0
        for sx, sz, w, d in ((cx, cz - 0.31, 0.62, 0.04), (cx, cz + 0.31, 0.62, 0.04), (cx - 0.31, cz, 0.04, 0.62), (cx + 0.31, cz, 0.04, 0.62)):
            k.box("Brick", V(sx, y + 0.034, sz), (w, 0.066, d))
        y += 0.075
    k.box("Brick", V(cx, (roof_y(cx) + 7.0) / 2 - 0.1, cz), (0.6, 7.0 - roof_y(cx) + 0.2, 0.6))
    k.box("Concrete", V(cx, 7.04, cz), (0.78, 0.08, 0.78))
    for dx in (-0.12, 0.12):
        k.cyl("Brick", V(cx + dx, 7.08, cz), V(cx + dx, 7.3, cz), 0.08, 8, 0.065)
    k.box("Steel", V(cx, roof_y(cx + 0.35) + 0.05, cz), (0.8, 0.02, 0.8), (0, 0, -PITCH))
    # The porch: deck boards, a rim joist, turned posts, rails and balusters,
    # its own roof on a beam, and a single step down.
    for n in range(int(3.15 / 0.12)):
        x = -1.575 + 0.06 + n * 0.12
        k.box("Wood", V(x, -0.012, 4.35), (0.112, 0.025, 1.54), (0, 0, rng.uniform(-0.01, 0.01)))
    k.box("Wood", V(0, -0.07, 5.13), (3.17, 0.14, 0.04))
    for x in (-1.59, 1.59):
        k.box("Wood", V(x, -0.07, 4.35), (0.04, 0.14, 1.56))
    k.box("Wood", V(0, -0.1, 5.32), (1.4, 0.04, 0.32))
    for x in (-1.47, 1.47):
        k.box("Trim", V(x, 0.1, 4.99), (0.2, 0.2, 0.2))
        k.box("Trim", V(x, 1.3, 4.99), (0.11, 2.2, 0.11))
        for y in (0.3, 1.05, 2.25):
            k.cyl("Trim", V(x, y - 0.06, 4.99), V(x, y + 0.06, 4.99), 0.085, 10)
        k.box("Trim", V(x, 2.38, 4.99), (0.18, 0.08, 0.18))
        # Side railings, back to the house.
        k.box("Trim", V(x, 0.9, 4.39), (0.09, 0.05, 1.16))
        k.box("Trim", V(x, 0.16, 4.39), (0.07, 0.05, 1.16))
        for i in range(7):
            if x > 0 and i == 4:
                continue
            k.box("Trim", V(x, 0.53, 3.93 + i * 0.15), (0.035, 0.7, 0.035))
    k.box("Trim", V(0, 2.42, 4.99), (3.2, 0.14, 0.12))
    porch_slope = radians(10)
    for r in range(8):
        z = 3.75 + r * 0.19
        k.box("Shingles", V(0, 2.62 - (z - 3.65) * tan(porch_slope), z), (3.3, 0.025, 0.22), (porch_slope + radians(2), 0, 0))
    k.box("Wood", V(0, 2.58 - 0.8 * tan(porch_slope), 4.43), (3.22, 0.03, 1.6), (porch_slope, 0, 0))
    k.box("Trim", V(0, 2.4, 5.22), (3.3, 0.16, 0.04))
    k.box("Trim", V(0, 2.62, HZ_FRONT + 0.03), (3.3, 0.06, 0.04))
    # A doormat, and the house number gone from beside the door.
    k.box("Fabric", V(0, 0.003, 4.0), (0.9, 0.006, 0.55))
    k.box("Trim", V(-1.1, 2.0, HZ_FRONT + 0.03), (0.2, 0.28, 0.02))
    # Out in the yard: a woodpile against the left wall under a sheet of tin,
    # and a rain barrel under the back downpipe.
    for row in range(4):
        for n in range(9 - row):
            z = -1.0 + n * 0.22 + row * 0.11
            k.cyl("Bark", V(-HX - 0.35, 0.09 + row * 0.16, z), V(-HX - 0.7, 0.09 + row * 0.16 + rng.uniform(-0.02, 0.02), z), 0.08, 7)
    k.box("Steel", V(-HX - 0.5, 0.78, -0.1), (0.7, 0.015, 2.3), (0, 0, radians(-12)))
    drum(k, V(HX + 0.3, 0, -EAVE_Z + 0.4), mat="Rust", radius=0.32, height=0.9, lid=False)
    return k.finish("RoadHouse")


def road_house_inside():
    k = Kit(501)
    # Wainscot boards to a chair rail round the ground floor, and a picture rail.
    def wainscot(a0, a1, plane, out, axis):
        n = int((a1 - a0) / 0.1)
        for i in range(n):
            u = a0 + (i + 0.5) * (a1 - a0) / n
            if axis == "x":
                k.box("Boards", V(u, 0.5, plane + out * 0.006), ((a1 - a0) / n - 0.006, 0.88, 0.012))
            else:
                k.box("Boards", V(plane + out * 0.006, 0.5, u), (0.012, 0.88, (a1 - a0) / n - 0.006))
        if axis == "x":
            k.box("Trim", V((a0 + a1) / 2, 0.96, plane + out * 0.018), (a1 - a0, 0.06, 0.036))
            k.box("Trim", V((a0 + a1) / 2, 2.32, plane + out * 0.01), (a1 - a0, 0.04, 0.02))
        else:
            k.box("Trim", V(plane + out * 0.018, 0.96, (a0 + a1) / 2), (0.036, 0.06, a1 - a0))
            k.box("Trim", V(plane + out * 0.01, 2.32, (a0 + a1) / 2), (0.02, 0.04, a1 - a0))
    wainscot(-3.4, 3.4, -3.545, 1, "x")
    wainscot(-3.4, -0.8, 3.52, -1, "x")
    wainscot(0.8, 3.4, 3.52, -1, "x")
    wainscot(-3.53, 3.5, -3.41, 1, "z")
    wainscot(-0.02, 3.5, 3.41, -1, "z")
    # Door casing inside.
    for x in (-0.86, 0.86):
        k.box("Trim", V(x, 1.31, 3.5), (0.12, 2.62, 0.04))
    k.box("Trim", V(0, 2.66, 3.5), (1.84, 0.12, 0.04))
    # Joists under the upper floor, and its edge board.
    for i in range(12):
        z = -3.3 + i * 0.6
        k.box("Wood", V(-1.42, 2.47, z), (4.1, 0.12, 0.07))
    k.box("Trim", V(0.66, 2.55, 0), (0.04, 0.24, 7.27))
    # Nosings on the stairs and a handrail on the stair wall.
    for i in range(13):
        h = 0.207 * (i + 1)
        k.box("Floor", V(1.8, h + 0.012, -0.10 - i * 0.27 + 0.13), (1.41, 0.024, 0.06))
    for i in range(12):
        a = V(1.07, 0.207 * (i + 1) + 0.9, -0.1 - i * 0.27)
        b = V(1.07, 0.207 * (i + 2) + 0.9, -0.1 - (i + 1) * 0.27)
        k.span("Wood", a, b, 0.05)
    for i in (0, 6, 11):
        k.box("Steel", V(1.05, 0.207 * (i + 1) + 0.86, -0.1 - i * 0.27), (0.06, 0.03, 0.03))
    # A kitchen counter beside the fridge, with a sink, under the back window.
    k.box("Wood", V(-1.75, 0.44, -3.25), (1.5, 0.88, 0.58))
    k.box("Enamel", V(-1.75, 0.9, -3.24), (1.56, 0.04, 0.62))
    k.box("Steel", V(-2.05, 0.885, -3.22), (0.5, 0.03, 0.38))
    k.cyl("Steel", V(-2.05, 0.92, -3.48), V(-2.05, 1.12, -3.44), 0.012, 6)
    for x in (-2.3, -1.75, -1.2):
        k.box("Wood", V(x, 0.45, -2.955), (0.5, 0.72, 0.012))
        k.box("Steel", V(x + 0.15, 0.7, -2.945), (0.02, 0.1, 0.02))
    return k.finish("RoadHouseInside")


# --- The stranger's cabin -----------------------------------------------------------

CABIN_X = 2.62
CABIN_Z = 2.12
CABIN_TOP = 2.6
CABIN_PITCH = 0.42


def cabin():
    k = Kit(600)
    rng = k.rng
    # Board and batten outside, rough horizontal boards inside, a frame between.
    plank_wall(k, -CABIN_X, CABIN_X, 0, CABIN_TOP, CABIN_Z, 1, skip=[(-0.66, 0.66, 0, 2.42), (1.3, 1.9, 1.25, 1.75)])
    plank_wall(k, -CABIN_X, CABIN_X, 0, CABIN_TOP, -CABIN_Z, -1)
    for side in (-1, 1):
        plank_wall(k, -CABIN_Z, CABIN_Z, 0, CABIN_TOP, side * CABIN_X, side, axis="z",
            skip=[(-0.85, 0.05, 1.1, 1.8)] if side < 0 else [])
    for y in range(int(CABIN_TOP / 0.22)):
        yc = 0.11 + y * 0.22
        k.box("Wood", V(0, yc, -1.98 + 0.012), (4.96, 0.2, 0.02))
        for side in (-1, 1):
            if side < 0 and 1.1 < yc < 1.8:
                for a, b in ((-1.98, -0.85), (0.05, 1.98)):
                    k.box("Wood", V(side * (2.48 - 0.012), yc, (a + b) / 2), (0.02, 0.2, b - a))
                continue
            k.box("Wood", V(side * (2.48 - 0.012), yc, 0), (0.02, 0.2, 3.96))
        if yc > 2.42 or True:
            for a, b in ((-2.48, -0.66), (0.66, 2.48)):
                if 1.25 < yc < 1.75 and a > 0:
                    for aa, bb in ((0.66, 1.3), (1.9, 2.48)):
                        k.box("Wood", V((aa + bb) / 2, yc, 1.98 - 0.012), (bb - aa, 0.2, 0.02))
                    continue
                if yc < 2.42:
                    k.box("Wood", V((a + b) / 2, yc, 1.98 - 0.012), (b - a, 0.2, 0.02))
            if yc >= 2.42:
                k.box("Wood", V(0, yc, 1.98 - 0.012), (4.96, 0.2, 0.02))
    for x in (-2.4, 2.4):
        for z in (-1.9, 1.9):
            k.box("Wood", V(x, 1.3, z), (0.1, 2.6, 0.1))
    # Door frame, the windows: one boarded over the warm glass, one small.
    for x in (-0.68, 0.68):
        k.box("Wood", V(x, 1.21, 2.15), (0.08, 2.42, 0.08))
    k.box("Wood", V(0, 2.46, 2.15), (1.44, 0.1, 0.1))
    k.box("Wood", V(0, 0.01, 2.22), (1.4, 0.03, 0.25))
    for su, sy, du, dy in ((0.72, 0.06, 0, 0.28), (0.72, 0.08, 0, -0.29), (0.06, 0.5, -0.33, 0), (0.06, 0.5, 0.33, 0)):
        k.box("Wood", V(1.6 + du, 1.5 + dy, 2.165), (su, sy, 0.04))
    k.box("Wood", V(1.6, 1.5, 2.17), (0.03, 0.5, 0.02))
    for su, sy, du, dy in ((1.02, 0.07, 0, 0.385), (1.02, 0.09, 0, -0.39), (0.07, 0.7, -0.48, 0), (0.07, 0.7, 0.48, 0)):
        k.box("Wood", V(-2.66, 1.45 + dy, -0.4 + du), (0.04, sy, su))
    for tilt, dy in ((0.5, 0.05), (-0.4, -0.08), (0.08, 0.25)):
        k.box("Wood", V(-2.68, 1.45 + dy, -0.4), (0.03, 0.13, 1.15), (tilt, 0, 0))
        for side in (-1, 1):
            k.box("Steel", V(-2.7, 1.45 + dy + side * sin(tilt) * 0.5, -0.4 + side * cos(tilt) * 0.5), (0.012, 0.015, 0.015))
    # Gables in boards, both faces.
    rise = CABIN_X * tan(CABIN_PITCH)
    for z, out in ((CABIN_Z, 1), (-CABIN_Z, -1)):
        n = int(2 * CABIN_X / 0.18)
        for i in range(n):
            x = -CABIN_X + (i + 0.5) * 2 * CABIN_X / n
            h = (CABIN_X - abs(x)) * tan(CABIN_PITCH)
            if h > 0.03:
                for zz, oo in ((z, out), (z - out * 0.16, -out)):
                    k.box("Wood", V(x, CABIN_TOP + h / 2, zz + oo * 0.012), (2 * CABIN_X / n - 0.01, h, 0.024))
    # Rafters and a ridge beam, a tin roof gone to rust, a stovepipe.
    eave = 0.35
    over = 0.3
    for side in (-1, 1):
        for i in range(6):
            z = -CABIN_Z - 0.1 + i * (2 * CABIN_Z + 0.2) / 5
            a = V(side * (CABIN_X + eave), CABIN_TOP - eave * tan(CABIN_PITCH), z)
            b = V(0, CABIN_TOP + rise, z)
            k.span("Wood", a, b, 0.06, 0.12)
        top = V(0, CABIN_TOP + rise + 0.08, -CABIN_Z - over)
        down = V(side * (CABIN_X + eave), -(CABIN_X + eave) * tan(CABIN_PITCH), 0)
        k.corrugated("Roof", top, V(0, 0, 1), down, 2 * (CABIN_Z + over), down.length, 0.076, 0.02,
            out=V(side * sin(CABIN_PITCH), cos(CABIN_PITCH), 0))
        for i in range(4):
            t = (i + 0.5) / 4
            k.box("Wood", top + down * t + V(0, -0.06, CABIN_Z + over), (0.05, 0.06, 2 * (CABIN_Z + over)), (0, 0, -side * CABIN_PITCH))
    k.box("Wood", V(0, CABIN_TOP + rise - 0.04, 0), (0.08, 0.14, 2 * CABIN_Z + 0.3))
    k.box("Steel", V(0, CABIN_TOP + rise + 0.1, 0), (0.25, 0.03, 2 * (CABIN_Z + over)))
    k.cyl("Steel", V(0.75, CABIN_TOP + rise - 0.75 * tan(CABIN_PITCH) - 0.1, -1.66), V(0.75, CABIN_TOP + rise + 0.6, -1.66), 0.08, 10)
    k.cyl("Steel", V(0.75, CABIN_TOP + rise + 0.6, -1.66), V(0.75, CABIN_TOP + rise + 0.75, -1.66), 0.16, 10, 0.03)
    # Inside: the stove the pipe comes from, shelves of tins, a rag rug.
    k.box("Steel", V(0.75, 0.35, -1.66), (0.55, 0.6, 0.45))
    for x in (0.55, 0.95):
        k.box("Steel", V(x, 0.03, -1.66), (0.05, 0.06, 0.45))
    k.cyl("Steel", V(0.75, 0.65, -1.66), V(0.75, CABIN_TOP + rise - 0.75 * tan(CABIN_PITCH) - 0.1, -1.66), 0.07, 10)
    k.box("Dark interior", V(0.75, 0.35, -1.43), (0.3, 0.2, 0.01))
    for y in (1.45, 1.9):
        k.box("Wood", V(-0.2, y, -1.86), (1.3, 0.03, 0.22))
        for x in (-0.8, 0.4):
            k.box("Wood", V(x, y - 0.08, -1.92), (0.03, 0.14, 0.1))
        for i in range(rng.randint(3, 6)):
            x = -0.75 + i * 0.22 + rng.uniform(-0.03, 0.03)
            k.cyl("Tin", V(x, y + 0.015, -1.86), V(x, y + 0.13, -1.86), 0.042, 10)
    k.box("Fabric", V(0.1, 0.004, 0.6), (1.4, 0.008, 0.9))
    # Outside: firewood stacked under the eave, a chopping block, a barrel.
    for row in range(4):
        for n in range(10 - row):
            z = -1.5 + n * 0.2 + row * 0.1
            k.cyl("Bark", V(CABIN_X + 0.15, 0.09 + row * 0.16, z), V(CABIN_X + 0.55, 0.09 + row * 0.16, z), 0.08, 7)
    k.cyl("Bark", V(CABIN_X + 1.2, 0, 1.4), V(CABIN_X + 1.2, 0.45, 1.4), 0.25, 9)
    k.span("Wood", V(CABIN_X + 1.2, 0.45, 1.4), V(CABIN_X + 1.6, 0.85, 1.55), 0.035)
    k.box("Steel", V(CABIN_X + 1.2, 0.47, 1.4), (0.12, 0.08, 0.02), (0, 0.4, 0.8))
    drum(k, V(-CABIN_X - 0.5, 0, 1.4), mat="Rust", radius=0.3, height=0.85, lid=False)
    return k.finish("Cabin")


build_all([
    ("road_house", road_house),
    ("road_house_inside", road_house_inside),
    ("cabin", cabin),
])
