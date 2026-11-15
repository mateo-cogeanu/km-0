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

# The hit, in stereo. A rushing intake as it closes the distance, then the
# impact: a hard slap and a sub drop. Over it, a screaming throat made of several
# detuned voices a tritone apart, raw and slightly overdriven, that chokes off
# into a small room. Loud but capped well below clipping.
from math import cos, tanh


def resonator(samples, freq, q):
    """RBJ band-pass, constant peak gain."""
    w = 2 * pi * freq / RATE
    alpha = sin(w) / (2 * q)
    b0, b2 = alpha, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cos(w), 1 - alpha
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for x in samples:
        y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


def drift(count, seed, rate):
    """Slow random wobble between -1 and 1."""
    rng = Random(seed)
    value = target = 0.0
    out = []
    for i in range(count):
        if i % int(RATE / rate) == 0:
            target = rng.uniform(-1, 1)
        value += (target - value) * 0.002
        out.append(value)
    return out


def write_stereo(name, left, right, gain):
    peak = max(max(map(abs, left)), max(map(abs, right))) or 1.0
    samples = array("h")
    for l, r in zip(left, right):
        samples.append(round(l * 32767 * gain / peak))
        samples.append(round(r * 32767 * gain / peak))
    if byteorder != "little":
        samples.byteswap()
    with wave.open(str(OUT / (name + ".wav")), "wb") as stream:
        stream.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(samples.tobytes())


IMPACT = 0.11
SCREAM_END = 1.08
count = int(1.75 * RATE)
left = [0.0] * count
right = [0.0] * count

# Intake: noise whose brightness and level climb into the impact.
rush = noise(int(IMPACT * RATE), 61)
low = 0.0
for i, x in enumerate(rush):
    t = i / RATE
    progress = t / IMPACT
    cutoff = 400 * (6000 / 400) ** progress
    low += (1 - exp(-2 * pi * cutoff / RATE)) * (x - low)
    level = 0.55 * progress ** 3
    left[i] += level * low
    right[i] += level * low * 0.9

# Impact: a hard broadband slap, a body thud and a falling sub.
start = int(IMPACT * RATE)
slap = band(noise(int(0.03 * RATE), 62), 500, 10000)
thud = band(noise(int(0.25 * RATE), 63), 50, 420)
phase = 0.0
for i in range(int(0.6 * RATE)):
    t = i / RATE
    k = start + i
    value = 0.0
    if i < len(slap):
        value += 1.1 * slap[i] * exp(-t / 0.005)
    if i < len(thud):
        value += 0.9 * thud[i] * exp(-t * 16)
    phase += 2 * pi * (95 * exp(-t * 4) + 32) / RATE
    value += tanh(2.5 * sin(phase)) * 0.75 * exp(-t * 5.5)
    left[k] += value
    right[k] += value

# The scream.
voice_start = start + int(0.004 * RATE)
length = int((SCREAM_END - IMPACT) * RATE)
wobble = drift(length, 64, 14)
for ratio, pan, level, seed in [(1.0, -0.25, 1.0, 71), (1.031, 0.3, 0.8, 72), (0.7071, 0.05, 0.6, 73), (1.414, -0.1, 0.32, 74)]:
    jitter = drift(length, seed, 30)
    hiss = noise(length, seed + 10)
    source = []
    phase = 0.0
    smooth = 0.0
    for i in range(length):
        t = i / RATE
        f0 = ratio * 640 * (1 - 0.2 * min(1.0, t / 0.9)) * (1 + 0.028 * sin(2 * pi * 7.3 * t + seed) + 0.02 * wobble[i] + 0.015 * jitter[i])
        phase = (phase + f0 / RATE) % 1.0
        saw = 2 * phase - 1
        smooth += 0.55 * (saw - smooth)
        # Breath rides on each pulse, which makes it rasp.
        source.append(smooth + 0.55 * hiss[i] * (0.4 + 0.6 * (phase < 0.35)))
    throat = [0.0] * length
    for freq, q, gain in [(850, 6, 1.0), (1250, 7, 0.7), (2850, 9, 0.5), (3600, 10, 0.25)]:
        for i, y in enumerate(resonator(source, freq * (1 + 0.04 * (ratio - 1)), q)):
            throat[i] += gain * y
    for i in range(length):
        t = i / RATE
        attack = min(1.0, t / 0.012)
        strain = 1.0 - 0.3 * min(1.0, t / 0.5) + 0.25 * max(0.0, (t - 0.55) / 0.42)
        choke = max(0.0, min(1.0, (length - i) / (0.022 * RATE)))
        value = tanh(2.4 * throat[i]) * attack * strain * choke * level * 0.62
        k = voice_start + i
        left[k] += value * (1 - pan)
        right[k] += value * (1 + pan)

# A small room, so the choke is not a digital edge.
for channel, delays in [(left, [0.0297, 0.0371, 0.0411, 0.0437]), (right, [0.0311, 0.0353, 0.0423, 0.0451])]:
    dry = channel[:]
    for delay in delays:
        offset = int(delay * RATE)
        comb = [0.0] * count
        for i in range(offset, count):
            comb[i] = dry[i - offset] + 0.72 * comb[i - offset]
        for i in range(count):
            channel[i] += 0.09 * comb[i]

write_stereo("hit", left, right, 0.89)


# Door hinges. Stick-slip friction: an uneven train of tiny catches, each
# ringing the wooden door, faster and higher as it strains. The long one is the
# door being pushed shut slowly; the short one is it swinging open.
def creak(seconds, seed, base, spread, strain):
    count = int(seconds * RATE)
    rng = Random(seed)
    wobble = drift(count, seed, 6)
    pulses = [0.0] * count
    t = 0.0
    while t < seconds:
        progress = t / seconds
        rate = base + spread * (0.5 + 0.5 * wobble[min(count - 1, int(t * RATE))]) + strain * progress
        # Now and then the hinge lets go for a moment.
        if rng.random() < 0.012:
            t += rng.uniform(0.04, 0.16)
            continue
        k = int(t * RATE)
        if k < count:
            pulses[k] += rng.uniform(0.5, 1.0)
        t += (1.0 / rate) * rng.uniform(0.85, 1.15)
    body = [0.0] * count
    for freq, q, gain in [(310, 9, 0.8), (720, 14, 1.0), (1380, 18, 0.7), (2350, 20, 0.35)]:
        for i, y in enumerate(resonator(pulses, freq, q)):
            body[i] += gain * y
    grit = band(noise(count, seed + 1), 900, 4000)
    out = []
    for i in range(count):
        t = i / RATE
        edge = min(1.0, t / 0.06, (seconds - t) / 0.12)
        swell = 0.75 + 0.25 * sin(pi * t / seconds)
        out.append(edge * swell * (body[i] + 0.04 * grit[i] * abs(body[i]) * 6))
    return out


write("door_creak", creak(3.7, 81, 22, 30, 40), 0.7)
write("door_open", creak(1.2, 82, 45, 25, 20), 0.6)

# The latch: a metal click and the soft thump of the door meeting its frame.
count = int(0.5 * RATE)
latch = [0.0] * count
click = band(noise(int(0.01 * RATE), 91), 2500, 9000)
add(latch, int(0.03 * RATE), [s * exp(-i / (0.0015 * RATE)) for i, s in enumerate(click)], 0.9)
thump = band(noise(int(0.2 * RATE), 92), 60, 500)
add(latch, 0, [s * exp(-i / (0.03 * RATE)) for i, s in enumerate(thump)], 1.0)
ring = resonator([1.0] + [0.0] * (count - 1), 1900, 40)
add(latch, int(0.03 * RATE), ring, 0.25)
write("door_latch", latch, 0.75)
