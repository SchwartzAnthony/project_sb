#!/usr/bin/env python3
# =============================================================
#  CROWD CHEERS OVER A SONG  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/mix_cheers.py            every song
#      ~/.venvs/sturmball/bin/python tools/mix_cheers.py suno_menu  just that song
#
#  Lays crowd cheers over a song at the moments you choose, so the cheering
#  is clear and never stuck to the beat. The song itself is not touched.
#
#  data/MusicCheers.csv - one row per cheer:
#    Song    the MusicLoops.csv row (its Source is the song)
#    Cheer   the cheer file (art_source/suno/cheers/...)
#    At      seconds into the song where the cheer starts
#    Volume  dB: 0 = as loud as the file, -6 = half as loud
#    Pan     -1 left, 0 middle, 1 right
#
#  Writes <song>_cheers.wav next to the song. Point the song's Source in
#  MusicLoops.csv at that file (suno_menu already is), then run
#  tools/make_loop.py for that row. To go back: Source = the plain song.
# =============================================================

import csv
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000


def read(path):
    """Any audio file as float stereo at SR (via ffmpeg)."""
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le",
                          "-ac", "2", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def write(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def plain_source(song_id):
    """The song as Suno made it: MusicLoops Source, minus any _cheers suffix."""
    with open(os.path.join(HERE, "data", "MusicLoops.csv"), newline="") as f:
        for row in csv.DictReader(f):
            if row["ID"] == song_id:
                return row["Source"].replace("_cheers.wav", ".wav")
    sys.exit(f"{song_id} is not in MusicLoops.csv")


def main():
    only = sys.argv[1:]
    songs = {}
    with open(os.path.join(HERE, "data", "MusicCheers.csv"), newline="") as f:
        for row in csv.DictReader(f):
            if not only or row["Song"] in only:
                songs.setdefault(row["Song"], []).append(row)
    for song_id, rows in songs.items():
        src = plain_source(song_id)
        mix = read(os.path.join(HERE, src))
        for r in rows:
            c = read(os.path.join(HERE, r["Cheer"]))
            n = len(c)
            env = np.ones(n)
            fi, fo = min(n // 4, int(0.08 * SR)), min(n // 2, int(0.6 * SR))
            env[:fi] = np.linspace(0, 1, fi)
            env[n - fo:] = np.linspace(1, 0, fo)
            pan = float(r["Pan"] or 0)
            gain = 10 ** (float(r["Volume"] or 0) / 20)
            lr = np.array([min(1, 1 - pan), min(1, 1 + pan)])
            at = int(float(r["At"]) * SR)
            end = min(len(mix), at + n)
            mix[at:end] += (c[:end - at] * env[:end - at, None]) * gain * lr
        peak = np.abs(mix).max()
        if peak > 0.98:  # never clip: soften the whole mix just enough
            mix *= 0.98 / peak
        out = src.replace(".wav", "_cheers.wav")
        write(os.path.join(HERE, out), mix)
        print(f"{song_id}: {len(rows)} cheers -> {out}" + (f" (lowered {20*np.log10(peak/0.98):.1f} dB to avoid clipping)" if peak > 0.98 else ""))


if __name__ == "__main__":
    main()
