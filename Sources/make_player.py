"""Rebuild assets/characters/player.glb, the body you see when you look down.

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_player.py

Like the creature, the body is one signed distance field meshed with OpenVDB,
so the jacket, jeans, boots and hands are one continuous surface with the same
level of detail everywhere. The head is a second surface, so your own view can
keep it as a shadow while other players see it. Fingers have two bones each so
the hands can close around what they hold.

Blender is Z-up; the body faces +Y here, which glTF turns into Godot's -Z, the
way the player faces. Feet stand at z = 0.
"""

from math import cos, pi, sin, sqrt
from pathlib import Path

import bmesh
import bpy
import numpy as np
import openvdb
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
GLB = ROOT / "assets/characters/player.glb"
BLEND = ROOT / "Sources/player.blend"
VOXEL = 0.0028

# Shared with scripts/player_body.gd, which solves the limbs to these lengths.
THIGH, SHIN = 0.46, 0.45
UPPER_ARM, FOREARM = 0.31, 0.27

FORWARD = Vector((0, 1, 0))
HIP_Z = 0.98
HIP_SPAN = 0.095
SHOULDER = Vector((0.19, -0.02, 1.575))
NECK_BASE = Vector((0, -0.01, 1.64))
HEAD_PIVOT = Vector((0, 0.0, 1.765))
HEAD_TOP = Vector((0, 0.0, 1.985))
FINGERS = (("Index", 0.028, 0.074), ("Middle", 0.009, 0.081), ("Ring", -0.01, 0.076), ("Pinky", -0.027, 0.061))


def joint(start, end, bend, first, second):
    span = end - start
    distance = min(max(span.length, 0.001), first + second - 0.002)
    direction = span.normalized()
    forward = (first * first + distance * distance - second * second) / (2 * distance)
    side = (bend - direction * bend.dot(direction)).normalized()
    return start + direction * forward + side * sqrt(max(0.0, first * first - forward * forward))


def leg(side):
    hip = Vector((side * HIP_SPAN, 0.0, HIP_Z))
    ankle = Vector((side * 0.105, -0.015, 0.085))
    knee = joint(hip, ankle, Vector((0, 1, 0)), THIGH, SHIN)
    toe = Vector((side * 0.112, 0.175, 0.035))
    return hip, knee, ankle, toe


def arm(side):
    shoulder = Vector((side * SHOULDER.x, SHOULDER.y, SHOULDER.z))
    elbow = shoulder + Vector((side * 0.42, -0.01, -0.91)).normalized() * UPPER_ARM
    wrist = elbow + Vector((side * 0.3, 0.08, -0.95)).normalized() * FOREARM
    return shoulder, elbow, wrist


def hand_frame(side):
    """Axis down the hand, across it (towards the thumb) and out of the palm."""
    shoulder, elbow, wrist = arm(side)
    along = (wrist - elbow).normalized()
    across = (FORWARD - along * FORWARD.dot(along)).normalized()
    palm = along.cross(across) * side
    return wrist, along, across, palm


def finger_points(side, curl=0.22):
    wrist, along, across, palm = hand_frame(side)
    out = {}
    for name, offset, length in FINGERS:
        knuckle = wrist + along * 0.093 + across * offset - palm * 0.003
        first = (along * cos(curl) + palm * sin(curl)).normalized()
        middle = knuckle + first * length * 0.56
        second = (along * cos(curl * 2.2) + palm * sin(curl * 2.2)).normalized()
        tip = middle + second * length * 0.44
        out[name] = (knuckle, middle, tip)
    root = wrist + along * 0.03 + across * 0.026 + palm * 0.008
    first = (along * 0.5 + across * 0.75 + palm * 0.35).normalized()
    middle = root + first * 0.042
    second = (along * 0.8 + across * 0.3 + palm * 0.45).normalized()
    out["Thumb"] = (root, middle, middle + second * 0.034)
    return out


# Distance field -----------------------------------------------------------

class Field:
    def __init__(self, low, high):
        self.low = np.array(low, dtype=np.float64)
        self.shape = tuple(int(np.ceil((h - l) / VOXEL)) + 1 for l, h in zip(low, high))
        self.d = np.full(self.shape, 0.25, dtype=np.float32)

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

    def ellipsoid(self, center, radii, k, subtract=False):
        c = np.array(center)
        r = np.array(radii)

        def sdf(x, y, z):
            lx, ly, lz = (x - c[0]) / r[0], (y - c[1]) / r[1], (z - c[2]) / r[2]
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

    def torus(self, center, ring, tube, k, squash=1.0):
        """A ring lying flat (around Z), squashed front to back by squash."""
        c = np.array(center)

        def sdf(x, y, z):
            px, py, pz = x - c[0], (y - c[1]) / squash, z - c[2]
            q = np.sqrt(px * px + py * py) - ring
            return np.sqrt(q * q + pz * pz) - tube

        reach = ring + tube
        self.add(sdf, c - reach, c + reach, k)

    def chain(self, points, radii, k):
        for i in range(len(points) - 1):
            self.capsule(points[i], points[i + 1], radii[i], radii[i + 1], k)

    def mesh(self, name):
        grid = openvdb.FloatGrid(0.25)
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


def build_body():
    f = Field((-0.62, -0.24, -0.02), (0.62, 0.3, 1.78))
    # Jeans: hips, thighs, knees, calves, and a hem over the boot.
    f.ellipsoid((0, -0.005, HIP_Z + 0.01), (0.165, 0.112, 0.12), 0.05)
    for side in (-1, 1):
        hip, knee, ankle, toe = leg(side)
        f.capsule(hip + Vector((0, 0, 0.03)), knee, 0.088, 0.061, 0.05)
        f.ellipsoid(hip.lerp(knee, 0.35) + Vector((side * 0.008, 0.004, 0)), (0.078, 0.082, 0.13), 0.04)
        f.ellipsoid(knee + Vector((0, 0.012, 0.0)), (0.056, 0.056, 0.05), 0.03)
        calf = knee.lerp(ankle, 0.3)
        f.capsule(knee, ankle + Vector((0, 0, 0.06)), 0.058, 0.047, 0.03)
        f.ellipsoid(calf + Vector((0, -0.016, 0)), (0.054, 0.058, 0.1), 0.03)
        hem = ankle + Vector((0, 0, 0.085))
        f.capsule(hem + Vector((0, 0, -0.015)), hem + Vector((0, 0, 0.012)), 0.056, 0.053, 0.008)
        # Boots: a high ankle, a broad toe and a thick sole with a heel.
        f.capsule(ankle + Vector((0, 0, -0.04)), ankle + Vector((0, 0, 0.07)), 0.055, 0.05, 0.02)
        heel = Vector((ankle.x, -0.055, 0.045))
        f.capsule(heel, toe - Vector((0, 0.02, 0)), 0.045, 0.039, 0.035)
        f.ellipsoid(toe + Vector((0, -0.03, 0.0)), (0.043, 0.052, 0.032), 0.03)
        f.ellipsoid(Vector((ankle.x, 0.05, 0.016)), (0.052, 0.14, 0.017), 0.012)
        f.ellipsoid(Vector((ankle.x, -0.05, 0.022)), (0.052, 0.05, 0.022), 0.01)
    # Belt.
    f.ellipsoid((0, -0.005, HIP_Z + 0.105), (0.172, 0.12, 0.024), 0.008)
    # Jacket: belly, chest, shoulders, a hem that sits out a little, pockets.
    f.ellipsoid((0, -0.002, 1.19), (0.165, 0.11, 0.14), 0.06)
    f.ellipsoid((0, 0.004, 1.4), (0.172, 0.112, 0.18), 0.07)
    f.ellipsoid((0, -0.02, 1.42), (0.16, 0.102, 0.17), 0.06)
    # Shoulders slope down from the neck instead of standing up like pads.
    for side in (-1, 1):
        f.capsule((side * 0.05, -0.015, 1.6), (side * 0.165, -0.02, 1.548), 0.055, 0.052, 0.05)
    f.ellipsoid((0, -0.004, 1.075), (0.178, 0.122, 0.035), 0.012)
    for side in (-1, 1):
        f.ellipsoid((side * 0.1, 0.104, 1.12), (0.055, 0.016, 0.05), 0.01)
    # Neck under a raised collar, open at the front.
    f.capsule(NECK_BASE + Vector((0, 0, -0.06)), NECK_BASE + Vector((0, 0.008, 0.11)), 0.066, 0.061, 0.02)
    f.torus((0, -0.012, 1.658), 0.08, 0.024, 0.02, squash=0.9)
    f.torus((0, -0.018, 1.69), 0.077, 0.02, 0.02, squash=0.9)
    f.torus((0, -0.022, 1.716), 0.075, 0.015, 0.015, squash=0.9)
    # The zip opening at the throat.
    f.capsule((0, 0.07, 1.6), (0, 0.075, 1.7), 0.018, 0.022, 0.01, subtract=True)
    # Sleeves with cuffs, then the hands.
    for side in (-1, 1):
        shoulder, elbow, wrist = arm(side)
        f.ellipsoid(shoulder + Vector((side * 0.006, 0, -0.01)), (0.058, 0.06, 0.06), 0.045)
        f.capsule(shoulder, elbow, 0.052, 0.043, 0.04)
        f.ellipsoid(elbow, (0.044, 0.044, 0.044), 0.025)
        f.capsule(elbow, wrist - (wrist - elbow).normalized() * 0.01, 0.043, 0.038, 0.03)
        cuff = wrist - (wrist - elbow).normalized() * 0.012
        f.capsule(cuff - (wrist - elbow).normalized() * 0.02, cuff, 0.042, 0.043, 0.006)
    obj = f.mesh("Body")
    finish(obj, 0.12)
    return obj


def build_hands():
    hands = []
    for side, suffix in ((-1, "L"), (1, "R")):
        wrist, along, across, palm = hand_frame(side)
        center = wrist + along * 0.06
        f = Field(tuple(center - Vector((0.13, 0.13, 0.13))), tuple(center + Vector((0.13, 0.13, 0.13))))
        build_hand(f, side)
        obj = f.mesh("Skin hand " + suffix)
        finish(obj, 0.35)
        hands.append(obj)
    return hands


def build_hand(f, side):
    wrist, along, across, palm = hand_frame(side)
    f.capsule(wrist - along * 0.02, wrist + along * 0.03, 0.026, 0.03, 0.015)
    center = wrist + along * 0.055
    # The palm as a few overlapping pads, thicker at the heel and thumb.
    for shift, radii in ((0.0, (0.036, 0.04, 0.016)), (0.022, (0.034, 0.03, 0.014))):
        p = center + along * shift
        rotation = Matrix((across, along, palm)).transposed()
        add_oriented_ellipsoid(f, p, radii, rotation, 0.012)
    add_oriented_ellipsoid(f, wrist + along * 0.035 + across * 0.022 + palm * 0.006, (0.018, 0.026, 0.016),
        Matrix((across, along, palm)).transposed(), 0.012)
    for name, points in finger_points(side).items():
        thumb = name == "Thumb"
        r0, r1, r2 = (0.0115, 0.0098, 0.0078) if thumb else (0.0096, 0.0085, 0.0068)
        f.chain(list(points), [r0, r1, r2], 0.004)
        f.ellipsoid(points[1], (r1 * 1.05,) * 3, 0.004)
        # A knuckle bump on the back of the hand.
        if not thumb:
            f.ellipsoid(points[0] - palm * 0.004, (0.0108, 0.0105, 0.0098), 0.006)


def add_oriented_ellipsoid(f, center, radii, rotation, k):
    c = np.array(center)
    r = np.array(radii)
    m = np.array(rotation)

    def sdf(x, y, z):
        px, py, pz = x - c[0], y - c[1], z - c[2]
        lx = (m[0, 0] * px + m[1, 0] * py + m[2, 0] * pz) / r[0]
        ly = (m[0, 1] * px + m[1, 1] * py + m[2, 1] * pz) / r[1]
        lz = (m[0, 2] * px + m[1, 2] * py + m[2, 2] * pz) / r[2]
        k0 = np.sqrt(lx * lx + ly * ly + lz * lz)
        k1 = np.sqrt((lx / r[0]) ** 2 + (ly / r[1]) ** 2 + (lz / r[2]) ** 2)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)

    reach = r.max()
    f.add(sdf, c - reach, c + reach, k)


def head_field():
    """Skull, face, jaw and neck: the surface hair and beard grow from."""
    f = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    # Neck, with a hint of an Adam's apple.
    f.capsule((0, -0.015, 1.62), (0, -0.006, 1.8), 0.064, 0.057, 0.03)
    f.ellipsoid((0, 0.043, 1.735), (0.012, 0.01, 0.014), 0.012)
    # Skull and the mass of the face.
    f.ellipsoid((0, -0.012, 1.905), (0.077, 0.095, 0.088), 0.03)
    f.ellipsoid((0, 0.035, 1.852), (0.066, 0.068, 0.075), 0.035)
    # Jaw: from each angle below the ear round to the chin.
    for side in (-1, 1):
        f.capsule((side * 0.056, -0.004, 1.81), (side * 0.03, 0.06, 1.783), 0.022, 0.02, 0.025)
    f.capsule((-0.03, 0.06, 1.783), (0.03, 0.06, 1.783), 0.02, 0.02, 0.02)
    f.ellipsoid((0, 0.073, 1.779), (0.022, 0.016, 0.016), 0.015)
    # Cheekbones and a continuous brow ridge.
    for side in (-1, 1):
        f.ellipsoid((side * 0.05, 0.063, 1.86), (0.022, 0.02, 0.015), 0.018)
    f.capsule((-0.05, 0.08, 1.898), (0.05, 0.08, 1.898), 0.008, 0.008, 0.022)
    return f


def build_head():
    f = head_field()
    # Eye sockets under the brow.
    for side in (-1, 1):
        f.ellipsoid((side * 0.032, 0.094, 1.877), (0.019, 0.013, 0.012), 0.01, subtract=True)
        # Lids wrapping the eye.
        f.ellipsoid((side * 0.032, 0.0865, 1.8855), (0.0165, 0.011, 0.0058), 0.003)
        f.ellipsoid((side * 0.032, 0.0858, 1.869), (0.0145, 0.0088, 0.0038), 0.003)
    # Nose: bridge, tip, the wings either side, and nostrils.
    f.capsule((0, 0.091, 1.888), (0, 0.111, 1.851), 0.0075, 0.011, 0.01)
    f.ellipsoid((0, 0.113, 1.848), (0.012, 0.0115, 0.0115), 0.008)
    for side in (-1, 1):
        f.ellipsoid((side * 0.0118, 0.103, 1.846), (0.0088, 0.0085, 0.007), 0.006)
        f.ellipsoid((side * 0.0068, 0.109, 1.8405), (0.0035, 0.0036, 0.0026), 0.002, subtract=True)
    # Mouth: upper and lower lip, parted by a thin line.
    f.ellipsoid((0, 0.0955, 1.822), (0.021, 0.0062, 0.005), 0.007)
    f.ellipsoid((0, 0.093, 1.81), (0.018, 0.0068, 0.0058), 0.007)
    f.ellipsoid((0, 0.099, 1.8158), (0.02, 0.005, 0.001), 0.002, subtract=True)
    # Ears, close to the head, with the bowl cut in.
    for side in (-1, 1):
        f.ellipsoid((side * 0.078, -0.006, 1.87), (0.0105, 0.021, 0.029), 0.01)
        f.ellipsoid((side * 0.083, -0.003, 1.868), (0.005, 0.012, 0.017), 0.005, subtract=True)
    obj = f.mesh("Head skin")
    finish(obj, 0.3)
    return obj


def grown_layer(name, region, thickness, ratio, extra=None):
    """A thin layer lying on the head's surface, kept only inside region (a
    Field whose negative side is where the layer belongs)."""
    head = head_field()
    # Lifted just off the skin, so the two surfaces never fight.
    shell = np.abs(head.d - (thickness * 0.5 + 0.0015)) - thickness * 0.5
    layer = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    layer.d = np.maximum(shell, region.d)
    if extra:
        extra(layer)
    obj = layer.mesh(name)
    finish(obj, ratio)
    return obj


def build_hair():
    """Short hair lying close to the skull, a natural hairline, eyebrows."""
    region = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    region.d[:] = 0.25
    # Where hair grows: the top and back of the skull, down to the ears.
    region.ellipsoid((0, -0.03, 1.935), (0.1, 0.13, 0.085), 0.02)
    region.ellipsoid((0, 0.11, 1.85), (0.115, 0.085, 0.085), 0.02, subtract=True)
    for side in (-1, 1):
        region.ellipsoid((side * 0.085, 0.0, 1.85), (0.03, 0.05, 0.048), 0.015, subtract=True)

    def brows(layer):
        layer.ellipsoid((0, 0.025, 1.975), (0.05, 0.05, 0.016), 0.02)
        for side in (-1, 1):
            layer.capsule((side * 0.014, 0.095, 1.8955), (side * 0.049, 0.088, 1.8935), 0.0055, 0.0042, 0.003)

    return grown_layer("Hair", region, 0.006, 0.6, brows)


def build_beard():
    """A short grey beard along the jaw and over the lip, only on the stranger."""
    region = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    region.d[:] = 0.25
    region.ellipsoid((0, 0.04, 1.796), (0.082, 0.088, 0.044), 0.015)
    # A light moustache over the lip.
    region.ellipsoid((0, 0.1, 1.829), (0.024, 0.02, 0.006), 0.006)
    # Bare cheeks, a clear mouth, and nothing down the neck.
    region.ellipsoid((0, 0.1, 1.853), (0.082, 0.07, 0.026), 0.012, subtract=True)
    region.ellipsoid((0, 0.11, 1.8155), (0.023, 0.03, 0.0088), 0.003, subtract=True)
    region.capsule((0, -0.02, 1.62), (0, 0.02, 1.765), 0.075, 0.05, 0.01, subtract=True)
    return grown_layer("Beard", region, 0.0032, 0.6)


def build_eyes():
    eyes = []
    for side in (-1, 1):
        for title, radius, at in (("Eye", 0.0115, (side * 0.032, 0.0795, 1.877)), ("Iris", 0.0056, (side * 0.032, 0.0902, 1.877))):
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=radius)
            mesh = bpy.data.meshes.new(title)
            bm.to_mesh(mesh)
            bm.free()
            if title == "Iris":
                mesh.transform(Matrix.Diagonal((1.0, 0.35, 1.0, 1.0)))
            mesh.transform(Matrix.Translation(at))
            obj = bpy.data.objects.new(title, mesh)
            bpy.context.scene.collection.objects.link(obj)
            mesh.shade_smooth()
            eyes.append(obj)
    return eyes


def finish(obj, ratio):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=VOXEL * 0.05)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    apply_modifier(obj, "LAPLACIANSMOOTH", iterations=2, lambda_factor=0.5, use_volume_preserve=True)
    apply_modifier(obj, "DECIMATE", ratio=ratio)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.shade_smooth()
    print(obj.name, "verts", len(obj.data.vertices))


def apply_modifier(obj, kind, **settings):
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new(kind.title(), kind)
    for key, value in settings.items():
        setattr(mod, key, value)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def material(name, color, roughness):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    return mat


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def beyond_wrist(p, side):
    shoulder, elbow, wrist = arm(side)
    along = (wrist - elbow).normalized()
    return (p - wrist).dot(along)


def paint(body, head, hair, beard, hands, eyes):
    jacket = material("Jacket", (0.16, 0.18, 0.13), 0.86)
    jeans = material("Jeans", (0.1, 0.12, 0.17), 0.9)
    boots = material("Boots", (0.075, 0.058, 0.045), 0.55)
    skin = material("Skin", (0.4, 0.25, 0.18), 0.84)
    lips = material("Lips", (0.44, 0.25, 0.21), 0.7)
    beard_mat = material("Beard", (0.24, 0.22, 0.2), 0.95)
    hair_mat = material("Hair", (0.06, 0.045, 0.032), 0.93)
    eye = material("Eye white", (0.78, 0.75, 0.7), 0.25)
    iris = material("Iris", (0.06, 0.07, 0.05), 0.15)
    for mat in (jacket, jeans, boots, skin):
        body.data.materials.append(mat)
    for poly in body.data.polygons:
        c = poly.center
        side = 1 if c.x > 0 else -1
        if c.z > 1.735 or (c.z > 1.6 and abs(c.x) < 0.035 and c.y > 0.06):
            poly.material_index = 3
        elif c.z < 0.155:
            poly.material_index = 2
        elif c.z < HIP_Z + 0.09 and (abs(c.x) < 0.2 or c.z < 0.9):
            poly.material_index = 1
        elif abs(c.z - (HIP_Z + 0.105)) < 0.022 and abs(c.x) < 0.2:
            poly.material_index = 2
        else:
            poly.material_index = 0
    head.data.materials.append(skin)
    head.data.materials.append(lips)
    for poly in head.data.polygons:
        c = poly.center
        upper = Vector(((c.x) / 0.021, (c.y - 0.097) / 0.009, (c.z - 1.822) / 0.0062)).length
        lower = Vector(((c.x) / 0.018, (c.y - 0.094) / 0.0095, (c.z - 1.809) / 0.0072)).length
        if min(upper, lower) < 1.15 and c.y > 0.09:
            poly.material_index = 1
    hair.data.materials.append(hair_mat)
    beard.data.materials.append(beard_mat)
    for obj in hands:
        obj.data.materials.append(skin)
    for obj in eyes:
        obj.data.materials.append(iris if obj.name.startswith("Iris") else eye)


def build_rig():
    data = bpy.data.armatures.new("Player rig")
    rig = bpy.data.objects.new("Player rig", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}

    def bone(name, head, tail, parent=None):
        eb = data.edit_bones.new(name)
        eb.head, eb.tail = head, tail
        if parent:
            eb.parent = bones[parent]
        bones[name] = eb

    bone("Hips", Vector((0, 0, HIP_Z)), Vector((0, 0, 1.12)))
    bone("Spine", Vector((0, 0, 1.12)), Vector((0, -0.005, 1.4)), "Hips")
    bone("Chest", Vector((0, -0.005, 1.4)), NECK_BASE, "Spine")
    bone("Neck", NECK_BASE, HEAD_PIVOT, "Chest")
    bone("Head", HEAD_PIVOT, HEAD_TOP, "Neck")
    for suffix, side in (("L", -1), ("R", 1)):
        hip, knee, ankle, toe = leg(side)
        bone("Thigh" + suffix, hip, knee, "Hips")
        bone("Shin" + suffix, knee, ankle, "Thigh" + suffix)
        bone("Foot" + suffix, ankle, toe, "Shin" + suffix)
        shoulder, elbow, wrist = arm(side)
        bone("UpperArm" + suffix, shoulder, elbow, "Chest")
        bone("Forearm" + suffix, elbow, wrist, "UpperArm" + suffix)
        _, along, _, _ = hand_frame(side)
        bone("Hand" + suffix, wrist, wrist + along * 0.09, "Forearm" + suffix)
        for name, (a, b, c) in finger_points(side).items():
            bone(name + "1" + suffix, a, b, "Hand" + suffix)
            bone(name + "2" + suffix, b, c, name + "1" + suffix)
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


BONE_RADIUS = {"Hips": 0.13, "Spine": 0.13, "Chest": 0.15, "Neck": 0.05,
    "UpperArm": 0.055, "Forearm": 0.043, "Thigh": 0.075, "Shin": 0.05}


def skin_body(obj, rig):
    bones = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
    groups = {name: obj.vertex_groups.new(name=name) for name in bones}
    hand_parts = {}
    for suffix in ("L", "R"):
        hand_parts[suffix] = [n for n in bones if n.endswith(suffix) and (n.startswith("Hand") or n[:-2] in
            ("Index", "Middle", "Ring", "Pinky", "Thumb"))]
    for v in obj.data.vertices:
        p = v.co
        side = 1 if p.x > 0 else -1
        suffix = "R" if side > 0 else "L"
        weights = {}
        # Hands and fingers are rigid pieces, each on its nearest bone.
        hand_share = 0.0
        # Feet: everything low in the boot.
        foot_share = smoothstep(0.17, 0.11, p.z)
        if hand_share > 0:
            ranked = sorted(((segment_distance(p, *bones[n]) - (0.012 if n.startswith("Hand") else 0.0), n)
                for n in hand_parts[suffix]))
            weights[ranked[0][1]] = hand_share
        distances = {}
        for name, (a, b) in bones.items():
            base = name.rstrip("LR") if name[-1] in "LR" and name[:-1] in ("Thigh", "Shin", "UpperArm", "Forearm") else name
            if base in BONE_RADIUS:
                distances[name] = max(segment_distance(p, a, b) - BONE_RADIUS[base], 0.002)
        ranked = sorted(distances.items(), key=lambda item: item[1])[:3]
        total = sum(1.0 / max(d, 0.0005) ** 6 for _, d in ranked)
        body_share = (1.0 - hand_share) * (1.0 - foot_share)
        for name, d in ranked:
            weights[name] = weights.get(name, 0.0) + (1.0 / max(d, 0.0005) ** 6) / total * body_share
        if foot_share > 0:
            weights["Foot" + suffix] = weights.get("Foot" + suffix, 0.0) + foot_share * (1.0 - hand_share)
        for name, w in weights.items():
            if w > 0.002:
                groups[name].add([v.index], w, "REPLACE")
    attach(obj, rig)


def skin_hand(obj, rig, suffix):
    """Each piece of the hand rides rigidly on its nearest bone."""
    bones = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones
        if b.name.endswith(suffix) and (b.name.startswith("Hand") or b.name[:-2] in ("Index", "Middle", "Ring", "Pinky", "Thumb"))}
    groups = {name: obj.vertex_groups.new(name=name) for name in bones}
    for v in obj.data.vertices:
        ranked = sorted(((segment_distance(v.co, *bones[n]) - (0.014 if n.startswith("Hand") else 0.0), n) for n in bones))
        groups[ranked[0][1]].add([v.index], 1.0, "REPLACE")
    attach(obj, rig)


def skin_head(obj, rig):
    for name in ("Neck", "Head"):
        obj.vertex_groups.new(name=name)
    for v in obj.data.vertices:
        share = smoothstep(1.72, 1.78, v.co.z)
        if share < 0.998:
            obj.vertex_groups["Neck"].add([v.index], 1.0 - share, "REPLACE")
        if share > 0.002:
            obj.vertex_groups["Head"].add([v.index], share, "REPLACE")
    attach(obj, rig)


def attach(obj, rig, fixed=None):
    if fixed:
        group = obj.vertex_groups.new(name=fixed)
        group.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
    obj.parent = rig
    obj.modifiers.new("Armature", "ARMATURE").object = rig


def smooth_weights(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.4, repeat=2)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = build_body()
    hands = build_hands()
    head = build_head()
    hair = build_hair()
    beard = build_beard()
    eyes = build_eyes()
    # A slightly bigger head, so it doesn't look perched on a long neck.
    for obj in [head, hair, beard] + eyes:
        obj.data.transform(Matrix.Translation((0, 0, 1.74)) @ Matrix.Scale(1.07, 4) @ Matrix.Translation((0, 0, -1.74)))
    paint(body, head, hair, beard, hands, eyes)
    rig = build_rig()
    skin_body(body, rig)
    smooth_weights(body)
    for obj, suffix in zip(hands, ("L", "R")):
        skin_hand(obj, rig, suffix)
        smooth_weights(obj)
    skin_head(head, rig)
    attach(hair, rig, "Head")
    attach(beard, rig, "Head")
    for eye in eyes:
        attach(eye, rig, "Head")
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True, export_animations=False,
        export_skins=True, export_yup=True, export_apply=False)
    print("exported", GLB)


main()
