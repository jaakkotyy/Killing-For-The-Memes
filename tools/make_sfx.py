"""Generates the game's sound effects into assets/sfx/ (16-bit mono WAV, 22.05 kHz).

Everything is synthesised here from sine waves, simple envelopes and noise, so the sounds
are entirely our own and need no license. Re-run after changing a recipe:

    python tools/make_sfx.py

Only the standard library is used.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")


def tone(freq, seconds, volume=0.5, attack=0.005, release=0.08, shape="sine", vibrato=0.0, slide=0.0):
    """One note with an attack/release envelope. `slide` bends the pitch (octaves over the note)."""
    samples = []
    count = int(seconds * RATE)
    phase = 0.0
    for i in range(count):
        t = i / RATE
        f = freq * (2.0 ** (slide * t / seconds)) * (1.0 + vibrato * math.sin(2 * math.pi * 6.0 * t))
        phase += 2 * math.pi * f / RATE
        if shape == "square":
            value = 1.0 if math.sin(phase) >= 0 else -1.0
            value *= 0.5
        elif shape == "saw":
            value = ((phase / (2 * math.pi)) % 1.0) * 2.0 - 1.0
            value *= 0.6
        elif shape == "bell":
            # A bell: the fundamental plus inharmonic partials that die away faster.
            value = (math.sin(phase) + 0.5 * math.sin(phase * 2.76) * math.exp(-t * 6)
                     + 0.25 * math.sin(phase * 5.4) * math.exp(-t * 10))
            value *= 0.6
        else:
            value = math.sin(phase)
        env = min(1.0, t / attack) if attack > 0 else 1.0
        left = seconds - t
        if left < release:
            env *= max(0.0, left / release)
        if shape == "bell":
            env *= math.exp(-t * 3.0)
        samples.append(value * env * volume)
    return samples


def noise(seconds, volume=0.3, attack=0.002, decay=20.0, lowpass=0.5, seed=1):
    rng = random.Random(seed)
    samples = []
    last = 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        last = last + lowpass * (rng.uniform(-1, 1) - last)
        env = min(1.0, t / attack) * math.exp(-t * decay)
        samples.append(last * env * volume)
    return samples


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(*tracks):
    length = max(len(track) for track in tracks)
    out = [0.0] * length
    for track in tracks:
        for i, value in enumerate(track):
            out[i] += value
    return out


def at(seconds, track):
    return silence(seconds) + track


def note(name):
    """'A4' -> Hz."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]]
    rest = name[1:]
    if rest.startswith("#"):
        semis += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        semis -= 1
        rest = rest[1:]
    octave = int(rest)
    return 440.0 * 2 ** ((semis + 12 * (octave - 4)) / 12)


def save(name, samples):
    peak = max(0.001, max(abs(s) for s in samples))
    scale = min(1.0, 0.89 / peak)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))
    print("wrote", path, "%.2f s" % (len(samples) / RATE))


def sounds():
    # A question goes up on the TV: a game-show two-tone chime.
    yield "question", mix(tone(note("E5"), 0.5, shape="bell", volume=0.6),
                          at(0.18, tone(note("C5"), 0.7, shape="bell", volume=0.6)))
    # Someone answered: a dry little tick.
    yield "answer_tick", mix(noise(0.05, volume=0.5, decay=90, lowpass=0.9, seed=3),
                             tone(1800, 0.03, volume=0.15, release=0.02))
    # The majority said yes: rising major third and fifth.
    yield "answer_yes", mix(tone(note("C5"), 0.16, volume=0.4, shape="square", release=0.05),
                            at(0.1, tone(note("E5"), 0.16, volume=0.4, shape="square", release=0.05)),
                            at(0.2, tone(note("G5"), 0.3, volume=0.4, shape="square", release=0.15)))
    # The majority said no: two falling notes.
    yield "answer_no", mix(tone(note("E4"), 0.2, volume=0.45, shape="saw", release=0.05),
                           at(0.18, tone(note("C4"), 0.35, volume=0.45, shape="saw", release=0.2, slide=-0.15)))
    # Nobody knew: a wobbly shrug.
    yield "answer_unclear", tone(note("A4"), 0.5, volume=0.4, vibrato=0.04, release=0.25, slide=-0.1)
    # Your turn to ask: a bright bell.
    yield "your_turn", mix(tone(note("A5"), 0.8, shape="bell", volume=0.7),
                           at(0.09, tone(note("E6"), 0.6, shape="bell", volume=0.35)))
    # Someone solved theirs: a short fanfare.
    fanfare = [("C5", 0.0), ("E5", 0.08), ("G5", 0.16), ("C6", 0.24)]
    yield "solved", mix(*[at(start, tone(note(n), 0.45 - start, volume=0.35, shape="square", release=0.2))
                          for n, start in fanfare],
                        at(0.24, tone(note("C6") * 2, 0.4, shape="bell", volume=0.3)))
    # A wrong guess: a buzzer.
    yield "wrong", mix(tone(110, 0.45, volume=0.5, shape="square", release=0.05),
                       tone(116, 0.45, volume=0.5, shape="square", release=0.05))
    # The reveal: a noise swell into a chord.
    swell = [s * min(1.0, (i / RATE) / 0.6) for i, s in
             enumerate(noise(0.7, volume=0.35, attack=0.6, decay=0.0, lowpass=0.3, seed=7))]
    yield "reveal", mix(swell, at(0.6, mix(tone(note("D4"), 0.9, volume=0.3, shape="saw", release=0.5),
                                           tone(note("F#4"), 0.9, volume=0.3, shape="saw", release=0.5),
                                           tone(note("A4"), 0.9, volume=0.3, shape="saw", release=0.5))))
    # The winner: a longer fanfare.
    tune = [("G4", 0.0, 0.15), ("C5", 0.15, 0.15), ("E5", 0.3, 0.15), ("G5", 0.45, 0.3),
            ("E5", 0.75, 0.15), ("G5", 0.9, 0.8)]
    yield "win", mix(*[at(start, tone(note(n), length, volume=0.4, shape="square", release=0.08))
                       for n, start, length in tune],
                     at(0.9, tone(note("C4"), 0.8, volume=0.3, shape="saw", release=0.4)),
                     at(0.9, tone(note("G5") * 2, 0.8, shape="bell", volume=0.3)))
    # A new round's identities are dealt: a card flick.
    yield "deal", mix(noise(0.12, volume=0.6, decay=35, lowpass=0.7, seed=11),
                      at(0.07, noise(0.1, volume=0.4, decay=40, lowpass=0.7, seed=12)))


if __name__ == "__main__":
    for sound_name, data in sounds():
        save(sound_name, data)
