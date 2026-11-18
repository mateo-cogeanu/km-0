"""Rebuild the drowned town of Marrow for the Salvage Run: its houses, the
corner shop and the street furniture, as separate .glb files in
assets/salvage/.

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_marrow_town.py

Everything is built from real parts, board by board: clapboard siding,
framed windows (some panes broken out), panelled doors, porches with railings
and steps, shingled roofs with fascia, gutters and downpipes, brick
chimneys. Materials are named for what they are; the game swaps in its own
shaders (scripts/salvage_town.gd) that add the flood: the tide line, silt,
grime and peeling paint.

Blender is Z-up; each building faces -Y (Godot +Z) with its origin at the
middle of its footprint at ground level.
"""

from math import atan2, cos, pi, radians, sin
from pathlib import Path
from random import Random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/salvage"
OUT.mkdir(parents=True, exist_ok=True)

COLORS = {
    "Siding": (0.55, 0.55, 0.5), "Trim": (0.82, 0.8, 0.74), "Shingles": (0.16, 0.15, 0.15),
    "Glass": (0.05, 0.06, 0.06), "Dark interior": (0.01, 0.01, 0.01), "Door": (0.3, 0.12, 0.1),
    "Brick": (0.45, 0.22, 0.16), "Wood": (0.42, 0.33, 0.24), "Metal": (0.35, 0.35, 0.36),
    "Concrete": (0.5, 0.49, 0.46), "Rust": (0.36, 0.18, 0.1), "Sign": (0.8, 0.78, 0.7),
    "Bark": (0.18, 0.15, 0.12), "Rubber": (0.04, 0.04, 0.04), "Canvas": (0.3, 0.32, 0.22),
    "Rock": (0.36, 0.34, 0.31), "Red paint": (0.55, 0.08, 0.06), "Lamp": (1.0, 0.9, 0.7),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    found = bpy.data.materials.get(name)
    if found:
        return found
    mat = bpy.data.materials.new(name)
    color = COLORS.get(name, (0.5, 0.5, 0.5))
    mat.diffuse_color = (*color, 1.0)
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = 0.8
    return mat


class Kit:
    """Collects geometry per material, then becomes one object."""

    def __init__(self, seed):
        self.parts = {}
        self.rng = Random(seed)

    def bm(self, mat):
        if mat not in self.parts:
            self.parts[mat] = bmesh.new()
        return self.parts[mat]

    def box(self, mat, center, size, rot=(0, 0, 0)):
        matrix = Matrix.Translation(center) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((*size, 1.0))
        bmesh.ops.create_cube(self.bm(mat), size=1.0, matrix=matrix)

    def cyl(self, mat, a, b, radius, sides=10, radius2=None):
        a, b = Vector(a), Vector(b)
        axis = b - a
        rot = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm(mat), cap_ends=True, segments=sides, radius1=radius,
            radius2=radius if radius2 is None else radius2, depth=axis.length,
            matrix=Matrix.Translation((a + b) * 0.5) @ rot)

    def tri(self, mat, points):
        bm = self.bm(mat)
        verts = [bm.verts.new(p) for p in points]
        bm.faces.new(verts)

    def quad(self, mat, points):
        bm = self.bm(mat)
        verts = [bm.verts.new(p) for p in points]
        bm.faces.new(verts)

    def finish(self, name):
        mesh = bpy.data.meshes.new(name)
        merged = bmesh.new()
        index_of = {}
        for i, (mat, bm) in enumerate(self.parts.items()):
            for face in bm.faces:
                face.material_index = i
            bm.normal_update()
            temp = bpy.data.meshes.new("t")
            bm.to_mesh(temp)
            merged.from_mesh(temp)
            bpy.data.meshes.remove(temp)
            index_of[mat] = i
        bmesh.ops.recalc_face_normals(merged, faces=merged.faces)
        merged.to_mesh(mesh)
        merged.free()
        for mat in self.parts:
            mesh.materials.append(material(mat))
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        for poly in mesh.polygons:
            poly.use_smooth = False
        return obj


def export(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + ".glb")), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True)
    print("exported", name)


# --- Building parts ----------------------------------------------------------

def siding(k, x0, x1, z0, z1, y, facing, board=0.2, skip=()):
    """Overlapping horizontal boards along a wall, leaving holes for openings.
    facing: -1 for a wall whose outside faces -Y, +1 for +Y. Walls along X."""
    rows = int((z1 - z0) / board)
    for r in range(rows):
        zb = z0 + r * board
        spans = [(x0, x1)]
        for (ox0, ox1, oz0, oz1) in skip:
            if zb + board > oz0 and zb < oz1:
                spans = [s for span in spans for s in ((span[0], min(span[1], ox0)), (max(span[0], ox1), span[1])) if s[1] - s[0] > 0.02]
        for a, b in spans:
            # Each board leans out at the bottom so it overlaps the one below.
            k.box("Siding", Vector(((a + b) / 2, y + facing * 0.015, zb + board / 2)), (b - a, 0.025, board + 0.02),
                (radians(-4 * facing), 0, 0))


def siding_side(k, y0, y1, z0, z1, x, facing, board=0.2, skip=()):
    """The same along a wall that runs along Y (outside facing ±X)."""
    rows = int((z1 - z0) / board)
    for r in range(rows):
        zb = z0 + r * board
        spans = [(y0, y1)]
        for (oy0, oy1, oz0, oz1) in skip:
            if zb + board > oz0 and zb < oz1:
                spans = [s for span in spans for s in ((span[0], min(span[1], oy0)), (max(span[0], oy1), span[1])) if s[1] - s[0] > 0.02]
        for a, b in spans:
            k.box("Siding", Vector((x + facing * 0.015, (a + b) / 2, zb + board / 2)), (0.025, b - a, board + 0.02),
                (0, radians(4 * facing), 0))


def window(k, center, width, height, facing_axis, facing, broken=0.0, shutters=True):
    """A framed sash window: frame, sill, mullions, glass (some panes out)."""
    x, y, z = center
    t = 0.09

    def at(u, v, w):
        # u: across the wall, v: out from it, w: up.
        if facing_axis == "y":
            return Vector((x + u, y + facing * v, z + w))
        return Vector((x + facing * v, y + u, z + w))

    def size(su, sv, sw):
        return (su, sv, sw) if facing_axis == "y" else (sv, su, sw)

    k.box("Dark interior", at(0, -0.08, 0), size(width, 0.04, height))
    for su, sw, u, w in ((width + 2 * t, t, 0, height / 2 + t / 2), (width + 2 * t, t, 0, -height / 2 - t / 2),
                         (t, height, -width / 2 - t / 2, 0), (t, height, width / 2 + t / 2, 0)):
        k.box("Trim", at(u, 0.03, w), size(su, 0.08, sw))
    k.box("Trim", at(0, 0.08, -height / 2 - t - 0.03), size(width + 0.36, 0.16, 0.05))
    k.box("Trim", at(0, 0.04, height / 2 + t + 0.06), size(width + 0.3, 0.1, 0.07))
    k.box("Trim", at(0, 0.01, 0), size(width, 0.04, 0.05))
    k.box("Trim", at(0, 0.01, 0), size(0.04, 0.04, height))
    for pu in (-1, 1):
        for pw in (-1, 1):
            cu, cw = pu * width / 4, pw * height / 4
            if k.rng.random() < broken:
                # Broken: a jagged shard left in one corner.
                corner = at(cu - width / 4 * 0.95, -0.02, cw - height / 4 * 0.95)
                k.tri("Glass", [corner, corner + (at(width * 0.3, 0, 0) - at(0, 0, 0)) * k.rng.uniform(0.4, 1.0),
                    corner + (at(0, 0, height * 0.25) - at(0, 0, 0)) * k.rng.uniform(0.4, 1.0)])
            else:
                k.box("Glass", at(cu, -0.02, cw), size(width / 2 - 0.03, 0.01, height / 2 - 0.03))
    if shutters:
        for side in (-1, 1):
            hang = k.rng.random() < 0.25
            u = side * (width / 2 + t + 0.25)
            if hang:
                # Hanging from one hinge, swung down at an angle.
                k.box("Trim", at(u + side * 0.1, 0.06, -0.15), size(0.45, 0.04, height + 0.1),
                    (0, radians(side * 25), 0) if facing_axis == "y" else (radians(side * 25), 0, 0))
            else:
                k.box("Trim", at(u, 0.04, 0), size(0.45, 0.04, height + 0.15))
                for s in range(6):
                    k.box("Trim", at(u, 0.065, -height / 2 + 0.12 + s * (height - 0.1) / 6), size(0.4, 0.015, 0.05))


def door(k, center, facing):
    x, y, z = center
    k.box("Dark interior", Vector((x, y - facing * 0.06, z + 1.05)), (1.0, 0.04, 2.1))
    k.box("Door", Vector((x + 0.35, y - facing * 0.3, z + 1.03)), (0.92, 0.05, 2.06), (0, 0, radians(-35)))
    for px, pz in ((-0.2, 0.6), (0.2, 0.6), (-0.2, 1.45), (0.2, 1.45)):
        k.box("Door", Vector((x + 0.35 + px * 0.82, y - facing * (0.3 - 0.03) + px * 0.57, z + pz)), (0.3, 0.02, 0.6 if pz < 1 else 0.5), (0, 0, radians(-35)))
    for su, sw, u, w in ((1.24, 0.12, 0, 2.16), (0.12, 2.16, -0.56, 1.08), (0.12, 2.16, 0.56, 1.08)):
        k.box("Trim", Vector((x + u, y + facing * 0.04, z + w)), (su, 0.1, sw))


def gable_roof(k, w, d, eave, pitch, overhang=0.4):
    """Two shingled slopes over a w x d footprint (ridge along Y), with
    fascia boards, a ridge cap and gutters with a downpipe."""
    rise = (w / 2 + overhang) * pitch
    for side in (-1, 1):
        slope = Vector((-side * (w / 2 + overhang), 0, rise)).normalized()
        length = (Vector((w / 2 + overhang, 0, rise))).length
        rows = int(length / 0.18)
        angle = atan2(rise, w / 2 + overhang)
        k.box("Wood", Vector((side * (w / 4 + overhang / 2), 0, eave + rise / 2 - 0.05)), (w / 2 + overhang + 0.05, d + 2 * overhang, 0.04),
            (0, side * angle, 0))
        for r in range(rows):
            t = (r + 0.5) / rows
            base = Vector((side * (w / 2 + overhang), 0, eave)) + slope * (t * length)
            # A course of shingles: strips about 1.4 m long, staggered row
            # to row, each a little askew; now and then one is missing.
            y = -d / 2 - overhang - (0.7 if r % 2 else 0.0)
            while y < d / 2 + overhang:
                a = max(y, -d / 2 - overhang)
                b = min(y + 1.4, d / 2 + overhang)
                if b - a > 0.2 and k.rng.random() > 0.04:
                    tilt = k.rng.uniform(-0.02, 0.02)
                    k.box("Shingles", base + Vector((0, (a + b) / 2, 0.035)), (0.2 / max(abs(cos(angle)), 0.3) * cos(angle) + 0.03, b - a - 0.01, 0.02),
                        (tilt, side * angle + radians(-side * 3), 0))
                y += 1.4
        # Fascia along the eave, and the gutter under it.
        k.box("Trim", Vector((side * (w / 2 + overhang), 0, eave - 0.08)), (0.04, d + 2 * overhang, 0.2))
        k.cyl("Metal", (side * (w / 2 + overhang + 0.08), -d / 2 - overhang, eave - 0.14), (side * (w / 2 + overhang + 0.08), d / 2 + overhang, eave - 0.16), 0.06, 8)
        if side == 1:
            k.cyl("Metal", (w / 2 + overhang + 0.08, -d / 2 - overhang + 0.1, eave - 0.16), (w / 2 + 0.12, -d / 2 - 0.1, 0.2), 0.04, 8)
    k.box("Shingles", Vector((0, 0, eave + rise + 0.03)), (0.3, d + 2 * overhang, 0.06))
    # Gable ends: siding up into the triangle, and a vent.
    for end in (-1, 1):
        y = end * d / 2
        rows = int(rise / 0.2)
        for r in range(rows):
            zb = eave + r * 0.2
            half = (w / 2) * (1.0 - (r * 0.2) / (rise * w / 2 / (w / 2 + overhang)))
            if half > 0.1:
                k.box("Siding", Vector((0, y + end * 0.015, zb + 0.1)), (2 * half, 0.025, 0.22), (radians(4 * end), 0, 0))
        k.box("Trim", Vector((0, y + end * 0.05, eave + rise * 0.55)), (0.5, 0.05, 0.35))
        k.box("Dark interior", Vector((0, y + end * 0.08, eave + rise * 0.55)), (0.4, 0.02, 0.26))
        for side in (-1, 1):
            k.box("Trim", Vector((side * (w / 4 + overhang / 2), y + end * (overhang + 0.02), eave + rise / 2)),
                ((w / 2 + overhang) * 1.15, 0.05, 0.18), (0, side * atan2(rise, w / 2 + overhang), 0))
    return rise


def chimney(k, x, y, z0, z1):
    for r in range(int((z1 - z0) / 0.075)):
        z = z0 + r * 0.075 + 0.0375
        offset = 0.11 if r % 2 else 0.0
        for side, (cx, cy, sx, sy) in enumerate(((x, y - 0.32, 0.64, 0.05), (x, y + 0.32, 0.64, 0.05), (x - 0.32, y, 0.05, 0.64), (x + 0.32, y, 0.05, 0.64))):
            k.box("Brick", Vector((cx, cy, z)), (sx, sy, 0.068))
        k.box("Brick", Vector((x, y, z)), (0.62, 0.62, 0.075))
    k.box("Concrete", Vector((x, y, z1 + 0.04)), (0.78, 0.78, 0.08))
    for dx in (-0.12, 0.12):
        k.cyl("Rust", (x + dx, y, z1 + 0.08), (x + dx, y, z1 + 0.35), 0.07, 8)


def porch(k, w, depth, height, front_y, roof_z, posts=4):
    """Deck planks, joists, posts, railing with balusters, steps and a lean-to roof."""
    y0, y1 = front_y - depth, front_y
    for n in range(int(w / 0.14)):
        x = -w / 2 + 0.07 + n * 0.14
        sag = -0.02 * sin(pi * (x + w / 2) / w)
        k.box("Wood", Vector((x, (y0 + y1) / 2, height + sag)), (0.13, depth, 0.035))
    k.box("Wood", Vector((0, y0 + 0.05, height - 0.12)), (w, 0.1, 0.2))
    for x in (-w / 2, w / 2):
        k.box("Wood", Vector((x, (y0 + y1) / 2, height - 0.12)), (0.1, depth, 0.2))
    for i in range(posts):
        x = -w / 2 + 0.1 + i * (w - 0.2) / (posts - 1)
        k.box("Trim", Vector((x, y0 + 0.1, height / 2)), (0.16, 0.16, height))
        k.box("Trim", Vector((x, y0 + 0.1, (height + roof_z) / 2)), (0.13, 0.13, roof_z - height))
    # Railing, with a gap for the steps in the middle.
    for a, b in ((-w / 2 + 0.1, -0.7), (0.7, w / 2 - 0.1)):
        k.box("Trim", Vector(((a + b) / 2, y0 + 0.1, height + 0.85)), (b - a, 0.08, 0.06))
        k.box("Trim", Vector(((a + b) / 2, y0 + 0.1, height + 0.12)), (b - a, 0.06, 0.05))
        x = a + 0.12
        while x < b - 0.05:
            if k.rng.random() > 0.08:
                k.box("Trim", Vector((x, y0 + 0.1, height + 0.48)), (0.035, 0.035, 0.72))
            x += 0.14
    steps = max(2, int(height / 0.2))
    for s in range(steps):
        k.box("Wood", Vector((0, y0 - 0.15 - s * 0.28, height - 0.18 - s * height / steps)), (1.3, 0.3, 0.05))
        for x in (-0.62, 0.62):
            k.box("Wood", Vector((x, y0 - 0.15 - s * 0.28, (height - 0.18 - s * height / steps) / 2)), (0.06, 0.3, height - 0.18 - s * height / steps + 0.02))
    # Porch roof.
    k.box("Shingles", Vector((0, (y0 + y1) / 2 - 0.15, roof_z + 0.12)), (w + 0.4, depth + 0.5, 0.06), (radians(-8), 0, 0))
    k.box("Trim", Vector((0, y0 - 0.1, roof_z - 0.02)), (w + 0.3, 0.06, 0.22))


def house(seed, w, d, storeys, pitch, porch_depth, chimney_at, bay=False):
    k = Kit(seed)
    rng = k.rng
    base = 0.6
    storey = 2.7
    top = base + storeys * storey
    # Foundation, in concrete block.
    k.box("Concrete", Vector((0, 0, base / 2)), (w + 0.1, d + 0.1, base))
    # The inside: a dark box behind the walls, so windows never show daylight.
    k.box("Dark interior", Vector((0, 0, (base + top) / 2)), (w - 0.25, d - 0.25, top - base - 0.1))
    front, back = -d / 2, d / 2
    openings_front = []
    door_x = rng.choice([-w * 0.25, w * 0.22]) if storeys > 1 else -w * 0.28
    openings_front.append((door_x - 0.62, door_x + 0.62, base, base + 2.25))
    win_xs = [x for x in (-w * 0.32, -w * 0.05, w * 0.3) if abs(x - door_x) > 1.2]
    for s in range(storeys):
        z = base + s * storey + 1.45
        for x in (win_xs if s == 0 else (-w * 0.3, 0.0, w * 0.3)):
            if bay and s == 0 and x == win_xs[-1]:
                continue
            openings_front.append((x - 0.55, x + 0.55, z - 0.72, z + 0.72))
    siding(k, -w / 2, w / 2, base, top, front, -1, skip=openings_front)
    siding(k, -w / 2, w / 2, base, top, back, 1, skip=[(x - 0.55, x + 0.55, base + s * storey + 0.75, base + s * storey + 2.15)
        for s in range(storeys) for x in (-w * 0.25, w * 0.25)])
    for side in (-1, 1):
        siding_side(k, -d / 2, d / 2, base, top, side * w / 2, side, skip=[(y - 0.5, y + 0.5, base + s * storey + 0.75, base + s * storey + 2.15)
            for s in range(storeys) for y in (-d * 0.2, d * 0.2)])
        # Corner boards.
        for end in (-1, 1):
            k.box("Trim", Vector((side * (w / 2 + 0.02), end * (d / 2 + 0.02), (base + top) / 2)), (0.14, 0.14, top - base))
    k.box("Trim", Vector((0, front - 0.04, top - 0.05)), (w + 0.1, 0.06, 0.18))
    k.box("Trim", Vector((0, back + 0.04, top - 0.05)), (w + 0.1, 0.06, 0.18))
    for x0, x1, z0, z1 in openings_front[1:]:
        window(k, ((x0 + x1) / 2, front, (z0 + z1) / 2), 1.0, 1.3, "y", -1, broken=0.35)
    for s in range(storeys):
        for x in (-w * 0.25, w * 0.25):
            window(k, (x, back, base + s * storey + 1.45), 1.0, 1.3, "y", 1, broken=0.3)
        for side in (-1, 1):
            for y in (-d * 0.2, d * 0.2):
                window(k, (side * w / 2, y, base + s * storey + 1.45), 0.9, 1.3, "x", side, broken=0.3, shutters=False)
    door(k, (door_x, front, base), -1)
    if bay:
        # A bay window pushed out from the front.
        x = win_xs[-1]
        k.box("Siding", Vector((x, front - 0.45, base + 0.5)), (2.2, 0.9, 1.0))
        k.box("Shingles", Vector((x, front - 0.5, base + 2.45)), (2.5, 1.1, 0.08), (radians(-15), 0, 0))
        for i, (dx, ang) in enumerate(((-0.95, 0.6), (0, 0), (0.95, -0.6))):
            window(k, (x + dx, front - 0.9 + abs(dx) * 0.45, base + 1.65), 0.7, 1.1, "y", -1, broken=0.4, shutters=False)
    porch_height = 1.35
    if porch_depth > 0:
        porch(k, w * 0.86, porch_depth, porch_height, front, base + storey + (0.0 if storeys > 1 else -0.25))
    rise = gable_roof(k, w, d, top, pitch)
    if chimney_at is not None:
        chimney(k, chimney_at * w / 2, d * 0.15, top - 1.0, top + rise + 0.6)
    obj = k.finish("House")
    return obj


def house_far(seed, w, d, storeys, pitch, porch_depth, chimney_at, bay=False):
    """The same house for seeing from down the street: plain walls, two roof
    slabs, dark windows in frames, the porch as a deck and posts."""
    k = Kit(seed)
    base, storey = 0.6, 2.7
    top = base + storeys * storey
    k.box("Concrete", Vector((0, 0, base / 2)), (w + 0.1, d + 0.1, base))
    k.box("Siding", Vector((0, 0, (base + top) / 2)), (w, d, top - base))
    overhang = 0.4
    rise = (w / 2 + overhang) * pitch
    angle = atan2(rise, w / 2 + overhang)
    length = Vector((w / 2 + overhang, 0, rise)).length
    for side in (-1, 1):
        k.box("Shingles", Vector((side * (w / 4 + overhang / 2), 0, top + rise / 2)), (length, d + 2 * overhang, 0.08), (0, side * angle, 0))
        k.tri("Siding", [Vector((-w / 2, side * d / 2, top)), Vector((w / 2, side * d / 2, top)), Vector((0, side * d / 2, top + rise * w / 2 / (w / 2 + overhang)))][::side])
    for s in range(storeys):
        z = base + s * storey + 1.45
        for x in (-w * 0.3, 0.0, w * 0.3):
            k.box("Trim", Vector((x, -d / 2 - 0.03, z)), (1.2, 0.05, 1.5))
            k.box("Dark interior", Vector((x, -d / 2 - 0.06, z)), (1.0, 0.03, 1.3))
            k.box("Trim", Vector((x, d / 2 + 0.03, z)), (1.2, 0.05, 1.5))
            k.box("Dark interior", Vector((x, d / 2 + 0.06, z)), (1.0, 0.03, 1.3))
    if porch_depth > 0:
        k.box("Wood", Vector((0, -d / 2 - porch_depth / 2, 1.35)), (w * 0.86, porch_depth, 0.1))
        k.box("Shingles", Vector((0, -d / 2 - porch_depth / 2 - 0.15, base + storey + 0.12 - (0.0 if storeys > 1 else 0.25))), (w * 0.86 + 0.4, porch_depth + 0.5, 0.06))
        for i in range(4):
            x = -w * 0.43 + 0.1 + i * (w * 0.86 - 0.2) / 3
            k.box("Trim", Vector((x, -d / 2 - porch_depth + 0.1, (base + storey) / 2 + 0.3)), (0.15, 0.15, base + storey))
    if chimney_at is not None:
        k.box("Brick", Vector((chimney_at * w / 2, d * 0.15, top + rise / 2)), (0.64, 0.64, rise + 1.6))
    return k.finish("HouseFar")


def shop(seed):
    """A corner shop: brick, a flat roof behind a parapet, big display windows
    (broken), a sagging awning and a painted sign."""
    k = Kit(seed)
    w, d, h = 11.0, 10.0, 5.2
    for r in range(int(h / 0.075)):
        z = r * 0.075 + 0.0375
        for side in (-1, 1):
            k.box("Brick", Vector((side * w / 2, 0, z)), (0.12, d, 0.068))
        k.box("Brick", Vector((0, d / 2, z)), (w, 0.12, 0.068))
        if z > 3.2 or z < 0.6:
            k.box("Brick", Vector((0, -d / 2, z)), (w, 0.12, 0.068))
    for x in (-w / 2 + 0.4, -1.3, 1.3, w / 2 - 0.4):
        k.box("Brick", Vector((x, -d / 2, 1.9)), (0.8, 0.14, 2.6))
    k.box("Dark interior", Vector((0, 0, h / 2)), (w - 0.3, d - 0.3, h - 0.1))
    k.box("Concrete", Vector((0, 0, h + 0.05)), (w + 0.2, d + 0.2, 0.12))
    for side in (-1, 1):
        k.box("Brick", Vector((side * w / 2, 0, h + 0.45)), (0.25, d + 0.2, 0.8))
    k.box("Brick", Vector((0, -d / 2, h + 0.55)), (w + 0.25, 0.25, 1.0))
    k.box("Brick", Vector((0, d / 2, h + 0.45)), (w + 0.25, 0.25, 0.8))
    # Display windows either side of the door, mostly smashed.
    for cx in (-3.3, 3.3):
        for su, sw, u, w2 in ((3.8, 0.1, 0, 3.15), (3.8, 0.15, 0, 0.6), (0.1, 2.6, -1.9, 1.9), (0.1, 2.6, 1.9, 1.9), (0.06, 2.5, 0, 1.9)):
            k.box("Trim", Vector((cx + u, -d / 2 - 0.02, w2)), (su, 0.12, sw))
        for pane in (-0.95, 0.95):
            if k.rng.random() < 0.6:
                corner = Vector((cx + pane - 0.9, -d / 2 + 0.01, 0.7))
                k.tri("Glass", [corner, corner + Vector((k.rng.uniform(0.4, 1.6), 0, 0)), corner + Vector((0, 0, k.rng.uniform(0.5, 2.0)))])
                k.tri("Glass", [Vector((cx + pane + 0.9, -d / 2 + 0.01, 3.1)), Vector((cx + pane + 0.9 - k.rng.uniform(0.3, 1.2), -d / 2 + 0.01, 3.1)),
                    Vector((cx + pane + 0.9, -d / 2 + 0.01, 3.1 - k.rng.uniform(0.4, 1.4)))])
            else:
                k.box("Glass", Vector((cx + pane, -d / 2 + 0.01, 1.9)), (1.75, 0.012, 2.4))
    door(k, (0, -d / 2, 0.0), -1)
    # The awning: a striped canvas sheet on a frame, one end collapsed.
    for i in range(8):
        x = -w / 2 + 0.7 + i * (w - 1.4) / 8
        drop = 0.0 if x < 2.5 else (x - 2.5) * 0.35
        k.box("Canvas" if i % 2 else "Red paint", Vector((x + (w - 1.4) / 16, -d / 2 - 0.8, 3.5 - drop)), ((w - 1.4) / 8, 1.7, 0.03), (radians(18), 0, 0))
    for x in (-w / 2 + 0.6, w / 2 - 0.6):
        k.cyl("Metal", (x, -d / 2, 3.75), (x, -d / 2 - 1.6, 3.2 - (0.0 if x < 0 else 0.9)), 0.025, 6)
    # The sign board over the awning.
    k.box("Wood", Vector((0, -d / 2 - 0.1, 4.45)), (7.0, 0.08, 0.9))
    k.box("Sign", Vector((0, -d / 2 - 0.15, 4.45)), (6.8, 0.02, 0.75))
    # A fire escape ladder down the side.
    for z in range(10):
        k.cyl("Rust", (w / 2 + 0.1, -2.0, 0.4 + z * 0.45), (w / 2 + 0.1, -1.5, 0.4 + z * 0.45), 0.018, 6)
    for y in (-2.0, -1.5):
        k.cyl("Rust", (w / 2 + 0.1, y, 0.2), (w / 2 + 0.1, y, 4.8), 0.025, 6)
    return k.finish("Shop")


# --- Street furniture ------------------------------------------------------------

def street_lamp():
    k = Kit(10)
    k.cyl("Metal", (0, 0, 0), (0, 0, 0.5), 0.16, 12, 0.11)
    k.cyl("Metal", (0, 0, 0.5), (0, 0, 5.0), 0.075, 10, 0.05)
    for i in range(9):
        a = i / 8 * pi * 0.5
        a2 = (i + 1) / 8 * pi * 0.5
        k.cyl("Metal", (0.6 * (1 - cos(a)), 0, 5.0 + 0.6 * sin(a)), (0.6 * (1 - cos(a2)), 0, 5.0 + 0.6 * sin(a2)), 0.045, 8)
    k.cyl("Metal", (0.6, 0, 5.6), (1.25, 0, 5.62), 0.045, 8)
    k.cyl("Metal", (1.25, 0, 5.62), (1.25, 0, 5.4), 0.2, 12, 0.08)
    k.cyl("Glass", (1.25, 0, 5.4), (1.25, 0, 5.25), 0.14, 12, 0.1)
    return k.finish("Lamp")


def utility_pole():
    k = Kit(11)
    k.cyl("Wood", (0, 0, 0), (0, 0, 8.5), 0.14, 10, 0.11)
    k.box("Wood", Vector((0, 0, 7.9)), (2.2, 0.12, 0.12))
    for x in (-0.95, -0.55, 0.55, 0.95):
        k.cyl("Glass", (x, 0, 7.97), (x, 0, 8.12), 0.04, 8)
    k.cyl("Metal", (0.25, 0.25, 6.6), (0.25, 0.25, 7.4), 0.25, 12)
    k.cyl("Metal", (0, 0, 2.5), (0, 0, 2.6), 0.16, 10)
    for r in range(12):
        k.box("Metal", Vector((0, -0.15, 2.0 + r * 0.38)), (0.25, 0.03, 0.03))
    return k.finish("Pole")


def picket_fence(broken):
    k = Kit(12 + broken)
    for x in (-1.2, 0.0, 1.2):
        k.box("Wood", Vector((x, 0, 0.55)), (0.09, 0.09, 1.1))
    for z in (0.3, 0.8):
        if broken and z == 0.8:
            k.box("Wood", Vector((-0.55, 0, z - 0.25)), (1.3, 0.04, 0.08), (0, radians(22), 0))
            continue
        k.box("Wood", Vector((0, 0.06, z)), (2.4, 0.04, 0.08))
    for n in range(16):
        x = -1.14 + n * 0.152
        if broken and k.rng.random() < 0.4:
            if k.rng.random() < 0.5:
                k.box("Wood", Vector((x, 0.3 + k.rng.uniform(0, 0.4), 0.03)), (0.08, 1.0, 0.025), (0, 0, k.rng.uniform(-0.6, 0.6)))
            continue
        height = 1.0 - (0.35 if broken and k.rng.random() < 0.3 else 0.0)
        k.box("Wood", Vector((x, 0.09, height / 2)), (0.08, 0.02, height))
        k.tri("Wood", [Vector((x - 0.04, 0.1, height)), Vector((x + 0.04, 0.1, height)), Vector((x, 0.1, height + 0.07))])
    return k.finish("Fence")


def small_props():
    """Mailbox, hydrant, stop sign, town sign, bin, sandbags, rowboat, tyre,
    drum, dead tree and rocks: one object each."""
    out = {}
    k = Kit(20)
    k.box("Wood", Vector((0, 0, 0.55)), (0.09, 0.09, 1.1))
    k.box("Metal", Vector((0, 0, 1.2)), (0.24, 0.5, 0.24))
    k.cyl("Metal", (0, -0.25, 1.32), (0, 0.25, 1.32), 0.12, 12)
    k.box("Red paint", Vector((0.14, 0.15, 1.38)), (0.02, 0.05, 0.25), (radians(30), 0, 0))
    out["mailbox"] = k.finish("Mailbox")
    k = Kit(21)
    k.cyl("Red paint", (0, 0, 0), (0, 0, 0.12), 0.16, 12)
    k.cyl("Red paint", (0, 0, 0.12), (0, 0, 0.62), 0.11, 12)
    k.cyl("Red paint", (0, 0, 0.62), (0, 0, 0.78), 0.12, 12, 0.05)
    for a in (0, pi):
        k.cyl("Red paint", (0.0, 0, 0.45), (0.17 * cos(a), 0.17 * sin(a), 0.45), 0.05, 8)
    out["hydrant"] = k.finish("Hydrant")
    k = Kit(22)
    k.cyl("Metal", (0, 0, 0), (0, 0, 2.3), 0.03, 8)
    bm = k.bm("Red paint")
    ring = [bm.verts.new((0.32 * cos(pi / 8 + i * pi / 4), -0.04, 2.3 + 0.32 * sin(pi / 8 + i * pi / 4))) for i in range(8)]
    bm.faces.new(ring[::-1])
    k.box("Sign", Vector((0, -0.05, 2.3)), (0.4, 0.01, 0.1))
    out["stop_sign"] = k.finish("StopSign")
    k = Kit(23)
    for x in (-1.0, 1.0):
        k.box("Wood", Vector((x, 0, 0.9)), (0.12, 0.12, 1.8))
    k.box("Wood", Vector((0, -0.05, 1.5)), (2.5, 0.06, 1.0), (0, radians(-4), 0))
    k.box("Sign", Vector((0, -0.09, 1.5)), (2.35, 0.01, 0.86), (0, radians(-4), 0))
    out["town_sign"] = k.finish("TownSign")
    k = Kit(24)
    k.cyl("Metal", (0, 0, 0), (0, 0, 0.9), 0.28, 14, 0.32)
    k.cyl("Metal", (0.05, 0.3, 0.05), (0.05, 0.31, 0.6), 0.3, 14, 0.33)
    out["bin"] = k.finish("Bin")
    k = Kit(25)
    for r in range(3):
        for n in range(5 - r):
            k.box("Canvas", Vector((-0.9 + n * 0.45 + r * 0.22, 0, 0.1 + r * 0.17)), (0.42, 0.28, 0.17), (0, 0, k.rng.uniform(-0.1, 0.1)))
    out["sandbags"] = k.finish("Sandbags")
    k = Kit(26)
    for i in range(12):
        t = i / 11
        width = 0.62 * sin(pi * min(t * 1.1, 1.0)) + 0.1
        for side in (-1, 1):
            k.box("Wood", Vector((side * width / 2, -1.7 + t * 3.4, 0.25 + 0.1 * (t - 0.5) ** 2)), (0.03, 0.32, 0.5), (0, side * radians(18), 0))
        k.box("Wood", Vector((0, -1.7 + t * 3.4, 0.02)), (width, 0.32, 0.03))
    for y in (-0.5, 0.4):
        k.box("Wood", Vector((0, y, 0.35)), (0.9, 0.22, 0.04))
    out["rowboat"] = k.finish("Rowboat")
    k = Kit(27)
    bm = k.bm("Rubber")
    bmesh.ops.create_cone(bm, cap_ends=False, segments=20, radius1=0.33, radius2=0.33, depth=0.22)
    bmesh.ops.create_cone(bm, cap_ends=False, segments=20, radius1=0.2, radius2=0.2, depth=0.22)
    out["tyre"] = k.finish("Tyre")
    k = Kit(28)
    k.cyl("Rust", (0, 0, 0), (0, 0, 0.88), 0.29, 16)
    for z in (0.28, 0.6):
        k.cyl("Rust", (0, 0, z - 0.02), (0, 0, z + 0.02), 0.3, 16)
    out["drum"] = k.finish("Drum")
    out["tree"] = dead_tree()
    for n in range(3):
        out["rock_%d" % n] = rock(30 + n)
    return out


def dead_tree():
    """A drowned tree: grey bark, no leaves, branches splitting and splitting."""
    k = Kit(40)

    def branch(a, direction, length, radius, depth):
        b = a + direction * length
        k.cyl("Bark", a, b, radius, 7, radius * 0.72)
        if depth == 0 or radius < 0.012:
            return
        for n in range(2 if depth < 3 else 3):
            turn = Euler((k.rng.uniform(-0.7, 0.7), k.rng.uniform(-0.7, 0.7), k.rng.uniform(0, 2 * pi))).to_matrix()
            child = (turn @ direction).normalized()
            child.z = abs(child.z) * 0.8 + 0.2
            branch(b, child.normalized(), length * k.rng.uniform(0.55, 0.75), radius * 0.68, depth - 1)

    k.cyl("Bark", (0, 0, -0.3), (0, 0, 0.3), 0.3, 9, 0.22)
    branch(Vector((0, 0, 0.2)), Vector((0.08, 0.04, 1)).normalized(), 3.2, 0.22, 4)
    return k.finish("Tree")


def rock(seed):
    k = Kit(seed)
    bm = k.bm("Rock")
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    rng = Random(seed)
    for v in bm.verts:
        n = v.co.normalized()
        v.co = n * (0.75 + 0.35 * rng.random() * 0.4 + 0.25 * sin(n.x * 3 + seed) * cos(n.y * 2))
        v.co.z *= 0.55
    return k.finish("Rock")


def main():
    reset()
    builds = [
        ("house_a", lambda: house(1, 9.0, 9.0, 2, 0.75, 2.4, -0.55)),
        ("house_b", lambda: house(2, 10.0, 8.5, 1, 0.55, 2.2, 0.5, bay=True)),
        ("house_c", lambda: house(3, 8.0, 10.0, 2, 0.95, 0.0, 0.4)),
        ("house_a_far", lambda: house_far(1, 9.0, 9.0, 2, 0.75, 2.4, -0.55)),
        ("house_b_far", lambda: house_far(2, 10.0, 8.5, 1, 0.55, 2.2, 0.5, bay=True)),
        ("house_c_far", lambda: house_far(3, 8.0, 10.0, 2, 0.95, 0.0, 0.4)),
        ("shop", lambda: shop(4)),
        ("lamp", street_lamp),
        ("pole", utility_pole),
        ("fence", lambda: picket_fence(0)),
        ("fence_broken", lambda: picket_fence(1)),
    ]
    for name, build in builds:
        reset()
        obj = build()
        export([obj], name)
    reset()
    for name, obj in small_props().items():
        export([obj], name)


main()
