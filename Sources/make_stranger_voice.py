"""Pre-record the stranger's conversation into assets/audio/stranger (macOS only).

Run with: python3 Sources/make_stranger_voice.py

Reads every ["him" | "you", "line"] pair from scripts/stranger_house.gd and
renders it with a built-in macOS voice, so the game plays the same recording on
every machine. Files are named after the speaker and an MD5 of the line, which
the game computes the same way; edit a line and run this again.
"""

import hashlib
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/stranger_house.gd"
OUT = ROOT / "assets/audio/stranger"
VOICES = {
    "him": ("Grandpa (English (US))", 160),
    "you": ("Reed (English (US))", 175),
}

OUT.mkdir(parents=True, exist_ok=True)
lines = re.findall(r'\["(him|you)", "((?:[^"\\]|\\.)*)"', SCRIPT.read_text())
wanted = set()
for who, text in lines:
    name = f"{who}_{hashlib.md5(text.encode()).hexdigest()[:10]}.wav"
    wanted.add(name)
    target = OUT / name
    if target.exists():
        continue
    voice, rate = VOICES[who]
    with tempfile.TemporaryDirectory() as tmp:
        aiff = Path(tmp) / "line.aiff"
        subprocess.run(["say", "-v", voice, "-r", str(rate), "-o", str(aiff), text], check=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@24000", "-c", "1", str(aiff), str(target)], check=True)
    print("recorded", name, text)
for stale in OUT.glob("*.wav"):
    if stale.name not in wanted:
        stale.unlink()
        Path(str(stale) + ".import").unlink(missing_ok=True)
        print("removed", stale.name)
