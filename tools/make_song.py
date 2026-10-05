#!/usr/bin/env python3
# =============================================================
#  MUSIC FROM A SPREADSHEET - NO AI  (round AL)
#
#      python3 tools/make_song.py                   every song in data/Songs.csv
#      python3 tools/make_song.py menu_blasmusik    just that one
#
#  The tune is written note by note in a CSV, and real recorded brass
#  instruments (a free SoundFont) play it. Nothing is made up by an AI,
#  so nothing creeps in as the song goes on: it plays exactly what's written.
#
#  ============ THREE SPREADSHEETS ============
#
#  data/Songs.csv       one row per song: its score, where the .ogg goes,
#                       Tempo, Soundfont, Reverb (0-1), Loudness (dB),
#                       Humanize (ms the players may drift, 0 = robot)
#
#  data/SongParts.csv   who plays. One row per player:
#      Plays       melody  - the tune
#                  thirds  - the tune a third lower (the Bavarian sound)
#                  bass    - the chord's root, then its fifth, on the Beats
#                  chords  - the chord, short, on the Beats (the "pah")
#                  drum    - one drum on the Beats
#      Instrument  General MIDI number: 56 trumpet, 57 trombone, 58 tuba,
#                  60 French horns, 61 brass section, 71 clarinet, 21 accordion.
#                  For drums: 36 bass drum, 38 snare, 42 hi-hat, 49/57 crash.
#      Bank        0 normally; 1 = the soundfont's alternative of that instrument
#      Volume      0-127 (0 = off)       Pan  -100 left ... 100 right
#      Octave      move the part up (+1) or down (-1) an octave
#      Beats       when bass/chords/drums play: "1 3", "2 4", "1& 3&" ...
#      Length      how long a bass/chord note lasts, in eighth-notes
#
#  data/songs/<song>.csv   the score, one bar a row:
#      Chord       Bb, F7, Eb, Cm, Gm7 ... (drives the bass and the chords)
#      Melody      8 eighth-notes: D5 Eb5 F#4 ... , - holds, R rests
#
#  The last bar should lead back into the first: the song is made as a
#  perfect loop (the echo of the end is folded onto the start).
#
#  Needs: pip install tinysoundfont numpy soundfile, and ffmpeg.
# =============================================================

import csv
import os
import random
import subprocess
import sys
import tempfile

import numpy as np
import soundfile as sf
import tinysoundfont

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 44100
PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
MAJOR = [0, 2, 4, 5, 7, 9, 11]


def read(path):
    with open(os.path.join(HERE, path), encoding="utf-8") as f:
        return [r for r in csv.DictReader(f)]


def pitch_class(name):
    pc = PC[name[0].upper()]
    for ch in name[1:]:
        pc += 1 if ch == "#" else -1 if ch == "b" else 0
    return pc % 12


def note(tok):
    """'Bb4' -> 70.  Middle C is C4 = 60."""
    i = len(tok) - 1
    while i > 0 and (tok[i].isdigit() or tok[i] == "-"):
        i -= 1
    return 12 * (int(tok[i + 1:]) + 1) + pitch_class(tok[:i + 1])


def chord_tones(ch):
    """'F7' -> (root pc, [pcs])"""
    i = 1 + (1 if len(ch) > 1 and ch[1] in "#b" else 0)
    root, q = pitch_class(ch[:i]), ch[i:]
    third = 3 if q.startswith("m") and not q.startswith("maj") else 4
    tones = [0, third, 7] + ([10] if "7" in q and "maj" not in q else []) + ([11] if "maj7" in q else [])
    return root, [(root + t) % 12 for t in tones]


def in_range(pc, lo, hi):
    n = lo + ((pc - lo) % 12)
    return n if n <= hi else n - 12


def third_below(n, key_pc, chord_pcs):
    scale = [(key_pc + s) % 12 for s in MAJOR]
    if n % 12 in scale:
        i = scale.index(n % 12)
        down = (scale[i] - scale[(i - 2) % 7]) % 12
        return n - down
    for d in (3, 4, 5):
        if (n - d) % 12 in chord_pcs:
            return n - d
    return n - 3


def beats(text):
    """'1 3' -> eighth positions [0, 4];  '2&' -> 3"""
    out = []
    for b in (text or "").split():
        e = (int(b.rstrip("&")) - 1) * 2 + (1 if b.endswith("&") else 0)
        out.append(e)
    return out


def make(song):
    sid = song["Song"].strip()
    score = read(song["Score"].strip())
    parts = [p for p in read("data/SongParts.csv") if p["Song"].strip() == sid and int(float(p.get("Volume") or 0)) > 0]
    tempo = float(song.get("Tempo") or 116)
    eighth = 60.0 / tempo / 2
    bar_len = eighth * 8
    human = float(song.get("Humanize") or 0) / 1000.0
    rng = random.Random(7)
    key_pc = chord_tones(score[0]["Chord"].strip())[0]

    synth = tinysoundfont.Synth(samplerate=SR)
    sfid = synth.sfload(os.path.join(HERE, song["Soundfont"].strip()))
    events = []  # (time, order, kind, chan, key, vel)

    def add(t, dur, chan, key, vel):
        jitter = max(-human, min(human, rng.gauss(0, human / 2))) if human else 0.0
        t = max(0.0, t + jitter)
        vel = int(max(1, min(127, vel + rng.randint(-6, 6))))
        events.append((t, 1, "on", chan, key, vel))
        events.append((t + dur, 0, "off", chan, key, 0))

    chan = 0
    for p in parts:
        plays = p["Plays"].strip()
        prog = int(float(p["Instrument"]))
        octv = int(float(p.get("Octave") or 0)) * 12
        vol = int(float(p["Volume"]))
        pan = int(64 + float(p.get("Pan") or 0) * 0.63)
        if plays == "drum":
            c = 9
            synth.program_select(c, sfid, 128, 0, True)
        else:
            c = chan if chan != 9 else 10
            chan = c + 1
            synth.program_select(c, sfid, int(float(p.get("Bank") or 0)), prog)
            synth.control_change(c, 7, max(0, min(127, vol)))
            synth.control_change(c, 10, max(0, min(127, pan)))
        length = float(p.get("Length") or 1) * eighth
        for bi, bar in enumerate(score):
            t0 = bi * bar_len
            root, pcs = chord_tones(bar["Chord"].strip())
            if plays in ("melody", "thirds"):
                toks = bar["Melody"].split()
                for i, tok in enumerate(toks):
                    if tok in ("-", "R"):
                        continue
                    n = 1
                    while i + n < len(toks) and toks[i + n] == "-":
                        n += 1
                    k = note(tok)
                    if plays == "thirds":
                        k = third_below(k, key_pc, pcs)
                    accent = 10 if i % 4 == 0 else (0 if i % 2 == 0 else -8)
                    add(t0 + i * eighth, n * eighth * 0.9, c, k + octv, 92 + accent)
            elif plays == "bass":
                for j, e in enumerate(beats(p["Beats"])):
                    r = in_range(root, 38, 49)
                    k = r if j % 2 == 0 else (r - 5 if r - 5 >= 29 else r + 7)
                    add(t0 + e * eighth, length, c, k + octv, 100)
            elif plays == "chords":
                for e in beats(p["Beats"]):
                    for pc in pcs[:4]:
                        add(t0 + e * eighth, length, c, in_range(pc, 55, 66) + octv, 78)
            elif plays == "drum":
                for e in beats(p["Beats"]):
                    add(t0 + e * eighth, eighth, 9, prog, int(vol))

    events.sort(key=lambda x: (x[0], x[1]))
    loop_len = int(round(len(score) * bar_len * SR))
    total = loop_len + int(3.0 * SR)
    out = np.zeros((total, 2), dtype=np.float32)
    pos = 0
    for t, _, kind, c, k, v in events + [(total / SR, 0, "end", 0, 0, 0)]:
        at = min(total, int(t * SR))
        if at > pos:
            buf = np.frombuffer(synth.generate(at - pos), dtype=np.float32).reshape(-1, 2)
            out[pos:at] = buf
            pos = at
        if kind == "on":
            synth.noteon(c, k, v)
        elif kind == "off":
            synth.noteoff(c, k)

    # Fold the ring-out after the last bar onto the start: a perfect loop.
    loop = out[:loop_len].copy()
    tail = out[loop_len:]
    loop[:len(tail)] += tail[:loop_len]

    # Beer-tent room: a short, soft echo tail, applied round the loop.
    wet = float(song.get("Reverb") or 0)
    if wet > 0:
        n = int(1.3 * SR)
        r = np.random.default_rng(3)
        env = np.exp(-np.arange(n) / (0.32 * SR))
        ir = np.stack([r.standard_normal(n) * env, r.standard_normal(n) * env], 1)
        ir[: int(0.012 * SR)] = 0
        ir /= np.sqrt((ir ** 2).sum(0))
        f = np.fft.rfft(loop, axis=0) * np.fft.rfft(np.vstack([ir, np.zeros((loop_len - n, 2))]), axis=0)
        loop = (1 - wet) * loop + wet * np.fft.irfft(f, n=loop_len, axis=0).astype(np.float32)

    target = float(song.get("Loudness") or -16)
    rms = float(np.sqrt(np.mean(loop ** 2))) or 1e-9
    loop *= min(10 ** (target / 20) / rms, 0.92 / float(np.max(np.abs(loop))))

    dst = os.path.join(HERE, song["Output"].strip())
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "song.wav")
        sf.write(wav, loop, SR)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", dst], check=True)
    print("  %s -> %s (%d bars, %.1f s, %d parts)" % (sid, song["Output"].strip(), len(score), loop_len / SR, len(parts)))


def main():
    only = sys.argv[1:]
    for song in read("data/Songs.csv"):
        if song.get("Song", "").strip() and (not only or song["Song"].strip() in only):
            make(song)


if __name__ == "__main__":
    main()
