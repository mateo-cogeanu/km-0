"""Generate the short mechanical sound effects used by KM0."""
from array import array
from math import exp, pi, sin
from pathlib import Path
from random import Random
import sys
import wave

RATE = 24000
OUT = Path(__file__).resolve().parents[1] / "assets/audio/vehicle"


def write(name, duration, hits):
    rng = Random(name)
    samples = []
    noise = 0.0
    for index in range(round(duration * RATE)):
        time = index / RATE
        noise += 0.38 * (rng.uniform(-1, 1) - noise)
        value = 0.0
        for start, strength, decay, tones, scrape in hits:
            age = time - start
            if age < 0.0:
                continue
            attack = min(1.0, age * 1300)
            ring = sum(gain * sin(2 * pi * frequency * age) for frequency, gain in tones)
            value += strength * attack * exp(-age / decay) * (ring + scrape * noise)
        value *= min(1.0, (duration - time) * 90)
        samples.append(value)
    peak = max(abs(value) for value in samples)
    pcm = array("h", (round(28000 * value / peak) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(OUT / f"{name}.wav"), "wb") as stream:
        stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(pcm.tobytes())


write("engine_mount", 0.32, [
    (0.01, 1.0, 0.055, [(82, 0.64), (187, 0.23), (496, 0.12)], 0.24),
    (0.055, 0.33, 0.035, [(136, 0.49), (607, 0.20)], 0.33),
])
write("door_latch", 0.18, [
    (0.006, 0.49, 0.017, [(335, 0.25), (1185, 0.20)], 0.37),
    (0.042, 1.0, 0.026, [(249, 0.39), (759, 0.25), (1481, 0.12)], 0.28),
])
write("wheel_mount", 0.24, [
    (0.01, 1.0, 0.041, [(113, 0.46), (229, 0.36), (391, 0.12)], 0.50),
    (0.082, 0.22, 0.02, [(314, 0.28), (676, 0.18)], 0.25),
])
write("gravel_ping", 0.13, [
    (0.002, 1.0, 0.019, [(623, 0.27), (1367, 0.36), (2153, 0.13)], 0.31),
    (0.026, 0.32, 0.014, [(918, 0.38), (1670, 0.22)], 0.26),
])
write("panel_rattle", 0.21, [
    (0.005, 0.72, 0.027, [(145, 0.51), (496, 0.22)], 0.51),
    (0.044, 1.0, 0.022, [(212, 0.47), (637, 0.24)], 0.37),
    (0.095, 0.35, 0.033, [(157, 0.42), (525, 0.31)], 0.25),
])
