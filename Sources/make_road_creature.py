"""Rebuild assets/characters/road_creature.glb.

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_road_creature.py

The skin is one signed distance field: every bone, rib and knuckle is a
primitive blended into its neighbours with a smooth union, then meshed with
OpenVDB. That keeps the surface continuous and the detail level uniform from
skull to fingertip.

The rest pose matches the crawl pose in scripts/road_end_house.gd and every
limb bone has the length that scripts/road_creature.gd solves for, so the game
never has to stretch or squash a limb. Blender is Z-up with the creature facing
-Y; the glTF exporter turns that into Godot's Y-up, +Z-forward space.
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
GLB = ROOT / "assets/characters/road_creature.glb"
BLEND = ROOT / "Sources/road_creature.blend"
VOXEL = 0.0032

# Lengths shared with road_creature.gd. Keep both files in sync.
UPPER_ARM, FOREARM = 0.73, 0.78
THIGH, SHIN = 0.69, 0.65
SHOULDER_SPAN, HIP_SPAN = 0.193, 0.116
HEAD_LIFT, HEAD_REACH, HEAD_PIVOT = 0.16, 0.36, 0.105

SHOULDERS = Vector((0, -0.37, 0.74))
PELVIS = Vector((0, 0.37, 0.66))
HEAD_POSITION = SHOULDERS + Vector((0, -HEAD_REACH, HEAD_LIFT))
HEAD_BONE = HEAD_POSITION + Vector((0, HEAD_PIVOT, 0))
FORWARD = Vector((0, -1, 0))

SKULL = HEAD_POSITION + Vector((0, -0.01, 0.08))
# A grin that runs cheek to cheek, rising at the corners.
SMILE_Z = HEAD_POSITION.z - 0.03
SMILE_HALF = 0.084
FACE = HEAD_POSITION + Vector((0, -0.04, -0.045))
EYE_HEIGHT = HEAD_POSITION.z + 0.093
EYE_SPAN = 0.048
EYE_DEPTH = HEAD_POSITION.y - 0.112

rng = Random(1907)


def smile_z(x):
    return SMILE_Z + 0.05 * (x / SMILE_HALF) ** 2


def smile_height(x):
    """Half the opening's height at x."""
    return 0.031 * max(0.0, 1.0 - (x / SMILE_HALF) ** 2) ** 0.7 + 0.003


def face_y(x):
    """Where the front of the face is, at mouth height."""
    return FACE.y - 0.104 * sqrt(max(0.0, 1.0 - (x / 0.093) ** 2))


def joint(start, end, bend, first, second):
    """Same two-bone solve as road_creature.gd so the rest pose is reachable."""
    span = end - start
    distance = min(max(span.length, 0.001), first + second - 0.002)
    direction = span.normalized()
    forward = (first * first + distance * distance - second * second) / (2 * distance)
    side = (bend - direction * bend.dot(direction)).normalized()
    return start + direction * forward + side * sqrt(max(0.0, first * first - forward * forward))


def limb_points(side):
    shoulder = SHOULDERS + Vector((side * SHOULDER_SPAN, 0, 0))
    palm = Vector((side * 0.39, SHOULDERS.y - 0.21, 0.0))
    wrist = palm + Vector((0, 0.057, 0.087))
    elbow = joint(shoulder, wrist, Vector((side * 0.91, 0.65, -0.20)), UPPER_ARM, FOREARM)
    hip = PELVIS + Vector((side * HIP_SPAN, 0, 0))
    sole = Vector((side * 0.32, PELVIS.y - 0.07, 0.0))
    ankle = sole + Vector((0, 0.04, 0.106))
    knee = joint(hip, ankle, Vector((side * 0.83, -0.74, 0.18)), THIGH, SHIN)
    return shoulder, elbow, wrist, palm, hip, knee, ankle, sole


# Distance field -----------------------------------------------------------

class Field:
    """A dense distance grid that primitives are blended into one at a time."""

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

    def capsule(self, a, b, ra, rb, k):
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
        self.add(sdf, np.minimum(a, b) - reach, np.maximum(a, b) + reach, k)

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


def build_hand(f, wrist, palm, side, length, curl):
    """Long knuckled fingers. Hands and feet share one design."""
    pad = palm + Vector((0, 0, 0.024))
    f.capsule(wrist, pad + Vector((0, 0.0, 0.012)), 0.021, 0.024, 0.02)
    f.ellipsoid(pad + Vector((0, -0.014, 0.004)), (0.034, 0.044, 0.016), 0.02)
    for n in range(4):
        spread = (n - 1.5) / 1.5
        knuckle = pad + Vector((side * spread * 0.025, -0.052, 0.012))
        heading = Vector((side * spread * 0.28, -1, 0)).normalized()
        reach = length * (1.0 - abs(spread) * 0.14 - (0.1 if n == (0 if side > 0 else 3) else 0.0))
        mid = knuckle + heading * reach * 0.44 + Vector((0, 0, 0.03))
        tip_joint = mid + heading * reach * 0.33 + Vector((0, 0, -0.008))
        tip = tip_joint + heading * reach * 0.25 + Vector((0, 0, -curl))
        f.chain([knuckle, mid, tip_joint, tip], [0.0098, 0.0086, 0.0072, 0.0038], 0.005)
        f.ellipsoid(knuckle + Vector((0, 0.004, 0.004)), (0.0115, 0.011, 0.01), 0.008)
        f.ellipsoid(mid, (0.0102, 0.0105, 0.0102), 0.005)
        f.ellipsoid(tip_joint, (0.0084, 0.0088, 0.0084), 0.004)
    inner = -side
    root = pad + Vector((inner * 0.026, -0.008, 0.008))
    middle = root + Vector((inner * 0.045, -0.038, 0.016))
    tip = middle + Vector((inner * 0.018, -0.05, -0.03))
    f.chain([root, middle, tip], [0.0115, 0.0092, 0.0042], 0.008)


def build_skin():
    f = Field((-1.02, -1.02, -0.03), (1.02, 0.62, 1.26))
    torso_k = 0.045
    # Ribcage, a sunken waist and a narrow pelvis.
    chest = SHOULDERS + Vector((0, 0.13, -0.02))
    f.ellipsoid(chest, (0.162, 0.225, 0.125), torso_k, Quaternion((1, 0, 0), 0.05))
    f.capsule(SHOULDERS + Vector((0, 0.27, -0.0)), PELVIS + Vector((0, -0.1, 0.01)), 0.078, 0.08, torso_k)
    f.ellipsoid(PELVIS + Vector((0, -0.03, 0.0)), (0.125, 0.105, 0.088), torso_k)
    for side in (-1, 1):
        f.ellipsoid(PELVIS + Vector((side * 0.095, -0.075, 0.032)), (0.03, 0.028, 0.024), 0.03)
        # Shoulder blades sit proud of the back.
        f.ellipsoid(SHOULDERS + Vector((side * 0.092, 0.1, 0.085)), (0.055, 0.075, 0.016), 0.05,
            Quaternion((0, 0, 1), side * 0.3))
        f.capsule(SHOULDERS + Vector((side * 0.025, -0.08, 0.035)), SHOULDERS + Vector((side * 0.18, -0.035, 0.035)),
            0.012, 0.015, 0.018)
        f.ellipsoid(SHOULDERS + Vector((side * SHOULDER_SPAN, 0.0, 0.01)), (0.048, 0.05, 0.046), 0.035)
        # Ribs: arcs just outside the chest, so they press through the skin.
        for r in range(7):
            t = r / 6
            y = chest.y - 0.16 + t * 0.31
            fall = 1.0 - ((y - chest.y) / 0.225) ** 2
            span = 0.162 * sqrt(max(fall, 0.05)) - 0.002
            height = 0.125 * sqrt(max(fall, 0.05)) - 0.002
            pts = []
            for n in range(9):
                a = 0.55 - n / 8 * 1.95
                pts.append(Vector((side * span * cos(a), y + n * 0.007, chest.z + height * sin(a))))
            f.chain(pts, [0.0058] * len(pts), 0.03)
    # Vertebrae ridge.
    top = [SHOULDERS + Vector((0, -0.06, 0.1)), chest + Vector((0, 0.0, 0.122)),
        SHOULDERS + Vector((0, 0.36, 0.07)), PELVIS + Vector((0, -0.1, 0.08)), PELVIS + Vector((0, 0.08, 0.078))]
    for i in range(22):
        s = i / 21 * (len(top) - 1)
        j = min(int(s), len(top) - 2)
        at = top[j].lerp(top[j + 1], s - j)
        f.ellipsoid(at, (0.012, 0.01, 0.01), 0.022)
    # Long neck with tendons.
    neck_base = SHOULDERS + Vector((0, -0.05, 0.04))
    neck_top = HEAD_BONE + Vector((0, -0.03, -0.045))
    f.capsule(neck_base, neck_top, 0.047, 0.037, 0.04)
    for side in (-1, 1):
        f.capsule(neck_base + Vector((side * 0.032, -0.035, -0.012)), neck_top + Vector((side * 0.024, -0.035, -0.022)),
            0.0095, 0.0085, 0.014)
    # Narrow egg skull with a heavy brow; the face is otherwise smooth.
    f.ellipsoid(SKULL + Vector((0, 0.012, 0.035)), (0.108, 0.125, 0.18), 0.05, Quaternion((1, 0, 0), -0.16))
    f.ellipsoid(HEAD_POSITION + Vector((0, -0.04, -0.045)), (0.088, 0.1, 0.1), 0.06)
    f.ellipsoid(Vector((0, EYE_DEPTH + 0.014, EYE_HEIGHT + 0.03)), (0.078, 0.022, 0.016), 0.035)
    for side in (-1, 1):
        f.ellipsoid(Vector((side * 0.072, HEAD_POSITION.y - 0.06, HEAD_POSITION.z + 0.02)), (0.022, 0.06, 0.04), 0.03)
    # Thin lips stretched tight along the grin.
    for edge in (1, -1):
        lip = []
        for n in range(29):
            x = SMILE_HALF * (n / 14 - 1) * 1.02
            lip.append(Vector((x, face_y(x) + 0.004, smile_z(x) + edge * (smile_height(x) + 0.002))))
        f.chain(lip, [0.0045] * len(lip), 0.012)
    # Arms and legs share the same taper language.
    for side in (-1, 1):
        shoulder, elbow, wrist, palm, hip, knee, ankle, sole = limb_points(side)
        f.chain([shoulder, shoulder.lerp(elbow, 0.3), shoulder.lerp(elbow, 0.75), elbow], [0.047, 0.04, 0.032, 0.028], 0.035)
        f.ellipsoid(elbow, (0.033, 0.033, 0.033), 0.02)
        f.chain([elbow, elbow.lerp(wrist, 0.22), elbow.lerp(wrist, 0.7), wrist], [0.029, 0.035, 0.025, 0.019], 0.028)
        build_hand(f, wrist, palm, side, 0.2, 0.036)
        f.chain([hip, hip.lerp(knee, 0.3), hip.lerp(knee, 0.8), knee], [0.062, 0.052, 0.038, 0.032], 0.04)
        f.ellipsoid(knee, (0.039, 0.039, 0.039), 0.02)
        f.chain([knee, knee.lerp(ankle, 0.25), knee.lerp(ankle, 0.7), ankle], [0.032, 0.037, 0.026, 0.02], 0.028)
        build_hand(f, ankle, sole, side, 0.17, 0.032)
    # Carve the mouth and deep eye sockets last.
    for n in range(41):
        x = SMILE_HALF * (n / 20 - 1)
        f.ellipsoid(Vector((x, face_y(x) + 0.032, smile_z(x))), (0.009, 0.048, smile_height(x)), 0.005, subtract=True)
    f.ellipsoid(Vector((0, FACE.y - 0.035, SMILE_Z + 0.012)), (0.066, 0.045, 0.048), 0.012, subtract=True)
    for side in (-1, 1):
        f.ellipsoid(Vector((side * EYE_SPAN, EYE_DEPTH - 0.006, EYE_HEIGHT)), (0.027, 0.038, 0.024), 0.016, subtract=True)
    skin = f.mesh("Continuous skin")
    bpy.context.view_layer.objects.active = skin
    apply_modifier(skin, "LAPLACIANSMOOTH", iterations=2, lambda_factor=0.5, use_volume_preserve=True)
    apply_modifier(skin, "DECIMATE", ratio=0.15)
    skin.data.shade_smooth()
    print("skin verts", len(skin.data.vertices))
    return skin


# Assembly -----------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"


def material(name, color, roughness):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    return mat


def apply_modifier(obj, kind, **settings):
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new(kind.title(), kind)
    for key, value in settings.items():
        setattr(mod, key, value)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def assign_skin_materials(skin):
    mats = [
        material("Pale mottled skin", (0.62, 0.56, 0.52), 0.75),
        material("Mouth interior", (0.07, 0.022, 0.026), 0.55),
        material("Gum tissue", (0.25, 0.07, 0.075), 0.5),
    ]
    skin.data.materials.clear()
    for mat in mats:
        skin.data.materials.append(mat)
    for poly in skin.data.polygons:
        c = poly.center
        if abs(c.x) > SMILE_HALF + 0.006:
            continue
        depth = c.y - face_y(c.x)
        band = abs(c.z - smile_z(c.x)) - smile_height(c.x)
        if 0.0 < depth < 0.06 and band < 0.0:
            poly.material_index = 2 if depth < 0.012 else 1
        elif depth > 0.025 and Vector((c.x / 0.07, (c.y - FACE.y + 0.035) / 0.05, (c.z - SMILE_Z - 0.012) / 0.052)).length < 1.05:
            poly.material_index = 1


def build_eyes():
    eye_mat = material("Black eyes with embedded red irises", (0.01, 0.01, 0.012), 0.4)
    eyes = []
    for index, side in enumerate((-1, 1)):
        mesh = bpy.data.meshes.new("Black eye")
        bm = bmesh.new()
        bm.loops.layers.uv.new("UVMap")
        bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=20, radius=0.017, calc_uvs=True)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("Black eye" if index == 0 else "Black eye.001", mesh)
        bpy.context.scene.collection.objects.link(obj)
        # Turn the sphere so the UV centre, where the slit is drawn, looks forward.
        uv = mesh.uv_layers.active.data
        best, best_d = None, 9.0
        for loop in mesh.loops:
            d = (Vector(uv[loop.index].uv) - Vector((0.5, 0.5))).length
            if d < best_d:
                best, best_d = mesh.vertices[loop.vertex_index].co.copy(), d
        flat = Vector((best.x, best.y, 0)).normalized()
        mesh.transform(flat.rotation_difference(FORWARD).to_matrix().to_4x4())
        mesh.transform(Matrix.Diagonal((1.0, 0.8, 1.1, 1.0)))
        mesh.transform(Matrix.Rotation(-side * 0.2, 4, "Z"))
        mesh.transform(Matrix.Translation((side * EYE_SPAN, EYE_DEPTH + 0.024, EYE_HEIGHT)))
        mesh.materials.append(eye_mat)
        eyes.append(obj)
    return eyes


def build_teeth():
    ivory = material("Aged ivory", (0.62, 0.56, 0.44), 0.42)
    teeth = {}
    for name, upper in (("Upper teeth", True), ("Lower teeth", False)):
        bm = bmesh.new()
        edge = 1 if upper else -1
        for depth, scale, count in ((0.009, 1.0, 30), (0.022, 0.72, 22)):
            for i in range(count):
                t = (i + 0.5 + rng.uniform(-0.25, 0.25)) / count
                x = SMILE_HALF * 0.94 * (2 * t - 1)
                open_half = smile_height(x)
                base = Vector((x, face_y(x) + depth, smile_z(x) + edge * open_half * 0.92))
                inward = Vector((0, 0, -edge))
                length = min(open_half * 1.75, rng.uniform(0.016, 0.03)) * scale + 0.004
                aim = (inward + Vector((rng.uniform(-0.18, 0.18), rng.uniform(0.05, 0.3), 0))).normalized()
                radius = rng.uniform(0.0026, 0.004) * (0.8 + 0.2 * scale)
                rot = aim.to_track_quat("Z", "Y").to_matrix().to_4x4()
                bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=radius, radius2=0.0003, depth=length,
                    matrix=Matrix.Translation(base + aim * length * 0.4) @ rot)
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        mesh.materials.append(ivory)
        mesh.shade_smooth()
        teeth[name] = obj
    return teeth


def build_rig():
    data = bpy.data.armatures.new("Contact rig")
    rig = bpy.data.objects.new("Contact rig", data)
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

    bone("Torso", PELVIS, SHOULDERS)
    bone("Neck", SHOULDERS, HEAD_BONE, "Torso")
    bone("Head", HEAD_BONE, HEAD_BONE + FORWARD * 0.34, "Neck")
    bone("Jaw", HEAD_BONE + Vector((0, -0.08, -0.06)), Vector((0, face_y(0.0) - 0.01, SMILE_Z - 0.07)), "Head")
    for suffix, side in (("L", -1), ("R", 1)):
        shoulder, elbow, wrist, palm, hip, knee, ankle, sole = limb_points(side)
        bone("UpperArm" + suffix, shoulder, elbow, "Torso")
        bone("Forearm" + suffix, elbow, wrist, "UpperArm" + suffix)
        bone("Hand" + suffix, wrist, wrist + Vector((0, -0.2, -0.06)), "Forearm" + suffix)
        bone("Thigh" + suffix, hip, knee, "Torso")
        bone("Shin" + suffix, knee, ankle, "Thigh" + suffix)
        bone("Foot" + suffix, ankle, ankle + Vector((0, -0.18, -0.06)), "Shin" + suffix)
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def segment_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def skin_to_rig(obj, rig, fixed=None):
    """Distance-based weights with a rigid skull, hands and feet."""
    bones = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
    groups = {name: obj.vertex_groups.new(name=name) for name in bones}
    head_center = SKULL + Vector((0, -0.01, -0.04))
    for v in obj.data.vertices:
        p = v.co
        if fixed:
            weights = dict(fixed)
        else:
            weights = {}
            head_local = Vector(((p.x - head_center.x) / 0.14, (p.y - head_center.y) / 0.16, (p.z - head_center.z) / 0.25))
            head_share = 1.0 - smoothstep(0.86, 1.06, head_local.length)
            distances = {}
            for name, (a, b) in bones.items():
                if name not in ("Head", "Jaw"):
                    distances[name] = segment_distance(p, a, b)
            for suffix in ("L", "R"):
                for extremity in ("Hand", "Foot"):
                    a, b = bones[extremity + suffix]
                    past = (p - a).dot((b - a).normalized())
                    near = (p - a).length < 0.26
                    distances[extremity + suffix] = 0.0001 + max(0.0, 0.012 - past) * 0.6 if near and past > -0.03 else 9.0
            ranked = sorted(distances.items(), key=lambda item: item[1])[:3]
            total = sum(1.0 / max(d, 0.0005) ** 6 for _, d in ranked)
            for name, d in ranked:
                weights[name] = (1.0 / max(d, 0.0005) ** 6) / total * (1.0 - head_share)
            if head_share > 0:
                jaw = smoothstep(smile_z(p.x) + 0.004, smile_z(p.x) - 0.035, p.z) * smoothstep(HEAD_POSITION.y + 0.02, HEAD_POSITION.y - 0.06, p.y)
                weights["Head"] = head_share * (1.0 - jaw)
                weights["Jaw"] = head_share * jaw
        for name, w in weights.items():
            if w > 0.002:
                groups[name].add([v.index], w, "REPLACE")
    obj.parent = rig
    obj.modifiers.new("Armature", "ARMATURE").object = rig


def smooth_weights(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.5, repeat=3)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def main():
    reset_scene()
    skin = build_skin()
    assign_skin_materials(skin)
    eyes = build_eyes()
    teeth = build_teeth()
    rig = build_rig()
    skin_to_rig(skin, rig)
    smooth_weights(skin)
    for eye in eyes:
        skin_to_rig(eye, rig, {"Head": 1.0})
    skin_to_rig(teeth["Upper teeth"], rig, {"Head": 1.0})
    skin_to_rig(teeth["Lower teeth"], rig, {"Jaw": 1.0})
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True, export_animations=False,
        export_skins=True, export_yup=True, export_apply=False)
    print("exported", GLB)


main()
