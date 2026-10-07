// Candidates for Mika's N3, the four-ring non-spell. "Woven disc" is the one
// built into the game; the rest are sketches only.
//
// "Counter discs": two pairs on two orbits turning opposite ways, each
// shedding a disc as N1 does; read as messy (the two families never line
// up). "Woven disc" and "Rosette": four rings shedding mirrored pairs into
// one disc. "Woven net" and "Alternating weave": the Woven net sketch
// (`mika_n1.js`) on two or four rings; Woven net's grains follow each other
// closely, so each ring's stream draws a clean curve, and that is what makes
// it read as intentional. Sand runs at N1's pace (`K`, 1.5 times the original
// sketches') unless a pattern says otherwise. Ember and amber sand bend
// opposite ways.
(function () {
'use strict';
const C = { ember: '#ff6a2a', amber: '#ffb627', gold: '#ffd84a' };
const PELLET = 3.3, MOTE = 4.3;

// The sand's pace, as N1's: grow, hold, brake and floor are the original
// sketch's run 1.5 times as fast.
const K = 1.5;

Sketch.set({
    id: 'mika_n3',
    name: "Mika's N3: four-ring candidates",
    orbit: { tilt: 0.53, depth: 0.2, dim: 0.55 },
    patterns: [

    { name: 'Counter discs', loop: () => 342,
      orbits: [
        { rings: 2, radius: 160, period: 114, way: -1, phase0: 0 },
        { rings: 2, radius: 310, period: 171, way: 1, phase0: 90, sand: 0.6 },
      ],
      emit(a) {
        if (a.t % 2) return;
        for (let k = 0; k < 2; k++) {
            const o = a.orbits[k], col = k ? C.gold : C.ember;
            for (let i = 0; i < o.rings; i++) {
                const r = a.ringOf(k, i);
                for (const [off, rr] of [[34, MOTE], [92, PELLET]]) {
                    a.bullet({ x: r.x, y: r.y, ph: r.p, o,
                               rad: o.radius + off, lim: o.radius + off + 300,
                               col, r: rr, cull: false, step: discStep });
                }
            }
        }
      } },

    // A: each ring sheds a pair into the disc, one circling with the rings
    // as N1's sand does and one against them at the same rate, so the two are
    // let go as mirror images of each other and their streams cross. The
    // owner's pick: what N3 runs in the game (`mika_nonspells`).
    { name: 'Woven disc', loop: () => 114,
      orbits: [{ rings: 4, radius: 205, period: 114, way: -1 }],
      emit(a) {
        if (a.t % 2) return;
        const o = a.orbits[0];
        for (let i = 0; i < 4; i++) {
            const r = a.ringOf(0, i);
            for (const [turn, col, rr] of [[1, C.ember, MOTE],
                                           [-1, C.amber, PELLET]]) {
                a.bullet({ x: r.x, y: r.y, ph: r.p, o, turn,
                           rad: o.radius + 34, lim: o.radius + 334, col,
                           r: rr, cull: false, step: pairStep });
            }
        }
      } },

    // B: each ring sheds one grain that trails it, as N1's sand does, and one
    // that leads it by as much. Turning with the rings, the two are mirror
    // images, so the disc is a lattice of spiral arms crossing.
    { name: 'Rosette', loop: () => 114,
      orbits: [{ rings: 4, radius: 205, period: 114, way: -1 }],
      emit(a) {
        if (a.t % 2) return;
        const o = a.orbits[0];
        for (let i = 0; i < 4; i++) {
            const r = a.ringOf(0, i);
            for (const [lead, col, rr] of [[0, C.ember, MOTE],
                                           [1, C.amber, PELLET]]) {
                a.bullet({ x: r.x, y: r.y, ph: r.p, o, lead,
                           rad: o.radius + 34, lim: o.radius + 334, col,
                           r: rr, cull: false, step: rosetteStep });
            }
        }
      } },

    // C: the Woven net sketch (`mika_n1.js`) on four rings: each ring throws
    // a pair straight out along its orbit angle, one bending each way once
    // braked. `woven(name, rings, beat, k)`: `k` is the pace (N1's is 1.5).
    woven('Woven net (the original)', 2, 3, 1, 172),
    woven('Woven net at N1 pace', 2, 2, 1.5, 114),

    // E: four rings, each throwing Woven net's interlocking pair.
    // `wovenFour(name, beat, k, period, opts)`: `front` throws only from a
    // ring on the front half of its orbit; `curl` and `bend` override the
    // bending (0.9 and 80 at the original's pace).
    wovenFour('Woven four, front half', 2, 1.5, 114, { front: true }),
    wovenFour('Woven four, original pace', 3, 1, 172, {}),
    wovenFour('Woven four, tighter', 2, 1.5, 114, { curl: 0.6, bend: 55 }),

    // D: four rings, each throwing one of Woven net's two families:
    // alternate rings' sand bends opposite ways, so the streams weave
    // between neighbouring rings. `alternate(name, beat, k, period)`.
    alternate('Alternating weave', 2, 1.5, 114),
    alternate('Alternating weave, original pace', 3, 1, 172),

    ],
});

function woven(name, rings, beat, k, period) {
    return { name, loop: () => period * beat,
      orbits: [{ rings, radius: 205, period, way: -1 }],
      emit(a) {
        if (a.t % beat) return;
        const w = a.orbits[0].way;
        for (let i = 0; i < rings; i++) {
            const r = a.ringOf(0, i), m = a.rim(r, r.orb);
            for (const [c, col, rr] of [[1, C.ember, MOTE],
                                        [-1, C.amber, PELLET]]) {
                a.grain({ x: m.x, y: m.y, v: 8.5 * k, dir: r.orb,
                          hold: Math.round(8 / k), brake: 0.4 * k * k,
                          flr: 2.0 * k, curl: 0.9 * k * c * w, bend: 80,
                          col, r: rr });
            }
        }
      } };
}

function wovenFour(name, beat, k, period, opt) {
    const curl = opt.curl || 0.9, bend = opt.bend || 80;
    return { name, loop: () => period * beat,
      orbits: [{ rings: 4, radius: 205, period, way: -1 }],
      emit(a) {
        if (a.t % beat) return;
        const w = a.orbits[0].way;
        for (let i = 0; i < 4; i++) {
            const r = a.ringOf(0, i);
            if (opt.front && r.far > 0) continue;
            const m = a.rim(r, r.orb);
            for (const [c, col, rr] of [[1, C.ember, MOTE],
                                        [-1, C.amber, PELLET]]) {
                a.grain({ x: m.x, y: m.y, v: 8.5 * k, dir: r.orb,
                          hold: Math.round(8 / k), brake: 0.4 * k * k,
                          flr: 2.0 * k, curl: curl * k * c * w, bend,
                          col, r: rr });
            }
        }
      } };
}

function alternate(name, beat, k, period) {
    return { name, loop: () => period * beat,
      orbits: [{ rings: 4, radius: 205, period, way: -1 }],
      emit(a) {
        if (a.t % beat) return;
        const w = a.orbits[0].way;
        for (let i = 0; i < 4; i++) {
            const r = a.ringOf(0, i), m = a.rim(r, r.orb), c = i % 2 ? -1 : 1;
            a.grain({ x: m.x, y: m.y, v: 8.5 * k, dir: r.orb,
                      hold: Math.round(8 / k), brake: 0.4 * k * k,
                      flr: 2.0 * k, curl: 0.9 * k * c * w, bend: 80,
                      col: c > 0 ? C.ember : C.amber,
                      r: c > 0 ? MOTE : PELLET });
        }
      } };
}

// A grain of the woven disc: round the centre `turn` ways (1 with the rings,
// -1 against them) at N1's sand's rate, out, and let go as N1's is.
function pairStep(b, a) {
    const o = b.o, ox = b.x, oy = b.y;
    b.ph += b.turn * (360 / o.period) * Math.pow(o.radius / b.rad, 1.5);
    b.rad += 0.9 * K;
    letGo(b, a, ox, oy);
}

// A grain of the rosette: trailing its ring as N1's sand does, or (`lead`)
// gaining on it by as much as the other falls behind.
function rosetteStep(b, a) {
    const o = b.o, ox = b.x, oy = b.y;
    const ring = 360 / o.period, k = Math.pow(o.radius / b.rad, 1.5);
    b.ph += b.lead ? ring * (2 - k) : ring * k;
    b.rad += 0.9 * K;
    letGo(b, a, ox, oy);
}

// Place a disc grain, and once far enough out let it go as N1's sand is.
function letGo(b, a, ox, oy) {
    const q = a.onOrbit(b.ph, b.rad, a.boss, b.o);
    b.x = q.x; b.y = q.y;
    if (b.rad < b.lim) return;
    const vx = b.x - ox, vy = b.y - oy;
    a.grain({ x: b.x, y: b.y, v: Math.hypot(vx, vy) * 1.5,
              dir: a.pdir(vx, vy), hold: Math.round(10 / K),
              brake: 0.05 * K * K, flr: 2.0 * K, col: b.col, r: b.r });
    b.dead = true;
}

// Round its own orbit's centre and out, slower further out; let go along its
// path at 1.5 times its speed there, then brake to a drift.
function discStep(b, a) {
    const o = b.o, ox = b.x, oy = b.y;
    b.ph += (o.sand || 1) * (360 / o.period) * Math.pow(o.radius / b.rad, 1.5);
    b.rad += 0.9 * K;
    const q = a.onOrbit(b.ph, b.rad, a.boss, o);
    b.x = q.x; b.y = q.y;
    if (b.rad >= b.lim) {
        const vx = b.x - ox, vy = b.y - oy;
        a.grain({ x: b.x, y: b.y, v: Math.hypot(vx, vy) * 1.5,
                  dir: a.pdir(vx, vy), hold: Math.round(10 / K),
                  brake: 0.05 * K * K, flr: 2.0 * K, col: b.col, r: b.r });
        b.dead = true;
    }
}
})();
