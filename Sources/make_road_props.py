"""The small things on the desert road, built piece by piece: the jerrycan,
the spray can, tins, a soda can, chocolate, crackers, an apple, jerky, a water
bottle, batteries, a road flare, the cooler, toolbox and cabinet you search,
the notes, and the parts that go in an engine bay (two engines, the electric
motor, radiator, battery, air filter, coolant reservoir, the bike engine).

Run with Blender 5.1 or newer:
    Blender -b --python Sources/make_road_props.py

Coordinates are Godot's (desert_kit.py). Every model keeps the size and origin
of the one it replaces, so the game's colliders, hold points and engine-bay
mounts still fit:
  - fuel can: bottom at y = -0.02, about 0.46 x 0.75 x 0.19 (scenes/fuel_canister.tscn)
  - spray can: radius 0.16, y from -0.30 to 0.43; the parts the game paints are
    a separate object named change_color (scripts/spray_can.gd)
  - food, supplies, notes: bottom at y = 0, the sizes in their scripts
  - loot boxes: the body, and the lid (or drawer) in the Lid node's own space
  - engine-bay parts: one mesh inside the old -0.97..0.97 cube, belts and
    pulleys toward +Z (the car turns them round); the car scales them.
Materials are named for what they are; scripts/prop_materials.gd makes the
game's versions, and the .glb imports point at them.
"""

import sys
from math import atan2, cos, pi, radians, sin, tan
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector
import desert_kit
from desert_kit import V, Kit, fix_normals, material, reset

import os
# KM0_PROPS_OUT sends everything to one folder instead (for trying changes).
OUT = Path(os.environ.get("KM0_PROPS_OUT", desert_kit.ROOT / "assets/desert/props"))
OUT.mkdir(parents=True, exist_ok=True)
PARTS = OUT if "KM0_PROPS_OUT" in os.environ else desert_kit.ROOT / "assets/vehicles/parts"

COLORS = {
    "Can paint": (0.5, 0.1, 0.07), "Tin plate": (0.7, 0.7, 0.68), "Label beans": (0.62, 0.25, 0.15),
    "Label soup": (0.78, 0.62, 0.22), "Soda paint": (0.15, 0.36, 0.6), "Paper": (0.82, 0.78, 0.66),
    "Cardboard": (0.75, 0.5, 0.18), "Wrapper": (0.35, 0.15, 0.1), "Foil": (0.8, 0.78, 0.7),
    "Apple": (0.55, 0.12, 0.1), "Stem": (0.3, 0.22, 0.12), "Leaf": (0.25, 0.35, 0.15),
    "Pouch": (0.22, 0.3, 0.2), "Jerky": (0.35, 0.16, 0.08), "Bottle plastic": (0.75, 0.85, 0.92),
    "Cap blue": (0.15, 0.32, 0.6), "Flare red": (0.62, 0.12, 0.08), "Flare cap": (0.88, 0.86, 0.8),
    "Flare band": (0.85, 0.72, 0.2), "Battery card": (0.72, 0.2, 0.15), "Blister": (0.9, 0.92, 0.95),
    "Cell": (0.1, 0.1, 0.1), "Cell top": (0.75, 0.62, 0.3), "Cooler white": (0.82, 0.8, 0.74), "Cooler blue": (0.18, 0.35, 0.55),
    "Toolbox red": (0.6, 0.15, 0.12), "Cabinet steel": (0.45, 0.48, 0.44), "Brass": (0.6, 0.48, 0.25),
    "Ink": (0.12, 0.11, 0.1), "Notebook cover": (0.22, 0.28, 0.21), "Elastic": (0.08, 0.08, 0.08),
    "Photo": (0.14, 0.13, 0.12), "Postcard picture": (0.45, 0.55, 0.62), "Clipboard": (0.42, 0.32, 0.2),
    "Rubber": (0.04, 0.04, 0.04), "Cast iron": (0.24, 0.23, 0.22), "Cast aluminum": (0.6, 0.6, 0.58),
    "Machined steel": (0.55, 0.56, 0.56), "Molded graphite": (0.06, 0.06, 0.065), "Heat stained steel": (0.35, 0.28, 0.24),
    "Slate blue enamel": (0.2, 0.28, 0.38), "Crimson enamel": (0.5, 0.08, 0.06), "Ivory decal": (0.85, 0.82, 0.72),
    "High voltage orange": (0.85, 0.35, 0.05), "Service yellow": (0.85, 0.7, 0.1), "Coolant green": (0.2, 0.7, 0.3),
    "Reservoir nylon": (0.85, 0.83, 0.75), "Copper": (0.6, 0.35, 0.2), "Can white": (0.85, 0.84, 0.8),
    "Spray plastic": (0.8, 0.1, 0.06),
}
desert_kit.COLORS.update(COLORS)


def save(objs, path):
    for obj in objs:
        fix_normals(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
    print("exported", path.name, sum(len(o.data.polygons) for o in objs), "faces")


def build(name, make, folder=OUT):
    reset()
    result = make()
    save(result if isinstance(result, list) else [result], folder / (name + ".glb"))


def ring(k, mat, y, r, h, sides=16, r_in=None):
    k.cyl(mat, V(0, y, 0), V(0, y + h, 0), r, sides)


# --- Fuel can and spray can ---------------------------------------------------------

def canister():
    """A 20 litre jerrycan: welded seam round the middle, the pressed X in each
    face, three handles, a spout with its cam-locked cap."""
    k = Kit(800)
    w, d, y0, y1 = 0.46, 0.19, -0.02, 0.62
    hw, hd = w / 2, d / 2
    # The body, its corners softened with chamfer strips.
    k.box("Can paint", V(0, (y0 + y1) / 2, 0), (w - 0.03, y1 - y0, d))
    k.box("Can paint", V(0, (y0 + y1) / 2, 0), (w, y1 - y0 - 0.03, d - 0.03))
    for sx in (-1, 1):
        for sz in (-1, 1):
            k.cyl("Can paint", V(sx * (hw - 0.015), y0 + 0.015, sz * (hd - 0.015)), V(sx * (hw - 0.015), y1 - 0.015, sz * (hd - 0.015)), 0.015, 6)
    # Weld seam round the middle.
    k.box("Can paint", V(0, (y0 + y1) / 2, 0), (w + 0.012, y1 - y0 - 0.02, 0.012))
    k.box("Can paint", V(0, y1 + 0.004, 0), (w - 0.04, 0.012, 0.012))
    # The pressed X and its border on each face.
    for sz in (-1, 1):
        z = sz * (hd + 0.004)
        cy = (y0 + y1) / 2
        ang = atan2(y1 - y0 - 0.12, w - 0.1)
        diag = ((w - 0.1) ** 2 + (y1 - y0 - 0.12) ** 2) ** 0.5
        for a in (ang, -ang):
            k.box("Can paint", V(0, cy, z), (diag, 0.03, 0.01), (0, 0, a))
        for su, sy, u, y in ((w - 0.06, 0.02, 0, y1 - 0.04), (w - 0.06, 0.02, 0, y0 + 0.04), (0.02, y1 - y0 - 0.08, -hw + 0.03, cy), (0.02, y1 - y0 - 0.08, hw - 0.03, cy)):
            k.box("Can paint", V(u, y, z), (su, sy, 0.008))
    # Three handles joined by a top rail.
    for x in (-0.13, 0.0, 0.13):
        k.cyl("Can paint", V(x, y1, 0), V(x, y1 + 0.1, 0), 0.014, 8)
    k.cyl("Can paint", V(-0.15, y1 + 0.1, 0), V(0.15, y1 + 0.1, 0), 0.016, 8)
    k.cyl("Can paint", V(-0.15, y1 + 0.1, 0), V(-0.19, y1 + 0.02, 0), 0.014, 8)
    k.cyl("Can paint", V(0.15, y1 + 0.1, 0), V(0.19, y1 + 0.02, 0), 0.014, 8)
    # Spout at the front corner, the cap clamped over it, a breather.
    base = V(-hw + 0.06, y1 - 0.01, 0)
    tip = base + V(-0.07, 0.07, 0)
    k.cyl("Can paint", base, tip, 0.032, 12)
    k.cyl("Can paint", tip, tip + V(-0.025, 0.025, 0), 0.038, 12)
    k.box("Machined steel", tip + V(0.01, -0.03, 0.04), (0.06, 0.012, 0.012), (0, 0, radians(45)))
    k.box("Machined steel", tip + V(0.02, -0.0, 0.0), (0.012, 0.06, 0.09), (0, 0, radians(45)))
    # A flexible pouring spout clipped to the side, as they were carried.
    k.cyl("Machined steel", V(hw + 0.012, 0.12, 0.0), V(hw + 0.012, 0.42, 0.0), 0.022, 10)
    k.cyl("Machined steel", V(hw + 0.012, 0.42, 0.0), V(hw + 0.05, 0.48, 0.0), 0.012, 8)
    for y in (0.16, 0.38):
        k.box("Machined steel", V(hw + 0.005, y, 0), (0.02, 0.02, 0.05))
    return k.finish("FuelCan")


def spray_can():
    """Radius 0.16, y -0.30..0.43 (the game's oversized can). The band and the
    nozzle are change_color, which the game paints."""
    k = Kit(801)
    r = 0.155
    k.cyl("Can white", V(0, -0.29, 0), V(0, 0.31, 0), r, 20)
    k.cyl("Tin plate", V(0, -0.304, 0), V(0, -0.285, 0), r - 0.01, 20)
    k.cyl("Tin plate", V(0, -0.29, 0), V(0, -0.27, 0), r + 0.006, 20)
    k.cyl("Tin plate", V(0, 0.31, 0), V(0, 0.37, 0), r, 20, 0.07)
    k.cyl("Tin plate", V(0, 0.3, 0), V(0, 0.322, 0), r + 0.006, 20)
    k.cyl("Tin plate", V(0, 0.37, 0), V(0, 0.385, 0), 0.075, 14)
    # A dent low on one side.
    k.box("Tin plate", V(0.14, -0.1, 0.05), (0.04, 0.08, 0.07), (0, 0.35, 0.2))
    body = k.finish("SprayCan")
    p = Kit(802)
    p.cyl("Spray plastic", V(0, -0.16, 0), V(0, 0.2, 0), r + 0.004, 20)
    p.cyl("Spray plastic", V(0, 0.385, 0), V(0, 0.425, 0), 0.04, 12)
    p.box("Spray plastic", V(0.03, 0.41, 0), (0.025, 0.02, 0.02))
    paint = p.finish("change_color")
    return [body, paint]


# --- Food -------------------------------------------------------------------------

def tin(label, h=0.11, r=0.042):
    k = Kit(810)
    k.cyl("Tin plate", V(0, 0.004, 0), V(0, h - 0.004, 0), r - 0.001, 16)
    for y in (0.0, h - 0.008):
        k.cyl("Tin plate", V(0, y, 0), V(0, y + 0.008, 0), r + 0.001, 16)
    for y in (0.02, h - 0.02):
        k.cyl("Tin plate", V(0, y - 0.002, 0), V(0, y + 0.002, 0), r + 0.0005, 16)
    k.cyl(label, V(0, 0.026, 0), V(0, h - 0.026, 0), r + 0.0015, 16)
    k.box("Paper", V(r + 0.0012, h / 2, 0), (0.002, h * 0.25, r * 0.7))
    k.cyl("Tin plate", V(0, h - 0.009, 0), V(0, h - 0.004, 0), r - 0.006, 16)
    return k.finish("Tin")


def soda():
    k = Kit(811)
    r, h = 0.033, 0.12
    k.cyl("Tin plate", V(0, 0, 0), V(0, 0.008, 0), r - 0.006, 14, r)
    k.cyl("Soda paint", V(0, 0.008, 0), V(0, h - 0.016, 0), r, 14)
    k.cyl("Tin plate", V(0, h - 0.016, 0), V(0, h - 0.004, 0), r, 14, r - 0.007)
    k.cyl("Tin plate", V(0, h - 0.004, 0), V(0, h, 0), r - 0.006, 14)
    k.box("Tin plate", V(0.008, h + 0.001, 0), (0.018, 0.002, 0.01))
    k.box("Can white", V(0, 0.06, r + 0.0008), (0.03, 0.03, 0.001))
    return k.finish("Soda")


def chocolate():
    k = Kit(812)
    k.box("Wrapper", V(0, 0.009, 0), (0.13, 0.018, 0.058))
    for sx in (-1, 1):
        k.box("Wrapper", V(sx * 0.072, 0.006, 0), (0.016, 0.004, 0.06), (0, 0, sx * 0.1))
        for i in range(4):
            k.box("Wrapper", V(sx * 0.077, 0.006, -0.022 + i * 0.015), (0.008, 0.005, 0.006))
    k.box("Foil", V(0.05, 0.0185, 0), (0.03, 0.002, 0.056))
    k.box("Ivory decal", V(0, 0.0185, 0), (0.06, 0.002, 0.059))
    return k.finish("Chocolate")


def crackers():
    k = Kit(813)
    k.box("Cardboard", V(0, 0.095, 0), (0.15, 0.19, 0.05))
    k.box("Cardboard", V(0, 0.196, -0.012), (0.148, 0.004, 0.03), (radians(-25), 0, 0))
    k.box("Cardboard", V(0, 0.193, 0.015), (0.148, 0.004, 0.02), (radians(15), 0, 0))
    k.box("Paper", V(0, 0.12, 0.0255), (0.11, 0.08, 0.002))
    for i in range(3):
        k.cyl("Cardboard", V(-0.03 + i * 0.03, 0.105, 0.027), V(-0.03 + i * 0.03, 0.105, 0.029), 0.013, 8)
    k.box("Label beans", V(0, 0.045, 0.0255), (0.13, 0.025, 0.002))
    return k.finish("Crackers")


def apple():
    k = Kit(814)
    k.ico("Apple", V(0, 0.038, 0), 0.04, (1.0, 0.92, 1.0), 2, 0.04)
    k.ico("Apple", V(0, 0.07, 0), 0.012, (1, 0.4, 1), 1, 0.0)
    k.cyl("Stem", V(0, 0.07, 0), V(0.004, 0.092, 0), 0.0025, 5)
    k.box("Leaf", V(0.012, 0.086, 0), (0.02, 0.002, 0.01), (0, 0.3, 0.4))
    return k.finish("Apple")


def jerky():
    k = Kit(815)
    k.box("Pouch", V(0, 0.08, 0), (0.12, 0.15, 0.024))
    for sx in (-1, 1):
        k.cyl("Pouch", V(sx * 0.058, 0.01, 0), V(sx * 0.058, 0.152, 0), 0.008, 6)
    k.box("Pouch", V(0, 0.162, 0), (0.122, 0.018, 0.006))
    for i in range(12):
        k.box("Pouch", V(-0.055 + i * 0.01, 0.165, 0.0035), (0.004, 0.012, 0.001))
    k.box("Pouch", V(0, 0.005, 0), (0.118, 0.012, 0.03))
    k.box("Jerky", V(0, 0.075, 0.0125), (0.07, 0.07, 0.002))
    k.box("Ivory decal", V(0, 0.13, 0.0125), (0.09, 0.02, 0.002))
    return k.finish("Jerky")


# --- Supplies -----------------------------------------------------------------------

def water_bottle():
    """The game draws the water inside; this is the bottle, cap and label."""
    k = Kit(820)
    r = 0.034
    k.cyl("Bottle plastic", V(0, 0.0, 0), V(0, 0.012, 0), r - 0.006, 16, r)
    for i in range(7):
        y = 0.012 + i * 0.026
        k.cyl("Bottle plastic", V(0, y, 0), V(0, y + 0.02, 0), r, 16)
        k.cyl("Bottle plastic", V(0, y + 0.02, 0), V(0, y + 0.026, 0), r - 0.003, 16)
    k.cyl("Bottle plastic", V(0, 0.194, 0), V(0, 0.222, 0), r, 16, 0.015)
    k.cyl("Bottle plastic", V(0, 0.222, 0), V(0, 0.228, 0), 0.014, 12)
    k.cyl("Bottle plastic", V(0, 0.226, 0), V(0, 0.229, 0), 0.018, 12)
    k.cyl("Cap blue", V(0, 0.229, 0), V(0, 0.246, 0), 0.0155, 14)
    k.cyl("Paper", V(0, 0.07, 0), V(0, 0.13, 0), r + 0.0012, 16)
    k.box("Cap blue", V(0, 0.1, r + 0.0018), (0.03, 0.025, 0.001))
    return k.finish("WaterBottle")


def batteries():
    k = Kit(821)
    k.box("Battery card", V(0, 0.06, 0), (0.09, 0.12, 0.004))
    k.box("Ivory decal", V(0, 0.105, 0.0022), (0.07, 0.016, 0.001))
    k.cyl("Battery card", V(0, 0.118, -0.002), V(0, 0.118, 0.002), 0.006, 10)
    k.box("Blister", V(0, 0.055, 0.009), (0.084, 0.07, 0.014))
    for i in range(4):
        x = -0.03 + i * 0.02
        k.cyl("Cell", V(x, 0.028, 0.009), V(x, 0.078, 0.009), 0.0068, 10)
        k.cyl("Cell top", V(x, 0.07, 0.009), V(x, 0.078, 0.009), 0.0069, 10)
        k.cyl("Machined steel", V(x, 0.078, 0.009), V(x, 0.081, 0.009), 0.0025, 6)
    return k.finish("Batteries")


def flare():
    k = Kit(822)
    k.cyl("Flare red", V(0, 0.02, 0), V(0, 0.29, 0), 0.019, 12)
    k.cyl("Rubber", V(0, 0.0, 0), V(0, 0.02, 0), 0.006, 6, 0.017)
    k.cyl("Flare band", V(0, 0.18, 0), V(0, 0.22, 0), 0.0195, 12)
    k.cyl("Ivory decal", V(0, 0.08, 0), V(0, 0.14, 0), 0.0193, 12)
    k.cyl("Flare cap", V(0, 0.285, 0), V(0, 0.33, 0), 0.021, 12)
    k.cyl("Ink", V(0, 0.329, 0), V(0, 0.331, 0), 0.018, 12)
    return k.finish("Flare")


# --- Loot boxes ---------------------------------------------------------------------

def cooler_body():
    k = Kit(830)
    w, h, d = 0.6, 0.32, 0.36
    k.box("Cooler white", V(0, h / 2, 0), (w - 0.04, h, d))
    k.box("Cooler white", V(0, h / 2, 0), (w, h, d - 0.04))
    k.box("Cooler white", V(0, 0.01, 0), (w - 0.04, 0.02, d - 0.04))
    for sx in (-1, 1):
        for sz in (-1, 1):
            k.cyl("Cooler white", V(sx * (w / 2 - 0.02), 0.0, sz * (d / 2 - 0.02)), V(sx * (w / 2 - 0.02), h, sz * (d / 2 - 0.02)), 0.02, 8)
        # Moulded end handles.
        k.box("Cooler white", V(sx * (w / 2 + 0.01), h - 0.06, 0), (0.025, 0.04, 0.16))
        k.box("Dark interior", V(sx * (w / 2 - 0.002), h - 0.085, 0), (0.008, 0.02, 0.13))
    k.box("Cooler blue", V(0, 0.24, d / 2 + 0.002), (w - 0.06, 0.05, 0.004))
    k.box("Cooler blue", V(0, 0.24, -d / 2 - 0.002), (w - 0.06, 0.05, 0.004))
    k.cyl("Rubber", V(-w / 2 + 0.08, 0.04, d / 2), V(-w / 2 + 0.08, 0.04, d / 2 + 0.02), 0.016, 8)
    k.box("Dark interior", V(0, h - 0.004, 0), (w - 0.08, 0.006, d - 0.08))
    for x in (-0.2, 0.2):
        k.box("Machined steel", V(x, h - 0.01, -d / 2 - 0.006), (0.06, 0.03, 0.01))
    k.box("Machined steel", V(0, h - 0.04, d / 2 + 0.008), (0.05, 0.03, 0.012))
    return k.finish("CoolerBody")


def cooler_lid():
    """Lid space: hinged at its back edge (z = 0), front at z = 0.38."""
    k = Kit(831)
    k.box("Cooler blue", V(0, 0.025, 0.18), (0.6, 0.05, 0.34))
    k.box("Cooler blue", V(0, 0.022, 0.18), (0.62, 0.044, 0.38))
    k.box("Cooler blue", V(0, 0.052, 0.18), (0.5, 0.008, 0.26))
    for x in (-0.15, 0.15):
        k.box("Cooler blue", V(x, 0.058, 0.14), (0.02, 0.006, 0.12))
    for x in (-0.2, 0.2):
        k.cyl("Machined steel", V(x - 0.03, 0.0, 0.0), V(x + 0.03, 0.0, 0.0), 0.008, 6)
    k.box("Cooler white", V(0, 0.005, 0.385), (0.07, 0.04, 0.012))
    return k.finish("CoolerLid")


def toolbox_body():
    k = Kit(832)
    w, h, d = 0.48, 0.18, 0.22
    k.box("Toolbox red", V(0, h / 2, 0), (w, h, d))
    for y in (0.04, 0.12):
        k.box("Toolbox red", V(0, y, d / 2 + 0.003), (w - 0.04, 0.012, 0.006))
        k.box("Toolbox red", V(0, y, -d / 2 - 0.003), (w - 0.04, 0.012, 0.006))
    k.box("Toolbox red", V(0, h - 0.006, 0), (w + 0.01, 0.012, d + 0.01))
    for x in (-0.15, 0.15):
        k.box("Machined steel", V(x, h - 0.03, d / 2 + 0.008), (0.04, 0.04, 0.01))
        k.box("Machined steel", V(x, h - 0.012, d / 2 + 0.012), (0.03, 0.01, 0.006))
    k.box("Dark interior", V(0, h - 0.003, 0), (w - 0.02, 0.004, d - 0.02))
    k.box("Molded graphite", V(0, h - 0.06, 0), (w - 0.03, 0.006, d - 0.03))
    return k.finish("ToolboxBody")


def toolbox_lid():
    """Lid space: hinged at the back (z = 0), front at z = 0.23."""
    k = Kit(833)
    k.box("Toolbox red", V(0, 0.015, 0.115), (0.49, 0.03, 0.23))
    k.box("Toolbox red", V(0, 0.035, 0.115), (0.46, 0.012, 0.18))
    k.cyl("Machined steel", V(-0.24, 0.0, 0.0), V(0.24, 0.0, 0.0), 0.006, 6)
    for x in (-0.07, 0.07):
        k.box("Machined steel", V(x, 0.05, 0.115), (0.012, 0.03, 0.02))
    k.cyl("Molded graphite", V(-0.09, 0.07, 0.115), V(0.09, 0.07, 0.115), 0.012, 8)
    return k.finish("ToolboxLid")


def cabinet_body():
    """An old steel cabinet: sides, top, back, base, the lower door; the
    drawer is separate."""
    k = Kit(834)
    w, h, d = 0.6, 0.8, 0.45
    for sx in (-1, 1):
        k.box("Cabinet steel", V(sx * 0.285, 0.4, 0), (0.03, 0.8, 0.45))
    k.box("Cabinet steel", V(0, 0.785, 0), (0.62, 0.03, 0.47))
    k.box("Cabinet steel", V(0, 0.4, -0.21), (0.6, 0.8, 0.03))
    k.box("Rubber", V(0, 0.03, 0), (0.58, 0.06, 0.43))
    k.box("Cabinet steel", V(0, 0.25, 0.21), (0.54, 0.38, 0.03))
    k.box("Cabinet steel", V(0, 0.25, 0.228), (0.48, 0.32, 0.006))
    k.box("Machined steel", V(0.21, 0.3, 0.235), (0.02, 0.08, 0.02))
    k.box("Dark interior", V(0, 0.55, 0.0), (0.53, 0.24, 0.4))
    for y in (0.43, 0.67):
        k.box("Cabinet steel", V(0, y, 0.2), (0.54, 0.012, 0.04))
    for sx in (-1, 1):
        for y in (0.2, 0.6):
            k.box("Dark interior", V(sx * 0.301, y, 0.0), (0.002, 0.012, 0.3))
    return k.finish("CabinetBody")


def cabinet_drawer():
    """Drawer space (the Lid node): front at z = 0.21, floor at y = -0.1."""
    k = Kit(835)
    k.box("Cabinet steel", V(0, 0, 0.21), (0.54, 0.22, 0.03))
    k.box("Cabinet steel", V(0, 0, 0.228), (0.5, 0.18, 0.006))
    k.box("Cabinet steel", V(0, -0.1, 0.01), (0.52, 0.02, 0.4))
    for sx in (-1, 1):
        k.box("Cabinet steel", V(sx * 0.255, -0.04, 0.01), (0.01, 0.12, 0.4))
    k.box("Cabinet steel", V(0, -0.04, -0.19), (0.52, 0.12, 0.01))
    k.box("Brass", V(0, 0.02, 0.24), (0.14, 0.025, 0.012))
    for sx in (-1, 1):
        k.box("Brass", V(sx * 0.07, 0.02, 0.232), (0.012, 0.025, 0.02))
    k.box("Brass", V(0, -0.05, 0.234), (0.07, 0.03, 0.004))
    k.box("Paper", V(0, -0.05, 0.236), (0.06, 0.022, 0.001))
    return k.finish("CabinetDrawer")


# --- Notes --------------------------------------------------------------------------

def writing(k, x0, z0, width, rows, pitch, y, rng):
    for i in range(rows):
        length = width * rng.uniform(0.55, 1.0)
        k.box("Ink", V(x0 + length / 2, y, z0 + i * pitch), (length, 0.0008, 0.0035))


def note_paper():
    """A folded sheet, opened out: two halves meeting at a crease."""
    k = Kit(840)
    for side in (-1, 1):
        k.box("Paper", V(0, 0.002 + 0.004, side * 0.07), (0.21, 0.002, 0.14), (side * radians(-3), 0, 0))
    k.box("Paper", V(0, 0.0025, 0), (0.21, 0.002, 0.006))
    writing(k, -0.09, -0.11, 0.17, 4, 0.025, 0.0085, k.rng)
    writing(k, -0.09, 0.03, 0.17, 3, 0.025, 0.0085, k.rng)
    k.box("Paper", V(0.1, 0.008, 0.13), (0.03, 0.003, 0.03), (0, 0.6, radians(30)))
    return k.finish("Note")


def note_notebook():
    k = Kit(841)
    k.box("Notebook cover", V(0, 0.003, 0), (0.15, 0.003, 0.21))
    k.box("Notebook cover", V(0, 0.021, 0), (0.15, 0.003, 0.21))
    k.box("Paper", V(0.004, 0.012, 0), (0.142, 0.016, 0.204))
    k.box("Notebook cover", V(-0.074, 0.012, 0), (0.006, 0.022, 0.21))
    k.box("Elastic", V(0, 0.012, 0.06), (0.154, 0.024, 0.008))
    for i in range(14):
        k.box("Ink", V(0.075, 0.006 + i * 0.0011, 0), (0.001, 0.0008, 0.2))
    k.box("Ivory decal", V(0.0, 0.0226, -0.06), (0.06, 0.0008, 0.03))
    return k.finish("Notebook")


def note_postcard():
    k = Kit(842)
    k.box("Paper", V(0, 0.0015, 0), (0.15, 0.003, 0.1))
    k.box("Postcard picture", V(-0.035, 0.0032, 0), (0.07, 0.0008, 0.085))
    k.box("Ivory decal", V(-0.035, 0.0036, 0.02), (0.05, 0.0008, 0.01))
    k.box("Ink", V(0.04, 0.0032, 0), (0.002, 0.0008, 0.085))
    writing(k, 0.045, -0.03, 0.025, 4, 0.016, 0.0034, k.rng)
    k.box("Can paint", V(0.062, 0.0034, -0.035), (0.014, 0.0008, 0.017))
    return k.finish("Postcard")


def note_photo():
    k = Kit(843)
    k.box("Paper", V(0, 0.0015, 0), (0.09, 0.003, 0.105), (0, 0.0, 0))
    k.box("Photo", V(0, 0.0032, -0.008), (0.076, 0.0008, 0.076))
    k.box("Paper", V(0.04, 0.0035, 0.048), (0.012, 0.001, 0.012), (0, 0.5, 0.2))
    return k.finish("Photo")


def note_sheet():
    k = Kit(844)
    k.box("Clipboard", V(0, 0.005, 0), (0.23, 0.01, 0.32))
    k.box("Paper", V(0, 0.0115, 0.01), (0.21, 0.003, 0.28))
    k.box("Paper", V(0.003, 0.0135, 0.012), (0.205, 0.0015, 0.275), (0, 0.02, 0))
    writing(k, -0.09, -0.08, 0.18, 9, 0.022, 0.0146, k.rng)
    k.box("Ink", V(0, 0.0146, -0.105), (0.18, 0.0008, 0.004))
    k.box("Machined steel", V(0, 0.016, -0.14), (0.09, 0.008, 0.035))
    k.cyl("Machined steel", V(-0.045, 0.02, -0.15), V(0.045, 0.02, -0.15), 0.006, 6)
    k.box("Machined steel", V(0, 0.024, -0.13), (0.05, 0.004, 0.02), (radians(-20), 0, 0))
    return k.finish("Sheet")


# --- Engine bay parts (inside the -0.97..0.97 cube, belts toward +Z) -------------------

def pulley(k, at, r, depth=0.12, mat="Machined steel"):
    a = V(*at)
    k.cyl(mat, a - V(0, 0, depth / 2), a + V(0, 0, depth / 2), r, 18)
    k.cyl(mat, a + V(0, 0, depth / 2), a + V(0, 0, depth / 2 + 0.03), r * 0.35, 10)


def belt(k, points, z, width=0.09):
    for a, b in zip(points, points[1:] + points[:1]):
        k.span("Rubber", V(a[0], a[1], z), V(b[0], b[1], z), 0.025, width)


def inline_engine():
    """An inline four, run front to back along Z: oil pan, block, head, valve
    cover, intake on -X, exhaust manifold on +X, pulleys, belt and alternator
    at the front, the bellhousing flange behind."""
    k = Kit(850)
    k.box("Cast aluminum", V(0, -0.78, 0.05), (0.75, 0.36, 1.4))
    for i in range(6):
        k.box("Cast aluminum", V(0, -0.94, -0.55 + i * 0.22), (0.72, 0.04, 0.03))
    k.box("Cast iron", V(0, -0.2, 0.0), (0.9, 0.82, 1.5))
    for i in range(5):
        z = -0.6 + i * 0.3
        for sx in (-1, 1):
            k.box("Cast iron", V(sx * 0.46, -0.25, z), (0.04, 0.7, 0.06))
    k.box("Cast aluminum", V(0, 0.36, 0.0), (0.8, 0.3, 1.45))
    k.box("Slate blue enamel", V(0, 0.6, 0.0), (0.66, 0.18, 1.34))
    for i in range(6):
        k.box("Slate blue enamel", V(0, 0.7, -0.5 + i * 0.2), (0.5, 0.03, 0.04))
    k.cyl("Molded graphite", V(0.12, 0.69, 0.42), V(0.12, 0.76, 0.42), 0.07, 12)
    k.box("Ivory decal", V(0, 0.7, -0.05), (0.3, 0.005, 0.16))
    # Spark plug leads, from the plugs to a coil pack.
    for i in range(4):
        z = -0.48 + i * 0.32
        k.cyl("Molded graphite", V(-0.36, 0.5, z), V(-0.42, 0.62, z), 0.025, 6)
        k.span("Crimson enamel", V(-0.42, 0.62, z), V(-0.28, 0.82, -0.75), 0.018)
    k.box("Molded graphite", V(-0.28, 0.82, -0.78), (0.18, 0.1, 0.14))
    # Intake: four runners curving out to a plenum and the throttle body.
    for i in range(4):
        z = -0.48 + i * 0.32
        k.cyl("Cast aluminum", V(-0.42, 0.32, z), V(-0.62, 0.42, z), 0.07, 10)
        k.cyl("Cast aluminum", V(-0.62, 0.42, z), V(-0.72, 0.2, z), 0.07, 10)
    k.box("Cast aluminum", V(-0.78, 0.05, 0.0), (0.24, 0.38, 1.3))
    k.cyl("Cast aluminum", V(-0.78, 0.15, 0.66), V(-0.78, 0.15, 0.88), 0.12, 14)
    # Exhaust manifold: four pipes into a collector, heat stained.
    for i in range(4):
        z = -0.48 + i * 0.32
        k.cyl("Heat stained steel", V(0.42, 0.28, z), V(0.68, 0.22, z), 0.065, 10)
        k.cyl("Heat stained steel", V(0.68, 0.22, z), V(0.8, -0.1, z * 0.4), 0.065, 10)
    k.cyl("Heat stained steel", V(0.82, -0.1, 0.1), V(0.86, -0.85, 0.1), 0.1, 12)
    k.box("Heat stained steel", V(0.6, 0.27, 0.0), (0.04, 0.16, 1.3))
    # Front: timing cover, crank, water pump and alternator pulleys and the belt.
    k.box("Cast aluminum", V(0, -0.15, 0.78), (0.7, 0.9, 0.08))
    crank, pump, alt = (0, -0.6, 0.86), (0, 0.05, 0.86), (0.42, -0.02, 0.86)
    pulley(k, crank, 0.2)
    pulley(k, pump, 0.14)
    k.cyl("Cast aluminum", V(0.42, -0.02, 0.5), V(0.42, -0.02, 0.8), 0.17, 16)
    for i in range(8):
        a = i / 8 * 2 * pi
        k.box("Cast aluminum", V(0.42 + cos(a) * 0.16, -0.02 + sin(a) * 0.16, 0.65), (0.03, 0.03, 0.28), (0, 0, a))
    pulley(k, alt, 0.08)
    belt(k, [(0.0, -0.81), (0.2, -0.6), (0.5, -0.07), (0.42, 0.06), (0.13, 0.12), (0, 0.19), (-0.14, 0.05), (-0.2, -0.6)], 0.86)
    # Bellhousing flange behind, motor mounts, the dipstick.
    k.cyl("Cast aluminum", V(0, -0.25, -0.78), V(0, -0.25, -0.92), 0.7, 20)
    for sx in (-1, 1):
        k.box("Machined steel", V(sx * 0.55, -0.45, 0.2), (0.2, 0.12, 0.2))
        k.box("Rubber", V(sx * 0.66, -0.45, 0.2), (0.06, 0.16, 0.16))
    k.cyl("Machined steel", V(0.3, -0.3, 0.55), V(0.38, 0.55, 0.55), 0.012, 6)
    k.box("Service yellow", V(0.38, 0.58, 0.55), (0.06, 0.04, 0.04))
    return k.finish("StockEngine")


def v8_engine():
    """A V8: block, two banks of heads under red rocker covers, a centre intake
    with the carburettor pad, headers down both sides, pulleys and belt."""
    k = Kit(851)
    k.box("Cast iron", V(0, -0.8, 0.0), (0.8, 0.34, 1.45))
    k.box("Cast iron", V(0, -0.35, 0.0), (0.95, 0.65, 1.55))
    for sx in (-1, 1):
        # Each bank leans out 45 degrees.
        k.box("Cast iron", V(sx * 0.42, 0.1, 0.0), (0.44, 0.5, 1.5), (0, 0, -sx * radians(45)))
        k.box("Cast aluminum", V(sx * 0.6, 0.32, 0.0), (0.4, 0.2, 1.45), (0, 0, -sx * radians(45)))
        k.box("Crimson enamel", V(sx * 0.7, 0.44, 0.0), (0.3, 0.14, 1.35), (0, 0, -sx * radians(45)))
        for i in range(4):
            k.box("Crimson enamel", V(sx * 0.74, 0.49, -0.45 + i * 0.3), (0.28, 0.04, 0.05), (0, 0, -sx * radians(45)))
        k.cyl("Machined steel", V(sx * 0.66, 0.5, 0.55), V(sx * 0.7, 0.58, 0.55), 0.04, 8)
        # Headers: four tubes per side sweeping down to a collector.
        for i in range(4):
            z = -0.54 + i * 0.36
            k.cyl("Heat stained steel", V(sx * 0.66, 0.0, z), V(sx * 0.88, -0.1, z), 0.06, 10)
            k.cyl("Heat stained steel", V(sx * 0.88, -0.1, z), V(sx * 0.9, -0.6, z * 0.3 - 0.2), 0.06, 10)
        k.cyl("Heat stained steel", V(sx * 0.9, -0.6, -0.25), V(sx * 0.9, -0.92, -0.45), 0.1, 12)
        # Plug leads.
        for i in range(4):
            z = -0.54 + i * 0.36
            k.span("Molded graphite", V(sx * 0.58, 0.05, z), V(sx * 0.2, 0.75, -0.7), 0.016)
    # Intake manifold and its carburettor pad between the banks.
    k.box("Cast aluminum", V(0, 0.38, 0.0), (0.5, 0.35, 1.3))
    for i in range(4):
        k.box("Cast aluminum", V(0, 0.56, -0.45 + i * 0.3), (0.46, 0.04, 0.05))
    k.box("Cast aluminum", V(0, 0.62, 0.05), (0.3, 0.12, 0.3))
    for dx in (-0.06, 0.06):
        for dz in (-0.04, 0.12):
            k.cyl("Dark interior", V(dx, 0.68, 0.05 + dz - 0.04), V(dx, 0.69, 0.05 + dz - 0.04), 0.045, 10)
    # Distributor at the back.
    k.cyl("Molded graphite", V(0, 0.45, -0.72), V(0, 0.78, -0.75), 0.1, 12)
    k.cyl("Molded graphite", V(0, 0.78, -0.75), V(0, 0.84, -0.75), 0.14, 12)
    # Front: timing cover, three pulleys, the belt, a water pump.
    k.box("Cast aluminum", V(0, -0.25, 0.8), (0.6, 0.8, 0.08))
    crank, pump, alt = (0, -0.62, 0.88), (0, 0.08, 0.88), (-0.48, 0.05, 0.88)
    pulley(k, crank, 0.22)
    pulley(k, pump, 0.16)
    k.cyl("Cast aluminum", V(-0.48, 0.05, 0.5), V(-0.48, 0.05, 0.82), 0.17, 16)
    pulley(k, alt, 0.08)
    belt(k, [(0.0, -0.84), (0.22, -0.62), (0.16, 0.08), (0.0, 0.24), (-0.48, 0.13), (-0.56, 0.05), (-0.22, -0.62)], 0.88)
    k.cyl("Cast aluminum", V(0, 0.08, 0.95), V(0, 0.08, 0.97), 0.34, 4)
    for i in range(4):
        a = i / 4 * pi + 0.3
        k.box("Molded graphite", V(cos(a) * 0.16, 0.08 + sin(a) * 0.16, 0.96), (0.32, 0.06, 0.01), (0, 0, a))
    k.cyl("Cast aluminum", V(0, -0.25, -0.8), V(0, -0.25, -0.94), 0.7, 20)
    return k.finish("V8Engine")


def electric_motor():
    """A traction motor: finned aluminium drum along Z, the inverter box on
    top with orange high-voltage cables, a reduction gear case on -X."""
    k = Kit(852)
    k.cyl("Cast aluminum", V(0.1, -0.3, -0.75), V(0.1, -0.3, 0.7), 0.55, 24)
    for i in range(14):
        z = -0.68 + i * 0.1
        k.cyl("Cast aluminum", V(0.1, -0.3, z - 0.015), V(0.1, -0.3, z + 0.015), 0.6, 24)
    for z in (-0.78, 0.73):
        k.cyl("Cast iron", V(0.1, -0.3, z - 0.04), V(0.1, -0.3, z + 0.04), 0.58, 24)
    k.cyl("Machined steel", V(0.1, -0.3, 0.77), V(0.1, -0.3, 0.95), 0.08, 12)
    k.box("Cast iron", V(-0.68, -0.4, 0.1), (0.5, 0.8, 0.9))
    k.cyl("Machined steel", V(-0.95, -0.55, 0.1), V(-0.7, -0.55, 0.1), 0.1, 12)
    k.box("Cast aluminum", V(0.05, 0.45, -0.05), (0.85, 0.32, 1.1))
    for i in range(8):
        k.box("Cast aluminum", V(0.05, 0.62, -0.5 + i * 0.13), (0.8, 0.04, 0.03))
    k.box("Slate blue enamel", V(0.05, 0.645, 0.35), (0.4, 0.004, 0.2))
    k.box("Ivory decal", V(0.05, 0.648, 0.35), (0.3, 0.002, 0.08))
    for i, x in enumerate((-0.2, 0.05, 0.3)):
        k.cyl("High voltage orange", V(x, 0.45, 0.5), V(x, 0.45, 0.62), 0.06, 10)
        k.span("High voltage orange", V(x, 0.45, 0.62), V(x - 0.25, 0.1, 0.9), 0.05)
        k.span("High voltage orange", V(x - 0.25, 0.1, 0.9), V(-0.6, -0.4 - i * 0.12, 0.92), 0.05)
    k.box("Molded graphite", V(-0.35, 0.62, -0.45), (0.25, 0.08, 0.2))
    for sx in (-1, 1):
        k.box("Machined steel", V(0.1 + sx * 0.62, -0.75, 0.0), (0.18, 0.12, 0.3))
    k.box("High voltage orange", V(0.5, 0.45, -0.4), (0.12, 0.1, 0.18))
    return k.finish("ElectricMotor")


def radiator():
    """Core facing Z (the car squashes it thin), plastic end tanks, a filler
    neck and cap, hose stubs, the fan shroud and fan behind (-Z)."""
    k = Kit(853)
    k.box("Cast aluminum", V(0, -0.02, 0.15), (1.5, 1.6, 0.5))
    # Fins and tubes on the face, drawn as alternating strips.
    for i in range(26):
        y = -0.78 + i * 0.062
        k.box("Machined steel", V(0, y, 0.41), (1.48, 0.018, 0.02))
    for i in range(12):
        x = -0.68 + i * 0.124
        k.box("Cast aluminum", V(x, -0.02, 0.42), (0.012, 1.56, 0.01))
    for sx in (-1, 1):
        k.box("Molded graphite", V(sx * 0.85, -0.02, 0.15), (0.24, 1.75, 0.6))
        for y in (-0.6, 0.0, 0.6):
            k.box("Molded graphite", V(sx * 0.97 - sx * 0.02, y, 0.15), (0.04, 0.1, 0.4))
    k.cyl("Molded graphite", V(-0.85, 0.75, 0.15), V(-0.85, 0.95, 0.15), 0.08, 12)
    k.cyl("Service yellow", V(-0.85, 0.92, 0.15), V(-0.85, 0.97, 0.15), 0.1, 14)
    k.cyl("Rubber", V(0.85, 0.55, 0.15), V(0.85, 0.55, -0.5), 0.09, 12)
    k.cyl("Rubber", V(-0.85, -0.6, 0.15), V(-0.85, -0.6, -0.5), 0.09, 12)
    k.box("Molded graphite", V(0, -0.02, -0.25), (1.5, 1.6, 0.3))
    k.cyl("Dark interior", V(0, -0.02, -0.41), V(0, -0.02, -0.4), 0.72, 24)
    k.cyl("Molded graphite", V(0, -0.02, -0.4), V(0, -0.02, -0.7), 0.16, 14)
    for i in range(7):
        a = i / 7 * 2 * pi
        k.box("Molded graphite", V(cos(a) * 0.42, -0.02 + sin(a) * 0.42, -0.5), (0.5, 0.18, 0.03), (radians(12), 0, a))
    for sx in (-1, 1):
        k.box("Machined steel", V(sx * 0.7, 0.88, 0.15), (0.12, 0.1, 0.3))
        k.box("Rubber", V(sx * 0.7, -0.95, 0.15), (0.12, 0.04, 0.3))
    return k.finish("RadiatorAssembly")


def battery():
    k = Kit(854)
    k.box("Molded graphite", V(0, -0.15, 0), (1.9, 1.6, 1.7))
    for i in range(6):
        k.box("Molded graphite", V(-0.8 + i * 0.32, -0.15, 0.86), (0.04, 1.4, 0.04))
        k.box("Molded graphite", V(-0.8 + i * 0.32, -0.15, -0.86), (0.04, 1.4, 0.04))
    k.box("Molded graphite", V(0, 0.68, 0), (1.94, 0.12, 1.74))
    k.box("Molded graphite", V(0, 0.76, 0), (1.6, 0.06, 1.2))
    for i in range(6):
        k.cyl("Molded graphite", V(-0.6 + i * 0.24, 0.79, 0.15), V(-0.6 + i * 0.24, 0.83, 0.15), 0.07, 10)
    for sx, mat in ((-1, "Crimson enamel"), (1, "Molded graphite")):
        x = sx * 0.62
        k.cyl("Machined steel", V(x, 0.74, -0.5), V(x, 0.92, -0.5), 0.1, 12, 0.085)
        k.cyl(mat, V(x, 0.84, -0.5), V(x, 0.95, -0.5), 0.13, 12)
        k.box("Machined steel", V(x, 0.86, -0.32), (0.06, 0.04, 0.3))
    k.span("Rubber", V(-0.95, 0.74, 0.0), V(-0.55, 0.97, 0.0), 0.06, 0.18)
    k.span("Rubber", V(-0.55, 0.97, 0.0), V(0.55, 0.97, 0.0), 0.06, 0.18)
    k.span("Rubber", V(0.55, 0.97, 0.0), V(0.95, 0.74, 0.0), 0.06, 0.18)
    k.box("Slate blue enamel", V(0, -0.05, 0.855), (1.6, 0.7, 0.01))
    k.box("Ivory decal", V(-0.2, 0.05, 0.862), (1.0, 0.22, 0.005))
    k.box("Ivory decal", V(0.5, -0.25, 0.862), (0.4, 0.12, 0.005))
    return k.finish("BatteryPack")


def air_filter():
    k = Kit(855)
    k.cyl("Molded graphite", V(-0.08, -0.3, 0), V(-0.08, 0.12, 0), 0.32, 22)
    k.cyl("Molded graphite", V(-0.08, 0.12, 0), V(-0.08, 0.2, 0), 0.33, 22, 0.28)
    for i in range(10):
        a = i / 10 * 2 * pi
        k.box("Molded graphite", V(-0.08 + cos(a) * 0.325, -0.09, sin(a) * 0.325), (0.02, 0.36, 0.04), (0, -a, 0))
    k.cyl("Machined steel", V(-0.08, 0.2, 0), V(-0.08, 0.27, 0), 0.03, 8)
    k.box("Machined steel", V(-0.08, 0.3, 0), (0.14, 0.03, 0.03))
    k.cyl("Rubber", V(0.2, -0.1, 0), V(0.46, -0.1, 0), 0.11, 14)
    for x in (0.26, 0.32, 0.38):
        k.cyl("Rubber", V(x - 0.01, -0.1, 0), V(x + 0.01, -0.1, 0), 0.125, 14)
    k.box("Cast iron", V(-0.08, -0.31, 0), (0.3, 0.04, 0.3))
    k.box("Ivory decal", V(-0.08, 0.205, 0.18), (0.16, 0.002, 0.06))
    return k.finish("AirFilter")


def coolant_reservoir():
    k = Kit(856)
    k.box("Reservoir nylon", V(-0.08, 0.0, 0), (0.5, 0.48, 0.5))
    k.box("Reservoir nylon", V(-0.08, 0.0, 0), (0.54, 0.44, 0.46))
    k.box("Coolant green", V(-0.08, -0.12, 0.255), (0.42, 0.18, 0.004))
    for y in (-0.15, 0.1):
        k.box("Molded graphite", V(-0.08, y, 0.257), (0.1, 0.006, 0.004))
    k.cyl("Reservoir nylon", V(-0.08, 0.24, 0), V(-0.08, 0.28, 0), 0.09, 14)
    k.cyl("Service yellow", V(-0.08, 0.27, 0), V(-0.08, 0.305, 0), 0.11, 14)
    k.cyl("Rubber", V(0.15, -0.15, 0), V(0.39, -0.15, 0), 0.04, 10)
    k.cyl("Rubber", V(0.15, 0.15, 0.05), V(0.32, 0.22, 0.05), 0.025, 8)
    k.box("Cast iron", V(-0.08, -0.27, -0.2), (0.3, 0.06, 0.12))
    k.box("Cast iron", V(-0.08, 0.0, -0.29), (0.3, 0.4, 0.04))
    return k.finish("CoolantReservoir")


def bike_engine():
    """A single: a crankcase, the finned barrel leaning forward, a head, a
    carburettor and an exhaust stub. Inside +-0.225 x 0.19 x 0.215."""
    k = Kit(857)
    k.cyl("Cast aluminum", V(-0.12, -0.08, 0.06), V(0.12, -0.08, 0.06), 0.11, 18)
    k.box("Cast aluminum", V(0, -0.11, -0.03), (0.22, 0.13, 0.2))
    k.cyl("Machined steel", V(0.12, -0.08, 0.06), V(0.15, -0.08, 0.06), 0.05, 12)
    k.cyl("Cast aluminum", V(-0.15, -0.08, 0.06), V(-0.12, -0.08, 0.06), 0.08, 14)
    for i in range(7):
        y = -0.02 + i * 0.025
        k.box("Cast iron", V(0, y, -0.03 + i * 0.008), (0.2 - i * 0.004, 0.012, 0.19 - i * 0.004))
    k.cyl("Cast iron", V(0, -0.05, -0.02), V(0, 0.16, 0.02), 0.06, 12)
    k.box("Cast aluminum", V(0, 0.17, 0.02), (0.15, 0.04, 0.15))
    k.cyl("Machined steel", V(0.0, 0.19, 0.02), V(0.03, 0.19, 0.02), 0.012, 6)
    k.cyl("Cast aluminum", V(0, 0.08, -0.08), V(0, 0.08, -0.18), 0.035, 10)
    k.cyl("Molded graphite", V(0, 0.08, -0.18), V(0, 0.08, -0.215), 0.05, 12)
    k.cyl("Heat stained steel", V(0, 0.08, 0.1), V(0, 0.0, 0.2), 0.025, 10)
    k.cyl("Heat stained steel", V(0, 0.0, 0.2), V(0.1, -0.15, 0.2), 0.025, 10)
    return k.finish("BikeEngine")


build("canister", canister)
build("spraycan", spray_can)
build("food_beans", lambda: tin("Label beans"))
build("food_soup", lambda: tin("Label soup"))
build("food_soda", soda)
build("food_chocolate", chocolate)
build("food_crackers", crackers)
build("food_apple", apple)
build("food_jerky", jerky)
build("supply_water", water_bottle)
build("supply_batteries", batteries)
build("supply_flare", flare)
build("cooler_body", cooler_body)
build("cooler_lid", cooler_lid)
build("toolbox_body", toolbox_body)
build("toolbox_lid", toolbox_lid)
build("cabinet_body", cabinet_body)
build("cabinet_drawer", cabinet_drawer)
build("note_paper", note_paper)
build("note_notebook", note_notebook)
build("note_postcard", note_postcard)
build("note_photo", note_photo)
build("note_sheet", note_sheet)
build("bike_engine", bike_engine)
build("stockengine", inline_engine, PARTS)
build("v8engine", v8_engine, PARTS)
build("electricmotor", electric_motor, PARTS)
build("radiatorassembly", radiator, PARTS)
build("batterypack", battery, PARTS)
build("airfilter", air_filter, PARTS)
build("coolantreservoir", coolant_reservoir, PARTS)
