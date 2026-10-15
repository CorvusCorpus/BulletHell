// Candidates for Astyr's non-spells: a jackalope ranger who hops about like a
// rabbit while firing arrows rapidly. Sketches only; none is in the game.
//
// He moves himself (`bossAt`): crouched at a station for `sit` frames, then a
// hop of `air` frames to the next, straight across and `lift` px up the screen
// at the top of a parabola. Every arrow is the game's `arrow` shape: its origin
// is the head, its shaft trails behind, and it hits along the capsule
// `bullet_table` gives it (radius 1.5 from 47.5 px behind the origin to 4 px
// ahead).
(function () {
'use strict';
const C = { jade: '#2fd48a', spring: '#8dffc0', lime: '#c2f24a',
            bone: '#f6e6bd', gold: '#ffd84a', azure: '#58a8ff' };
const W = 1360, H = 992, PLAYER_R = 4.0;
const ARROW = { r: 1.5, back: -47.5, front: 4.0 };
const PELLET = 3.3;
const dsin = (a) => Math.sin(a * Math.PI / 180);
const dcos = (a) => Math.cos(a * Math.PI / 180);
const pdir = (dx, dy) => Math.atan2(-dy, dx) * 180 / Math.PI;

// ---- hopping ---------------------------------------------------------------

// Hops round the stations `st` for ever. `at(t)` gives where he is, the
// station he is on or leaving (`k`, counting up without wrapping), the frames
// into this station's sit and hop (`u`), whether he is in the air, and the
// stations he hops from and to.
function hops(st, sit, air, lift) {
    const cyc = sit + air, n = st.length;
    return {
        period: cyc * n, sit, air,
        at(t) {
            const k = Math.floor(t / cyc), u = t % cyc;
            const A = st[k % n], B = st[(k + 1) % n];
            if (u < sit) return { x: A.x, y: A.y, k, u, air: false, from: A, to: B };
            const f = (u - sit) / air;
            return { x: A.x + (B.x - A.x) * f,
                     y: A.y + (B.y - A.y) * f - lift * 4 * f * (1 - f),
                     k, u, f, air: true, from: A, to: B };
        },
    };
}

// ---- arrows ----------------------------------------------------------------

/* An arrow at `v` along `dir`. Optional: `acc` a frame toward `vmax`, gravity
 * `g` (px a frame per frame, down the screen) with the fall capped at `vt`,
 * `wall` (times the side walls turn it back), `scale`, `loft` (may leave by
 * the top and come back), and `fn(b, a)`, run each frame before it moves. Its
 * heading is always its direction of travel. */
function arrow(a, o) {
    return a.bullet(Object.assign({
        v: 10, dir: 270, acc: 0, vmax: 99, g: 0, vt: 99, wall: 0, scale: 1,
        loft: false, col: C.jade, r: ARROW.r, cull: false,
        step: arrowStep, draw: arrowDraw, hit: arrowHit,
    }, o));
}

function arrowStep(b, a) {
    if (b.fn) b.fn(b, a);
    if (b.dead) return;
    if (b.acc > 0) b.v = Math.min(b.vmax, b.v + b.acc);
    if (b.acc < 0) b.v = Math.max(b.vmax, b.v + b.acc);
    let vx = dcos(b.dir) * b.v, vy = -dsin(b.dir) * b.v;
    if (b.g) {
        vy = Math.min(b.vt, vy + b.g);
        b.v = Math.hypot(vx, vy);
        b.dir = pdir(vx, vy);
    }
    if (b.wall > 0 && (b.x + vx < 0 || b.x + vx > W)) {
        vx = -vx;
        b.wall--;
        b.dir = pdir(vx, vy);
    }
    b.x += vx;
    b.y += vy;
    const m = 70 * b.scale;
    if (b.x < -m || b.x > W + m || b.y > H + m || (b.y < -m && !b.loft)) {
        b.dead = true;
    }
}

function arrowHit(b, p) {
    const ux = dcos(b.dir), uy = -dsin(b.dir), s = b.scale;
    const x0 = b.x + ux * ARROW.back * s, y0 = b.y + uy * ARROW.back * s;
    const dx = ux * (ARROW.front - ARROW.back) * s;
    const dy = uy * (ARROW.front - ARROW.back) * s;
    const u = Math.max(0, Math.min(1, ((p.x - x0) * dx + (p.y - y0) * dy)
                                      / (dx * dx + dy * dy)));
    return Math.hypot(x0 + dx * u - p.x, y0 + dy * u - p.y)
           < ARROW.r * s + PLAYER_R;
}

// A shaft trailing back from the head, two chevron vanes at its tail, and a
// barbed head with a white core.
function arrowDraw(g, s) {
    const b = this, k = b.scale * s;
    const ux = dcos(b.dir), uy = -dsin(b.dir);
    const X = b.x * s, Y = b.y * s;
    const P = (f, w) => [X + (ux * f - uy * w) * k, Y + (uy * f + ux * w) * k];
    const line = (pts, col, wid) => {
        g.strokeStyle = col;
        g.lineWidth = Math.max(0.8, wid * k);
        g.beginPath();
        g.moveTo(...pts[0]);
        for (const q of pts.slice(1)) g.lineTo(...q);
        g.stroke();
    };
    const poly = (pts, col) => {
        g.fillStyle = col;
        g.beginPath();
        g.moveTo(...pts[0]);
        for (const q of pts.slice(1)) g.lineTo(...q);
        g.closePath();
        g.fill();
    };
    g.lineCap = 'round';
    g.lineJoin = 'round';
    line([P(-48, 0), P(-6, 0)], b.col, 2.6);
    line([P(-50, -7), P(-40, 0), P(-50, 7)], b.col, 2);
    line([P(-56, -7), P(-46, 0), P(-56, 7)], b.col, 2);
    poly([P(12, 0), P(-8, 8), P(-4, 0), P(-8, -8)], b.col);
    poly([P(8, 0), P(-4, 4), P(-2, 0), P(-4, -4)], '#ffffff');
}

// The direction from (x, y) to the player.
function aim(a, x, y) {
    return pdir(a.player.x - x, a.player.y - y);
}

// ---- the patterns ----------------------------------------------------------

// 1. Bounding volley: zigzag hops across the top and back. Each landing
// thumps out a ring of slow dust, then looses a string of seven arrows that
// sweeps a fan across the player, toward the way he is about to hop.
const BOUND = hops([[250, 240], [460, 200], [680, 250], [900, 200], [1110, 240],
                    [900, 280], [680, 230], [460, 280]]
                   .map(([x, y]) => ({ x, y })), 36, 20, 70);

// 2. Lofted rain: from each station he looses two strings of arrows high
// out of the top of the field, sweeping opposite ways, that fall as two
// slanting curtains across where the player was when they were loosed
// (about four seconds later). Each landing also snaps an aimed three-way.
const RAIN = hops([{ x: 340, y: 230 }, { x: 1020, y: 230 }, { x: 680, y: 190 }],
                  150, 26, 90);
const LOFT = { up: 12.5, g: 0.2, vt: 6.0, n: 14, gap: 64 };

// The frames a lofted arrow takes from `by` to come down through `ty`.
function loftTime(by, ty) {
    const t1 = LOFT.up / LOFT.g, apex = by - LOFT.up * LOFT.up / (2 * LOFT.g);
    const t2 = LOFT.vt / LOFT.g, d2 = LOFT.vt * LOFT.vt / (2 * LOFT.g);
    return t1 + t2 + (ty - apex - d2) / LOFT.vt;
}

function loftString(a, s, n0, sweep, half) {
    const i = (s.u - n0) / 2;
    if (i < 0 || i >= LOFT.n || i % 1) return;
    const b = a.boss, p = a.player;
    const j = sweep > 0 ? i : LOFT.n - 1 - i;
    const tx = p.x + (j - (LOFT.n - 1) / 2 + half) * LOFT.gap;
    const vx = (tx - b.x) / loftTime(b.y, p.y);
    arrow(a, { x: b.x, y: b.y, v: Math.hypot(vx, LOFT.up), dir: pdir(vx, -LOFT.up),
               g: LOFT.g, vt: LOFT.vt, loft: true, col: half ? C.lime : C.jade });
}

// 3. Leapfrog rings: each landing looses a ring of arrows that bound outward
// as he does, a dash and a rest every `LEAP` frames. A ring is loosed every
// one and a half bounds, so alternate rings dash while the others rest.
const LEAPER = hops([{ x: 440, y: 240 }, { x: 680, y: 190 }, { x: 920, y: 240 },
                     { x: 680, y: 300 }], 40, 20, 70);
const LEAP = 40;

function bound(b) {
    const p = (b.age + b.off) % LEAP;
    b.v = p < 14 ? 0.5 + 13 * Math.pow(1 - p / 14, 2) : 0.5;
}

// 4. Leading string: quick short hops round a wide loop, and an arrow every
// four frames aimed where the player will be if he keeps going (as a ranger
// leads a running mark). Steady streaming walks into it; it has to be jinked.
// Each landing adds a pair aimed straight at him, either side of his lane.
const LOOP_ST = [];
for (let i = 0; i < 10; i++) {
    LOOP_ST.push({ x: 680 + 380 * dcos(90 + i * 36),
                   y: 235 - 70 * dsin(90 + i * 36) });
}
const LOOPER = hops(LOOP_ST, 10, 18, 45);

// Where to aim from (x, y) at speed `v` to meet the player if he keeps his
// present velocity.
function lead(a, x, y, v) {
    const p = a.player, st = a.store;
    const vx = st.pvx || 0, vy = st.pvy || 0;
    const dx = p.x - x, dy = p.y - y;
    const A = vx * vx + vy * vy - v * v, B = 2 * (dx * vx + dy * vy);
    const D = B * B - 4 * A * (dx * dx + dy * dy);
    const t = D < 0 ? 0 : Math.max(0, (-B - Math.sqrt(D)) / (2 * A));
    return pdir(dx + vx * t, dy + vy * t);
}

// 5. Broadheads: each landing looses two triples of heavy arrows at the
// player, the second turned half their spacing, which brake and burst at a
// fixed distance into a forward fan of small ones.
const BROAD = hops([{ x: 480, y: 220 }, { x: 880, y: 220 }, { x: 680, y: 290 }],
                   70, 24, 80);

function broadSplit(b, a) {
    b.run = (b.run || 0) + b.v;
    if (b.run < 330) return;
    for (let i = 0; i < 7; i++) {
        arrow(a, { x: b.x, y: b.y, v: 3, acc: 0.25, vmax: 10,
                   dir: b.dir + (i - 3) * 10, col: C.lime });
    }
    b.dead = true;
}

// 6. Ricochet: from either side he looses a string down a fan toward the far
// wall, which turns each arrow back once, so the two sides' fans cross in a
// lattice. From the middle, an aimed five-way.
const RICO = hops([{ x: 300, y: 230 }, { x: 680, y: 190 }, { x: 1060, y: 230 },
                   { x: 680, y: 190 }], 60, 24, 90);

// 7. Scramble: pure dodging. Hops of random length and timing between random
// spots, and at each landing a random aimed fan and a random spray.
function rng(seed) {
    return () => {
        seed = (seed + 0x6D2B79F5) | 0;
        let r = Math.imul(seed ^ (seed >>> 15), 1 | seed);
        r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
        return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    };
}

Sketch.set({
    id: 'astyr',
    name: "Astyr's non-spells: hops and arrows",
    patterns: [

    { name: 'Bounding volley', loop: () => BOUND.period,
      bossAt: (a) => BOUND.at(a.t),
      emit(a) {
        const s = BOUND.at(a.t), b = a.boss;
        if (s.air) return;
        if (s.u === 0) {
            for (let i = 0; i < 20; i++) {
                a.grain({ x: b.x, y: b.y + 20, v: 4.5, hold: 6, brake: 0.12,
                          flr: 1.9, dir: s.k * 9 + i * 18, col: C.bone,
                          r: PELLET });
            }
        }
        const i = (s.u - 6) / 2;
        if (i >= 0 && i < 7 && i % 1 === 0) {
            const way = Math.sign(s.to.x - s.from.x) || 1;
            arrow(a, { x: b.x, y: b.y, v: 6, acc: 0.5, vmax: 13,
                       dir: aim(a, b.x, b.y) + (i - 3) * 8 * way });
        }
      } },

    { name: 'Lofted rain', loop: () => RAIN.period,
      bossAt: (a) => RAIN.at(a.t),
      emit(a) {
        const s = RAIN.at(a.t), b = a.boss;
        if (s.air) return;
        if (s.u === 0) {
            for (let i = -1; i <= 1; i++) {
                arrow(a, { x: b.x, y: b.y, v: 12, dir: aim(a, b.x, b.y) + i * 14,
                           col: C.spring });
            }
        }
        const sweep = s.k % 2 ? 1 : -1;
        loftString(a, s, 20, sweep, 0);
        loftString(a, s, 80, -sweep, 0.5);
      } },

    { name: 'Leapfrog rings', loop: () => LEAPER.period,
      bossAt: (a) => LEAPER.at(a.t),
      emit(a) {
        const s = LEAPER.at(a.t), b = a.boss;
        if (s.u !== 4) return;
        const n = 26;
        for (let i = 0; i < n; i++) {
            arrow(a, { x: b.x, y: b.y, v: 0, off: 0, fn: bound,
                       dir: 90 + (i + (s.k % 2) / 2) * 360 / n + s.k * 3,
                       col: s.k % 2 ? C.lime : C.jade });
        }
      } },

    { name: 'Leading string', loop: () => LOOPER.period,
      bossAt: (a) => LOOPER.at(a.t),
      step(a) {
        const p = a.player, st = a.store;
        if (st.lx !== undefined) {
            st.pvx = 0.7 * (st.pvx || 0) + 0.3 * (p.x - st.lx);
            st.pvy = 0.7 * (st.pvy || 0) + 0.3 * (p.y - st.ly);
        }
        st.lx = p.x;
        st.ly = p.y;
      },
      emit(a) {
        const s = LOOPER.at(a.t), b = a.boss;
        if (a.t % 4 === 0) {
            arrow(a, { x: b.x, y: b.y, v: 13, dir: lead(a, b.x, b.y, 13) });
        }
        if (s.u === 0) {
            for (const d of [-16, 16]) {
                arrow(a, { x: b.x, y: b.y, v: 9, dir: aim(a, b.x, b.y) + d,
                           col: C.spring });
            }
        }
      } },

    { name: 'Broadheads', loop: () => BROAD.period,
      bossAt: (a) => BROAD.at(a.t),
      emit(a) {
        const s = BROAD.at(a.t), b = a.boss;
        if (s.u !== 6 && s.u !== 26) return;
        const off = s.u === 26 ? 11 : 0;
        for (let i = -1; i <= 1; i++) {
            arrow(a, { x: b.x, y: b.y, v: 9, acc: -0.12, vmax: 4, scale: 1.7,
                       dir: aim(a, b.x, b.y) + i * 22 + off, col: C.jade,
                       fn: broadSplit });
        }
      } },

    { name: 'Ricochet', loop: () => RICO.period,
      bossAt: (a) => RICO.at(a.t),
      emit(a) {
        const s = RICO.at(a.t), b = a.boss;
        if (s.air) return;
        const st = s.from;
        if (st.x === 680) {
            if (s.u === 4) {
                for (let i = -2; i <= 2; i++) {
                    arrow(a, { x: b.x, y: b.y, v: 11, col: C.spring,
                               dir: aim(a, b.x, b.y) + i * 12 });
                }
            }
            return;
        }
        const i = (s.u - 4) / 3;
        if (i < 0 || i >= 12 || i % 1) return;
        const side = st.x < 680 ? 1 : -1;       // 1 fires to the right
        const d = -8 - i * 4;                   // down from level, toward the far wall
        arrow(a, { x: b.x, y: b.y, v: 10, wall: 1, col: side > 0 ? C.jade : C.lime,
                   dir: side > 0 ? d : 180 - d });
      } },

    { name: 'Scramble', loop: () => 600,
      init(a) {
        const R = rng(7), st = a.store;
        st.R = rng(11);
        st.plan = [];
        let t = 0, from = { x: 680, y: 250 };
        while (t < 20000) {
            const sit = 12 + Math.floor(R() * 30), air = 14 + Math.floor(R() * 10);
            const to = { x: Math.max(200, Math.min(1160, from.x + (R() - 0.5) * 600)),
                         y: 180 + R() * 130 };
            st.plan.push({ t, sit, air, from, to, lift: 40 + R() * 60 });
            t += sit + air;
            from = to;
        }
        st.i = 0;
      },
      bossAt(a) {
        const st = a.store;
        while (st.plan[st.i].t + st.plan[st.i].sit + st.plan[st.i].air <= a.t) st.i++;
        const h = st.plan[st.i], u = a.t - h.t;
        st.landed = u === 0;
        if (u < h.sit) return h.from;
        const f = (u - h.sit) / h.air;
        return { x: h.from.x + (h.to.x - h.from.x) * f,
                 y: h.from.y + (h.to.y - h.from.y) * f - h.lift * 4 * f * (1 - f) };
      },
      emit(a) {
        const st = a.store, R = st.R, b = a.boss;
        if (!st.landed) return;
        const n = 3 + Math.floor(R() * 5), sp = 6 + R() * 12;
        const base = aim(a, b.x, b.y) + (R() - 0.5) * 20;
        for (let i = 0; i < n; i++) {
            arrow(a, { x: b.x, y: b.y, v: 10 + R() * 3,
                       dir: base + (i - (n - 1) / 2) * sp });
        }
        for (let i = 0; i < 10; i++) {
            arrow(a, { x: b.x, y: b.y, v: 4 + R() * 6, dir: 200 + R() * 140,
                       col: C.lime });
        }
      } },

    ],
});
})();
