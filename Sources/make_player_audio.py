"""Regenerate the player's footsteps and flashlight click in assets/audio/player (stdlib only)."""

from array import array
from math import exp, pi, sin
from pathlib import Path
from random import Random
from sys import byteorder
import wave

RATE = 24000
OUT = Path(__file__).resolve().parents[1] / "assets/audio/player"
OUT.mkdir(parents=True, exist_ok=True)


def band(samples, low, high):
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


# Soft steps: the dull heel, then the sole rolling and scuffing a little.
for take in range(4):
    rng = Random(200 + take)
    count = int(0.26 * RATE)
    heel = band(noise(count, 210 + take), 70, 420 + take * 40)
    scuff = band(noise(count, 220 + take), 900, 3800)
    step = [0.0] * count
    roll = rng.uniform(0.045, 0.07)
    for i in range(count):
        t = i / RATE
        step[i] += heel[i] * exp(-t / 0.018) * 1.0
        if t > roll:
            u = t - roll
            step[i] += heel[i] * exp(-u / 0.022) * 0.55
            step[i] += scuff[i] * (u / 0.02 if u < 0.02 else exp(-(u - 0.02) / 0.05)) * rng.uniform(0.12, 0.2)
    write("step_%d" % (take + 1), step, 0.5)

# Landing after a jump or a drop.
count = int(0.35 * RATE)
thud = band(noise(count, 240), 50, 380)
grit = band(noise(count, 241), 700, 3000)
write("land", [thud[i] * exp(-i / (0.035 * RATE)) + 0.15 * grit[i] * exp(-i / (0.06 * RATE)) for i in range(count)], 0.6)

# A flashlight's switch: a small plastic click.
count = int(0.06 * RATE)
click = band(noise(count, 250), 1800, 8000)
body = band(noise(count, 251), 300, 1500)
write("flashlight_click", [click[i] * exp(-i / (0.0012 * RATE)) + 0.4 * body[i] * exp(-i / (0.006 * RATE)) for i in range(count)], 0.45)
