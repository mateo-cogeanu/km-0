"""The roadside stations along the desert road, and the workshop you start in,
built piece by piece: corrugated sheet walls over steel frames, block and
brick, framed windows (some boarded), parapets, gutters and downpipes, roof
sheets on purlins, sign bands, and the clutter left outside. Also the bench
and shelving inside them. Exported to assets/desert/ as station_<n>.glb (and
station_<n>_far.glb, the simple shell for seeing from the road),
workshop.glb, workshop_small.glb, workbench.glb and shelving.glb.

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_road_stations.py

Coordinates are Godot's and match scripts/abandoned_building.gd and
scripts/garage_model.gd: front at z = 4.14 facing +Z, the shutter opening
from x = -2.94 to 1.62, the side door from 1.88 to 2.94, both 2.34 high.
The game keeps its own box colliders; these models are only what you see.
"""

import sys
from math import atan2, cos, pi, radians, sin, tan
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from desert_kit import (V, Kit, build_all, corrugated_box_walls, corrugated_roof, drum, framed_window, pallet,
    purlins, strip_light, tyre)

FRONT = 4.14
SHUTTER = (-2.94, 1.62)
DOOR = (1.88, 2.94)
OPEN_TOP = 2.34
# Width, depth and wall height of the four abandoned stations (abandoned_building.gd).
STATIONS = [(7.8, 7.2, 2.91), (6.8, 8.7, 3.45), (6.6, 7.4, 3.1), (7.2, 8.0, 3.25)]


def solid_wall(k, mat, axis, plane, thick, a0, a1, y0, y1, openings=()):
    """A wall box split round its openings [(a, b, bottom, top)]. axis "x"
    runs along x at z = plane; axis "z" runs along z at x = plane."""
    cuts = sorted({a0, a1, *[c for o in openings for c in (max(a0, o[0]), min(a1, o[1]))]})
    for a, b in zip(cuts, cuts[1:]):
        if b - a < 0.005:
            continue
        mid = (a + b) / 2
        ranges = [(y0, y1)]
        for oa, ob, oy0, oy1 in openings:
            if oa < mid < ob:
                ranges = [r for rg in ranges for r in ((rg[0], min(rg[1], oy0)), (max(rg[0], oy1), rg[1])) if r[1] - r[0] > 0.005]
        for ya, yb in ranges:
            if axis == "x":
                k.box(mat, V(mid, (ya + yb) / 2, plane), (b - a, yb - ya, thick))
            else:
                k.box(mat, V(plane, (ya + yb) / 2, mid), (thick, yb - ya, b - a))


def door_frame(k, x0, x1, top, z, mat="Steel"):
    for x in (x0, x1):
        k.box(mat, V(x, top / 2, z + 0.11), (0.06, top, 0.05))
    k.box(mat, V((x0 + x1) / 2, top + 0.03, z + 0.11), (x1 - x0 + 0.06, 0.06, 0.05))
    k.box("Concrete", V((x0 + x1) / 2, 0.02, z + 0.3), (x1 - x0 + 0.2, 0.06, 0.4))


def shutter_surround(k, z, mat="Steel"):
    """Box-section jambs either side of the shutter, a sill plate, kick
    plates, and the shutter's guide rail brackets."""
    for x in SHUTTER:
        k.box(mat, V(x, OPEN_TOP / 2, z + 0.12), (0.1, OPEN_TOP, 0.06))
        for y in (0.4, 1.2, 2.0):
            k.box(mat, V(x, y, z + 0.16), (0.14, 0.06, 0.04))
        k.box("Yellow paint", V(x, 0.45, z + 0.155), (0.11, 0.9, 0.012))
    k.box("Steel", V(sum(SHUTTER) / 2, 0.01, z + 0.12), (SHUTTER[1] - SHUTTER[0], 0.02, 0.18))


def downpipe(k, x, z, top, out_x=0.0, out_z=0.12):
    k.cyl("Steel", V(x, top, z), V(x + out_x, top - 0.25, z + out_z), 0.045, 8)
    k.cyl("Steel", V(x + out_x, top - 0.25, z + out_z), V(x + out_x, 0.25, z + out_z), 0.045, 8)
    k.cyl("Steel", V(x + out_x, 0.25, z + out_z), V(x + out_x * 1.4, 0.06, z + out_z * 2.4), 0.045, 8)
    for y in (0.8, 1.7):
        if y < top - 0.3:
            k.box("Steel", V(x + out_x, y, z + out_z - 0.03), (0.1, 0.03, 0.04))


def meter_box(k, at, normal_x=0.0):
    k.box("Steel", V(*at), (0.42 if not normal_x else 0.14, 0.55, 0.14 if not normal_x else 0.42))
    k.cyl("Steel", V(at[0], at[1] + 0.27, at[2]), V(at[0], at[1] + 1.4, at[2]), 0.02, 6)


def tyre_stack(k, at, count, lean=False):
    for i in range(count):
        jitter = V(k.rng.uniform(-0.03, 0.03), 0, k.rng.uniform(-0.03, 0.03))
        tyre(k, V(*at) + jitter + V(0, 0.1 + i * 0.205, 0))
    if lean:
        tyre(k, V(at[0] + 0.55, 0.3, at[2] + 0.05), axis=V(0.3, 0, 1))


def inner_frame(k, w, rear, front, top, bays, mat="Steel"):
    """Steel portal columns down both sides with a tie beam across, and girts."""
    for i in range(bays + 1):
        z = rear + 0.25 + (front - rear - 0.5) * i / bays
        for side in (-1, 1):
            k.box(mat, V(side * (w / 2 - 0.17), (top - 0.05) / 2, z), (0.12, top - 0.05, 0.08))
        k.box(mat, V(0, top - 0.12, z), (w - 0.3, 0.14, 0.08))
    for side in (-1, 1):
        for y in (1.1, 2.2):
            if y < top - 0.3:
                k.box(mat, V(side * (w / 2 - 0.12), y, (rear + front) / 2), (0.04, 0.1, front - rear - 0.3))


def sign_band(k, x, y, z, width, height=0.5, mat="Sign"):
    k.box("Steel", V(x, y, z + 0.03), (width + 0.1, height + 0.1, 0.05))
    k.box(mat, V(x, y, z + 0.06), (width, height, 0.02))
    for dx in (-width / 2 + 0.2, width / 2 - 0.2):
        k.box("Rust", V(x + dx, y - height / 2 + 0.05, z + 0.075), (0.05, 0.2, 0.005))


# --- The four abandoned stations ------------------------------------------------

def station(v, far=False):
    k = Kit(100 + v)
    w, d, top = STATIONS[v]
    rear = FRONT - d
    mid = (FRONT + rear) / 2
    hw = w / 2
    k.box("Concrete", V(0, -0.05, mid), (w + 0.25, 0.12, d + 0.22))
    front_open = [(SHUTTER[0], SHUTTER[1], -1, OPEN_TOP), (DOOR[0], DOOR[1], -1, OPEN_TOP)]
    sheet = v in (1, 2)
    wall_mat = {0: "Block", 1: "Corrugated", 2: "Corrugated", 3: "Brick"}[v]
    # Windows: one each side (some boarded), and one in the back.
    side_windows = [(-1, mid + 0.6, 1.6, 0.9), (1, mid - 0.3, 1.4, 0.9)]
    back_window = (-hw * 0.45, 1.5, 1.2, 0.8)
    if far:
        k.box(wall_mat, V(0, top / 2, rear), (w, top, 0.21))
        for side in (-1, 1):
            k.box(wall_mat, V(side * hw, top / 2, mid), (0.19, top, d))
        solid_wall(k, wall_mat, "x", FRONT, 0.21, -hw, hw, 0, top, front_open)
        for side, z, wl, hl in side_windows:
            k.box("Dark interior", V(side * (hw + 0.1), 1.6, z), (0.02, hl, wl))
    elif sheet:
        # Corrugated sheet outside and a liner inside, on a steel frame.
        corrugated_box_walls(k, -hw - 0.095, hw + 0.095, rear - 0.105, FRONT + 0.105, top,
            skip_front=[(SHUTTER[0], SHUTTER[1], OPEN_TOP), (DOOR[0], DOOR[1], OPEN_TOP)])
        k.corrugated("Corrugated", V(hw - 0.095, 0, rear + 0.105), V(-1, 0, 0), V(0, 1, 0), w - 0.19, top, out=V(0, 0, 1))
        for side in (-1, 1):
            k.corrugated("Corrugated", V(side * (hw - 0.095), 0, rear + 0.105), V(0, 0, 1), V(0, 1, 0), d - 0.21, top, out=V(-side, 0, 0))
        for a, b, top_y in ((-hw, SHUTTER[0], 0), (SHUTTER[1], DOOR[0], 0), (DOOR[1], hw, 0)):
            k.corrugated("Corrugated", V(a, 0, FRONT - 0.105), V(1, 0, 0), V(0, 1, 0), b - a, top, out=V(0, 0, -1))
        for a, b in (SHUTTER, DOOR):
            k.corrugated("Corrugated", V(a, OPEN_TOP, FRONT - 0.105), V(1, 0, 0), V(0, 1, 0), b - a, top - OPEN_TOP, out=V(0, 0, -1))
        inner_frame(k, w, rear, FRONT, top, 3)
        # Flashing at the corners and along the bottom.
        for sx in (-1, 1):
            for z in (rear - 0.105, FRONT + 0.105):
                k.box("Steel", V(sx * (hw + 0.1), top / 2, z), (0.07, top, 0.07))
        k.box("Steel", V(0, 0.06, FRONT + 0.12), (w + 0.2, 0.12, 0.03))
        for side, z, wl, hl in side_windows:
            framed_window(k, V(side * (hw + 0.115), 1.65, z), wl, hl, V(side, 0, 0), boarded=4 if side > 0 else 0, broken=0.6, frame_mat="Steel", depth=0.2, backing=False)
    else:
        win_side = [(z - wl / 2, z + wl / 2, 1.65 - hl / 2, 1.65 + hl / 2) for side, z, wl, hl in side_windows]
        for i, side in enumerate((-1, 1)):
            solid_wall(k, wall_mat, "z", side * hw, 0.19, rear - 0.095, FRONT + 0.095, 0, top, [win_side[i]])
            framed_window(k, V(side * (hw + 0.095), 1.65, side_windows[i][1]), side_windows[i][2], side_windows[i][3], V(side, 0, 0),
                boarded=4 if side > 0 else 0, broken=0.7, frame_mat="Steel" if v == 3 else "Trim", depth=0.19, backing=False)
        bx, by, bw, bh = back_window
        solid_wall(k, wall_mat, "x", rear, 0.21, -hw + 0.095, hw - 0.095, 0, top, [(bx - bw / 2, bx + bw / 2, by - bh / 2, by + bh / 2)])
        framed_window(k, V(bx, by, rear - 0.105), bw, bh, V(0, 0, -1), boarded=3, broken=0.5, frame_mat="Steel", depth=0.21, backing=False)
        solid_wall(k, wall_mat, "x", FRONT, 0.21, -hw + 0.095, hw - 0.095, 0, top, front_open)
        # A concrete plinth round the bottom, and the steel lintel over the openings.
        for side in (-1, 1):
            k.box("Concrete", V(side * (hw + 0.11), 0.15, mid), (0.04, 0.3, d + 0.23))
        k.box("Concrete", V(0, 0.15, rear - 0.12), (w + 0.23, 0.3, 0.04))
        for a, b in ((-hw - 0.11, SHUTTER[0]), (SHUTTER[1], DOOR[0]), (DOOR[1], hw + 0.11)):
            k.box("Concrete", V((a + b) / 2, 0.15, FRONT + 0.12), (b - a, 0.3, 0.04))
        k.box("Steel", V(-0.66, OPEN_TOP + 0.08, FRONT + 0.12), (4.9, 0.16, 0.04))
        if v == 3:
            # Brick piers at the corners and a soldier course over the openings.
            for sx in (-1, 1):
                for z in (rear, FRONT):
                    k.box("Brick", V(sx * (hw + 0.02), top / 2, z + (0.13 if z == FRONT else -0.13)), (0.42, top, 0.06))
            k.box("Brick", V(0, OPEN_TOP + 0.3, FRONT + 0.125), (w - 0.4, 0.24, 0.04))
    # Opening surrounds.
    if not far:
        shutter_surround(k, FRONT)
        door_frame(k, *DOOR, OPEN_TOP, FRONT)
    # Roofs and the fronts that go with them.
    if v == 0:
        # Flat roof behind a parapet with coping, a scupper and a downpipe.
        k.box("Roof", V(0, top + 0.06, mid), (w - 0.1, 0.1, d - 0.1))
        ptop = top + 0.42
        for z, sx in ((FRONT, w + 0.13), (rear, w + 0.13)):
            k.box(wall_mat, V(0, (top + ptop) / 2, z), (sx, ptop - top, 0.2))
            k.box("Concrete", V(0, ptop + 0.03, z), (sx + 0.08, 0.06, 0.28))
        for side in (-1, 1):
            k.box(wall_mat, V(side * hw, (top + ptop) / 2, mid), (0.19, ptop - top, d))
            k.box("Concrete", V(side * hw, ptop + 0.03, mid), (0.27, 0.06, d + 0.08))
        if not far:
            k.box("Steel", V(hw + 0.12, top + 0.15, rear + 1.0), (0.2, 0.12, 0.2))
            downpipe(k, hw + 0.2, rear + 1.0, top + 0.1, 0.0, 0.0)
            sign_band(k, -0.65, top - 0.1, FRONT + 0.105, 3.2, 0.42)
            # The awning: its frame bent down, a scrap of canvas left on it.
            for x in (-3.65, -1.0, 1.6):
                drop = 0.0 if x > -2 else 1.0
                k.cyl("Steel", V(x, OPEN_TOP + 0.45, FRONT + 0.1), V(x + (0.5 if drop else 0), OPEN_TOP + 0.45 - drop * 1.3 - (1 - drop) * 0.35,
                    FRONT + 1.15), 0.025, 6)
            k.cyl("Steel", V(-1.0, OPEN_TOP + 0.1, FRONT + 1.15), V(1.6, OPEN_TOP + 0.1, FRONT + 1.15), 0.025, 6)
            k.box("Fabric", V(0.3, OPEN_TOP + 0.28, FRONT + 0.62), (2.5, 0.02, 1.1), (radians(18), 0, 0))
            for i in range(4):
                k.box("Fabric", V(-0.7 + i * 0.6, OPEN_TOP - 0.05 - (i % 2) * 0.12, FRONT + 1.17), (0.5, 0.35 + (i % 2) * 0.2, 0.01))
            tyre_stack(k, (-hw - 0.55, 0, FRONT - 0.6), 5, lean=False)
            tyre_stack(k, (-hw - 0.55, 0, FRONT - 1.35), 3)
            tyre(k, V(hw + 0.45, 0.31, FRONT - 0.8), axis=V(1, 0, 0.25))
            tyre(k, V(-hw - 0.9, 0.1, FRONT + 0.9))
            meter_box(k, (hw + 0.17, 1.4, rear + 2.4), 1)
    elif v == 1:
        overhang = 0.3
        pitch = 0.25
        rise = (hw + overhang) * tan(pitch)
        eave = top + 0.08
        ridge = eave + rise
        if far:
            for side in (-1, 1):
                length = (hw + overhang) / cos(pitch)
                k.box("Roof", V(side * (hw + overhang) / 2, eave + rise / 2, mid), (length, 0.06, d + 0.5), (0, 0, -side * pitch))
            for z in (FRONT, rear):
                k.poly("Corrugated", [V(-hw, top, z + 0.1 * (1 if z == FRONT else -1)), V(hw, top, z + 0.1 * (1 if z == FRONT else -1)),
                    V(0, top + hw * tan(pitch), z + 0.1 * (1 if z == FRONT else -1))][::(1 if z == FRONT else -1)])
        else:
            for side in (-1, 1):
                start = V(side * (hw + overhang), eave - overhang * tan(pitch) + rise * 0 , rear - 0.3)
                run = V(-side * (hw + overhang), rise, 0)
                k.corrugated("Roof", V(side * (hw + overhang), eave - 0.0, rear - 0.35), V(0, 0, 1), run, d + 0.7, run.length, 0.076, 0.02, out=V(side * sin(pitch), cos(pitch), 0))
                # Purlins and rafters under it.
                for i in range(4):
                    t = (i + 0.3) / 4
                    k.box("Steel", V(side * (hw + overhang) * (1 - t), eave + rise * t - 0.08, mid), (0.05, 0.1, d + 0.4))
                for i in range(4):
                    z = rear + 0.25 + (d - 0.5) * i / 3
                    length = (hw) / cos(pitch)
                    k.box("Steel", V(side * hw / 2, eave + (rise * hw / (hw + overhang)) / 2 - 0.15, z), (length, 0.14, 0.08), (0, 0, -side * pitch))
                k.box("Steel", V(side * (hw + overhang + 0.06), eave - 0.08, mid), (0.12, 0.1, d + 0.7))
            k.box("Steel", V(0, ridge + 0.03, mid), (0.3, 0.04, d + 0.7))
            # Gable ends in sheet, both faces.
            for z, out in ((FRONT + 0.105, 1), (rear - 0.105, -1)):
                for zz, oo in ((z, out), (z - out * 0.21, -out)):
                    steps = int(w / 0.076)
                    for s in range(steps):
                        x0 = -hw + s * w / steps
                        x1 = x0 + w / steps
                        h0 = (hw - abs(x0)) * tan(pitch)
                        h1 = (hw - abs(x1)) * tan(pitch)
                        lift = 0.018 * oo if s % 2 else 0.0
                        k.quad("Corrugated", [V(x0, top, zz + lift), V(x1, top, zz + lift), V(x1, top + h1, zz + lift), V(x0, top + h0, zz + lift)][::oo])
            k.box("Dark interior", V(0, top + 0.35, FRONT + 0.13), (0.5, 0.3, 0.02))
            for i in range(5):
                k.box("Steel", V(0, top + 0.23 + i * 0.06, FRONT + 0.14), (0.5, 0.012, 0.03), (radians(30), 0, 0))
            sign_band(k, -0.65, OPEN_TOP + 0.55, FRONT + 0.125, 3.6, 0.42)
            downpipe(k, hw + 0.4, FRONT + 0.15, eave - 0.1, -0.3, 0.0)
            drum(k, V(hw + 0.5, 0, rear + 1.2))
            drum(k, V(hw + 0.55, 0, rear + 1.85), mat="Steel", lid=False)
            drum(k, V(hw + 0.9, 0, rear + 0.4), tipped=True)
            pallet(k, V(-hw - 0.15, 0.55, rear + 1.4), yaw=pi / 2, lean=0.0)
            k.box("Wood", V(-hw - 0.2, 0.6, rear + 1.4), (0.14, 1.2, 1.2), (0, 0, radians(-12)))
            meter_box(k, (-hw - 0.17, 1.5, FRONT - 1.0), 1)
            # An engine hoist left out back, rusted solid.
            k.span("Rust", V(-1.2, 0, rear - 1.2), V(0.6, 0, rear - 1.2), 0.08)
            k.span("Rust", V(-0.3, 0, rear - 1.2), V(-0.3, 1.9, rear - 1.0), 0.08)
            k.span("Rust", V(-0.3, 1.9, rear - 1.0), V(-0.3, 1.7, rear - 2.3), 0.07)
            k.cyl("Steel", V(-0.3, 1.7, rear - 2.3), V(-0.3, 1.1, rear - 2.3), 0.008, 4)
    elif v == 2:
        # Mono-pitch roof running out over a canopy on posts.
        y_back, y_front = top + 0.3, top + 0.02
        canopy = FRONT + 2.3
        if far:
            k.box("Roof", V(0, (y_back + y_front) / 2 + 0.05, (rear + canopy) / 2), (w + 0.4, 0.08, canopy - rear + 0.3), (atan2(y_back - y_front, canopy - rear), 0, 0))
            for x in (-3.13, 3.13):
                k.box("Steel", V(x, top / 2, FRONT + 1.9), (0.13, top, 0.14))
        else:
            corrugated_roof(k, -hw - 0.2, hw + 0.2, rear, canopy, y_front, y_back, overhang=0.15)
            purlins(k, -hw - 0.2, hw + 0.2, rear, canopy, y_front, y_back, 7)
            for x in (-3.13, 3.13):
                k.box("Steel", V(x, top / 2, FRONT + 1.9), (0.08, top, 0.14))
                k.box("Steel", V(x, top / 2, FRONT + 1.9), (0.14, top, 0.02))
                k.box("Concrete", V(x, 0.1, FRONT + 1.9), (0.3, 0.2, 0.3))
                k.span("Steel", V(x, top - 0.6, FRONT + 1.9), V(x, top - 0.05, FRONT + 1.2), 0.05)
            k.box("Steel", V(0, y_front - 0.1, FRONT + 1.9), (w + 0.2, 0.16, 0.08))
            k.box("Steel", V(0, y_front - 0.02, canopy + 0.12), (w + 0.4, 0.2, 0.03))
            # Gutter along the canopy edge, sagging, a downpipe down one post.
            k.cyl("Steel", V(-hw - 0.2, y_front - 0.1, canopy + 0.2), V(hw + 0.2, y_front - 0.22, canopy + 0.2), 0.06, 8)
            k.cyl("Steel", V(3.2, y_front - 0.2, canopy + 0.15), V(3.2, 0.2, FRONT + 2.0), 0.04, 8)
            # The gable triangles under the sloping roof, in sheet.
            for side in (-1, 1):
                x = side * (hw + 0.095)
                k.poly("Corrugated", [V(x, top, rear - 0.1), V(x, top, FRONT + 0.1), V(x, top + 0.04, FRONT + 0.1), V(x, y_back - 0.05, rear - 0.1)][::side])
            k.box("Corrugated", V(0, (top + y_front) / 2 + 0.02, FRONT + 0.105), (w + 0.2, y_front - top + 0.05, 0.01))
            sign_band(k, -0.65, OPEN_TOP + 0.4, FRONT + 0.125, 3.2, 0.36)
            # A loading dock's worth of leftovers under the canopy, out of the way.
            pallet(k, V(2.55, 0.0, FRONT + 1.2), yaw=0.1)
            pallet(k, V(2.6, 0.15, FRONT + 1.15), yaw=-0.05)
            k.box("Paper", V(2.5, 0.48, FRONT + 1.2), (0.6, 0.32, 0.5), (0, 0.2, 0))
            k.box("Paper", V(2.7, 0.75, FRONT + 1.05), (0.45, 0.25, 0.4), (0, -0.3, 0.05))
            # A sack truck against the wall.
            k.span("Steel", V(-hw - 0.05 - 0.2, 0.05, FRONT + 0.4), V(-hw - 0.2, 1.25, FRONT + 0.35), 0.03)
            k.span("Steel", V(-hw - 0.25, 0.05, FRONT + 0.8), V(-hw - 0.2, 1.25, FRONT + 0.75), 0.03)
            for wz in (FRONT + 0.4, FRONT + 0.8):
                tyre(k, V(-hw - 0.45, 0.12, wz), 0.12, 0.06, axis=V(0, 0, 1), sides=10)
            drum(k, V(-hw - 0.6, 0, rear + 1.0), mat="Red paint")
            meter_box(k, (hw + 0.17, 1.4, mid), 1)
    elif v == 3:
        k.box("Roof", V(0, top + 0.06, mid), (w + 0.3, 0.12, d + 0.4))
        k.box("Concrete", V(0, top + 0.16, mid), (w + 0.42, 0.08, d + 0.51))
        if not far:
            sign_band(k, -0.65, top - 0.35, FRONT + 0.11, 3.0, 0.4)
            downpipe(k, -hw - 0.15, FRONT - 0.3, top + 0.1)
            downpipe(k, hw + 0.15, rear + 0.4, top + 0.1)
            drum(k, V(hw + 0.55, 0, FRONT - 1.2))
            drum(k, V(hw + 0.6, 0, FRONT - 1.85), mat="Red paint")
            tyre(k, V(hw + 0.5, 0.1, FRONT - 2.6))
            tyre(k, V(hw + 0.5, 0.31, FRONT - 2.6))
            # An old air pump post by the forecourt.
            k.box("Red paint", V(-hw - 0.5, 0.6, FRONT + 0.6), (0.3, 1.2, 0.25))
            k.box("Steel", V(-hw - 0.5, 1.25, FRONT + 0.6), (0.34, 0.1, 0.29))
            k.cyl("Rubber", V(-hw - 0.36, 0.9, FRONT + 0.6), V(-hw - 0.2, 0.3, FRONT + 0.9), 0.012, 5)
            k.box("Yellow paint", V(-hw - 0.5, 0.15, FRONT + 0.6), (0.4, 0.3, 0.35))
            meter_box(k, (-hw - 0.17, 1.4, rear + 1.5), 1)
    if not far:
        # Inside: dead strip lights, a fuse board, conduit, oil on the floor.
        light_y = (top + 0.08 if v == 1 else top) - 0.45
        for z in (mid - d * 0.22, mid + d * 0.22):
            strip_light(k, V(-0.65, light_y, z))
        k.box("Steel", V(-hw + 0.17, 1.6, rear + 0.6), (0.1, 0.5, 0.36))
        k.cyl("Steel", V(-hw + 0.17, 1.85, rear + 0.6), V(-hw + 0.17, light_y + 0.2, rear + 0.6), 0.018, 6)
        k.cyl("Steel", V(-hw + 0.17, light_y + 0.2, rear + 0.6), V(-0.65, light_y + 0.2, rear + 0.6), 0.018, 6)
        for spot in ((-0.4, 1.0, 1.4), (-1.2, -0.6, 0.9), (0.3, 2.4, 0.7)):
            k.ico("Dark interior" if False else "Rubber", V(spot[0], 0.005, spot[1]), spot[2] * 0.5, (1, 0.004, 0.7), 1, 0.2)
        # Sand drifted in under the door and against the walls.
        for x, z, s in ((-0.6, FRONT - 0.3, 2.2), (2.4, FRONT - 0.25, 0.8), (-hw + 0.3, mid, 1.2)):
            k.ico("Rock" if False else "Concrete", V(x, -0.02, z), s, (1, 0.035, 0.35), 1, 0.25)
    return k.finish("Station")


# --- The workshop ----------------------------------------------------------------

def workshop(start=True, far=False):
    """The workshop: garage_model.gd's starting garage (and, without the
    extra room, the older stations from earlier saves)."""
    k = Kit(200)
    es = 0.8 if start else 0.0
    ed = 0.9 if start else 0.0
    hw = 3.16 + es
    rear = -2.8 - ed
    front_z = 4.14
    top = 2.95
    k.box("Concrete", V(0, -0.05, 0.8 - ed / 2), (6.6 + 2 * es, 0.12, 7.6 + ed))
    k.box("Concrete", V(-0.65, -0.033, 6.1), (4.6, 0.065, 3.2))
    if far:
        k.box("Corrugated", V(0, 1.47, rear), (6.4 + 2 * es, 2.95, 0.18))
        for side in (-1, 1):
            k.box("Corrugated", V(side * hw, 1.5, 0.7 - ed / 2), (0.16, 3.0, 7.0 + ed))
        k.box("Paint", V(0, 2.68, front_z), (6.4 + 2 * es, 0.64, 0.2))
        for x in (-3.07, 1.77, 3.05):
            k.box("Steel", V(x, 1.2, front_z), (0.23, 2.4, 0.24))
        if start:
            for side in (-1, 1):
                k.box("Corrugated", V(side * (3.16 + es / 2), 1.2, front_z), (es, 2.4, 0.2))
        k.box("Roof", V(0, 3.04, 0.7 - ed / 2), (7.05 + 2 * es, 0.19, 7.8 + ed))
        k.box("Steel", V(0, 3.08, 4.63), (7.1 + 2 * es, 0.29, 0.14))
        return k.finish("Workshop")
    # A block plinth all round, corrugated sheet above it, a liner inside.
    plinth = 0.6
    for side in (-1, 1):
        k.box("Block", V(side * hw, plinth / 2, 0.7 - ed / 2), (0.2, plinth, 7.0 + ed))
    k.box("Block", V(0, plinth / 2, rear), (6.4 + 2 * es, plinth, 0.22))
    x0, x1, z0, z1 = -hw - 0.08, hw + 0.08, rear - 0.09, front_z
    k.corrugated("Corrugated", V(x1, plinth, z0), V(-1, 0, 0), V(0, 1, 0), x1 - x0, top - plinth, out=V(0, 0, -1))
    window = (0.28, 1.92, 1.69, 2.43) if start else None
    for side in (-1, 1):
        x = side * x1
        if side < 0 and window:
            za, zb, ya, yb = window
            k.corrugated("Corrugated", V(x, plinth, z0), V(0, 0, 1), V(0, 1, 0), za - z0, top - plinth, out=V(-1, 0, 0))
            k.corrugated("Corrugated", V(x, plinth, zb), V(0, 0, 1), V(0, 1, 0), z1 - zb, top - plinth, out=V(-1, 0, 0))
            k.corrugated("Corrugated", V(x, plinth, za), V(0, 0, 1), V(0, 1, 0), zb - za, ya - plinth, out=V(-1, 0, 0))
            k.corrugated("Corrugated", V(x, yb, za), V(0, 0, 1), V(0, 1, 0), zb - za, top - yb, out=V(-1, 0, 0))
        else:
            k.corrugated("Corrugated", V(x, plinth, z1 if side > 0 else z0), V(0, 0, -side), V(0, 1, 0), z1 - z0, top - plinth, out=V(side, 0, 0))
        # Liner.
        k.corrugated("Corrugated", V(side * (hw - 0.08), plinth, rear + 0.09), V(0, 0, 1), V(0, 1, 0), front_z - rear - 0.2, top - plinth, out=V(-side, 0, 0))
        k.box("Steel", V(side * (x1 + 0.01), plinth + 0.02, (z0 + z1) / 2), (0.05, 0.05, z1 - z0))
        for z in (z0, z1):
            k.box("Steel", V(side * (x1 + 0.02), (top + plinth) / 2, z), (0.07, top - plinth, 0.07))
    k.corrugated("Corrugated", V(-hw + 0.08, plinth, rear + 0.09), V(1, 0, 0), V(0, 1, 0), 2 * hw - 0.16, top - plinth, out=V(0, 0, 1))
    if window:
        za, zb, ya, yb = window
        framed_window(k, V(-x1 - 0.02, (ya + yb) / 2, (za + zb) / 2), zb - za - 0.1, yb - ya - 0.1, V(-1, 0, 0), broken=0.0, frame_mat="Steel", depth=0.18, sill=True, backing=False)
    inner_frame(k, 2 * hw, rear, front_z, top, 3)
    # Front: the header with its sign board, posts, and the extension walls.
    k.box("Paint", V(0, 2.68, front_z), (6.4 + 2 * es, 0.64, 0.2))
    for i in range(int((6.4 + 2 * es) / 0.3)):
        k.box("Paint", V(-3.2 - es + 0.15 + i * 0.3, 2.68, front_z + 0.105), (0.015, 0.62, 0.012))
    for x in (-3.07, 1.77, 3.05):
        k.box("Steel", V(x, 1.2, front_z + 0.02), (0.2, 2.4, 0.16))
        k.box("Steel", V(x, 1.2, front_z + 0.02), (0.08, 2.4, 0.24))
        k.box("Concrete", V(x, 0.06, front_z + 0.02), (0.3, 0.12, 0.3))
    if start:
        for side in (-1, 1):
            xc = side * (3.16 + es / 2)
            k.box("Block", V(xc, 0.3, front_z), (es, 0.6, 0.2))
            k.corrugated("Corrugated", V(xc - es / 2, 0.6, front_z + 0.1), V(1, 0, 0), V(0, 1, 0), es, 1.8, out=V(0, 0, 1))
            k.corrugated("Corrugated", V(xc - es / 2, 0.6, front_z - 0.1), V(1, 0, 0), V(0, 1, 0), es, 1.8, out=V(0, 0, -1))
    shutter_surround(k, front_z - 0.02)
    door_frame(k, *DOOR, 2.29, front_z - 0.02)
    k.box("Steel", V(-0.65, 2.72, front_z + 0.14), (3.7, 0.55, 0.05))
    k.box("Sign", V(-0.65, 2.72, front_z + 0.17), (3.55, 0.42, 0.01))
    for dx in (-1.6, 1.6):
        k.span("Steel", V(-0.65 + dx, 3.05, front_z + 0.35), V(-0.65 + dx, 2.95, front_z + 0.17), 0.03)
        k.cyl("Steel", V(-0.65 + dx, 3.05, front_z + 0.35), V(-0.65 + dx * 0.95, 3.0, front_z + 0.55), 0.02, 6)
        k.cyl("Steel", V(-0.65 + dx * 0.95, 3.0, front_z + 0.55), V(-0.65 + dx * 0.95, 2.95, front_z + 0.6), 0.07, 8, 0.04)
    # Roof: sheets on purlins, fascia, gutter, downpipe.
    y_back, y_front = 3.18, 3.06
    corrugated_roof(k, -hw - 0.17, hw + 0.17, rear, front_z, y_front, y_back, overhang=0.35)
    purlins(k, -hw, hw, rear, front_z, y_front - 0.04, y_back - 0.04, 6)
    k.box("Steel", V(0, 3.08, 4.63), (7.1 + 2 * es, 0.29, 0.06))
    k.cyl("Steel", V(-hw - 0.4, 2.92, 4.72), V(hw + 0.4, 2.95, 4.72), 0.07, 8)
    downpipe(k, hw + 0.3, 4.72, 2.92, 0.0, -0.3)
    k.box("Steel", V(0, 3.0, rear - 0.25), (7.1 + 2 * es, 0.25, 0.06))
    # Outside: a drum and tyres by the wall, a gas bottle cage, a meter box.
    drum(k, V(hw + 0.5, 0, 0.6), mat="Red paint")
    drum(k, V(hw + 0.55, 0, -0.1), mat="Steel")
    tyre_stack(k, (-hw - 0.6, 0, 3.4), 4, lean=True)
    meter_box(k, (hw + 0.13, 1.5, -1.6), 1)
    for y in (0.0, 1.3):
        k.box("Steel", V(-hw - 0.45, y + 0.02, -1.0), (0.6, 0.04, 0.9))
    for x in (-hw - 0.17, -hw - 0.73):
        for z in (-1.43, -0.57):
            k.box("Steel", V(x, 0.66, z), (0.03, 1.32, 0.03))
    for z in (-1.2, -0.8):
        k.cyl("Steel", V(-hw - 0.45, 0.04, z), V(-hw - 0.45, 1.0, z), 0.13, 12)
        k.cyl("Steel", V(-hw - 0.45, 1.0, z), V(-hw - 0.45, 1.12, z), 0.13, 12, 0.05)
    # Inside: strip lights, conduit, a fire extinguisher on the post.
    for z in (-1.2, 1.4):
        strip_light(k, V(-0.65, 2.6, z), dead=False)
    k.cyl("Red paint", V(-hw + 0.25, 0.9, 3.5), V(-hw + 0.25, 1.4, 3.5), 0.07, 10)
    k.box("Steel", V(-hw + 0.12, 1.15, 3.5), (0.04, 0.3, 0.06))
    return k.finish("Workshop")


# --- Bench and shelves -------------------------------------------------------

def workbench():
    """Matches garage_model.gd's bench: top at y = 0.97 from x = 0.72 to 2.92,
    z = -2.645 to -2.015; pegboard on the wall behind it."""
    k = Kit(300)
    for i in range(5):
        k.box("Wood", V(1.82, 0.935, -2.645 + 0.063 + i * 0.126), (2.2, 0.07, 0.122))
    k.box("Steel", V(1.82, 0.88, -2.33), (2.18, 0.04, 0.6))
    for x in (0.84, 2.79):
        for z in (-2.57, -2.1):
            k.box("Steel", V(x, 0.44, z), (0.05, 0.88, 0.05))
        k.box("Steel", V(x, 0.15, -2.335), (0.04, 0.04, 0.47))
    k.box("Steel", V(1.82, 0.15, -2.1), (1.95, 0.04, 0.04))
    k.box("Wood", V(1.4, 0.17, -2.335), (1.0, 0.025, 0.42))
    # Drawer unit.
    k.box("Steel", V(2.46, 0.6, -2.33), (0.6, 0.52, 0.5))
    for y in (0.46, 0.63, 0.79):
        k.box("Steel", V(2.46, y, -2.075), (0.55, 0.14, 0.012))
        k.box("Steel", V(2.46, y + 0.03, -2.06), (0.2, 0.025, 0.025))
    # A vise on the end.
    k.box("Steel", V(0.95, 1.03, -2.08), (0.18, 0.12, 0.16))
    k.box("Steel", V(0.95, 1.06, -1.97), (0.16, 0.1, 0.05))
    k.cyl("Steel", V(0.95, 1.04, -1.9), V(0.95, 1.04, -1.82), 0.012, 6)
    k.cyl("Steel", V(0.87, 1.04, -1.82), V(1.03, 1.04, -1.82), 0.01, 6)
    # Pegboard with tools on it, and outlines of the ones taken.
    k.box("Wood", V(1.82, 1.47, -2.67), (1.68, 0.62, 0.02))
    k.box("Steel", V(1.82, 1.8, -2.66), (1.72, 0.04, 0.04))
    k.box("Steel", V(1.82, 1.14, -2.66), (1.72, 0.04, 0.04))
    for i in range(7):
        x = 1.18 + i * 0.21
        h = 0.14 + (i % 3) * 0.06
        if i in (2, 5):
            k.box("Dark interior", V(x, 1.47, -2.658), (0.045, h, 0.002))
            continue
        k.box("Steel", V(x, 1.5, -2.645), (0.035, h, 0.02), (0, 0, 0.13 * (i - 3)))
        k.box("Red paint" if i % 2 else "Rubber", V(x, 1.5 - h / 2 - 0.04, -2.645), (0.04, 0.09, 0.03), (0, 0, 0.13 * (i - 3)))
    k.box("Steel", V(2.45, 1.62, -2.64), (0.3, 0.02, 0.06))
    for i in range(4):
        k.cyl("Tin", V(2.34 + i * 0.07, 1.63, -2.635), V(2.34 + i * 0.07, 1.68, -2.635), 0.022, 8)
    return k.finish("Workbench")


def shelving():
    """Matches garage_model.gd's shelves at y = 0.36, 0.98, 1.58, from x =
    2.48 to 3.04, z = -0.45 to 1.29; parts bins on the top shelf."""
    k = Kit(301)
    for y in (0.36, 0.98, 1.58):
        k.box("Steel", V(2.76, y + 0.02, 0.42), (0.54, 0.02, 1.72))
        for x in (2.49, 3.03):
            k.box("Steel", V(x, y, 0.42), (0.03, 0.06, 1.74))
    for x in (2.49, 3.04):
        for z in (-0.42, 1.26):
            k.box("Steel", V(x, 0.88, z), (0.04, 1.76, 0.012))
            k.box("Steel", V(x, 0.88, z + (0.014 if z < 0 else -0.014)), (0.012, 1.76, 0.04))
    for z in (-0.42, 1.26):
        k.span("Steel", V(3.04, 0.2, z), V(3.04, 1.5, z), 0.012)
    k.span("Steel", V(3.04, 0.3, -0.42), V(3.04, 1.4, 1.26), 0.01)
    k.span("Steel", V(3.04, 1.4, -0.42), V(3.04, 0.3, 1.26), 0.01)
    for z in (-0.13, 0.55):
        k.box("Red paint", V(2.78, 1.69, z), (0.38, 0.17, 0.43))
        k.box("Dark interior", V(2.585, 1.72, z), (0.01, 0.08, 0.3))
    k.box("Paper", V(2.75, 1.08, 1.0), (0.4, 0.18, 0.3), (0, 0.15, 0))
    k.box("Paper", V(2.8, 1.66, 1.05), (0.35, 0.14, 0.28), (0, -0.2, 0))
    for i in range(3):
        k.cyl("Tin", V(2.65 + i * 0.1, 1.0, -0.3), V(2.65 + i * 0.1, 1.13, -0.3), 0.04, 10)
    return k.finish("Shelving")


build_all([
    *[("station_%d" % v, (lambda v=v: station(v))) for v in range(4)],
    *[("station_%d_far" % v, (lambda v=v: station(v, True))) for v in range(4)],
    ("workshop", lambda: workshop(True)),
    ("workshop_far", lambda: workshop(True, True)),
    ("workshop_small", lambda: workshop(False)),
    ("workshop_small_far", lambda: workshop(False, True)),
    ("workbench", workbench),
    ("shelving", shelving),
])
