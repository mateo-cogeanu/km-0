"""Point each prop .glb's materials at the game's own material files
(scripts/prop_materials.gd saves them to assets/desert/props/materials/).

Run with plain Python after Godot has imported the .glb files once:
    python3 Sources/link_prop_materials.py
then let Godot import again. Edits the _subresources line of each .glb.import.
"""

import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FOLDER = "res://assets/desert/props/materials/"
GLBS = sorted((ROOT / "assets/desert/props").glob("*.glb")) + [
    ROOT / "assets/vehicles/parts" / (name + ".glb")
    for name in ("stockengine", "v8engine", "electricmotor", "radiatorassembly", "batterypack", "airfilter", "coolantreservoir")]


def snake(title):
    # Matches prop_materials.gd file_for().
    return title.lower().replace(" ", "_")


def materials(path):
    data = path.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + length])
    return [m.get("name", "") for m in doc.get("materials", [])]


for glb in GLBS:
    imp = glb.with_suffix(".glb.import")
    if not imp.exists():
        print("not imported yet:", glb.name)
        continue
    entries = []
    for name in materials(glb):
        entries.append('"%s": {\n"use_external/enabled": true,\n"use_external/path": "%s%s.tres"\n}' % (name, FOLDER, snake(name)))
    block = '_subresources={\n"materials": {\n' + ",\n".join(entries) + "\n}\n}"
    text = imp.read_text()
    text = re.sub(r"_subresources=\{.*?\n\}(?=\n[a-z_/]+=|\n\n|\Z)", block, text, count=1, flags=re.S) if "_subresources={\n" in text else text.replace("_subresources={}", block)
    imp.write_text(text)
    print("linked", glb.name, len(entries), "materials")
