"""Regenerate the seamless PCM loops in assets/audio/road (stdlib only)."""

from array import array
from math import cos, exp, pi, sin
from pathlib import Path
from random import Random
from sys import byteorder
import wave

RATE = 24000
OUT = Path(__file__).resolve().parents[1] / "assets/audio/road"
OUT.mkdir(parents=True, exist_ok=True)


def noise(seconds, seed, low, high):
    """Band-limited noise with filters warmed up on the same repeating signal."""
    rng = Random(seed)
    raw = [rng.uniform(-1, 1) for _ in range(int(seconds * RATE))]
    fast_a = 1 - exp(-2 * pi * high / RATE)
    slow_a = 1 - exp(-2 * pi * low / RATE)
    fast = slow = 0
    for pass_index in range(2):
        if pass_index == 1:
            band = []
        for sample in raw:
            fast += fast_a * (sample - fast)
            slow += slow_a * (fast - slow)
            if pass_index == 1:
                band.append(fast - slow)
    return band


def write(name, layers, gain):
    mix = [sum(layer) for layer in zip(*layers)]
    peak = max(map(abs, mix))
    samples = array("h", (round(x * 32767 * gain / peak) for x in mix))
    if byteorder != "little":
        samples.byteswap()
    with wave.open(str(OUT / (name + ".wav")), "wb") as stream:
        stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(samples.tobytes())


# Tread rumble and a little higher-frequency hiss on asphalt.
tread = [a * (1 + 0.14 * cos(2 * pi * 38 * i / RATE))
         for i, a in enumerate(noise(3, 701, 85, 460))]
write("asphalt", [tread, [0.28 * a for a in noise(3, 702, 650, 2600)]], 0.65)

# Irregular stone ticks over a lower, dry rolling crunch.
gravel = noise(4, 822, 230, 1850)
stone = noise(4, 823, 1100, 4800)
rng = Random(824)
ticks = [0.0] * len(gravel)
for _ in range(155):
    start = rng.randrange(len(ticks))
    length = rng.randrange(48, 320)
    strength = rng.uniform(0.2, 1.45)
    for j in range(length):
        k = (start + j) % len(ticks)
        ticks[k] += stone[k] * strength * sin(pi * j / length) * exp(-3 * j / length)
write("gravel", [[0.52 * a for a in gravel], ticks], 0.76)
write("soil", [noise(3, 855, 75, 340), [0.22 * a for a in noise(3, 856, 470, 1400)]], 0.66)

def soften(samples, cutoff):
    """Roll off the hiss above cutoff without introducing a click at the loop seam."""
    alpha = 1 - exp(-2 * pi * cutoff / RATE)
    value = 0.0
    for _ in range(2):
        filtered = []
        for sample in samples:
            value += alpha * (sample - value)
            filtered.append(value)
    return filtered


def write_wind():
    duration = 26
    base = soften(noise(duration, 990, 42, 185), 240)
    air = soften(noise(duration, 991, 150, 520), 440)
    gusts = [(2.6, 0.85, 0.76), (8.3, 1.65, 0.92), (16.1, 0.95, 0.69), (22.5, 1.35, 0.85)]
    open_air, enclosed = [], []
    for i, (rumble, rustle) in enumerate(zip(base, air)):
        time = i / RATE
        swell = 0.055
        for center, width, strength in gusts:
            distance = (time - center + duration / 2) % duration - duration / 2
            swell += strength * exp(-0.5 * (distance / width) ** 2)
        open_air.append(swell * (rumble + 0.22 * swell * rustle))
        enclosed.append((0.24 + 0.76 * swell) * rumble)
    write("wind_exposed", [open_air], 0.49)
    write("wind_cabin", [soften(enclosed, 145)], 0.4)


write_wind()


def write_storm():
    """A dust storm: a constant roar of air with grit hissing through it and
    heavy gusts. Loops."""
    duration = 12
    roar = soften(noise(duration, 1101, 60, 420), 520)
    grit = noise(duration, 1102, 1200, 5200)
    gusts = [(1.5, 1.2, 0.8), (5.0, 1.8, 1.0), (8.6, 1.0, 0.7), (10.8, 1.4, 0.9)]
    storm = []
    for i, (low, high) in enumerate(zip(roar, grit)):
        time = i / RATE
        swell = 0.55
        for center, width, strength in gusts:
            distance = (time - center + duration / 2) % duration - duration / 2
            swell += strength * exp(-0.5 * (distance / width) ** 2)
        storm.append(swell * (low + 0.18 * swell * high))
    write("dust_storm", [storm], 0.6)


write_storm()
