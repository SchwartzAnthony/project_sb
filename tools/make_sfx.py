#!/usr/bin/env python3
# =============================================================
#  SOUND EFFECTS FROM A SPREADSHEET  (round AI, with pyfxr)
#
#      pip install pyfxr          (once)
#      python3 tools/make_sfx.py  (every time you change the sheet)
#
#  Every row of data/SoundRecipes.csv becomes assets/audio/<Name>.wav.
#  Audio.csv then plays it by that Name, like any other sound.
#
#  The columns are the classic "sfxr" dials, all 0 to 1 unless it says so:
#
#    Wave         square, saw, sine or noise (noise = explosions, hits)
#    Base Freq    how high it starts                 0.05 deep ... 0.8 shrill
#    Freq Ramp    -1..1: it slides down (-) or up (+)
#    Duty         square only: 0.5 hollow, 0.1 thin and buzzy
#    Attack       how long it takes to get loud      (0 = at once)
#    Sustain      how long it stays loud
#    Punch        a kick at the start
#    Decay        how long it takes to fade
#    Arp Mod      -1..1: jumps to a second note (coins, power-ups)
#    Arp Speed    how soon that jump comes
#    LPF Freq     1 = bright; lower = muffled (bass)
#    LPF Ramp     -1..1: it gets duller (-) or brighter (+)
#    HPF Freq     0 = full; higher = thinner (clicks)
#    Phaser Offset / Phaser Ramp   a sweeping "whoosh"
#    Repeat Speed 0 = once; higher = it restarts (stutters)
#
#  Lengths come out squared, as in sfxr: Sustain 0.3 is about 0.1 s.
#  Change a number, run this again, listen in Godot.
# =============================================================

import csv
import os
import sys

try:
    from pyfxr import SFX, WaveType
except ImportError:
    sys.exit("pyfxr is not installed. Run:  pip install pyfxr")

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(HERE, "data", "SoundRecipes.csv")
OUT = os.path.join(HERE, "assets", "audio")

WAVES = {"square": WaveType.SQUARE, "saw": WaveType.SAW, "sine": WaveType.SINE, "noise": WaveType.NOISE}
DIALS = {"Base Freq": "base_freq", "Freq Ramp": "freq_ramp", "Duty": "duty", "Attack": "env_attack",
         "Sustain": "env_sustain", "Punch": "env_punch", "Decay": "env_decay", "Arp Mod": "arp_mod",
         "Arp Speed": "arp_speed", "LPF Freq": "lpf_freq", "LPF Ramp": "lpf_ramp", "HPF Freq": "hpf_freq",
         "Phaser Offset": "pha_offset", "Phaser Ramp": "pha_ramp", "Repeat Speed": "repeat_speed"}


def main():
    only = sys.argv[1:]
    made = 0
    with open(SHEET, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            name = (row.get("Name") or "").strip()
            if not name or (only and name not in only):
                continue
            wave = (row.get("Wave") or "square").strip().lower()
            if wave not in WAVES:
                print("  ! %s: Wave '%s' is not square, saw, sine or noise - skipping" % (name, wave))
                continue
            dials = {"wave_type": WAVES[wave]}
            for column, key in DIALS.items():
                text = (row.get(column) or "").strip()
                if text == "":
                    continue
                try:
                    dials[key] = float(text)
                except ValueError:
                    print("  ! %s: %s '%s' is not a number - ignoring it" % (name, column, text))
            path = os.path.join(OUT, name + ".wav")
            SFX(**dials).build().save(path)
            made += 1
            print("  wrote assets/audio/%s.wav" % name)
    print("%d sound(s) made from data/SoundRecipes.csv" % made)


if __name__ == "__main__":
    main()
