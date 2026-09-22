#!/usr/bin/env python3
"""Synthesise every sound effect in the game and register them.

Every cue is a placeholder. A replacement should be a mono 16-bit WAV of
about the same length and loudness at `sounds/<name>/<name>.wav`, with the
duration in its `.yy` updated; the gains in `audio_functions` were set
against the levels made here.

The cues are short and dry, and spread across frequency bands so they mask
each other less. Each is normalised to a target loudness (see `finish`), and
its noise is seeded from its name, so re-running writes identical WAVs.
`main` exits non-zero if a cue doesn't decay (`check_envelopes`).

    python tools/make_sfx.py            # write every sound + the preview
    python tools/make_sfx.py --preview  # only the preview, touch no resource
"""
import argparse
import hashlib
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gm_new

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREVIEW = os.path.join(ROOT, "tools", "_preview")
os.makedirs(PREVIEW, exist_ok=True)  # git-ignored, so a fresh clone lacks it

RATE = 44100
FOLDER = "Sounds"

# Peak ceiling, leaving headroom for up to `SFX_VOICES` cues on one frame.
PEAK_CEILING = 0.92


# ---------------------------------------------------------------------------
# The toolkit
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


def env_ad(n, attack, decay, curve=3.0):
    """Attack-decay, in seconds, with an exponential decay; `curve` is how
    sharply it falls.
    """
    e = np.ones(n)
    a = min(n, n_of(attack))
    if a > 1:
        e[:a] = np.linspace(0.0, 1.0, a) ** 0.6
    d = max(1, min(n - a, n_of(decay)))
    tail = np.linspace(0.0, 1.0, d)
    e[a:a + d] = np.exp(-curve * tail) * (1 - tail)
    e[a + d:] = 0.0
    return e


def env_pluck(n, decay=1.0, curve=5.0):
    """Instant attack, exponential fall across the whole cue. A struck
    thing."""
    tail = np.linspace(0.0, 1.0, n)
    return np.exp(-curve * tail / max(1e-6, decay))


def env_swell(n, peak=0.35, curve=2.4):
    """Rise to `peak` of the way through, then fall. A thing arriving."""
    p = max(1, int(n * peak))
    e = np.empty(n)
    e[:p] = np.linspace(0.0, 1.0, p) ** 1.6
    tail = np.linspace(0.0, 1.0, n - p) if n > p else np.zeros(0)
    e[p:] = np.exp(-curve * tail) * (1 - tail)
    return e


def sweep(f0, f1, n, shape="exp"):
    """Phase for a pitch sweep from `f0` to `f1` across `n` samples."""
    if shape == "exp":
        f = f0 * (max(1e-6, f1) / max(1e-6, f0)) ** np.linspace(0, 1, n)
    else:
        f = np.linspace(f0, f1, n)
    return 2 * np.pi * np.cumsum(f) / RATE


def sine(f0, n, f1=None, shape="exp"):
    return np.sin(sweep(f0, f1 if f1 is not None else f0, n, shape))


def tri(f0, n, f1=None):
    """A triangle wave: softer than a square, richer than a sine."""
    p = sweep(f0, f1 if f1 is not None else f0, n) / (2 * np.pi)
    return 2 * np.abs(2 * (p - np.floor(p + 0.5))) - 1


def square(f0, n, f1=None, duty=0.5):
    p = sweep(f0, f1 if f1 is not None else f0, n) / (2 * np.pi)
    return np.where((p - np.floor(p)) < duty, 1.0, -1.0)


def noise(n, gen):
    return gen.standard_normal(n)


def biquad(x, b0, b1, b2, a1, a2):
    """Direct form I, written out so the tools don't need scipy."""
    y = np.empty_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(x.shape[0]):
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        y[i] = yi
        x2, x1 = x1, xi
        y2, y1 = y1, yi
    return y


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


def lowpass(x, f, q=0.707):
    return biquad(x, *_rbj("lp", f, q))


def highpass(x, f, q=0.707):
    return biquad(x, *_rbj("hp", f, q))


def bandpass(x, f, q=2.0):
    return biquad(x, *_rbj("bp", f, q))


def moving_lowpass(x, f0, f1, q=0.9):
    """A lowpass whose corner slides from `f0` to `f1` across the sound. The
    coefficients are recomputed every 64 samples.
    """
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
    d = n_of(delay)
    out = np.concatenate([np.zeros(d), x])
    return out if n is None else pad_to(out, n)


def soft_clip(x, drive=1.0):
    """Saturation (tanh): adds harmonics, and bounds the result."""
    return np.tanh(x * drive) / math.tanh(drive) if drive > 0 else x


def finish(x, level):
    """Fade both ends, then normalise to a target loudness.

    `level` is an RMS target (see `loudness`), not a peak, because a short cue
    and a long one at the same peak are nowhere near equally loud. The peak is
    capped at `PEAK_CEILING`, which wins when the two disagree; `main` marks
    the cues that were capped. The head fade is 0.4ms, short enough to keep a
    plucked cue's attack; the tail fade is 3ms.
    """
    head = min(n_of(0.0004), x.shape[0] // 2)
    tail = min(n_of(0.003), x.shape[0] // 2)
    if head > 1:
        x[:head] *= np.linspace(0, 1, head)
    if tail > 1:
        x[-tail:] *= np.linspace(1, 0, tail)

    lo = loudness(x)
    if lo > 0:
        x = x * (level / lo)

    peak = float(np.max(np.abs(x)))
    if peak > PEAK_CEILING:
        x = x * (PEAK_CEILING / peak)
    return x


# ---------------------------------------------------------------------------
# Resonators
#
# - `struck`: a bank of inharmonic partials, for something with mass being hit.
# - `zap`: a rich waveform swept down through a resonant filter.
# - `air`: noise through a resonant moving filter.
# ---------------------------------------------------------------------------

# Partial ratios for `struck`, deliberately inharmonic (whole-number ratios
# sound like a musical note).
ARCANE = (1.0, 2.41, 3.87, 5.62, 7.09)
STONE = (1.0, 1.83, 2.67, 4.12)


def saw(f0, n, f1=None):
    """A sawtooth, optionally sweeping from `f0` to `f1`."""
    p = sweep(f0, f1 if f1 is not None else f0, n) / (2 * np.pi)
    return 2 * (p - np.floor(p + 0.5))


def ringmod(a, b):
    """Two tones multiplied, giving inharmonic sum and difference
    frequencies."""
    n = max(a.shape[0], b.shape[0])
    return pad_to(a, n) * pad_to(b, n)


def struck(f, n, ratios=ARCANE, amps=(1.0, 0.55, 0.32, 0.18, 0.10),
           decay=1.0, curve0=3.0, spread=1.9, detune=0.004):
    """A bank of decaying partials: a resonator being hit. Higher partials
    decay faster, and each is detuned slightly so they shimmer.
    """
    out = np.zeros(n)
    for i, (r, a) in enumerate(zip(ratios, amps)):
        fi = f * r * (1.0 + detune * (i - len(ratios) / 2.0))
        out += sine(fi, n) * env_pluck(n, decay, curve0 * (spread ** i)) * a
    return out


def zap(f0, f1, n, q=7.0, cut=2.6, wave="saw", drive=1.6):
    """A rich waveform swept down through a resonant lowpass. `cut` is the
    filter's corner relative to the oscillator; above 1 it opens onto the
    harmonics.
    """
    src = saw(f0, n, f1) if wave == "saw" else square(f0, n, f1, duty=0.42)
    out = moving_lowpass(src, f0 * cut, max(60.0, f1 * cut), q=q)
    return soft_clip(out, drive)


def air(n, gen, f0, f1, q=6.0, amount=1.0):
    """Noise through a resonant moving filter: a whistle rather than a hiss."""
    return moving_lowpass(noise(n, gen), f0, f1, q=q) * amount


def loudness(x):
    """RMS of the loudest 100ms window, or of the whole cue if it is shorter.
    What `finish` normalises to.
    """
    w = min(x.shape[0], n_of(0.100))
    if w >= x.shape[0]:
        return float(np.sqrt(np.mean(x ** 2)))
    # Cheap sliding RMS on the squared signal.
    sq = np.convolve(x ** 2, np.ones(w) / w, mode="valid")
    return float(np.sqrt(sq.max()))


# ---------------------------------------------------------------------------
# The cues
#
# Each returns mono float samples, finished at its own loudness before
# `audio_functions` applies its gain.
# ---------------------------------------------------------------------------

def cue_shot_soft(g):
    """The shot cue for round bullets and any shape `sfx_for_shape` doesn't
    list: a resonant downward sweep over a struck body, with a little
    inharmonic sparkle. The most frequent sound, so the shortest.
    """
    n = n_of(0.130)
    core = zap(760, 165, n, q=8.0, cut=2.4, drive=1.9) * env_pluck(n, 0.85, 4.2)
    body = struck(196, n, ratios=ARCANE, decay=0.75, curve0=4.0) * 0.55
    spark = ringmod(sine(1180, n, 820), sine(1790, n)) \
        * env_pluck(n, 0.30, 12.0) * 0.22
    sub = sine(96, n, 62) * env_pluck(n, 0.7, 5.0) * 0.45
    return finish(soft_clip(mix(core, body, spark, sub), 1.5), 0.20)


def cue_shot_sharp(g):
    """The shot cue for the thin shapes (see `sfx_for_shape`): a high
    inharmonic resonator struck hard and swept.
    """
    n = n_of(0.115)
    ring = struck(1240, n, ratios=ARCANE, amps=(1.0, 0.62, 0.40, 0.24, 0.14),
                  decay=0.62, curve0=4.2)
    edge = zap(2900, 940, n, q=9.0, cut=1.9, wave="square", drive=1.7) \
        * env_pluck(n, 0.42, 7.0) * 0.85
    chiff = air(n, g, 5200, 2400, q=7.5, amount=0.40) * env_pluck(n, 0.22, 16.0)
    return finish(soft_clip(mix(ring, edge, chiff), 1.6), 0.22)


def cue_shot_heavy(g):
    """The shot cue for the big angular shapes (see `sfx_for_shape`): low
    partials on the `STONE` ratios, a sub, and a resonant sweep.
    """
    n = n_of(0.230)
    body = struck(146, n, ratios=STONE, amps=(1.0, 0.60, 0.34, 0.18),
                  decay=1.15, curve0=2.6)
    core = zap(430, 108, n, q=7.5, cut=2.2, drive=2.0) * env_pluck(n, 1.0, 3.4)
    sub = sine(74, n, 52) * env_pluck(n, 1.1, 2.8) * 0.7
    grit = air(n, g, 1500, 300, q=5.0, amount=0.30) * env_ad(n, 0.001, 0.16, 5.0)
    return finish(soft_clip(mix(body, core, sub, grit), 1.7), 0.24)


def cue_pshot(g):
    """Szuix's shot. It plays constantly, so it is thin: a resonator, with a
    sweep underneath to give it direction.
    """
    n = n_of(0.075)
    tip = struck(2080, n, ratios=(1.0, 2.41, 3.87, 5.62),
                 amps=(1.0, 0.50, 0.24, 0.11), decay=0.48, curve0=4.6)
    core = zap(1650, 900, n, q=6.5, cut=1.8, drive=1.15)         * env_pluck(n, 0.40, 8.5) * 0.50
    return finish(mix(tip, core), 0.115)


def cue_graze(g):
    """Grazing a bullet: a high, bright ping."""
    n = n_of(0.150)
    ping = struck(3520, n, ratios=(1.0, 2.0, 3.01, 4.72),
                  amps=(1.0, 0.62, 0.36, 0.18), decay=0.95, curve0=3.0)
    low = struck(1760, n, ratios=(1.0, 2.41, 3.87), amps=(1.0, 0.34, 0.16),
                 decay=0.55, curve0=4.5) * 0.30
    chiff = air(n, g, 6800, 4600, q=8.0, amount=0.26) * env_pluck(n, 0.18, 18.0)
    return finish(mix(ping, low, chiff), 0.156)


def cue_item(g):
    """A shard collected: a small bright bell, meant to bear repeating many
    times in a few seconds.
    """
    n = n_of(0.135)
    bell = struck(1046, n, ratios=(1.0, 2.76, 5.40), amps=(1.0, 0.42, 0.18),
                  decay=0.85, curve0=3.4)
    up = sine(1568, n, 2093) * env_pluck(n, 0.30, 9.0) * 0.30
    return finish(mix(bell, up), 0.145)


def cue_enemy_hit(g):
    """A player shot landing: a short damped resonance with a low centre."""
    n = n_of(0.055)
    thud = struck(280, n, ratios=STONE, amps=(1.0, 0.48, 0.24, 0.12),
                  decay=0.30, curve0=6.0)
    tick = air(n, g, 2200, 900, q=5.0, amount=0.45) * env_pluck(n, 0.20, 14.0)
    return finish(soft_clip(mix(thud, tick), 1.4), 0.085)


def cue_enemy_die(g):
    """Fodder destroyed: a stone resonator struck hard and detuned, a swept
    crack, and a sub.
    """
    n = n_of(0.290)
    shell = struck(210, n, ratios=STONE, amps=(1.0, 0.66, 0.40, 0.22),
                   decay=0.85, curve0=3.0, detune=0.02)
    crack = zap(900, 120, n, q=6.5, cut=2.0, drive=2.2) * env_pluck(n, 0.7, 4.4)
    burst = air(n, g, 4200, 400, q=3.5, amount=0.55) * env_ad(n, 0.001, 0.26, 3.6)
    sub = sine(88, n, 54) * env_pluck(n, 1.0, 3.2) * 0.6
    return finish(soft_clip(mix(shell, crack, burst, sub), 1.7), 0.30)


def cue_hit(g):
    """Szuix hit: loud and low. A detuned low resonator under a falling sweep,
    with a bright sting on the front so it registers first.
    """
    n = n_of(0.480)
    # Decays fast, so it doesn't sit on the mix while the player dodges.
    low = struck(82, n, ratios=STONE, amps=(1.0, 0.70, 0.40, 0.20),
                 decay=0.85, curve0=2.6, detune=0.03)
    fall = zap(520, 58, n, q=7.0, cut=2.2, drive=2.4) * env_pluck(n, 0.9, 3.0)
    boom = air(n, g, 900, 70, q=2.2, amount=0.85) * env_ad(n, 0.001, 0.44, 2.8)
    sting = struck(1480, n, ratios=ARCANE, decay=0.26, curve0=6.0) * 0.42
    return finish(soft_clip(mix(low, fall, boom, sting), 2.0), 0.50)


def cue_bomb(g):
    """The sigil. The transient is at sample zero, because the cue answers a
    key press: a low crack, then a sweep and ringing over `BOMB_GROW` while the
    wave travels.
    """
    n = n_of(0.950)

    m = n_of(0.620)
    crack = pad_to(soft_clip(mix(
        air(m, g, 3000, 62, q=2.4, amount=1.0) * env_ad(m, 0.0005, 0.58, 3.6),
        zap(430, 44, m, q=8.0, cut=2.0, drive=2.4) * env_pluck(m, 1.0, 2.8),
        struck(66, m, ratios=STONE, decay=1.3, curve0=2.0, detune=0.03) * 0.9),
        2.0), n)

    swell = air(n, g, 340, 5400, q=3.0, amount=0.55) * env_swell(n, 0.34, 2.6)

    k = n_of(0.640)
    shimmer = at(struck(880, k, ratios=ARCANE,
                        amps=(1.0, 0.60, 0.38, 0.22, 0.12),
                        decay=1.1, curve0=2.8) * 0.55, 0.09, n)
    return finish(mix(crack, swell, shimmer), 0.52)


def cue_laser_charge(g):
    """A beam's warning line: a resonant rise that reads as rising from its
    first fifty milliseconds.
    """
    n = n_of(0.560)
    tone = mix(zap(150, 880, n, q=9.0, cut=2.0, drive=1.5) * 0.85,
               saw(225, n, 1320) * 0.30)
    tone *= env_ad(n, 0.10, 0.46, curve=1.0)
    hiss = air(n, g, 420, 3600, q=6.0, amount=0.34) * env_ad(n, 0.14, 0.40, 1.1)
    return finish(soft_clip(mix(tone, hiss), 1.4), 0.26)


def cue_laser_fire(g):
    """A beam arriving: a hard resonant front and a short body, with no tail
    (the beam itself lasts much longer than the cue).
    """
    n = n_of(0.380)
    front = air(n, g, 6200, 800, q=4.0, amount=0.9) * env_ad(n, 0.001, 0.34, 3.8)
    body = mix(zap(340, 245, n, q=8.5, cut=2.3, drive=2.1) * 0.9,
               struck(170, n, ratios=STONE, decay=0.8, curve0=3.2) * 0.5)
    body *= env_ad(n, 0.003, 0.32, curve=2.4)
    return finish(soft_clip(mix(front, body), 1.8), 0.36)


def cue_ward_close(g):
    """The Hex's seal closing and going live: a struck fifth on the `ARCANE`
    ratios.
    """
    n = n_of(0.620)
    a = struck(174.61, n, ratios=ARCANE, amps=(1.0, 0.62, 0.38, 0.22, 0.12),
               decay=1.3, curve0=2.2)
    b = struck(261.63, n, ratios=ARCANE, amps=(1.0, 0.50, 0.28, 0.15, 0.08),
               decay=1.0, curve0=2.6) * 0.62
    lock = air(n, g, 2600, 900, q=7.0, amount=0.32) * env_pluck(n, 0.30, 8.0)
    return finish(soft_clip(mix(a, b, lock), 1.4), 0.30)


def cue_ward_scatter(g):
    """The Hex's red ward thrown outward: a low crack opening into a wash."""
    n = n_of(0.720)
    m = n_of(0.34)
    crack = pad_to(soft_clip(mix(
        air(m, g, 2600, 240, q=2.6, amount=0.9) * env_ad(m, 0.0005, 0.31, 3.8),
        struck(118, m, ratios=STONE, decay=1.0, curve0=2.4, detune=0.035),
        zap(300, 70, m, q=7.0, cut=2.1, drive=2.2) * 0.8), 1.9), n)
    wash = air(n, g, 1800, 460, q=2.0, amount=0.45) * env_ad(n, 0.02, 0.66, 2.2)
    return finish(mix(crack, wash), 0.40)


def cue_ward_pull(g):
    """The Hex's blue ward collapsing to a point: a rising, tightening tone
    that resolves onto `snd_ward_burst`. It lasts `HEX_IMPLODE` frames,
    hard-coded below as `108 / 60.0`, so change the two together.
    """
    n = n_of(108 / 60.0)
    rise = mix(zap(74, 560, n, q=11.0, cut=2.1, drive=1.6) * 0.9,
               saw(111, n, 840) * 0.28,
               sine(55, n, 420) * 0.45)
    rise *= env_ad(n, 0.22, 1.62, curve=0.5)

    # Air dragged inward: a resonant filter opening as the tone climbs, so the
    # cue brightens as it rises.
    drag = air(n, g, 240, 4400, q=7.0, amount=0.34) * env_ad(n, 0.30, 1.52, 0.65)
    return finish(soft_clip(mix(rise, drag), 1.5), 0.30)


def cue_ward_burst(g):
    """The Hex's seal detonating, at the top of `cue_ward_pull`'s climb: the
    loudest cue in the attack.
    """
    n = n_of(1.300)
    m = n_of(0.75)
    impact = pad_to(soft_clip(mix(
        air(m, g, 3400, 54, q=2.4, amount=1.0) * env_ad(m, 0.0005, 0.70, 4.0),
        zap(520, 42, m, q=8.0, cut=2.1, drive=2.4) * env_pluck(m, 1.0, 3.0),
        struck(58, m, ratios=STONE, decay=1.4, curve0=2.0, detune=0.03) * 1.0),
        2.1), n)

    shards = at(struck(1174.7, n_of(0.85), ratios=ARCANE,
                       amps=(1.0, 0.58, 0.34, 0.20, 0.10),
                       decay=0.95, curve0=3.0) * 0.42, 0.02, n)
    tail = air(n, g, 1300, 140, q=2.0, amount=0.30) * env_ad(n, 0.03, 1.10, 3.2)
    return finish(mix(impact, shards, tail), 0.52)


def cue_spell_declare(g):
    """A spell being named, during `BOSS_SPELL_LEAD`: struck arcane resonators
    over a low swell.
    """
    n = n_of(1.250)
    swell = air(n, g, 90, 1500, q=2.2, amount=0.55) * env_swell(n, 0.34, 1.9)

    bells = np.zeros(n)
    for i, (f, delay, amp) in enumerate(((196.0, 0.00, 1.00),
                                         (294.0, 0.060, 0.80),
                                         (392.0, 0.120, 0.62),
                                         (588.0, 0.180, 0.42))):
        k = n_of(1.10 - i * 0.13)
        bells = mix(bells, at(struck(f, k, ratios=ARCANE,
                                     amps=(1.0, 0.58, 0.34, 0.20, 0.11),
                                     decay=1.3, curve0=2.2) * amp, delay, n))

    low = struck(98, n, ratios=STONE, decay=1.5, curve0=1.8, detune=0.02) * 0.55
    return finish(soft_clip(mix(swell, bells * 0.9, low), 1.4), 0.44)


def cue_spell_break(g):
    """An attack broken: rising, bright and short."""
    n = n_of(0.680)
    out = np.zeros(n)
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        k = n_of(0.46 - i * 0.05)
        v = struck(f, k, ratios=(1.0, 2.0, 3.01, 4.72),
                   amps=(1.0, 0.55, 0.30, 0.15), decay=0.85, curve0=3.2)
        out = mix(out, at(v * (0.9 - i * 0.08), 0.050 * i, n))
    burst = air(n, g, 5000, 700, q=3.0, amount=0.45) * env_ad(n, 0.001, 0.32, 3.8)
    return finish(soft_clip(mix(out, burst), 1.3), 0.38)


def cue_spell_survive(g):
    """An attack that ran out its clock (no capture): falling, dull and
    short."""
    n = n_of(0.540)
    out = np.zeros(n)
    for i, f in enumerate((392.0, 329.63, 261.63)):
        k = n_of(0.40 - i * 0.04)
        v = struck(f, k, ratios=STONE, amps=(1.0, 0.45, 0.22, 0.10),
                   decay=0.80, curve0=3.4)
        v = lowpass(v, 1500)
        out = mix(out, at(v * (0.85 - i * 0.10), 0.072 * i, n))
    dust = air(n, g, 900, 320, q=2.0, amount=0.24) * env_ad(n, 0.01, 0.44, 2.8)
    return finish(mix(out, dust), 0.26)


def cue_capture(g):
    """A spell captured (broken with no hit and no sigil). It plays over
    `snd_spell_break`, so it is thin and high.
    """
    n = n_of(0.840)
    out = np.zeros(n)
    for i, f in enumerate((1567.98, 2093.0, 2637.02)):
        k = n_of(0.66 - i * 0.08)
        v = struck(f, k, ratios=(1.0, 2.76, 5.40), amps=(1.0, 0.38, 0.16),
                   decay=1.0, curve0=3.0)
        out = mix(out, at(v * (0.8 - i * 0.14), 0.078 * i, n))
    return finish(out, 0.24)


def cue_boss_appear(g):
    """A boss arriving: a low rise that resolves onto a hit."""
    n = n_of(1.100)
    rumble = air(n, g, 58, 520, q=2.4, amount=0.9) * env_swell(n, 0.62, 2.6)
    rise = mix(zap(52, 172, n, q=9.0, cut=2.0, drive=1.8) * 0.85,
               struck(64, n, ratios=STONE, decay=1.6, curve0=1.7,
                      detune=0.03) * 0.5)
    rise *= env_ad(n, 0.30, 0.70, curve=1.2)

    m = n_of(0.520)
    hit = at(soft_clip(mix(
        air(m, g, 1800, 110, q=2.2, amount=0.9) * env_ad(m, 0.001, 0.48, 3.0),
        struck(96, m, ratios=STONE, decay=1.2, curve0=2.2, detune=0.03),
        zap(300, 54, m, q=7.5, cut=2.0, drive=2.2)
        * env_pluck(m, 0.85, 3.2) * 0.8), 1.9) * 0.95,
        0.55, n)
    return finish(mix(rumble, rise, hit), 0.46)


def cue_boss_die(g):
    """A boss beaten, filling the pause before the result panel
    (`win_pending`).

    Only the impact is saturated: `soft_clip` over the whole mix lifts the
    tail, so the cue stops decaying.
    """
    n = n_of(1.750)

    m = n_of(0.950)
    impact = pad_to(soft_clip(mix(
        air(m, g, 2400, 46, q=2.4, amount=1.0) * env_ad(m, 0.0005, 0.86, 4.2),
        zap(420, 36, m, q=8.5, cut=2.0, drive=2.4) * env_pluck(m, 1.0, 3.2),
        struck(52, m, ratios=STONE, decay=1.6, curve0=1.8, detune=0.035) * 1.1),
        2.0), n)

    shimmer = np.zeros(n)
    for i, f in enumerate((196.0, 261.63, 392.0, 523.25)):
        k = n_of(1.25 - i * 0.16)
        shimmer = mix(shimmer, at(
            struck(f, k, ratios=ARCANE, amps=(1.0, 0.58, 0.34, 0.19, 0.10),
                   decay=1.35, curve0=2.1) * (0.46 - i * 0.07),
            0.26 + 0.095 * i, n))

    tail = air(n, g, 950, 120, q=2.0, amount=0.24) * env_ad(n, 0.02, 1.40, 3.8)
    return finish(mix(impact, shimmer, tail), 0.56)


def cue_player_down(g):
    """The run lost: falling, and unresolved."""
    n = n_of(1.200)
    fall = mix(zap(390, 42, n, q=8.0, cut=2.1, drive=1.9) * 0.9,
               struck(74, n, ratios=STONE, decay=1.5, curve0=1.8,
                      detune=0.03) * 0.7)
    fall *= env_ad(n, 0.005, 1.14, curve=1.8)
    wash = air(n, g, 1400, 90, q=2.0, amount=0.35) * env_ad(n, 0.001, 1.08, 2.2)
    return finish(soft_clip(mix(fall, wash), 1.6), 0.40)


def cue_ui_move(g):
    """The cursor moving: short, soft, and pitched below the confirm (it
    repeats while a key is held).
    """
    n = n_of(0.075)
    v = struck(620, n, ratios=(1.0, 2.41, 3.87), amps=(1.0, 0.35, 0.15),
               decay=0.42, curve0=5.5)
    return finish(lowpass(v, 3400), 0.15)


def cue_ui_select(g):
    """Confirm: two notes rising."""
    n = n_of(0.260)
    a = struck(660, n_of(0.13), ratios=ARCANE, amps=(1.0, 0.45, 0.22, 0.10, 0.05),
               decay=0.60, curve0=3.6)
    b = struck(990, n_of(0.20), ratios=ARCANE, amps=(1.0, 0.50, 0.26, 0.13, 0.06),
               decay=0.85, curve0=3.2)
    return finish(mix(pad_to(a, n), at(b * 0.95, 0.058, n)), 0.26)


def cue_ui_back(g):
    """Leaving a screen. The confirm's interval, inverted."""
    n = n_of(0.230)
    a = struck(660, n_of(0.11), ratios=ARCANE, amps=(1.0, 0.40, 0.18, 0.08, 0.04),
               decay=0.52, curve0=4.0)
    b = struck(440, n_of(0.18), ratios=ARCANE, amps=(1.0, 0.44, 0.20, 0.10, 0.05),
               decay=0.80, curve0=3.4)
    return finish(lowpass(mix(pad_to(a, n), at(b * 0.9, 0.052, n)), 3600), 0.22)


def cue_ui_deny(g):
    """A refusal, such as a locked stage: low and flat, with no interval."""
    n = n_of(0.250)
    v = mix(struck(118, n, ratios=STONE, amps=(1.0, 0.50, 0.24, 0.10),
                   decay=0.62, curve0=3.2, detune=0.03),
            square(147, n, 136, duty=0.5) * 0.35)
    v *= env_ad(n, 0.004, 0.22, curve=2.6)
    return finish(soft_clip(lowpass(v, 1200), 1.4), 0.24)


def cue_pause(g):
    """The pause menu opening or closing: one muted thunk."""
    n = n_of(0.170)
    v = struck(196, n, ratios=STONE, amps=(1.0, 0.44, 0.20, 0.09),
               decay=0.55, curve0=3.6)
    v = lowpass(v, 1600)
    click = air(n_of(0.016), g, 2600, 1200, q=5.0, amount=0.45) \
        * env_pluck(n_of(0.016), 0.4, 10.0)
    return finish(mix(v, pad_to(click, n)), 0.20)


# The set, in the order the preview lays them out (grouped by use).
CUES = (
    ("snd_shot_soft", cue_shot_soft),
    ("snd_shot_sharp", cue_shot_sharp),
    ("snd_shot_heavy", cue_shot_heavy),
    ("snd_laser_charge", cue_laser_charge),
    ("snd_laser_fire", cue_laser_fire),

    ("snd_ward_close", cue_ward_close),
    ("snd_ward_scatter", cue_ward_scatter),
    ("snd_ward_pull", cue_ward_pull),
    ("snd_ward_burst", cue_ward_burst),

    ("snd_pshot", cue_pshot),
    ("snd_graze", cue_graze),
    ("snd_item", cue_item),
    ("snd_enemy_hit", cue_enemy_hit),
    ("snd_enemy_die", cue_enemy_die),

    ("snd_hit", cue_hit),
    ("snd_bomb", cue_bomb),
    ("snd_player_down", cue_player_down),

    ("snd_boss_appear", cue_boss_appear),
    ("snd_spell_declare", cue_spell_declare),
    ("snd_spell_break", cue_spell_break),
    ("snd_spell_survive", cue_spell_survive),
    ("snd_capture", cue_capture),
    ("snd_boss_die", cue_boss_die),

    ("snd_ui_move", cue_ui_move),
    ("snd_ui_select", cue_ui_select),
    ("snd_ui_back", cue_ui_back),
    ("snd_ui_deny", cue_ui_deny),
    ("snd_pause", cue_pause),
)


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

    import struct
    import wave
    with wave.open(path, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(RATE)
        fh.writeframes(b"".join(
            struct.pack("<h", int(round(max(-1.0, min(1.0, s)) * 32767)))
            for s in strip))


def write_preview_png(built, path):
    from PIL import Image, ImageDraw

    try:
        import art_common
        font = art_common.font(art_common.SPECTRAL, 12)
        small = art_common.font(art_common.SPECTRAL, 10)
    except Exception:
        font = small = None

    cw, ch, pad = 300, 96, 12
    cols = 4
    rows = (len(built) + cols - 1) // cols
    W = cols * (cw + pad) + pad
    H = rows * (ch + pad + 16) + pad
    img = Image.new("RGB", (W, H), (16, 17, 28))
    d = ImageDraw.Draw(img)

    for i, (name, samples) in enumerate(built):
        x0 = pad + (i % cols) * (cw + pad)
        y0 = pad + (i // cols) * (ch + pad + 16)
        d.rectangle([x0, y0, x0 + cw, y0 + ch], fill=(24, 26, 42))

        # The waveform, min/max per column, on a common time base so the
        # lengths can be compared.
        span = max(s.shape[0] for _, s in built)
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
        if font:
            d.text((x0, y0 + ch + 2), label, font=small, fill=(180, 186, 210))
        else:
            d.text((x0, y0 + ch + 2), label, fill=(180, 186, 210))

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
    for name, fn in CUES:
        samples = fn(rng_for(name))
        built.append((name, samples))
        if not args.preview:
            gm_new.sound(name, samples, rate=RATE, folder=FOLDER)
        pk = float(np.max(np.abs(samples)))
        print("  %-18s %6.0fms  rms %.3f  peak %.2f%s"
              % (name, samples.shape[0] * 1000.0 / RATE,
                 loudness(samples), pk,
                 "  <- peak-limited" if pk >= PEAK_CEILING - 1e-4 else ""))

    bad = check_envelopes(built)

    write_preview_wav(built, os.path.join(PREVIEW, "sfx.wav"))
    write_preview_png(built, os.path.join(PREVIEW, "sfx.png"))
    total = sum(s.shape[0] for _, s in built) * 2
    print("\n%d cues, %.1fs, %.0f KB of PCM" % (
        len(built), sum(s.shape[0] for _, s in built) / float(RATE),
        total / 1024.0))
    print("preview: tools/_preview/sfx.wav and sfx.png")
    if bad:
        print("")
        print("%d cue(s) do not decay -- see above" % len(bad))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
