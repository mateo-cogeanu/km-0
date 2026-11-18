"""Shared parts for the desert road's Blender models (make_road_stations.py,
make_road_houses.py, make_roadside_props.py).

Everything is authored in Godot's coordinates (Y up, buildings facing +Z) so
the numbers match the game scripts that place doors, finds and colliders;
Kit.finish() turns the result into Blender's Z-up before export, and the glTF
exporter turns it back.

Materials are named for what they are; scripts/desert_models.gd swaps in the
weathering shader (assets/desert/weathered_surface.gdshader) by name.
"""

from math import atan2, cos, pi, radians, sin
from pathlib import Path
from random import Random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/desert"
OUT.mkdir(parents=True, exist_ok=True)

# Godot (x, y, z) -> Blender (x, -z, y).
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

COLORS = {
    "Corrugated": (0.55, 0.56, 0.55), "Roof": (0.3, 0.3, 0.29), "Paint": (0.6, 0.55, 0.48),
    "Block": (0.62, 0.6, 0.55), "Brick": (0.45, 0.24, 0.17), "Concrete": (0.55, 0.53, 0.48),
    "Steel": (0.33, 0.34, 0.34), "Rust": (0.38, 0.2, 0.11), "Wood": (0.45, 0.37, 0.28),
    "Boards": (0.6, 0.55, 0.47), "Trim": (0.78, 0.74, 0.65), "Glass": (0.05, 0.06, 0.06),
    "Dark interior": (0.01, 0.01, 0.01), "Rubber": (0.04, 0.04, 0.04), "Sign": (0.8, 0.76, 0.66),
    "Red paint": (0.55, 0.12, 0.08), "Shingles": (0.18, 0.17, 0.16), "Plaster": (0.55, 0.5, 0.44),
    "Floor": (0.33, 0.27, 0.21), "Fabric": (0.3, 0.27, 0.22), "Enamel": (0.72, 0.7, 0.64),
    "Yellow paint": (0.75, 0.58, 0.2), "Lamp": (0.9, 0.86, 0.75), "Stone": (0.34, 0.32, 0.29),
    "Bark": (0.25, 0.22, 0.18), "Scrub": (0.36, 0.34, 0.22), "Rock": (0.5, 0.42, 0.34),
    "Tin": (0.62, 0.62, 0.6), "Paper": (0.75, 0.7, 0.6), "Green paint": (0.18, 0.35, 0.24),
    "Cactus": (0.32, 0.43, 0.27), "Grass": (0.62, 0.58, 0.36), "Leaves": (0.36, 0.42, 0.26), "Needles": (0.22, 0.33, 0.25),
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
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    if shader:
        shader.inputs["Base Color"].default_value = (*color, 1.0)
        shader.inputs["Roughness"].default_value = 0.85
    return mat


def V(x, y, z):
    return Vector((x, y, z))


class Kit:
    """Collects geometry per material (in Godot space), then becomes one object."""

    def __init__(self, seed):
        self.parts = {}
        self.rng = Random(seed)

    def bm(self, mat):
        if mat not in self.parts:
            self.parts[mat] = bmesh.new()
        return self.parts[mat]

    def box(self, mat, center, size, rot=(0, 0, 0)):
        """size along x, y (up), z; rot is a Godot euler (x, y, z) in radians."""
        if min(size) <= 0.0005:
            return
        matrix = Matrix.Translation(Vector(center)) @ Euler(rot, "YXZ").to_matrix().to_4x4() @ Matrix.Diagonal((*size, 1.0))
        bmesh.ops.create_cube(self.bm(mat), size=1.0, matrix=matrix)

    def span(self, mat, a, b, thick, depth=None, up=None):
        """A beam from a to b with a square (or thick x depth) section."""
        a, b = Vector(a), Vector(b)
        axis = b - a
        length = axis.length
        if length < 1e-4:
            return
        if up is None:
            up = V(0, 1, 0) if abs(axis.normalized().y) < 0.95 else V(1, 0, 0)
        z = axis.normalized()
        x = up.cross(z).normalized()
        y = z.cross(x)
        basis = Matrix((x, y, z)).transposed().to_4x4()
        matrix = Matrix.Translation((a + b) * 0.5) @ basis @ Matrix.Diagonal((thick, depth or thick, length, 1.0))
        bmesh.ops.create_cube(self.bm(mat), size=1.0, matrix=matrix)

    def cyl(self, mat, a, b, radius, sides=10, radius2=None, caps=True):
        a, b = Vector(a), Vector(b)
        axis = b - a
        if axis.length < 1e-4:
            return
        rot = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm(mat), cap_ends=caps, segments=sides, radius1=radius,
            radius2=radius if radius2 is None else radius2, depth=axis.length,
            matrix=Matrix.Translation((a + b) * 0.5) @ rot)

    def poly(self, mat, points):
        bm = self.bm(mat)
        verts = [bm.verts.new(Vector(p)) for p in points]
        bm.faces.new(verts)

    def quad(self, mat, points):
        self.poly(mat, points)

    def ico(self, mat, center, radius, scale=(1, 1, 1), subdiv=2, jitter=0.0):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
        for v in bm.verts:
            n = v.co.normalized()
            r = 1.0 + jitter * (self.rng.random() - 0.5) * 2.0
            v.co = Vector((n.x * scale[0], n.y * scale[1], n.z * scale[2])) * r * radius + Vector(center)
        temp = bpy.data.meshes.new("t")
        bm.to_mesh(temp)
        bm.free()
        self.bm(mat).from_mesh(temp)
        bpy.data.meshes.remove(temp)

    def corrugated(self, mat, origin, along, up, length, height, pitch=0.076, depth=0.018, out=None):
        """A corrugated sheet: a trapezoid profile repeating along `along`,
        running the full `height` along `up`. The sheet is one surface; the
        game draws both sides."""
        origin, along, up = Vector(origin), Vector(along).normalized(), Vector(up).normalized()
        out = Vector(out).normalized() if out is not None else along.cross(up).normalized()
        bm = self.bm(mat)
        steps = max(1, int(length / pitch))
        pitch = length / steps
        profile = []
        for s in range(steps):
            u = s * pitch
            for frac, lift in ((0.0, 0.0), (0.3, 0.0), (0.45, 1.0), (0.85, 1.0)):
                profile.append((u + frac * pitch, lift))
        profile.append((length, 0.0))
        bottom = [bm.verts.new(origin + along * u + out * (lift * depth)) for u, lift in profile]
        top = [bm.verts.new(origin + along * u + out * (lift * depth) + up * height) for u, lift in profile]
        for i in range(len(profile) - 1):
            bm.faces.new((bottom[i], bottom[i + 1], top[i + 1], top[i]))

    def finish(self, name):
        mesh = bpy.data.meshes.new(name)
        merged = bmesh.new()
        for i, (mat, bm) in enumerate(self.parts.items()):
            for face in bm.faces:
                face.material_index = i
            temp = bpy.data.meshes.new("t")
            bm.to_mesh(temp)
            merged.from_mesh(temp)
            bpy.data.meshes.remove(temp)
        bmesh.ops.transform(merged, matrix=TO_BLENDER, verts=merged.verts)
        bmesh.ops.remove_doubles(merged, verts=merged.verts, dist=0.0001)
        merged.normal_update()
        merged.to_mesh(mesh)
        merged.free()
        for mat in self.parts:
            mesh.materials.append(material(mat))
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        for poly in mesh.polygons:
            poly.use_smooth = False
        return obj


def fix_normals(obj):
    """Outward faces for closed parts; open sheets keep their winding."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


def export(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + ".glb")), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True)
    print("exported", name, sum(len(o.data.polygons) for o in objs), "faces")


def build_all(builds):
    for name, build in builds:
        reset()
        obj = build()
        fix_normals(obj)
        export([obj], name)


# --- Shared building parts (Godot space) -------------------------------------

def framed_window(k, center, width, height, normal, boarded=0, broken=0.3, frame_mat="Trim", sill=True, depth=0.1, backing=True):
    """A window on a wall whose outside faces `normal` (+-X or +-Z): frame,
    sill, a sash cross, dark glass with panes out, or boards nailed over it.
    `center` is on the outside face of the wall."""
    n = Vector(normal).normalized()
    across = V(0, 1, 0).cross(n).normalized()
    c = Vector(center)

    def at(u, v, w):
        return c + across * u + n * v + V(0, w, 0)

    def size(su, sv, sw):
        return (abs(across.x) * su + abs(n.x) * sv, sw, abs(across.z) * su + abs(n.z) * sv)

    t = 0.07
    if backing:
        k.box("Dark interior", at(0, -depth, 0), size(width, 0.02, height))
    for su, sw, u, w in ((width + 2 * t, t, 0, height / 2 + t / 2), (width + 2 * t, t, 0, -height / 2 - t / 2),
                         (t, height, -width / 2 - t / 2, 0), (t, height, width / 2 + t / 2, 0)):
        k.box(frame_mat, at(u, 0.02, w), size(su, 0.06, sw))
    # The reveal: the wall's thickness round the opening.
    for su, sw, u, w in ((width, 0.02, 0, height / 2), (width, 0.02, 0, -height / 2), (0.02, height, -width / 2, 0), (0.02, height, width / 2, 0)):
        k.box(frame_mat, at(u, -depth / 2, w), size(su, depth, sw))
    if sill:
        k.box(frame_mat, at(0, 0.06, -height / 2 - t - 0.02), size(width + 0.26, 0.12, 0.045))
    k.box(frame_mat, at(0, -0.03, 0), size(width, 0.03, 0.04))
    k.box(frame_mat, at(0, -0.03, 0), size(0.04, 0.03, height))
    for pu in (-1, 1):
        for pw in (-1, 1):
            cu, cw = pu * width / 4, pw * height / 4
            if k.rng.random() < broken:
                corner = at(cu - pu * width / 4 * 0.95, -0.05, cw - pw * height / 4 * 0.95)
                k.poly("Glass", [corner, corner + across * (pu * -width * 0.3 * k.rng.uniform(0.3, 1.0)),
                    corner + V(0, -pw * height * 0.25 * k.rng.uniform(0.3, 1.0), 0)])
            else:
                k.box("Glass", at(cu, -0.05, cw), size(width / 2 - 0.03, 0.008, height / 2 - 0.03))
    for b in range(boarded):
        tilt = k.rng.uniform(-0.25, 0.25)
        w = -height / 2 + (b + 0.5) * height / boarded + k.rng.uniform(-0.05, 0.05)
        rot = (0, 0, tilt) if abs(n.z) > 0.5 else (tilt, 0, 0)
        k.box("Wood", at(k.rng.uniform(-0.05, 0.05), 0.07, w), size(width + 0.35, 0.025, 0.17), rot)
        for side in (-1, 1):
            k.box("Steel", at(side * (width / 2 + 0.1), 0.085, w), size(0.015, 0.012, 0.015))


def corrugated_box_walls(k, x0, x1, z0, z1, h, mat="Corrugated", skip_front=(), pitch=0.076, base=0.0):
    """Four corrugated walls round a rectangle, on the outside of it; the front
    (z1) can leave gaps [(xa, xb, top)] for doors."""
    k.corrugated(mat, V(x1, base, z0), V(-1, 0, 0), V(0, 1, 0), x1 - x0, h - base, pitch, out=V(0, 0, -1))
    k.corrugated(mat, V(x0, base, z0), V(0, 0, 1), V(0, 1, 0), z1 - z0, h - base, pitch, out=V(-1, 0, 0))
    k.corrugated(mat, V(x1, base, z1), V(0, 0, -1), V(0, 1, 0), z1 - z0, h - base, pitch, out=V(1, 0, 0))
    spans = [(x0, x1, base)]
    for xa, xb, top in skip_front:
        spans = [s for sp in spans for s in ((sp[0], min(sp[1], xa), base), (max(sp[0], xb), sp[1], base)) if s[1] - s[0] > 0.02]
        k.corrugated(mat, V(xa, top, z1), V(1, 0, 0), V(0, 1, 0), xb - xa, h - top, pitch, out=V(0, 0, 1))
    for a, b, bottom in spans:
        k.corrugated(mat, V(a, bottom, z1), V(1, 0, 0), V(0, 1, 0), b - a, h - bottom, pitch, out=V(0, 0, 1))


def corrugated_roof(k, x0, x1, z0, z1, y_front, y_back, mat="Roof", pitch=0.076, overhang=0.25):
    """A mono-pitch corrugated roof: ribs run front to back, falling to the front."""
    za, zb = z0 - overhang, z1 + overhang
    rise = y_back - y_front
    slope = rise / (z1 - z0)
    ya = y_back + slope * overhang
    yb = y_front - slope * overhang
    run = V(0, yb - ya, zb - za)
    k.corrugated(mat, V(x0 - overhang, ya, za), V(1, 0, 0), run, x1 - x0 + 2 * overhang, run.length, pitch, 0.02, out=V(0, 1, 0))
    return ya, yb


def purlins(k, x0, x1, z0, z1, y_front, y_back, count, mat="Steel"):
    for i in range(count):
        t = (i + 0.5) / count
        z = z0 + (z1 - z0) * (1 - t)
        y = y_front + (y_back - y_front) * t
        k.box(mat, V((x0 + x1) / 2, y - 0.06, z), (x1 - x0, 0.1, 0.05))


def strip_light(k, center, length=1.3, dead=True):
    k.box("Steel", Vector(center), (length, 0.05, 0.12))
    k.box("Lamp" if not dead else "Tin", Vector(center) - V(0, 0.035, 0), (length - 0.1, 0.03, 0.07))
    for dx in (-length * 0.35, length * 0.35):
        k.box("Steel", Vector(center) + V(dx, 0.25, 0), (0.008, 0.5, 0.008))


def tyre(k, center, radius=0.31, width=0.2, axis=V(0, 1, 0), sides=14):
    c = Vector(center)
    a = Vector(axis).normalized() * width / 2
    k.cyl("Rubber", c - a, c + a, radius, sides, caps=False)
    k.cyl("Rubber", c - a, c + a, radius * 0.6, sides, caps=False)
    bm = k.bm("Rubber")
    rot = a.to_track_quat("Z", "Y").to_matrix()
    for end in (-1, 1):
        ring = []
        for s in range(sides):
            ang = s / sides * 2 * pi
            d = rot @ V(cos(ang), sin(ang), 0)
            ring.append((c + a * end + d * radius, c + a * end + d * radius * 0.6))
        for s in range(sides):
            o0, i0 = ring[s]
            o1, i1 = ring[(s + 1) % sides]
            verts = [bm.verts.new(p) for p in (o0, o1, i1, i0)]
            bm.faces.new(verts if end > 0 else verts[::-1])


def drum(k, center, mat="Rust", radius=0.29, height=0.88, lid=True, tipped=False):
    c = Vector(center)
    if tipped:
        a, b = c + V(-height / 2, radius, 0), c + V(height / 2, radius, 0)
        k.cyl(mat, a, b, radius, 14)
        for t in (0.3, 0.7):
            p = a + (b - a) * t
            k.cyl(mat, p - V(0.015, 0, 0), p + V(0.015, 0, 0), radius + 0.01, 14)
        return
    k.cyl(mat, c, c + V(0, height, 0), radius, 14)
    for t in (0.32, 0.66):
        k.cyl(mat, c + V(0, height * t - 0.015, 0), c + V(0, height * t + 0.015, 0), radius + 0.01, 14)
    k.cyl(mat, c + V(0, height - 0.01, 0), c + V(0, height + 0.012, 0), radius + 0.012, 14)
    if lid:
        k.cyl("Steel", c + V(radius * 0.5, height + 0.012, 0), c + V(radius * 0.5, height + 0.03, 0), 0.03, 8)


def pallet(k, center, yaw=0.0, lean=0.0):
    c = Vector(center)
    rot = Euler((lean, yaw, 0), "YXZ").to_matrix()
    for i in range(7):
        k.box("Wood", c + rot @ V(-0.5 + i * 0.1667, 0.13, 0), (0.1, 0.02, 1.2), (lean, yaw, 0))
    for x in (-0.5, 0, 0.5):
        k.box("Wood", c + rot @ V(x, 0.07, 0), (0.1, 0.1, 1.2), (lean, yaw, 0))
    for z in (-0.55, 0, 0.55):
        k.box("Wood", c + rot @ V(0, 0.01, z), (1.1, 0.02, 0.1), (lean, yaw, 0))


def plank_wall(k, x0, x1, y0, y1, z, out, mat="Wood", board=0.18, gap=0.012, skip=(), axis="x", batten=True):
    """Vertical boards (board and batten) along a wall at z (axis x) or x
    (axis z); `out` is +-1 for the outside direction. Openings in `skip` as
    (a, b, bottom, top)."""
    n = int((x1 - x0) / board)
    w = (x1 - x0) / n
    for i in range(n):
        a = x0 + i * w
        u = a + w / 2
        ranges = [(y0, y1)]
        for sa, sb, sy0, sy1 in skip:
            if u > sa and u < sb:
                ranges = [r for rg in ranges for r in ((rg[0], min(rg[1], sy0)), (max(rg[0], sy1), rg[1])) if r[1] - r[0] > 0.02]
        for ya, yb in ranges:
            sag = k.rng.uniform(-0.004, 0.004)
            if axis == "x":
                k.box(mat, V(u, (ya + yb) / 2, z + out * (0.012 + sag)), (w - gap, yb - ya, 0.024))
                if batten and i > 0:
                    k.box(mat, V(a, (ya + yb) / 2, z + out * 0.03), (0.05, yb - ya, 0.018))
            else:
                k.box(mat, V(z + out * (0.012 + sag), (ya + yb) / 2, u), (0.024, yb - ya, w - gap))
                if batten and i > 0:
                    k.box(mat, V(z + out * 0.03, (ya + yb) / 2, a), (0.018, yb - ya, 0.05))


def clapboards(k, a0, a1, y0, y1, plane, out, axis="x", board=0.2, skip=(), mat="Boards"):
    """Lapped horizontal siding along a wall at `plane` (z for axis x, x for
    axis z), each board tipped out at the bottom; openings as (a, b, y0, y1)."""
    rows = int((y1 - y0) / board)
    for r in range(rows):
        yb = y0 + r * board
        spans = [(a0, a1)]
        for (sa, sb, sy0, sy1) in skip:
            if yb + board > sy0 and yb < sy1:
                spans = [s for sp in spans for s in ((sp[0], min(sp[1], sa)), (max(sp[0], sb), sp[1])) if s[1] - s[0] > 0.02]
        for a, b in spans:
            if axis == "x":
                k.box(mat, V((a + b) / 2, yb + board / 2, plane + out * 0.016), (b - a, board + 0.018, 0.022), (radians(4 * out), 0, 0))
            else:
                k.box(mat, V(plane + out * 0.016, yb + board / 2, (a + b) / 2), (0.022, board + 0.018, b - a), (0, 0, radians(-4 * out)))
