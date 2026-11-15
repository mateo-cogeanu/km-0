"""Regenerate the synthesized sounds in assets/audio/ending (stdlib only).

The recorded voices and creature sounds in that folder are not made here.
"""

from array import array
from math import exp, pi, sin
from pathlib import Path
from random import Random
from sys import byteorder
import wave

RATE = 24000
OUT = Path(__file__).resolve().parents[1] / "assets/audio/ending"


def band(samples, low, high):
    """Two one-pole filters: a low-pass at high, then a high-pass at low."""
    fast_a = 1 - exp(-2 * pi * high / RATE)
    slow_a = 1 - exp(-2 * pi * low / RATE)
    fast = slow = 0.0
    out = []
    for sample in samples:
        fast += fast_a * (sample - fast)
        slow += slow_a * (fast - slow)
        out.append(fast - slow)
    return out


def noise(count, seed):
    rng = Random(seed)
    return [rng.uniform(-1, 1) for _ in range(count)]


def write(name, mix, gain):
    peak = max(map(abs, mix)) or 1.0
    samples = array("h", (round(x * 32767 * gain / peak) for x in mix))
    if byteorder != "little":
        samples.byteswap()
    with wave.open(str(OUT / (name + ".wav")), "wb") as stream:
        stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(samples.tobytes())


def add(mix, start, sound, level=1.0):
    for i, value in enumerate(sound):
        if 0 <= start + i < len(mix):
            mix[start + i] += value * level


# A wall clock: a dry wooden tick and a slightly lower tock, one per second.
def tick(seed, low, high, length=0.03):
    count = int(length * RATE)
    body = band(noise(count, seed), low, high)
    return [b * exp(-i / (0.004 * RATE)) for i, b in enumerate(body)]


clock = [0.0] * (2 * RATE)
add(clock, 0, tick(11, 1800, 5200))
add(clock, RATE, tick(12, 1300, 4200), 0.85)
write("clock_tick", clock, 0.5)

# The low electrical hum of an old house: mains and a few harmonics, a little
# hiss, slowly breathing. Four seconds that loop cleanly.
count = 4 * RATE
hiss = band(noise(count, 21), 400, 2400)
hum = []
for i in range(count):
    t = i / RATE
    swell = 1 + 0.08 * sin(2 * pi * 0.25 * t)
    hum.append(swell * (0.6 * sin(2 * pi * 50 * t) + 0.32 * sin(2 * pi * 100 * t)
        + 0.12 * sin(2 * pi * 150 * t) + 0.05 * sin(2 * pi * 250 * t)) + 0.05 * hiss[i])
write("house_hum", hum, 0.35)

# A failing bulb: a relay snap, then a short buzzing stutter.
count = int(0.42 * RATE)
flicker = [0.0] * count
add(flicker, 0, tick(31, 900, 6000, 0.02), 1.0)
crackle = band(noise(count, 32), 1200, 7000)
for i in range(count):
    t = i / RATE
    gate = 1.0 if (int(t * 61) % 3) else 0.15
    flicker[i] += gate * exp(-t * 7) * (0.35 * sin(2 * pi * 100 * t) + 0.18 * crackle[i])
write("flicker", flicker, 0.55)

# A joint popping the wrong way: a few hard, close snaps.
count = int(0.3 * RATE)
crack = [0.0] * count
rng = Random(41)
for k, start in enumerate([0, 0.018, 0.031, 0.07]):
    snap = band(noise(int(0.012 * RATE), 42 + k), 1500, 9000)
    add(crack, int(start * RATE), [s * exp(-i / (0.0018 * RATE)) for i, s in enumerate(snap)], 1.0 - k * 0.2)
low = band(noise(count, 49), 120, 600)
for i in range(count):
    crack[i] += 0.4 * low[i] * exp(-i / (0.02 * RATE))
write("crack", crack, 0.8)

# The hit: a dry slap right at your ear, a body thump under it, and a short
# rasping shriek that cuts off. Loud but capped well below clipping.
count = int(1.1 * RATE)
hit = [0.0] * count
slap = band(noise(int(0.05 * RATE), 51), 700, 9000)
add(hit, 0, [s * exp(-i / (0.006 * RATE)) for i, s in enumerate(slap)], 1.0)
for i in range(int(0.4 * RATE)):
    t = i / RATE
    hit[i] += 0.9 * sin(2 * pi * (70 - 30 * t) * t) * exp(-t * 11)
rasp = band(noise(count, 52), 900, 5200)
for i in range(count):
    t = i / RATE
    if t < 0.025:
        continue
    shape = min(1.0, (t - 0.025) / 0.03) * exp(-(t - 0.025) * 3.2) * (1.0 if t < 0.85 else max(0.0, 1 - (t - 0.85) / 0.05))
    tone = sin(2 * pi * 1170 * t + 3 * sin(2 * pi * 37 * t)) + 0.7 * sin(2 * pi * 1655 * t) + 0.5 * sin(2 * pi * 2310 * t)
    hit[i] += shape * (0.28 * tone + 0.55 * rasp[i])
write("hit", hit, 0.89)
