"""Record every spoken line in KM0 with Chatterbox (MIT licence), performed scared.

Run inside a Python 3.11 environment with chatterbox-tts installed, e.g.:
    uv venv --python 3.11 voice-env && VIRTUAL_ENV=voice-env uv pip install chatterbox-tts
    PYTORCH_ENABLE_MPS_FALLBACK=1 voice-env/bin/python Sources/make_voices.py [stranger|ending|radio ...]

Each character speaks in the voice of a short reference clip in Sources/voice_refs.
Those clips were made with public-domain Piper voices (him, you, county, mick)
and Apache-2.0 Kokoro voices (ruth, operator, caller), so everything here can be shipped
under the game's GPL.

Writes:
  assets/audio/stranger/{him|you}_{md5}.wav   the conversation in the cabin
  assets/audio/ending/{hello,anybody,tricked}.wav
  assets/audio/radio/*.wav                    the five broadcasts
and updates the caption times, cues and lip sync in scripts/road_radio.gd and
scripts/road_end_house.gd to match the new takes.
"""

import hashlib
import re
import sys
from pathlib import Path

import numpy as np
import perth
import soundfile as sf
import torch

perth.PerthImplicitWatermarker = perth.DummyWatermarker
from chatterbox.tts import ChatterboxTTS  # noqa: E402
from chatterbox.tts_turbo import ChatterboxTurboTTS  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
REFS = ROOT / "Sources/voice_refs"
RATE = 24000
# The "scared" performance: more emotion, slower and more halting.
EXAGGERATION = 0.85
CFG = 0.3
DEVICE = "mps" if torch.backends.mps.is_available() else "cpu"
model = None
turbo = None


def seed_for(text, who):
    torch.manual_seed(int(hashlib.md5(f"{who}:{text}".encode()).hexdigest()[:8], 16))


def tidy(audio, level=0.09):
    """Trim silence at both ends and bring every take to the same loudness."""
    audio = np.asarray(audio, dtype=np.float64).reshape(-1)
    loud = np.where(np.abs(audio) > 0.012)[0]
    if loud.size:
        pad = int(0.04 * RATE)
        audio = audio[max(0, loud[0] - pad): loud[-1] + pad]
    rms = np.sqrt((audio ** 2).mean()) or 1.0
    audio = audio / rms * level
    peak = np.abs(audio).max()
    return audio / max(1.0, peak / 0.89)


listener = None


def words_of(text):
    text = text.lower().replace("’", "'").replace("‘", "'").replace("okay", "ok")
    return re.findall(r"[a-z0-9']+", text.replace("'", ""))


def heard(audio):
    """What a speech recognizer hears in a take, to catch Chatterbox repeating
    or dropping words."""
    global listener
    if listener is None:
        from faster_whisper import WhisperModel
        listener = WhisperModel("base.en", compute_type="int8")
    segments, _ = listener.transcribe(np.asarray(audio, dtype=np.float32), language="en", beam_size=5)
    return " ".join(segment.text for segment in segments)


def repeats(words):
    """Runs of three or more words said twice."""
    seen = set()
    for i in range(len(words) - 2):
        run = tuple(words[i:i + 3])
        if run in seen:
            return True
        seen.add(run)
    return False


def mismatch(target, audio):
    """0 when the take says the line; above ACCEPT for repeats, extra words or
    big slips. A misheard word here and there does not count."""
    import difflib
    want, got = words_of(target), words_of(heard(audio))
    extra = max(0, len(got) - len(want))
    if len(want) <= 2:
        # Short calls and breaths: only reject takes that run on into more words.
        return 0.0 if extra <= 1 else 0.3 * extra
    ratio = difflib.SequenceMatcher(None, want, got).ratio()
    score = max(0.0, 0.8 - ratio) + 0.3 * max(0, extra - 1)
    if repeats(got) and not repeats(want):
        score += 1.0
    return score


ACCEPT = 0.01


def say(text, who, tries=8):
    """Record a line, listen back, and record it again until it says the words
    once, in order, with nothing repeated."""
    global model
    if model is None:
        model = ChatterboxTTS.from_pretrained(device=DEVICE)
    spoken = text.replace("’", "'").replace("‘", "'")
    best, best_score = None, None
    for attempt in range(tries):
        seed_for(text + ("#%d" % attempt if attempt else ""), who)
        wav = model.generate(spoken, audio_prompt_path=str(REFS / f"{who}.wav"), exaggeration=EXAGGERATION, cfg_weight=CFG)
        take = tidy(wav.squeeze(0).cpu().numpy())
        score = mismatch(text, take)
        if best is None or score < best_score:
            best, best_score = take, score
        if score <= ACCEPT:
            break
        print(f"  retake {attempt + 1} for {who}: {text!r} (heard {heard(take)!r})", flush=True)
    if best_score > ACCEPT:
        print(f"  WARNING best take still off ({best_score:.2f}) for {who}: {text!r}", flush=True)
    return best


def cough(who, text="[cough] [cough] [cough] Hm."):
    """Real coughs come from Chatterbox Turbo's [cough] tag, in the same voice."""
    global turbo
    if turbo is None:
        turbo = ChatterboxTurboTTS.from_pretrained(device=DEVICE)
    seed_for(text, who)
    wav = turbo.generate(text, audio_prompt_path=str(REFS / f"{who}.wav"))
    return tidy(wav.squeeze(0).cpu().numpy(), 0.07)


def silence(seconds):
    return np.zeros(int(seconds * RATE))


def write(path, audio):
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, audio, RATE, subtype="PCM_16")
    Path(str(path) + ".import").unlink(missing_ok=True)
    print("wrote", path.relative_to(ROOT), f"{len(audio) / RATE:.2f}s")


# The cabin -------------------------------------------------------------------

def stranger(mode="all"):
    """mode "all" re-records everything, "coughs" only the lines marked cough,
    "missing" only lines that have no recording yet."""
    script = (ROOT / "scripts/stranger_house.gd").read_text()
    out = ROOT / "assets/audio/stranger"
    if mode == "all":
        for old in out.glob("*.wav*"):
            old.unlink()
    for who, text, cue in re.findall(r'\["(him|you)", "((?:[^"\\]|\\.)*)"(?:, "(\w+)")?\]', script):
        if mode == "coughs" and cue != "cough":
            continue
        name = f"{who}_{hashlib.md5(text.encode()).hexdigest()[:10]}.wav"
        if mode == "missing" and (out / name).exists():
            continue
        line = say(text, who)
        if cue == "cough":
            line = np.concatenate([cough(who, "[cough] [cough] Sorry."), silence(0.2), line])
        write(out / name, line)


# The house at the end of the road ---------------------------------------------

def envelope(audio, step=0.05):
    frames = int(len(audio) / (step * RATE)) + 1
    values = [np.sqrt((audio[int(i * step * RATE): int((i + 1) * step * RATE)] ** 2).mean() or 0.0) for i in range(frames)]
    top = max(values) or 1.0
    return [int(round(min(1.0, v / top) * 214)) if v / top > 0.08 else 0 for v in values]


def pitch_down(audio, semitones):
    import librosa
    return librosa.effects.pitch_shift(audio.astype(np.float32), sr=RATE, n_steps=-semitones)


def ending():
    folder = ROOT / "assets/audio/ending"
    hello = say("Hello?", "you")
    question = say("Anybody there?", "you")
    gap = 0.55
    write(folder / "hello.wav", np.concatenate([hello, silence(gap), question]))
    question_cue = round(len(hello) / RATE + gap, 2)
    write(folder / "anybody.wav", say("Anybody there? ...Anybody?", "you"))
    # It speaks in your own voice, a little lower: a breath of a laugh, a pause,
    # then the line.
    laugh = pitch_down(say("Ha.", "you"), 2.5)
    words = pitch_down(say("Tricked you too.", "you"), 2.5)
    pause = 0.8
    tricked = tidy(np.concatenate([laugh, silence(pause), words]))
    write(folder / "tricked.wav", tricked)
    words_cue = round(len(laugh) / RATE + pause, 2)
    jaw = envelope(tricked)
    code = (ROOT / "scripts/road_end_house.gd").read_text()
    code = re.sub(r"const INTRO_QUESTION_CUE := [0-9.]+", f"const INTRO_QUESTION_CUE := {question_cue}", code)
    code = re.sub(r"const FINAL_WORDS_CUE := [0-9.]+", f"const FINAL_WORDS_CUE := {words_cue}", code)
    rows = ",\n\t".join(", ".join(str(v) for v in jaw[i:i + 18]) for i in range(0, len(jaw), 18))
    code = re.sub(r"const FINAL_JAW := \[.*?\n\]", f"const FINAL_JAW := [\n\t{rows},\n]", code, flags=re.S)
    (ROOT / "scripts/road_end_house.gd").write_text(code)
    print("cues", question_cue, words_cue, "jaw frames", len(jaw))


def escape():
    """Your own voice calling after you as you leave it all behind."""
    folder = ROOT / "assets/audio/ending"
    write(folder / "escape_wait.wav", say("Wait. Wait! Where are you going?", "you"))
    write(folder / "escape_back.wav", say("Come back. Please. The kettle's on.", "you"))


def replaced():
    """Somebody new on channel 4, answering you."""
    folder = ROOT / "assets/audio/ending"
    first = say("Hello? ...Hello, I hear you.", "caller")
    second = say("I've been listening for days. I thought nobody was out there.", "caller")
    third = say("Okay. Okay. I'm coming out.", "caller")
    gap = 0.7
    write(folder / "replaced_reply.wav", np.concatenate([first, silence(gap), second, silence(gap), third]))
    print("reply cues", 0.0, round((len(first)) / RATE + gap, 2), round((len(first) + len(second)) / RATE + gap * 2, 2))


# The radio ---------------------------------------------------------------------

SPEAKERS = {"County": "county", "Ruth": "ruth", "Garage operator": "operator", "Mick": "mick", "You": "you"}
BROADCASTS = ["workshop", "relay", "wayside", "tower", "last_stop", "quiet", "you"]


def radio():
    path = ROOT / "scripts/road_radio.gd"
    code = path.read_text()
    block = re.search(r"const LINES := \[\n(.*?)\n\]\n", code, re.S)
    groups = re.findall(r"\t\[\n(.*?)\n\t\],", block.group(1), re.S)
    takes = {}
    new_groups = []
    for index, group in enumerate(groups):
        entries = [(float(t), text) for t, text in re.findall(r'\[([0-9.]+), "((?:[^"\\]|\\.)*)"\]', group)]
        pieces = [silence(entries[0][0])]
        clock = entries[0][0]
        rows = []
        for i, (start, text) in enumerate(entries):
            if not text:
                continue
            speaker, words = text.split(": ", 1)
            key = (speaker, words)
            if key not in takes:
                # The same report twice is the same recording twice.
                if words == "[Coughs]":
                    # Mick's one cough: a Chatterbox Turbo take trimmed to its three
                    # clean bursts, kept on its own for the creature to reuse.
                    takes[key] = sf.read(REFS / "mick_cough_take.wav")[0]
                    write(ROOT / "assets/audio/radio/mick_cough.wav", takes[key])
                else:
                    takes[key] = say(words, SPEAKERS[speaker])
            audio = takes[key]
            rows.append((round(clock, 3), text))
            pieces.append(audio)
            clock += len(audio) / RATE
            # Keep the original pause before whatever comes next.
            later = entries[i + 1:]
            ends_with_gap = later and not later[0][1]
            if ends_with_gap:
                rows.append((round(clock, 3), ""))
                following = next((t for t, words_next in later[1:] if words_next), None)
                pause = (following - later[0][0]) if following is not None else 0.0
            else:
                pause = 0.0
            pieces.append(silence(max(0.0, pause)))
            clock += max(0.0, pause)
        pieces.append(silence(0.6))
        write(ROOT / f"assets/audio/radio/{BROADCASTS[index]}.wav", np.concatenate(pieces))
        new_groups.append("\t[\n" + "\n".join(f'\t\t[{t}, "{text}"],' for t, text in rows) + "\n\t],")
    code = code[:block.start(1)] + "\n".join(new_groups) + code[block.end(1):]
    path.write_text(code)


if __name__ == "__main__":
    jobs = sys.argv[1:] or ["stranger", "ending", "radio"]
    for job in jobs:
        {"stranger": stranger, "stranger-coughs": lambda: stranger("coughs"), "stranger-missing": lambda: stranger("missing"),
         "ending": ending, "escape": escape, "replaced": replaced, "radio": radio}[job]()
