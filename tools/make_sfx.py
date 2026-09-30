#!/usr/bin/env python3
"""Synthesise every sound effect in the game and register them.

Every cue is synthesised here. A replacement should be a mono 16-bit WAV at
`sounds/<name>/<name>.wav`, with the duration in its `.yy` updated, and its
gain in `audio_functions` set so it lands at the loudness `CUES` gives it.

What the cues are made of:

- noise through moving filters, for air, fire, sand and impacts (`svf`,
  `crack`, `crackle`);
- sines whose pitch drops, for weight (`thump`);
- a soft struck chime, for the few musical cues (`chime`);
- a formant "choir" of detuned saws (`choir`);
- inharmonic metal with a soft front: a gong, and a hoop for Mika's rings
  (`metal`);
- a Freeverb-style room on the larger cues (`reverb`).

The frequent cues (shots, hits, grazes, the player's fireball) are short and
dry. Each cue is normalised to twice its loudness in the mix (see `main`),
measured K-weighted as in ITU-R BS.1770, and `main` prints the gain that
brings it down to that loudness. Its noise is seeded from its name, so
re-running writes identical WAVs. `main` exits non-zero if a cue doesn't
decay (`check_envelopes`) or would need a gain above 1.

    python tools/make_sfx.py            # write every sound + the preview
    python tools/make_sfx.py --preview  # only the preview, touch no resource
"""
import argparse
import hashlib
import math
import os
import sys

import numpy as np
from scipy import signal
from scipy.ndimage import maximum_filter1d, uniform_filter1d

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gm_new

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREVIEW = os.path.join(ROOT, "tools", "_preview")
os.makedirs(PREVIEW, exist_ok=True)  # git-ignored, so a fresh clone lacks it

RATE = 44100
FOLDER = "Sounds"

# Peak ceiling, leaving headroom for up to `SFX_VOICES` cues on one frame.
PEAK_CEILING = 0.92

# At most this much peak limiting (2 = 6 dB) when a cue is normalised; past
# it the cue is left quieter and its gain makes up the difference.
LIMIT_MAX = 2.0

# `BOSS_CHARGE_LEAD` in `constants`, in seconds: the charge cue peaks just
# before it runs out. Change the two together.
CHARGE_S = 1.2


# ---------------------------------------------------------------------------
# Time, envelopes and pitch curves
# ---------------------------------------------------------------------------

def n_of(seconds):
    return max(1, int(round(seconds * RATE)))


def rng_for(name):
    """A generator seeded off a cue's name, so a cue is the same every run."""
    h = hashlib.sha256(name.encode("utf-8")).digest()
    return np.random.default_rng(int.from_bytes(h[:8], "little"))


def t_of(n):
    """Seconds, as an array, for `n` samples."""
    return np.arange(n, dtype=np.float64) / RATE


def env_exp(n, attack, tau):
    """A smooth rise over `attack` seconds, then an exponential fall with
    time constant `tau` seconds."""
    t = t_of(n)
    e = np.exp(-np.maximum(0.0, t - attack) / max(1e-5, tau))
    if attack > 0:
        e *= np.sin(0.5 * np.pi * np.clip(t / attack, 0.0, 1.0)) ** 2
    return e


def env_rise(n, peak, fall, curve=2.0):
    """A swell: rise to 1 at `peak` seconds (steeper toward the top as
    `curve` grows), then fall to 0 over `fall` seconds."""
    t = t_of(n)
    up = np.clip(t / max(1e-5, peak), 0.0, 1.0) ** curve
    down = np.clip((t - peak) / max(1e-5, fall), 0.0, 1.0)
    return up * 0.5 * (1.0 + np.cos(np.pi * down))


def env_pluck(n, decay=1.0, curve=5.0):
    """Instant attack, exponential fall across the whole cue. Used by the
    graze, which keeps the old shot's recipe."""
    tail = np.linspace(0.0, 1.0, n)
    return np.exp(-curve * tail / max(1e-6, decay))


def glide(f0, f1, n, span=None, shape=1.0):
    """Per-sample values sliding exponentially from `f0` to `f1` over `span`
    seconds (the whole cue by default), then holding `f1`."""
    s = span if span is not None else n / RATE
    u = np.clip(t_of(n) / max(1e-5, s), 0.0, 1.0) ** shape
    return f0 * (f1 / f0) ** u


def settle(f0, f1, n, tau):
    """Per-sample values starting at `f0` and settling onto `f1` with time
    constant `tau`: a drum's pitch drop."""
    return f1 + (f0 - f1) * np.exp(-t_of(n) / tau)


def trem(n, rate, depth):
    """Amplitude flutter at `rate` Hz (per-sample allowed), dipping by
    `depth`."""
    ph = np.cumsum(np.broadcast_to(np.asarray(rate, float), (n,))) / RATE
    return 1.0 - depth * (0.5 + 0.5 * np.sin(2 * np.pi * ph))


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

def white(n, gen):
    return gen.standard_normal(n)


def _shaped(n, gen, power):
    w = np.fft.rfft(gen.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    x = np.fft.irfft(w / np.maximum(f, 20.0) ** power, n)
    return x / (np.std(x) + 1e-12)


def pink(n, gen):
    """Noise falling 3 dB an octave: air, flame."""
    return _shaped(n, gen, 0.5)


def brown(n, gen):
    """Noise falling 6 dB an octave: rumble."""
    return _shaped(n, gen, 1.0)


def osc_sine(f, n, ph0=0.0):
    """A sine at `f` Hz (per-sample allowed)."""
    ph = np.cumsum(np.broadcast_to(np.asarray(f, float), (n,))) / RATE
    return np.sin(2 * np.pi * (ph + ph0))


def osc_saw(f, n, gen=None):
    """A band-limited (polyBLEP) sawtooth at `f` Hz (per-sample allowed),
    from a random phase if `gen` is given."""
    dt = np.broadcast_to(np.asarray(f, float), (n,)) / RATE
    p = (np.cumsum(dt) + (gen.random() if gen is not None else 0.0)) % 1.0
    y = 2.0 * p - 1.0
    lo = p < dt
    u = p[lo] / dt[lo]
    y[lo] -= u + u - u * u - 1.0
    hi = p > 1.0 - dt
    u = (p[hi] - 1.0) / dt[hi]
    y[hi] -= u * u + u + u + 1.0
    return y


def thump(n, f0, f1, tau_f, tau_a, attack=0.0015):
    """Weight: a sine dropping from `f0` to settle on `f1`, decaying with
    `tau_a`."""
    return osc_sine(settle(f0, f1, n, tau_f), n) * env_exp(n, attack, tau_a)


def crack(n, gen, f0, f1, tau):
    """The front of an impact: white noise through a low-pass closing from
    `f0` to `f1`, gone within a few `tau`."""
    return svf(white(n, gen), settle(f0, f1, n, tau * 1.5), 0.7) \
        * env_exp(n, 0.0005, tau)


def crackle(n, gen, rate, lo=1500.0, hi=7000.0):
    """Sparse clicks, `rate` a second (per-sample allowed), each a
    sub-millisecond burst of uneven strength, kept between `lo` and `hi` Hz:
    fire, grit, shattering."""
    dens = np.broadcast_to(np.asarray(rate, float), (n,)) / RATE
    idx = np.nonzero(gen.random(n) < dens)[0]
    imp = np.zeros(n)
    imp[idx] = np.minimum(gen.pareto(2.5, idx.size) + 0.25, 5.0) \
        * gen.choice((-1.0, 1.0), idx.size)
    k = n_of(0.0007)
    kern = gen.standard_normal(k) * np.exp(-np.linspace(0.0, 5.0, k))
    return lp(hp(np.convolve(imp, kern)[:n], lo), hi)


def chime(f, n, gen, bright=0.5, sustain=0.9):
    """A soft struck chime: a sine frequency-modulated at 1:1, its index
    falling away within tens of milliseconds so the front has a gentle
    overtone edge and the body is round, with a faint bell shimmer (3.5:1)
    that fades faster still. Two copies a few cents apart beat slowly.
    `bright` (0..1) scales the overtones; `sustain` is the seconds to fall
    60 dB."""
    t = t_of(n)
    out = np.zeros(n)
    for cents in (-3.0, 3.0):
        fc = f * 2.0 ** (cents / 1200.0)
        p0, p1 = gen.uniform(0.0, 2 * np.pi, 2)
        idx = (0.3 + 2.2 * bright) * np.exp(-t / 0.06) + 0.12
        body = np.sin(2 * np.pi * fc * t + p0
                      + idx * np.sin(2 * np.pi * fc * t + p1))
        sidx = 0.8 * bright * np.exp(-t / 0.03)
        shimmer = np.sin(2 * np.pi * 2 * fc * t
                         + sidx * np.sin(2 * np.pi * 3.5 * fc * t))             * np.exp(-t / (0.25 * sustain))
        out += body + shimmer * 0.2 * bright
    return 0.5 * out * env_exp(n, 0.004 + 0.006 * (1.0 - bright), sustain / 6.9)


def arpeggio(freqs, step, n, gen, bright, sustain, fall=0.9, start=0.0):
    """Chimes in turn, `step` seconds apart, each `fall` times the last."""
    out = np.zeros(n)
    for i, f in enumerate(freqs):
        d = start + i * step
        k = n - n_of(d)
        out += at(unit(chime(f, k, gen, bright, sustain)) * fall ** i, d, n)
    return out


def glitter(n, gen, notes, rate, start, span):
    """Twinkles: tiny soft chimes on `notes`, `rate` a second, scattered from
    `start` over the next `span` seconds."""
    out = np.zeros(n)
    m = n_of(0.35)
    for _ in range(int(rate * span)):
        d = start + gen.random() * span
        f = notes[int(gen.integers(len(notes)))]
        out += at(chime(f, m, gen, 0.3, 0.35) * gen.uniform(0.4, 1.0), d, n)
    return out


# Formants (centre Hz, level, bandwidth Hz) of sung vowels, lower voice.
VOWELS = {
    "a": ((730.0, 1.00, 90.0), (1090.0, 0.50, 110.0), (2440.0, 0.22, 160.0)),
    "o": ((570.0, 1.00, 80.0), (840.0, 0.45, 100.0), (2410.0, 0.12, 160.0)),
}


def choir(freqs, n, gen, vowel="a", bend=1.0, voices=3, cents=10.0):
    """A sung chord: each note is `voices` detuned saws with their own slow
    vibrato, and the sum is shaped by a vowel's formants. `bend` multiplies
    every pitch (per-sample allowed)."""
    t = t_of(n)
    src = np.zeros(n)
    for f in freqs:
        for v in range(voices):
            det = 2.0 ** (((v - (voices - 1) / 2.0) * cents
                           + gen.uniform(-2.0, 2.0)) / 1200.0)
            wob = 1.0 + 0.005 * np.sin(2 * np.pi * gen.uniform(4.4, 6.0) * t
                                       + gen.uniform(0.0, 2 * np.pi))
            src += osc_saw(f * det * bend * wob, n, gen)
    out = lp(src, 300.0) * 0.15
    for fc, amp, bw in VOWELS[vowel]:
        out += bp(src, fc, fc / bw) * amp
    return out


# Partial ratios for `metal`.
GONG = (1.0, 1.47, 1.98, 2.44, 3.03, 3.71)
GONG_AMPS = (1.0, 0.7, 0.5, 0.35, 0.25, 0.15)
# The in-plane modes of a free hoop: Mika's rings.
HOOP = (1.0, 2.83, 5.42, 8.77)


def metal(f, n, gen, ratios, amps, taus, attack=0.002, beat=0.6):
    """Struck metal: partials on `ratios` over `f`, each with its own decay,
    each split into two copies `beat` Hz apart that beat against each other
    (a real hoop or gong is never perfectly round)."""
    t = t_of(n)
    out = np.zeros(n)
    for r, a, tau in zip(ratios, amps, taus):
        fr = f * r
        if fr > RATE * 0.45:
            continue
        split = beat * gen.uniform(0.5, 1.5)
        p0, p1 = gen.uniform(0.0, 2 * np.pi, 2)
        tone = np.sin(2 * np.pi * (fr - split / 2) * t + p0) \
            + np.sin(2 * np.pi * (fr + split / 2) * t + p1)
        out += a * 0.5 * tone * env_exp(n, attack, tau)
    return out


# ---------------------------------------------------------------------------
# Filters
# ---------------------------------------------------------------------------

def _rbj(kind, f, q):
    w = 2 * math.pi * max(20.0, min(f, RATE * 0.45)) / RATE
    cw, sw = math.cos(w), math.sin(w)
    alpha = sw / (2 * max(0.05, q))
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:                                       # band-pass, constant peak
        b0, b1, b2 = alpha, 0.0, -alpha
    a0 = 1 + alpha
    return (b0 / a0, b1 / a0, b2 / a0,
            (-2 * cw) / a0, (1 - alpha) / a0)


def _static(kind, x, f, q):
    b0, b1, b2, a1, a2 = _rbj(kind, f, q)
    return signal.lfilter([b0, b1, b2], [1.0, a1, a2], x)


def lp(x, f, q=0.707):
    return _static("lp", x, f, q)


def hp(x, f, q=0.707):
    return _static("hp", x, f, q)


def bp(x, f, q=2.0):
    return _static("bp", x, f, q)


def svf(x, f, q=0.707, mode="lp"):
    """A state-variable filter (Zavalishin's TPT form) whose cutoff `f` and
    resonance `q` may change every sample, which a biquad can't do without
    zipper noise or blowing up. `mode` is "lp", "bp" (unity at the centre)
    or "hp"."""
    n = x.shape[0]
    f = np.clip(np.broadcast_to(np.asarray(f, float), (n,)), 20.0, RATE * 0.45)
    k = 1.0 / np.maximum(0.05, np.broadcast_to(np.asarray(q, float), (n,)))
    g = np.tan(np.pi * f / RATE)
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs, A1, A2, A3 = x.tolist(), a1.tolist(), a2.tolist(), a3.tolist()
    low = [0.0] * n
    band = [0.0] * n
    ic1 = ic2 = 0.0
    for i in range(n):
        v3 = xs[i] - ic2
        v1 = A1[i] * ic1 + A2[i] * v3
        v2 = ic2 + A2[i] * ic1 + A3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        low[i] = v2
        band[i] = v1
    low, band = np.array(low), np.array(band)
    if mode == "bp":
        return band * k
    if mode == "hp":
        return x - k * band - low
    return low


def moving_lowpass(x, f0, f1, q=0.9):
    """A lowpass whose corner slides from `f0` to `f1` across the sound, the
    coefficients recomputed every 64 samples. Kept for the graze."""
    n = x.shape[0]
    y = np.empty(n)
    x1 = x2 = y1 = y2 = 0.0
    block = 64
    for start in range(0, n, block):
        frac = start / max(1, n - 1)
        f = f0 * (max(1e-6, f1) / max(1e-6, f0)) ** frac
        b0, b1, b2, a1, a2 = _rbj("lp", f, q)
        for i in range(start, min(start + block, n)):
            xi = x[i]
            yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            y[i] = yi
            x2, x1 = x1, xi
            y2, y1 = y1, yi
    return y


# ---------------------------------------------------------------------------
# The room
# ---------------------------------------------------------------------------

# Freeverb's delay lengths, in samples at 44.1 kHz.
COMBS = (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617)
ALLPASSES = (556, 441, 341, 225)


def _comb(x, D, fb, d):
    """Freeverb's comb: a delay of `D` fed back through a one-pole low-pass
    (`d`), so the highs die first. Run a period at a time, since each period
    only reads the one before."""
    n = x.shape[0]
    b = np.zeros(n + D)                # b[i + D] is the loop at time i
    s_prev = 0.0
    for k in range(0, n, D):
        m = min(D, n - k)
        s, _ = signal.lfilter([1.0 - d], [1.0, -d], b[k:k + m],
                              zi=[d * s_prev])
        s_prev = s[-1]
        b[k + D:k + D + m] = x[k:k + m] + fb * s
    return b[:n]


def _allpass(x, D, g=0.5):
    n = x.shape[0]
    b = np.zeros(n + D)
    for k in range(0, n, D):
        m = min(D, n - k)
        b[k + D:k + D + m] = x[k:k + m] + g * b[k:k + m]
    return b[:n] - x


def reverb(x, wet, room=0.7, damp=0.5, tail=0.8, predelay=0.012, lo_cut=160.0):
    """A mono Freeverb, returned with `tail` seconds added. `wet` is the
    room's level against the dry sound (Freeverb's wet parameter), `room`
    its size, `damp` how fast its highs fade. The room is fed without the
    lows below `lo_cut`, which would only muddy it."""
    n = x.shape[0] + n_of(tail)
    dry = pad_to(x, n)
    feed = at(hp(dry, lo_cut), predelay, n) * 0.015
    fb = 0.7 + 0.28 * room
    d = 0.4 * damp
    acc = np.zeros(n)
    for D in COMBS:
        acc += _comb(feed, D, fb, d)
    for D in ALLPASSES:
        acc = _allpass(acc, D)
    return dry + wet * 3.0 * acc


# ---------------------------------------------------------------------------
# Assembly and level
# ---------------------------------------------------------------------------

def pad_to(x, n):
    if x.shape[0] >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - x.shape[0])])


def mix(*parts):
    n = max(p.shape[0] for p in parts)
    out = np.zeros(n)
    for p in parts:
        out += pad_to(p, n)
    return out


def at(x, delay, n=None):
    """Place `x` `delay` seconds in. What layers a cue in time."""
    out = np.concatenate([np.zeros(n_of(delay)), x])
    return out if n is None else pad_to(out, n)


def soft_clip(x, drive=1.0):
    """Saturation (tanh): adds harmonics, and bounds the result."""
    return np.tanh(x * drive) / math.tanh(drive) if drive > 0 else x


def tail_off(x, seconds=0.08):
    """A cosine fade over the last `seconds`, so a room's tail ends at 0."""
    k = min(n_of(seconds), x.shape[0] // 2)
    x = x.copy()
    x[-k:] *= 0.5 * (1.0 + np.cos(np.linspace(0.0, np.pi, k)))
    return x


def _window_rms(x):
    """RMS of the loudest 100ms window, or of the whole cue if shorter."""
    w = min(x.shape[0], n_of(0.100))
    if w >= x.shape[0]:
        return float(np.sqrt(np.mean(x ** 2)))
    sq = np.convolve(x ** 2, np.ones(w) / w, mode="valid")
    return float(np.sqrt(sq.max()))


def unit(x):
    """`x` scaled so its loudest 100ms is at RMS 1: what lets a cue's layers
    be weighted by how loud each should be."""
    r = _window_rms(x)
    return x / r if r > 0 else x


def _k_weighting():
    """BS.1770's two pre-filters (a +4 dB shelf above ~1.7 kHz, and a
    high-pass near 38 Hz), designed for `RATE`."""
    G, Q, fc = 3.99984385397, 0.7071752369554193, 1681.974450955533
    A = 10 ** (G / 40)
    w0 = 2 * math.pi * fc / RATE
    alpha = math.sin(w0) / (2 * Q)
    cw, sa = math.cos(w0), math.sqrt(A)
    shelf = ([A * ((A + 1) + (A - 1) * cw + 2 * sa * alpha),
              -2 * A * ((A - 1) + (A + 1) * cw),
              A * ((A + 1) + (A - 1) * cw - 2 * sa * alpha)],
             [(A + 1) - (A - 1) * cw + 2 * sa * alpha,
              2 * ((A - 1) - (A + 1) * cw),
              (A + 1) - (A - 1) * cw - 2 * sa * alpha])
    Q, fc = 0.5003270373253953, 38.13547087613982
    w0 = 2 * math.pi * fc / RATE
    alpha = math.sin(w0) / (2 * Q)
    cw = math.cos(w0)
    rlb = ([(1 + cw) / 2, -(1 + cw), (1 + cw) / 2],
           [1 + alpha, -2 * cw, 1 - alpha])
    return shelf, rlb


K_WEIGHTING = _k_weighting()


def loudness(x):
    """K-weighted RMS of the loudest 100ms window: roughly how loud a cue
    sounds, where a plain RMS would rate its inaudible lows as loud as its
    piercing highs. What `finish` normalises to."""
    (b1, a1), (b2, a2) = K_WEIGHTING
    return _window_rms(signal.lfilter(b2, a2, signal.lfilter(b1, a1, x)))


def limit(x, ceiling, release=0.05, look=0.0015):
    """A peak limiter: the gain rides down `look` seconds ahead of anything
    over `ceiling` and recovers over `release` seconds."""
    L = n_of(look)
    need = maximum_filter1d(np.maximum(1.0, np.abs(x) / ceiling), 2 * L + 1)
    k = math.exp(-1.0 / n_of(release))
    r = need.tolist()
    prev = 1.0
    for i in range(len(r)):
        v = r[i]
        prev = v if v > prev else 1.0 + (prev - 1.0) * k
        r[i] = prev
    return x / uniform_filter1d(np.array(r), L)


def finish(x, level):
    """Fade both ends, normalise to `level` (see `loudness`), and limit the
    peaks to `PEAK_CEILING`, by at most `LIMIT_MAX`. The head fade is 0.4ms,
    short enough to keep a plucked cue's attack; the tail fade is 3ms."""
    x = np.array(x, dtype=np.float64)
    head = min(n_of(0.0004), x.shape[0] // 2)
    tail = min(n_of(0.003), x.shape[0] // 2)
    if head > 1:
        x[:head] *= np.linspace(0, 1, head)
    if tail > 1:
        x[-tail:] *= np.linspace(1, 0, tail)

    lo = loudness(x)
    if lo > 0:
        x = x * (level / lo)
    pk = float(np.max(np.abs(x)))
    if pk > PEAK_CEILING * LIMIT_MAX:
        x = x * (PEAK_CEILING * LIMIT_MAX / pk)
    if float(np.max(np.abs(x))) > PEAK_CEILING:
        x = limit(x, PEAK_CEILING)
    return np.clip(x, -PEAK_CEILING, PEAK_CEILING)


# ---------------------------------------------------------------------------
# The graze keeps the old player shot's recipe: a struck resonator over a
# swept, resonant sawtooth.
# ---------------------------------------------------------------------------

ARCANE = (1.0, 2.41, 3.87, 5.62, 7.09)


def sweep(f0, f1, n, shape="exp"):
    """Phase for a pitch sweep from `f0` to `f1` across `n` samples."""
    if shape == "exp":
        f = f0 * (max(1e-6, f1) / max(1e-6, f0)) ** np.linspace(0, 1, n)
    else:
        f = np.linspace(f0, f1, n)
    return 2 * np.pi * np.cumsum(f) / RATE


def sine(f0, n, f1=None, shape="exp"):
    return np.sin(sweep(f0, f1 if f1 is not None else f0, n, shape))


def saw(f0, n, f1=None):
    """A naive sawtooth, optionally sweeping from `f0` to `f1`."""
    p = sweep(f0, f1 if f1 is not None else f0, n) / (2 * np.pi)
    return 2 * (p - np.floor(p + 0.5))


def struck(f, n, ratios=ARCANE, amps=(1.0, 0.55, 0.32, 0.18, 0.10),
           decay=1.0, curve0=3.0, spread=1.9, detune=0.004):
    """A bank of decaying partials: a resonator being hit. Higher partials
    decay faster, and each is detuned slightly so they shimmer."""
    out = np.zeros(n)
    for i, (r, a) in enumerate(zip(ratios, amps)):
        fi = f * r * (1.0 + detune * (i - len(ratios) / 2.0))
        out += sine(fi, n) * env_pluck(n, decay, curve0 * (spread ** i)) * a
    return out


def zap(f0, f1, n, q=7.0, cut=2.6, drive=1.6):
    """A sawtooth swept down through a resonant lowpass. `cut` is the
    filter's corner relative to the oscillator."""
    out = moving_lowpass(saw(f0, n, f1), f0 * cut, max(60.0, f1 * cut), q=q)
    return soft_clip(out, drive)


# ---------------------------------------------------------------------------
# The cues
#
# Each returns mono float samples; `main` sets their level.
# ---------------------------------------------------------------------------

def cue_shot_soft(g):
    """The shot cue for round bullets and any shape `sfx_for_shape` doesn't
    list: a puff of air through a closing band, with a low pop."""
    n = n_of(0.100)
    puff = unit(svf(pink(n, g), glide(1800, 620, n, 0.06), 1.3, "bp")
                * env_exp(n, 0.002, 0.022))
    pop = unit(osc_sine(settle(480, 290, n, 0.018), n) * env_exp(n, 0.0015, 0.020))
    return hp(mix(puff, pop * 0.4), 120)


def cue_shot_sharp(g):
    """The shot cue for the thin shapes (see `sfx_for_shape`), which include
    Mika's sand: a quick slice of air, falling, with a faint tick."""
    n = n_of(0.090)
    hiss = unit(svf(white(n, g), glide(2200, 1000, n, 0.05), 1.5, "bp")
                * env_exp(n, 0.001, 0.017))
    body = unit(svf(pink(n, g), 750, 0.9, "bp") * env_exp(n, 0.001, 0.013))
    tick = unit(thump(n, 300, 170, 0.008, 0.010))
    return lp(hp(mix(hiss, body * 0.5, tick * 0.2), 150), 7000)


def cue_shot_heavy(g):
    """The shot cue for the big angular shapes (see `sfx_for_shape`): a
    dropping thump, a rush of air, and a short low growl."""
    n = n_of(0.260)
    body = unit(soft_clip(thump(n, 165, 60, 0.03, 0.075), 1.5))
    rush = unit(svf(pink(n, g), glide(2300, 300, n, 0.14), 0.9)
                * env_exp(n, 0.003, 0.055))
    src = mix(osc_saw(82.4, n, g), osc_saw(83.3, n, g), osc_saw(123.5, n, g) * 0.5)
    growl = unit(svf(src, glide(1000, 240, n, 0.16), 1.2) * env_exp(n, 0.004, 0.075))
    return hp(mix(body, rush * 0.75, growl * 0.4), 40)


def cue_laser_charge(g):
    """A beam's warning line, or a ring charging (`ring_charge`): a buzzing
    hum rising a fifth with a quickening flutter, and a hiss rising with it,
    gone when the beam fires."""
    n = n_of(0.62)
    e = env_rise(n, 0.50, 0.12, 1.5)
    bend = glide(1.0, 1.5, n, 0.5)
    src = mix(osc_saw(98.0 * bend, n, g), osc_saw(98.6 * bend, n, g))
    hum = svf(src, glide(250, 1800, n, 0.5), 1.6) * trem(n, glide(10, 32, n, 0.5), 0.35)
    fizz = svf(pink(n, g), glide(500, 3000, n, 0.5), 2.5, "bp")
    x = lp(hp(mix(unit(hum * e) * 0.7, unit(fizz * e) * 0.5), 60), 5500)
    return tail_off(reverb(x, 0.15, room=0.55, damp=0.5, tail=0.25))


def cue_laser_fire(g):
    """A beam arriving, a charged ring going live, and Storm Cage's bolt: an
    electric snap and crackle over a saturated low buzz, with no long tail
    (the beam itself lasts much longer than the cue)."""
    n = n_of(0.50)
    snap = unit(crack(n, g, 10000, 900, 0.02))
    arc = unit(crackle(n, g, 2500.0, 1500, 8000) * env_exp(n, 0.0, 0.06))
    src = soft_clip(mix(osc_saw(55.0, n, g), osc_saw(55.6, n, g),
                        osc_saw(110.4, n, g) * 0.6), 2.5)
    buzz = unit(svf(src, glide(2600, 300, n, 0.35), 1.1) * env_exp(n, 0.002, 0.13))
    roar = unit(svf(pink(n, g), 1000, 0.7, "bp") * env_exp(n, 0.001, 0.10))
    sub = unit(thump(n, 110, 42, 0.03, 0.10))
    x = hp(mix(snap * 0.6, arc * 0.35, buzz * 0.7, roar * 0.55, sub * 0.55), 35)
    return tail_off(reverb(x, 0.2, room=0.6, damp=0.5, tail=0.4))


def cue_ward_close(g):
    """A ring forming (`ring_new`), or a thrown chakram caught back at rest:
    Mika's hoop sounding low, with a soft front, a short metallic scrape and
    a little weight."""
    n = n_of(0.80)
    hoop = unit(lp(metal(146.83, n, g, HOOP, (1.0, 0.45, 0.22, 0.10),
                         (0.38, 0.19, 0.10, 0.05), attack=0.012, beat=1.2), 3500))
    scrape = unit(svf(pink(n, g), glide(2600, 1200, n, 0.08), 3.0, "bp")
                  * env_exp(n, 0.008, 0.05))
    weight = unit(thump(n, 95, 60, 0.03, 0.05))
    x = hp(mix(hoop, scrape * 0.3, weight * 0.35), 40)
    return tail_off(reverb(x, 0.24, room=0.62, damp=0.5, tail=0.4))


def cue_ward_scatter(g):
    """Something flung outward: the sigil's seals leaving Szuix, a chakram
    thrown. A low launch and a rush of air that recedes."""
    n = n_of(0.75)
    launch = unit(soft_clip(thump(n, 140, 50, 0.03, 0.08), 1.5))
    snap = unit(crack(n, g, 6000, 600, 0.02))
    rush = unit(svf(pink(n, g), glide(1700, 340, n, 0.55), 1.1, "bp")
                * env_exp(n, 0.012, 0.19))
    x = hp(mix(launch * 0.7, snap * 0.4, rush), 40)
    return tail_off(reverb(x, 0.28, room=0.7, damp=0.5, tail=0.55))


def cue_ward_pull(g):
    """The charge before every boss attack (`boss_charge`, as `Sfx.Charge`):
    air and energy drawn in, rising and tightening, peaking just before
    `CHARGE_S` runs out and the attack's first shots come. (`Sfx.WardPull`
    also names this sound.)"""
    peak = CHARGE_S - 0.08
    n = n_of(CHARGE_S + 0.35)
    e = env_rise(n, peak, 0.14, 2.0)
    suck = svf(pink(n, g), glide(220, 2200, n, peak), glide(1.2, 3.5, n, peak), "bp")
    bend = glide(1.0, 2.0, n, peak)
    src = mix(osc_saw(55.0 * bend, n, g), osc_saw(55.4 * bend, n, g),
              osc_saw(110.3 * bend, n, g) * 0.6)
    drone = svf(src, glide(180, 2200, n, peak), 1.3) \
        * trem(n, glide(5, 26, n, peak), 0.45)
    motes = crackle(n, g, glide(40, 420, n, peak), 2500, 7000)
    x = mix(unit(suck * e), unit(drone * env_rise(n, peak, 0.12, 1.6)) * 0.55,
            unit(motes * e) * 0.12)
    return tail_off(reverb(hp(x, 40), 0.22, room=0.65, damp=0.5, tail=0.3))


def cue_ward_burst(g):
    """A detonation: a sigil seal going off, a chakram slamming to rest as
    it starts to spray. A dropping boom and crack, rumble, shards, and the
    hoop ringing under them."""
    n = n_of(0.95)
    boom = unit(soft_clip(mix(unit(thump(n, 120, 40, 0.04, 0.18)),
                              unit(crack(n, g, 8000, 350, 0.045)) * 0.75), 1.8))
    rumble = unit(svf(brown(n, g), 300, 0.7) * env_exp(n, 0.003, 0.30))
    shards = unit(crackle(n, g, 900.0, 1500, 6000) * env_exp(n, 0.0, 0.12))
    hoop = unit(lp(metal(110.0, n, g, HOOP, (1.0, 0.4, 0.18, 0.08),
                         (0.42, 0.20, 0.10, 0.05), attack=0.004, beat=1.0), 3000))
    x = hp(mix(boom, rumble * 0.45, shards * 0.28, hoop * 0.3), 30)
    return tail_off(reverb(x, 0.3, room=0.8, damp=0.45, tail=0.8))


def cue_pshot(g):
    """Szuix's shot, his blue fireball. It sounds about ten times a second
    while Z is held, so it is short, soft-fronted and mid-low: a puff of
    flame through a band that closes as it flies off, a roar under it, a
    faint pop of weight, and a few crackles."""
    n = n_of(0.140)
    flame = unit(svf(pink(n, g), glide(1500, 520, n, 0.09), 1.1, "bp")
                 * env_exp(n, 0.004, 0.032))
    roar = unit(svf(brown(n, g), 700, 0.7) * env_exp(n, 0.007, 0.042))
    pop = unit(thump(n, 190, 90, 0.018, 0.026))
    fizz = unit(crackle(n, g, 220.0, 1800, 6500) * env_exp(n, 0.002, 0.05))
    return hp(mix(flame, roar * 0.75, pop * 0.28, fizz * 0.22), 80)


def cue_graze(g):
    """Grazing a bullet: the player's old shot, a short bright resonator
    over a swept sawtooth."""
    n = n_of(0.075)
    tip = struck(2080, n, ratios=(1.0, 2.41, 3.87, 5.62),
                 amps=(1.0, 0.50, 0.24, 0.11), decay=0.48, curve0=4.6)
    core = zap(1650, 900, n, q=6.5, cut=1.8, drive=1.15) \
        * env_pluck(n, 0.40, 8.5) * 0.50
    return mix(tip, core)


def cue_item(g):
    """A shard collected: an upward breath of air and a soft glass tone. The
    tone dies within tens of milliseconds, so a stream of pickups patters
    rather than rings."""
    n = n_of(0.200)
    glass = unit(metal(784.0, n, g, (1.0, 2.32, 4.25), (1.0, 0.3, 0.1),
                       (0.07, 0.035, 0.018), attack=0.003, beat=4.0))
    breath = unit(svf(white(n, g), glide(1400, 3600, n, 0.05), 1.4, "bp")
                  * env_exp(n, 0.004, 0.018))
    return lp(mix(glass, breath * 0.5), 5000)


def cue_enemy_hit(g):
    """A player shot landing: a muted tick with a little knock under it."""
    n = n_of(0.050)
    tsk = unit(svf(white(n, g), 1600, 1.5, "bp") * env_exp(n, 0.0005, 0.0065))
    thud = unit(thump(n, 340, 210, 0.008, 0.011))
    return lp(hp(mix(tsk, thud * 0.6), 150), 5500)


def cue_enemy_die(g):
    """Fodder destroyed: a dropping boom, a puff of air, and debris."""
    n = n_of(0.34)
    boom = unit(soft_clip(thump(n, 190, 58, 0.03, 0.06), 1.6))
    poof = unit(svf(pink(n, g), glide(5200, 420, n, 0.2), 0.8)
                * env_exp(n, 0.001, 0.07))
    debris = unit(crackle(n, g, 650.0, 1300, 5500) * env_exp(n, 0.0, 0.075))
    x = hp(mix(boom * 0.85, poof, debris * 0.32), 45)
    return tail_off(reverb(x, 0.18, room=0.5, damp=0.6, tail=0.28))


def cue_hit(g):
    """Szuix hit: loud and low. A heavy boom and snap, his seal shattering,
    a dissonant low tone closing down, and air falling away."""
    n = n_of(0.75)
    boom = unit(soft_clip(thump(n, 150, 38, 0.05, 0.16), 1.8))
    snap = unit(crack(n, g, 8000, 420, 0.035))
    shatter = unit(crackle(n, g, 1500.0, 1200, 6000) * env_exp(n, 0.0, 0.09))
    src = mix(osc_saw(73.42, n, g), osc_saw(77.78, n, g))
    dread = unit(svf(src, glide(1100, 170, n, 0.5), 1.0) * env_exp(n, 0.004, 0.22))
    fall = unit(svf(pink(n, g), glide(2400, 160, n, 0.5), 1.3, "bp")
                * env_exp(n, 0.002, 0.20))
    x = hp(mix(boom, snap * 0.7, shatter * 0.35, dread * 0.55, fall * 0.5), 35)
    return tail_off(reverb(x, 0.25, room=0.72, damp=0.5, tail=0.55))


def cue_bomb(g):
    """The sigil. The transient is at sample zero, because the cue answers a
    key press: a blast, a roar of flame, a sweep rising while the wave
    travels, and a sung open fifth."""
    n = n_of(1.15)
    blast = unit(soft_clip(mix(unit(thump(n, 130, 34, 0.06, 0.26)),
                               unit(crack(n, g, 9000, 500, 0.045)) * 0.7), 1.8))
    fire = unit(svf(pink(n, g), 650, 0.7, "bp") * env_exp(n, 0.05, 0.34))
    crackles = unit(crackle(n, g, 320.0, 1500, 6500) * env_exp(n, 0.02, 0.32))
    rise = unit(svf(pink(n, g), glide(300, 3800, n, 0.45), 2.0, "bp")
                * env_rise(n, 0.34, 0.55, 1.6))
    chant = unit(choir((110.0, 164.81, 220.0, 329.63), n, g, "a")
                 * env_exp(n, 0.05, 0.45))
    x = hp(mix(blast, fire * 0.6, crackles * 0.25, rise * 0.4, chant * 0.42), 30)
    return tail_off(reverb(x, 0.33, room=0.85, damp=0.45, tail=1.0))


def cue_player_down(g):
    """The run lost: an impact, then a tritone and a sung "oh" sinking
    together, unresolved."""
    n = n_of(1.45)
    impact = unit(soft_clip(mix(unit(thump(n, 150, 34, 0.05, 0.22)),
                                unit(crack(n, g, 7000, 380, 0.04)) * 0.6), 1.7))
    bend = glide(1.0, 0.55, n, 1.2)
    src = mix(osc_saw(110.0 * bend, n, g), osc_saw(155.56 * bend, n, g),
              osc_saw(55.0 * bend, n, g) * 0.6)
    fall = unit(svf(src, glide(1500, 140, n, 1.2), 1.1) * env_exp(n, 0.01, 0.5))
    mourn = unit(choir((110.0, 155.56), n, g, "o", bend=bend) * env_exp(n, 0.06, 0.5))
    rumble = unit(svf(brown(n, g), 260, 0.7) * env_exp(n, 0.01, 0.5))
    x = hp(mix(impact, fall * 0.55, mourn * 0.4, rumble * 0.5), 30)
    return tail_off(reverb(x, 0.38, room=0.9, damp=0.5, tail=1.2))


def cue_boss_appear(g):
    """A boss arriving: rumble, drone and indrawn air rising together, onto
    a strike and a gong."""
    hit_at = 0.55
    n = n_of(1.30)
    rumble = unit(svf(brown(n, g), glide(90, 900, n, hit_at), 0.8)
                  * env_rise(n, hit_at, 0.06, 1.5))
    src = mix(osc_saw(41.2, n, g), osc_saw(41.6, n, g), osc_saw(82.4, n, g))
    drone = unit(svf(src, glide(150, 800, n, hit_at), 1.4)
                 * env_rise(n, hit_at, 0.12, 1.3))
    suck = unit(svf(pink(n, g), glide(400, 3000, n, hit_at), 2.5, "bp")
                * env_rise(n, hit_at - 0.03, 0.05, 2.2))
    m = n - n_of(hit_at)
    strike = soft_clip(mix(unit(thump(m, 120, 40, 0.05, 0.25)),
                           unit(crack(m, g, 7000, 300, 0.04)) * 0.6), 1.7)
    gong = lp(metal(73.42, m, g, GONG, GONG_AMPS,
                    (0.8, 0.6, 0.45, 0.32, 0.22, 0.15), attack=0.002, beat=0.8), 2600)
    hit = at(mix(unit(strike), unit(gong) * 0.6), hit_at, n)
    x = hp(mix(rumble * 0.6, drone * 0.5, suck * 0.35, hit), 30)
    return tail_off(reverb(x, 0.33, room=0.86, damp=0.45, tail=1.0))


def cue_spell_declare(g):
    """A spell being named, during `BOSS_SPELL_LEAD`: a short indrawn breath,
    then a gong and a sung minor chord."""
    hit_at = 0.20
    n = n_of(1.45)
    inhale = unit(svf(pink(n, g), glide(300, 2600, n, hit_at), 1.8, "bp")
                  * env_rise(n, hit_at, 0.08, 2.0))
    m = n - n_of(hit_at)
    gong = unit(lp(metal(82.41, m, g, GONG, GONG_AMPS,
                         (1.1, 0.8, 0.6, 0.45, 0.3, 0.2), attack=0.003, beat=0.7), 3000))
    weight = unit(thump(m, 130, 45, 0.04, 0.2))
    chant = unit(choir((146.83, 220.0, 293.66, 349.23), m, g, "a")
                 * env_exp(m, 0.12, 0.62))
    x = mix(inhale * 0.45, at(mix(gong * 0.8, weight * 0.7, chant * 0.6), hit_at, n))
    return tail_off(reverb(hp(x, 30), 0.38, room=0.88, damp=0.4, tail=1.2))


def cue_spell_cut(g):
    """A spell's cut-in opening (`scripts/spell_cutin`): air split by the
    cut running across the field, a low whump as the band slams open behind
    it, and the rush of the face sliding in, receding before the declaration's
    in-breath (`cue_spell_declare`, which starts 0.37s in) begins."""
    n = n_of(0.60)
    blade = unit(svf(pink(n, g), glide(1200, 5000, n, 0.11, 0.7), 2.6, "bp")
                 * env_rise(n, 0.08, 0.10, 1.4))
    m = n - n_of(0.06)
    whump = soft_clip(mix(unit(thump(m, 150, 42, 0.05, 0.13, attack=0.012)),
                          unit(svf(pink(m, g), settle(2400, 260, m, 0.05), 0.8)
                               * env_exp(m, 0.01, 0.07)) * 0.5), 1.4)
    rush = unit(svf(pink(n, g), glide(2600, 380, n, 0.36), 1.2, "bp")
                * env_rise(n, 0.10, 0.28, 1.2))
    x = hp(mix(blade * 0.5, at(unit(whump), 0.06, n), rush * 0.5), 40)
    return tail_off(reverb(x, 0.26, room=0.7, damp=0.5, tail=0.45))


def cue_spell_break(g):
    """An attack broken: its bullets swept away in a burst of air and a
    rising rush, with weight under it. The rank card's medal
    (`cue_medal`) sounds on the same frame and carries the melody."""
    n = n_of(0.90)
    whoomph = unit(svf(pink(n, g), settle(5000, 480, n, 0.05), 0.8)
                   * env_exp(n, 0.001, 0.08))
    weight = unit(thump(n, 140, 60, 0.03, 0.10))
    rush = unit(svf(pink(n, g), glide(900, 3200, n, 0.25), 1.5, "bp")
                * env_rise(n, 0.06, 0.40, 1.0))
    shards = unit(crackle(n, g, 1200.0, 1500, 5000) * env_exp(n, 0.0, 0.12))
    x = hp(mix(whoomph, weight * 0.45, rush * 0.25, shards * 0.15), 50)
    return tail_off(reverb(x, 0.3, room=0.8, damp=0.45, tail=0.8))


def cue_spell_survive(g):
    """An attack that ran out its clock: its bullets fizzling out in air
    falling away, dull and short. The medal carries the melody, as for
    `cue_spell_break`."""
    n = n_of(0.80)
    fade = unit(svf(pink(n, g), glide(1600, 250, n, 0.5), 1.0, "bp")
                * env_exp(n, 0.01, 0.20))
    dust = unit(svf(pink(n, g), 900, 0.7) * env_exp(n, 0.01, 0.20))
    weight = unit(thump(n, 110, 55, 0.04, 0.12))
    x = lp(hp(mix(fade, dust * 0.4, weight * 0.4), 50), 2400)
    return tail_off(reverb(x, 0.22, room=0.7, damp=0.6, tail=0.6))


# D major, rising: each medal's arpeggio climbs further up it.
D_MAJOR = (220.0, 293.66, 369.99, 440.0, 587.33, 739.99, 880.0, 1174.66)
TWINKLE = (1174.66, 1479.98, 1760.0)


def cue_medal(g, tier):
    """A medal thrown by the rank card, one cue per `Mark` (0 is STONE, 4 is
    AMETHYST). Each rung climbs higher on `D_MAJOR` over more notes, with a
    brighter chime, and from SILVER up a twinkle over it; AMETHYST adds a
    sung halo. A small burst of air and a knock land with the medal's
    strike."""
    notes = (D_MAJOR[0:2], D_MAJOR[1:4], D_MAJOR[1:5], D_MAJOR[1:7],
             D_MAJOR[1:8])[tier]
    step = (0.07, 0.055, 0.05, 0.045, 0.04)[tier]
    bright = (0.25, 0.38, 0.48, 0.56, 0.60)[tier]
    sustain = (0.5, 0.7, 0.9, 1.1, 1.3)[tier]
    twinkle = (0.0, 0.0, 8.0, 16.0, 24.0)[tier]
    top = (len(notes) - 1) * step
    n = n_of(top + 0.8 * sustain + 0.1)
    rise = unit(arpeggio(notes, step, n, g, bright, sustain, fall=0.92))
    whoomph = unit(svf(pink(n, g), settle(4200, 500, n, 0.05), 0.8)
                   * env_exp(n, 0.001, 0.05))
    knock = unit(thump(n, 150, 80, 0.02, 0.06))
    parts = [rise, whoomph * (0.35 + 0.06 * tier), knock * (0.3 + 0.04 * tier)]
    if twinkle > 0:
        parts.append(unit(glitter(n, g, TWINKLE, twinkle, top * 0.5, top + 0.35))
                     * (0.08 + 0.03 * tier))
    if tier >= 4:
        halo = choir((293.66, 369.99, 440.0, 587.33), n, g, "a")             * env_exp(n, 0.15, 0.8)
        parts.append(unit(halo) * 0.3)
    x = hp(mix(*parts), 60)
    return tail_off(reverb(x, 0.26 + 0.04 * tier, room=0.8, damp=0.45,
                           tail=0.7 + 0.15 * tier))


def cue_capture(g):
    """A spell captured (broken with no hit and no sigil). It plays over the
    break and a GOLD or AMETHYST medal, so it is thin and high: the medals'
    chime, in their key, an octave up, and a breath of air."""
    n = n_of(1.05)
    shine = unit(arpeggio((587.33, 880.0, 1174.66), 0.07, n, g, 0.42, 1.1,
                          fall=0.85, start=0.02))
    air = unit(svf(white(n, g), 5200, 2.0, "bp") * env_rise(n, 0.10, 0.55, 1.5))
    x = lp(hp(mix(shine, air * 0.14), 200), 7000)
    return tail_off(reverb(x, 0.45, room=0.86, damp=0.4, tail=1.0))


def cue_boss_die(g):
    """A boss beaten, filling the pause before the result panel
    (`win_pending`): the largest impact in the set, then a sung major chord
    and a rising arpeggio."""
    n = n_of(2.0)
    impact = soft_clip(mix(unit(thump(n, 110, 30, 0.08, 0.34)),
                           unit(crack(n, g, 9000, 300, 0.06)) * 0.7), 1.9)
    rumble = unit(svf(brown(n, g), 250, 0.7) * env_exp(n, 0.005, 0.7))
    debris = unit(crackle(n, g, 600.0, 1300, 6000) * env_exp(n, 0.0, 0.25))
    chord_at = 0.28
    m = n - n_of(chord_at)
    chant = unit(choir((146.83, 185.0, 220.0, 293.66), m, g, "a")
                 * env_exp(m, 0.15, 0.85))
    rise = unit(arpeggio((293.66, 369.99, 440.0, 587.33, 739.99), 0.06, m, g,
                         0.5, 1.2, fall=0.9))
    x = hp(mix(unit(impact), rumble * 0.55, debris * 0.3,
               at(mix(chant * 0.5, rise * 0.45), chord_at, n)), 28)
    return tail_off(reverb(x, 0.42, room=0.9, damp=0.45, tail=1.5))


def cue_ui_move(g):
    """The cursor moving: a soft wooden tok (it repeats while a key is
    held)."""
    n = n_of(0.080)
    tok = unit(osc_sine(settle(800, 610, n, 0.004), n) * env_exp(n, 0.0008, 0.012))
    tap = unit(svf(white(n, g), 2300, 2.0, "bp") * env_exp(n, 0.0003, 0.003))
    return lp(mix(tok, tap * 0.3), 3600)


def cue_ui_select(g):
    """Confirm: two chimed notes rising a fifth."""
    n = n_of(0.42)
    two = unit(arpeggio((220.0, 329.63), 0.06, n, g, 0.35, 0.45))
    air = unit(svf(pink(n, g), glide(800, 2400, n, 0.15), 1.2, "bp")
               * env_exp(n, 0.01, 0.06))
    x = hp(mix(two, air * 0.22), 80)
    return tail_off(reverb(x, 0.18, room=0.5, damp=0.5, tail=0.3))


def cue_ui_back(g):
    """Leaving a screen: the confirm's fifth, falling and duller."""
    n = n_of(0.38)
    two = unit(arpeggio((329.63, 220.0), 0.055, n, g, 0.25, 0.35, fall=0.9))
    x = lp(hp(two, 80), 2600)
    return tail_off(reverb(x, 0.14, room=0.5, damp=0.55, tail=0.25))


def cue_ui_deny(g):
    """A refusal, such as a locked stage: two low, muffled, sour buzzes."""
    n = n_of(0.28)
    k = n_of(0.12)

    def buzz():
        src = mix(osc_saw(98.0, k, g), osc_saw(103.83, k, g))
        return unit(svf(src, 650, 0.9) * env_exp(k, 0.003, 0.035))

    knock = unit(thump(n, 180, 100, 0.01, 0.02))
    return lp(mix(at(buzz(), 0.0, n), at(buzz() * 0.85, 0.095, n), knock * 0.3), 1200)


def cue_pause(g):
    """The pause menu opening or closing: a muted knock, with the hoop
    sounding faintly under it."""
    n = n_of(0.24)
    knock = unit(thump(n, 240, 150, 0.01, 0.03))
    felt = unit(svf(brown(n, g), 700, 0.7) * env_exp(n, 0.001, 0.025))
    hoop = unit(lp(metal(196.0, n, g, HOOP, (1.0, 0.35, 0.12, 0.05),
                         (0.09, 0.05, 0.03, 0.02), attack=0.002, beat=1.5), 2500))
    x = hp(mix(knock, felt * 0.5, hoop * 0.3), 60)
    return tail_off(reverb(x, 0.12, room=0.45, damp=0.6, tail=0.2))


# The set, in the order the preview lays them out (grouped by use), with each
# cue's loudness in the mix (`loudness`, before `SFX_MASTER`). The row's gain
# in `audio_functions` is that loudness over the WAV's, which `main` prints.
CUES = (
    ("snd_shot_soft", cue_shot_soft, 0.075),
    ("snd_shot_sharp", cue_shot_sharp, 0.070),
    ("snd_shot_heavy", cue_shot_heavy, 0.100),
    ("snd_laser_charge", cue_laser_charge, 0.100),
    ("snd_laser_fire", cue_laser_fire, 0.150),

    ("snd_ward_close", cue_ward_close, 0.120),
    ("snd_ward_scatter", cue_ward_scatter, 0.160),
    ("snd_ward_pull", cue_ward_pull, 0.130),
    ("snd_ward_burst", cue_ward_burst, 0.240),

    ("snd_pshot", cue_pshot, 0.050),
    ("snd_graze", cue_graze, 0.075),
    ("snd_item", cue_item, 0.060),
    ("snd_enemy_hit", cue_enemy_hit, 0.040),
    ("snd_enemy_die", cue_enemy_die, 0.140),

    ("snd_hit", cue_hit, 0.260),
    ("snd_bomb", cue_bomb, 0.300),
    ("snd_player_down", cue_player_down, 0.240),

    ("snd_boss_appear", cue_boss_appear, 0.210),
    ("snd_spell_cut", cue_spell_cut, 0.160),
    ("snd_spell_declare", cue_spell_declare, 0.230),
    ("snd_spell_break", cue_spell_break, 0.160),
    ("snd_spell_survive", cue_spell_survive, 0.120),
    ("snd_capture", cue_capture, 0.120),
    ("snd_medal_stone", lambda g: cue_medal(g, 0), 0.120),
    ("snd_medal_bronze", lambda g: cue_medal(g, 1), 0.140),
    ("snd_medal_silver", lambda g: cue_medal(g, 2), 0.160),
    ("snd_medal_gold", lambda g: cue_medal(g, 3), 0.180),
    ("snd_medal_amethyst", lambda g: cue_medal(g, 4), 0.210),
    ("snd_boss_die", cue_boss_die, 0.360),

    ("snd_ui_move", cue_ui_move, 0.070),
    ("snd_ui_select", cue_ui_select, 0.110),
    ("snd_ui_back", cue_ui_back, 0.090),
    ("snd_ui_deny", cue_ui_deny, 0.090),
    ("snd_pause", cue_pause, 0.090),
)

# Each WAV is written at twice its mix loudness (so its gain is about 0.5),
# and never above this.
LEVEL_CAP = 0.45


# ---------------------------------------------------------------------------
# The preview
#
# A WAV of the whole set in order with a beat between cues (to hear whether
# two are too alike), and a PNG of every cue's waveform and spectrum (to see
# whether two share a band).
# ---------------------------------------------------------------------------

def write_preview_wav(built, path):
    gap = np.zeros(n_of(0.35))
    parts = []
    for _, samples in built:
        parts.append(samples)
        parts.append(gap)
    strip = np.concatenate(parts) if parts else np.zeros(1)

    import wave
    pcm = (np.clip(strip, -1.0, 1.0) * 32767).round().astype("<i2")
    with wave.open(path, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(RATE)
        fh.writeframes(pcm.tobytes())


def write_preview_png(built, path):
    from PIL import Image, ImageDraw

    try:
        import art_common
        small = art_common.font(art_common.SPECTRAL, 10)
    except Exception:
        small = None

    cw, ch, pad = 300, 96, 12
    cols = 4
    rows = (len(built) + cols - 1) // cols
    W = cols * (cw + pad) + pad
    H = rows * (ch + pad + 16) + pad
    img = Image.new("RGB", (W, H), (16, 17, 28))
    d = ImageDraw.Draw(img)
    span = max(s.shape[0] for _, s in built)

    for i, (name, samples) in enumerate(built):
        x0 = pad + (i % cols) * (cw + pad)
        y0 = pad + (i // cols) * (ch + pad + 16)
        d.rectangle([x0, y0, x0 + cw, y0 + ch], fill=(24, 26, 42))

        # The waveform, min/max per column, on a common time base so the
        # lengths can be compared.
        wave_w = max(2, int(cw * samples.shape[0] / span))
        chunk = max(1, samples.shape[0] // wave_w)
        mid = y0 + ch // 2
        for c in range(wave_w):
            seg = samples[c * chunk:(c + 1) * chunk]
            if seg.size == 0:
                continue
            hi = int(mid - float(np.max(seg)) * (ch // 2 - 6))
            lo = int(mid - float(np.min(seg)) * (ch // 2 - 6))
            d.line([(x0 + c, hi), (x0 + c, lo)], fill=(120, 200, 230))

        # The spectrum, as a strip under it.
        spec = np.abs(np.fft.rfft(samples * np.hanning(samples.shape[0])))
        freqs = np.fft.rfftfreq(samples.shape[0], 1.0 / RATE)
        keep = freqs <= 9000
        spec, freqs = spec[keep], freqs[keep]
        if spec.max() > 0:
            spec = spec / spec.max()
        bands = 96
        for b in range(bands):
            lo_f = 60 * (9000 / 60.0) ** (b / bands)
            hi_f = 60 * (9000 / 60.0) ** ((b + 1) / bands)
            sel = (freqs >= lo_f) & (freqs < hi_f)
            v = float(spec[sel].max()) if sel.any() else 0.0
            bx = x0 + int(b * cw / bands)
            bh = int(v * 22)
            d.rectangle([bx, y0 + ch - bh, bx + max(1, cw // bands - 1),
                         y0 + ch], fill=(210, 170, 90))

        label = "%s   %.0fms   peak %.2f" % (
            name, samples.shape[0] * 1000.0 / RATE, float(np.max(np.abs(samples))))
        d.text((x0, y0 + ch + 2), label, font=small, fill=(180, 186, 210))

    img.save(path)


# ---------------------------------------------------------------------------

def check_envelopes(built):
    """Report the cues that don't decay: those whose last 100ms window is
    louder than half their loudest (cues under 300ms are skipped). Such a cue
    sounds cut off, and neither its peak, its length nor its spectrum shows it.
    """
    bad = []
    for name, x in built:
        w = min(x.shape[0], n_of(0.100))
        if x.shape[0] < w * 3:
            continue                      # too short for the question to mean anything
        env = [float(np.sqrt(np.mean(x[i:i + w] ** 2)))
               for i in range(0, x.shape[0] - w, w)]
        if not env:
            continue
        if env[-1] > max(env) * 0.5:
            bad.append(name)
            print("  !! %s does not decay: ends at %.2f against a peak of %.2f"
                  % (name, env[-1], max(env)))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true",
                    help="write the preview only; touch no project resource")
    args = ap.parse_args()

    os.makedirs(PREVIEW, exist_ok=True)
    if not args.preview:
        gm_new.folder(FOLDER)

    built = []
    loud = []
    for name, fn, target in CUES:
        samples = finish(fn(rng_for(name)), min(LEVEL_CAP, 2.0 * target))
        built.append((name, samples))
        if not args.preview:
            gm_new.sound(name, samples, rate=RATE, folder=FOLDER)
        lo = loudness(samples)
        gain = target / lo
        if gain > 1.0:
            loud.append(name)
        pk = float(np.max(np.abs(samples)))
        print("  %-18s %6.0fms  loudness %.3f  peak %.2f  gain %.2f%s"
              % (name, samples.shape[0] * 1000.0 / RATE, lo, pk, gain,
                 "  <- limited" if pk >= PEAK_CEILING - 1e-4 else ""))

    bad = check_envelopes(built)

    write_preview_wav(built, os.path.join(PREVIEW, "sfx.wav"))
    write_preview_png(built, os.path.join(PREVIEW, "sfx.png"))
    total = sum(s.shape[0] for _, s in built) * 2
    print("\n%d cues, %.1fs, %.0f KB of PCM" % (
        len(built), sum(s.shape[0] for _, s in built) / float(RATE),
        total / 1024.0))
    print("preview: tools/_preview/sfx.wav and sfx.png")
    if loud:
        print("\n%d cue(s) need a gain above 1: %s" % (len(loud), ", ".join(loud)))
    if bad:
        print("")
        print("%d cue(s) do not decay -- see above" % len(bad))
    return 1 if (bad or loud) else 0


if __name__ == "__main__":
    sys.exit(main() or 0)
