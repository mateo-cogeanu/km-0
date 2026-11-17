"""Synthesize the beds under the ending cinematics (stdlib only).

Writes to assets/audio/ending:
  cine_dread.wav   a low, slowly breathing drone for the night endings (loops)
  cine_dawn.wav    a warm open chord for the morning ending (loops)
  crickets.wav     night insects far off in the scrub (loops)
  kettle.wav       a kettle coming to the boil and starting to whistle
"""

from array import array
from math import exp, pi, sin, tanh
from pathlib import Path
from random import Random
from sys import byteorder
import wave

RATE = 24000
OUT = Path(__file__).resolve().parents[1] / "assets/audio/ending"


def write(name, mix, gain):
    peak = max(map(abs, mix)) or 1.0
    samples = array("h", (round(x * 32767 * gain / peak) for x in mix))
    if byteorder != "little":
        samples.byteswap()
    with wave.open(str(OUT / (name + ".wav")), "wb") as stream:
        stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(samples.tobytes())
    print("wrote", name, f"{len(mix) / RATE:.1f}s")


def lowpass(samples, cutoff):
    a = 1 - exp(-2 * pi * cutoff / RATE)
    y = 0.0
    out = []
    for x in samples:
        y += a * (x - y)
        out.append(y)
    return out


def noise(count, seed):
    rng = Random(seed)
    return [rng.uniform(-1, 1) for _ in range(count)]


def looped_noise(count, seed, cutoff, passes=2):
    """Filtered noise that joins up with itself: run it twice and keep the second lap."""
    raw = noise(count, seed)
    for _ in range(passes):
        doubled = lowpass(raw + raw, cutoff)
        raw = doubled[count:]
    return raw


# Loop length: every tone below fits a whole number of cycles in it.
LOOP = 24.0
COUNT = int(LOOP * RATE)


def tone(freq, phase=0.0):
    """freq is rounded to fit LOOP exactly, so the loop has no click."""
    cycles = round(freq * LOOP)
    step = 2 * pi * cycles / COUNT
    return [sin(i * step + phase) for i in range(COUNT)]


def lfo(cycles, phase=0.0):
    step = 2 * pi * cycles / COUNT
    return [0.5 + 0.5 * sin(i * step + phase) for i in range(COUNT)]


# The dread: two close low notes beating against each other, a minor second
# above them that comes and goes, and a breath of wind.
dread = [0.0] * COUNT
for freq, level, swell, phase in [(55.0, 1.0, 1, 0.0), (55.6, 0.8, 2, 1.0), (82.4, 0.35, 3, 2.0),
                                  (110.3, 0.22, 1, 3.0), (116.5, 0.16, 2, 0.4), (164.8, 0.07, 3, 1.7)]:
    wave_ = tone(freq, phase)
    breathe = lfo(swell, phase)
    for i in range(COUNT):
        dread[i] += wave_[i] * level * (0.35 + 0.65 * breathe[i])
air = looped_noise(COUNT, 71, 380)
gust = lfo(2, 0.7)
for i in range(COUNT):
    dread[i] = tanh(0.9 * dread[i]) + air[i] * 4.0 * (0.2 + 0.8 * gust[i] ** 2)
write("cine_dread", dread, 0.55)

# The dawn: an open D chord, slow and warm, with a high shimmer.
dawn = [0.0] * COUNT
for freq, level, swell, phase in [(73.4, 0.7, 1, 0.0), (146.8, 0.55, 2, 0.5), (220.0, 0.5, 1, 1.3),
                                  (293.7, 0.38, 3, 2.1), (370.0, 0.3, 2, 2.9), (440.0, 0.2, 1, 0.9),
                                  (587.3, 0.1, 3, 1.6), (880.0, 0.05, 2, 2.4)]:
    for detune in (-0.08, 0.08):
        wave_ = tone(freq + detune * freq / 100.0, phase + detune * 10)
        breathe = lfo(swell, phase)
        for i in range(COUNT):
            dawn[i] += wave_[i] * level * (0.55 + 0.45 * breathe[i])
breeze = looped_noise(COUNT, 72, 900)
for i in range(COUNT):
    dawn[i] = tanh(0.5 * dawn[i]) + breeze[i] * 1.6
write("cine_dawn", dawn, 0.5)

# Crickets: a few of them, each trilling at its own pace.
CRICKET_LOOP = 8.0
count = int(CRICKET_LOOP * RATE)
crickets = [0.0] * count
rng = Random(73)
for pitch, rate, level in [(4400, 0.9, 1.0), (4750, 1.3, 0.6), (4100, 0.7, 0.45), (5100, 1.6, 0.3)]:
    period = CRICKET_LOOP / round(CRICKET_LOOP * rate)
    offset = rng.uniform(0, period)
    step = 2 * pi * round(pitch * CRICKET_LOOP) / count
    for i in range(count):
        t = (i / RATE + offset) % period
        # A burst of quick pulses at the start of each period.
        pulse = 0.0
        if t < 0.22:
            within = (t * 34) % 1.0
            pulse = sin(pi * within) ** 2 if within < 1.0 else 0.0
        crickets[i] += sin(i * step) * pulse * level
write("crickets", crickets, 0.4)

# A kettle: a rumble building to a boil, then the whistle climbing in.
count = int(9.0 * RATE)
kettle = [0.0] * count
roar = lowpass(lowpass(noise(count, 74), 700), 900)
hiss = noise(count, 75)
hiss_hi = [h - l for h, l in zip(hiss, lowpass(hiss, 2500))]
phase = 0.0
wobble = lowpass(noise(count, 76), 6)
for i in range(count):
    t = i / RATE
    boil = min(1.0, t / 4.0)
    bubbles = 1.0 + (1.5 if Random(i // 900).random() < 0.25 * boil else 0.0)
    kettle[i] += roar[i] * 6.0 * boil * bubbles
    whistle = max(0.0, min(1.0, (t - 3.6) / 3.0))
    if whistle > 0.0:
        freq = 1650 + 450 * whistle + 900 * wobble[i] * 2
        phase += 2 * pi * freq / RATE
        kettle[i] += (sin(phase) * 0.8 + sin(2 * phase) * 0.12) * whistle ** 1.5 * (0.9 + 0.1 * sin(t * 31))
        kettle[i] += hiss_hi[i] * 0.25 * whistle
    kettle[i] *= min(1.0, (9.0 - t) / 0.3)
write("kettle", kettle, 0.5)

# A house fire: a low roar with crackles and the odd sharp pop. Loops.
FIRE_LOOP = 6.0
count = int(FIRE_LOOP * RATE)
roar = looped_noise(count, 77, 260)
hiss = looped_noise(count, 78, 2600, passes=1)
fire = [roar[i] * 7.0 + hiss[i] * 1.2 for i in range(count)]
rng = Random(79)
for _ in range(int(FIRE_LOOP * 26)):
    at = rng.randrange(count)
    size = rng.random() ** 3
    length = int((0.004 + 0.02 * size) * RATE)
    pop = noise(length, rng.randrange(1 << 30))
    for j in range(length):
        k = (at + j) % count
        fire[k] += pop[j] * (0.4 + 2.6 * size) * exp(-j / (0.003 * RATE + size * 0.01 * RATE))
write("fire_crackle", fire, 0.55)
