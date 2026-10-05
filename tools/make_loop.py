#!/usr/bin/env python3
# =============================================================
#  SEAMLESS MUSIC LOOPS  (round AL)
#
#      python3 tools/make_loop.py                  every row of data/MusicLoops.csv
#      python3 tools/make_loop.py menu_blasmusik   just that row
#
#  AI music (Ludo.ai) comes as a short track with a start and an end that
#  don't join. This script finds the two moments in the track that sound the
#  most alike, cuts between them, and blends the join, so the game can play
#  it round and round with no bump.
#
#  ============ data/MusicLoops.csv - one row per track ============
#
#    ID          a name for the row
#    Source      the track as it came (art_source/ludo/music/...)
#    Output      the looping .ogg the game plays (assets/audio/...)
#    Start       seconds into the track where the loop starts. Blank = find it.
#    Length      how many seconds the loop lasts. Blank = find it.
#    Min Length  when finding: the shortest loop allowed (seconds)
#    Max Length  when finding: the longest loop allowed (seconds)
#    Bars        round AL: loop exactly this many bars (4 beats each) - the
#                beat never stumbles at the join. 8 or 16 is usual. Blank =
#                the old way (any length between Min and Max Length).
#    Search From / Search To   round AL: only look for the loop between
#                these seconds of the track (e.g. the part you like best).
#                Blank = the whole track.
#    Crossfade   seconds the end is blended into the start (0.2-1 is good)
#    Loudness    average loudness in dB (-16 is a sensible music level;
#                the volume in Audio.csv is applied on top of this)
#    Notes       anything
#
#  Needs: pip install librosa soundfile   and ffmpeg.
# =============================================================

import csv
import os
import subprocess
import sys
import tempfile

import numpy as np
import librosa
import soundfile as sf

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(HERE, "data", "MusicLoops.csv")
SR = 44100


def num(row, key, default=None):
    v = (row.get(key) or "").strip()
    return float(v) if v else default


def find_loop(mono, min_len, max_len, match=1.5):
    """The (start, length) whose first `match` seconds sound most like the
    `match` seconds right after the end."""
    hop = 256
    mel = librosa.power_to_db(librosa.feature.melspectrogram(y=mono, sr=SR, hop_length=hop, n_mels=48))
    mel -= mel.mean(1, keepdims=True)
    fps = SR / hop
    w = int(match * fps)
    n = mel.shape[1]
    best = (1e18, 0, 0)
    for lag in range(int(min_len * fps), int(max_len * fps) + 1):
        top = min(int(3 * fps), n - w - lag)
        for a in range(0, max(0, top), 2):
            d = float(np.mean((mel[:, a:a + w] - mel[:, a + lag:a + lag + w]) ** 2))
            if d < best[0]:
                best = (d, a, lag)
    # Fine-tune to the sample with the raw waveform, +-10 ms.
    a = best[1] * hop
    b = a + best[2] * hop
    seg = mono[a:a + 4096]
    span = 441
    scores = [float(np.dot(seg, mono[b + k:b + k + 4096])) if b + k + 4096 <= len(mono) and b + k >= 0 else -1e18
              for k in range(-span, span + 1)]
    b += int(np.argmax(scores)) - span
    return a / SR, (b - a) / SR, best[0]


def find_loop_bars(mono, bars, t_from=None, t_to=None, match=1.5):
    """Start on a beat, last exactly `bars` bars; pick the start whose join
    sounds most alike (the moments before AND after the join are compared)."""
    tempo, beats = librosa.beat.beat_track(y=mono, sr=SR, units="samples")
    hop = 256
    mel = librosa.power_to_db(librosa.feature.melspectrogram(y=mono, sr=SR, hop_length=hop, n_mels=48))
    mel -= mel.mean(1, keepdims=True)
    w = int(match * SR / hop)
    pre = int(0.5 * SR / hop)
    n = mel.shape[1]
    lo = (t_from or 0.0) * SR
    hi = (t_to * SR) if t_to else len(mono)
    best = (1e18, 0, 0)
    step = bars * 4
    for i in range(len(beats) - step):
        a, b = int(beats[i]), int(beats[i + step])
        if a < lo or b > hi:
            continue
        fa, fb = a // hop, b // hop
        if fb + w >= n or fa - pre < 0:
            continue
        d = float(np.mean((mel[:, fa:fa + w] - mel[:, fb:fb + w]) ** 2))
        d += 0.5 * float(np.mean((mel[:, fa - pre:fa] - mel[:, fb - pre:fb]) ** 2))
        if d < best[0]:
            best = (d, a, b)
    if best[0] >= 1e18:
        raise SystemExit("  ! no %d-bar loop fits between those seconds - make the search wider or Bars smaller" % bars)
    _, a, b = best
    seg = mono[a:a + 4096]
    span = 441
    scores = [float(np.dot(seg, mono[b + k:b + k + 4096])) if b + k + 4096 <= len(mono) and b + k >= 0 else -1e18
              for k in range(-span, span + 1)]
    b += int(np.argmax(scores)) - span
    return a / SR, (b - a) / SR, best[0], float(np.atleast_1d(tempo)[0])


def make(row):
    src = os.path.join(HERE, row["Source"].strip())
    dst = os.path.join(HERE, row["Output"].strip())
    if not os.path.isfile(src):
        print("  ! %s: no track at %s" % (row["ID"], row["Source"]))
        return
    y, _ = librosa.load(src, sr=SR, mono=False)
    if y.ndim == 1:
        y = np.stack([y, y])
    mono = y.mean(0)
    start, length = num(row, "Start"), num(row, "Length")
    xf = num(row, "Crossfade", 0.4)
    bars = num(row, "Bars")
    if (start is None or length is None) and bars:
        s, l, score, bpm = find_loop_bars(mono, int(bars), num(row, "Search From"), num(row, "Search To"))
        start = s if start is None else start
        length = l if length is None else length
        print("  %s: %d bars at %.0f BPM - loop from %.3f s, %.3f s long (match %.0f; lower is better)" % (row["ID"], int(bars), bpm, start, length, score))
    if start is None or length is None:
        s, l, score = find_loop(mono, num(row, "Min Length", 20), num(row, "Max Length", 30))
        start = s if start is None else start
        length = l if length is None else length
        print("  %s: found a loop from %.3f s, %.3f s long (match %.0f; lower is better)" % (row["ID"], start, length, score))
    a, b, x = int(start * SR), int((start + length) * SR), int(xf * SR)
    if b + x > y.shape[1]:
        x = max(0, y.shape[1] - b)
    loop = y[:, a:b].copy()
    if x > 0:
        ramp = np.linspace(0.0, 1.0, x)
        # Equal-power blend: the tail after the loop end fades out over the start.
        loop[:, :x] = loop[:, :x] * np.sin(ramp * np.pi / 2) + y[:, b:b + x] * np.cos(ramp * np.pi / 2)
    # Loudness: scale the average (RMS) to the Loudness row, never clip.
    target = num(row, "Loudness", -16.0)
    rms = float(np.sqrt(np.mean(loop ** 2))) or 1e-9
    gain = min(10 ** (target / 20) / rms, 0.92 / float(np.max(np.abs(loop))))
    loop *= gain
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "loop.wav")
        sf.write(wav, loop.T, SR)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", dst], check=True)
    print("  %s -> %s (%.2f s)" % (row["Source"], row["Output"], loop.shape[1] / SR))


def main():
    only = sys.argv[1:]
    with open(SHEET, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("ID", "").strip() and (not only or row["ID"].strip() in only):
                make(row)


if __name__ == "__main__":
    main()
