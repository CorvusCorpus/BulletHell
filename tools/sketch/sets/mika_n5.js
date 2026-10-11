// Candidates for Mika's N5 (six rings) and N7 (the last non-spell before the
// Grand Orrery). "Pulses, turning" (N5), "N6: Pulses, turning" and "N7:
// Reversing disc" are built into the game (`mika_nonspells`); the rest are
// sketches only. "Pulses" was N5's first build: every burst left from the same
// places, so the lanes between them never moved.
//
// Six rings on his six-ring radius (300, as the Grand Orrery's), moving along
// their path as fast as N3's rings do, and sand at N1's pace (`K`). Ember sand
// circles with the rings, amber against them, as in N3's woven disc.
(function () {
'use strict';
const C = { ember: '#ff6a2a', amber: '#ffb627', gold: '#ffd84a' };
const PELLET = 3.3, MOTE = 4.3;
const K = 1.5;                  // the sand's pace, as N1's
const R = 300, PERIOD = 168;    // the six rings' orbit and frames a turn

// An orbit of six rings, clockwise (N1's way), with extra fields.
function six(extra) {
    return Object.assign({ rings: 6, radius: R, period: PERIOD, way: -1 },
                         extra || {});
}

// Shed a woven pair from every ring: one grain circling with the rings, one
// against them, both starting `off` beyond the ring's present radius. Ember
// glints circle with the rings and amber grains against them, or the other
// way round if `swap`.
function shedPairs(a, off, swap) {
    const o = a.orbits[0];
    const pair = [[1, C.ember, MOTE], [-1, C.amber, PELLET]];
    if (swap) { pair[0][0] = -1; pair[1][0] = 1; }
    for (let i = 0; i < o.rings; i++) {
        const r = a.ringOf(0, i);
        const rad = Math.hypot(r.x - a.boss.x, (r.y - a.boss.y) / o.tilt);
        for (const [turn, col, rr] of pair) {
            a.bullet({ x: r.x, y: r.y, ph: r.p, o, turn, rad: rad + off,
                       lim: rad + off + 260, col, r: rr, cull: false,
                       step: discStep });
        }
    }
}

Sketch.set({
    id: 'mika_n5',
    name: "Mika's N5 and N7: six-ring candidates",
    orbit: { tilt: 0.53, depth: 0.2, dim: 0.55 },
    patterns: [

    // The woven disc on six rings, its orbit slowly swelling and shrinking:
    // sand shed while it swells is laid closer, so ripples of denser and
    // thinner sand travel outward. Gentle: the swell never outruns the sand's
    // own spread.
    { name: 'Breathing disc', loop: () => PERIOD,
      orbits: [six({ radiusAt: (t) => R + 30 * Math.sin(2 * Math.PI * t / PERIOD) })],
      emit(a) { if (a.t % 3 === 0) shedPairs(a, 34); } },

    // The same, breathing twice a turn and further, so the swell outruns the
    // sand's spread and the ripples pile up into sharp crests.
    { name: 'Breathing disc, crests', loop: () => PERIOD,
      orbits: [six({ radiusAt: (t) => R + 30 * Math.sin(4 * Math.PI * t / PERIOD) })],
      emit(a) { if (a.t % 3 === 0) shedPairs(a, 34); } },

    // The woven disc on six rings shedding only in bursts: every ring sheds
    // each frame for 10 frames in 42, so the sand goes out in waves. 42
    // frames is a quarter turn, so the bursts take turns between two sets of
    // places and the lanes between them never move.
    pulses('Pulses', 42, 10, -1, false),

    // N5: Pulses whose bursts don't fit the turn. 48 frames turn the rings
    // 102.9 degrees, 17.1 short of two rings' spacing, so each burst leaves a
    // little behind where the last one did and the lanes between the waves
    // creep round.
    pulses('Pulses, turning', 48, 10, -1, false),

    // N6: the same mirrored, its colours swapped, with bursts half as long
    // again and half as rare again (72 frames, 25.7 degrees short of three
    // rings' spacing).
    pulses('N6: Pulses, turning', 72, 15, 1, true),

    // Plain escalation: N1's three bands (each ring's own sand, gold, its own
    // again) on six rings, alternate rings ember and amber.
    { name: 'Three bands on six', loop: () => PERIOD,
      orbits: [six()],
      emit(a) {
        if (a.t % 4) return;
        const o = a.orbits[0];
        for (let i = 0; i < 6; i++) {
            const r = a.ringOf(0, i), own = i % 2 ? C.amber : C.ember;
            for (const [off, col, rr] of [[34, own, i % 2 ? PELLET : MOTE],
                                          [92, C.gold, PELLET],
                                          [150, own, i % 2 ? PELLET : MOTE]]) {
                a.bullet({ x: r.x, y: r.y, ph: r.p, o, turn: 1,
                           rad: o.radius + off, lim: o.radius + off + 260,
                           col, r: rr, cull: false, step: discStep });
            }
        }
      } },

    // N7 candidate: six rings whose turn reverses every few seconds (holding
    // `HOLD` frames, then easing round over `SWING`). Sand keeps circling the
    // way the rings were going when it was shed, so fresh sand crosses the
    // old after each reversal and the disc folds into a new weave. Each
    // ring's sand in its own colour; a gold band beyond it, let go at the
    // same radius as the own sand and shed a frame before it, so once loose
    // each gold grain falls halfway between two of the own sand's and the
    // curtains are even lines (as the game has it).
    { name: 'N7: Reversing disc', loop: () => 2 * (HOLD + SWING),
      orbits: [six({ turnAt: reversingTurn })],
      emit(a) {
        const beat = a.t % 3;
        if (beat > 1) return;
        const o = a.orbits[0], dir = reversingDir(a.t);
        const out = o.radius + 34 + 260;        // where both bands let go
        for (let i = 0; i < 6; i++) {
            const r = a.ringOf(0, i), own = i % 2 ? C.amber : C.ember;
            const [off, col, rr] = beat ? [34, own, i % 2 ? PELLET : MOTE]
                                        : [34 + 0.9 * K * 53, C.gold, PELLET];
            a.bullet({ x: r.x, y: r.y, ph: r.p, o, turn: dir,
                       rad: o.radius + off, lim: out,
                       col, r: rr, cull: false, step: discStep });
        }
      } },

    ],
});

// Pulses: the woven pair from every ring each frame for `on` frames in every
// `every`, the rings turning `way` (-1 clockwise), with the colours swapped
// if `swap`. One loop is whole bursts and whole turns.
function pulses(name, every, on, way, swap) {
    const gcd = (x, y) => (y ? gcd(y, x % y) : x);
    return { name, loop: () => every * PERIOD / gcd(every, PERIOD),
             orbits: [six({ way })],
             emit(a) { if (a.t % every < on) shedPairs(a, 34, swap); } };
}

// N7's reversals: `HOLD` frames turning one way, `SWING` frames easing round
// to the other (a half cosine), and back.
const HOLD = 150, SWING = 30;

// The rings' direction at frame `t`, 1 one way and -1 the other, eased.
function reversingDir(t) {
    const v = t % (2 * (HOLD + SWING));
    if (v < HOLD) return 1;
    if (v < HOLD + SWING) return Math.cos(Math.PI * (v - HOLD) / SWING);
    if (v < 2 * HOLD + SWING) return -1;
    return -Math.cos(Math.PI * (v - 2 * HOLD - SWING) / SWING);
}

// Degrees turned by frame `t` (the sum of the eased direction, cached).
const turnCache = [0];
function reversingTurn(t) {
    const rate = 360 / PERIOD;
    while (turnCache.length <= t) {
        const k = turnCache.length;
        turnCache.push(turnCache[k - 1] + rate * reversingDir(k));
    }
    return turnCache[Math.max(0, Math.floor(t))];
}

// A disc grain: round the boss `turn` ways (1 with the rings' way, -1
// against) at N1's sand's rate for its radius, out at N1's pace, and let go
// along its path as N1's is.
function discStep(b, a) {
    const o = b.o, ox = b.x, oy = b.y;
    b.ph += b.turn * (360 / o.period) * Math.pow(o.radius / b.rad, 1.5);
    b.rad += 0.9 * K;
    const q = a.onOrbit(b.ph, b.rad, a.boss, o);
    b.x = q.x; b.y = q.y;
    if (b.rad < b.lim) return;
    const vx = b.x - ox, vy = b.y - oy;
    a.grain({ x: b.x, y: b.y, v: Math.hypot(vx, vy) * 1.5,
              dir: a.pdir(vx, vy), hold: Math.round(10 / K),
              brake: 0.05 * K * K, flr: 2.0 * K, col: b.col, r: b.r });
    b.dead = true;
}
})();
