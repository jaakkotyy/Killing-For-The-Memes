"""Composes and renders the game's background music, "Forgotten Rooms": a slow, melancholy
loop with a hint of mystery, like trying to remember a room you were once in.

    python tools/make_music.py      # writes assets/music/forgotten_rooms.wav (about 20 s)

Everything is synthesised here, so the track is entirely our own: dark detuned pads, a
music-box tune, a slow arpeggio, a soft half-time beat drowned in reverb, a quiet sub,
reversed swells and old-record crackle. Everything with a pitch wavers slightly like a
worn tape. A minor, Am9 - Fmaj7 - Dm9 - E7(b9), 120 BPM in half time, 56 bars:

    intro 8 | first memory 16 | forgetting 8 | build 4 | second memory 16 | fade 4

In "forgetting" the tune keeps starting and breaking off, a little lower each time.
Reverb and delay tails wrap around the end, so the file loops seamlessly. Only the
standard library is used.
"""
import math
import os
import random
import struct

SR = 24000
BPM = 120
BEAT = 60.0 / BPM
BAR = 4 * BEAT
BARS = 56
N = int(round(BARS * BAR * SR))
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "music", "forgotten_rooms.wav")

# Pad voicings and sub roots, two bars each.
CHORDS = [("A3", "C4", "E4", "B4"), ("F3", "A3", "C4", "E4"), ("D3", "F3", "A3", "E4"), ("E3", "G#3", "D4", "F4")]
ROOTS = ["A1", "F1", "D2", "E1"]

# The music-box tune over one 8-bar chord cycle: (beat, note, beats).
MELODY = [
    (0, "E5", 2), (2, "C5", 1), (3, "B4", 1), (4, "A4", 3), (7, "B4", 1),
    (8, "C5", 2), (10, "A4", 1), (11, "G4", 1), (12, "A4", 3), (15, "E5", 1),
    (16, "F5", 2), (18, "E5", 1), (19, "D5", 1), (20, "A4", 2), (22, "D5", 2),
    (24, "G#4", 2), (26, "B4", 1), (27, "D5", 1), (28, "F5", 2), (30, "E5", 2),
]


def hz(name):
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]]
    rest = name[1:]
    if rest.startswith("#"):
        semis += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        semis -= 1
        rest = rest[1:]
    return 440.0 * 2 ** ((semis + 12 * (int(rest) - 4)) / 12)


CHORD_HZ = [[hz(n) for n in chord] for chord in CHORDS]
ROOT_HZ = [hz(n) for n in ROOTS]


def section(bar):
    if bar < 8:
        return "intro"
    if bar < 24:
        return "memoryA"
    if bar < 32:
        return "forgetting"
    if bar < 36:
        return "build"
    if bar < 52:
        return "memoryB"
    return "fade"


def has_beat(bar):
    return section(bar) in ("memoryA", "memoryB")


def chord_index(bar):
    return (bar // 2) % 4


def at(seconds):
    return int(round(seconds * SR))


def wow(t):
    """A worn tape: the pitch drifts a little, slowly."""
    return 1.0 + 0.0028 * math.sin(2 * math.pi * 0.31 * t) + 0.0016 * math.sin(2 * math.pi * 0.113 * t + 1.0)


def add(buf, start, samples, gain=1.0):
    """Mixes samples into buf from start, wrapping past the end (the loop point)."""
    for i, value in enumerate(samples):
        buf[(start + i) % N] += value * gain


class Svf:
    """Chamberlin state-variable filter."""

    def __init__(self):
        self.low = 0.0
        self.band = 0.0

    def run(self, x, cutoff, damping):
        f = 2.0 * math.sin(math.pi * min(cutoff, 3800.0) / SR)
        self.low += f * self.band
        high = x - self.low - damping * self.band
        self.band += f * high
        return self.low, self.band, high


# --- One-shot drums -----------------------------------------------------------------------

def kick():
    out = []
    phase = 0.0
    for i in range(int(0.5 * SR)):
        t = i / SR
        phase += 2 * math.pi * (48 + 70 * math.exp(-t * 30)) / SR
        out.append(math.tanh(1.1 * math.sin(phase) * math.exp(-t * 7)))
    return out


def snare():
    """A soft, papery snare that mostly lives in the reverb."""
    out = []
    rng = random.Random(2)
    filt = Svf()
    phase = 0.0
    for i in range(int(0.35 * SR)):
        t = i / SR
        _, band, _ = filt.run(rng.uniform(-1, 1), 1500, 1.1)
        phase += 2 * math.pi * 210 / SR
        out.append(band * 0.8 * math.exp(-t * 16) + math.sin(phase) * 0.25 * math.exp(-t * 40))
    return out


def hat(length, decay, seed):
    out = []
    rng = random.Random(seed)
    filt = Svf()
    for i in range(int(length * SR)):
        t = i / SR
        _, _, high = filt.run(rng.uniform(-1, 1), 3200, 0.7)
        out.append(high * math.exp(-t * decay) * 0.5)
    return out


# --- Layers -------------------------------------------------------------------------------

def drums(dry, send):
    k, s, sh = kick(), snare(), hat(0.09, 45, 3)
    kicks = []
    for bar in range(BARS):
        t0 = bar * BAR
        if not has_beat(bar):
            continue
        late = section(bar) == "memoryB"
        kicks.append(t0)
        add(dry, at(t0), k, 0.38)
        if bar % 2 == 1:
            kicks.append(t0 + 2.5 * BEAT)
            add(dry, at(t0 + 2.5 * BEAT), k, 0.24)
        add(dry, at(t0 + 2 * BEAT), s, 0.45)
        add(send, at(t0 + 2 * BEAT), s, 0.75)
        for eighth in range(8):
            level = (0.12 if eighth % 2 else 0.06) * (1.0 if late else 0.6)
            add(dry, at(t0 + eighth * 0.5 * BEAT), sh, level)
    return kicks


def sidechain(kicks):
    """A gentle dip after each kick, so the pads breathe with the beat."""
    gain = [1.0] * N
    for t in kicks:
        s = at(t)
        for i in range(int(0.4 * SR)):
            gain[(s + i) % N] = min(gain[(s + i) % N], 1.0 - 0.35 * math.exp(-i / SR / 0.15))
    return gain


def pad(left, right, send, duck):
    phases = [0.0] * 8
    lp1, lp2 = 0.0, 0.0
    delay = [0.0] * int(0.017 * SR)    # a short delay on the right side for width
    d = 0
    for i in range(N):
        t = i / SR
        bar = int(t / BAR)
        part = section(bar)
        notes = CHORD_HZ[chord_index(bar)]
        breath = 0.85 + 0.15 * math.sin(2 * math.pi * t / (2 * BAR))   # swells every two bars
        if part == "intro":
            cutoff, gain = 300 + 500 * (t / (8 * BAR)), 0.32
        elif part == "forgetting":
            cutoff, gain = 650, 0.34
        elif part == "fade":
            cutoff, gain = 800 - 450 * ((t - 52 * BAR) / (4 * BAR)), 0.32
        else:
            cutoff, gain = 950, 0.28
        w = wow(t)
        value = 0.0
        for v in range(8):
            f = notes[v // 2] * (1.003 if v % 2 else 0.997) * w
            phases[v] = (phases[v] + f / SR) % 1.0
            value += phases[v] * 2.0 - 1.0
        a = 1.0 - math.exp(-2 * math.pi * cutoff / SR)
        lp1 += a * (value - lp1)
        lp2 += a * (lp1 - lp2)
        out = lp2 * gain * 0.25 * breath * duck[i]
        left[i] += out
        right[i] += delay[d]
        delay[d] = out
        d = (d + 1) % len(delay)
        send[i] += out * 0.7


def swells(left, right, send):
    """Reversed chords that rise into the two memories, like something coming back."""
    for bar in (8, 36):
        notes = CHORD_HZ[chord_index(bar)]
        length = at(2 * BAR)
        start = at(bar * BAR) - length
        for i in range(length):
            p = i / length
            t = i / SR
            value = sum(math.sin(2 * math.pi * f * 2 * t) for f in notes) * (p ** 3) * 0.12
            j = (start + i) % N
            left[j] += value
            right[j] += value * 0.8
            send[j] += value * 0.8


def music_box_note(f, length):
    """A music-box tine: bright partials that fade fast, a wavering fundamental."""
    note = []
    phase = 0.0
    for i in range(int((length + 1.2) * SR)):
        t = i / SR
        phase += 2 * math.pi * f * wow(t + f) / SR
        env = min(1.0, t / 0.004) * math.exp(-t * 2.2)
        if t > length:
            env *= math.exp(-(t - length) * 4)
        note.append((math.sin(phase) + 0.3 * math.sin(3 * phase) * math.exp(-t * 7)
                     + 0.12 * math.sin(5.93 * phase) * math.exp(-t * 14)) * env)
    return note


def lead(left, right, send):
    rng = random.Random(21)
    for bar0 in range(0, BARS, 8):
        part = section(bar0)
        if part not in ("intro", "memoryA", "forgetting", "memoryB"):
            continue
        for beat, name, beats in MELODY:
            f = hz(name)
            gain = 0.3
            if part == "intro":
                if beat >= 16:
                    continue          # the intro only remembers the start
                gain = 0.22
            elif part == "forgetting":
                # Each 2-bar phrase breaks off sooner, quieter and a little lower.
                phrase = int(beat // 8)
                if beat % 8 >= 6 - phrase * 1.5:
                    continue
                f *= 2 ** (-0.15 * phrase / 12)
                gain = 0.28 * (1.0 - 0.18 * phrase)
            elif part == "memoryB" and rng.random() < 0.5:
                # Second time round, an echo a sixth below sometimes answers.
                low = music_box_note(f * 2 ** (-9 / 12), beats * BEAT)
                add(left, at(bar0 * BAR + (beat + 0.5) * BEAT), low, 0.09)
                add(send, at(bar0 * BAR + (beat + 0.5) * BEAT), low, 0.12)
            note = music_box_note(f, beats * BEAT)
            start = at(bar0 * BAR + beat * BEAT)
            add(left, start, note, gain * 0.9)
            add(right, start, note, gain * 0.75)
            add(right, start + at(0.75 * BEAT), note, gain * 0.3)
            add(left, start + at(1.5 * BEAT), note, gain * 0.18)
            add(right, start + at(2.25 * BEAT), note, gain * 0.1)
            add(send, start, note, gain * 0.8)


def arp(left, right, send):
    """Slow quarter-note chord tones, far away."""
    order = [0, 2, 1, 3]
    for bar in range(BARS):
        part = section(bar)
        if part not in ("memoryA", "build", "memoryB"):
            continue
        notes = CHORD_HZ[chord_index(bar)]
        for step in range(4):
            f = notes[order[step]] * 2
            pluck = []
            phase = 0.0
            for i in range(int(0.6 * SR)):
                t = i / SR
                phase += 2 * math.pi * f * wow(t) / SR
                pluck.append(math.sin(phase) * math.exp(-t * 6))
            start = at(bar * BAR + step * BEAT)
            add(left if step % 2 else right, start, pluck, 0.08)
            add(send, start, pluck, 0.14)


def sub(mono, duck):
    """Only a quiet, round sub under the memories; no wobble."""
    phase = 0.0
    for i in range(N):
        t = i / SR
        bar = int(t / BAR)
        if not has_beat(bar):
            continue
        phase = (phase + ROOT_HZ[chord_index(bar)] / SR) % 1.0
        # Fade in where a memory starts and out where it ends, so the sub never clicks.
        edge = min(t - (8 if bar < 24 else 36) * BAR, (24 if bar < 24 else 52) * BAR - t)
        mono[i] += math.sin(2 * math.pi * phase) * 0.09 * duck[i] * min(1.0, edge / 0.25)


def crackle(left, right):
    """Old-record dust: a faint hiss and sparse clicks, all the way through."""
    rng = random.Random(33)
    lp = 0.0
    for i in range(N):
        lp += 0.08 * (rng.uniform(-1, 1) - lp)
        value = lp * 0.012
        if rng.random() < 0.0004:
            value += rng.uniform(-0.12, 0.12)
        left[i] += value
        right[i] += value * 0.9


def reverb(send):
    """A long Schroeder reverb (4 combs, 2 allpasses per side), tails wrapped to the start."""
    outs = []
    for spread in (0, 17):
        combs = [[0.0] * (n + spread) for n in (1201, 1291, 1373, 1447)]
        idx = [0, 0, 0, 0]
        damp = [0.0, 0.0, 0.0, 0.0]
        aps = [[0.0] * (n + spread) for n in (347, 263)]
        aidx = [0, 0]
        out = [0.0] * N
        tail = int(5.0 * SR)
        for i in range(N + tail):
            x = send[i] * 0.25 if i < N else 0.0
            y = 0.0
            for c in range(4):
                buf = combs[c]
                value = buf[idx[c]]
                damp[c] = value * 0.55 + damp[c] * 0.45
                buf[idx[c]] = x + damp[c] * 0.88
                idx[c] = (idx[c] + 1) % len(buf)
                y += value
            for a in range(2):
                buf = aps[a]
                value = buf[aidx[a]]
                buf[aidx[a]] = y + value * 0.5
                y = value - y * 0.5
                aidx[a] = (aidx[a] + 1) % len(buf)
            out[i % N] += y
        outs.append(out)
    return outs


def write_wav(path, left, right):
    frames = bytearray()
    for l, r in zip(left, right):
        frames += struct.pack("<hh", int(max(-1, min(1, l)) * 32767), int(max(-1, min(1, r)) * 32767))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(frames)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 2, SR, SR * 4, 4, 16))
        f.write(b"data" + struct.pack("<I", len(frames)) + frames)


def main():
    left, right, mono, send = [0.0] * N, [0.0] * N, [0.0] * N, [0.0] * N
    print("drums"); kicks = drums(mono, send)
    duck = sidechain(kicks)
    print("pad"); pad(left, right, send, duck)
    print("swells"); swells(left, right, send)
    print("music box"); lead(left, right, send)
    print("arp"); arp(left, right, send)
    print("sub"); sub(mono, duck)
    print("crackle"); crackle(left, right)
    print("reverb"); rev_l, rev_r = reverb(send)
    for i in range(N):
        left[i] += mono[i] + rev_l[i] * 0.6
        right[i] += mono[i] + rev_r[i] * 0.6
    # Level the mix, round off the peaks gently, then leave some headroom.
    peak = max(max(abs(v) for v in left), max(abs(v) for v in right), 1e-6)
    soft = math.tanh(1.3)
    for i in range(N):
        left[i] = math.tanh(left[i] / peak * 1.3) / soft * 0.85
        right[i] = math.tanh(right[i] / peak * 1.3) / soft * 0.85
    # Smooth the seam: the last and first few milliseconds meet at zero instead of jumping.
    seam = int(0.008 * SR)
    for i in range(seam):
        g = i / seam
        for side in (left, right):
            side[i] *= g
            side[N - 1 - i] *= g
    write_wav(OUT, left, right)
    print("wrote %s: %.1f s, %d bars at %d BPM" % (OUT, N / SR, BARS, BPM))


if __name__ == "__main__":
    main()
