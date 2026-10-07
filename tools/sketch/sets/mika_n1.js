// Candidates for Mika's N1 on the 2.5D orbit: two rings throwing amber and
// ember sand. Sketches only; none is in the game yet.
//
// The orbit is N1's (radius 205, tilt 0.53) turning clockwise on screen,
// which is N2's way (`way: -1`); N1 itself turns the other way (`way: 1`).
// The period is 172 frames a turn rather than the game's 171.4 (2.1 degrees a
// frame) so that a GIF loops exactly; the woven net uses 174, because it
// throws every third frame.
(function () {
'use strict';
const C = { ember: '#ff6a2a', amber: '#ffb627', bone: '#f6e6bd',
            gold: '#ffd84a' };
const PELLET = 3.3, MOTE = 4.3;

Sketch.set({
    id: 'mika_n1',
    name: "Mika's N1: sand off the 2.5D orbit",
    orbit: { rings: 2, radius: 205, tilt: 0.53, depth: 0.2, dim: 0.55,
             period: 172, way: -1 },
    toggles: [
        // For the spiral arms and the woven net.
        { id: 'frontOnly', label: 'Throw only from the front half' },
    ],
    patterns: [

    // Each ring throws a doubled thread straight out along its orbit angle;
    // the grains brake, then bend 50 degrees the way the orbit turns.
    { name: 'Spiral arms', emit(a) {
        if (a.t % 4) return;
        for (let i = 0; i < 2; i++) {
            const r = a.ring(i);
            if (a.opts.frontOnly && r.far >= 0.15) continue;
            const m = a.rim(r, r.orb);
            for (const v of [9.5, 7.4]) {
                a.grain({ x: m.x, y: m.y, v, dir: r.orb, hold: 8, brake: 0.42,
                          flr: 1.9, curl: 0.55 * a.orbit.way, bend: 50,
                          col: i ? C.amber : C.ember, r: i ? PELLET : MOTE });
            }
        }
    } },

    // The same throw as a pair: one grain bends each way, so the two
    // families cross into interlaced loops.
    { name: 'Woven net', orbit: { period: 174 }, emit(a) {
        if (a.t % 3) return;
        for (let i = 0; i < 2; i++) {
            const r = a.ring(i);
            if (a.opts.frontOnly && r.far >= 0.15) continue;
            const m = a.rim(r, r.orb);
            const w = a.orbit.way;
            a.grain({ x: m.x, y: m.y, v: 8.5, dir: r.orb, hold: 8, brake: 0.4,
                      flr: 2.0, curl: 0.9 * w, bend: 80, col: C.ember, r: MOTE });
            a.grain({ x: m.x, y: m.y, v: 8.5, dir: r.orb, hold: 8, brake: 0.4,
                      flr: 2.0, curl: -0.9 * w, bend: 80, col: C.amber,
                      r: PELLET });
        }
    } },

    // As ring 0 passes the front, a six-petal lotus outlined in sand: every
    // grain's speed, brake and floor scale with its point on the outline, so
    // the shape grows without distorting. Each bloom is turned 30 degrees from
    // the last and swaps hue.
    { name: 'Lotus blooms', loop: (o) => 2 * o.period, emit(a) {
        if (!a.passed(0, 90)) return;
        const r = a.ring(0), k = Math.floor(a.t / a.orbit.period) % 2;
        const rot = k * 30 + 90;            // screen degrees; 90 points down
        const edge = [[1, 0]];
        for (const u of [0.3, 0.45, 0.6, 0.75, 0.88]) {
            for (const sd of [-1, 1]) {
                edge.push([u, sd * 0.3 * Math.sin(Math.PI * Math.pow(u, 0.8))]);
            }
        }
        for (let q = 0; q < 6; q++) {
            const pa = (rot + q * 60) * Math.PI / 180;
            const c = Math.cos(pa), s = Math.sin(pa);
            for (const [u, w] of edge) {
                // Screen offsets (y down), the bloom squashed a little.
                const px = u * c - w * s, py = (u * s + w * c) * 0.85;
                const L = Math.hypot(px, py), tip = (u === 1);
                a.grain({ x: r.x, y: r.y, v: 11 * L, dir: a.pdir(px, py),
                          hold: 10, brake: 0.5 * L, flr: 1.2 * L, fall: 0.9,
                          col: tip ? C.bone : (k ? C.amber : C.ember),
                          r: tip ? MOTE : PELLET });
            }
        }
    } },

    // Only the ring in front throws. Each pass lays an arched double row
    // that falls and sways; each row has one gap, on alternate sides, so it
    // repeats every two turns.
    { name: 'Dune rows', loop: (o) => 2 * o.period, emit(a) {
        if (a.t % 2) return;
        for (let i = 0; i < 2; i++) {
            const r = a.ring(i);
            if (r.far > -0.05) continue;
            const pass = Math.floor(r.p / 360) + i;
            const gap = (pass % 2) ? 58 : 122;
            if (Math.abs(a.wrap(r.p) - gap) < 15) continue;
            const m = a.rim(r, r.orb);
            for (const v of [7, 5.4]) {
                a.grain({ x: m.x, y: m.y, v, dir: r.orb, hold: 4, brake: 0.45,
                          flr: 1.8, down: 1.1, sway: 16 * a.orbit.way,
                          col: v > 6 ? (i ? C.amber : C.ember) : C.bone,
                          r: v > 6 ? MOTE : PELLET });
            }
        }
    } },

    // The rings shed two bands of sand that keep circling in the orbit's
    // plane, slower the further out (as orbits do), drifting outward. At the
    // edge a grain comes loose along its path at 1.5 times its speed there,
    // and brakes to a drift.
    { name: 'Sand disc', emit(a) {
        if (a.t % 4) return;
        for (let i = 0; i < 2; i++) {
            const r = a.ring(i);
            for (const [off, col] of [[34, i ? C.amber : C.ember],
                                      [92, C.gold]]) {
                a.bullet({ x: r.x, y: r.y, ph: r.p, rad: a.orbit.radius + off,
                           lim: a.orbit.radius + off + 300, col, r: PELLET,
                           cull: false, step: discStep });
            }
        }
    } },

    // The sand disc with everything running 1.5 times as fast (the rings'
    // turn included, so the shape is the same), shedding every other frame,
    // with a third band. What N1 runs in the game, between his hops
    // (`mika_nonspells`).
    { name: 'Sand disc, faster', orbit: { period: 114 }, emit(a) {
        if (a.t % 2) return;
        const k = 172 / a.orbit.period;          // how much faster
        for (let i = 0; i < 2; i++) {
            const r = a.ring(i), own = i ? C.amber : C.ember;
            for (const [off, col] of [[34, own], [92, C.gold], [150, own]]) {
                a.bullet({ x: r.x, y: r.y, ph: r.p, rad: a.orbit.radius + off,
                           lim: a.orbit.radius + off + 300, k, col, r: PELLET,
                           cull: false, step: discFastStep });
            }
        }
    } },

    // As a ring reaches either side, it drops a whirl of sand that sinks,
    // drawing in toward the middle; whirls on the two sides spin opposite
    // ways. Low on the field each bursts into a pinwheel.
    { name: 'Dust devils',
      step(a) {
        const ds = a.store.devils || (a.store.devils = []);
        for (let k = ds.length - 1; k >= 0; k--) {
            const c = ds[k];
            c.age++;
            c.x += (c.tx - c.x) * 0.025;
            c.y += 1.4;
            if (c.y > 620) { c.burst = true; ds.splice(k, 1); }
        }
      },
      emit(a) {
        const ds = a.store.devils || (a.store.devils = []);
        for (let i = 0; i < 2; i++) {
            for (const side of [0, 180]) {
                if (!a.passed(i, side)) continue;
                const r = a.ring(i), sg = a.dcos(r.orb) > 0 ? 1 : -1;
                const c = { x: r.x, y: r.y, tx: a.boss.x + sg * 115, age: 0,
                            sg, n: 14, burst: false };
                ds.push(c);
                for (let j = 0; j < c.n; j++) {
                    a.bullet({ c, j, col: sg > 0 ? C.ember : C.amber, r: MOTE,
                               step: devilStep });
                }
            }
        }
    } },

    // Ring 0 is one pole of a lodestone and ring 1 the other. Sand runs from
    // it along six meridians of a globe whose axis turns with the rings,
    // ember turning amber past the equator, and is flung off past the far
    // pole.
    { name: 'Lodestone globe', emit(a) {
        if (a.t % 4) return;
        for (let j = 0; j < 6; j++) {
            a.bullet({ lam: j * 60, s: 0, col: C.ember, r: MOTE,
                       step: globeStep });
        }
    } },

    ],
});

function discStep(b, a) {
    const o = a.orbit, ox = b.x, oy = b.y;
    b.ph += (360 / o.period) * Math.pow(o.radius / b.rad, 1.5);
    b.rad += 0.9;
    const q = a.onOrbit(b.ph, b.rad);
    b.x = q.x; b.y = q.y;
    if (b.rad >= b.lim) {
        const vx = b.x - ox, vy = b.y - oy;
        a.grain({ x: b.x, y: b.y, v: Math.hypot(vx, vy) * 1.5,
                  dir: a.pdir(vx, vy), hold: 10, brake: 0.05, flr: 2.0,
                  col: b.col, r: b.r });
        b.dead = true;
    }
}

// `discStep` with time running `b.k` times as fast: the same paths.
function discFastStep(b, a) {
    const o = a.orbit, k = b.k, ox = b.x, oy = b.y;
    b.ph += (360 / o.period) * Math.pow(o.radius / b.rad, 1.5);
    b.rad += 0.9 * k;
    const q = a.onOrbit(b.ph, b.rad);
    b.x = q.x; b.y = q.y;
    if (b.rad >= b.lim) {
        const vx = b.x - ox, vy = b.y - oy;
        a.grain({ x: b.x, y: b.y, v: Math.hypot(vx, vy) * 1.5,
                  dir: a.pdir(vx, vy), hold: Math.round(10 / k),
                  brake: 0.05 * k * k, flr: 2.0 * k, col: b.col, r: b.r });
        b.dead = true;
    }
}

function devilStep(b, a) {
    const c = b.c;
    const rr = Math.min(66, 10 + c.age * 0.9);
    const ang = c.sg * 2.6 * c.age + b.j * 360 / c.n;   // screen degrees
    const x = c.x + rr * Math.cos(ang * Math.PI / 180);
    const y = c.y + rr * Math.sin(ang * Math.PI / 180);
    if (c.burst) {
        a.grain({ x, y, v: 6, dir: -(ang + c.sg * 90), hold: 6, brake: 0.2,
                  flr: 2.0, col: b.col, r: b.r });
        b.dead = true;
        return;
    }
    b.x = x; b.y = y;
}

function globeStep(b, a) {
    const ds = 180 / 44;                    // degrees of meridian a frame
    const lx = b.x, ly = b.y;
    b.s += ds;
    if (b.s > 90) b.col = C.amber;

    // The axis runs through ring 0. X across, Y up, Z toward the viewer.
    const R = a.orbit.radius, orb = a.ring(0).orb;
    const ux = a.dcos(orb), uz = -a.dsin(orb), wx = -uz, wz = ux;
    const c = a.dcos(b.s), sn = a.dsin(b.s) * 1.25;
    const X = R * (c * ux + sn * a.dsin(b.lam) * wx);
    const Y = R * sn * a.dcos(b.lam);
    const Z = R * (c * uz + sn * a.dsin(b.lam) * wz);
    b.x = a.boss.x + X;
    b.y = a.boss.y + Z * a.orbit.tilt - Y * 0.85;

    if (b.s >= 180) {
        const vx = b.x - lx, vy = b.y - ly;
        a.grain({ x: b.x, y: b.y, v: Math.hypot(vx, vy), dir: a.pdir(vx, vy),
                  hold: 3, brake: 0.35, flr: 1.9, col: b.col, r: b.r });
        b.dead = true;
    }
}
})();
