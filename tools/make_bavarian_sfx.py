#!/usr/bin/env python3
"""Every sound effect in Sturmball, made from scratch in Bavarian style.

ROUND AN (Anthony, 8 Oct 2026): "replace ALL sound effects with bavarian
sounds - woods, birds, beer being poured, cow bell, tuba ... winning should
sound fun and good, losing unfun and sad."

Nothing here is a recording. Every sound is built from sine waves and
filtered noise by the little instruments below (a tuba, an Alpine cow bell,
a wood block, beer pouring, a blackbird ...), so there is nobody to credit
and no licence to track: the files are our own (data/SoundCredits.csv).

    python3 tools/make_bavarian_sfx.py            # make them all
    python3 tools/make_bavarian_sfx.py bav_goal   # make one (or several)

Writes assets/audio/bav_<name>.ogg. Audio.csv names these files in its
Sound column, so a remade file is heard the next time the game starts.

KIND TO EARS: every sound is low-passed (nothing shrill above ~7 kHz),
faded in and out (no clicks), brought to the same loudness and kept under
-1 dBFS by a soft limiter, so no sound can clip. How loud each one plays
in the game is the Volume column of Audio.csv.

Needs numpy and scipy (pip install numpy scipy) and ffmpeg for the .ogg.
"""
import os
import subprocess
import sys
import tempfile
import wave
import zlib

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(1810)  # the year of the first Oktoberfest; reseeded per sound


# =============================================================
#  BASICS
# =============================================================

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def silence(dur):
    return np.zeros(int(dur * SR))


def note(name):
    """'Bb2' -> Hz. Brass bands play in B-flat, so most tunes here do too."""
    names = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
             "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
    pitch, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + names[pitch]
    return 440.0 * 2 ** ((midi - 69) / 12)


def env_ad(n, attack, decay_time):
    """Fast rise, exponential fall. decay_time = seconds to fall ~60 dB."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-6.9 * np.maximum(t - attack, 0) / max(decay_time, 1e-4))


def env_asr(n, attack, release):
    """Rise, hold, fall - for notes that are held (tuba, accordion)."""
    e = np.ones(n)
    a = min(int(attack * SR), n)
    r = min(int(release * SR), n - a)
    if a:
        e[:a] = np.linspace(0, 1, a) ** 0.7
    if r:
        e[n - r:] *= np.linspace(1, 0, r) ** 1.5
    return e


def lowpass(x, hz, order=2):
    b, a = signal.butter(order, min(hz, SR * 0.45) / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def resonator(x, hz, q):
    """One formant / body resonance."""
    b, a = signal.iirpeak(hz / (SR / 2), q)
    return signal.lfilter(b, a, x)


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def mix(parts, total=None):
    """parts = [(start_seconds, samples, gain), ...]"""
    end = max(int(s * SR) + len(x) for s, x, _ in parts)
    out = np.zeros(max(end, int((total or 0) * SR)))
    for start, x, gain in parts:
        i = int(start * SR)
        out[i:i + len(x)] += x * gain
    return out


def fade(x, fin=0.004, fout=0.02):
    x = x.copy()
    a, b = min(int(fin * SR), len(x) // 2), min(int(fout * SR), len(x) // 2)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


# =============================================================
#  THE INSTRUMENTS
# =============================================================

def brass(freq, dur, vel=0.8, bright=1.0, vibrato=0.0, scoop=0.03, partials=14):
    """A brass note. Tuba when low, flugelhorn / trumpet when high.
    vel and bright open the tone - a loud note is a brighter one."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    # the lip scoop up into the note, and a slow vibrato on held notes
    f = freq * (1 - scoop * np.exp(-t / 0.035))
    if vibrato:
        f *= 1 + vibrato * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.15) / 0.3, 0, 1)
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = np.zeros(n)
    # the brassy swell: upper partials come in later than the fundamental
    for k in range(1, partials + 1):
        if freq * k > 6500:
            break
        amp = (1.0 / k ** (1.9 - 0.7 * vel * bright))
        rise = 0.012 + 0.006 * k
        out += amp * np.sin(k * phase) * np.clip(t / rise, 0, 1)
    out += 0.015 * lowpass(noise(dur), 1500) * np.exp(-t / 0.05)  # breath
    out *= env_asr(n, 0.02, min(0.08, dur * 0.4))
    return out / partials ** 0.2


def tuba(name, dur, vel=0.8, **kw):
    return brass(note(name), dur, vel=vel, bright=0.8, **kw)


def horn(name, dur, vel=0.7, **kw):
    return lowpass(brass(note(name), dur, vel=vel, bright=1.0, **kw), 4500)


def clarinet(name, dur, vel=0.6):
    """Odd partials, a little breath - the Bavarian band's clarinet."""
    freq = note(name)
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * (1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.1) / 0.2, 0, 1))
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = sum(np.sin(k * phase) / k ** (1.4 - 0.4 * vel) for k in range(1, 12, 2) if freq * k < 6000)
    out += 0.01 * bandpass(noise(dur), 1000, 4000)
    return out * env_asr(n, 0.03, 0.06) * 0.6


def accordion(names, dur, vel=0.6):
    """A chord on the squeeze box: two reeds per note, a hair apart, so it
    shimmers the way a Bavarian (musette) accordion does."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for name in names:
        for detune in (1.0, 1.0045):
            f = note(name) * detune
            ph = 2 * np.pi * f * t + rng.uniform(0, 6.28)
            out += sum(np.sin(k * ph) / k ** 1.25 for k in range(1, 10) if f * k < 5000)
    out *= 1 + 0.06 * np.sin(2 * np.pi * 5.0 * t)  # the bellows
    return lowpass(out, 3800) * env_asr(n, 0.04, 0.12) * vel / len(names)


def cowbell(freq=620, dur=1.4, vel=1.0, clapper=True):
    """An Alpine cow bell (Kuhschelle): a hammered sheet-metal bell with a
    hollow, slightly sour ring - not the disco cowbell."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    ratios = [1.0, 1.51, 2.08, 2.79, 3.43, 4.17]
    decays = [dur, dur * 0.7, dur * 0.45, dur * 0.3, dur * 0.2, dur * 0.12]
    amps = [1.0, 0.65, 0.5, 0.32, 0.2, 0.12]
    out = np.zeros(n)
    for r, d, a in zip(ratios, decays, amps):
        f = freq * r * (1 + rng.uniform(-0.004, 0.004))
        if f > 7000:
            continue
        # a slow beat between the two halves of the bell
        beat = 1 + 0.25 * np.sin(2 * np.pi * rng.uniform(2, 5) * t)
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-6.9 * t / d) * beat
    if clapper:
        click = bandpass(noise(0.015), 1200, 4500) * env_ad(int(0.015 * SR), 0.0005, 0.012)
        out[: len(click)] += 0.8 * click
    return fade(out * vel, 0.001, 0.05)


def cowbells(count=3, dur=1.6, spread=0.5, base=560):
    """A few cow bells shaken together - a herd coming down the Alm, or the
    supporters' bells in the stands."""
    parts = []
    for i in range(count):
        f = base * rng.uniform(0.85, 1.5)
        parts.append((rng.uniform(0, spread), cowbell(f, dur * rng.uniform(0.7, 1.0), rng.uniform(0.5, 1.0)), 1.0))
    return mix(parts)


def glock(name, dur=0.9, vel=0.7):
    """Glockenspiel bar: bright, sweet, gone quickly."""
    freq = note(name)
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * freq * t) * np.exp(-6.9 * t / dur)
    out += 0.25 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-6.9 * t / (dur * 0.25))
    out += 0.08 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-6.9 * t / (dur * 0.1))
    return fade(out * vel, 0.0008, 0.02)


def woodblock(freq=900, dur=0.12, vel=1.0, hollow=1.0):
    """A knock on wood: a beer table, a cuckoo clock, a Schuhplattler's slap."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * freq * t) * np.exp(-6.9 * t / dur)
    out += 0.45 * hollow * np.sin(2 * np.pi * freq * 2.31 * t) * np.exp(-6.9 * t / (dur * 0.5))
    out += 0.2 * np.sin(2 * np.pi * freq * 3.9 * t) * np.exp(-6.9 * t / (dur * 0.3))
    click = bandpass(noise(dur), 800, 5000) * np.exp(-t / 0.002)
    return fade((out + 0.5 * click) * vel, 0.0005, 0.01)


def thump(freq=90, dur=0.25, vel=1.0, drop=0.5):
    """Something heavy landing: a boot into leather, a body on grass."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * (1 + drop * np.exp(-t / 0.02))
    out = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-6.9 * t / dur)
    out += 0.35 * np.sin(2 * np.pi * freq * 3.3 * t) * np.exp(-t / 0.03)
    out += 0.6 * lowpass(noise(dur), 1500) * np.exp(-t / 0.012)
    return fade(out * vel, 0.0005, 0.02)


def leather(dur=0.06, vel=1.0, low=600, high=2800):
    """Leather slapped: a ball, a goalkeeper's glove, Lederhosen."""
    t = t_axis(dur)
    return fade(bandpass(noise(dur), low, high) * np.exp(-t / 0.008) * vel, 0.0003, 0.005)


def kick(vel=1.0, heavy=False):
    d = 0.35 if heavy else 0.18
    body = thump(85 if heavy else 120, d, 1.0, drop=1.2 if heavy else 0.8)
    return mix([(0, body, vel), (0, leather(0.05, 0.7 * vel), 1.0)])


def glass_clink(freq=2100, dur=0.6, vel=1.0):
    """Two Maß glasses touching - Prost! Thick glass, so lower and duller
    than a wine glass, and low-passed so it never stings."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for r, a, d in [(1.0, 1.0, dur), (1.58, 0.6, dur * 0.6), (2.31, 0.35, dur * 0.4), (2.97, 0.15, dur * 0.25)]:
        out += a * np.sin(2 * np.pi * freq * r * t + rng.uniform(0, 6)) * np.exp(-6.9 * t / d)
    out += 0.3 * bandpass(noise(dur), 1500, 5000) * np.exp(-t / 0.003)
    return lowpass(fade(out * vel, 0.0005, 0.03), 6500)


def mug_on_table(vel=1.0):
    """A full Maßkrug set down hard on a wooden table."""
    return mix([
        (0, thump(140, 0.22, 1.0, drop=0.3), 1.0),
        (0, woodblock(310, 0.14, 0.6), 1.0),
        (0, glass_clink(780, 0.25, 0.35), 1.0),
        (0.02, slosh(0.25), 0.35),
    ]) * vel


def slosh(dur=0.3):
    t = t_axis(dur)
    return bandpass(noise(dur), 250, 1400) * np.sin(np.pi * t / dur) ** 2


def bubbles(dur, rate=40, lo=500, hi=1600, vel=1.0):
    """Air bubbles in liquid - each one a little rising 'blip'."""
    n = int(dur * SR)
    out = np.zeros(n)
    for _ in range(int(rate * dur)):
        start = rng.integers(0, n)
        f0 = rng.uniform(lo, hi)
        d = rng.uniform(0.008, 0.03)
        m = int(d * SR)
        tt = np.arange(m) / SR
        f = f0 * (1 + 2.5 * tt / d)
        blip = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / (d / 3))
        end = min(n, start + m)
        out[start:end] += blip[: end - start] * rng.uniform(0.3, 1.0)
    return out * vel


def pour(dur=1.4, vel=1.0):
    """Beer pouring from a jug into a Maß: the stream, the glug, the head
    of foam settling."""
    t = t_axis(dur)
    shape = np.clip(t / 0.08, 0, 1) * np.clip((dur - t) / 0.25, 0, 1)
    stream = bandpass(noise(dur), 300, 1800) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t + np.sin(2 * np.pi * 1.3 * t)))
    # the pitch of the glass filling: the resonance climbs as it fills up
    filled = np.zeros_like(stream)
    for i, f in enumerate(np.linspace(450, 1100, 8)):
        seg = slice(int(i * len(t) / 8), int((i + 1) * len(t) / 8))
        filled[seg] = resonator(stream, f, 4)[seg]
    foam = highpass(noise(dur), 3000) * (rng.random(len(t)) < 0.02) * np.clip((t - 0.4) / 0.5, 0, 1)
    out = 0.5 * stream * shape + 0.9 * filled * shape + 0.6 * bubbles(dur, 30, 500, 1400) * shape + 0.05 * lowpass(foam, 6000)
    return fade(out * vel, 0.01, 0.15)


def gulp(vel=1.0):
    """Swallowing a mouthful - a low, wet 'glk'."""
    d = 0.16
    t = t_axis(d)
    f = 220 * (1 + 1.5 * t / d)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / d) ** 2
    return fade(lowpass(body + 0.4 * slosh(d), 1800) * vel)


def cork_pop(vel=1.0):
    d = 0.12
    t = t_axis(d)
    pop = np.sin(2 * np.pi * np.cumsum(500 * (1 + 2 * np.exp(-t / 0.01))) / SR) * np.exp(-t / 0.02)
    return fade(pop + 0.3 * bandpass(noise(d), 1000, 4000) * np.exp(-t / 0.004)) * vel


def fizz(dur=0.8, vel=1.0):
    """Foam hissing down - soft and sparkling, never a hiss in the ear."""
    t = t_axis(dur)
    crackle = bandpass(noise(dur) * (rng.random(len(t)) < 0.05), 2500, 6500)
    return fade(crackle * np.exp(-t / (dur * 0.5)) * vel, 0.005, 0.1)


def whistle(dur=0.5, freq=1750, vel=1.0, trill=True):
    """The referee's pea whistle - pitched lower and rounder than a real one,
    so it carries without hurting."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    roll = np.sin(2 * np.pi * 28 * t) if trill else np.zeros(n)
    f = freq * (1 + 0.03 * roll) * (1 - 0.04 * np.exp(-t / 0.02))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR)
    tone += 0.06 * np.sin(2 * 2 * np.pi * np.cumsum(f) / SR)
    am = 1 - (0.35 * (0.5 + 0.5 * roll) if trill else 0)
    breath = bandpass(noise(dur), freq * 0.8, freq * 1.3) * 0.08
    out = (tone * am + breath) * env_asr(n, 0.015, 0.05)
    return lowpass(out, 3200, 4) * vel


def bird(kind="amsel", vel=1.0):
    """A bird in the trees. amsel = blackbird (fluting), fink = chaffinch
    (a quick descending rattle), meise = great tit (tee-cha tee-cha)."""
    parts = []
    def syll(f0, f1, d, a=1.0):
        t = t_axis(d)
        f = np.linspace(f0, f1, len(t)) * (1 + 0.04 * np.sin(2 * np.pi * 60 * t))
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / d) ** 1.5 * a
    if kind == "amsel":
        pos = 0
        for f0, f1, d in [(1800, 2300, 0.12), (2300, 1900, 0.1), (1700, 2600, 0.16), (2500, 2100, 0.09), (2200, 2900, 0.07)]:
            parts.append((pos, syll(f0, f1, d), 1.0))
            pos += d + 0.03
    elif kind == "fink":
        pos = 0
        for i in range(9):
            f = 4200 - i * 180
            parts.append((pos, syll(f, f - 600, 0.04), 1 - i * 0.05))
            pos += 0.055
        parts.append((pos + 0.02, syll(3000, 2000, 0.12), 0.8))
    else:  # meise
        pos = 0
        for _ in range(3):
            parts.append((pos, syll(4300, 4200, 0.08), 0.7))
            parts.append((pos + 0.11, syll(3200, 3100, 0.1), 0.6))
            pos += 0.26
    return lowpass(mix(parts), 6500) * vel


def crowd(dur, mood="cheer", size=40, vel=1.0):
    """A beer-tent crowd. cheer = going up, groan = the air going out,
    murmur = chatting, ooh = a near miss, boo = a red card."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    vowels = {"a": (800, 1200, 2500), "o": (500, 900, 2400), "e": (450, 1900, 2600), "u": (350, 800, 2300), "ei": (650, 1600, 2500)}
    for _ in range(size):
        start = rng.uniform(0, 0.25) if mood in ("cheer", "ooh", "groan", "boo") else rng.uniform(0, dur * 0.7)
        length = rng.uniform(0.6, 1.0) * (dur - start)
        if length < 0.1:
            continue
        m = int(length * SR)
        tt = np.arange(m) / SR
        base = rng.uniform(100, 230) * (1.4 if rng.random() < 0.35 else 1.0)
        if mood == "cheer":
            f = base * (1.2 + 0.35 * np.clip(tt / 0.3, 0, 1)) * (1 + 0.03 * np.sin(2 * np.pi * rng.uniform(4, 7) * tt))
            vow = rng.choice(["e", "ei", "a"])
            amp = np.clip(tt / 0.15, 0, 1) * np.exp(-tt / (length * 0.7))
        elif mood == "groan":
            f = base * (1.1 - 0.35 * tt / length)
            vow = rng.choice(["o", "u"])
            amp = np.clip(tt / 0.1, 0, 1) * np.exp(-tt / (length * 0.5))
        elif mood == "ooh":
            f = base * (1.0 + 0.25 * np.sin(np.pi * tt / length))
            vow = "u"
            amp = np.sin(np.pi * tt / length) ** 1.2
        elif mood == "boo":
            f = base * 0.9 * np.ones(m)
            vow = "u"
            amp = np.clip(tt / 0.2, 0, 1) * np.exp(-tt / (length * 0.8))
        else:  # murmur: short words
            f = base * (1 + 0.1 * np.sin(2 * np.pi * rng.uniform(2, 4) * tt))
            vow = rng.choice(list(vowels))
            amp = (np.sin(2 * np.pi * rng.uniform(1.5, 3.5) * tt) > 0.2) * 1.0
            amp = lowpass(amp, 30)
        ph = 2 * np.pi * np.cumsum(f) / SR
        src = sum(np.sin(k * ph) / k for k in range(1, 18) if base * k < 5000)  # a voice's buzz
        voice = sum(resonator(src, F, 6) * g for F, g in zip(vowels[vow], (1.0, 0.6, 0.25)))
        i = int(start * SR)
        out[i:i + m] += voice[: n - i] * amp[: n - i] * rng.uniform(0.4, 1.0)
    bed = bandpass(noise(dur), 250, 1800) * 0.1
    shape = {"cheer": np.clip(t / 0.15, 0, 1) * np.exp(-t / (dur * 0.6)),
             "groan": np.clip(t / 0.1, 0, 1) * np.exp(-t / (dur * 0.4)),
             "ooh": np.sin(np.pi * np.clip(t / dur, 0, 1)),
             "boo": np.clip(t / 0.2, 0, 1) * np.exp(-t / (dur * 0.7)),
             "murmur": np.ones(n)}[mood]
    out = lowpass(out + bed * shape, 3800)
    return fade(out * vel, 0.01, 0.2)


def creak(dur=0.7, pitch=70, vel=1.0):
    """Old timber: a door, a wagon hatch. Stick-slip friction through the
    body of the wood - kept low and dull so it groans rather than squeals."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    rate = pitch * (1 + 0.6 * np.sin(np.pi * t / dur)) * (1 + 0.15 * lowpass(noise(dur), 8))
    phase = np.cumsum(rate) / SR
    pulses = (np.diff(np.floor(phase), prepend=0) > 0).astype(float)
    src = pulses * (0.6 + 0.4 * rng.random(n))
    body = resonator(src, 320, 8) + 0.7 * resonator(src, 760, 10) + 0.4 * resonator(src, 1350, 12)
    out = lowpass(body, 3000) * np.sin(np.pi * t / dur) ** 0.6
    return fade(out * vel, 0.01, 0.05)


def snore(vel=1.0):
    """A sleeper in the dorms: the rumbling in-breath, the 'pfff' out."""
    d_in, d_out = 1.1, 0.9
    t = t_axis(d_in)
    flutter = (np.sin(2 * np.pi * 32 * t) > 0).astype(float)
    src = lowpass(flutter, 600) + 0.3 * noise(d_in)
    inhale = (resonator(src, 400, 4) + 0.5 * resonator(src, 900, 6)) * np.sin(np.pi * t / d_in) ** 1.5
    t2 = t_axis(d_out)
    exhale = bandpass(noise(d_out), 500, 2200) * np.sin(np.pi * t2 / d_out) ** 2 * 0.5
    one = np.concatenate([inhale, exhale, silence(0.25)])
    return lowpass(np.concatenate([one, one * 0.85]), 3000) * vel


def voice(text_shape, vel=1.0):
    """A wordless grunt. text_shape = [(vowel, pitch_hz, seconds, breathy), ...]
    - 'hm', 'oh', 'ha'. Short and buried in other sounds on purpose."""
    formants = {"m": (250, 1100, 2400), "a": (750, 1150, 2500), "o": (450, 850, 2400),
                "e": (500, 1800, 2500), "h": (750, 1150, 2500)}
    pieces = []
    for vow, f0, d, breathy in text_shape:
        t = t_axis(d)
        f = f0 * (1 + 0.15 * np.exp(-t / 0.05)) * (1 - 0.12 * t / d)
        ph = 2 * np.pi * np.cumsum(f) / SR
        src = sum(np.sin(k * ph) / k ** 1.2 for k in range(1, 25) if f0 * k < 5000)
        src = src * (1 - breathy) + noise(d) * breathy * 0.6
        out = sum(resonator(src, F, 7) * g for F, g in zip(formants[vow], (1.0, 0.5 if vow != "m" else 0.1, 0.2)))
        pieces.append(out * np.sin(np.pi * np.clip(t / d, 0, 1)) ** 0.5)
    return lowpass(np.concatenate(pieces), 4000) * vel


def crackle(dur=0.8, vel=1.0):
    """Fire: pops and a low roar."""
    t = t_axis(dur)
    pops = np.zeros(len(t))
    for _ in range(int(dur * 30)):
        i = rng.integers(0, len(t) - 400)
        pops[i:i + 400] += woodblock(rng.uniform(1500, 3500), 400 / SR, rng.uniform(0.1, 0.5), 0.2)
    roar = lowpass(noise(dur), 400) * 0.4
    return fade((pops + roar) * np.clip((dur - t) / 0.3, 0, 1) * vel)


def whoosh(dur=0.3, lo=400, hi=2500, vel=1.0):
    t = t_axis(dur)
    x = noise(dur)
    out = np.zeros_like(x)
    steps = 12
    for i in range(steps):
        f = lo + (hi - lo) * i / steps
        seg = slice(int(i * len(t) / steps), int((i + 1) * len(t) / steps))
        out[seg] = bandpass(x, f * 0.7, f * 1.3)[seg]
    return fade(out * np.sin(np.pi * t / dur) ** 2 * vel)


def boeller(vel=1.0):
    """A Böller - the Bavarian black-powder salute fired at festivals.
    A deep boom from across the valley with an echo off the hills, never a
    crack in the ear."""
    d = 1.8
    t = t_axis(d)
    boom = lowpass(noise(d), 180) * np.exp(-t / 0.25) * 3
    boom += np.sin(2 * np.pi * np.cumsum(55 * (1 + np.exp(-t / 0.05))) / SR) * np.exp(-t / 0.35)
    echo = np.zeros_like(boom)
    delay = int(0.45 * SR)
    echo[delay:] = lowpass(boom, 120)[:-delay] * 0.35
    return fade(lowpass(boom + echo, 900) * vel, 0.002, 0.3)


def zither(name, dur=1.2, vel=0.7):
    """A plucked zither string (Karplus-Strong)."""
    freq = note(name)
    period = int(SR / freq)
    buf = rng.uniform(-1, 1, period)
    n = int(dur * SR)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = 0.4985 * (buf[i % period] + buf[(i + 1) % period])
    return lowpass(fade(out * vel, 0.001, 0.05), 5000)


def coins(count=5, vel=1.0):
    parts = []
    for i in range(count):
        f = rng.uniform(2000, 3300)
        d = rng.uniform(0.08, 0.2)
        t = t_axis(d)
        c = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.47 * t)) * np.exp(-6.9 * t / d)
        parts.append((i * rng.uniform(0.03, 0.07), c, rng.uniform(0.4, 1.0)))
    return lowpass(mix(parts), 6000) * vel


def hand_bell(freq=1500, dur=1.0, vel=1.0):
    t = t_axis(dur)
    out = sum(a * np.sin(2 * np.pi * freq * r * t) * np.exp(-6.9 * t / (dur * dd))
              for r, a, dd in [(1, 1, 1), (2.0, 0.4, 0.6), (2.98, 0.25, 0.4), (4.1, 0.1, 0.25)])
    return lowpass(fade(out * vel, 0.0005, 0.05), 6500)


def flutter(dur=0.6, vel=1.0):
    """A banner snapping in the wind."""
    t = t_axis(dur)
    rate = 14 + 6 * np.sin(np.pi * t / dur)
    flaps = (np.sin(2 * np.pi * np.cumsum(rate) / SR) > 0.6).astype(float)
    flaps = lowpass(flaps, 120)
    cloth = bandpass(noise(dur), 300, 2500) * flaps
    return fade(cloth * np.sin(np.pi * t / dur) * vel, 0.01, 0.08)


# =============================================================
#  LITTLE TUNES (a Bavarian brass band, three players and a tuba)
# =============================================================

def oompah(bass, chord, beats, bpm=132, vel=0.8):
    """The tuba 'oom' on one and three, the band's 'pah' in between."""
    beat = 60 / bpm
    parts = []
    for i in range(beats):
        if i % 2 == 0:
            parts.append((i * beat, tuba(bass[(i // 2) % len(bass)], beat * 0.8, vel), 0.9))
        else:
            for n in chord:
                parts.append((i * beat, horn(n, beat * 0.45, vel * 0.7, scoop=0.01), 0.22))
    return mix(parts)


def melody(line, bpm=132, instrument="horn", vel=0.75, gain=0.5):
    """line = [(note or None, beats), ...]"""
    beat = 60 / bpm
    pos = 0
    parts = []
    for name, beats in line:
        if name:
            d = beats * beat
            if instrument == "horn":
                x = horn(name, d * 0.95, vel, vibrato=0.006 if beats >= 2 else 0)
            elif instrument == "clarinet":
                x = clarinet(name, d * 0.95, vel)
            elif instrument == "glock":
                x = glock(name, max(d, 0.5), vel)
            else:
                x = tuba(name, d * 0.95, vel, vibrato=0.01 if beats >= 2 else 0)
            parts.append((pos, x, gain))
        pos += beats * 60 / bpm
    return mix(parts)


def sad_tuba(notes, bpm=76, vel=0.7, wobble=True):
    """The 'wah wah wahhh' - a tuba falling and giving up. Played soft and
    round so it is funny-sad, never grating."""
    beat = 60 / bpm
    parts = []
    pos = 0
    for i, (name, beats) in enumerate(notes):
        last = i == len(notes) - 1
        d = beats * beat
        x = brass(note(name) * 2, d * 0.92, vel, bright=0.75, vibrato=0.025 if (last and wobble) else 0.004, scoop=0.05)
        if last:  # sags flat as it dies away
            t = t_axis(d * 0.92)
            x *= np.exp(-t / (d * 0.6))
        parts.append((pos, lowpass(x, 3000), 1.0))
        pos += d
    return mix(parts)


# =============================================================
#  REAL INSTRUMENTS (round AN take 2)
#
#  The brass band, accordion, dulcimer, bells, drums and the crowd's
#  applause are REAL RECORDINGS from the free GeneralUser GS SoundFont the
#  songs already use (art_source/soundfonts/, by S. Christian Collins,
#  free for any use). The thumps, beer, glass and wood above fill in what
#  a band cannot play.
# =============================================================

SOUNDFONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art_source", "soundfonts", "GeneralUser-GS.sf2")

# name: (bank, program). Bank 128 = a drum kit, where the "note" picks the drum.
INSTRUMENTS = {
    "tuba": (0, 58), "trombone": (0, 57), "trumpet": (0, 56), "horn": (1, 60),
    "brass": (8, 61), "clarinet": (0, 71), "accordion": (8, 21), "dulcimer": (0, 15),
    "glock": (0, 9), "xylo": (0, 13), "marimba": (0, 12), "tubular": (0, 14), "church": (8, 14),
    "woodblock": (0, 115), "bassdrum": (8, 116), "choir": (1, 52), "timpani": (0, 47),
    "applause": (0, 126), "laughing": (1, 126), "footsteps": (5, 126), "punch": (3, 126),
    "explosion": (3, 127), "door": (3, 124), "creak": (2, 124), "horse": (2, 123),
    "birds": (0, 123), "bird2": (3, 123), "bubbles": (5, 122), "stream": (4, 122), "wind": (3, 122),
    "kit": (128, 0), "orch": (128, 48),
}
# drums in the kit (General MIDI numbers)
KICK, SNARE, CLAP, CRASH, COWBELL, TAMBO, HI_WOOD, LO_WOOD, TRIANGLE = 36, 38, 39, 49, 56, 54, 76, 77, 81


def midi(k):
    if isinstance(k, int):
        return k
    return int(round(69 + 12 * np.log2(note(k) / 440.0)))


def sf(events, tail=1.5, room=0.18):
    """Play the SoundFont. events = [(seconds, instrument, note, velocity, length), ...]
    note is 'Bb2' or a drum number. A 6th item 'bend' = semitones the note
    slides by over its length (the sad trombone). room = beer-tent echo."""
    import tinysoundfont
    synth = tinysoundfont.Synth(samplerate=SR)
    sfid = synth.sfload(SOUNDFONT)
    chans = {}
    timeline = []
    for ev in events:
        start, inst, key, vel, length = ev[:5]
        bend = ev[5] if len(ev) > 5 else 0
        if inst not in chans:
            c = len(chans)
            c = c + 1 if c >= 9 else c
            chans[inst] = c
            bank, prog = INSTRUMENTS[inst]
            if bank == 128:
                synth.program_select(c, sfid, 128, prog, True)
            else:
                synth.program_select(c, sfid, bank, prog)
            synth.pitchbend_range(c, 12)
        c = chans[inst]
        k = midi(key)
        timeline.append((start, 1, "on", c, k, int(vel), 0))
        if bend:
            steps = 24
            for i in range(1, steps + 1):
                timeline.append((start + length * i / steps, 0, "bend", c, k, 0, bend * (i / steps) ** 1.6))
            timeline.append((start + length + 0.3, 2, "bend", c, k, 0, 0.0))
        timeline.append((start + length, 0, "off", c, k, 0, 0))
    timeline.sort(key=lambda e: (e[0], e[1]))
    total = int((max(e[0] for e in timeline) + tail) * SR)
    out = np.zeros((total, 2), dtype=np.float32)
    pos = 0
    for t, _, kind, c, k, v, b in timeline + [(total / SR, 9, "end", 0, 0, 0, 0)]:
        at = min(total, int(t * SR))
        if at > pos:
            out[pos:at] = np.frombuffer(synth.generate(at - pos), dtype=np.float32).reshape(-1, 2)
            pos = at
        if kind == "on":
            synth.noteon(c, k, v)
        elif kind == "off":
            synth.noteoff(c, k)
        elif kind == "bend":
            synth.pitchbend(c, int(8192 + 8191 * max(-1, min(1, b / 12))))
    mono = out.mean(axis=1).astype(float)
    return tent(mono, room) if room else mono


def tent(x, wet=0.18, size=0.9):
    """A beer tent's warm echo: soft, short, dull - never a cathedral."""
    n = int(size * SR)
    r = np.random.default_rng(3)
    ir = r.standard_normal(n) * np.exp(-np.arange(n) / (0.22 * SR))
    ir[: int(0.01 * SR)] = 0
    ir = lowpass(ir, 2800)
    ir /= np.sqrt((ir ** 2).sum())
    wet_sig = signal.fftconvolve(x, ir)
    dry = np.zeros(len(wet_sig))
    dry[: len(x)] = x
    return dry * (1 - wet * 0.5) + wet * wet_sig


def polka(bars, chords, melody=(), bpm=138, start=0.0, tuba_vel=105, pah_vel=80, mel_inst="trumpet",
          mel_vel=95, drums=True, thirds=True):
    """A Bavarian polka, as events: tuba on 1 and 3, accordion 'pah' on 2
    and 4, a bass drum and a little snare, and a tune (with its third below,
    the Bavarian way). chords = one triad per bar, e.g. [('Bb1','F2'), ['D4','F4','Bb4']]
    melody = [(note or None, beats), ...]"""
    beat = 60 / bpm
    ev = []
    for b in range(bars):
        (root, fifth), triad = chords[b % len(chords)]
        t0 = start + b * 4 * beat
        ev += [(t0, "tuba", root, tuba_vel, beat * 0.8), (t0 + 2 * beat, "tuba", fifth, tuba_vel - 8, beat * 0.8)]
        for off in (1, 3):
            for n in triad:
                ev.append((t0 + off * beat, "accordion", n, pah_vel, beat * 0.45))
        if drums:
            ev += [(t0, "kit", KICK, 70, 0.1), (t0 + 2 * beat, "kit", KICK, 60, 0.1),
                   (t0 + beat, "kit", SNARE, 38, 0.1), (t0 + 3 * beat, "kit", SNARE, 38, 0.1)]
    pos = start
    for n, beats in melody:
        if n:
            ev.append((pos, mel_inst, n, mel_vel, beats * beat * 0.92))
            if thirds:
                ev.append((pos, "clarinet", midi(n) - 4 if midi(n) % 12 in (2, 7) else midi(n) - 3, mel_vel - 15, beats * beat * 0.92))
        pos += beats * beat
    return ev


def moo(vel=1.0):
    """A cow on the Alm: a long, low 'mmmoooh'."""
    d = 1.6
    t = t_axis(d)
    f = 120 * (1 + 0.25 * np.sin(np.pi * np.clip(t / d, 0, 1)) - 0.15 * t / d)
    ph = 2 * np.pi * np.cumsum(f) / SR
    src = sum(np.sin(k * ph) / k ** 1.1 for k in range(1, 30) if 120 * k < 5000) + 0.05 * noise(d)
    mouth = np.clip((t - 0.25) / 0.35, 0, 1)  # m ... oo opening
    voice = (1 - mouth) * resonator(src, 260, 6) + mouth * (resonator(src, 420, 5) + 0.6 * resonator(src, 800, 6) + 0.2 * resonator(src, 2400, 8))
    return fade(lowpass(voice * np.sin(np.pi * t / d) ** 0.7, 3500) * vel, 0.05, 0.3)


# =============================================================
#  THE SOUNDS - one function per file. The docstring is what you
#  hear; it is copied into data/SoundCredits.csv.
# =============================================================

def s_kickoff():
    "Kick-off: the referee's whistle, a bass-drum boom, the brass band's 'oom-pah-TA!', cow bells and the tent clapping."
    ev = [(0.62, "kit", KICK, 110, 0.2), (0.62, "orch", 57, 70, 1.0),
          (0.62, "tuba", "F2", 100, 0.22), (0.86, "tuba", "Bb1", 110, 0.8),
          (0.86, "brass", "D4", 100, 0.7), (0.86, "brass", "F4", 100, 0.7), (0.86, "brass", "Bb4", 100, 0.7),
          (0.86, "kit", COWBELL, 70, 0.3), (1.0, "kit", COWBELL, 60, 0.3), (1.0, "applause", "C4", 80, 1.8)]
    return mix([(0, whistle(0.55, 1750), 0.5), (0, sf(ev), 1.0), (0.9, cowbells(3, 1.2, 0.4), 0.12)])


def s_play_maker():
    "Play Maker: a short whistle, a snare roll and the trumpets' bright 'ta-daa!'."
    ev = [(0.3 + i * 0.035, "kit", SNARE, 40 + i * 4, 0.05) for i in range(10)]
    ev += [(0.66, "trumpet", "F4", 95, 0.12), (0.8, "trumpet", "Bb4", 105, 0.5), (0.8, "horn", "D4", 90, 0.5),
           (0.8, "tuba", "Bb1", 100, 0.5), (0.8, "kit", CRASH, 45, 0.6)]
    return mix([(0, whistle(0.25, 1750), 0.5), (0, sf(ev), 1.0)])


def s_star_switch():
    "Star switch: two whistle chirps, a timpani roll and the brass band swelling up to a big chord with a glockenspiel sparkle."
    ev = [(0.4 + i * 0.05, "orch", 41, 40 + i * 5, 0.06) for i in range(14)]
    for n in ("Bb2", "F3", "D4", "F4", "Bb4"):
        ev.append((1.1, "brass", n, 105, 1.0))
    ev += [(1.1, "tuba", "Bb1", 110, 1.0), (1.1, "kit", CRASH, 50, 1.0)]
    ev += [(1.1 + i * 0.07, "glock", n, 80, 0.4) for i, n in enumerate(("Bb5", "D6", "F6", "Bb6"))]
    return mix([(0, whistle(0.14, 1750), 0.45), (0.2, whistle(0.16, 1750), 0.45), (0, sf(ev), 1.0)])


def s_goal():
    "GOAL: a bass-drum hit, the full brass band's fanfare in B-flat, cow bells clanging and the beer tent cheering."
    bpm = 150
    beat = 60 / bpm
    ev = [(0, "kit", KICK, 120, 0.2), (0, "kit", CRASH, 60, 1.5), (0, "applause", "C4", 100, 3.0)]
    tune = [("F4", 0.5), ("Bb4", 0.5), ("D5", 0.5), ("F5", 0.5), ("D5", 0.5), ("F5", 2.5)]
    pos = 0
    for n, b in tune:
        ev.append((pos, "trumpet", n, 105, b * beat * 0.9))
        ev.append((pos, "horn", midi(n) - 3 if midi(n) % 12 in (5, 10) else midi(n) - 4, 90, b * beat * 0.9))
        pos += b * beat
    for i in range(6):
        ev.append((i * beat, "tuba", ("Bb1", "F2")[i % 2], 110, beat * 0.8))
        if i % 2:
            ev += [(i * beat, "accordion", n, 85, beat * 0.4) for n in ("D4", "F4", "Bb4")]
    ev += [(2.5 * beat, "brass", n, 100, 2.5 * beat) for n in ("Bb3", "D4", "F4")]
    ev += [(2.5 * beat, "kit", CRASH, 55, 1.5), (2.5 * beat, "kit", KICK, 110, 0.2)]
    ev += [(t * beat, "kit", COWBELL, 75, 0.2) for t in (2.5, 3, 3.5, 4)]
    return mix([(0, sf(ev, tail=1.8), 1.0), (2.5 * beat, cowbells(4, 1.4, 0.5), 0.12)])


def s_goal_star():
    "A STAR scores: a Böller salute, a timpani roll, the whole band and a choir on a huge B-flat chord, cow bells and the tent going wild."
    bpm = 140
    beat = 60 / bpm
    s = 0.5
    ev = [(s + i * 0.04, "orch", 41, 50 + i * 3, 0.05) for i in range(12)]
    s2 = s + 0.5
    tune = [("F4", 0.5), ("G4", 0.5), ("A4", 0.5), ("Bb4", 0.5), ("D5", 1), ("C5", 0.5), ("Bb4", 0.5), ("F5", 3.5)]
    pos = s2
    for n, b in tune:
        ev.append((pos, "trumpet", n, 108, b * beat * 0.92))
        ev.append((pos, "clarinet", midi(n) - 3 if midi(n) % 12 in (5, 10, 0) else midi(n) - 4, 85, b * beat * 0.92))
        pos += b * beat
    for i in range(8):
        ev.append((s2 + i * beat, "tuba", ("Bb1", "F2")[i % 2], 112, beat * 0.8))
        ev.append((s2 + i * beat, "kit", KICK if i % 2 == 0 else SNARE, 80 if i % 2 == 0 else 45, 0.1))
        if i % 2:
            ev += [(s2 + i * beat, "accordion", n, 85, beat * 0.4) for n in ("D4", "F4", "Bb4")]
    end = s2 + 5 * beat
    ev += [(end, "brass", n, 110, 3.5 * beat) for n in ("Bb2", "F3", "Bb3", "D4", "F4")]
    ev += [(end, "choir", n, 90, 3.5 * beat) for n in ("D4", "F4", "Bb4")]
    ev += [(end, "kit", CRASH, 65, 2.0), (end, "orch", 41, 110, 1.0), (end, "tuba", "Bb1", 115, 3.5 * beat)]
    ev += [(end + i * 0.06, "glock", n, 85, 0.5) for i, n in enumerate(("Bb5", "D6", "F6", "Bb6"))]
    ev += [(s2, "applause", "C4", 110, 4.0)]
    return mix([(0, boeller(), 0.5), (0, sf(ev, tail=2.0), 1.0), (end, cowbells(6, 1.8, 0.7), 0.14)])


def s_goal_against():
    "Conceding: the trombone's 'wah, wah, wahhh' sliding sadly down, a soft tuba under it, and the tent sighing."
    ev = [(0.0, "trombone", "F3", 85, 0.35), (0.45, "trombone", "E3", 82, 0.35), (0.9, "trombone", "Eb3", 80, 1.3, -1.0),
          (0.0, "tuba", "F2", 70, 0.35), (0.45, "tuba", "E2", 68, 0.35), (0.9, "tuba", "Eb2", 66, 1.3, -1.0)]
    return mix([(0, sf(ev, tail=1.0), 1.0), (0.05, crowd(1.8, "groan", 30), 0.2)])


def s_shot():
    "A shot: boot through leather, a punchy thump and a rush of air."
    ev = [(0, "kit", KICK, 100, 0.1), (0, "punch", "C4", 70, 0.2)]
    return mix([(0, kick(1.0), 0.8), (0, sf(ev, tail=0.3, room=0.08), 0.8), (0.02, whoosh(0.3, 400, 1600), 0.2)])


def s_save():
    "Keeper's catch: a leather slap and a low thud into the gloves."
    ev = [(0, "punch", "C4", 60, 0.15), (0, "kit", KICK, 70, 0.1)]
    return mix([(0, leather(0.05, 1.0, 400, 2200), 0.7), (0, sf(ev, tail=0.3, room=0.06), 0.9)])


def s_save_big():
    "A big save: the glove slap, a timpani thud as the keeper lands, and the tent going 'ooooh!' with a cow bell."
    ev = [(0, "punch", "C4", 80, 0.15), (0.22, "orch", 41, 100, 0.8), (0.22, "kit", KICK, 90, 0.2),
          (0.35, "kit", COWBELL, 60, 0.3)]
    return mix([(0, leather(0.06, 1.0, 400, 2400), 0.8), (0, sf(ev, tail=0.8), 1.0), (0.1, crowd(1.4, "ooh", 30), 0.3)])


def s_ability_success():
    "An ability goes off: steins clink - Prost! - a tambourine shake and the glockenspiel and accordion leaping up."
    ev = [(0.05, "kit", TAMBO, 60, 0.2)]
    ev += [(0.1 + i * 0.06, "glock", n, 90, 0.4) for i, n in enumerate(("F5", "Bb5", "D6", "F6"))]
    ev += [(0.34, "accordion", n, 90, 0.35) for n in ("D4", "F4", "Bb4")]
    return mix([(0, glass_clink(1900, 0.6), 0.35), (0.04, glass_clink(2250, 0.5), 0.25), (0, sf(ev, tail=0.8), 1.0)])


def s_ability_fail():
    "An ability fizzles: a dud cork, the foam going flat and the trombone going 'bwomp' downhill."
    ev = [(0.12, "trombone", "Bb2", 80, 0.6, -3.0)]
    return mix([(0, cork_pop(0.5), 0.25), (0.03, fizz(0.6), 0.2), (0, sf(ev, tail=0.6), 1.0)])


def s_power_victory():
    "Winning the power check: a stein slammed on the table, a bass-drum boom and the band's cheeky 'oom-PAH!' with a cow bell."
    ev = [(0.12, "tuba", "F2", 100, 0.15), (0.3, "tuba", "Bb1", 115, 0.4),
          (0.3, "brass", "D4", 105, 0.35), (0.3, "brass", "F4", 105, 0.35), (0.3, "brass", "Bb4", 105, 0.35),
          (0.3, "kit", KICK, 110, 0.2), (0.3, "kit", COWBELL, 75, 0.3), (0.3, "kit", CRASH, 40, 0.8)]
    return mix([(0, mug_on_table(), 0.6), (0, sf(ev, tail=0.9), 1.0)])


def s_power_fail():
    "Losing the power check: a dull knock on the table and the tuba drooping down two notes."
    ev = [(0.1, "tuba", "Ab2", 85, 0.3), (0.42, "tuba", "E2", 80, 0.7, -1.0), (0.42, "trombone", "E3", 60, 0.7, -1.0)]
    return mix([(0, woodblock(260, 0.15, 0.7), 0.5), (0, sf(ev, tail=0.6), 1.0)])


def s_pour():
    "Beer poured from a jug into a Maß: the stream, the glass filling up and the foam fizzing."
    ev = [(0.1, "bubbles", "C4", 50, 1.3)]
    return mix([(0, pour(1.6), 1.0), (0, sf(ev, tail=0.3, room=0), 0.25)])


def s_card_hover():
    "Pointing at a card: one soft, short tap of a wooden xylophone bar."
    return sf([(0, "marimba", "F5", 55, 0.06)], tail=0.15, room=0)


def s_card_pick():
    "Picking a card: two wood-block knocks and a dulcimer note - 'tock-tock-ding'."
    ev = [(0, "kit", HI_WOOD, 85, 0.05), (0.07, "kit", LO_WOOD, 85, 0.05), (0.07, "dulcimer", "Bb4", 70, 0.4)]
    return sf(ev, tail=0.4, room=0.08)


def s_full_time_win():
    "Full time, WON: the brass band strikes up a real polka - tuba oom-pah, accordion, trumpets and clarinet - ending on a big chord with cymbal, cow bells and the tent cheering."
    bpm = 150
    beat = 60 / bpm
    chords = [(("Bb1", "F2"), ["D4", "F4", "Bb4"]), (("F2", "C2"), ["C4", "Eb4", "A4"])]
    tune = [("F4", 0.5), ("Bb4", 0.5), ("D5", 0.5), ("F5", 0.5), ("D5", 1), ("Bb4", 1),
            ("Eb5", 0.5), ("D5", 0.5), ("C5", 0.5), ("Bb4", 0.5), ("A4", 0.5), ("C5", 0.5), ("Eb5", 1)]
    ev = polka(2, chords, tune, bpm)
    end = 8 * beat
    ev += [(end, "brass", n, 108, 3 * beat) for n in ("Bb2", "F3", "D4", "F4", "Bb4")]
    ev += [(end, "tuba", "Bb1", 115, 3 * beat), (end, "kit", CRASH, 60, 2.0), (end, "kit", KICK, 115, 0.2),
           (end, "applause", "C4", 105, 2.0)]
    ev += [(end + i * 0.06, "glock", n, 80, 0.5) for i, n in enumerate(("Bb5", "D6", "F6", "Bb6"))]
    ev += [(end + t, "kit", COWBELL, 70, 0.2) for t in (0, 0.2, 0.4)]
    return mix([(0, sf(ev, tail=2.2), 1.0), (end, cowbells(5, 1.8, 0.5), 0.12)])


def s_full_time_loss():
    "Full time, LOST: a slow, lonely trombone and tuba sinking down in a minor key over a sighing accordion, the last note sagging away."
    ev = []
    for i, (n, d) in enumerate([("Bb3", 0.7), ("A3", 0.7), ("Ab3", 0.7), ("G3", 2.2)]):
        t = i * 0.75
        last = i == 3
        ev.append((t, "trombone", n, 78, d, -1.0 if last else 0))
        ev.append((t, "tuba", midi(n) - 24, 70, d, -1.0 if last else 0))
    ev += [(0, "accordion", n, 50, 1.5) for n in ("Eb4", "Gb4", "Bb4")]
    ev += [(1.5, "accordion", n, 45, 2.3) for n in ("C4", "Eb4", "G4")]
    ev += [(2.25, "kit", KICK, 40, 0.2)]
    return sf(ev, tail=1.5)


def s_full_time_draw():
    "Full time, DRAWN: the band starts a polka and stops halfway on an unfinished chord, then one shrugging 'tock' on a wood block."
    bpm = 150
    beat = 60 / bpm
    chords = [(("Bb1", "F2"), ["D4", "F4", "Bb4"]), (("F2", "C2"), ["C4", "Eb4", "A4"])]
    tune = [("F4", 1), ("Bb4", 0.5), ("D5", 0.5), ("F5", 1), ("D5", 1), ("Eb5", 0.5), ("D5", 0.5), ("C5", 1), (None, 2)]
    ev = polka(2, chords, tune, bpm)
    end = 8 * beat
    ev += [(end, "tuba", "F2", 95, 0.6), (end, "accordion", "C4", 70, 1.0), (end, "accordion", "Eb4", 70, 1.0),
           (end, "accordion", "A4", 70, 1.0), (end + 1.0, "kit", HI_WOOD, 80, 0.1)]
    return sf(ev, tail=1.0)


def s_foul():
    "A foul: one short, round whistle blast and a snare tap."
    return mix([(0, whistle(0.35, 1750), 0.55), (0.3, sf([(0, "kit", SNARE, 40, 0.1)], tail=0.3, room=0.05), 0.5)])


def s_yellow():
    "A booking: the whistle, the tent going 'oooh' and the low brass muttering 'uh-oh'."
    ev = [(0.35, "trombone", "D3", 80, 0.25), (0.62, "trombone", "Bb2", 80, 0.6, -0.5), (0.35, "tuba", "D2", 75, 0.25),
          (0.62, "tuba", "Bb1", 75, 0.6, -0.5)]
    return mix([(0, whistle(0.3, 1750), 0.45), (0.25, crowd(1.3, "ooh", 25), 0.25), (0, sf(ev, tail=0.6), 1.0)])


def s_red():
    "A sending-off: a long whistle, a timpani crash and a dark brass chord, and the beer tent booing."
    ev = [(0.6, "orch", 41, 115, 1.0), (0.6, "kit", CRASH, 55, 1.5)]
    ev += [(0.6, "brass", n, 100, 1.4) for n in ("G2", "Db3", "G3", "Bb3")]
    ev += [(0.6, "tuba", "G1", 110, 1.4)]
    return mix([(0, whistle(0.6, 1750), 0.45), (0, sf(ev, tail=1.0), 1.0), (0.7, crowd(1.8, "boo", 35), 0.3)])


def s_ball_tap():
    "A player taking the ball: the tiniest scuff of boot on leather."
    return mix([(0, leather(0.025, 1.0, 300, 1600), 0.6), (0, sf([(0, "kit", KICK, 45, 0.03)], tail=0.06, room=0), 0.8)])


def s_ball_kick():
    "A player striking the ball on the run: short, dry and leathery, with a bit of thump."
    return mix([(0, kick(0.8), 0.8), (0, sf([(0, "kit", KICK, 80, 0.05)], tail=0.15, room=0), 0.7)])


def s_hit_soft():
    "An ordinary hit: a knock on a wooden beer bench. Short and plain - you hear it a lot."
    return mix([(0, sf([(0, "kit", LO_WOOD, 90, 0.05)], tail=0.1, room=0), 1.0), (0, thump(140, 0.07, 0.5, 0.3), 0.4)])


def s_hit_heavy():
    "A big hit: a punch, a concert bass drum and a full Maßkrug slammed down."
    ev = [(0, "punch", "C4", 90, 0.2), (0, "bassdrum", "C3", 90, 0.4)]
    return mix([(0, sf(ev, tail=0.3, room=0.05), 1.0), (0, glass_clink(700, 0.2, 0.3), 0.2), (0.02, slosh(0.2), 0.2)])


def s_enemy_down():
    "An enemy finished off: a xylophone tumbling down the scale and a bass-drum thud on the floorboards."
    ev = [(i * 0.07, "xylo", n, 90, 0.1) for i, n in enumerate(("F5", "D5", "Bb4", "F4"))]
    ev += [(0.3, "bassdrum", "C3", 100, 0.5), (0.3, "kit", CRASH, 25, 0.5)]
    return sf(ev, tail=0.6)


def s_player_hurt():
    "One of yours hurt: a muffled punch and a short, sour trombone bend."
    ev = [(0, "punch", "C4", 60, 0.15), (0.03, "trombone", "E3", 70, 0.25, -1.5)]
    return sf(ev, tail=0.3, room=0.08)


def s_player_drop():
    "One of yours exhausted: a body on the grass, a bass drum and a tired tuba sighing down."
    ev = [(0, "bassdrum", "C3", 95, 0.4), (0.12, "tuba", "C2", 80, 0.3), (0.45, "tuba", "A1", 75, 0.9, -1.0)]
    return mix([(0, thump(65, 0.4, 1.0, 0.4), 0.6), (0, sf(ev, tail=0.6), 1.0)])


def s_item_use():
    "An item mends somebody: a quick glug of beer, a gulp and a warm dulcimer flourish."
    ev = [(0.4 + i * 0.07, "dulcimer", n, 80, 0.5) for i, n in enumerate(("F4", "Bb4", "D5"))]
    return mix([(0, pour(0.45, 0.8), 0.5), (0.35, gulp(), 0.5), (0, sf(ev, tail=0.8), 1.0)])


def s_combo():
    "A combo comes off: a cow bell and a glockenspiel 'ding-ding!'."
    ev = [(0, "kit", COWBELL, 80, 0.2), (0.03, "glock", "Bb5", 80, 0.4), (0.1, "glock", "D6", 85, 0.5)]
    return lowpass(sf(ev, tail=0.6, room=0.12), 4500)


def s_shot_heavy():
    "The big Adventure shot: the hardest boot in the game, a timpani and bass-drum boom, a rush of air and a distant Böller."
    ev = [(0, "kit", KICK, 120, 0.2), (0, "orch", 41, 110, 0.8), (0, "punch", "C4", 90, 0.2), (0.05, "kit", CRASH, 40, 1.0)]
    return mix([(0, kick(1.0, heavy=True), 0.7), (0, sf(ev, tail=0.8), 1.0), (0.02, whoosh(0.4, 300, 1800), 0.25),
                (0.1, boeller(), 0.25)])


def s_enemy_windup():
    "An enemy powering up: a cuckoo clock ticking - tick, tock, tick, tock - on wood blocks."
    ev = [(i * 0.22, "kit", HI_WOOD if i % 2 == 0 else LO_WOOD, 75, 0.05) for i in range(4)]
    return sf(ev, tail=0.2, room=0.05)


def s_crowd_goal():
    "The beer tent going up for a goal: real applause and cheering, cow bells clanging."
    ev = [(0, "applause", "C4", 110, 2.4), (0.1, "kit", COWBELL, 70, 0.2), (0.35, "kit", COWBELL, 60, 0.2)]
    return mix([(0, sf(ev, tail=1.0), 1.0), (0, crowd(2.4, "cheer", 30), 0.15), (0.2, cowbells(4, 1.6, 0.8), 0.1)])


def s_menu_hover():
    "Pointing at a menu button: the lightest pluck of a dulcimer string."
    return sf([(0, "dulcimer", "Bb5", 50, 0.08)], tail=0.2, room=0)


def s_menu_click():
    "Pressing a menu button: a knock on a wooden plank."
    return sf([(0, "kit", HI_WOOD, 90, 0.05)], tail=0.12, room=0)


def s_menu_start():
    "START: the band's 'oom-PAH!' with a bass drum, a cymbal and a cow bell - off we go."
    ev = [(0, "tuba", "F2", 100, 0.15), (0.18, "tuba", "Bb1", 115, 0.5), (0.18, "kit", KICK, 110, 0.2),
          (0.18, "kit", CRASH, 45, 1.0), (0.18, "kit", COWBELL, 75, 0.3)]
    ev += [(0.18, "brass", n, 105, 0.45) for n in ("D4", "F4", "Bb4")]
    return sf(ev, tail=1.0)


def s_menu_back():
    "Back / Quit: two wood-block knocks, high then low."
    return sf([(0, "kit", HI_WOOD, 80, 0.05), (0.09, "kit", LO_WOOD, 80, 0.05)], tail=0.15, room=0)


def s_coin():
    "Paying: coins dropping into a stoneware mug and a little shop bell."
    return mix([(0, lowpass(coins(6), 4000), 0.4), (0.25, sf([(0, "tubular", "F5", 60, 0.8)], tail=0.8), 0.6)])


def s_boeller():
    "A Böller salute from across the valley - the festival's black-powder boom, echoing off the hills."
    return mix([(0, boeller(), 0.8), (0, sf([(0, "explosion", "C3", 70, 0.6)], tail=1.0), 0.3)])


def s_banner():
    "A banner snapping in a gust of wind, and birds in the trees."
    ev = [(0, "wind", "C4", 60, 0.9), (0.2, "birds", "C4", 50, 0.8)]
    return mix([(0, flutter(0.7), 0.5), (0, lowpass(sf(ev, tail=0.5, room=0), 5000), 0.5)])


def s_bld_brewery():
    "The Brewery: the copper kettle bubbling, running water and a clink of glass."
    d = 1.6
    t = t_axis(d)
    boil = bubbles(d, 70, 120, 450) + 0.4 * lowpass(noise(d), 300)
    ev = [(0, "bubbles", "C3", 70, 1.5), (0, "stream", "C4", 50, 1.5)]
    return mix([(0, boil * np.sin(np.pi * t / d), 0.5), (0, sf(ev, tail=0.4, room=0), 0.6), (0.9, glass_clink(1100, 0.3), 0.12)])


def s_bld_pub():
    "The Pub: an accordion playing in the corner, people laughing and chatting, steins clinking."
    bpm = 150
    beat = 60 / bpm
    ev = []
    tune = [("F5", 0.5), ("E5", 0.5), ("F5", 0.5), ("A5", 0.5), ("C6", 1), ("A5", 1), ("Bb5", 0.5), ("G5", 0.5), ("E5", 1)]
    pos = 0
    for n, b in tune:
        ev.append((pos, "accordion", n, 80, b * beat * 0.9))
        pos += b * beat
    for i in range(4):
        ev.append((i * beat, "accordion", ("F3", "C4")[i % 2] if i % 2 == 0 else "A3", 65, beat * 0.4))
    ev += [(0.5, "laughing", "C4", 45, 0.8)]
    return mix([(0, sf(ev, tail=0.6), 1.0), (0, crowd(2.0, "murmur", 20), 0.25),
                (0.6, glass_clink(1900, 0.5), 0.2), (0.64, glass_clink(2200, 0.5), 0.15)])


def s_bld_club_house():
    "The Club House: a door swinging open, boots on floorboards and the coach's whistle."
    ev = [(0, "door", "C4", 70, 0.6), (0.5, "footsteps", "C4", 70, 0.8)]
    return mix([(0, sf(ev, tail=0.4), 1.0), (1.2, whistle(0.25, 1800), 0.35)])


def s_bld_dorms():
    "The Dorms: someone snoring in a creaky wooden bunk."
    return mix([(0, snore(), 0.6), (1.0, sf([(0, "creak", "C4", 50, 0.5)], tail=0.3, room=0), 0.3)])


def s_bld_training():
    "The Training Ground: a ball thumped against a wooden board, birds in the trees and the coach's whistle."
    ev = [(0.18, "kit", LO_WOOD, 100, 0.1), (0.5, "birds", "C4", 45, 0.8)]
    return mix([(0, kick(0.8), 0.6), (0, sf(ev, tail=0.4, room=0.05), 1.0), (1.1, whistle(0.25, 1800), 0.35)])


def s_bld_trophy():
    "The Trophy Room: a church bell ringing, a glockenspiel sparkle and a short choir 'aah'."
    ev = [(0, "church", "Bb3", 70, 1.2)]
    ev += [(0.15 + i * 0.08, "glock", n, 75, 0.4) for i, n in enumerate(("Bb5", "D6", "F6"))]
    ev += [(0.2, "choir", n, 60, 1.0) for n in ("Bb3", "D4", "F4")]
    return sf(ev, tail=1.2)


def s_bld_tavern():
    "The Traveling Tavern: a horse trotting up, the wagon creaking, a squeeze of accordion and a stein on the counter."
    ev = [(0, "horse", "C4", 70, 1.0), (0.8, "creak", "C4", 55, 0.5),
          (1.1, "accordion", "F4", 70, 0.3), (1.1, "accordion", "A4", 70, 0.3), (1.1, "accordion", "C5", 70, 0.3)]
    return mix([(0, sf(ev, tail=0.5), 1.0), (1.4, mug_on_table(), 0.35)])


def s_door():
    "An old wooden door creaking open."
    return lowpass(sf([(0, "creak", "C4", 60, 0.6), (0.55, "door", "C4", 45, 0.3)], tail=0.4, room=0.05), 4000)


def s_visitor_brewer():
    "The Brewer: a gruff 'Hm-HO!' answered by the tuba, and his stein on the bar."
    v = voice([("m", 105, 0.18, 0.1), ("o", 125, 0.3, 0.15)])
    ev = [(0.05, "tuba", "Bb1", 85, 0.15), (0.22, "tuba", "F2", 95, 0.3)]
    return mix([(0, v, 0.35), (0, sf(ev, tail=0.5), 0.8), (0.55, mug_on_table(), 0.3)])


def s_visitor_heatwave():
    "Heatwave: a cocky 'HAH!', a brass stab and a crackle of fire."
    v = voice([("h", 170, 0.06, 0.9), ("a", 175, 0.25, 0.2)])
    ev = [(0.05, "brass", n, 100, 0.25) for n in ("E3", "Bb3", "E4")]
    return mix([(0, crackle(1.0), 0.35), (0.05, v, 0.35), (0, sf(ev, tail=0.6), 0.8)])


def s_wagon():
    "The Tavern wagon's hatch: old timber creaking open."
    return mix([(0, sf([(0, "creak", "C3", 60, 0.8)], tail=0.3, room=0.05), 1.0), (0.85, thump(120, 0.12, 0.6), 0.25)])


def s_drink():
    "A big drink: beer glugging out of a barrel, three gulps and the foam bubbling."
    return mix([(0, pour(0.7, 0.7), 0.4), (0.5, gulp(), 0.6), (0.72, gulp(), 0.55), (0.94, gulp(), 0.5),
                (0.9, sf([(0, "bubbles", "C4", 50, 0.6)], tail=0.2, room=0), 0.3)])


def s_birds():
    "The woods: birds singing in the trees."
    return lowpass(sf([(0, "birds", "C4", 60, 2.0), (0.8, "bird2", "C4", 50, 1.2)], tail=0.4, room=0), 4500)


def s_moo():
    "The Alm: a cow mooing, her bell clanking, and a cow-bell answer from further up the hill."
    return mix([(0, moo(), 0.6), (0.2, cowbell(560, 1.2), 0.15), (0.9, cowbell(700, 1.0), 0.1)])


SOUNDS = {
    "bav_kickoff": s_kickoff, "bav_play_maker": s_play_maker, "bav_star_switch": s_star_switch,
    "bav_goal": s_goal, "bav_goal_star": s_goal_star, "bav_goal_against": s_goal_against,
    "bav_shot": s_shot, "bav_save": s_save, "bav_save_big": s_save_big,
    "bav_ability_success": s_ability_success, "bav_ability_fail": s_ability_fail,
    "bav_power_victory": s_power_victory, "bav_power_fail": s_power_fail,
    "bav_pour": s_pour, "bav_card_hover": s_card_hover, "bav_card_pick": s_card_pick,
    "bav_full_time_win": s_full_time_win, "bav_full_time_loss": s_full_time_loss, "bav_full_time_draw": s_full_time_draw,
    "bav_foul": s_foul, "bav_yellow": s_yellow, "bav_red": s_red,
    "bav_ball_tap": s_ball_tap, "bav_ball_kick": s_ball_kick, "bav_hit_soft": s_hit_soft, "bav_hit_heavy": s_hit_heavy,
    "bav_enemy_down": s_enemy_down, "bav_player_hurt": s_player_hurt, "bav_player_drop": s_player_drop,
    "bav_item_use": s_item_use, "bav_combo": s_combo, "bav_shot_heavy": s_shot_heavy,
    "bav_enemy_windup": s_enemy_windup, "bav_crowd_goal": s_crowd_goal,
    "bav_menu_hover": s_menu_hover, "bav_menu_click": s_menu_click, "bav_menu_start": s_menu_start, "bav_menu_back": s_menu_back,
    "bav_coin": s_coin, "bav_boeller": s_boeller, "bav_banner": s_banner,
    "bav_bld_brewery": s_bld_brewery, "bav_bld_pub": s_bld_pub, "bav_bld_club_house": s_bld_club_house,
    "bav_bld_dorms": s_bld_dorms, "bav_bld_training": s_bld_training, "bav_bld_trophy": s_bld_trophy,
    "bav_bld_tavern": s_bld_tavern, "bav_door": s_door, "bav_visitor_brewer": s_visitor_brewer,
    "bav_visitor_heatwave": s_visitor_heatwave, "bav_wagon": s_wagon,
    "bav_drink": s_drink, "bav_birds": s_birds, "bav_moo": s_moo,
}


# =============================================================
#  FINISHING: same loudness, no clipping, nothing shrill
# =============================================================

TARGET_RMS_DB = -20.0   # loudness of the loud part of every sound
CEILING_DB = -1.0       # nothing ever goes above this


def finish(x):
    x = np.asarray(x, dtype=float)
    x = highpass(x, 60)          # no sub-rumble to eat the speakers
    x = lowpass(x, 7500)         # nothing shrill
    x = x - np.mean(x)
    # loudness of the loudest 50 ms windows, not the whole file - so a
    # short knock and a long tune end up feeling equally loud
    # Measured above 200 Hz - what a Steam Deck's speakers can actually
    # play - so a tuba is not turned down for bass nobody hears.
    heard = highpass(x, 200)
    win = int(0.05 * SR)
    frames = [np.sqrt(np.mean(heard[i:i + win] ** 2)) for i in range(0, max(1, len(x) - win), win // 2)]
    loud = np.mean(sorted(frames)[-max(1, len(frames) // 5):]) + 1e-12
    x *= 10 ** (TARGET_RMS_DB / 20) / loud
    # soft limiter: gentle above the ceiling, never a hard clip
    ceiling = 10 ** (CEILING_DB / 20)
    # turned down rather than squashed when it would go far over
    x *= min(1.0, ceiling * 1.1 / (np.max(np.abs(x)) + 1e-12))
    x = ceiling * np.tanh(x / ceiling)
    # trim trailing silence, then fade out
    keep = np.nonzero(np.abs(x) > 10 ** (-48 / 20))[0]
    if len(keep):
        x = x[: keep[-1] + int(0.02 * SR)]
    return fade(x, 0.003, min(0.25, len(x) / SR * 0.1))


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, name + ".wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        ogg_path = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "6", ogg_path], check=True)
    peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    print(f"  {name:24s} {len(x) / SR:5.2f} s  peak {peak:5.1f} dBFS")


CREDITS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "SoundCredits.csv")


def write_credits():
    """data/SoundCredits.csv: every effect, what you hear, which Audio.csv
    rows play it, and where it came from. Rewritten on every full run."""
    import csv
    audio = os.path.join(os.path.dirname(CREDITS), "Audio.csv")
    users = {}
    with open(audio, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            users.setdefault(row["Sound"].strip(), []).append(row["ID"])
    with open(CREDITS, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["File", "Folder", "What you hear", "Audio.csv rows", "Source", "Licence"])
        for name, fn in SOUNDS.items():
            w.writerow([name + ".ogg", "assets/audio/", fn.__doc__.strip(), "; ".join(users.get(name, [])) or "spare",
                        "Synthesized from scratch by tools/make_bavarian_sfx.py (Round AN, 8 Oct 2026). No recordings or samples.",
                        "Our own - no attribution needed"])


# The longest each may ring, in seconds: sounds that play often or under
# a click must stop quickly, whatever the instrument's own ring-out.
MAX_SECONDS = {
    "bav_card_hover": 0.2, "bav_card_pick": 0.35, "bav_menu_hover": 0.25, "bav_menu_click": 0.15,
    "bav_menu_back": 0.25, "bav_ball_tap": 0.1, "bav_ball_kick": 0.2, "bav_hit_soft": 0.12,
    "bav_hit_heavy": 0.5, "bav_player_hurt": 0.5, "bav_combo": 0.7, "bav_enemy_windup": 0.9,
    "bav_shot": 0.5, "bav_save": 0.4, "bav_enemy_down": 1.0, "bav_play_maker": 1.6, "bav_menu_start": 1.3,
    "bav_ability_success": 1.1, "bav_ability_fail": 1.0, "bav_power_victory": 1.3, "bav_power_fail": 1.3,
    "bav_coin": 1.0, "bav_door": 1.0, "bav_wagon": 1.0, "bav_foul": 0.45, "bav_player_drop": 1.4,
    "bav_item_use": 1.4, "bav_save_big": 1.3, "bav_shot_heavy": 1.5,
}


def cap(name, x):
    limit = MAX_SECONDS.get(name)
    if not limit or len(x) <= limit * SR:
        return x
    x = x[: int(limit * SR)].copy()
    n = int(len(x) * 0.3)
    x[-n:] *= np.linspace(1, 0, n) ** 2
    return x


def main(argv):
    wanted = argv or list(SOUNDS)
    global rng
    for name in wanted:
        if name not in SOUNDS:
            sys.exit(f"No sound called {name}. Known: {', '.join(SOUNDS)}")
        # each sound has its own dice, so remaking one never changes another
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        write(name, cap(name, finish(SOUNDS[name]())))
    if not argv:
        write_credits()


if __name__ == "__main__":
    main(sys.argv[1:])
