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

    def box(self, center, half, rotation=None, k=0.004, rounding=0.003, subtract=False):
        """A rounded box; rotation is a 3x3 whose columns are the box's axes."""
        c = np.array(center)
        h = np.array(half)
        m = np.array(rotation if rotation is not None else Matrix.Identity(3))

        def sdf(x, y, z):
            px, py, pz = x - c[0], y - c[1], z - c[2]
            lx = np.abs(m[0, 0] * px + m[1, 0] * py + m[2, 0] * pz) - h[0] + rounding
            ly = np.abs(m[0, 1] * px + m[1, 1] * py + m[2, 1] * pz) - h[1] + rounding
            lz = np.abs(m[0, 2] * px + m[1, 2] * py + m[2, 2] * pz) - h[2] + rounding
            outside = np.sqrt(np.maximum(lx, 0) ** 2 + np.maximum(ly, 0) ** 2 + np.maximum(lz, 0) ** 2)
            return outside + np.minimum(np.maximum(lx, np.maximum(ly, lz)), 0) - rounding

        reach = float(np.linalg.norm(h))
        self.add(sdf, c - reach, c + reach, k, subtract)

    def ring(self, center, axis, radius, tube, k, subtract=False, squash=1.0):
        """A torus around an arbitrary axis (squash scales one of its radii)."""
        c = np.array(center)
        a = Vector(axis).normalized()
        u = a.orthogonal().normalized()
        v = a.cross(u)
        A, U, Vv = np.array(a), np.array(u), np.array(v)

        def sdf(x, y, z):
            px, py, pz = x - c[0], y - c[1], z - c[2]
            pa = px * A[0] + py * A[1] + pz * A[2]
            pu = px * U[0] + py * U[1] + pz * U[2]
            pv = (px * Vv[0] + py * Vv[1] + pz * Vv[2]) / squash
            q = np.sqrt(pu * pu + pv * pv) - radius
            return np.sqrt(q * q + pa * pa) - tube

        reach = radius + tube
        self.add(sdf, c - reach, c + reach, k, subtract)

    def surface(self, start, direction, limit=0.4):
        """Where a ray from start along direction first meets the surface."""
        start = Vector(start)
        d = Vector(direction).normalized()
        steps = int(limit / (VOXEL * 0.5))
        for i in range(steps):
            p = start + d * (i * VOXEL * 0.5)
            idx = np.round((np.array(p) - self.low) / VOXEL).astype(int)
            if np.any(idx < 0) or np.any(idx >= self.shape):
                continue
            if self.d[tuple(idx)] < 0:
                return p
        return start

    def groove(self, points, radius=0.0028, depth=0.0012, k=0.002):
        """A stitched seam: a thin channel pressed into the surface along points
        (each found on the surface already)."""
        for a, b in zip(points, points[1:]):
            self.capsule(a, b, radius, radius, k, subtract=True)

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


FIELDS = {}


def front_of(f, x, z, y_from=0.3):
    return f.surface(Vector((x, y_from, z)), Vector((0, -1, 0)))


def back_of(f, x, z, y_from=-0.3):
    return f.surface(Vector((x, y_from, z)), Vector((0, 1, 0)))


def side_of(f, side, y, z, x_from=0.5):
    return f.surface(Vector((side * x_from, y, z)), Vector((-side, 0, 0)))


def tilt_to(normal):
    """A rotation whose third column faces along normal, first column level."""
    n = Vector(normal).normalized()
    across = Vector((0, 0, 1)).cross(n)
    if across.length < 1e-4:
        across = Vector((1, 0, 0))
    across.normalize()
    up = n.cross(across)
    return Matrix((across, up, n)).transposed()


def torso(f, grow=0.0, hem_z=1.115, collar=True):
    """The jacket's shape: a flat-fronted chest and back with a real shoulder
    line (trapezius sloping off the neck into the deltoids), straight sides
    down to a hem band."""
    g = grow
    f.box(Vector((0, -0.01, 1.43)), (0.152 + g, 0.096 + g, 0.16), None, 0.03, 0.075)
    f.box(Vector((0, -0.006, 1.24)), (0.148 + g, 0.1 + g, 0.13), None, 0.04, 0.075)
    # Chest and shoulder blades, just enough to shape the cloth.
    for side in (-1, 1):
        f.ellipsoid((side * 0.07, 0.06, 1.47), (0.06, 0.03, 0.05), 0.03)
        f.ellipsoid((side * 0.075, -0.085, 1.46), (0.06, 0.025, 0.07), 0.03)
        f.capsule((side * 0.045, -0.02, 1.64), (side * 0.165, -0.02, 1.575), 0.045 + g, 0.05 + g, 0.04)
        f.ellipsoid((side * 0.19, -0.018, 1.55), (0.056 + g, 0.058 + g, 0.055 + g), 0.03)
    f.box(Vector((0, -0.004, hem_z + 0.07)), (0.15 + g, 0.104 + g, 0.075), None, 0.03, 0.06)
    f.torus((0, -0.004, hem_z), 0.15 + g, 0.01, 0.005, squash=0.72)


def sleeves(f, grow=0.0, cuff=True):
    """Sleeves with an adult arm inside: full over the biceps, a little
    narrower at the elbow, the forearm swelling below it, cuffs at the wrist."""
    g = grow
    for side in (-1, 1):
        shoulder, elbow, wrist = arm(side)
        along = (wrist - elbow).normalized()
        upper = (elbow - shoulder).normalized()
        f.capsule(shoulder, elbow, 0.058 + g, 0.051 + g, 0.03)
        f.ellipsoid(elbow, (0.051 + g,) * 3, 0.02)
        end = wrist - along * 0.012
        f.capsule(elbow, end - along * 0.03, 0.055 + g, 0.046 + g, 0.02)
        f.ellipsoid(elbow.lerp(wrist, 0.3), (0.052 + g, 0.052 + g, 0.07 + g), 0.03)
        if cuff:
            f.capsule(end - along * 0.05, end, 0.048 + g, 0.049 + g, 0.004)
            f.ring(end - along * 0.052, along, 0.048 + g, 0.0026, 0.002, subtract=True)
        for t in (-0.02, 0.0, 0.022):
            f.ring(elbow + along * t + Vector((0, 0.03, 0)), along, 0.05 + g, 0.003, 0.004, subtract=True, squash=0.5)
        # The seam down the back of the sleeve.
        f.groove([f.surface(shoulder.lerp(wrist, t) - Vector((0, 0.3, 0)), Vector((0, 1, 0))) for t in (0.1, 0.35, 0.6, 0.85)], 0.0022)


def flat_collar(f, neck_radius=0.072, fall=0.055, front_gap=0.42, z_back=1.7, z_front=1.62, thick=0.006, lapel=False):
    """A shirt-style collar: a low stand round the neck and a fall folded
    flat over it onto the shoulders, open at the front with pointed ends."""
    pieces = 18
    for i in range(pieces):
        a = -pi + (i + 0.5) / pieces * 2 * pi   # 0 at the front (+Y)
        if abs(a) < front_gap:
            continue
        out = Vector((sin(a), cos(a), 0))
        z = z_front + (z_back - z_front) * (abs(a) / pi) ** 0.7
        base = Vector((0, -0.012, 0)) + out * neck_radius + Vector((0, 0, z))
        # The fall leans out and down from the top of the stand.
        n = (out * 0.55 + Vector((0, 0, 1))).normalized()
        rot = tilt_to(n)
        f.box(base + out * fall * 0.45 - Vector((0, 0, fall * 0.25)), (2 * pi * neck_radius / pieces * 0.62, fall * 0.5, thick), rot, 0.006, 0.003)
        f.capsule(base - Vector((0, 0, 0.012)), base + Vector((0, 0, 0.004)), 0.007, 0.007, 0.006)
    for side in (-1, 1):
        a = side * front_gap
        out = Vector((sin(a), cos(a), 0))
        tip = Vector((0, -0.012, z_front - 0.055)) + out * (neck_radius + 0.03) + Vector((side * 0.012, 0.012, 0))
        root = Vector((0, -0.012, z_front)) + out * neck_radius
        n = (out * 0.8 + Vector((0, 0, 0.6))).normalized()
        f.box((root + tip) * 0.5, (0.018, (tip - root).length * 0.55, thick), tilt_to(n) @ Matrix.Rotation(side * 0.5, 3, "Z"), 0.006, 0.003)


def build_jacket():
    """A canvas work jacket: hem band, zip placket open at the throat, chest
    pockets with flaps, slash pockets, side and yoke seams, a flat folded
    collar, sleeves with cuffs."""
    f = Field((-0.48, -0.2, 1.0), (0.48, 0.22, 1.76))
    torso(f)
    sleeves(f)
    # Neck hole, and the zip left open from mid-chest up.
    f.capsule((0, -0.012, 1.6), (0, -0.012, 1.76), 0.066, 0.07, 0.01, subtract=True)
    f.capsule((0, 0.13, 1.5), (0, 0.13, 1.72), 0.004, 0.06, 0.006, subtract=True)
    flat_collar(f)
    zs = [1.115 + i * 0.04 for i in range(10)]
    line = [front_of(f, 0.0, z) for z in zs]
    for p, q in zip(line, line[1:]):
        f.capsule(p + Vector((0, 0.002, 0)), q + Vector((0, 0.002, 0)), 0.01, 0.01, 0.003)
    for x in (-0.013, 0.013):
        f.groove([front_of(f, x, z) for z in zs])
    for side in (-1, 1):
        at = front_of(f, side * 0.088, 1.42)
        n = (at - Vector((side * 0.03, 0.0, 1.42))).normalized()
        rot = tilt_to(n)
        f.box(at + n * 0.002, (0.043, 0.052, 0.005), rot, 0.003, 0.003)
        flap = front_of(f, side * 0.088, 1.475)
        f.box(flap + n * 0.006, (0.047, 0.016, 0.005), rot, 0.002, 0.003)
        f.groove([at + n * 0.006 + rot @ Vector((-0.036, -0.045, 0)), at + n * 0.006 + rot @ Vector((0.036, -0.045, 0))], 0.0016)
    for side in (-1, 1):
        a = front_of(f, side * 0.07, 1.25)
        b = side_of(f, side, 0.06, 1.16)
        f.capsule(a, b, 0.004, 0.004, 0.002, subtract=True)
        f.capsule(a + Vector((0, 0.004, 0.006)), b + Vector((side * 0.004, 0.0, 0.006)), 0.0035, 0.0035, 0.003)
    for side in (-1, 1):
        f.groove([side_of(f, side, -0.01, z) for z in (1.13, 1.22, 1.32, 1.42, 1.5)])
        f.groove([f.surface(Vector((side * x, -0.02, 1.8)), Vector((0, 0, -1))) for x in (0.09, 0.13, 0.17, 0.21)])
    f.groove([back_of(f, x, 1.5) for x in (-0.15, -0.1, -0.05, 0.0, 0.05, 0.1, 0.15)])
    f.ring((0, -0.004, 1.135), (0, 0, 1), 0.152, 0.0024, 0.002, subtract=True, squash=0.72)
    FIELDS["jacket"] = f
    obj = f.mesh("Jacket")
    finish(obj, 0.06, smooth=1)
    return obj


def build_tee(stranger=False):
    """The T-shirt showing at the open neck of the jacket; for the stranger,
    a flannel shirt open at the collar inside his coat."""
    f = Field((-0.18, -0.13, 1.25), (0.18, 0.15, 1.74))
    f.box(Vector((0, -0.002, 1.46)), (0.13, 0.078, 0.15), None, 0.02, 0.06)
    f.capsule((0, -0.012, 1.6), (0, -0.012, 1.76), 0.056, 0.058, 0.008, subtract=True)
    if stranger:
        f.capsule((0, 0.13, 1.56), (0, 0.13, 1.7), 0.003, 0.04, 0.005, subtract=True)
        for side in (-1, 1):
            root = Vector((side * 0.035, 0.05, 1.66))
            tip = Vector((side * 0.06, 0.1, 1.6))
            n = Vector((side * 0.3, 1.0, 0.5)).normalized()
            along_c = (tip - root).normalized()
            across = along_c.cross(n).normalized()
            n = across.cross(along_c)
            f.box((root + tip) * 0.5 + n * 0.004, (0.016, (tip - root).length * 0.55, 0.003), Matrix((across, along_c, n)).transposed(), 0.003, 0.002)
            f.capsule(Vector((side * 0.05, -0.04, 1.66)), root, 0.006, 0.006, 0.004)
        for z in (1.5, 1.42, 1.34):
            f.ellipsoid((0.006, front_of(f, 0.006, z).y + 0.002, z), (0.005, 0.002, 0.005), 0.001)
    else:
        f.ring((0, -0.012, 1.625), (0, 0, 1), 0.06, 0.005, 0.004, squash=1.05)
    obj = f.mesh("Stranger shirt" if stranger else "Shirt")
    finish(obj, 0.04, smooth=1)
    return obj


def build_jeans(name="Jeans"):
    """Straight-leg jeans: waistband with loops, fly and front pocket seams,
    back pockets, out-seams and rolled hems."""
    f = Field((-0.32, -0.2, 0.06), (0.32, 0.2, 1.14))
    f.ellipsoid((0, -0.005, 1.0), (0.168, 0.114, 0.16), 0.05)
    hems = []
    for side in (-1, 1):
        hip, knee, ankle, toe = leg(side)
        f.capsule(hip + Vector((0, 0, 0.03)), knee, 0.1, 0.068, 0.04)
        f.ellipsoid(hip.lerp(knee, 0.32) + Vector((side * 0.008, 0.004, 0)), (0.096, 0.1, 0.16), 0.04)
        f.capsule(knee, ankle + Vector((0, 0, 0.09)), 0.066, 0.06, 0.02)
        f.ellipsoid(knee.lerp(ankle, 0.3) + Vector((0, -0.012, 0)), (0.064, 0.068, 0.11), 0.03)
        hem = ankle + Vector((0, 0, 0.098))
        hems.append(hem)
        # Rolled hem.
        f.ring(hem, (0, 0, 1), 0.06, 0.012, 0.004)
        f.ring(hem + Vector((0, 0, 0.016)), (0, 0, 1), 0.062, 0.003, 0.002, subtract=True)
        # Wrinkles behind the knee and stacked over the boot.
        for dz in (-0.02, 0.0, 0.02):
            f.ring(knee + Vector((0, -0.04, dz)), (0, 0, 1), 0.07, 0.003, 0.004, subtract=True, squash=0.6)
        for dz in (0.14, 0.17):
            f.ring(ankle + Vector((0, 0.0, dz)), (0.1 * side, 0.2, 1), 0.063, 0.0025, 0.003, subtract=True)
        # Out-seam down the side of the leg.
        pts = [side_of(f, side, -0.005, z, 0.45) for z in (1.04, 0.9, 0.75, 0.6, 0.45, 0.3, 0.2)]
        f.groove(pts, 0.0024)
    # Waistband and its loops.
    f.ring((0, -0.005, 1.07), (0, 0, 1), 0.146, 0.014, 0.004, squash=0.74)
    f.ring((0, -0.005, 1.053), (0, 0, 1), 0.152, 0.0025, 0.002, subtract=True, squash=0.74)
    # Fly: a J of stitching down the front.
    fly = [front_of(f, 0.022, z) for z in (1.05, 1.01, 0.98, 0.95)] + [front_of(f, 0.008, 0.925), front_of(f, 0.0, 0.92)]
    f.groove(fly)
    f.groove([front_of(f, 0.0, z) for z in (1.05, 1.0, 0.93)], 0.002)
    # Front pocket openings, curving from the waistband to the side.
    for side in (-1, 1):
        f.groove([front_of(f, side * 0.075, 1.05), front_of(f, side * 0.105, 1.02), side_of(f, side, 0.06, 0.98, 0.4)], 0.003)
        # Back pockets: patches with a V of stitching.
        at = back_of(f, side * 0.075, 0.98)
        rot = tilt_to(Vector((side * 0.25, -1, 0.1)))
        f.box(at - Vector((0, 0.002, 0)), (0.05, 0.058, 0.005), rot, 0.002, 0.006)
        f.groove([at + rot @ Vector((-0.04, 0.03, 0.006)), at + rot @ Vector((0, 0.01, 0.006)), at + rot @ Vector((0.04, 0.03, 0.006))], 0.0016)
    FIELDS["jeans"] = f
    obj = f.mesh(name)
    finish(obj, 0.058, smooth=1)
    return obj


def build_belt():
    f = Field((-0.2, -0.16, 1.03), (0.2, 0.16, 1.11))
    f.ring((0, -0.005, 1.07), (0, 0, 1), 0.153, 0.012, 0.002, squash=0.74)
    f.ring((0, -0.005, 1.07), (0, 0, 1), 0.158, 0.0022, 0.002, subtract=True, squash=0.74)
    obj = f.mesh("Belt")
    finish(obj, 0.14, smooth=1)
    return obj


def build_boots():
    """Leather work boots: shaft, a toe box, tongue, pull tab, a stitched welt
    line; the soles and heels are their own object."""
    objs = []
    for side, suffix in ((-1, "L"), (1, "R")):
        hip, knee, ankle, toe = leg(side)
        x = ankle.x
        f = Field((x - 0.1, -0.13, 0.0), (x + 0.1, 0.25, 0.22))
        f.capsule(ankle + Vector((0, 0, -0.035)), ankle + Vector((0, 0, 0.095)), 0.058, 0.056, 0.015)
        heel = Vector((x, -0.052, 0.05))
        f.capsule(heel, toe - Vector((0, 0.03, 0)), 0.048, 0.042, 0.03)
        f.ellipsoid(toe + Vector((0, -0.028, 0.004)), (0.045, 0.055, 0.034), 0.02)
        # Tongue showing between the lacing.
        f.box(Vector((x, 0.045, 0.135)), (0.022, 0.01, 0.06), tilt_to(Vector((0, 1, 0.45))), 0.006, 0.006)
        # Pull tab at the back.
        f.box(Vector((x, -0.066, 0.18)), (0.012, 0.006, 0.024), None, 0.003, 0.003)
        # Toe-cap seam and the welt line above the sole.
        f.ring(toe + Vector((0, -0.055, 0.004)), (0, 1, 0.25), 0.04, 0.0022, 0.002, subtract=True, squash=0.8)
        f.ring(Vector((x, 0.06, 0.037)), (0, 0, 1), 0.05, 0.0022, 0.002, subtract=True, squash=2.9)
        obj = f.mesh("Boot " + suffix)
        finish(obj, 0.14, smooth=1)
        objs.append(obj)
        # Sole and heel: flat, hard-edged rubber.
        g = Field((x - 0.08, -0.13, -0.01), (x + 0.08, 0.25, 0.06))
        g.box(Vector((x, 0.058, 0.016)), (0.056, 0.152, 0.016), None, 0.004, 0.012)
        g.box(Vector((x, -0.055, 0.024)), (0.051, 0.045, 0.024), None, 0.004, 0.006)
        for i in range(9):
            g.box(Vector((x, -0.06 + i * 0.03, 0.0)), (0.06, 0.004, 0.004), None, 0.002, 0.002, subtract=True)
        obj = g.mesh("Sole " + suffix)
        finish(obj, 0.1, smooth=0)
        objs.append(obj)
    return objs


def bm_object(name, build):
    bm = bmesh.new()
    build(bm)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def cube(bm, center, size, rotation=None):
    m = Matrix.Translation(center) @ (rotation.to_4x4() if rotation else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def rod(bm, a, b, radius, sides=6):
    a, b = Vector(a), Vector(b)
    axis = b - a
    rot = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius, depth=axis.length,
        matrix=Matrix.Translation((a + b) * 0.5) @ rot)


def build_hardware(jacket_field, jeans_field):
    """Metal: the zip, pocket snaps, rivets, the belt buckle and boot eyelets."""
    def make(bm):
        zs = [1.12 + i * 0.012 for i in range(46)]
        for z in zs:
            p = jacket_field.surface(Vector((0, 0.3, z)), Vector((0, -1, 0)))
            cube(bm, p + Vector((0, 0.009, 0)), (0.007, 0.003, 0.005))
        pull = jacket_field.surface(Vector((0, 0.3, 1.62)), Vector((0, -1, 0)))
        cube(bm, pull + Vector((0, 0.013, -0.015)), (0.008, 0.003, 0.024))
        for side in (-1, 1):
            p = jacket_field.surface(Vector((side * 0.088, 0.3, 1.48)), Vector((0, -1, 0)))
            rod(bm, p + Vector((0, 0.006, 0)), p + Vector((0, 0.013, 0)), 0.006, 8)
            p = jeans_field.surface(Vector((side * 0.085, 0.3, 1.035)), Vector((0, -1, 0)))
            rod(bm, p, p + Vector((0, 0.006, 0)), 0.004, 6)
        # Buckle.
        cube(bm, Vector((0, 0.121, 1.07)), (0.05, 0.008, 0.034))
        cube(bm, Vector((0, 0.126, 1.07)), (0.034, 0.006, 0.019))
        # Eyelets up each boot.
        for side in (-1, 1):
            hip, knee, ankle, toe = leg(side)
            for i in range(5):
                z = 0.08 + i * 0.022
                for dx in (-0.022, 0.022):
                    rod(bm, Vector((ankle.x + dx, 0.052 - i * 0.004, z)), Vector((ankle.x + dx, 0.058 - i * 0.004, z)), 0.0045, 6)
    return bm_object("Hardware", make)


def build_laces():
    def make(bm):
        for side in (-1, 1):
            hip, knee, ankle, toe = leg(side)
            for i in range(4):
                z = 0.08 + i * 0.022
                y = 0.058 - i * 0.004
                rod(bm, Vector((ankle.x - 0.022, y, z)), Vector((ankle.x + 0.022, y, z + 0.022)), 0.0028, 5)
                rod(bm, Vector((ankle.x + 0.022, y, z)), Vector((ankle.x - 0.022, y, z + 0.022)), 0.0028, 5)
            top = Vector((ankle.x, 0.04, 0.175))
            rod(bm, top, top + Vector((0.025, 0.03, -0.05)), 0.0028, 5)
            rod(bm, top, top + Vector((-0.02, 0.028, -0.055)), 0.0028, 5)
    return bm_object("Laces", make)


def build_coat():
    """The stranger's coat: heavy wool to mid-thigh over everything, wide
    lapels, a row of buttons, flap pockets, turned-back cuffs."""
    f = Field((-0.5, -0.22, 0.7), (0.5, 0.24, 1.78))
    torso(f, grow=0.02, hem_z=1.18)
    sleeves(f, grow=0.014, cuff=False)
    # The skirt hangs from the waist to mid-thigh, open a little at the front.
    f.capsule((0, -0.008, 1.15), (0, -0.01, 0.76), 0.19, 0.205, 0.05)
    f.box(Vector((0, 0.22, 0.86)), (0.025, 0.06, 0.12), None, 0.01, 0.01, subtract=True)
    # Folds hanging down the skirt, and a collar turned up round the neck.
    for i in range(14):
        a = i / 14 * 2 * pi + 0.2
        top = Vector((0.2 * cos(a), -0.008 + 0.2 * sin(a), 1.02))
        bottom = Vector((0.215 * cos(a), -0.01 + 0.215 * sin(a), 0.74))
        f.capsule(top, bottom, 0.004, 0.012, 0.012, subtract=True)
    # Neck hole and the V where the coat lies open over the shirt.
    f.capsule((0, -0.014, 1.6), (0, -0.014, 1.78), 0.075, 0.08, 0.01, subtract=True)
    f.capsule((0, 0.155, 1.3), (0, 0.15, 1.72), 0.003, 0.085, 0.006, subtract=True)
    flat_collar(f, neck_radius=0.084, fall=0.065, front_gap=0.75, z_back=1.69, z_front=1.63, thick=0.007)
    for side in (-1, 1):
        shoulder, elbow, wrist = arm(side)
        along = (wrist - elbow).normalized()
        f.capsule(wrist - along * 0.08, wrist - along * 0.01, 0.06, 0.062, 0.006)
        f.ring(wrist - along * 0.082, along, 0.061, 0.003, 0.002, subtract=True)
        # Notched lapels lying flat either side of the V, a gap where they
        # meet the collar.
        top = front_of(f, side * 0.07, 1.6) + Vector((0, 0.004, 0))
        low = front_of(f, side * 0.02, 1.31) + Vector((0, 0.004, 0))
        along_l = (top - low).normalized()
        n = Vector((side * 0.25, 1, 0.1)).normalized()
        across = along_l.cross(n).normalized()
        n = across.cross(along_l).normalized()
        rot = Matrix((across, along_l, n)).transposed()
        mid = (top + low) * 0.5 + across * (side * 0.022 if across.x * side > 0 else -side * 0.022)
        f.box(mid + n * 0.005, (0.032, (top - low).length * 0.5, 0.0055), rot, 0.003, 0.004)
        f.box(top + n * 0.006 + Vector((side * 0.035, 0, -0.004)), (0.022, 0.016, 0.0055), rot @ Matrix.Rotation(side * 0.7, 3, "Z"), 0.003, 0.004)
        for z in (1.12, 0.98, 0.84):
            pass
        # Flap pockets at the hips.
        at = front_of(f, side * 0.12, 1.0)
        f.box(at + Vector((0, 0.004, 0)), (0.065, 0.018, 0.007), tilt_to(Vector((side * 0.4, 1, 0))), 0.003, 0.005)
    f.groove([front_of(f, 0.0, z) for z in (0.78, 0.9, 1.02, 1.14, 1.26, 1.33)], 0.003)
    f.groove([back_of(f, 0.0, z) for z in (0.78, 0.95, 1.12, 1.3, 1.5)], 0.0025)
    obj = f.mesh("Stranger coat")
    finish(obj, 0.055, smooth=1)
    return obj


def build_cap():
    """A knitted watch cap, rolled up at the brim, ribbed."""
    head = head_field()
    shell = np.abs(head.d - 0.009) - 0.008
    region = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    region.d[:] = 0.25
    region.ellipsoid((0, -0.02, 1.96), (0.12, 0.14, 0.1), 0.01)
    region.box(Vector((0, 0, 1.86)), (0.2, 0.2, 0.045), None, 0.01, 0.002, subtract=True)
    cap = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    cap.d = np.maximum(shell, region.d)
    cap.ring((0, -0.018, 1.915), (0, 0.15, 1), 0.087, 0.014, 0.006, squash=1.12)
    for i in range(36):
        a = i / 36 * 2 * pi
        p = Vector((0.1 * cos(a), -0.018 + 0.112 * sin(a), 1.93))
        cap.capsule(p, p + Vector((0, 0, 0.06)) - Vector((p.x, p.y + 0.018, 0)) * 0.3, 0.003, 0.002, 0.002, subtract=True)
    obj = cap.mesh("Stranger cap")
    finish(obj, 0.15, smooth=1)
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
    f.capsule(wrist - along * 0.03, wrist + along * 0.03, 0.03, 0.034, 0.015)
    center = wrist + along * 0.055
    # The palm as a few overlapping pads, thicker at the heel and thumb.
    for shift, radii in ((0.0, (0.041, 0.045, 0.019)), (0.022, (0.039, 0.034, 0.017))):
        p = center + along * shift
        rotation = Matrix((across, along, palm)).transposed()
        add_oriented_ellipsoid(f, p, radii, rotation, 0.012)
    add_oriented_ellipsoid(f, wrist + along * 0.035 + across * 0.022 + palm * 0.006, (0.018, 0.026, 0.016),
        Matrix((across, along, palm)).transposed(), 0.012)
    for name, points in finger_points(side).items():
        thumb = name == "Thumb"
        r0, r1, r2 = (0.0132, 0.0113, 0.009) if thumb else (0.011, 0.0098, 0.0079)
        f.chain(list(points), [r0, r1, r2], 0.004)
        f.ellipsoid(points[1], (r1 * 1.05,) * 3, 0.004)
        # A knuckle bump on the back of the hand.
        if not thumb:
            f.ellipsoid(points[0] - palm * 0.004, (0.0124, 0.012, 0.0112), 0.006)
            # A nail on the back of the fingertip.
            tip_dir = (points[2] - points[1]).normalized()
            f.ellipsoid(points[2] - tip_dir * 0.006 - palm * 0.006, (0.006, 0.0075, 0.0025), 0.002)


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


def head_field(old=False):
    """Skull, face mass, jaw and neck: the surface the face is cut into and
    hair, beard and cap sit on."""
    f = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    # Neck: the muscles from behind the ears to the collarbones, the windpipe.
    f.capsule((0, -0.016, 1.62), (0, -0.01, 1.8), 0.058, 0.052, 0.03)
    for side in (-1, 1):
        f.capsule((side * 0.046, -0.01, 1.81), (side * 0.016, 0.03, 1.655), 0.014, 0.012, 0.02)
    f.ellipsoid((0, 0.04, 1.735), (0.011, 0.012, 0.016) if not old else (0.013, 0.014, 0.018), 0.012)
    # Cranium, a little longer front to back than wide, and the face.
    f.ellipsoid((0, -0.016, 1.9), (0.073, 0.094, 0.09), 0.03)
    f.ellipsoid((0, 0.028, 1.855), (0.06, 0.068, 0.07), 0.03)
    # Jaw from below each ear round to a modest chin.
    for side in (-1, 1):
        f.capsule((side * 0.054, -0.006, 1.815), (side * 0.024, 0.064, 1.784), 0.019, 0.016, 0.022)
        if old:
            # Jowls.
            f.ellipsoid((side * 0.04, 0.05, 1.79), (0.02, 0.022, 0.016), 0.015)
    f.capsule((-0.024, 0.064, 1.784), (0.024, 0.064, 1.784), 0.016, 0.016, 0.018)
    f.ellipsoid((0, 0.068, 1.78), (0.019, 0.013, 0.014), 0.014)
    # Cheekbones, the hollow under them, the temples.
    for side in (-1, 1):
        f.ellipsoid((side * 0.045, 0.06, 1.86), (0.017, 0.013, 0.01), 0.018)
        if old:
            f.ellipsoid((side * 0.046, 0.072, 1.826), (0.014, 0.006, 0.015), 0.016, subtract=True)
        f.ellipsoid((side * 0.07, 0.03, 1.9), (0.006, 0.024, 0.016) if not old else (0.01, 0.028, 0.02), 0.016, subtract=True)
    # A real brow ridge with a glabella between.
    f.capsule((-0.044, 0.079, 1.897), (0.044, 0.079, 1.897), 0.0095 if not old else 0.011, 0.0095 if not old else 0.011, 0.02)
    f.ellipsoid((0, 0.088, 1.895), (0.012, 0.008, 0.01), 0.01)
    return f


def build_head(old=False):
    f = head_field(old)
    # Deep-set eye sockets under the brow; the lids wrap the eyeball.
    for side in (-1, 1):
        x = side * 0.031
        f.ellipsoid((x, 0.092, 1.877), (0.0155, 0.0145, 0.0105), 0.008, subtract=True)
        f.ellipsoid((x, 0.0812, 1.8852), (0.0158, 0.0108, 0.0056), 0.0025)
        f.capsule((x - 0.012, 0.0905, 1.8885), (x + 0.012, 0.0905, 1.8885), 0.0012, 0.0012, 0.0015)
        f.ellipsoid((x, 0.081, 1.8692), (0.0148, 0.0095, 0.0036), 0.0025)
        # The corners where the lids meet.
        for c in (-1, 1):
            f.ellipsoid((x + c * 0.0118, 0.0815, 1.877), (0.0035, 0.006, 0.0042), 0.002)
        if old:
            # Bags under the eyes and crow's feet.
            f.ellipsoid((x, 0.083, 1.861), (0.014, 0.008, 0.0055), 0.004)
            for dz in (-0.004, 0.002, 0.008):
                f.capsule((side * 0.047, 0.078, 1.877 + dz), (side * 0.06, 0.066, 1.879 + dz * 1.6), 0.0011, 0.0011, 0.0014, subtract=True)
    # Nose: a narrow bridge, the tip, the wings, nostrils, the septum.
    nose = 1.08 if old else 1.0
    f.capsule((0, 0.09, 1.889), (0, 0.104 * nose, 1.854), 0.0062, 0.0084, 0.009)
    f.ellipsoid((0, 0.1055 * nose, 1.8505), (0.0094, 0.0094, 0.0094), 0.007)
    for side in (-1, 1):
        f.ellipsoid((side * 0.0098, 0.0975 * nose, 1.8468), (0.0066, 0.0072, 0.0058), 0.005)
        f.ellipsoid((side * 0.0056, 0.101 * nose, 1.8422), (0.0028, 0.0032, 0.0021), 0.0018, subtract=True)
        # Folds from the nose down past the mouth.
        depth = 0.0026 if old else 0.0016
        f.capsule((side * 0.0165, 0.1, 1.848), (side * 0.03, 0.088, 1.812), depth, depth, 0.003, subtract=True)
        # Philtrum ridges.
        f.capsule((side * 0.0042, 0.1005, 1.841), (side * 0.0048, 0.0985, 1.8275), 0.0016, 0.0019, 0.0016)
    # Thin lips with a cupid's bow, parted by a line.
    f.ellipsoid((0, 0.0962, 1.8232), (0.0185, 0.0048, 0.0032), 0.004)
    for side in (-1, 1):
        f.ellipsoid((side * 0.006, 0.0975, 1.8248), (0.0065, 0.0032, 0.0022), 0.002)
    f.ellipsoid((0, 0.0935, 1.8128), (0.0158, 0.0052, 0.0042), 0.004)
    f.ellipsoid((0, 0.0985, 1.8185), (0.0195, 0.004, 0.0008), 0.0015, subtract=True)
    f.ellipsoid((0, 0.092, 1.803), (0.012, 0.004, 0.003), 0.004, subtract=True)
    # Ears: a lobe, the helix rolled round the rim, the bowl, the antihelix.
    for side in (-1, 1):
        x = side * 0.077
        size = 1.08 if old else 1.0
        f.ellipsoid((x, -0.006, 1.868), (0.007, 0.019 * size, 0.027 * size), 0.008)
        rim = []
        for i in range(12):
            t = -0.35 * pi + i / 11 * 1.55 * pi
            rim.append(Vector((x + side * 0.004, -0.006 - 0.017 * size * cos(t), 1.87 + 0.025 * size * sin(t))))
        for p, q in zip(rim, rim[1:]):
            f.capsule(p, q, 0.0032, 0.0032, 0.002)
        f.ellipsoid((x, -0.004, 1.85), (0.006, 0.008, 0.008), 0.004)
        f.ellipsoid((x + side * 0.006, -0.002, 1.866), (0.005, 0.01, 0.013), 0.004, subtract=True)
        f.capsule((x + side * 0.005, -0.012, 1.882), (x + side * 0.005, -0.006, 1.86), 0.0022, 0.0022, 0.002)
    if old:
        for dz in (0.0, 0.011, 0.022):
            f.capsule((-0.042, 0.082, 1.917 + dz), (0.042, 0.082, 1.917 + dz), 0.0016, 0.0016, 0.002, subtract=True)
        for side in (-1, 1):
            f.capsule((side * 0.006, 0.091, 1.902), (side * 0.008, 0.09, 1.893), 0.0014, 0.0014, 0.0015, subtract=True)
    obj = f.mesh("Stranger head" if old else "Head skin")
    finish(obj, 0.3, smooth=1)
    return obj


def grown_layer(name, region, thickness, ratio, extra=None, old=False):
    """A thin layer lying on the head's surface, kept only inside region (a
    Field whose negative side is where the layer belongs)."""
    head = head_field(old)
    # Lifted just off the skin, so the two surfaces never fight.
    shell = np.abs(head.d - (thickness * 0.5 + 0.0015)) - thickness * 0.5
    layer = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    layer.d = np.maximum(shell, region.d)
    if extra:
        extra(layer)
    obj = layer.mesh(name)
    finish(obj, ratio)
    return obj


def region_test(region):
    def inside(p):
        idx = np.round((np.array(p) - region.low) / VOXEL).astype(int)
        if np.any(idx < 0) or np.any(idx >= region.shape):
            return 1.0
        return float(region.d[tuple(idx)])
    return inside


def strand_mesh(name, roots, rng, length, flow, width=0.0045, segments=4, lift=0.45, clumps=160, lie=0.12, droop=0.0):
    """Hair as many tapered ribbons (alpha-free cards), gathered into clumps
    whose tips draw together. roots: [(position, normal)]. length(p) and
    flow(p, n) give each strand's length and the way it is combed. Vertex
    colour carries the strand direction (rgb) and a random shade (alpha)."""
    centres = [roots[rng.randrange(len(roots))] for _ in range(clumps)]
    bm = bmesh.new()
    colour = bm.loops.layers.float_color.new("Col")
    uv = bm.loops.layers.uv.new("UVMap")
    for p, n in roots:
        p, n = Vector(p), Vector(n).normalized()
        c = min(centres, key=lambda item: (Vector(item[0]) - p).length_squared)
        cp = Vector(c[0])
        L = length(p) * rng.uniform(0.8, 1.15)
        comb = flow(p, n)
        comb = (comb - n * comb.dot(n)).normalized()
        clump_comb = flow(cp, Vector(c[1]).normalized())
        clump_tip = cp + (clump_comb.normalized() + Vector(c[1]) * lie) * L
        shade = rng.random()
        points = [p - n * 0.0015]
        d = (n * lift + comb).normalized()
        for i in range(segments):
            t = (i + 1) / segments
            step = d * (L / segments)
            q = points[-1] + step - Vector((0, 0, droop * t * L))
            # Tips draw in towards the clump's own tip.
            q = q.lerp(clump_tip, 0.35 * t * t)
            points.append(q)
            d = (n * lie + comb).normalized()
        verts = []
        for i, q in enumerate(points):
            ahead = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
            side = ahead.cross(n)
            if side.length < 1e-5:
                side = Vector((1, 0, 0))
            side.normalize()
            w = width * (1.0 - i / len(points)) + 0.0006
            verts.append((bm.verts.new(q - side * w), bm.verts.new(q + side * w), i / segments))
        direction = (points[-1] - points[0]).normalized()
        for (a0, b0, v0), (a1, b1, v1) in zip(verts, verts[1:]):
            face = bm.faces.new((a0, b0, b1, a1))
            for loop, (u, v) in zip(face.loops, ((0, v0), (1, v0), (1, v1), (0, v1))):
                loop[colour] = (direction.x * 0.5 + 0.5, direction.y * 0.5 + 0.5, direction.z * 0.5 + 0.5, shade)
                loop[uv].uv = (u, v)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    print(name, "strands", len(roots))
    return obj


def scalp_roots(head, region, count, rng, spacing=0.0):
    inside = region_test(region)
    candidates = []
    mesh = head.data
    for poly in mesh.polygons:
        if inside(poly.center) < 0:
            candidates.append((poly.center.copy(), poly.normal.copy(), poly.area))
    total = sum(c[2] for c in candidates)
    roots = []
    for _ in range(count):
        pick = rng.uniform(0, total)
        for centre, normal, area in candidates:
            pick -= area
            if pick <= 0:
                jitter = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.0015
                roots.append((centre + jitter, normal))
                break
    return roots


def hair_region(old):
    region = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    region.d[:] = 0.25
    region.ellipsoid((0, -0.03, 1.935), (0.1, 0.13, 0.085), 0.02)
    region.ellipsoid((0, 0.11, 1.85), (0.115, 0.085, 0.085), 0.02, subtract=True)
    for side in (-1, 1):
        region.ellipsoid((side * 0.085, 0.0, 1.85), (0.03, 0.05, 0.048), 0.015, subtract=True)
    if old:
        for side in (-1, 1):
            region.ellipsoid((side * 0.055, 0.07, 1.95), (0.035, 0.05, 0.05), 0.015, subtract=True)
    return region


def build_hair(head, old=False):
    """Short hair in clumps: longer on top and swept back and up off the
    forehead, short at the sides and back. Old: thin, grey, only what shows
    under the cap. A dark layer under it so no scalp shows between strands."""
    rng = __import__("random").Random(19 if old else 7)
    region = hair_region(old)
    if old:
        region.box(Vector((0, 0, 1.96)), (0.2, 0.2, 0.05), None, 0.01, 0.002, subtract=True)

    def length(p):
        top = smoothstep(1.87, 1.97, p.z)
        return (0.016 + 0.006 * (1 - top)) if old else (0.02 + 0.028 * top + 0.01 * smoothstep(0.0, 0.09, p.y) * top)

    def flow(p, n):
        top = smoothstep(1.88, 1.96, p.z)
        front = smoothstep(0.0, 0.08, p.y)
        back_down = Vector((p.x * 2.0, -0.6, -1.0))
        swept = Vector((p.x * 0.8, -1.0, -0.1 + 0.35 * front))
        return back_down.lerp(swept, top).normalized()

    roots = scalp_roots(head, region, 800 if old else 2700, rng)
    strands = strand_mesh("Stranger hair" if old else "Hair", roots, rng, length, flow,
        width=0.0032 if old else 0.0045, lift=0.32 if not old else 0.25, clumps=90 if old else 170, lie=0.04)
    base = grown_layer(("Stranger hair" if old else "Hair") + " base", region, 0.0025, 0.12, old=old)
    return [strands, base]


def build_brows(head, old=False):
    rng = __import__("random").Random(23 if old else 11)
    roots = []
    for side in (-1, 1):
        for i in range(70 if old else 55):
            t = rng.random()
            p = Vector((side * (0.014 + 0.036 * t), 0.0955 - 0.009 * t, 1.8955 - 0.002 * t + rng.uniform(-0.0025, 0.0025)))
            roots.append((p, Vector((side * 0.3 * t, 1, 0.25)).normalized()))

    def length(p):
        return 0.011 if old else 0.008

    def flow(p, n):
        return Vector((1 if p.x > 0 else -1, 0, 0.35))

    return strand_mesh("Stranger brows" if old else "Brows", roots, rng, length, flow, width=0.0016, segments=3, lift=0.25, clumps=14, lie=0.15)


def build_beard(head):
    """A short grey beard in strands along the jaw and over the lip."""
    rng = __import__("random").Random(31)
    region = Field((-0.13, -0.14, 1.6), (0.13, 0.17, 2.03))
    region.d[:] = 0.25
    region.ellipsoid((0, 0.04, 1.8), (0.086, 0.09, 0.052), 0.015)
    region.ellipsoid((0, 0.1, 1.829), (0.024, 0.02, 0.006), 0.006)
    region.ellipsoid((0, 0.1, 1.853), (0.082, 0.07, 0.026), 0.012, subtract=True)
    region.ellipsoid((0, 0.11, 1.8155), (0.023, 0.03, 0.0088), 0.003, subtract=True)
    region.capsule((0, -0.02, 1.62), (0, 0.02, 1.765), 0.075, 0.05, 0.01, subtract=True)
    roots = scalp_roots(head, region, 2300, rng)

    def length(p):
        return 0.02 + 0.01 * smoothstep(1.82, 1.78, p.z)

    def flow(p, n):
        lip = p.z > 1.824
        return Vector((p.x * 1.5, 0.35, -1.0)) if not lip else Vector((p.x * 3.0, 0.2, -1.0))

    strands = strand_mesh("Beard", roots, rng, length, flow, width=0.0026, segments=3, lift=0.45, clumps=140, lie=0.2)
    base = grown_layer("Beard base", region, 0.002, 0.15, old=True)
    return [strands, base]


def build_eyes():
    eyes = []
    for side in (-1, 1):
        for title, radius, at in (("Eye", 0.0102, (side * 0.031, 0.0772, 1.8768)), ("Iris", 0.0048, (side * 0.031, 0.0862, 1.8768))):
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


def finish(obj, ratio, smooth=2):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=VOXEL * 0.05)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    if smooth:
        apply_modifier(obj, "LAPLACIANSMOOTH", iterations=smooth, lambda_factor=0.35 if smooth == 1 else 0.5, use_volume_preserve=True)
    apply_modifier(obj, "DECIMATE", ratio=ratio)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.validate()
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


def paint(objects):
    """One material per piece, so each garment shades as what it is."""
    mats = {
        "Jacket": material("Jacket", (0.2, 0.19, 0.13), 0.88),
        "Jeans": material("Jeans", (0.085, 0.1, 0.15), 0.9),
        "Belt": material("Belt", (0.09, 0.055, 0.035), 0.55),
        "Boots": material("Boots", (0.16, 0.095, 0.055), 0.6),
        "Sole": material("Sole", (0.03, 0.028, 0.026), 0.85),
        "Metal": material("Metal", (0.45, 0.42, 0.36), 0.35),
        "Laces": material("Laces", (0.32, 0.27, 0.2), 0.9),
        "Skin": material("Skin", (0.4, 0.25, 0.18), 0.84),
        "Lips": material("Lips", (0.44, 0.25, 0.21), 0.7),
        "Hair": material("Hair", (0.06, 0.045, 0.032), 0.93),
        "Hair grey": material("Hair grey", (0.27, 0.26, 0.24), 0.95),
        "Beard": material("Beard", (0.2, 0.19, 0.175), 0.95),
        "Coat": material("Coat", (0.2, 0.15, 0.11), 0.95),
        "Cap": material("Cap", (0.22, 0.24, 0.2), 1.0),
        "Shirt": material("Shirt", (0.55, 0.53, 0.5), 0.95),
        "Hair base": material("Hair base", (0.05, 0.04, 0.03), 0.95),
        "Hair base grey": material("Hair base grey", (0.2, 0.19, 0.18), 0.95),
        "Flannel": material("Flannel", (0.35, 0.12, 0.08), 0.95),
        "Eye white": material("Eye white", (0.62, 0.58, 0.54), 0.3),
        "Iris": material("Iris", (0.06, 0.07, 0.05), 0.15),
    }
    pick = {"Jacket": "Jacket", "Jeans": "Jeans", "Belt": "Belt", "Boot": "Boots", "Sole": "Sole", "Hardware": "Metal",
        "Laces": "Laces", "Skin hand": "Skin", "Hair": "Hair", "Stranger hair": "Hair grey", "Beard": "Beard",
        "Brows": "Hair", "Stranger brows": "Hair grey", "Shirt": "Shirt", "Stranger shirt": "Flannel",
        "Hair base": "Hair base", "Stranger hair base": "Hair base grey", "Beard base": "Hair base grey",
        "Stranger coat": "Coat", "Stranger cap": "Cap", "Eye": "Eye white", "Iris": "Iris"}
    for obj in objects:
        if obj.name in ("Head skin", "Stranger head"):
            obj.data.materials.append(mats["Skin"])
            obj.data.materials.append(mats["Lips"])
            for poly in obj.data.polygons:
                c = poly.center
                upper = Vector(((c.x) / 0.021, (c.y - 0.097) / 0.009, (c.z - 1.822) / 0.0062)).length
                lower = Vector(((c.x) / 0.018, (c.y - 0.094) / 0.0095, (c.z - 1.809) / 0.0072)).length
                if min(upper, lower) < 1.15 and c.y > 0.09:
                    poly.material_index = 1
            continue
        for prefix in sorted(pick, key=len, reverse=True):
            if obj.name.startswith(prefix):
                obj.data.materials.append(mats[pick[prefix]])
                break


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
        share = smoothstep(1.72 - HEAD_DROP, 1.77 - HEAD_DROP, v.co.z)
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


# The face sits this much lower on the neck than the old model's did, so the
# jaw hangs below the head's pivot the way a real one does.
HEAD_DROP = 0.05
UV_BONES = ("Hips", "Spine", "Chest", "Neck", "Head", "Thigh", "Shin", "Foot", "UpperArm", "Forearm", "Hand")


def wear_of(name, p):
    """How worn the cloth or leather is at p (0 to 1): thigh fronts, knees
    and seat of the jeans, elbows, cuffs and hem of a jacket, scuffed toes."""
    if name.startswith("Jeans"):
        side = 1 if p.x > 0 else -1
        hip, knee, ankle, toe = leg(side)
        front = smoothstep(-0.01, 0.06, p.y - hip.lerp(ankle, 0.5).y)
        thigh = front * smoothstep(0.55, 0.7, p.z) * smoothstep(0.98, 0.85, p.z)
        knee_w = smoothstep(0.08, 0.02, (p - knee - Vector((0, 0.05, 0))).length)
        seat = smoothstep(-0.06, -0.11, p.y) * smoothstep(0.85, 0.95, p.z) * smoothstep(1.06, 0.98, p.z)
        hem = smoothstep(0.2, 0.17, p.z)
        return max(thigh * 0.8, knee_w, seat * 0.7, hem * 0.6)
    if name.startswith("Jacket") or name.startswith("Stranger coat"):
        w = 0.0
        for side in (-1, 1):
            shoulder, elbow, wrist = arm(side)
            w = max(w, smoothstep(0.07, 0.02, (p - elbow).length), smoothstep(0.05, 0.0, (p - wrist).length) * 0.8)
        w = max(w, smoothstep(1.14, 1.1, p.z) * 0.6 if name.startswith("Jacket") else smoothstep(0.8, 0.75, p.z) * 0.6)
        return w
    if name.startswith("Boot"):
        return max(smoothstep(0.12, 0.2, p.y), smoothstep(-0.04, -0.08, p.y) * 0.6)
    return 0.0


def redness_of(name, p):
    if "head" in name.lower():
        cheeks = max(smoothstep(0.02, 0.0, (Vector((abs(p.x), p.y, p.z)) - Vector((0.045, 0.072, 1.845))).length - 0.005), 0.0)
        nose = smoothstep(0.016, 0.0, (p - Vector((0, 0.11, 1.849))).length)
        ears = smoothstep(0.065, 0.08, abs(p.x)) * smoothstep(1.83, 1.87, p.z)
        return max(cheeks * 0.8, nose, ears * 0.8)
    if name.startswith("Skin hand"):
        return 0.4
    return 0.0


def body_uv(obj, rig):
    """UVs in metres round and along the nearest bone, so the fabric
    patterns keep their size, and a colour layer with wear (r) and flush (g)."""
    bones = [(b.name, b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones
        if b.name.rstrip("LR") in UV_BONES or b.name in UV_BONES]
    mesh = obj.data
    uv = mesh.uv_layers.new(name="UVMap")
    colour = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    per_vertex = {}
    for v in mesh.vertices:
        p = v.co
        best = min(bones, key=lambda b: segment_distance(p, b[1], b[2]))
        a, b = best[1], best[2]
        axis = (b - a).normalized()
        t = (p - a).dot(axis)
        radial = (p - a) - axis * t
        ref = Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((0, 0, 1))
        ref = (ref - axis * ref.dot(axis)).normalized()
        other = axis.cross(ref)
        angle = __import__("math").atan2(radial.dot(other), radial.dot(ref))
        r = max(radial.length, 0.02)
        per_vertex[v.index] = (angle, r, t + hash(best[0]) % 7 * 0.7, 2 * pi * r)
    for poly in mesh.polygons:
        angles = [per_vertex[mesh.loops[li].vertex_index][0] for li in poly.loop_indices]
        wrap = max(angles) - min(angles) > pi
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            angle, r, along, around = per_vertex[vi]
            if wrap and angle < 0:
                angle += 2 * pi
            uv.data[li].uv = (angle * r, along)
            p = mesh.vertices[vi].co
            colour.data[li].color = (wear_of(obj.name, p), redness_of(obj.name, p), 0.0, 1.0)
    mesh.color_attributes.active_color = colour


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    garments = [build_jacket(), build_tee(), build_tee(stranger=True), build_jeans(), build_belt()] + build_boots()
    garments += [build_hardware(FIELDS["jacket"], FIELDS["jeans"]), build_laces(), build_coat()]
    hands = build_hands()
    head = build_head()
    old_head = build_head(old=True)
    hair = build_hair(head) + build_hair(old_head, old=True) + build_beard(old_head)
    brows = [build_brows(head), build_brows(old_head, old=True)]
    cap = build_cap()
    eyes = build_eyes()
    heads = [head, old_head, cap] + hair + brows + eyes
    paint(garments + hands + heads)
    rig = build_rig()
    for obj in garments + hands + [head, old_head, cap]:
        body_uv(obj, rig)
    # A slightly bigger head on the same neck: about seven and a half heads tall.
    for obj in heads:
        obj.data.transform(Matrix.Translation((0, 0, 1.75 - HEAD_DROP)) @ Matrix.Scale(1.1, 4) @ Matrix.Translation((0, 0, -1.75)))
    for obj in garments:
        skin_body(obj, rig)
        smooth_weights(obj)
    for obj, suffix in zip(hands, ("L", "R")):
        skin_hand(obj, rig, suffix)
        smooth_weights(obj)
    skin_head(head, rig)
    skin_head(old_head, rig)
    for obj in [cap] + hair + brows + eyes:
        attach(obj, rig, "Head")
    total = 0
    counts = {}
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
            counts[obj.name] = tris
            total += tris
            print("tris", obj.name, tris)
    stranger_only = ("Stranger", "Beard")
    player = sum(t for n, t in counts.items() if not n.startswith(stranger_only))
    stranger = sum(t for n, t in counts.items() if not n.startswith(("Head skin", "Hair", "Jacket", "Belt", "Hardware", "Shirt", "Brows")))
    print("tris total", total, "player", player, "stranger", stranger)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True, export_animations=False,
        export_skins=True, export_yup=True, export_apply=False, export_tangents=True,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False)
    print("exported", GLB)


main()
