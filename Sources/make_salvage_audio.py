"""Synthesize the Salvage Run's sounds (stdlib only).

Writes to assets/audio/salvage:
  water_bed.wav    still floodwater lapping at walls and cars (loops)
  splash_1..4.wav  a footstep in knee-deep water
  scrape.wav       an engine block dragged over wet concrete (loops)
  listen.wav       the thing in the water, close: a wet, rattling click train
  surface.wav      something big breaking the surface
  grab.wav         a violent splash and churn
"""

from array import array
from math import exp, pi, sin
from pathlib import Path
from random import Random
from sys import byteorder
import wave

RATE = 24000
OUT = Path(__file__).resolve().parents[1] / "assets/audio/salvage"
OUT.mkdir(parents=True, exist_ok=True)


def write(name, mix, gain):
    peak = max(map(abs, mix)) or 1.0
    samples = array("h", (round(x * 32767 * gain / peak) for x in mix))
    if byteorder != "little":
        samples.byteswap()
    with wave.open(str(OUT / (name + ".wav")), "wb") as stream:
        stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(samples.tobytes())
    print("wrote", name, f"{len(mix) / RATE:.2f}s")


def lowpass(samples, cutoff):
    a = 1 - exp(-2 * pi * cutoff / RATE)
    y, out = 0.0, []
    for x in samples:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [x - l for x, l in zip(samples, low)]


def noise(count, seed):
    rng = Random(seed)
    return [rng.uniform(-1, 1) for _ in range(count)]


def looped(count, seed, cutoff):
    raw = noise(count, seed)
    doubled = lowpass(raw + raw, cutoff)
    return doubled[count:]


# Lapping water: soft filtered noise with slow, overlapping swells, and the
# odd drip and slap. Loops on a whole number of swells.
LOOP = 12.0
count = int(LOOP * RATE)
body = looped(count, 11, 700)
fizz = highpass(looped(count, 12, 4000), 1500)
bed = [0.0] * count
for i in range(count):
    t = i / RATE
    swell = 0.45 + 0.3 * sin(2 * pi * t * 2 / LOOP) + 0.25 * sin(2 * pi * t * 5 / LOOP + 1.3)
    bed[i] = body[i] * 3.0 * swell + fizz[i] * 0.6 * swell
rng = Random(13)
for _ in range(14):
    at = rng.randrange(count)
    pitch = rng.uniform(900, 1800)
    for j in range(int(0.08 * RATE)):
        k = (at + j) % count
        env = exp(-j / (0.012 * RATE))
        bed[k] += sin(2 * pi * pitch * (1 + 0.6 * j / RATE * 10) * j / RATE) * env * 0.5
write("water_bed", bed, 0.5)

# Footsteps in water: a push of low churn and a bright splash on top.
for n in range(1, 5):
    length = int(0.42 * RATE)
    churn = lowpass(noise(length, 20 + n), 500)
    spray = highpass(noise(length, 30 + n), 1800)
    step = [0.0] * length
    for i in range(length):
        t = i / RATE
        attack = min(1.0, t / 0.015)
        step[i] = (churn[i] * 5.0 * exp(-t / 0.12) + spray[i] * 0.9 * exp(-t / 0.05)) * attack
    write(f"splash_{n}", step, 0.75)

# Scrape: grit (noise through a narrow-ish band), a juddering grind and the
# odd screech where metal bites concrete. Loops.
LOOP = 3.0
count = int(LOOP * RATE)
grit = highpass(looped(count, 40, 2600), 400)
grind = looped(count, 41, 160)
scrape = [0.0] * count
rng = Random(42)
judder = [0.6 + 0.4 * sin(2 * pi * round(17 * LOOP) * i / count) for i in range(count)]
for i in range(count):
    scrape[i] = grit[i] * 1.6 * judder[i] + grind[i] * 6.0
for _ in range(5):
    at = rng.randrange(count)
    pitch = rng.uniform(1300, 2400)
    length = int(rng.uniform(0.08, 0.22) * RATE)
    for j in range(length):
        k = (at + j) % count
        env = sin(pi * j / length) ** 2
        scrape[k] += sin(2 * pi * pitch * j / RATE + 3 * sin(2 * pi * 30 * j / RATE)) * env * 0.35
write("scrape", scrape, 0.6)

# Listening: wet clicks in uneven trains, over a low, bubbling throat.
length = int(3.2 * RATE)
listen = [0.0] * length
throat = lowpass(noise(length, 50), 140)
for i in range(length):
    t = i / RATE
    listen[i] = throat[i] * 9.0 * (0.4 + 0.6 * sin(pi * t / 3.2))
rng = Random(51)
t = 0.15
while t < 3.0:
    burst = rng.randint(3, 9)
    gap = rng.uniform(0.018, 0.045)
    for b in range(burst):
        at = int((t + b * gap) * RATE)
        for j in range(int(0.012 * RATE)):
            if at + j < length:
                listen[at + j] += rng.uniform(-1, 1) * exp(-j / (0.0025 * RATE)) * 1.4
    t += burst * gap + rng.uniform(0.18, 0.5)
write("listen", listen, 0.7)

# Surfacing: a heavy displacement of water, rising then streaming off.
length = int(1.6 * RATE)
heave = lowpass(noise(length, 60), 380)
stream = highpass(noise(length, 61), 1200)
surface = [0.0] * length
for i in range(length):
    t = i / RATE
    surface[i] = heave[i] * 6.0 * min(1.0, t / 0.25) * exp(-max(0.0, t - 0.25) / 0.4) \
        + stream[i] * 0.5 * min(1.0, t / 0.4) * exp(-max(0.0, t - 0.5) / 0.5)
write("surface", surface, 0.8)

# Grab: an explosion of water, then churning.
length = int(2.4 * RATE)
blast = lowpass(noise(length, 70), 900)
churn = lowpass(noise(length, 71), 260)
spray = highpass(noise(length, 72), 2000)
grab = [0.0] * length
for i in range(length):
    t = i / RATE
    grab[i] = blast[i] * 4.0 * exp(-t / 0.18) + spray[i] * 1.2 * exp(-t / 0.3) \
        + churn[i] * 7.0 * (0.5 + 0.5 * sin(2 * pi * 3.1 * t)) * min(1.0, t / 0.2) * exp(-t / 1.4)
write("grab", grab, 0.85)
