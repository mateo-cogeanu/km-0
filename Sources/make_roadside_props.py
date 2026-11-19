"""What stands along the desert road: telephone poles, kilometre posts, the
signs before each station, and the plants and rocks of each stretch of
country (creosote scrub, saguaro, dry grass, mesquite, pine, sandstone).
Exported to assets/desert/.

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_roadside_props.py

Coordinates are Godot's; every model stands on its origin. The pole's wires
hang from y = 6.78, 0.6 m either side (scripts/infinite_road.gd).
"""

import sys
from math import cos, pi, radians, sin
from pathlib import Path
from random import Random

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector
from desert_kit import TO_BLENDER, V, Kit, build_all, material

POLE_HEIGHT = 7.2


def pole():
    k = Kit(700)
    # A tapered, weathered timber pole, with checks down it and climbing steps.
    k.cyl("Wood", V(0, -0.3, 0), V(0, POLE_HEIGHT, 0), 0.135, 9, 0.1)
    for a in (0.4, 2.3, 4.1):
        k.box("Dark interior", V(0.122 * cos(a), 2.5, 0.122 * sin(a)), (0.012, 3.0, 0.012), (0, -a, 0))
    k.box("Tin", V(0.0, 2.2, 0.135), (0.09, 0.12, 0.006))
    for i in range(10):
        side = 1 if i % 2 else -1
        k.cyl("Steel", V(0, 2.4 + i * 0.38, 0), V(side * 0.3, 2.4 + i * 0.38, 0.02), 0.014, 5)
    # Cross-arm with braces and four insulators; the wires use the middle two.
    k.box("Wood", V(0, 6.62, 0), (1.9, 0.1, 0.1))
    for side in (-1, 1):
        k.span("Steel", V(0, 6.1, 0.06), V(side * 0.6, 6.58, 0.06), 0.03, 0.008)
    for x in (-0.82, -0.6, 0.6, 0.82):
        k.cyl("Steel", V(x, 6.67, 0), V(x, 6.71, 0), 0.012, 5)
        for j in range(3):
            k.cyl("Glass", V(x, 6.71 + j * 0.025, 0), V(x, 6.73 + j * 0.025, 0), 0.045 - j * 0.008, 8)
    k.cyl("Wood", V(0, POLE_HEIGHT, 0), V(0, POLE_HEIGHT + 0.03, 0), 0.105, 9)
    k.box("Tin", V(0, POLE_HEIGHT + 0.035, 0), (0.24, 0.01, 0.24))
    return k.finish("Pole")


def km_post():
    """The label sits at (0, 0.88, 0.05), facing +Z."""
    k = Kit(701)
    k.box("Concrete", V(0, 0.42, 0), (0.12, 0.96, 0.08))
    k.box("Concrete", V(0, -0.05, 0), (0.2, 0.12, 0.16))
    k.box("Red paint", V(0, 0.82, 0.001), (0.125, 0.08, 0.082))
    k.box("Steel", V(0, 0.88, 0.022), (0.4, 0.34, 0.012))
    k.box("Green paint", V(0, 0.88, 0.033), (0.36, 0.3, 0.012))
    for x in (-0.15, 0.15):
        for y in (0.76, 1.0):
            k.cyl("Steel", V(x, y, 0.04), V(x, y, 0.046), 0.008, 6)
    return k.finish("KmPost")


def station_sign():
    """Two posts and a board; the label sits at (0, 1.75, 0.075), facing +Z."""
    k = Kit(702)
    for x in (-0.55, 0.55):
        k.box("Wood", V(x, 1.0, -0.03), (0.1, 2.15, 0.1))
        k.box("Wood", V(x, 2.08, -0.03), (0.11, 0.02, 0.11))
        k.span("Wood", V(x, 0.1, -0.5), V(x, 1.0, -0.06), 0.06)
    k.box("Wood", V(0, 1.75, 0.035), (1.56, 0.81, 0.04))
    k.box("Green paint", V(0, 1.75, 0.056), (1.5, 0.75, 0.006))
    k.box("Sign", V(0, 1.75, 0.059), (1.42, 0.67, 0.002))
    k.box("Green paint", V(0, 1.75, 0.0605), (1.38, 0.63, 0.002))
    for x in (-0.55, 0.55):
        for y in (1.5, 2.0):
            k.cyl("Steel", V(x, y, 0.055), V(x, y, 0.066), 0.012, 6)
    k.box("Wood", V(0, 1.32, 0.0), (1.3, 0.06, 0.05))
    return k.finish("StationSign")


# --- Plants and rocks -------------------------------------------------------------

class Plant:
    """A plant as smooth, tapering limbs plus leaf cards.

    Limbs are tubes along curved paths, shaded smooth. Cards are quads with
    0..1 UVs (assets/desert/foliage.gdshader draws the leaves on them) whose
    normals point out of the crown, so the crown lights as one soft mass.
    """

    def __init__(self, seed):
        self.rng = Random(seed)
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []
        self.card_normals = {}

    def _mat(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def tube(self, mat, points, radii, sides=8):
        """A tube through `points` (Godot space), radius per point, closed
        with a small cap at the far end."""
        bm, index = self.bm, self._mat(mat)
        points = [Vector(p) for p in points]
        rings = []
        normal = None
        for i, p in enumerate(points):
            ahead = points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]
            ahead.normalize()
            if normal is None:
                normal = ahead.orthogonal().normalized()
            normal = (normal - ahead * normal.dot(ahead)).normalized()
            side = ahead.cross(normal)
            ring = []
            for k in range(sides):
                a = k / sides * 2 * pi
                ring.append(bm.verts.new(p + (normal * cos(a) + side * sin(a)) * radii[i]))
            rings.append(ring)
        length = 0.0
        for i in range(len(rings) - 1):
            step = (points[i + 1] - points[i]).length
            for k in range(sides):
                n = (k + 1) % sides
                face = bm.faces.new((rings[i][k], rings[i][n], rings[i + 1][n], rings[i + 1][k]))
                face.material_index = index
                face.smooth = True
                for loop, (u, v) in zip(face.loops, ((k, length), (k + 1, length), (k + 1, length + step), (k, length + step))):
                    loop[self.uv].uv = (u / sides, v)
            length += step
        tip = bm.verts.new(points[-1] + (points[-1] - points[-2]).normalized() * radii[-1])
        for k in range(sides):
            face = bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], tip))
            face.material_index = index
            face.smooth = True

    def limb(self, mat, start, direction, length, r0, r1, bend=0.25, segments=5, sides=8, droop=0.0):
        """A gently curving limb; returns its points so twigs can branch off."""
        rng = self.rng
        d = Vector(direction).normalized()
        wobble = Vector((rng.uniform(-1, 1), rng.uniform(-0.3, 0.3), rng.uniform(-1, 1))) * bend
        points, radii = [], []
        p = Vector(start) - d * min(r0, length * 0.2)
        for i in range(segments + 1):
            t = i / segments
            points.append(p.copy())
            radii.append(r0 + (r1 - r0) * t)
            d = (d + wobble / segments + Vector((0, -droop / segments, 0))).normalized()
            p = p + d * (length / segments)
        self.tube(mat, points, radii, sides)
        return points

    def card(self, mat, center, right, up, crown, crown_size):
        """A leaf card: `right` and `up` are its half-extents."""
        bm, index = self.bm, self._mat(mat)
        center = Vector(center)
        corners = [center - right - up, center + right - up, center + right + up, center - right + up]
        face = bm.faces.new([bm.verts.new(c) for c in corners])
        face.material_index = index
        face.smooth = True
        normals = []
        for loop, uv in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[self.uv].uv = uv
            rel = loop.vert.co - Vector(crown)
            rel = Vector((rel.x / crown_size[0], rel.y / crown_size[1], rel.z / crown_size[2]))
            normals.append((rel.normalized() * 0.8 + Vector((0, 0.45, 0))).normalized())
        self.card_normals[face] = normals

    def spray(self, mat, at, size, crown, crown_size, count=3, flat=0.0, along=None):
        """A few crossed cards around one point: a clump of leaves."""
        rng = self.rng
        for _ in range(count):
            if along is not None:
                up = Vector(along).normalized()
                spin = rng.uniform(0, pi)
                side = up.orthogonal().normalized()
                side = Matrix.Rotation(spin, 3, up) @ side
                self.card(mat, Vector(at) + up * size * 0.45, side * size * 0.32, up * size * 0.55, crown, crown_size)
                continue
            n = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1) * (1 - flat) + flat * 2.0, rng.uniform(-1, 1))).normalized()
            right = n.orthogonal().normalized()
            right = Matrix.Rotation(rng.uniform(0, pi), 3, n) @ right
            up = n.cross(right)
            s = size * rng.uniform(0.8, 1.15)
            self.card(mat, at, right * s * 0.5, up * s * 0.5, crown, crown_size)

    def finish(self, name):
        bm = self.bm
        bm.faces.index_update()
        normals_by_face = {face.index: n for face, n in self.card_normals.items()}
        rot = TO_BLENDER.to_3x3()
        bmesh.ops.transform(bm, matrix=TO_BLENDER, verts=bm.verts)
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        for mat in self.mats:
            mesh.materials.append(material(mat))
        loop_normals = [Vector(c.vector) for c in mesh.corner_normals]
        for poly in mesh.polygons:
            wanted = normals_by_face.get(poly.index)
            if wanted:
                for k, li in enumerate(poly.loop_indices):
                    loop_normals[li] = rot @ wanted[k]
        mesh.normals_split_custom_set(loop_normals)
        obj = bpy.data.objects.new(name, mesh)
        obj["keep_normals"] = True
        bpy.context.scene.collection.objects.link(obj)
        return obj


def _crown_cards(plant, mat, tips, size, crown, crown_size, per_tip=4, flat=0.4):
    for tip in tips:
        plant.spray(mat, tip, size, crown, crown_size, per_tip, flat)


def scrub(seed=710):
    """Creosote: a vase of thin grey stems from one root, sprays of small
    olive leaves along their upper halves."""
    k = Plant(seed)
    rng = k.rng
    crown, crown_size = V(0, 0.55, 0), (0.6, 0.45, 0.6)
    for i in range(13):
        a = i / 13 * 2 * pi + rng.uniform(-0.3, 0.3)
        lean = rng.uniform(0.2, 0.7)
        length = rng.uniform(0.55, 1.0)
        d = V(sin(lean) * cos(a), cos(lean), sin(lean) * sin(a))
        pts = k.limb("Bark", V(0, 0, 0), d, length, 0.016, 0.005, bend=0.35, segments=4, sides=5)
        if rng.random() < 0.85:
            for p in pts[2:]:
                k.spray("Scrub", p, rng.uniform(0.26, 0.36), crown, crown_size, 2, 0.2)
    return k.finish("Scrub")


def cactus(arms=2, seed=720):
    """A ribbed saguaro, arms bending up."""
    k = Kit(seed)
    rng = k.rng

    def ribbed(a, b, r, ribs=12):
        k.cyl("Cactus", a, b, r, ribs * 2, r * 0.92)

    height = rng.uniform(2.2, 2.9)
    ribbed(V(0, -0.1, 0), V(0, height, 0), 0.19)
    k.ico("Cactus", V(0, height, 0), 0.19, (1, 0.7, 1), 2, 0.0)
    for i in range(arms):
        a = i * pi + rng.uniform(-0.4, 0.4)
        out = V(cos(a), 0, sin(a))
        y0 = rng.uniform(0.9, 1.4)
        elbow = V(0, y0, 0) + out * 0.5 + V(0, 0.12, 0)
        ribbed(V(0, y0, 0) + out * 0.1, elbow, 0.12, 10)
        k.ico("Cactus", elbow, 0.12, (1, 1, 1), 1, 0.0)
        top = elbow + V(0, rng.uniform(0.6, 1.0), 0)
        ribbed(elbow, top, 0.12, 10)
        k.ico("Cactus", top, 0.12, (1, 0.7, 1), 1, 0.0)
    # Spines catch the light as a pale fuzz on the crown.
    k.ico("Grass", V(0, height + 0.08, 0), 0.06, (1, 0.4, 1), 1, 0.2)
    return k.finish("Cactus")


def grass(seed=730, mat="Dry grass"):
    """A tuft of bunchgrass: a few crossed cards of blades (the blades are
    drawn by assets/desert/foliage.gdshader from foliage_grass.png), leaning
    a little outward, lit as one soft clump."""
    k = Plant(seed)
    rng = k.rng
    crown, crown_size = V(0, 0.05, 0), (0.45, 0.6, 0.45)
    cards = 4
    for i in range(cards):
        yaw = i / cards * pi + rng.uniform(-0.25, 0.25)
        right = V(cos(yaw), 0, sin(yaw))
        out = V(-sin(yaw), 0, cos(yaw)) * rng.uniform(-0.06, 0.06)
        width = rng.uniform(0.27, 0.34)
        height = rng.uniform(0.24, 0.3)
        up = V(0, height, 0) + out
        centre = V(rng.uniform(-0.04, 0.04), 0, rng.uniform(-0.04, 0.04)) + up - V(0, 0.02, 0)
        k.card(mat, centre, right * width, up, crown, crown_size)
    return k.finish("Grass")


def tree(seed=740):
    """A mesquite: a short leaning trunk splitting low into crooked limbs,
    then twigs, under a wide, broken umbrella of small leaves."""
    k = Plant(seed)
    rng = k.rng
    crown, crown_size = V(0.2, 3.1, 0.1), (2.6, 1.1, 2.6)
    tips = []

    def grow(start, d, length, r, depth):
        pts = k.limb("Bark", start, d, length, r, r * 0.68, bend=0.45, segments=4 if depth else 3, sides=9 if depth > 1 else 6)
        end = pts[-1]
        if depth == 0:
            tips.extend(pts[-3:])
            return
        for n in range(2 if depth > 1 else 3):
            turn = Euler((rng.uniform(-0.6, 0.6), rng.uniform(0, 2 * pi), rng.uniform(-0.6, 0.6)), "XYZ").to_matrix()
            child = (turn @ d).normalized()
            child.y = abs(child.y) * 0.45 + 0.22
            grow(end, child.normalized(), length * rng.uniform(0.62, 0.8), r * 0.62, depth - 1)

    trunk = k.limb("Bark", V(0, -0.25, 0), V(0.12, 1, 0.05), 1.15, 0.2, 0.15, bend=0.2, segments=4, sides=10)
    for i in range(3):
        a = i / 3 * 2 * pi + rng.uniform(-0.35, 0.35)
        grow(trunk[-1], V(cos(a) * 0.75, 0.75, sin(a) * 0.75), 1.25, 0.12, 2)
    _crown_cards(k, "Leaves", tips, 1.05, crown, crown_size, 4, 0.55)
    return k.finish("Tree")


def pine(seed=750):
    """A pinyon-ish pine: a tall tapering trunk, uneven whorls of drooping
    branches, needle sprigs along them, thinning toward a ragged top."""
    k = Plant(seed)
    rng = k.rng
    height = 6.2
    crown, crown_size = V(0, 3.4, 0), (1.7, 2.6, 1.7)
    k.limb("Pine bark", V(0, -0.25, 0), V(0.02, 1, 0.01), height + 0.25, 0.2, 0.03, bend=0.08, segments=8, sides=10)
    whorls = 9
    for t in range(whorls):
        f = t / whorls
        y = 1.3 + f * (height - 1.6)
        spread = 1.9 * (1 - f) ** 0.9 + 0.25
        count = rng.randint(4, 6) if f < 0.8 else 3
        for i in range(count):
            if rng.random() < 0.15:
                continue
            a = i / count * 2 * pi + rng.uniform(-0.4, 0.4) + t * 1.3
            out = V(cos(a), 0.15 - 0.1 * (1 - f), sin(a))
            length = spread * rng.uniform(0.75, 1.05)
            pts = k.limb("Pine bark", V(0, y, 0), out, length, 0.045 * (1 - f) + 0.015, 0.008, bend=0.2, segments=4, sides=5, droop=0.35 * (1 - f))
            for j in range(1, len(pts)):
                d = (pts[j] - pts[j - 1]).normalized()
                size = 0.75 * (0.6 + 0.4 * (1 - f))
                k.spray("Needles", pts[j - 1], size, crown, crown_size, 2, along=(d + V(0, 0.35, 0)))
                for side in (-1, 1):
                    sd = (d.cross(V(0, 1, 0)) * side + d * 0.6 + V(0, 0.2, 0)).normalized()
                    k.spray("Needles", pts[j - 1] + d * 0.1, size * 0.8, crown, crown_size, 1, along=sd)
    for i in range(4):
        k.spray("Needles", V(0, height - 0.5 + i * 0.15, 0), 0.6, crown, crown_size, 2, along=V(rng.uniform(-0.2, 0.2), 1, rng.uniform(-0.2, 0.2)))
    return k.finish("Pine")


def dead_tree(seed=760):
    """A long-dead mesquite, bleached grey: crooked limbs down to bare twigs."""
    k = Plant(seed)
    rng = k.rng

    def grow(start, d, length, r, depth):
        pts = k.limb("Dead wood", start, d, length, r, r * 0.66, bend=0.55, segments=4 if depth > 1 else 3, sides=8 if depth > 2 else 5)
        if depth == 0 or r < 0.015:
            return
        for n in range(2 if rng.random() < 0.7 else 3):
            turn = Euler((rng.uniform(-0.8, 0.8), rng.uniform(0, 2 * pi), rng.uniform(-0.8, 0.8)), "XYZ").to_matrix()
            child = (turn @ d).normalized()
            child.y = abs(child.y) * 0.7 + 0.15
            grow(pts[-1] if n else pts[-2], child.normalized(), length * rng.uniform(0.55, 0.78), r * 0.62, depth - 1)

    grow(V(0, -0.25, 0), V(0.12, 1, 0.05), 1.7, 0.17, 4)
    return k.finish("DeadTree")


def _boulder(rng, center, radius, scale, layered, subdiv, crack=True, seed=0.0):
    """One eroded boulder in its own bmesh (Godot space): a squashed sphere
    roughened by layered noise, with sandstone bedding ledges (each band
    undercut a little, so the lips overhang), a fissure or two, and a base
    that spreads and sinks into the ground."""
    from mathutils import noise
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    step = rng.uniform(0.13, 0.19)
    tilt = Vector((rng.uniform(-0.15, 0.15), 1.0, rng.uniform(-0.15, 0.15))).normalized()
    cracks = []
    if crack:
        for _ in range(rng.randint(1, 2)):
            a = rng.uniform(0, 2 * pi)
            cracks.append((Vector((cos(a), 0, sin(a))), rng.uniform(-0.25, 0.25), rng.uniform(0.025, 0.045)))
    for v in bm.verts:
        n = v.co.normalized()
        p = Vector((n.x * scale[0], n.y * scale[1], n.z * scale[2]))
        # Broad lumps, then finer pitting.
        lump = noise.fractal(p * 1.3 + off, 0.6, 2.0, 3) * 0.22
        pit = noise.noise(p * 6.0 + off) * 0.035
        r = 1.0 + lump + pit
        q = p * r
        if layered:
            # Bedding: each band's lower part is cut back, its top a ledge.
            h = q.dot(tilt) + 0.5
            band = (h / step) % 1.0
            # Softer beds wear back into grooves between the harder ones.
            groove = 0.5 - 0.5 * cos(2 * pi * band)
            # Only on the flanks: the top and the buried underside stay whole.
            flank = max(0.0, 1.0 - abs(n.y) / 0.75)
            undercut = 0.045 * groove * flank * max(0.0, min(1.0, h * 2.0))
            q = q - Vector((n.x, 0.0, n.z)) * undercut
        for normal, offset, width in cracks:
            d = abs(q.dot(normal) - offset)
            if d < width and q.y > -0.25:
                q = q - n * (width - d) / width * 0.09
        # Spread and sink the base into the ground.
        if q.y < 0.0:
            q = Vector((q.x * (1.0 + 0.25 * min(1.0, -q.y * 2.5)), q.y, q.z * (1.0 + 0.25 * min(1.0, -q.y * 2.5))))
        v.co = q * radius + Vector(center)
    return bm


def rock(seed, layered=True):
    """A weathered desert boulder, sitting half buried: eroded sandstone with
    bedding ledges and a crack (layered), or a rounded, split boulder with a
    smaller one leaning on it; a few loose stones around either."""
    rng = Random(seed)
    merged = bmesh.new()
    parts = []
    if layered:
        parts.append(_boulder(rng, V(0, 0.18, 0), 1.0, (1.15, 0.62, 0.85), True, 5, False, seed))
    else:
        parts.append(_boulder(rng, V(0, 0.22, 0), 0.95, (1.0, 0.78, 0.9), False, 5, True, seed))
        parts.append(_boulder(rng, V(0.95, 0.05, 0.35), 0.5, (1.0, 0.8, 0.95), False, 4, False, seed + 7))
    for i in range(rng.randint(3, 5)):
        a = rng.uniform(0, 2 * pi)
        dist = rng.uniform(1.15, 1.7)
        parts.append(_boulder(rng, V(cos(a) * dist, -0.02, sin(a) * dist * 0.8), rng.uniform(0.08, 0.18),
            (1.0, 0.6, 0.85), False, 3, False, seed + 11 + i))
    for bm in parts:
        temp = bpy.data.meshes.new("t")
        bm.to_mesh(temp)
        bm.free()
        merged.from_mesh(temp)
        bpy.data.meshes.remove(temp)
    bmesh.ops.transform(merged, matrix=TO_BLENDER, verts=merged.verts)
    mesh = bpy.data.meshes.new("Rock")
    merged.to_mesh(mesh)
    merged.free()
    mesh.materials.append(material("Rock"))
    obj = bpy.data.objects.new("Rock", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    # Down to a sensible count: collapse keeps the form, the ledges stay crisp
    # where the angle is sharp and everything else shades smooth.
    dec = obj.modifiers.new("Decimate", "DECIMATE")
    dec.ratio = 0.24
    bpy.ops.object.modifier_apply(modifier=dec.name)
    bpy.ops.object.shade_smooth_by_angle(angle=radians(75))
    return obj


build_all([
    ("pole", pole),
    ("km_post", km_post),
    ("station_sign", station_sign),
    ("scrub", scrub),
    ("scrub_b", lambda: scrub(711)),
    ("cactus", cactus),
    ("cactus_b", lambda: cactus(1, 721)),
    ("grass", grass),
    ("grass_b", lambda: grass(731, "Green grass")),
    ("tree", tree),
    ("pine", pine),
    ("dead_tree", dead_tree),
    ("rock", lambda: rock(770)),
    ("rock_b", lambda: rock(771, False)),
])
