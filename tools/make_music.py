#!/usr/bin/env python3
"""Make the placeholder music: streamed OGG sounds, normalised and looped.

Both tracks are free placeholders from OpenTracks (formerly DOVA-SYNDROME),
standing in until the commissioned music exists. OpenTracks' licence forbids
redistributing the audio files, and this repository is public, so neither
the downloads in `tools/source/music/` nor the OGGs this writes are committed
(see `.gitignore`). On a fresh clone, download each track from its page in
`TRACKS` into `tools/source/music/` under the name given there, and run this.

Every track is written at the same loudness (`LOUDNESS`), so `MUSIC_MASTER`
in `constants` sets them all. How a track loops:

- "whole": the file is already a loop. Its last few milliseconds are faded,
  which softens the click at the wrap.
- "twice": the file plays its body twice, then fades out. The period is
  found by comparing the spectrum with itself at every lag. One period is cut
  starting at the second pass (so it opens with the second pass's inherited
  reverb, as the loop will), and the seam is crossfaded into what precedes
  that start, because the two passes are not sample-identical.

    python tools/make_music.py
"""
import os
import sys

import numpy as np
import soundfile as sf
from scipy import signal
from scipy.ndimage import maximum_filter1d, uniform_filter1d

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gm_new
from make_sfx import K_WEIGHTING

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "tools", "source", "music")
FOLDER = "Sounds/music"

# K-weighted RMS over the whole track (see `make_sfx.loudness`).
LOUDNESS = 0.20
PEAK = 0.95

# name, source file, where it came from, how it loops
TRACKS = (
    ("snd_music_sanctum", "mystery_of_egypt.mp3",
     "Mystery of Egypt, by Yuli (Yuli Audio Craft): "
     "https://opentracks.com/en/bgm/detail/6483", "whole"),
    ("snd_music_mika", "tsuyoi_mono_tono_tatakai.mp3",
     "強い者との戦い, by こっけ: https://opentracks.com/en/bgm/detail/8392",
     "twice"),
)


def k_rms(x):
    """K-weighted RMS of a whole (stereo) track."""
    (b1, a1), (b2, a2) = K_WEIGHTING
    y = signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=0), axis=0)
    return float(np.sqrt(np.mean(y ** 2)))


def limit(x, ceiling, sr, release=0.08, look=0.002):
    """A stereo peak limiter: one gain for both channels, riding down ahead
    of anything over `ceiling` and recovering over `release` seconds."""
    L = max(1, int(look * sr))
    need = maximum_filter1d(np.maximum(1.0, np.abs(x).max(1) / ceiling), 2 * L + 1)
    k = np.exp(-1.0 / (release * sr))
    r = need.tolist()
    prev = 1.0
    for i in range(len(r)):
        v = r[i]
        prev = v if v > prev else 1.0 + (prev - 1.0) * k
        r[i] = prev
    return x / uniform_filter1d(np.array(r), L)[:, None]


def spectral_period(m, sr, lo, hi):
    """The lag, in samples, at which the track best matches itself, searched
    between `lo` and `hi` seconds. Compared on log band energies every 10ms
    over a long stretch early in the track."""
    hop, win = sr // 100, 2048
    frames = np.lib.stride_tricks.sliding_window_view(m, win)[::hop] * np.hanning(win)
    spec = np.abs(np.fft.rfft(frames, axis=1))
    f = np.fft.rfftfreq(win, 1.0 / sr)
    edges = np.geomspace(60, 12000, 49)
    feat = np.log(np.stack([spec[:, (f >= a) & (f < b)].sum(1)
                            for a, b in zip(edges[:-1], edges[1:])], 1) + 1e-6)
    feat -= feat.mean(1, keepdims=True)
    feat /= np.linalg.norm(feat, axis=1, keepdims=True) + 1e-9
    fps = sr / hop
    a, n = int(10 * fps), int(30 * fps)

    def sim(lag):
        return float(np.mean(np.sum(feat[a:a + n] * feat[a + lag:a + lag + n], 1)))

    lags = range(int(lo * fps), min(int(hi * fps), len(feat) - a - n))
    best = max(lags, key=sim)
    return best * hop


def loop_twice(x, sr, xfade=0.10):
    """One period of a track that plays its body twice, cut from the start
    of the second pass, with the seam crossfaded (equal power, since the
    passes differ sample by sample)."""
    m = x.mean(1)
    dur = len(m) / sr
    D = spectral_period(m, sr, 0.3 * dur, 0.6 * dur)
    # Align the seam to the sample: what precedes the second pass against
    # what precedes the end of the cut.
    W = sr // 2
    ref = m[D - W:D]
    reach = sr // 50
    c = np.correlate(m[2 * D - W - reach:2 * D + reach], ref, mode="valid")
    D = D + int(np.argmax(c)) - reach
    X = int(xfade * sr)
    out = x[D:2 * D].copy()
    th = np.linspace(0.0, np.pi / 2, X)[:, None]
    out[-X:] = out[-X:] * np.cos(th) + x[D - X:D] * np.sin(th)
    return out, D


def main():
    os.makedirs(os.path.join(ROOT, "sounds"), exist_ok=True)
    gm_new.folder("Sounds")
    gm_new.folder(FOLDER)
    tmp = os.path.join(ROOT, "tools", "_preview")
    os.makedirs(tmp, exist_ok=True)
    missing = []
    for name, src, where, how in TRACKS:
        path = os.path.join(SOURCE, src)
        if not os.path.exists(path):
            missing.append((src, where))
            continue
        x, sr = sf.read(path, always_2d=True)
        note = ""
        if how == "twice":
            x, period = loop_twice(x, sr)
            note = "  period %.3fs" % (period / sr)
        else:
            k = int(0.008 * sr)
            x[-k:] *= np.linspace(1.0, 0.0, k)[:, None]
        x = x * (LOUDNESS / k_rms(x))
        if np.abs(x).max() > PEAK:
            x = limit(x, PEAK, sr)
        x = np.clip(x, -PEAK, PEAK)
        ogg = os.path.join(tmp, name + ".ogg")
        # In blocks: libsndfile's Vorbis encoder overflows the stack when
        # handed a whole track in one write.
        with sf.SoundFile(ogg, "w", sr, x.shape[1], format="OGG",
                          subtype="VORBIS") as fh:
            for i in range(0, len(x), 8192):
                fh.write(x[i:i + 8192])
        gm_new.music(name, ogg, len(x) / sr, channels=x.shape[1], rate=sr,
                     folder=FOLDER)
        print("  %-18s %6.1fs  loudness %.3f  peak %.2f%s"
              % (name, len(x) / sr, k_rms(x), np.abs(x).max(), note))
    for src, where in missing:
        print("  missing tools/source/music/%s -- download %s" % (src, where))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main() or 0)
