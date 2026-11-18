"""Vehicle parts for the desert road, and Len's van. Exported to
assets/desert/vehicles/.

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_road_vehicles.py

The cars' painted body panels stay procedural (scripts/compact_car_model.gd)
because the game dents them, repaints them and lets you take them off. What
is built here replaces the box-shaped pieces around them:

- Unit parts, modelled inside a 1 x 1 x 1 box centred on the origin, that the
  game scales to the size the old box had and keeps the old material on:
  lens, lamp_bezel, grille_slat, mirror_housing, door_handle, number_plate,
  seat_back, headrest, bench, air_vent, radio, pedal.
- Whole parts with their own materials: car_wheel (radius 0.39 m, axle along
  X), steering_wheel (in the plane of Steerwheel's local XZ), and Len's van
  (len_van.glb and its open driver's door, len_van_door.glb), matching
  scripts/len_van.gd, which keeps its own colliders, keys and notes.

Coordinates are Godot's (Y up, front towards -Z).
"""

import sys
from math import atan2, cos, pi, radians, sin, sqrt
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import desert_kit
from desert_kit import V, Kit, build_all, reset, fix_normals

OUT = desert_kit.ROOT / "assets/desert/vehicles"
OUT.mkdir(parents=True, exist_ok=True)
desert_kit.OUT = OUT
for name, color in {"Chrome": (0.8, 0.8, 0.8), "Lens": (0.9, 0.88, 0.8), "Reflector": (0.6, 0.6, 0.6),
                    "Upholstery": (0.35, 0.32, 0.27), "Vinyl": (0.12, 0.12, 0.12), "Carpet": (0.2, 0.19, 0.17),
                    "Gauge": (0.05, 0.05, 0.05), "Van paint": (0.5, 0.52, 0.44), "Tread": (0.03, 0.03, 0.03)}.items():
    desert_kit.COLORS[name] = color


def rounded_box(k, mat, center, size, r, seg=3, rot=(0, 0, 0)):
    """A box with rounded vertical and top edges, by stacking rounded slabs."""
    c = Vector(center)
    sx, sy, sz = size
    r = min(r, sx / 2, sz / 2, sy / 2)
    rows = []
    for j in range(seg + 1):
        a = j / seg * pi / 2
        rows.append((sy / 2 - r + sin(a) * r, cos(a)))
    rows = [(-sy / 2 + r - sin(j / seg * pi / 2) * r, cos(j / seg * pi / 2)) for j in range(seg, 0, -1)] + rows
    bm = k.bm(mat)
    rotm = Euler(rot, "YXZ").to_matrix()
    rings = []
    for y, f in rows:
        ring = []
        hx = sx / 2 - r + r * f
        hz = sz / 2 - r + r * f
        rr = r * f
        for corner, (cx, cz) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
            for s in range(seg + 1):
                a = (corner + s / seg) * pi / 2
                px = cx * (hx - rr) + cos(a) * rr
                pz = cz * (hz - rr) + sin(a) * rr
                ring.append(bm.verts.new(c + rotm @ Vector((px, y, pz))))
        rings.append(ring)
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(rings[-1])
    bm.faces.new(rings[0][::-1])


def revolve(k, mat, profile, sides=48, axis="x", phase=0.0):
    """Revolve (offset along axis, radius) points round the X axis."""
    bm = k.bm(mat)
    rings = []
    for u, r in profile:
        ring = []
        for s in range(sides):
            a = phase + s / sides * 2 * pi
            ring.append(bm.verts.new(Vector((u, cos(a) * r, sin(a) * r))))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(sides):
            bm.faces.new((a[i], a[(i + 1) % sides], b[(i + 1) % sides], b[i]))


# --- Unit parts --------------------------------------------------------------

def lens():
    """A lamp lens: pillowed face with fluting, the face towards -Z."""
    k = Kit(800)
    rounded_box(k, "Lens", V(0, 0, 0.1), (1.0, 1.0, 0.8), 0.12, 3)
    for i in range(9):
        x = -0.4 + i * 0.1
        k.box("Lens", V(x, 0, -0.32), (0.06, 0.86, 0.12))
    for j in range(4):
        k.box("Lens", V(0, -0.33 + j * 0.22, -0.34), (0.9, 0.04, 0.1))
    return k.finish("Lens")


def lamp_bezel():
    """A chrome-edged housing round a lamp: a frame with a back, open at -Z."""
    k = Kit(801)
    t = 0.12
    for sx, sy, x, y in ((1.0, t, 0, 0.5 - t / 2), (1.0, t, 0, -0.5 + t / 2), (t, 1.0, 0.5 - t / 2, 0), (t, 1.0, -0.5 + t / 2, 0)):
        rounded_box(k, "Lens", V(x, y, -0.1), (sx, sy, 0.8), 0.04, 2)
    k.box("Lens", V(0, 0, 0.42), (1.0, 1.0, 0.16))
    return k.finish("Bezel")


def grille_slat():
    k = Kit(802)
    rounded_box(k, "Lens", V(0, 0, 0), (1.0, 1.0, 1.0), 0.45, 4, rot=(0, 0, 0))
    return k.finish("Slat")


def mirror_housing():
    """Teardrop housing, glass face towards +Z (as the game's mirror box)."""
    k = Kit(803)
    bm_parts = []
    for j in range(7):
        t = j / 6
        z = 0.5 - t
        w = 0.5 * (1 - 0.55 * t * t)
        h = 0.5 * (1 - 0.4 * t * t)
        rounded_box(k, "Lens", V(0, 0, z - 0.08), (2 * w, 2 * h, 0.17), min(w, h) * 0.6, 3)
    return k.finish("Mirror")


def door_handle():
    k = Kit(804)
    rounded_box(k, "Lens", V(0.2, 0, 0), (0.6, 0.8, 1.0), 0.25, 3)
    rounded_box(k, "Lens", V(-0.2, 0, 0), (0.6, 0.5, 0.75), 0.2, 3)
    return k.finish("Handle")


def number_plate():
    """A blank plate with a pressed rim (front face +Z)."""
    k = Kit(805)
    k.box("Lens", V(0, 0, 0), (1.0, 1.0, 0.5))
    for sx, sy, x, y in ((0.96, 0.06, 0, 0.44), (0.96, 0.06, 0, -0.44), (0.03, 0.88, 0.47, 0), (0.03, 0.88, -0.47, 0)):
        k.box("Lens", V(x, y, 0.35), (sx, sy, 0.3))
    for x in (-0.38, 0.38):
        k.cyl("Lens", V(x, 0.3, 0.25), V(x, 0.3, 0.5), 0.03, 8)
    return k.finish("Plate")


def seat_back():
    """Bolstered seat back with pleats; the face towards -Z."""
    k = Kit(806)
    rounded_box(k, "Lens", V(0, 0, 0.05), (0.62, 0.98, 0.85), 0.2, 3)
    for side in (-1, 1):
        rounded_box(k, "Lens", V(side * 0.39, -0.02, -0.08), (0.22, 0.96, 0.98), 0.1, 3)
    for j in range(6):
        y = -0.4 + j * 0.16
        rounded_box(k, "Lens", V(0, y, -0.38), (0.6, 0.13, 0.2), 0.06, 2)
    return k.finish("SeatBack")


def headrest():
    k = Kit(807)
    rounded_box(k, "Lens", V(0, 0, 0), (1.0, 1.0, 1.0), 0.35, 4)
    return k.finish("Headrest")


def bench():
    k = Kit(808)
    rounded_box(k, "Lens", V(0, 0.05, 0), (1.0, 0.9, 1.0), 0.18, 3)
    for i in range(7):
        x = -0.39 + i * 0.13
        rounded_box(k, "Lens", V(x, 0.42, 0), (0.11, 0.2, 0.92), 0.05, 2)
    return k.finish("Bench")


def air_vent():
    k = Kit(809)
    for sx, sy, x, y in ((1.0, 0.14, 0, 0.43), (1.0, 0.14, 0, -0.43), (0.1, 1.0, 0.45, 0), (0.1, 1.0, -0.45, 0)):
        rounded_box(k, "Lens", V(x, y, 0), (sx, sy, 1.0), 0.04, 2)
    k.box("Lens", V(0, 0, -0.4), (0.9, 0.8, 0.2))
    for j in range(5):
        k.box("Lens", V(0, -0.3 + j * 0.15, 0.2), (0.84, 0.05, 0.6), (radians(-25), 0, 0))
    return k.finish("Vent")


def radio():
    k = Kit(810)
    rounded_box(k, "Lens", V(0, 0, -0.2), (1.0, 1.0, 0.6), 0.06, 2)
    k.box("Lens", V(0, 0.15, 0.15), (0.45, 0.3, 0.2))
    for i in range(5):
        k.box("Lens", V(-0.2 + i * 0.1, -0.28, 0.15), (0.07, 0.18, 0.25))
    return k.finish("Radio")


def pedal():
    k = Kit(811)
    rounded_box(k, "Lens", V(0, 0, 0), (1.0, 1.0, 0.6), 0.2, 2)
    for j in range(4):
        k.box("Lens", V(0, -0.33 + j * 0.22, -0.32), (0.85, 0.08, 0.1))
    return k.finish("Pedal")


# --- Whole parts -------------------------------------------------------------

def car_wheel(radius=0.39, width=0.218, rim_r=0.27, name="Wheel"):
    """Tyre with a rounded shoulder and sidewall, a shallow road tread, a
    pressed-steel rim with cooling slots, hubcap and lug nuts. Axle along X."""
    k = Kit(820)
    hw = width / 2
    # Tyre carcass: bead, a bulging sidewall, rounded shoulders, and a flat
    # crown with two shallow grooves running round it.
    R = radius
    left = [(-0.9 * hw, rim_r + 0.012), (-1.0 * hw, rim_r + 0.035), (-1.05 * hw, rim_r + 0.07), (-1.04 * hw, R - 0.055),
        (-0.99 * hw, R - 0.032), (-0.9 * hw, R - 0.019), (-0.8 * hw, R - 0.0135), (-0.36 * hw, R - 0.012),
        (-0.33 * hw, R - 0.0155), (-0.22 * hw, R - 0.0155), (-0.19 * hw, R - 0.012)]
    profile = left + [(-u, r) for u, r in reversed(left)]
    revolve(k, "Rubber", profile, 72)
    # Cross grooves: thin dark cuts laid on the crown, flush, staggered.
    cuts = 64
    for i in range(cuts):
        a = i / cuts * 2 * pi
        for row, (u0, u1, off) in enumerate(((-0.78 * hw, -0.36 * hw, 0.0), (0.36 * hw, 0.78 * hw, 0.5), (-0.17 * hw, 0.17 * hw, 0.25))):
            if row == 2 and i % 2:
                continue
            aa = a + off * 2 * pi / cuts
            mid = (u0 + u1) / 2
            c = Vector((mid, cos(aa) * (R - 0.0118), sin(aa) * (R - 0.0118)))
            k.box("Tread", c, (u1 - u0, 0.0012, 0.0055), (aa, radians(14 if row == 0 else -14), 0))
    for side in (-1, 1):
        # A raised ring of ribs on the sidewall.
        for i in range(24):
            a = i / 24 * 2 * pi
            k.box("Rubber", Vector((side * hw * 1.03, cos(a) * (radius - 0.075), sin(a) * (radius - 0.075))), (0.004, 0.004, 0.02), (a, 0, 0))
    # Rim: barrel, flanges, dished face with slots, hub and nuts (outer face +X).
    revolve(k, "Steel", [(-hw * 0.85, rim_r + 0.012), (-hw * 0.85, rim_r - 0.005), (-hw * 0.7, rim_r - 0.02),
        (hw * 0.7, rim_r - 0.02), (hw * 0.85, rim_r - 0.005), (hw * 0.85, rim_r + 0.012)], 48)
    revolve(k, "Steel", [(hw * 0.82, rim_r - 0.02), (hw * 0.6, rim_r * 0.82), (hw * 0.55, rim_r * 0.55),
        (hw * 0.62, rim_r * 0.4), (hw * 0.62, 0.0001)], 48)
    revolve(k, "Steel", [(-hw * 0.6, 0.0001), (-hw * 0.6, rim_r * 0.5), (-hw * 0.82, rim_r - 0.02)], 32)
    for i in range(8):
        a = i / 8 * 2 * pi + pi / 8
        c = Vector((hw * 0.585, cos(a) * rim_r * 0.68, sin(a) * rim_r * 0.68))
        k.box("Gauge", c, (0.012, 0.03, 0.055), (a, 0, 0))
    revolve(k, "Chrome", [(hw * 0.62, rim_r * 0.42), (hw * 0.72, rim_r * 0.4), (hw * 0.8, rim_r * 0.3), (hw * 0.83, rim_r * 0.12), (hw * 0.84, 0.0001)], 32)
    for i in range(4):
        a = i / 4 * 2 * pi
        k.cyl("Steel", Vector((hw * 0.62, cos(a) * 0.072, sin(a) * 0.072)), Vector((hw * 0.7, cos(a) * 0.072, sin(a) * 0.072)), 0.012, 6)
    obj = k.finish(name)
    return obj


def steering_wheel():
    """Rim (radius 0.164) with a stitched grip, three spokes and a horn pad, in
    the XZ plane like the TorusMesh it replaces; the driver sees +Y."""
    k = Kit(821)
    bm = k.bm("Vinyl")
    rings = []
    seg, tube = 48, 10
    for i in range(seg):
        a = i / seg * 2 * pi
        centre = Vector((cos(a) * 0.164, 0, sin(a) * 0.164))
        out = Vector((cos(a), 0, sin(a)))
        ring = []
        for j in range(tube):
            b = j / tube * 2 * pi
            r = 0.0135 * (1.0 + 0.08 * (1 if (i % 4 < 2 and abs(sin(a)) > 0.5) else 0))
            ring.append(bm.verts.new(centre + out * cos(b) * r + Vector((0, sin(b) * r, 0))))
        rings.append(ring)
    for i in range(seg):
        a, b = rings[i], rings[(i + 1) % seg]
        for j in range(tube):
            bm.faces.new((a[j], a[(j + 1) % tube], b[(j + 1) % tube], b[j]))
    for ang in (0.0, pi, pi / 2):
        d = Vector((cos(ang), 0, sin(ang)))
        k.span("Steel", d * 0.05 + Vector((0, 0.01, 0)), d * 0.155, 0.03, 0.012)
    rounded_box(k, "Vinyl", V(0, 0.018, 0.0), (0.12, 0.04, 0.09), 0.02, 2)
    k.cyl("Chrome", V(0, 0.038, 0), V(0, 0.042, 0), 0.02, 12)
    return k.finish("Steering")


# --- Len's van ---------------------------------------------------------------------

def len_van():
    """A boxy old delivery van: cab with a short nose, a tall cargo box with
    rear doors and a sliding side door, chrome bumpers, round lamps."""
    k = Kit(830)
    w = 1.8
    hw = w / 2
    # Lower body / sills all along, and the cargo box (with rounded top edges).
    rounded_box(k, "Van paint", V(0, 0.55, 0.0), (w, 0.5, 4.3), 0.06, 2)
    rounded_box(k, "Van paint", V(0, 1.32, 0.88), (w, 1.22, 2.52), 0.12, 3)
    # Cab: sides up to the belt, the roof, pillars round the windows.
    rounded_box(k, "Van paint", V(0, 1.0, -0.98), (w, 0.42, 1.78), 0.06, 2)
    rounded_box(k, "Van paint", V(0, 1.88, -0.8), (w - 0.02, 0.14, 1.66), 0.07, 3)
    for side in (-1, 1):
        k.span("Van paint", V(side * (hw - 0.04), 1.2, -1.66), V(side * (hw - 0.04), 1.82, -1.52), 0.07)
        k.span("Van paint", V(side * (hw - 0.04), 1.2, -0.43), V(side * (hw - 0.04), 1.82, -0.43), 0.08)
    k.box("Van paint", V(0, 1.84, -1.6), (w - 0.06, 0.1, 0.12))
    # Bonnet, sloping a little, a grille and round lamps.
    k.box("Van paint", V(0, 0.86, -1.87), (w - 0.02, 0.3, 0.72), (radians(-3), 0, 0))
    k.box("Chrome", V(0, 0.83, -2.245), (0.86, 0.22, 0.03))
    for i in range(6):
        k.box("Gauge", V(0, 0.75 + i * 0.033, -2.255), (0.8, 0.018, 0.02))
    for side in (-1, 1):
        k.cyl("Chrome", V(side * 0.61, 0.84, -2.24), V(side * 0.61, 0.84, -2.28), 0.11, 20)
        k.cyl("Lens", V(side * 0.61, 0.84, -2.27), V(side * 0.61, 0.84, -2.29), 0.09, 20)
        k.box("Yellow paint", V(side * 0.8, 0.84, -2.25), (0.09, 0.08, 0.03))
    # Glass.
    k.box("Glass", V(0, 1.45, -1.57), (1.6, 0.74, 0.02), (radians(-12.6), 0, 0))
    for side in (-1, 1):
        k.box("Glass", V(side * (hw - 0.01), 1.5, -1.0), (0.02, 0.5, 1.0))
    # Bumpers, chrome with rubber strip.
    for z in (-2.3, 2.17):
        rounded_box(k, "Chrome", V(0, 0.53, z), (1.94, 0.15, 0.12), 0.04, 2)
        k.box("Rubber", V(0, 0.53, z + (-0.065 if z < 0 else 0.065)), (1.9, 0.04, 0.012))
    # Rear doors with a seam, hinges, handles; tall tail lamps.
    k.box("Gauge", V(0, 1.32, 2.141), (0.012, 1.08, 0.006))
    for side in (-1, 1):
        for y in (0.95, 1.7):
            k.box("Chrome", V(side * 0.86, y, 2.15), (0.05, 0.1, 0.04))
        k.box("Chrome", V(side * 0.1, 1.3, 2.155), (0.04, 0.16, 0.03))
        rounded_box(k, "Red paint", V(side * 0.75, 0.99, 2.15), (0.13, 0.43, 0.05), 0.02, 2)
        k.box("Glass", V(side * 0.45, 1.62, 2.142), (0.6, 0.36, 0.01))
    # Sliding side door rails and seams (passenger side), fuel flap, mirrors.
    k.box("Gauge", V(-hw - 0.002, 1.25, -0.2), (0.006, 1.3, 0.012))
    k.box("Gauge", V(-hw - 0.002, 1.25, 0.9), (0.006, 1.3, 0.012))
    k.box("Steel", V(-hw - 0.02, 1.15, 0.9), (0.03, 0.03, 2.3))
    k.cyl("Steel", V(hw + 0.003, 0.75, 1.6), V(hw + 0.01, 0.75, 1.6), 0.06, 14)
    for side in (-1, 1):
        k.span("Steel", V(side * hw, 1.3, -1.45), V(side * (hw + 0.2), 1.45, -1.45), 0.015)
        rounded_box(k, "Gauge", V(side * (hw + 0.24), 1.45, -1.45), (0.1, 0.24, 0.05), 0.02, 2)
    # Arches, dark under the body.
    for side in (-1, 1):
        for axle in (-1.46, 1.34):
            k.cyl("Rubber", V(side * (hw - 0.05), 0.35, axle), V(side * (hw + 0.005), 0.35, axle), 0.43, 24)
    k.box("Rubber", V(0, 0.33, 0), (1.6, 0.1, 3.8))
    # Inside the cab: dash, seats, floor, bulkhead.
    rounded_box(k, "Vinyl", V(0, 1.04, -1.43), (1.61, 0.16, 0.36), 0.05, 2)
    k.box("Gauge", V(0.4, 1.1, -1.27), (0.32, 0.1, 0.02))
    for i in range(2):
        k.cyl("Chrome", V(0.32 + i * 0.16, 1.1, -1.262), V(0.32 + i * 0.16, 1.1, -1.255), 0.04, 16)
    k.box("Carpet", V(0, 0.79, -0.95), (1.7, 0.02, 1.1))
    k.box("Upholstery", V(0, 1.3, -0.43), (1.73, 1.08, 0.1))
    for side in (-1, 1):
        rounded_box(k, "Upholstery", V(side * 0.42, 0.84, -0.84), (0.54, 0.14, 0.48), 0.05, 2)
        rounded_box(k, "Upholstery", V(side * 0.42, 1.08, -0.6), (0.54, 0.5, 0.11), 0.05, 2, rot=(0.16, 0, 0))
        for j in range(4):
            k.box("Upholstery", V(side * 0.42, 0.915, -1.02 + j * 0.12), (0.5, 0.015, 0.02))
    return k.finish("LenVan")


def len_van_door():
    """The driver's door, swung open (in OpenDriverDoor's space)."""
    k = Kit(831)
    rounded_box(k, "Van paint", V(0, 1.04, 0.53), (0.08, 0.62, 1.05), 0.03, 2)
    k.box("Upholstery", V(-0.045, 1.04, 0.53), (0.02, 0.5, 0.92))
    k.box("Vinyl", V(-0.07, 1.12, 0.7), (0.05, 0.05, 0.3))
    for a, b in ((V(0, 1.34, 0.06), V(0, 1.8, 0.26)), (V(0, 1.8, 0.26), V(0, 1.8, 1.03)), (V(0, 1.8, 1.03), V(0, 1.34, 1.03))):
        k.span("Van paint", a, b, 0.045)
    k.poly("Glass", [V(0, 1.35, 0.08), V(0, 1.35, 1.0), V(0, 1.78, 1.0), V(0, 1.78, 0.28)])
    k.box("Chrome", V(0.05, 1.18, 0.95), (0.03, 0.04, 0.14))
    return k.finish("VanDoor")


def build_set(builds):
    for name, build in builds:
        reset()
        obj = build()
        fix_normals(obj)
        desert_kit.export([obj], name)


build_set([
    ("lens", lens), ("lamp_bezel", lamp_bezel), ("grille_slat", grille_slat), ("mirror_housing", mirror_housing),
    ("door_handle", door_handle), ("number_plate", number_plate), ("seat_back", seat_back), ("headrest", headrest),
    ("bench", bench), ("air_vent", air_vent), ("radio", radio), ("pedal", pedal),
    ("car_wheel", car_wheel), ("steering_wheel", steering_wheel),
    ("len_van", len_van), ("len_van_door", len_van_door),
])
