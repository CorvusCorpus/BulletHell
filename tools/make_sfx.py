#!/usr/bin/env python3
"""Synthesise every sound effect in the game, and register them.

These are synthesised rather than sourced because it is the only way to get a
complete set into the project in one pass without hunting licences -- not
because generated audio is better than recorded audio. It is not. **Every one
of these is a placeholder in the same sense `tools/make_boss.py` is**, and the
contract a replacement has to keep is small: a mono 16-bit WAV of roughly the
same length at roughly the same peak, dropped in `sounds/<name>/<name>.wav`
with the duration in the `.yy` updated. Nothing in `audio_functions` knows or
cares where a cue came from.

There is no music. This file is `sfx` and it means it -- a cue is at most a
second and a half, dry, and mono.

    python tools/make_sfx.py            # write every sound + the preview
    python tools/make_sfx.py --preview  # only the preview, touch no resource

# What the set is built to

**Short, and dry.** A tail is a voice that outlives its own event. At the rate
this game fires, a shot cue with a 400ms tail is not a shot cue, it is a drone
-- and the drone is loudest exactly when the screen is fullest, which is when
the player most needs to hear the one cue that matters. Nothing here reverbs,
and the longest shot cue is 110ms.

**Narrow, and in different bands.** Anything in this set can sound on the same
frame as anything else, so two cues that share a band are two cues that mask
each other. The shots live at 400-2500Hz, the graze sits above them at 3-5kHz
where nothing else goes, the player's own shot is deliberately thinner than the
enemy's, and the ceremony is the only thing allowed below 200Hz.

**Levelled here, not at the call site.** Every cue is normalised and then
scaled to a designed peak, so the gains in `audio_functions` mean what they
say. A cue that is quiet because its waveform happens to be quiet is a cue
whose mix cannot be reasoned about -- and it is the half a replacement set has
to match, since the mixer's gains are tuned against these peaks.

**Deterministic.** Every cue's noise comes from a seed derived from its own
name, so re-running this writes byte-identical WAVs and produces no diff.

# Where the design comes from

Touhou's, in shape rather than in content. What that series gets right and
what is borrowed: cues are tiny, they are *dry*, they are all clearly
different from each other, and the enemy shot is the quietest thing in the
game despite being the most frequent. What is not borrowed is any particular
sound.

**The one thing sound design cannot fix is how often a cue is asked for**, and
that is not here. See `audio_functions`: a hundred bullets fired on one frame
request one cue and it sounds once, which is a property of the API rather than
a rule anybody has to remember.
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

RATE = 44100
FOLDER = "Sounds"


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
    """Attack-decay, in seconds. `curve` is how sharply the decay falls.

    Exponential rather than linear, because a linear decay to zero reads as a
    sound being *switched off* at the end -- which is audible at these lengths
    and is what makes a short cue sound like a clipped sample.
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
    """Instant attack, exponential fall across the whole cue. A struck thing."""
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
    """A triangle. Softer than a square and richer than a sine -- what most of
    the pitched cues here are made of, because a pure sine has no edge to it
    and disappears the moment anything else is playing."""
    p = sweep(f0, f1 if f1 is not None else f0, n) / (2 * np.pi)
    return 2 * np.abs(2 * (p - np.floor(p + 0.5))) - 1


def square(f0, n, f1=None, duty=0.5):
    p = sweep(f0, f1 if f1 is not None else f0, n) / (2 * np.pi)
    return np.where((p - np.floor(p)) < duty, 1.0, -1.0)


def noise(n, gen):
    return gen.standard_normal(n)


def biquad(x, b0, b1, b2, a1, a2):
    """Direct form I. Written out rather than reached for, because scipy is not
    installed on this machine and a filter is thirty lines."""
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
    """A lowpass whose corner slides from `f0` to `f1` across the sound.

    This is what makes a noise burst read as an *event* rather than as static:
    a puff of air, a thing igniting, a wall of light coming on. Coefficients
    are recomputed every 64 samples, which is far finer than the ear can
    resolve at these lengths and about seven hundred times cheaper than every
    sample.
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
    """Saturation. Adds the harmonics that make a synthesised hit sound struck
    rather than played, and guarantees the result is bounded on the way."""
    return np.tanh(x * drive) / math.tanh(drive) if drive > 0 else x


def finish(x, peak):
    """Take the clicks off both ends, then normalise to a designed peak.

    A waveform that starts or stops at a non-zero sample is a step, and a step
    is a click -- audible on every one of these, and worst on the quietest,
    since a click has no level of its own.

    **The two ends want very different fades and giving them the same one was
    a bug.** At two milliseconds each, the fade-in was eating the attack of
    every cue whose peak is at sample zero -- which is every plucked one --
    and `snd_enemy_hit` came out at 0.08 against a designed 0.26. A 26ms click
    is *all* attack; blunting the first eight per cent of it is blunting the
    thing itself. So the head gets 0.4ms, which is enough to kill the step and
    short enough to be inaudible as an attack, and the tail keeps 3ms, where
    nothing is happening anyway.

    **And the normalising happens after**, so the peak a cue is finished at is
    the peak it actually has. Scaling first and fading second means the number
    in the call is a number the file does not hold, which is the half of this
    that `audio_functions` tunes its gains against.
    """
    head = min(n_of(0.0004), x.shape[0] // 2)
    tail = min(n_of(0.003), x.shape[0] // 2)
    if head > 1:
        x[:head] *= np.linspace(0, 1, head)
    if tail > 1:
        x[-tail:] *= np.linspace(1, 0, tail)

    m = float(np.max(np.abs(x)))
    if m > 0:
        x = x / m
    return x * peak


# ---------------------------------------------------------------------------
# The cues
#
# Each returns mono float samples. The peak each is finished at is its place in
# the mix **as drawn**, before `audio_functions` applies its own gain -- the
# two are deliberately separate, so a cue can be re-levelled without touching
# the waveform and re-drawn without touching the mix.
# ---------------------------------------------------------------------------

def cue_shot_soft(g):
    """A round bullet leaving. The most frequent sound in the game, so the
    quietest: a soft filtered puff with a fast downward sweep, and no pitched
    component at all -- a note repeated fifteen times a second becomes a
    melody, and a melody is something the ear tracks instead of the field."""
    n = n_of(0.075)
    body = moving_lowpass(noise(n, g), 2600, 620, q=1.1)
    body *= env_ad(n, 0.001, 0.070, curve=4.2)
    thump = tri(300, n, 150) * env_pluck(n, 0.4, 7.0) * 0.35
    return finish(mix(body, thump), 0.50)


def cue_shot_sharp(g):
    """A needle, a dart, a kunai. Brighter and shorter than the round one, and
    band-limited rather than swept: it is a *tick*, and the whole of what makes
    it distinguishable from the puff is where it sits, not how loud it is."""
    n = n_of(0.048)
    body = bandpass(noise(n, g), 3200, q=1.6)
    body *= env_pluck(n, 0.5, 9.0)
    edge = square(1900, n, 1200, duty=0.32) * env_pluck(n, 0.3, 16.0) * 0.30
    return finish(mix(body, edge), 0.46)


def cue_shot_heavy(g):
    """A rune, a crystal, a card -- the shapes drawn big. Lower, with a body,
    and the only shot cue with any weight to it, because the pattern it belongs
    to is the one with fewer and larger bullets in it."""
    n = n_of(0.110)
    body = moving_lowpass(noise(n, g), 1400, 260, q=1.3)
    body *= env_ad(n, 0.002, 0.105, curve=3.4)
    low = tri(190, n, 96) * env_pluck(n, 0.9, 4.4) * 0.75
    return finish(soft_clip(mix(body, low), 1.4), 0.58)


def cue_ward_close(g):
    """A seal finished and going live. Five traces land their last rune on the
    same frame and the figure starts to turn -- so this resolves rather than
    stops: a struck fifth with a low under it, saying the shape is now a thing
    rather than a drawing."""
    n = n_of(0.520)
    a = mix(sine(174.61, n) * env_pluck(n, 1.0, 3.0),
            sine(261.63, n) * env_pluck(n, 0.8, 3.8) * 0.7,
            sine(349.23, n) * env_pluck(n, 0.5, 5.4) * 0.4)
    ring = bandpass(noise(n, g), 2800, q=3.0) * env_pluck(n, 0.35, 7.0) * 0.30
    return finish(mix(a, ring), 0.60)


def cue_ward_scatter(g):
    """The red ward thrown outward. Stone coming apart rather than glass
    breaking -- the beads keep going and are outrun rather than dodged, so this
    is a low crack opening into a wash rather than a bright shatter that would
    promise something sharper than what arrives."""
    n = n_of(0.680)
    crack = pad_to(soft_clip(mix(
        moving_lowpass(noise(n_of(0.30), g), 2400, 260, q=1.2)
        * env_ad(n_of(0.30), 0.0005, 0.28, 4.0),
        tri(210, n_of(0.30), 70) * env_pluck(n_of(0.30), 0.8, 4.2) * 0.9), 1.5), n)
    wash = moving_lowpass(noise(n, g), 1600, 500, q=0.9)
    wash *= env_ad(n, 0.02, 0.62, curve=2.4) * 0.42
    return finish(mix(crack, wash), 0.72)


def cue_ward_pull(g):
    """The blue ward collapsing to a point.

    **This is a telegraph, not a reaction, and it is the only cue in the set
    written to a frame count.** `HEX_IMPLODE` is 108 frames -- 1.80 seconds --
    and the collapse's whole difficulty is that its only cue is the ward
    beginning to move, which `HEX_IMPLODE_RAMP` deliberately makes gentle:
    a quarter of a pixel a frame for the first fifth of a second, so a player
    reading it correctly still finds out about the collapse from the collapse.

    A rising, tightening tone that arrives at the top exactly as the ward
    reaches the middle says the same thing a second and a half earlier, and it
    says it without spending a single pixel of the field. That is the trade the
    ramp could not make: a visual cue big enough to read is a visual cue that
    has already moved the ward.

    So it is 1.80 seconds and it resolves onto `snd_ward_burst`. Change
    `HEX_IMPLODE` and this wants changing with it -- which is why the number is
    written here rather than left to be noticed."""
    n = n_of(108 / 60.0)
    rise = mix(tri(88, n, 620) * 0.8, tri(132, n, 930) * 0.45,
               sine(66, n, 465) * 0.5)
    rise *= env_ad(n, 0.22, 1.60, curve=0.55)

    # Air dragged inward with it: a lowpass opening as the tone climbs, so the
    # cue gets *brighter* as well as higher. Pitch alone reads as one thing
    # moving; both together read as everything moving.
    air = moving_lowpass(noise(n, g), 260, 4200, q=1.3)
    air *= env_ad(n, 0.30, 1.50, curve=0.7) * 0.34
    return finish(mix(rise, air), 0.66)


def cue_ward_burst(g):
    """The seal detonating. What `cue_ward_pull` has been climbing toward, so
    it lands on the downbeat and is the loudest thing in the attack -- seven
    kinds of debris leave on this frame and the player is either outside the
    ring or is not."""
    n = n_of(1.250)
    impact = pad_to(soft_clip(mix(
        moving_lowpass(noise(n_of(0.70), g), 3200, 52, q=1.3)
        * env_ad(n_of(0.70), 0.0005, 0.66, 4.4),
        tri(340, n_of(0.70), 40) * env_pluck(n_of(0.70), 0.8, 3.4) * 1.1), 1.7), n)

    shards = np.zeros(n)
    for i, f in enumerate((1174.7, 1567.98, 1975.5)):
        k = n_of(0.80 - i * 0.12)
        shards = mix(shards, at(sine(f, k) * env_pluck(k, 0.9, 4.2)
                                * (0.34 - i * 0.07), 0.02 + 0.045 * i, n))

    tail = moving_lowpass(noise(n, g), 1100, 150, q=1.0)
    tail *= env_ad(n, 0.03, 1.05, curve=3.4) * 0.26
    return finish(mix(impact, shards, tail), 0.98)


def cue_pshot(g):
    """Szuix's own bolt. **Thinner than anything the enemy fires**, which is
    the same decision `pshot_draw` makes in pixels: the player's shots are
    constant and must never be mistaken for something that can hurt. Two
    hundred milliseconds of this a second is the test it has to pass."""
    n = n_of(0.042)
    body = tri(1250, n, 720) * env_pluck(n, 0.42, 11.0)
    air = highpass(noise(n, g), 2600) * env_pluck(n, 0.25, 18.0) * 0.30
    return finish(mix(body, air), 0.30)


def cue_graze(g):
    """Passing a bullet. **Above everything else in the set**, at 3-5kHz where
    nothing else goes, because it is the one cue that has to cut through a full
    screen -- it is the game's only reward for nerve, and a reward nobody can
    hear during the moment that earned it is not one."""
    n = n_of(0.090)
    ping = (sine(3900, n) * 0.7 + sine(5850, n) * 0.3) * env_pluck(n, 0.5, 7.0)
    air = bandpass(noise(n, g), 6400, q=2.2) * env_pluck(n, 0.2, 22.0) * 0.35
    return finish(mix(ping, air), 0.42)


def cue_item(g):
    """A shard collected. Bell-ish and brief; a bomb can put fifty on the field
    at once, so this is written to be pleasant thirty times in four seconds
    rather than satisfying once."""
    n = n_of(0.080)
    a = sine(1560, n) * env_pluck(n, 0.55, 8.0)
    b = sine(2340, n) * env_pluck(n, 0.35, 13.0) * 0.5
    return finish(mix(a, b), 0.34)


def cue_enemy_hit(g):
    """A bolt connecting. Fires up to twenty times a second against a boss, so
    it is a *click* and nothing else -- no pitch, no body, 25ms. Its whole job
    is to say the shots are landing, which is a fact the player checks
    peripherally and never listens to."""
    n = n_of(0.026)
    body = bandpass(noise(n, g), 1750, q=1.1) * env_pluck(n, 0.4, 13.0)
    return finish(body, 0.26)


def cue_enemy_die(g):
    """A piece of fodder coming apart. A swept noise burst with a struck low
    under it -- these are objects rather than creatures, so what it says is
    *broken*, not hurt."""
    n = n_of(0.190)
    burst = moving_lowpass(noise(n, g), 4200, 340, q=1.0)
    burst *= env_ad(n, 0.001, 0.185, curve=3.6)
    low = tri(260, n, 78) * env_pluck(n, 0.8, 5.0) * 0.6
    ring = sine(880, n, 560) * env_pluck(n, 0.3, 12.0) * 0.25
    return finish(soft_clip(mix(burst, low, ring), 1.3), 0.62)


def cue_hit(g):
    """Szuix struck. Loud, low, and the longest thing in the game that is not
    ceremony -- being hit costs a quarter of the bar and starts a scramble, and
    the cue has to be unmistakable through whatever wall of pattern caused it."""
    n = n_of(0.420)
    boom = moving_lowpass(noise(n, g), 900, 90, q=1.2)
    boom *= env_ad(n, 0.001, 0.400, curve=3.0)
    fall = tri(420, n, 62) * env_pluck(n, 1.0, 3.4)
    sting = bandpass(noise(n, g), 2400, q=1.4) * env_pluck(n, 0.16, 16.0) * 0.5
    return finish(soft_clip(mix(boom * 1.1, fall, sting), 1.7), 0.92)


def cue_bomb(g):
    """The sigil. **The transient is at sample zero and that is the whole
    design constraint**, because this is the only cue in the game that answers
    a key the player has just pressed under pressure -- and the first version
    opened with a rising swell, which put 250ms of near-silence between X and
    anything happening. A bomb that is heard a quarter of a second late is a
    bomb the player presses twice.

    So it breaks first and blooms after: a low crack, then the sweep and the
    shimmer riding out over `BOMB_GROW` while the wave travels. Same shape as
    the drawing -- `fx_flash_screen` and `fx_shake` land on the first frame and
    the ring is what expands.
    """
    n = n_of(0.900)

    m = n_of(0.560)
    crack = pad_to(soft_clip(mix(
        moving_lowpass(noise(m, g), 2600, 70, q=1.2) * env_ad(m, 0.0005, 0.52, 3.6),
        tri(190, m, 42) * env_pluck(m, 0.9, 3.4) * 1.2), 1.7), n)

    swell = moving_lowpass(noise(n, g), 300, 5600, q=1.1)
    swell *= env_swell(n, peak=0.34, curve=2.6) * 0.55

    k = n_of(0.620)
    shimmer = at(mix(sine(1760, k) * env_pluck(k, 0.8, 3.6),
                     sine(2640, k) * env_pluck(k, 0.6, 5.0) * 0.6,
                     sine(3520, k) * env_pluck(k, 0.45, 6.5) * 0.35) * 0.50,
                 0.10, n)
    return finish(mix(crack, swell, shimmer), 0.95)


def cue_laser_charge(g):
    """A beam's warning line. **A rise, and it has to read as one from its
    first fifty milliseconds**, because the telegraph is the whole of what
    makes a wall of light fair -- a player who has not worked out that
    something is coming has not been warned."""
    n = n_of(0.520)
    tone = mix(tri(180, n, 900) * 0.7, tri(270, n, 1350) * 0.35)
    tone *= env_ad(n, 0.10, 0.42, curve=1.1)
    air = moving_lowpass(noise(n, g), 400, 3400, q=1.4)
    air *= env_ad(n, 0.14, 0.38, curve=1.2) * 0.30
    return finish(mix(tone, air), 0.52)


def cue_laser_fire(g):
    """The beam arriving. A hard front and a short lit body -- no tail, because
    the beam stands there for a second and a half and a cue that lasted as long
    would be a drone the player has to listen past."""
    n = n_of(0.340)
    front = moving_lowpass(noise(n, g), 6000, 900, q=1.1)
    front *= env_ad(n, 0.001, 0.32, curve=3.8)
    body = mix(square(310, n, 250, duty=0.42) * 0.55,
               tri(620, n, 500) * 0.4)
    body *= env_ad(n, 0.004, 0.30, curve=2.6)
    return finish(soft_clip(mix(front, body), 1.5), 0.72)


def cue_spell_declare(g):
    """A spell being named. **The only cue in the game allowed to be
    ceremonial**, because it is the only moment the game stops to say
    something -- and it has `BOSS_SPELL_LEAD` to itself, with the boss unable
    to fire and the eye card across the field. A struck cluster over a low
    swell: something old being woken up."""
    n = n_of(1.150)
    swell = moving_lowpass(noise(n, g), 90, 1400, q=1.0)
    swell *= env_swell(n, peak=0.34, curve=2.0) * 0.55

    bells = np.zeros(n)
    for i, (f, delay, amp) in enumerate(((196.0, 0.00, 1.00),
                                         (294.0, 0.055, 0.80),
                                         (392.0, 0.110, 0.65),
                                         (588.0, 0.165, 0.45),
                                         (784.0, 0.220, 0.30))):
        k = n_of(1.0 - i * 0.12)
        voice = mix(sine(f, k) * env_pluck(k, 1.0, 3.2),
                    sine(f * 2.01, k) * env_pluck(k, 0.6, 5.0) * 0.35,
                    sine(f * 3.03, k) * env_pluck(k, 0.35, 8.0) * 0.16)
        bells = mix(bells, at(voice * amp, delay, n))

    low = tri(98, n, 92) * env_ad(n, 0.02, 0.9, curve=2.2) * 0.5
    return finish(mix(swell, bells * 0.9, low), 0.86)


def cue_spell_break(g):
    """An attack broken. Rising, bright, and over quickly -- the player has
    already been handed the next attack's pause and this is the punctuation on
    the one they just beat, not an event of its own."""
    n = n_of(0.620)
    out = np.zeros(n)
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        k = n_of(0.42 - i * 0.05)
        v = mix(tri(f, k) * env_pluck(k, 0.8, 4.6),
                sine(f * 2, k) * env_pluck(k, 0.5, 7.0) * 0.35)
        out = mix(out, at(v * (0.9 - i * 0.08), 0.048 * i, n))
    burst = moving_lowpass(noise(n, g), 4800, 700, q=1.0)
    burst *= env_ad(n, 0.001, 0.30, curve=4.0) * 0.45
    return finish(mix(out, burst), 0.78)


def cue_spell_survive(g):
    """An attack that ran out its clock. **A third outcome, not a quieter
    version of the second.** A spell survived ends the attack and awards no
    capture, and telling somebody who was ground down for forty seconds the
    same thing you tell somebody who broke it would be lying about the rules
    they were playing under. Falling, dull, and short."""
    n = n_of(0.480)
    out = np.zeros(n)
    for i, f in enumerate((392.0, 329.63, 261.63)):
        k = n_of(0.36 - i * 0.04)
        v = tri(f, k) * env_pluck(k, 0.8, 5.0)
        v = lowpass(v, 1600)
        out = mix(out, at(v * (0.85 - i * 0.10), 0.070 * i, n))
    air = lowpass(noise(n, g), 900) * env_ad(n, 0.01, 0.40, curve=3.0) * 0.22
    return finish(mix(out, air), 0.58)


def cue_capture(g):
    """A spell captured -- broken with no hit and no bomb. It plays *over*
    `snd_spell_break` rather than instead of it, which is why it is thin and
    high: the break already said the attack ended, and this says the one extra
    thing, in the only band the break leaves free."""
    n = n_of(0.780)
    out = np.zeros(n)
    for i, f in enumerate((1567.98, 2093.0, 2637.02)):
        k = n_of(0.62 - i * 0.08)
        v = mix(sine(f, k) * env_pluck(k, 1.0, 3.4),
                sine(f * 1.5, k) * env_pluck(k, 0.6, 5.0) * 0.28)
        out = mix(out, at(v * (0.8 - i * 0.14), 0.075 * i, n))
    return finish(out, 0.62)


def cue_boss_appear(g):
    """A boss arriving. Low, rising, and it resolves onto a hit -- the fight
    has a name splash and an entry glide to cover, and what this has to do is
    make the two seconds before the first attack feel like weight arriving."""
    n = n_of(1.050)
    rumble = moving_lowpass(noise(n, g), 60, 520, q=1.2)
    rumble *= env_swell(n, peak=0.62, curve=2.6) * 0.9
    rise = tri(58, n, 176) * env_ad(n, 0.30, 0.68, curve=1.3) * 0.8

    m = n_of(0.480)
    hit = at(soft_clip(mix(
        moving_lowpass(noise(m, g), 1600, 120, q=1.2) * env_ad(m, 0.001, 0.46, 3.2),
        tri(220, m, 55) * env_pluck(m, 1.0, 3.0)), 1.6) * 0.9, 0.60, n)
    return finish(mix(rumble, rise, hit), 0.88)


def cue_boss_die(g):
    """A boss beaten outright. The biggest thing in the set, and the only one
    over a second and a half -- `win_pending` holds the result panel back for
    170 frames precisely so this moment is not stepped on, and the cue is what
    fills them.

    **The impact is saturated and the tail is not, and running the whole mix
    through `soft_clip` was the bug.** tanh at drive 1.6 compresses the front
    and lifts everything behind it, so what came out held an RMS of 0.65 for
    seven hundred milliseconds and reached 0.28 only at the very end -- a
    sustained roar rather than a boom, and the one cue in the set whose
    envelope did not decay. Saturation is for the hit; the bells that carry the
    tail want to be left alone.
    """
    n = n_of(1.700)

    m = n_of(0.900)
    impact = pad_to(soft_clip(mix(
        moving_lowpass(noise(m, g), 2200, 48, q=1.3) * env_ad(m, 0.0005, 0.80, 4.6),
        tri(300, m, 38) * env_pluck(m, 0.85, 3.6) * 1.15), 1.6), n)

    shimmer = np.zeros(n)
    for i, f in enumerate((392.0, 523.25, 659.25, 783.99, 1046.5)):
        k = n_of(1.20 - i * 0.14)
        v = mix(sine(f, k) * env_pluck(k, 1.1, 3.0),
                sine(f * 2, k) * env_pluck(k, 0.7, 4.6) * 0.3)
        shimmer = mix(shimmer, at(v * (0.42 - i * 0.05), 0.26 + 0.090 * i, n))

    air = moving_lowpass(noise(n, g), 900, 120, q=1.0)
    air *= env_ad(n, 0.02, 1.35, curve=4.2) * 0.22

    return finish(mix(impact, shimmer, air), 1.00)


def cue_player_down(g):
    """The run lost. Falling, and it does not resolve -- the panel that follows
    it is the resolution."""
    n = n_of(1.150)
    fall = mix(tri(330, n, 41) * 0.9, tri(495, n, 61) * 0.4)
    fall *= env_ad(n, 0.006, 1.10, curve=2.0)
    fall = lowpass(fall, 2200)
    air = moving_lowpass(noise(n, g), 1400, 90, q=1.1)
    air *= env_ad(n, 0.001, 1.05, curve=2.4) * 0.35
    return finish(soft_clip(mix(fall, air), 1.3), 0.80)


def cue_ui_move(g):
    """The cursor moving. Held down, an arrow key repeats -- so this is short,
    soft and slightly *below* the confirm, which is what keeps travelling
    through a rack from sounding like a decision being made ten times."""
    n = n_of(0.050)
    v = tri(760, n, 700) * env_pluck(n, 0.5, 9.0)
    return finish(lowpass(v, 3200), 0.34)


def cue_ui_select(g):
    """Confirm. Two notes rising: the only cue on these screens with an
    interval in it, because an interval is what says a thing was *chosen*."""
    n = n_of(0.210)
    a = tri(660, n_of(0.10)) * env_pluck(n_of(0.10), 0.6, 6.0)
    b = tri(990, n_of(0.16)) * env_pluck(n_of(0.16), 0.8, 5.0)
    return finish(mix(pad_to(a, n), at(b * 0.95, 0.055, n)), 0.56)


def cue_ui_back(g):
    """Leaving a screen. The confirm's interval, inverted."""
    n = n_of(0.190)
    a = tri(660, n_of(0.09)) * env_pluck(n_of(0.09), 0.6, 6.5)
    b = tri(440, n_of(0.15)) * env_pluck(n_of(0.15), 0.8, 5.5)
    return finish(lowpass(mix(pad_to(a, n), at(b * 0.9, 0.050, n)), 3600), 0.48)


def cue_ui_deny(g):
    """A locked stage, an attack list with nothing in it. **Not a rude noise.**
    The rack refuses in order to advertise that there is more game coming, and
    a cue that punished the player for looking would say the opposite. Low,
    flat, and no interval -- a door that did not open."""
    n = n_of(0.200)
    v = mix(square(150, n, 138, duty=0.5) * 0.7, tri(224, n, 208) * 0.5)
    v *= env_ad(n, 0.004, 0.18, curve=2.8)
    return finish(lowpass(v, 1100), 0.50)


def cue_pause(g):
    """The pause menu, opening or closing. One muted thunk -- the screen has
    gone still and the cue's job is to say the game did that on purpose."""
    n = n_of(0.130)
    v = tri(300, n, 190) * env_pluck(n, 0.7, 6.0)
    v = lowpass(v, 1500)
    click = highpass(noise(n_of(0.012), g), 1800) * env_pluck(n_of(0.012), 0.4, 10.0)
    return finish(mix(v, pad_to(click * 0.5, n)), 0.46)


# The set. Order is the order the preview lays them out in, grouped by what
# they belong to rather than alphabetically -- a sheet sorted by name puts the
# player's shot next to the pause menu.
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
# **Every generator writes one and this one writes two**, because a sound
# cannot be reviewed by looking at it and a *set* of sounds cannot be reviewed
# by listening to them one at a time. The WAV is the set in order with a beat
# between each, which is the only way to hear whether two cues are too alike;
# the PNG is every cue's envelope and spectrum on one sheet, which is the only
# way to see that two of them are sitting in the same band.
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

        # The waveform, min/max per column so a 40ms cue and a 1.7s one are
        # both legible -- drawn against a common time base so the *lengths*
        # can be compared, which is half of what this sheet is for.
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

        # ...and the spectrum, as a strip under it. A cue that shares a band
        # with its neighbour is a cue that masks it, and this is where that
        # shows.
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
        print("  %-18s %6.0fms  peak %.2f"
              % (name, samples.shape[0] * 1000.0 / RATE,
                 float(np.max(np.abs(samples)))))

    write_preview_wav(built, os.path.join(PREVIEW, "sfx.wav"))
    write_preview_png(built, os.path.join(PREVIEW, "sfx.png"))
    total = sum(s.shape[0] for _, s in built) * 2
    print("\n%d cues, %.1fs, %.0f KB of PCM" % (
        len(built), sum(s.shape[0] for _, s in built) / float(RATE),
        total / 1024.0))
    print("preview: tools/_preview/sfx.wav and sfx.png")


if __name__ == "__main__":
    main()
