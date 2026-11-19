"""Rebuild assets/characters/salvage_listener.glb: the thing in Marrow's water.

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_salvage_creature.py

Built the same way as the road creature (make_road_creature.py): the skin is
one signed distance field, every bone, spur, rib and knuckle a primitive
blended into its neighbours, meshed with OpenVDB, smoothed and decimated.
The ear membranes are thin sheets of their own, strung between bony rays.

It lies flat just under the surface: the water line is z = 0, so at rest only
the spurs along its spine break it. It faces -Y (Blender is Z-up); the glTF
exporter turns that into Godot's Y-up, +Z-forward space.

Bones, used by scripts/salvage_listener.gd:
    Pelvis, Spine, Chest, Neck1, Neck2, Head, Jaw, EarL, EarR,
    EarL0..EarL5 / EarR0..EarR5 (one per ray, so the ears fan open),
    Tail1..Tail4, UpperArmL/R, ForearmL/R, HandL/R
"""

from math import cos, pi, sin, sqrt
from pathlib import Path
from random import Random

import bmesh
import bpy
import numpy as np
import openvdb
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
GLB = ROOT / "assets/characters/salvage_listener.glb"
BLEND = ROOT / "Sources/salvage_listener.blend"
VOXEL = 0.006

rng = Random(4471)

# The body plan, front to back along -Y.
SNOUT = Vector((0, -2.12, -0.05))
HEAD = Vector((0, -1.66, 0.0))          # where the head turns on the neck
NECK_TOP = Vector((0, -1.52, -0.03))
NECK_MID = Vector((0, -1.28, -0.07))
NECK_BASE = Vector((0, -1.02, -0.1))
CHEST = Vector((0, -0.58, -0.16))
WAIST = Vector((0, 0.12, -0.17))
HIPS = Vector((0, 0.72, -0.18))
TAIL = [Vector((0, 0.92, -0.18)), Vector((0.02, 1.35, -0.19)), Vector((-0.03, 1.8, -0.2)),
    Vector((0.03, 2.25, -0.2)), Vector((0, 2.68, -0.2))]
TAIL_RADII = [0.15, 0.11, 0.075, 0.045, 0.012]
# The mouth: a lipless seam from the snout tip back under the ear.
MOUTH_FRONT = SNOUT + Vector((0, 0.03, -0.01))
MOUTH_BACK_Y = -1.68
EAR_HINGE = 0.11
EAR_ROOT = Vector((0, -1.7, 0.06))


def mouth_z(y):
    """The seam's height: low at the snout, rising toward the back."""
    t = (y - MOUTH_FRONT.y) / (MOUTH_BACK_Y - MOUTH_FRONT.y)
    return MOUTH_FRONT.z + 0.05 * t * t


def mouth_half(y):
    """How far out to the side the seam runs at y (the jaw's width)."""
    t = min(max((y - MOUTH_FRONT.y) / (MOUTH_BACK_Y - MOUTH_FRONT.y), 0.0), 1.0)
    return 0.025 + 0.075 * sqrt(t)


def back_z(y):
    """The top of the back, along the spine."""
    if y < NECK_BASE.y:
        return NECK_BASE.z + 0.12
    if y < WAIST.y:
        return -0.16 + 0.19 * (1.0 - ((y - CHEST.y) / 0.8) ** 2) ** 0.5 if abs(y - CHEST.y) < 0.8 else -0.02
    if y < HIPS.y:
        return 0.0 - 0.03 * (y - WAIST.y) / (HIPS.y - WAIST.y)
    return -0.06


def arm_points(side):
    shoulder = CHEST + Vector((side * 0.34, -0.2, -0.02))
    elbow = shoulder + Vector((side * 0.3, 0.42, -0.08))
    wrist = elbow + Vector((-side * 0.08, -0.62, -0.12))
    palm = wrist + Vector((side * 0.06, -0.12, -0.05))
    return shoulder, elbow, wrist, palm


def ear_rays(side):
    """Six bony rays fanning from the hinge, folded back along the neck."""
    hinge = EAR_ROOT + Vector((side * EAR_HINGE, 0, 0))
    rays = []
    for n in range(6):
        t = n / 5
        length = 0.42 + 0.38 * sin(pi * (0.25 + 0.6 * t))
        # Folded: swept back and a little out, fanning from low to high.
        direction = Vector((side * (0.32 + 0.1 * t), 0.9, -0.25 + 0.75 * t)).normalized()
        mid = hinge + direction * length * 0.5 + Vector((side * 0.03, 0, 0.02))
        tip = hinge + direction * length + Vector((side * 0.02 * sin(n * 1.7), 0, -0.03))
        rays.append((hinge, mid, tip))
    return hinge, rays


# Distance field (as in make_road_creature.py) ---------------------------------

class Field:
    def __init__(self, low, high):
        self.low = np.array(low, dtype=np.float64)
        self.shape = tuple(int(np.ceil((h - l) / VOXEL)) + 1 for l, h in zip(low, high))
        self.d = np.full(self.shape, 0.3, dtype=np.float32)
        print("field", self.shape, f"{np.prod(self.shape) / 1e6:.0f}M voxels")

    def _region(self, low, high):
        lo = np.maximum(np.floor((np.array(low) - self.low) / VOXEL).astype(int), 0)
        hi = np.minimum(np.ceil((np.array(high) - self.low) / VOXEL).astype(int) + 1, self.shape)
        if np.any(hi <= lo):
            return None
        axes = [self.low[i] + VOXEL * np.arange(lo[i], hi[i], dtype=np.float32) for i in range(3)]
        x, y, z = np.meshgrid(*axes, indexing="ij")
        return (slice(lo[0], hi[0]), slice(lo[1], hi[1]), slice(lo[2], hi[2])), x, y, z

    def add(self, sdf, low, high, k, subtract=False):
        pad = k + 4 * VOXEL
        found = self._region(np.array(low) - pad, np.array(high) + pad)
        if found is None:
            return
        region, x, y, z = found
        a = self.d[region]
        b = sdf(x, y, z).astype(np.float32)
        if subtract:
            h = np.clip(0.5 - 0.5 * (a + b) / k, 0.0, 1.0)
            self.d[region] = a * (1 - h) - b * h + k * h * (1 - h)
        else:
            h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
            self.d[region] = b * (1 - h) + a * h - k * h * (1 - h)

    def ellipsoid(self, center, radii, k, rotation=None, subtract=False):
        c = np.array(center)
        r = np.array(radii)
        m = np.array(rotation.to_matrix()) if rotation else np.eye(3)

        def sdf(x, y, z):
            px, py, pz = x - c[0], y - c[1], z - c[2]
            lx = (m[0, 0] * px + m[1, 0] * py + m[2, 0] * pz) / r[0]
            ly = (m[0, 1] * px + m[1, 1] * py + m[2, 1] * pz) / r[1]
            lz = (m[0, 2] * px + m[1, 2] * py + m[2, 2] * pz) / r[2]
            k0 = np.sqrt(lx * lx + ly * ly + lz * lz)
            k1 = np.sqrt((lx / r[0]) ** 2 + (ly / r[1]) ** 2 + (lz / r[2]) ** 2)
            return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)

        reach = r.max()
        self.add(sdf, c - reach, c + reach, k, subtract)

    def capsule(self, a, b, ra, rb, k, subtract=False):
        a = np.array(a)
        b = np.array(b)
        ab = b - a
        length2 = max(float(ab.dot(ab)), 1e-9)

        def sdf(x, y, z):
            px, py, pz = x - a[0], y - a[1], z - a[2]
            t = np.clip((px * ab[0] + py * ab[1] + pz * ab[2]) / length2, 0.0, 1.0)
            dx, dy, dz = px - ab[0] * t, py - ab[1] * t, pz - ab[2] * t
            return np.sqrt(dx * dx + dy * dy + dz * dz) - (ra + (rb - ra) * t)

        reach = max(ra, rb)
        self.add(sdf, np.minimum(a, b) - reach, np.maximum(a, b) + reach, k, subtract)

    def chain(self, points, radii, k):
        for i in range(len(points) - 1):
            self.capsule(points[i], points[i + 1], radii[i], radii[i + 1], k)

    def mesh(self, name):
        grid = openvdb.FloatGrid(0.3)
        grid.copyFromArray(self.d)
        grid.transform = openvdb.createLinearTransform(voxelSize=VOXEL)
        points, triangles, quads = grid.convertToPolygons(isovalue=0.0, adaptivity=0.0)
        points = points + self.low
        mesh = bpy.data.meshes.new(name)
        faces = [tuple(int(i) for i in f[::-1]) for f in quads] + [tuple(int(i) for i in f[::-1]) for f in triangles]
        mesh.from_pydata([tuple(p) for p in points], [], faces)
        mesh.validate()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def curve(points, t):
    s = t * (len(points) - 1)
    i = min(int(s), len(points) - 2)
    return points[i].lerp(points[i + 1], s - i)


def build_hand(f, wrist, palm, side):
    """A long webbed hand: four jointed fingers ending in hooked claws."""
    f.capsule(wrist, palm, 0.032, 0.036, 0.03)
    f.ellipsoid(palm + Vector((0, -0.02, 0)), (0.055, 0.07, 0.022), 0.03)
    claws = []
    for n in range(4):
        spread = (n - 1.5) / 1.5
        knuckle = palm + Vector((side * spread * 0.045, -0.07, 0.0))
        heading = Vector((side * spread * 0.35, -1, -0.15)).normalized()
        reach = 0.24 * (1.0 - abs(spread) * 0.18)
        mid = knuckle + heading * reach * 0.42 + Vector((0, 0, 0.025))
        end = mid + heading * reach * 0.35 + Vector((0, 0, -0.02))
        tip = end + heading * reach * 0.23 + Vector((0, 0, -0.035))
        f.chain([knuckle, mid, end, tip], [0.014, 0.012, 0.0095, 0.006], 0.008)
        for joint in (knuckle, mid, end):
            f.ellipsoid(joint, (0.016, 0.015, 0.014), 0.007)
        claws.append((tip, heading))
    # Webbing between the fingers, thin and sagging.
    for n in range(3):
        a = palm + Vector((side * ((n - 1.5) / 1.5) * 0.045, -0.15, -0.004))
        b = palm + Vector((side * ((n - 0.5) / 1.5) * 0.045, -0.15, -0.004))
        f.capsule(a, b, 0.006, 0.006, 0.02)
    return claws


def build_skin():
    f = Field((-0.98, -2.3, -0.62), (0.98, 2.78, 0.95))
    k = 0.07
    # A long, flat body made for lying just under the surface.
    f.ellipsoid(CHEST, (0.4, 0.6, 0.19), k)
    f.ellipsoid(WAIST, (0.33, 0.55, 0.16), k)
    f.ellipsoid(HIPS, (0.27, 0.32, 0.14), k)
    f.capsule(CHEST, HIPS, 0.17, 0.14, 0.12)
    # A pale, softer belly that sags a little.
    f.ellipsoid(Vector((0, -0.2, -0.3)), (0.3, 0.8, 0.07), 0.08)
    # Shoulder humps where the arms join.
    for side in (-1, 1):
        f.ellipsoid(CHEST + Vector((side * 0.3, -0.22, 0.04)), (0.13, 0.17, 0.1), 0.06)
        # Ribs pressing out through the flanks.
        for r in range(9):
            y = CHEST.y - 0.38 + r * 0.1
            fall = 1.0 - ((y - CHEST.y) / 0.6) ** 2
            span = 0.4 * sqrt(max(fall, 0.05)) - 0.004
            height = 0.19 * sqrt(max(fall, 0.05)) - 0.004
            pts = []
            for n in range(9):
                a = 0.75 - n / 8 * 1.85
                pts.append(Vector((side * span * cos(a), y + n * 0.011, CHEST.z + height * sin(a))))
            f.chain(pts, [0.0095] * len(pts), 0.04)
    # The tail: long and eel-like, flattened side to side toward the tip.
    for i in range(len(TAIL) - 1):
        f.capsule(TAIL[i], TAIL[i + 1], TAIL_RADII[i], TAIL_RADII[i + 1], 0.09)
    for i in range(36):
        t = i / 35
        at = curve(TAIL, t)
        r = TAIL_RADII[0] + (TAIL_RADII[-1] - TAIL_RADII[0]) * t
        # A ragged fin along the top and bottom of the tail.
        tall = (0.05 + 0.13 * sin(pi * min(t * 1.4, 1.0))) * (0.7 + 0.3 * rng.random())
        f.ellipsoid(at + Vector((0, 0, r + tall * 0.45)), (0.008, 0.035, tall * 0.55), 0.015)
        if t > 0.3:
            f.ellipsoid(at + Vector((0, 0, -r - tall * 0.25)), (0.007, 0.03, tall * 0.3), 0.015)
    # The spine: a ridge of knuckled vertebrae, every other one with a bony
    # spur raking back. These are what show above the water.
    for i in range(44):
        t = i / 43
        y = NECK_BASE.y + t * (TAIL[1].y - NECK_BASE.y)
        z = back_z(y)
        f.ellipsoid(Vector((0, y, z + 0.012)), (0.034, 0.03, 0.028), 0.03)
        if i % 2 == 0 or rng.random() < 0.25:
            # Uneven: long and short, leaning, some snapped off short.
            size = (0.04 + 0.13 * sin(pi * min(t * 1.25, 1.0))) * rng.uniform(0.45, 1.25)
            if rng.random() < 0.2:
                size *= 0.4
            base = Vector((rng.uniform(-0.012, 0.012), y, z + 0.02))
            tip = base + Vector((rng.uniform(-0.04, 0.04), size * rng.uniform(0.35, 0.8), size))
            f.capsule(base, tip, 0.024 + size * 0.06, 0.004, 0.025)
        if 0.05 < t < 0.45 and i % 3 == 0:
            # Smaller spurs in pairs over the shoulders.
            for side in (-1, 1):
                base = Vector((side * 0.11, y, z - 0.02))
                f.capsule(base, base + Vector((side * 0.05, 0.04, 0.06)), 0.014, 0.003, 0.015)
    # Growths and old wounds on the back.
    for _ in range(26):
        y = rng.uniform(CHEST.y - 0.4, HIPS.y + 0.2)
        x = rng.uniform(-0.28, 0.28) * (1.0 if abs(y - CHEST.y) < 0.6 else 0.7)
        z = back_z(y) - abs(x) * 0.35
        f.ellipsoid(Vector((x, y, z)), (rng.uniform(0.012, 0.03),) * 2 + (rng.uniform(0.01, 0.02),), 0.02)
    # The neck: long, thick, with tendons down the sides and folds of skin
    # at its base for when it stretches up.
    f.chain([NECK_BASE, NECK_MID, NECK_TOP], [0.15, 0.125, 0.105], 0.08)
    for side in (-1, 1):
        f.chain([NECK_BASE + Vector((side * 0.1, -0.02, 0.0)), NECK_MID + Vector((side * 0.085, 0, 0.0)),
            NECK_TOP + Vector((side * 0.07, 0, -0.01))], [0.022, 0.019, 0.016], 0.03)
    for n in range(5):
        y = NECK_BASE.y - 0.04 - n * 0.05
        f.ellipsoid(Vector((0, y, NECK_BASE.z - 0.1 + n * 0.012)), (0.12 - n * 0.008, 0.018, 0.04), 0.025)
    # The head: long, narrow and bony, no eyes at all. Skin stretched thin
    # over the skull: a crest down the middle, hollow temples, sharp cheeks.
    f.ellipsoid(HEAD + Vector((0, -0.1, 0.035)), (0.105, 0.22, 0.085), 0.045, Quaternion((1, 0, 0), -0.1))
    f.capsule(Vector((0, -1.86, 0.0)), SNOUT, 0.07, 0.03, 0.05)
    f.chain([HEAD + Vector((0, 0.08, 0.1)), HEAD + Vector((0, -0.14, 0.125)), Vector((0, -1.95, 0.05)),
        SNOUT + Vector((0, 0.06, 0.02))], [0.016, 0.02, 0.012, 0.008], 0.025)
    for side in (-1, 1):
        f.capsule(Vector((side * 0.095, -1.6, -0.025)), Vector((side * 0.07, -1.9, -0.035)), 0.024, 0.012, 0.025)
        f.ellipsoid(Vector((side * 0.112, -1.74, 0.06)), (0.045, 0.06, 0.04), 0.02, subtract=True)
        # Where eyes would be: shallow pits, skinned over.
        f.ellipsoid(Vector((side * 0.07, -1.86, 0.05)), (0.022, 0.03, 0.016), 0.012, subtract=True)
    # The lower jaw: two long bones meeting at a pointed chin.
    for side in (-1, 1):
        f.capsule(Vector((side * 0.095, -1.6, -0.1)), Vector((side * 0.012, -2.1, -0.095)), 0.034, 0.02, 0.03)
    f.ellipsoid(Vector((0, -1.84, -0.11)), (0.075, 0.22, 0.035), 0.04)
    # Loose skin hanging in ragged folds under the jaw and throat.
    for n in range(7):
        y = -1.62 - n * 0.06
        f.ellipsoid(Vector((rng.uniform(-0.02, 0.02), y, -0.155 - 0.02 * sin(n))), (0.04 - n * 0.003, 0.03, 0.03), 0.03)
    # Ears: hinge knuckles and six rays each; the membrane is its own mesh.
    for side in (-1, 1):
        hinge, rays = ear_rays(side)
        f.ellipsoid(hinge, (0.05, 0.06, 0.05), 0.03)
        for a, m, b in rays:
            f.chain([a, m, b], [0.016, 0.011, 0.004], 0.012)
            f.ellipsoid(m, (0.016, 0.016, 0.016), 0.008)
    # Arms folded along the flanks.
    claws = []
    for side in (-1, 1):
        shoulder, elbow, wrist, palm = arm_points(side)
        f.chain([shoulder, shoulder.lerp(elbow, 0.4), elbow], [0.075, 0.062, 0.048], 0.05)
        f.ellipsoid(elbow, (0.05, 0.05, 0.05), 0.03)
        f.capsule(elbow + Vector((0, 0.04, 0)), elbow + Vector((side * 0.02, 0.1, 0.01)), 0.03, 0.012, 0.02)
        f.chain([elbow, elbow.lerp(wrist, 0.3), elbow.lerp(wrist, 0.75), wrist], [0.046, 0.05, 0.038, 0.03], 0.04)
        claws += [(tip, heading, side) for tip, heading in build_hand(f, wrist, palm, side)]
    # Carve: nostril slits, the mouth seam, a hollow throat behind it.
    for side in (-1, 1):
        f.capsule(SNOUT + Vector((side * 0.035, 0.05, 0.05)), SNOUT + Vector((side * 0.05, 0.12, 0.055)),
            0.008, 0.005, 0.004, subtract=True)
    for n in range(48):
        y = MOUTH_FRONT.y + (MOUTH_BACK_Y - MOUTH_FRONT.y) * n / 47
        half = mouth_half(y)
        f.ellipsoid(Vector((0, y, mouth_z(y))), (half + 0.02, 0.012, 0.011), 0.004, subtract=True)
    f.ellipsoid(Vector((0, -1.8, -0.06)), (0.06, 0.2, 0.03), 0.012, subtract=True)
    skin = f.mesh("Wet pale skin")
    del f
    recalculate_normals(skin)
    apply_modifier(skin, "LAPLACIANSMOOTH", iterations=2, lambda_factor=0.5, use_volume_preserve=True)
    apply_modifier(skin, "DECIMATE", ratio=0.12)
    recalculate_normals(skin)
    skin.data.shade_smooth()
    print("skin verts", len(skin.data.vertices))
    return skin, claws


def build_membranes():
    """Thin, wrinkled skin strung between each ear's rays, sagging between
    the tips in scallops."""
    meshes = []
    for side in (-1, 1):
        hinge, rays = ear_rays(side)
        bm = bmesh.new()
        rows = 10
        grid = []
        for n, (a, m, b) in enumerate(rays):
            column = []
            for r in range(rows + 1):
                t = r / rows
                p = a.lerp(m, t * 2) if t < 0.5 else m.lerp(b, (t - 0.5) * 2)
                column.append(p)
            grid.append(column)
        verts = []
        shares = []
        for n in range(len(rays) - 1):
            strip = []
            for s in range(5):
                u = s / 4
                col = []
                for r in range(rows + 1):
                    t = r / rows
                    p = grid[n][r].lerp(grid[n + 1][r], u)
                    # Sag between rays, most at the rim; fine wrinkles.
                    sag = sin(pi * u) * (0.02 + 0.07 * t * t)
                    p = p + Vector((side * 0.01, 0.02, -1.0)) * sag
                    p = p + Vector((side * 0.004 * sin(t * 40 + u * 9), 0, 0.003 * sin(t * 31)))
                    col.append(bm.verts.new(p))
                    shares.append((n, u))
                strip.append(col)
            verts.append(strip)
        for strip in verts:
            for s in range(4):
                for r in range(rows):
                    face = (strip[s][r], strip[s + 1][r], strip[s + 1][r + 1], strip[s][r + 1])
                    bm.faces.new(face if side > 0 else face[::-1])
        mesh = bpy.data.meshes.new("Ear membrane")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("Ear membrane" + ("L" if side < 0 else "R"), mesh)
        bpy.context.scene.collection.objects.link(obj)
        mesh.shade_smooth()
        mesh.materials.append(material("Ear membrane", (0.32, 0.22, 0.21), 0.45))
        # Each strip of skin follows the two rays it hangs between.
        suffix = "L" if side < 0 else "R"
        for index, (n, u) in enumerate(shares):
            for ray, w in ((n, 1.0 - u), (n + 1, u)):
                if w > 0.001:
                    name = "Ear%s%d" % (suffix, ray)
                    group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                    group.add([index], w, "ADD")
        meshes.append(obj)
    return meshes


def build_teeth():
    """Needles along the mouth seam, upper and lower, angled in. Some are
    longer than the mouth is tall and show even when it is shut."""
    ivory = material("Old ivory", (0.66, 0.6, 0.48), 0.32)
    teeth = {}
    for name, upper in (("Upper teeth", True), ("Lower teeth", False)):
        bm = bmesh.new()
        edge = 1 if upper else -1
        for side in (-1, 1):
            for i in range(26):
                t = (i + 0.5 + rng.uniform(-0.3, 0.3)) / 26
                y = MOUTH_FRONT.y + (MOUTH_BACK_Y - MOUTH_FRONT.y) * t
                x = side * mouth_half(y) * 0.92
                base = Vector((x, y, mouth_z(y) + edge * 0.012))
                inward = Vector((-side * 0.25, -0.1, -edge)).normalized()
                long = rng.random() < 0.2
                length = rng.uniform(0.02, 0.04) * (1.8 if long else 1.0)
                aim = (inward + Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.1, 0.2), 0))).normalized()
                if long:
                    # Overbite: these hook down outside the lip.
                    aim = Vector((side * 0.3, -0.1, -edge)).normalized()
                    base += Vector((side * 0.012, 0, 0))
                radius = rng.uniform(0.003, 0.0055)
                rot = aim.to_track_quat("Z", "Y").to_matrix().to_4x4()
                bmesh.ops.create_cone(bm, cap_ends=True, segments=7, radius1=radius, radius2=0.0004, depth=length,
                    matrix=Matrix.Translation(base + aim * length * 0.45) @ rot)
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        mesh.materials.append(ivory)
        mesh.shade_smooth()
        teeth[name] = obj
    return teeth


def build_claws(claws):
    horn = material("Black horn", (0.05, 0.045, 0.04), 0.3)
    objs = {}
    for side_name, wanted in (("L", -1), ("R", 1)):
        bm = bmesh.new()
        for tip, heading, side in claws:
            if side != wanted:
                continue
            aim = (heading + Vector((0, 0, -0.6))).normalized()
            rot = aim.to_track_quat("Z", "Y").to_matrix().to_4x4()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.008, radius2=0.0006, depth=0.06,
                matrix=Matrix.Translation(tip + aim * 0.022) @ rot)
        mesh = bpy.data.meshes.new("Claws")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("Claws" + side_name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        mesh.materials.append(horn)
        mesh.shade_smooth()
        objs[side_name] = obj
    return objs


# Assembly -----------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"


def material(name, color, roughness):
    found = bpy.data.materials.get(name)
    if found:
        return found
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    return mat


def recalculate_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=VOXEL * 0.05)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


def apply_modifier(obj, kind, **settings):
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new(kind.title(), kind)
    for key, value in settings.items():
        setattr(mod, key, value)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def assign_skin_materials(skin):
    mats = [material("Wet pale skin", (0.55, 0.56, 0.52), 0.35), material("Mouth interior", (0.08, 0.025, 0.03), 0.4),
        material("Gum tissue", (0.3, 0.09, 0.09), 0.35)]
    skin.data.materials.clear()
    for mat in mats:
        skin.data.materials.append(mat)
    for poly in skin.data.polygons:
        c = poly.center
        if MOUTH_BACK_Y - 0.02 < c.y < MOUTH_FRONT.y + 0.4 and c.y > -2.2:
            if MOUTH_BACK_Y - 0.02 < c.y < MOUTH_FRONT.y + 0.01:
                gap = abs(c.z - mouth_z(c.y))
                if gap < 0.014 and abs(c.x) < mouth_half(c.y) + 0.005:
                    poly.material_index = 1
                elif gap < 0.03 and abs(c.x) < mouth_half(c.y) + 0.03:
                    poly.material_index = 2


BONES = {}


def build_rig():
    data = bpy.data.armatures.new("Listener rig")
    rig = bpy.data.objects.new("Listener rig", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}

    def bone(name, head, tail, parent=None):
        eb = data.edit_bones.new(name)
        eb.head, eb.tail = head, tail
        eb.roll = 0.0
        if parent:
            eb.parent = bones[parent]
            eb.use_connect = False
        bones[name] = eb
        BONES[name] = (Vector(head), Vector(tail))

    bone("Pelvis", HIPS, WAIST)
    bone("Spine", WAIST, CHEST, "Pelvis")
    bone("Chest", CHEST, NECK_BASE, "Spine")
    bone("Neck1", NECK_BASE, NECK_MID, "Chest")
    bone("Neck2", NECK_MID, NECK_TOP, "Neck1")
    bone("Head", NECK_TOP, SNOUT, "Neck2")
    bone("Jaw", Vector((0, -1.62, -0.08)), Vector((0, -2.1, -0.13)), "Head")
    for suffix, side in (("L", -1), ("R", 1)):
        hinge, rays = ear_rays(side)
        bone("Ear" + suffix, hinge, rays[3][2], "Head")
        for n, (a, m, b) in enumerate(rays):
            bone("Ear%s%d" % (suffix, n), a, b, "Ear" + suffix)
        shoulder, elbow, wrist, palm = arm_points(side)
        bone("UpperArm" + suffix, shoulder, elbow, "Chest")
        bone("Forearm" + suffix, elbow, wrist, "UpperArm" + suffix)
        bone("Hand" + suffix, wrist, palm + Vector((0, -0.25, -0.04)), "Forearm" + suffix)
    tail_parent = "Pelvis"
    for i in range(4):
        bone("Tail%d" % (i + 1), TAIL[i], TAIL[i + 1], tail_parent)
        tail_parent = "Tail%d" % (i + 1)
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def bind_fixed(obj, rig, weights):
    for name, w in weights.items():
        group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
        group.add([v.index for v in obj.data.vertices], w, "REPLACE")
    obj.parent = rig
    obj.modifiers.new("Armature", "ARMATURE").object = rig


def bind_skin(skin, rig):
    """Heat-diffusion weights for the body, then the parts that must move as
    one piece are made rigid: the skull (and the jaw below the mouth), each
    ear, each hand."""
    bpy.ops.object.select_all(action="DESELECT")
    skin.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    # The ear rays are weighted by hand below; left in, their thin bones
    # make the heat solve fail for the whole body.
    rays = [b for b in rig.data.bones if b.name[:-1] in ("EarL", "EarR")]
    for b in rays:
        b.use_deform = False
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in rays:
        b.use_deform = True
    groups = {g.name: g for g in skin.vertex_groups}
    for name in BONES:
        if name not in groups:
            groups[name] = skin.vertex_groups.new(name=name)
    ears = {"EarL": ear_rays(-1), "EarR": ear_rays(1)}
    for v in skin.data.vertices:
        p = v.co
        rigid = None
        for name, (hinge, rays) in ears.items():
            if (p - hinge).length < 0.06:
                rigid = {name: 1.0}
            else:
                gaps = [segment_distance(p, a, b) for a, _, b in rays]
                if min(gaps) < 0.035:
                    # Shared between the nearest rays, so the bone web at the
                    # root stretches smoothly as the rays fan apart; near the
                    # hinge some of it stays with the ear itself.
                    near = sorted(range(len(gaps)), key=gaps.__getitem__)[:2]
                    pull = [1.0 / max(gaps[n], 0.002) ** 3 for n in near]
                    total = sum(pull)
                    root = smoothstep(0.16, 0.06, (p - hinge).length)
                    rigid = {"%s%d" % (name, n): (1.0 - root) * w / total for n, w in zip(near, pull)}
                    rigid[name] = root
        if rigid is None:
            for suffix in ("L", "R"):
                wrist, tip = BONES["Hand" + suffix]
                if (p - wrist).length < 0.42 and segment_distance(p, wrist, tip) + 0.01 < segment_distance(p, *BONES["Forearm" + suffix]):
                    rigid = {"Hand" + suffix: 1.0}
        if rigid is None and abs(p.x) < 0.2:
            # Everything forward of the neck joint is head, blending over 8 cm.
            share = smoothstep(NECK_TOP.y + 0.05, NECK_TOP.y - 0.03, p.y)
            if share > 0.0:
                jaw = smoothstep(mouth_z(p.y) + 0.004, mouth_z(p.y) - 0.02, p.z) if p.y < -1.58 else 0.0
                rigid = {"Head": share * (1.0 - jaw), "Jaw": share * jaw}
                keep = 1.0 - share
                if keep > 0.0:
                    for g in v.groups:
                        name = skin.vertex_groups[g.group].name
                        if name not in ("Head", "Jaw"):
                            rigid[name] = rigid.get(name, 0.0) + g.weight * keep
        if rigid is None:
            # Only the ears themselves move with the ear bones.
            stray = [g.group for g in v.groups if skin.vertex_groups[g.group].name.startswith("Ear")]
            if stray and len(stray) < len(v.groups):
                for group in stray:
                    skin.vertex_groups[group].remove([v.index])
            continue
        for g in list(v.groups):
            skin.vertex_groups[g.group].remove([v.index])
        for name, w in rigid.items():
            if w > 0.002:
                groups[name].add([v.index], w, "REPLACE")


def smooth_weights(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.3, repeat=1)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def main():
    reset_scene()
    skin, claws = build_skin()
    assign_skin_materials(skin)
    membranes = build_membranes()
    teeth = build_teeth()
    claw_meshes = build_claws(claws)
    rig = build_rig()
    bind_skin(skin, rig)
    smooth_weights(skin)
    for membrane in membranes:
        membrane.parent = rig
        membrane.modifiers.new("Armature", "ARMATURE").object = rig
    bind_fixed(teeth["Upper teeth"], rig, {"Head": 1.0})
    bind_fixed(teeth["Lower teeth"], rig, {"Jaw": 1.0})
    bind_fixed(claw_meshes["L"], rig, {"HandL": 1.0})
    bind_fixed(claw_meshes["R"], rig, {"HandR": 1.0})
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True, export_animations=False,
        export_skins=True, export_yup=True, export_apply=False)
    print("exported", GLB)


main()
