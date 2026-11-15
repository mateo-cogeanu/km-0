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


def resonator(samples, freq, q):
    from math import cos as _cos
    w = 2 * pi * freq / RATE
    alpha = sin(w) / (2 * q)
    b0, b2 = alpha, -alpha
    a0, a1, a2 = 1 + alpha, -2 * _cos(w), 1 - alpha
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for x in samples:
        y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


# Water pouring from a bottle onto your face: a bubbly glug and a splashy hiss.
count = int(1.5 * RATE)
rng = Random(260)
splash = band(noise(count, 261), 900, 6500)
glug = [0.0] * count
t = 0.0
while t < 1.4:
    k = int(t * RATE)
    freq = rng.uniform(380, 720)
    n = int(0.04 * RATE)
    for i in range(n):
        if k + i < count:
            glug[k + i] += sin(2 * pi * freq * (1 + i / n * 0.6) * i / RATE) * exp(-i / (0.012 * RATE)) * 0.6
    t += rng.uniform(0.06, 0.13)
pour = []
for i in range(count):
    u = i / RATE
    edge = min(1.0, u / 0.08, (1.5 - u) / 0.15)
    pour.append(edge * (0.55 * splash[i] * (0.7 + 0.3 * sin(u * 23)) + glug[i]))
write("pour", pour, 0.5)

# A drawer sliding and a lid opening.
count = int(0.45 * RATE)
slide = band(noise(count, 270), 300, 2500)
write("drawer", [slide[i] * min(1.0, i / (0.03 * RATE)) * exp(-i / (0.25 * RATE)) * (0.8 + 0.2 * sin(i / RATE * 90)) for i in range(count)], 0.45)
count = int(0.35 * RATE)
thunk = band(noise(count, 271), 120, 900)
latch = band(noise(count, 272), 2000, 7000)
write("lid", [thunk[i] * exp(-i / (0.04 * RATE)) + 0.5 * latch[i] * exp(-i / (0.003 * RATE)) for i in range(count)], 0.5)

# Batteries clicking into the flashlight.
count = int(0.25 * RATE)
clicks = [0.0] * count
for k, at in enumerate((0.0, 0.07, 0.16)):
    snap = band(noise(int(0.01 * RATE), 280 + k), 2200, 8000)
    for i, s in enumerate(snap):
        clicks[int(at * RATE) + i] += s * exp(-i / (0.0015 * RATE))
write("batteries", clicks, 0.4)
