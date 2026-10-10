// Candidates for Faol's non-spells: water and seaweed, from his lake. No
// gimmick (his sinking is for his spells). Sketches only; none is in the game.
(function () {
'use strict';
// The game's bullet hues (`palette`): water in cyan, azure and spring, weed
// in jade and lime, foam in bone.
const C = { cyan: '#38d6ff', azure: '#448cff', spring: '#2ce2be', jade: '#2cdc76',
            lime: '#96f03c', bone: '#e8eeff' };
const ORB = 7.0, BALL = 15.0;      // hit radii (`bullet_table`)
const PI = Math.PI;
const dcos = (d) => Math.cos(d * PI / 180), dsin = (d) => Math.sin(d * PI / 180);
const pdir = (dx, dy) => Math.atan2(-dy, dx) * 180 / PI;

// The "small" toggle draws and hits each bullet a size down (a ball as an
// orb, an orb as a pellet), which can read better in a sketch.
const size = (a, r) => (!a.opts.small ? r : r >= BALL ? ORB : 3.3);

// A shot. Polar: speed `v` heading `dir`, changing speed by `acc` a frame
// until `vto`, turning `turn` a frame, its vertical motion squashed by `q`
// (a ripple on a surface seen at an angle). Or, with `vx` set, Cartesian:
// `vx`, `vy` with `gx`, `gy` added each frame (gravity, or a bubble's lift).
// Either way `sink` adds a drift downward each frame up to `sinkTo`, and
// `wob` sways it sideways that far (`wobF` radians a frame). `ev` is a list
// of [age, fn(b, a)] run as it reaches each age; `on(b, a)` runs every frame.
function shot(a, o) {
    const b = a.bullet(Object.assign({ v: 0, dir: 270, acc: 0, vto: 0, turn: 0, q: 1,
                                       step: move }, o));
    b.r = size(a, b.r);
    return b;
}

function move(b, a) {
    while (b.ev && b.ev.length && b.ev[0][0] <= b.age) b.ev.shift()[1](b, a);
    if (b.vx !== undefined) {
        b.vx += b.gx || 0;
        b.vy += b.gy || 0;
        b.x += b.vx;
        b.y += b.vy;
        b.dir = pdir(b.vx, b.vy);
    } else {
        if (b.acc) b.v = b.acc > 0 ? Math.min(b.vto, b.v + b.acc) : Math.max(b.vto, b.v + b.acc);
        b.dir += b.turn;
        b.x += dcos(b.dir) * b.v;
        b.y -= dsin(b.dir) * b.v * b.q;
    }
    if (b.sink) {
        b.dy = Math.min(b.sinkTo, (b.dy || 0) + b.sink);
        b.y += b.dy;
    }
    if (b.wob) b.x += b.wob * Math.sin(b.age * b.wobF + (b.wobP || 0));
    if (b.on) b.on(b, a);
}

// ---- Ripples -------------------------------------------------------------------

// Every 70 frames a drip falls from him and lands 36 frames later at the
// next of six spots across the middle of the field. Where it lands, three
// rings of 18 spread, 8 frames apart, flattened to 0.55 as ripples on a lake
// seen at an angle: each ring slower than the last (4.5, 3.6, 2.7), and each
// slowing to a crawl. 80 frames on they begin to sink, drifting down at up
// to 1.2.
const DRIPS = [[-380, 560], [260, 640], [-120, 520], [420, 600], [-300, 660], [100, 580]];
const RIPPLE = [[4.5, 0.8, C.cyan], [3.6, 0.6, C.azure], [2.7, 0.4, C.bone]];

function ripples(a) {
    if (a.t % 70 !== 1) return;
    const k = Math.floor(a.t / 70), [dx, ly] = DRIPS[k % DRIPS.length];
    const x0 = a.boss.x, y0 = a.boss.y + 30, T = 36, g = 0.3;
    const lx = a.GAME.fieldW / 2 + dx;
    shot(a, { x: x0, y: y0, vx: (lx - x0) / T, vy: (ly - y0 - g * T * (T + 1) / 2) / T, gy: g,
              r: ORB, col: C.bone,
              ev: [[T, (b, api) => {
                  RIPPLE.forEach(([v, crawl, col], ring) => {
                      for (let i = 0; i < 18; i++) {
                          shot(api, { x: b.x, y: b.y, v: 0, q: 0.55, r: ORB, col,
                                      dir: i * 20 + ring * 10,
                                      ev: [[ring * 8, (r) => { r.v = v; r.acc = -0.07; r.vto = crawl; }],
                                           [ring * 8 + 80, (r) => { r.sink = 0.02; r.sinkTo = 1.2; }]] });
                      }
                  });
                  b.dead = true;
              }]] });
}

// ---- Fountain --------------------------------------------------------------------

// Every 40 frames he sends up a jet, alternately leaning left and right:
// eleven drops (speeds 9 to 11, 12 to 42 degrees off straight up) that arc
// under gravity. A drop falling through the lake's surface (y 600) splashes:
// it becomes a crown of five drops thrown back up (speed 4) that arc and
// fall in turn, and a drop entering the water slows to 0.3 of its speed and
// sinks, gathering speed slowly.
const SURF = 600, GRAV = 0.22;

function enterWater(b) {
    if (b.wet || b.vy <= 0 || b.y < SURF) return;
    b.wet = true;
    b.vx *= 0.3;
    b.vy *= 0.3;
    b.gy = 0.015;
}

function fountain(a) {
    if (a.t % 40 !== 1) return;
    const m = Math.floor(a.t / 40) % 2 ? -1 : 1;
    for (let i = 0; i < 11; i++) {
        const d = 90 - m * (12 + i * 3), v = 9 + (i % 3);
        shot(a, { x: a.boss.x + m * 30, y: a.boss.y, vx: dcos(d) * v, vy: -dsin(d) * v, gy: GRAV,
                  r: ORB, col: i % 2 ? C.azure : C.cyan,
                  on: (b, api) => {
                      if (b.vy <= 0 || b.y < SURF) return;
                      for (let j = 0; j < 5; j++) {
                          const cd = 50 + j * 20;
                          shot(api, { x: b.x, y: SURF - 1, vx: dcos(cd) * 4, vy: -dsin(cd) * 4,
                                      gy: GRAV, r: ORB, col: j % 2 ? C.bone : C.spring,
                                      on: enterWater });
                      }
                      b.dead = true;
                  } });
    }
}

// ---- Kelp ------------------------------------------------------------------------

// Every 240 frames four fronds of seaweed grow from his waist, two each side
// (fourteen links 26 px apart, one more every 3 frames), and sway in a wave
// that runs down them, wider toward the tips (up to 60 px, 100 frames a sway).
// 150 frames in, every other link comes loose as a leaf and drifts off the
// way it was swaying, fluttering and slowly sinking; from 190 the rest of
// each frond draws back in, gone by 220. Alternate rounds grow at other angles.
const KELP = { links: 14, gap: 26, grow: 3, amp: 60, P: 100, wave: 0.45, loose: 150,
               back: 190, gone: 220, every: 240 };
const KELP_ANGLES = [[235, 255, 285, 305], [225, 262, 278, 315]];

function kelpAt(f, j, t) {
    const pull = t < KELP.back ? 1 : Math.max(0, 1 - (t - KELP.back) / (KELP.gone - KELP.back));
    const d = (j + 1) * KELP.gap * pull;
    const off = KELP.amp * Math.pow((j + 1) / KELP.links, 1.5)
                * Math.sin(2 * PI * t / KELP.P - KELP.wave * j + f.ph);
    return { x: f.x + dcos(f.dir) * d + dcos(f.dir + 90) * off,
             y: f.y - dsin(f.dir) * d - dsin(f.dir + 90) * off };
}

function kelpLink(b, a) {
    const t = a.t - b.f.t0;
    if (t > KELP.gone) { b.dead = true; return; }
    const q = kelpAt(b.f, b.j, t);
    if (t === KELP.loose && b.j % 2 === 1) {
        const p = kelpAt(b.f, b.j, t - 1);
        Object.assign(b, { step: move, x: q.x, y: q.y, vx: q.x - p.x, vy: q.y - p.y, gy: 0.012,
                           wob: 1.1, wobF: 0.09, wobP: b.j });
        return;
    }
    b.x = q.x;
    b.y = q.y;
}

function kelp(a) {
    const s = a.store;
    if (a.t % KELP.every === 1) {
        const set = KELP_ANGLES[Math.floor(a.t / KELP.every) % 2];
        s.fronds = set.map((dir, i) => ({ t0: a.t, x: a.boss.x, y: a.boss.y + 40, dir,
                                          ph: i * 1.3, made: 0 }));
    }
    for (const f of s.fronds || []) {
        const t = a.t - f.t0;
        while (f.made < KELP.links && f.made * KELP.grow <= t && t < KELP.loose) {
            const j = f.made++, tip = j === KELP.links - 1;
            a.bullet({ x: f.x, y: f.y, f, j, r: size(a, tip ? BALL : ORB),
                       col: tip ? C.spring : j % 2 ? C.lime : C.jade, step: kelpLink });
        }
    }
}

// ---- Bubbles -----------------------------------------------------------------------

// Every 45 frames he blows three bubbles down in a fan (turning 20 degrees a
// volley): thrown at 7, they rise back as their lift (0.12 a frame) takes
// over, swaying side to side, and at 130 frames each pops into a ring of ten
// drops that set off slowly (1.5), speed up to 3.5 and sink a little.
function bubbles(a) {
    if (a.t % 45 !== 1) return;
    const base = (Math.floor(a.t / 45) % 3) * 20 - 20;
    for (let i = -1; i <= 1; i++) {
        const d = 270 + base + i * 28;
        shot(a, { x: a.boss.x, y: a.boss.y + 30, vx: dcos(d) * 7, vy: -dsin(d) * 7, gy: -0.12,
                  r: BALL, col: C.cyan, hollow: true, wob: 0.9, wobF: 0.08, wobP: i,
                  ev: [[130, (b, api) => {
                      for (let k = 0; k < 10; k++) {
                          shot(api, { x: b.x, y: b.y, dir: k * 36 + 18 * (i + 1), v: 1.5,
                                      acc: 0.04, vto: 3.5, sink: 0.01, sinkTo: 0.8,
                                      r: ORB, col: k % 2 ? C.azure : C.bone });
                      }
                      b.dead = true;
                  }]] });
    }
}

// ---- Tide ----------------------------------------------------------------------------

// Every 100 frames a wave rolls in: 36 drops across the field, its line a
// sine 40 px high and 340 px long, sinking at 1.8 a frame while the wave runs
// sideways (alternate waves the other way), so each drop bobs as it passes.
// 100 frames in, the drops at the crests whiten into foam; 20 frames later
// they break, spilling forward and speeding up to 5, while the rest roll on.
const TIDE = { n: 36, amp: 40, len: 340, sink: 1.8, run: 0.05, foam: 100, breaks: 120 };

function tideDrop(b, a) {
    const w = b.w, t = a.t - w.t0;
    const s = Math.sin(2 * PI * b.x / TIDE.len + w.way * TIDE.run * t);
    if (t === TIDE.foam && s > 0.55) { b.crest = true; b.col = C.bone; }
    if (t === TIDE.breaks && b.crest) {
        Object.assign(b, { step: move, v: 2, dir: 270 - w.way * 15, acc: 0.1, vto: 5 });
        return;
    }
    b.y = w.y + TIDE.sink * t + TIDE.amp * s;
}

function tide(a) {
    if (a.t % 100 !== 1) return;
    const way = Math.floor(a.t / 100) % 2 ? -1 : 1;
    const w = { t0: a.t, y: a.boss.y + 60, way };
    for (let i = 0; i < TIDE.n; i++) {
        a.bullet({ x: 20 + i * (a.GAME.fieldW - 40) / (TIDE.n - 1), y: w.y, w, r: size(a, ORB),
                   col: i % 2 ? C.spring : C.azure, step: tideDrop });
    }
}

Sketch.set({
    id: 'faol',
    name: "Faol's non-spells: water and weed",
    toggles: [{ id: 'small', label: 'Small bullets' }],
    patterns: [
        { name: 'Ripples', loop: () => 420, emit: ripples },
        { name: 'Fountain', loop: () => 80, emit: fountain },
        { name: 'Kelp', loop: () => 480, emit: kelp },
        { name: 'Bubbles', loop: () => 270, emit: bubbles },
        { name: 'Tide', loop: () => 200, emit: tide },
    ],
});
})();
