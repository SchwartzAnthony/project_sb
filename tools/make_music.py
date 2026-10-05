#!/usr/bin/env python3
# =============================================================
#  THE MAIN MENU TUNE  (round AI) - an Oktoberfest oom-pah polka,
#  played on 1990s chiptune instruments
#
#      python3 tools/make_music.py
#
#  Writes assets/audio/menu_oktoberfest.ogg (needs ffmpeg on the PATH; if
#  ffmpeg is missing it writes a .wav instead). Audio.csv's menu_theme row
#  plays it on the main menu and loops it.
#
#  ============ CHANGING THE TUNE - NO CODE NEEDED ============
#
#  Everything you would want to change is in the block below:
#
#    TEMPO       beats per minute. A polka is 2 beats a bar.
#    CHORDS      one chord per bar: F, C, Bb, G7 ... (see CHORD_NOTES)
#    MELODY      one bar per line, four eighth-notes a bar:
#                  C5 = the C above middle C,  Bb4, F#5 ...
#                  -  = hold the note before    R = rest
#    VOLUMES     how loud each instrument is (0 = off)
#
#  The tune is 32 bars - about 30 seconds - and its end leads back into
#  its start, so the loop has no seam.
# =============================================================

import os
import shutil
import subprocess
import wave

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "assets", "audio", "menu_oktoberfest")

RATE = 44100
TEMPO = 132

VOLUMES = {"tuba": 0.55, "pah": 0.22, "melody": 0.30, "harmony": 0.12, "kick": 0.45, "snare": 0.18, "clap": 0.12}

A = ["F", "C", "C", "F", "F", "Bb", "C", "F"]
B = ["Bb", "F", "C", "F", "Bb", "F", "C", "F"]
CHORDS = A + A + B + A

MELODY_A1 = """
C5 A4 C5 F5
E5 D5 C5 Bb4
G4 Bb4 C5 E5
F5 - A4 -
C5 A4 C5 F5
D5 F5 D5 Bb4
G4 C5 E5 G5
F5 - - R
"""
MELODY_A2 = """
C5 A4 C5 F5
E5 D5 C5 Bb4
G4 Bb4 C5 E5
F5 - A5 -
C6 A5 F5 C5
D5 F5 D5 Bb4
G5 F5 E5 D5
C5 - - R
"""
MELODY_B = """
D5 F5 Bb5 F5
C5 F5 A5 F5
E5 G5 C6 G5
A5 - F5 -
D5 F5 Bb5 F5
C5 F5 A5 F5
G5 F5 E5 D5
C5 - - R
"""
MELODY = MELODY_A1 + MELODY_A2 + MELODY_B + MELODY_A1

CHORD_NOTES = {
    "F": ["F", "A", "C"], "C": ["C", "E", "G"], "Bb": ["Bb", "D", "F"],
    "G7": ["G", "B", "F"], "C7": ["C", "E", "Bb"], "Dm": ["D", "F", "A"],
}

# ---------------------------------------------------------------

NAMES = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
         "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(note):
    name, octave = note[:-1], int(note[-1])
    midi = 12 * (octave + 1) + NAMES[name]
    return 440.0 * 2 ** ((midi - 69) / 12)


BEAT = 60.0 / TEMPO
EIGHTH = BEAT / 2
BAR = BEAT * 2
LENGTH = int(round(len(CHORDS) * BAR * RATE))
mix = {k: np.zeros(LENGTH) for k in VOLUMES}


def t_of(n):
    return np.arange(n) / RATE


def pulse(f, n, duty=0.5):
    ph = (t_of(n) * f) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def tri(f, n):
    ph = (t_of(n) * f) % 1.0
    return 4 * np.abs(ph - 0.5) - 1


def env(n, attack=0.005, release=0.04):
    e = np.ones(n)
    a, r = int(attack * RATE), int(release * RATE)
    if a > 0:
        e[:a] = np.linspace(0, 1, a)
    if r > 0 and r < n:
        e[-r:] = np.linspace(1, 0, r)
    return e


def put(track, start_s, sound):
    i = int(start_s * RATE)
    j = min(LENGTH, i + len(sound))
    if i < LENGTH:
        mix[track][i:j] += sound[: j - i]


rng = np.random.default_rng(7)

for bar, chord in enumerate(CHORDS):
    t0 = bar * BAR
    root = CHORD_NOTES[chord][0]
    fifth = CHORD_NOTES[chord][2]
    # OOM: the tuba on each beat - root, then the fifth below.
    for beat, note in enumerate([root + "2", fifth + "2"]):
        n = int(EIGHTH * 1.6 * RATE)
        f = hz(note)
        s = 0.7 * tri(f, n) + 0.3 * pulse(f, n, 0.5) * 0.5
        put("tuba", t0 + beat * BEAT, s * env(n, 0.004, 0.06) * np.exp(-t_of(n) * 3))
        # kick on the beat
        k = int(0.12 * RATE)
        kf = 120 * np.exp(-t_of(k) * 30) + 45
        put("kick", t0 + beat * BEAT, np.sin(2 * np.pi * np.cumsum(kf) / RATE) * np.exp(-t_of(k) * 22))
    # PAH: the chord stabbed on each off-beat, plus a snare.
    for beat in range(2):
        n = int(EIGHTH * 0.55 * RATE)
        s = sum(pulse(hz(x + "4"), n, 0.25) for x in CHORD_NOTES[chord]) / 3
        put("pah", t0 + beat * BEAT + EIGHTH, s * env(n, 0.003, 0.03))
        m = int(0.09 * RATE)
        put("snare", t0 + beat * BEAT + EIGHTH, rng.uniform(-1, 1, m) * np.exp(-t_of(m) * 35))
    # a clap on the second beat of every other bar - the crowd joining in
    if bar % 2 == 1:
        m = int(0.07 * RATE)
        put("clap", t0 + BEAT, rng.uniform(-1, 1, m) * np.exp(-t_of(m) * 25))

# MELODY - an accordion-ish pulse with a little vibrato, and a quiet third
# above it as the second voice.
steps = MELODY.split()
held = []
for i, s in enumerate(steps):
    if s == "-":
        continue
    length = 1
    while i + length < len(steps) and steps[i + length] == "-":
        length += 1
    held.append((i, s, length))
for i, s, length in held:
    if s == "R":
        continue
    n = int(length * EIGHTH * RATE * 0.92)
    f = hz(s)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t_of(n))
    ph = np.cumsum(f * vib) / RATE % 1.0
    tone = np.where(ph < 0.3, 1.0, -1.0) * 0.6 + np.where(((ph * 2) % 1.0) < 0.5, 1.0, -1.0) * 0.4
    put("melody", i * EIGHTH, tone * env(n, 0.006, 0.05))
    ph2 = np.cumsum(f * 2 ** (4 / 12) * vib) / RATE % 1.0
    put("harmony", i * EIGHTH, np.where(ph2 < 0.5, 1.0, -1.0) * env(n, 0.01, 0.05))

out = sum(VOLUMES[k] * mix[k] for k in mix)
out = out / max(1e-9, np.max(np.abs(out))) * 0.89
pcm = (out * 32767).astype(np.int16)

wav_path = OUT + ".wav"
with wave.open(wav_path, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(pcm.tobytes())

if shutil.which("ffmpeg"):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "5", OUT + ".ogg"], check=True)
    os.remove(wav_path)
    print("wrote %s.ogg (%.1f s, %d bars at %d bpm)" % (os.path.relpath(OUT, HERE), LENGTH / RATE, len(CHORDS), TEMPO))
else:
    print("wrote %s.wav (no ffmpeg found for .ogg)" % os.path.relpath(OUT, HERE))
