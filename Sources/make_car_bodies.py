"""The cars' painted body shells, panel by panel, for the sedan, hatchback and
wagon. Exported to assets/desert/vehicles/body_<style>_<panel>.glb.

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_car_bodies.py

scripts/compact_car_model.gd still builds every node, hinge, mount and
collider (the game dents panels, repaints them and lets you take them off);
these meshes replace the meshes on its painted panels, in the same local
coordinates, so nothing moves. The body numbers below are copied from that
script. Panels:

    chassis    the body sides, fenders with flared arches and a rolled sill,
               the nose and tail faces (node Chassis/BodyPaint)
    cabin      roof with a crown and drip rails, and the pillars
               (Chassis/RoofPaint; the old pillar boxes are hidden)
    door_FL .. door_RR   each door skin with its window frame, in door space
    hood       crowned, rolled at the edges (HoodTargetHinge/Hood)
    trunk      the sedan's boot lid (TrunkTargetHinge/Trunk)
    tailgate   the hatchback's and wagon's lift-gate panel and frame
    bumper_front, bumper_rear

Every panel is dense enough (a few centimetres between vertices) for the
game's dents to look like dents. Godot coordinates: Y up, nose towards -Z.
"""

import sys
from math import cos, pi, radians, sin, sqrt
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import desert_kit
from desert_kit import V, Kit, reset, material, TO_BLENDER

OUT = desert_kit.ROOT / "assets/desert/vehicles"
OUT.mkdir(parents=True, exist_ok=True)
desert_kit.OUT = OUT

# --- From scripts/compact_car_model.gd -----------------------------------------

BODIES = [
    {"sections": [[-2.24, 0.805, 0.785], [-2.10, 0.88, 0.84], [-1.72, 0.915, 0.885], [-0.91, 0.905, 0.91],
        [0.045, 0.895, 0.92], [0.98, 0.905, 0.93], [1.28, 0.925, 0.945], [1.93, 0.91, 0.92], [2.22, 0.85, 0.885]],
     "roof": [V(0.637, 1.515, -0.30), V(0.641, 1.50, 0.70)], "rear": V(0.779, 0.945, 1.28)},
    {"sections": [[-2.10, 0.78, 0.785], [-1.98, 0.865, 0.83], [-1.62, 0.915, 0.885], [-0.91, 0.905, 0.91],
        [0.045, 0.895, 0.92], [0.98, 0.905, 0.93], [1.25, 0.915, 0.93], [1.88, 0.89, 0.905], [2.00, 0.84, 0.905]],
     "roof": [V(0.657, 1.58, -0.42), V(0.65, 1.55, 1.02)], "rear": V(0.770, 0.911, 1.91)},
    {"sections": [[-2.27, 0.82, 0.845], [-2.17, 0.889, 0.875], [-1.70, 0.925, 0.895], [-0.91, 0.905, 0.91],
        [0.045, 0.895, 0.92], [0.98, 0.905, 0.93], [1.57, 0.922, 0.944], [2.12, 0.92, 0.943], [2.32, 0.868, 0.93]],
     "roof": [V(0.664, 1.61, -0.37), V(0.663, 1.605, 1.86)], "rear": V(0.788, 0.931, 2.30)},
]
SEDAN, HATCHBACK, WAGON = 0, 1, 2
SILL = 0.306
WHEEL_AXLES = [-1.4, 1.43]
ARCH_RADIUS = 0.46
ARCH_HUB_HEIGHT = 0.31
ARCH_RISE = 0.41
HOOD_FRONT = -2.08
HOOD_BACK = -0.916
HOOD_HALF_WIDTH = 0.739
WINDSHIELD_BASE = V(0.775, 0.915, -0.89)
DOORS = {"FL_Door": (-1, True), "FR_Door": (1, True), "RL_Door": (-1, False), "RR_Door": (1, False)}


def lerp(a, b, t):
    return a + (b - a) * t


def clamp01(t):
    return max(0.0, min(1.0, t))


def inv_lerp(a, b, v):
    return (v - a) / (b - a) if b != a else 0.0


def smoothstep(a, b, v):
    t = clamp01(inv_lerp(a, b, v))
    return t * t * (3 - 2 * t)


def station(z, style):
    rows = BODIES[style]["sections"]
    for i in range(1, len(rows)):
        b = rows[i]
        if z <= b[0]:
            a = rows[i - 1]
            t = clamp01(inv_lerp(a[0], b[0], z))
            return lerp(a[1], b[1], t), lerp(a[2], b[2], t)
    return rows[-1][1], rows[-1][2]


def arch_bottom(z):
    for axle in WHEEL_AXLES:
        off = z - axle
        if abs(off) < ARCH_RADIUS:
            return max(SILL, ARCH_HUB_HEIGHT + ARCH_RISE * sqrt(max(0.0, 1.0 - (off / ARCH_RADIUS) ** 2)))
    return SILL


def rear_bumper(style):
    return BODIES[style]["sections"][-1][0]


def opening_edge(z, style):
    w, h = station(z, style)
    if z < 0.0:
        rise = clamp01(inv_lerp(HOOD_FRONT, HOOD_BACK, z))
        return min(w - 0.04, HOOD_HALF_WIDTH + 0.008), lerp(0.813, 0.913, rise)
    rear = BODIES[style]["rear"]
    width = rear.x + 0.009
    if style == SEDAN:
        width = lerp(0.784, 0.764, clamp01(inv_lerp(rear.z, rear_bumper(style), z)))
    return min(width, w - 0.041), h - 0.021


def roof_at(z, style):
    front, back = BODIES[style]["roof"]
    return front.lerp(back, inv_lerp(front.z, back.z, z))


def rear_door_top(style):
    if style != SEDAN:
        return roof_at(0.831, style)
    back = BODIES[style]["roof"][1]
    rear = BODIES[style]["rear"]
    return back.lerp(rear, 0.25)


def arch_flare(z):
    """How far the fender bulges out over a wheel at this z."""
    best = 0.0
    for axle in WHEEL_AXLES:
        best = max(best, smoothstep(ARCH_RADIUS + 0.16, ARCH_RADIUS - 0.05, abs(z - axle)))
    return best


# --- Building helpers ---------------------------------------------------------------

def side_profile(z, style, low, flare=True):
    """The body side from the bottom edge up to the top of the beltline, for
    the +X side: a rolled sill (or a lip turned in round a wheel arch), a gently
    curved side, the beltline crease, and the shoulder rolling in to the top."""
    w, h = station(z, style)
    f = arch_flare(z) * 0.014 if flare else 0.0
    crease = h - 0.055
    pts = []
    if low > SILL + 0.01:
        pts.append((w - 0.075, low + 0.006))      # the arch lip, turned in
        pts.append((w - 0.058, low + 0.002))
        pts.append((w - 0.04 + f, low))
    else:
        pts.append((w - 0.085, low - 0.012))      # rolled under the sill
        pts.append((w - 0.055, low - 0.004))
        pts.append((w - 0.04, low + 0.012))
    span = crease - low
    pts.append((w - 0.03 + f * 0.8, low + span * 0.2))
    pts.append((w - 0.018 + f, low + span * 0.45))
    pts.append((w - 0.009 + f * 0.7, low + span * 0.75))
    pts.append((w - 0.002, crease - 0.012))
    pts.append((w, crease))                       # beltline crease
    pts.append((w - 0.006, crease + 0.02))
    pts.append((w - 0.016, h - 0.014))
    pts.append((w - 0.031, h))
    return pts


def loft(k, mat, rows, close=False):
    """Quads between rows of points (all rows the same length)."""
    bm = k.bm(mat)
    verts = [[bm.verts.new(Vector(p)) for p in row] for row in rows]
    for a, b in zip(verts, verts[1:]):
        n = len(a)
        for i in range(n if close else n - 1):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    return verts


def cap(k, mat, ring):
    bm = k.bm(mat)
    centre = sum((Vector(p) for p in ring), Vector()) / len(ring)
    c = bm.verts.new(centre)
    vs = [bm.verts.new(Vector(p)) for p in ring]
    for i in range(len(vs)):
        bm.faces.new((c, vs[i], vs[(i + 1) % len(vs)]))


def rounded_section(z, crown, shoulder, bottom, top, bulge=0.0, radius=None):
    """A closed rounded section across X (like compact_car_model's _profile,
    with a crowned top and real corner radii), clockwise from the top centre."""
    r = radius if radius is not None else min(0.03, (top - bottom) * 0.35)
    r = min(r, (top - bottom) * 0.45)
    half = []
    for i in range(6):
        x = crown * i / 5
        half.append((x, top + bulge * (1 - (x / max(crown, 1e-4)) ** 2)))
    for j in range(1, 4):
        a = j / 4 * pi / 2
        half.append((crown + (shoulder - crown) * sin(a), top - r * (1 - cos(a))))
    half.append((shoulder, top - r))
    half.append((shoulder, bottom + r))
    for j in range(1, 4):
        a = j / 4 * pi / 2
        half.append((shoulder - r * (1 - cos(a)), bottom + r * (1 - sin(a))))
    half.append((shoulder - r, bottom))
    half.append((0.0, bottom))
    ring = [V(x, y, z) for x, y in half]
    ring += [V(-x, y, z) for x, y in reversed(half[1:-1])]
    return ring


def skin_loft(k, mat, sections, steps=8, bulge=0.0, radius=None):
    """compact_car_model's _skin, smooth: sections [z, crown, shoulder,
    bottom, top] eased into many rows, rounded, capped."""
    rows = []
    for i in range(len(sections) - 1):
        a, b = sections[i], sections[i + 1]
        for s in range(steps):
            t = s / steps
            e = t * t * (3 - 2 * t) if len(sections) > 2 else t
            row = [lerp(a[j], b[j], e if j > 0 else t) for j in range(5)]
            rows.append(rounded_section(row[0], row[1], row[2], row[3], row[4], bulge, radius))
    last = sections[-1]
    rows.append(rounded_section(last[0], last[1], last[2], last[3], last[4], bulge, radius))
    loft(k, mat, rows, close=True)
    cap(k, mat, list(reversed(rows[0])))
    cap(k, mat, rows[-1])


def tube(k, mat, a, b, width, depth=None, sides=8):
    """A rounded tube from a to b (a pillar, a rail)."""
    a, b = Vector(a), Vector(b)
    axis = b - a
    if axis.length < 1e-4:
        return
    z = axis.normalized()
    x = Vector((0, 1, 0)).cross(z)
    if x.length < 1e-3:
        x = Vector((1, 0, 0)).cross(z)
    x.normalize()
    y = z.cross(x)
    d = depth or width
    rings = []
    steps = max(2, int(axis.length / 0.05))
    for s in range(steps + 1):
        c = a + axis * (s / steps)
        rings.append([c + x * cos(t * 2 * pi / sides) * width / 2 + y * sin(t * 2 * pi / sides) * d / 2 for t in range(sides)])
    loft(k, mat, rings, close=True)
    cap(k, mat, list(reversed(rings[0])))
    cap(k, mat, rings[-1])


FILE = ["panel"]


def finish(k, name, outward_from=None):
    """Join, orient faces outward from a point (for open panels), smooth by
    angle, export."""
    mesh = bpy.data.meshes.new(name)
    merged = bmesh.new()
    for i, (mat, bm) in enumerate(k.parts.items()):
        temp = bpy.data.meshes.new("t")
        bm.to_mesh(temp)
        merged.from_mesh(temp)
        bpy.data.meshes.remove(temp)
    bmesh.ops.remove_doubles(merged, verts=merged.verts, dist=0.0004)
    merged.normal_update()
    if outward_from is not None:
        ref = Vector(outward_from)
        for face in merged.faces:
            if face.normal.dot(face.calc_center_median() - ref) < 0:
                face.normal_flip()
    else:
        bmesh.ops.recalc_face_normals(merged, faces=merged.faces)
    bmesh.ops.transform(merged, matrix=TO_BLENDER, verts=merged.verts)
    merged.to_mesh(mesh)
    merged.free()
    mesh.materials.append(material("Paint"))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=radians(38))
    except Exception:
        for poly in mesh.polygons:
            poly.use_smooth = True
    obj.name = FILE[0]
    desert_kit.export([obj], FILE[0])
    return obj


def z_samples(a, b, step=0.03, extra=()):
    zs = {a, b}
    n = max(1, int(abs(b - a) / step))
    for i in range(n + 1):
        zs.add(lerp(a, b, i / n))
    for e in extra:
        if a < e < b:
            zs.add(e)
    return sorted(zs)


# --- Panels ---------------------------------------------------------------------

def chassis(style):
    """Fenders, rear quarters, nose and tail faces and the header over the
    grille, round the hood and boot openings (the doors cover the middle)."""
    k = Kit(900 + style)
    rows_spec = BODIES[style]["sections"]
    nose, tail = rows_spec[0][0], rows_spec[-1][0]
    arch_edges = []
    for axle in WHEEL_AXLES:
        for i in range(41):
            arch_edges.append(axle - cos(pi * i / 40) * ARCH_RADIUS)
    for side in (-1, 1):
        for a, b in ((nose, -0.902), (0.979, tail)):
            rows = []
            for z in z_samples(a, b, 0.03, arch_edges + [HOOD_FRONT - 0.008, HOOD_BACK + 0.007]):
                prof = side_profile(z, style, arch_bottom(z))
                ix, iy = opening_edge(z, style)
                w, h = station(z, style)
                # Over the top to the edge of the hood or boot opening.
                top = [(lerp(w - 0.031, ix, 0.45), h + (iy - h) * 0.5 + 0.004), (ix, iy)]
                row = [V(side * x, y, z) for x, y in prof + top]
                rows.append(row)
            loft(k, "Paint", rows)
    # Nose and tail faces, between the two sides' profiles.
    for z, sign in ((nose, -1), (tail, 1)):
        w, h = station(z, style)
        ix, iy = opening_edge(z, style)
        prof = side_profile(z, style, SILL, flare=False)
        pts = [(x, y) for x, y in prof] + [(ix, iy)]
        rows = []
        for t in range(9):
            u = t / 8
            rows.append([V(lerp(-x, x, u), y + 0.012 * sin(pi * u) * (y > SILL + 0.05), z + sign * 0.006 * sin(pi * u)) for x, y in pts])
        loft(k, "Paint", rows)
    # The header between the nose and the front of the hood opening.
    hx, hy = opening_edge(nose, style)
    fx, fy = opening_edge(HOOD_FRONT - 0.008, style)
    rows = []
    for t in range(9):
        u = t / 8
        rows.append([V(lerp(-hx, hx, u), hy, nose), V(lerp(-fx, fx, u), fy, HOOD_FRONT - 0.008)])
    loft(k, "Paint", rows)
    return finish(k, "Chassis", V(0, 0.55, 0))


def cabin(style):
    """The roof, crowned, with drip rails; the pillars and rails that used to
    be painted boxes (FrontPillar, CenterPillar, RoofGutter, RearPillar,
    RearDoorJamb, QuarterBelt)."""
    k = Kit(910 + style)
    front, back = BODIES[style]["roof"]
    rear = BODIES[style]["rear"]
    skin_loft(k, "Paint", [[front.z, front.x - 0.025, front.x, front.y - 0.012, front.y + 0.023],
        [front.z + 0.14, front.x - 0.028, front.x + 0.004, front.y, front.y + 0.052],
        [back.z - 0.11, back.x - 0.028, back.x + 0.004, back.y + 0.005, back.y + 0.045],
        [back.z, back.x - 0.025, back.x, back.y - 0.013, back.y + 0.022]], steps=10, bulge=0.028, radius=0.022)
    for side in (-1, 1):
        def s(p):
            return V(side * p.x, p.y, p.z)
        roof_c = roof_at(0.045, style)
        tube(k, "Paint", s(WINDSHIELD_BASE), s(front), 0.05, 0.04)
        tube(k, "Paint", s(V(0.828, 0.938, 0.045)), s(roof_c), 0.06, 0.045)
        # Drip rail along the roof edge.
        tube(k, "Paint", s(front + V(0.012, 0.02, 0.0)), s(back + V(0.012, 0.02, 0.0)), 0.018, 0.026)
        tube(k, "Paint", s(back), s(rear), 0.07, 0.05)
        quarter_front = V(0.839, 0.938, 0.978)
        tube(k, "Paint", s(V(0.865, 0.915, 0.976)), s(quarter_front), 0.045, 0.04)
        if style != SEDAN:
            quarter_back = rear - V(0.005, -0.015, 0.038)
            tube(k, "Paint", s(quarter_front), s(quarter_back), 0.04, 0.035)
    return finish(k, "Cabin")


def door(style, title):
    side, front = DOORS[title]
    origin = V(side * 0.82, 0.69, -0.92 if front else 0.055)
    start = -0.892 if front else 0.055
    end = 0.035 if front else 0.969
    k = Kit(920 + style)
    rows = []
    zs = z_samples(start + 0.004, end - 0.004, 0.03)
    for i, z in enumerate(zs):
        prof = side_profile(z, style, SILL + 0.007, flare=False)
        w, h = station(z, style)
        # The window ledge, turned in to the belt line.
        prof = prof + [(0.836 + 0.02, h - 0.002), (0.836, h - 0.004)]
        # Ends turn in so the door has a rounded edge and a visible gap.
        inset = 0.012 if i in (0, len(zs) - 1) else (0.004 if i in (1, len(zs) - 2) else 0.0)
        rows.append([V(side * (x - inset), y, z) - origin for x, y in prof])
    loft(k, "Paint", rows)
    # The window frame round the glass, on the door.
    a = station(start, style)
    b = station(end, style)
    belt_a = V(0.836, a[1] - 0.004, start)
    belt_b = V(0.836, b[1] - 0.004, end)
    top_front = BODIES[style]["roof"][0] if front else roof_at(0.082, style)
    top_back = roof_at(0.011, style) if front else rear_door_top(style)
    top_front = top_front + V(0.009, -0.044, 0.014)
    top_back = top_back + V(0.009, -0.044, -0.015)
    bottom_front = belt_a + V(0, 0.006, 0.020)
    bottom_back = belt_b + V(0, 0.006, -0.021)

    def s(p):
        return V(side * p.x, p.y, p.z) - origin
    tube(k, "Paint", s(bottom_back), s(top_back), 0.028, 0.022)
    tube(k, "Paint", s(top_back), s(top_front), 0.024, 0.02)
    tube(k, "Paint", s(top_front), s(bottom_front), 0.026, 0.022)
    return finish(k, "Door", V(side * 0.4, 0.55, (start + end) / 2) - origin)


def hood():
    k = Kit(930)
    skin_loft(k, "Paint", [[-1.19, 0.707, 0.739, -0.124, -0.092], [-0.69, 0.709, 0.739, -0.076, -0.041],
        [-0.026, 0.709, 0.739, -0.033, 0.007]], steps=14, bulge=0.016, radius=0.02)
    # A raised centre swage, just a few millimetres.
    return finish(k, "Hood")


def trunk(style):
    rear = BODIES[style]["rear"]
    hinge_z = rear.z + 0.01
    length = rear_bumper(style) - hinge_z
    k = Kit(940 + style)
    skin_loft(k, "Paint", [[0.0, 0.722, 0.775, -0.038, -0.005], [length - 0.21, 0.719, 0.767, -0.06, -0.022],
        [length - 0.018, 0.702, 0.752, -0.084, -0.058]], steps=10, bulge=0.01, radius=0.018)
    return finish(k, "Trunk")


def tailgate(style):
    """The lift-gate's painted lower panel and its frame up the glass, in
    the gate's space (TrunkTargetHinge/Trunk)."""
    back = BODIES[style]["roof"][1]
    rear = BODIES[style]["rear"]
    hinge = V(0, back.y, back.z + 0.012)
    top = back - hinge + V(-0.016, -0.021, 0.018)
    bottom = rear - hinge + V(-0.018, 0.004, 0.025)
    belt = top.lerp(bottom, 0.69 if style == HATCHBACK else 0.74)
    k = Kit(950 + style)
    rows = []
    for i in range(9):
        t = i / 8
        p = belt.lerp(bottom, t)
        bow = 0.012 * sin(pi * t)
        row = []
        for j in range(17):
            u = j / 16
            x = lerp(-p.x, p.x, u)
            edge = abs(2 * u - 1)
            roll = (edge ** 6) * 0.03
            row.append(V(x * (1 - 0.02 * edge ** 4), p.y - roll * 0.3, p.z + bow + 0.004 * (1 - edge ** 2) - roll))
        rows.append(row)
    loft(k, "Paint", rows)
    # A return along the bottom edge and a lip under the glass.
    loft(k, "Paint", [[V(lerp(-bottom.x, bottom.x, j / 16), bottom.y, bottom.z) for j in range(17)],
        [V(lerp(-bottom.x, bottom.x, j / 16) * 0.98, bottom.y + 0.01, bottom.z - 0.03) for j in range(17)]])
    for side in (-1, 1):
        tube(k, "Paint", V(side * top.x, top.y, top.z), V(side * belt.x, belt.y, belt.z), 0.042, 0.036)
    tube(k, "Paint", V(-top.x, top.y, top.z), V(top.x, top.y, top.z), 0.04, 0.03)
    return finish(k, "Tailgate", V(0, belt.y - 0.3, belt.z - 0.6))


def bumper(style, front):
    rows = BODIES[style]["sections"]
    bumper_top = [0.475, 0.49, 0.54][style]
    k = Kit(960 + style)
    if front:
        w, z = rows[0][1], rows[0][0]
        sections = [[z - 0.078, w - 0.06, w - 0.005, 0.285, bumper_top], [z - 0.015, w - 0.015, w + 0.035, 0.25, bumper_top],
            [z + 0.12, w, w + 0.049, 0.25, bumper_top - 0.012]]
    else:
        w, z = rows[-1][1], rows[-1][0]
        sections = [[z - 0.11, w - 0.01, w + 0.041, 0.254, 0.47], [z + 0.025, w - 0.014, w + 0.024, 0.26, 0.47],
            [z + 0.078, w - 0.053, w, 0.29, 0.46]]
    skin_loft(k, "Paint", sections, steps=6, bulge=0.0, radius=0.035)
    return finish(k, "Bumper")


def build(file, fn, *args):
    reset()
    FILE[0] = file
    return fn(*args)


def main():
    for style in range(3):
        build("body_%d_chassis" % style, chassis, style)
        build("body_%d_cabin" % style, cabin, style)
        for title in DOORS:
            build("body_%d_door_%s" % (style, title[:2]), door, style, title)
        if style == SEDAN:
            build("body_%d_trunk" % style, trunk, style)
        else:
            build("body_%d_tailgate" % style, tailgate, style)
        build("body_%d_bumper_front" % style, bumper, style, True)
        build("body_%d_bumper_rear" % style, bumper, style, False)
    build("body_hood", hood)


main()
