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

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathutils import Euler, Vector
from desert_kit import V, Kit, build_all

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

def _blob(k, mat, at, r, squash=0.7, subdiv=1):
    k.ico(mat, at, r, (1.0, squash, 1.0), subdiv, 0.35)


def scrub(seed=710):
    """Creosote: a vase of thin grey stems from one root, olive clumps of
    leaves at their ends, and a few bare twigs."""
    k = Kit(seed)
    rng = k.rng
    for i in range(11):
        a = i / 11 * 2 * pi + rng.uniform(-0.3, 0.3)
        lean = rng.uniform(0.25, 0.75)
        length = rng.uniform(0.55, 0.95)
        tip = V(sin(lean) * cos(a), cos(lean), sin(lean) * sin(a)) * length
        mid = tip * 0.55 + V(rng.uniform(-0.06, 0.06), 0, rng.uniform(-0.06, 0.06))
        k.cyl("Bark", V(0, 0, 0), mid, 0.018, 4, 0.012)
        k.cyl("Bark", mid, tip, 0.012, 4, 0.006)
        if rng.random() < 0.8:
            _blob(k, "Scrub", tip + V(0, 0.02, 0), rng.uniform(0.13, 0.22), 0.6)
            _blob(k, "Scrub", mid + (tip - mid) * 0.5 + V(rng.uniform(-0.05, 0.05), 0, 0), rng.uniform(0.08, 0.13), 0.6)
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


def grass(seed=730):
    """A tuft of dry bunchgrass: a few dozen blades, bending out and over."""
    k = Kit(seed)
    rng = k.rng
    for i in range(18):
        a = rng.uniform(0, 2 * pi)
        lean = rng.uniform(0.15, 0.7)
        length = rng.uniform(0.3, 0.55)
        base = V(rng.uniform(-0.05, 0.05), 0, rng.uniform(-0.05, 0.05))
        d = V(sin(lean) * cos(a), cos(lean), sin(lean) * sin(a))
        side = V(-sin(a), 0, cos(a)) * 0.012
        mid = base + d * length * 0.6
        tip = base + d * length + V(0, -0.05 * lean, 0) + V(cos(a), 0, sin(a)) * 0.06 * lean
        k.poly("Grass", [base - side, base + side, mid + side * 0.7, mid - side * 0.7])
        k.poly("Grass", [mid - side * 0.7, mid + side * 0.7, tip])
    return k.finish("Grass")


def tree(seed=740):
    """A mesquite: a short twisted trunk splitting low into spreading limbs,
    with loose clumps of small leaves."""
    k = Kit(seed)
    rng = k.rng

    def limb(a, d, length, r, depth):
        b = a + d * length
        k.cyl("Bark", a, b, r, 7, r * 0.7)
        if depth == 0:
            for _ in range(3):
                _blob(k, "Leaves", b + V(rng.uniform(-0.3, 0.3), rng.uniform(-0.1, 0.2), rng.uniform(-0.3, 0.3)), rng.uniform(0.35, 0.6), 0.55, 1)
            return
        for n in range(2 if depth < 2 else 3):
            turn = Euler((rng.uniform(-0.5, 0.5), rng.uniform(0, 2 * pi), rng.uniform(-0.5, 0.5)), "XYZ").to_matrix()
            child = (turn @ d).normalized()
            child.y = abs(child.y) * 0.6 + 0.3
            limb(b, child.normalized(), length * rng.uniform(0.6, 0.8), r * 0.65, depth - 1)

    k.cyl("Bark", V(0, -0.2, 0), V(0.1, 0.9, 0.05), 0.17, 8, 0.14)
    for i in range(3):
        a = i / 3 * 2 * pi + rng.uniform(-0.3, 0.3)
        limb(V(0.1, 0.85, 0.05), V(cos(a) * 0.6, 0.8, sin(a) * 0.6).normalized(), 1.2, 0.12, 2)
    return k.finish("Tree")


def pine(seed=750):
    """A pinyon-ish pine: a trunk and ragged, uneven tiers of needles."""
    k = Kit(seed)
    rng = k.rng
    k.cyl("Bark", V(0, -0.2, 0), V(0, 4.6, 0), 0.16, 8, 0.05)
    for t in range(6):
        y = 1.0 + t * 0.62
        spread = 1.35 * (1 - t / 6.5)
        for i in range(7):
            a = i / 7 * 2 * pi + rng.uniform(-0.3, 0.3) + t
            out = V(cos(a), 0, sin(a))
            k.cyl("Bark", V(0, y, 0), V(0, y, 0) + out * spread * 0.8 + V(0, -0.15, 0), 0.03, 4, 0.01)
            _blob(k, "Needles", V(0, y + 0.05, 0) + out * spread * rng.uniform(0.45, 0.8), spread * rng.uniform(0.35, 0.5), 0.45, 1)
    _blob(k, "Needles", V(0, 4.5, 0), 0.35, 1.2, 1)
    return k.finish("Pine")


def dead_tree(seed=760):
    k = Kit(seed)
    rng = k.rng

    def limb(a, d, length, r, depth):
        b = a + d * length
        k.cyl("Bark", a, b, r, 6, r * 0.65)
        if depth == 0 or r < 0.02:
            return
        for n in range(2):
            turn = Euler((rng.uniform(-0.7, 0.7), rng.uniform(0, 2 * pi), rng.uniform(-0.7, 0.7)), "XYZ").to_matrix()
            child = (turn @ d).normalized()
            child.y = abs(child.y) * 0.7 + 0.2
            limb(b, child.normalized(), length * rng.uniform(0.55, 0.75), r * 0.65, depth - 1)

    limb(V(0, -0.2, 0), V(0.1, 1, 0.05).normalized(), 1.8, 0.16, 4)
    return k.finish("DeadTree")


def rock(seed, layered=True):
    """Weathered sandstone: a lumpy boulder with flat-ish bedding steps."""
    k = Kit(seed)
    rng = k.rng
    k.ico("Rock", V(0, 0.1, 0), 1.0, (1.0, 0.55, 0.8), 3, 0.18)
    bm = k.bm("Rock")
    for v in bm.verts:
        if layered:
            # Terrace the top into ledges.
            step = 0.16
            y = v.co.y
            v.co.y = (int(y / step) + min(1.0, (y % step) / step * 3.0)) * step if y > 0 else y
        v.co.x += 0.06 * sin(v.co.y * 9 + seed)
    for i in range(rng.randint(2, 4)):
        a = rng.uniform(0, 2 * pi)
        k.ico("Rock", V(cos(a) * 1.0, 0.0, sin(a) * 0.8), rng.uniform(0.15, 0.3), (1, 0.6, 1), 1, 0.3)
    return k.finish("Rock")


build_all([
    ("pole", pole),
    ("km_post", km_post),
    ("station_sign", station_sign),
    ("scrub", scrub),
    ("scrub_b", lambda: scrub(711)),
    ("cactus", cactus),
    ("cactus_b", lambda: cactus(1, 721)),
    ("grass", grass),
    ("tree", tree),
    ("pine", pine),
    ("dead_tree", dead_tree),
    ("rock", lambda: rock(770)),
    ("rock_b", lambda: rock(771, False)),
])
