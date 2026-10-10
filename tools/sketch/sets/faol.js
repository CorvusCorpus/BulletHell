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

// Four fronds of seaweed grow from his waist at the start, a link every 2
// frames, and stay for the whole attack. Each is a chain of 15 links 26 px
// apart whose every segment bends: a sway that runs down it (up to 22 degrees
// at the tip, 120 frames a sway) and a current that leans every frond the same
// way, turning slowly from 25 degrees one side to 25 the other and back over
// 480 frames. Their links hurt like any bullet, and have no age limit.
const FROND = { links: 15, gap: 26, grow: 2, sway: 22, P: 120, wave: 0.5, lean: 25, L: 480 };
const FROND_BASE = [215, 245, 295, 325];

// Frond `f`'s points (root first) and segment headings at frame `t`.
function frondPath(f, t) {
    if (f.at === t) return f.path;
    const cur = FROND.lean * Math.sin(2 * PI * t / FROND.L);
    const pts = [{ x: f.x, y: f.y }], angs = [];
    for (let j = 0; j < FROND.links; j++) {
        const k = (j + 1) / FROND.links;
        const ang = f.base + cur * k + FROND.sway * k * Math.sin(2 * PI * t / FROND.P - FROND.wave * j + f.ph);
        const p = pts[j];
        pts.push({ x: p.x + dcos(ang) * FROND.gap, y: p.y - dsin(ang) * FROND.gap });
        angs.push(ang);
    }
    f.at = t;
    f.path = { pts, angs };
    return f.path;
}

function frondLink(b, a) {
    const q = frondPath(b.f, a.t).pts[b.j + 1];
    b.x = q.x;
    b.y = q.y;
    if (b.pod) b.pod(b, a);
}

// Grow the fronds a link at a time; `dress(f, j)` gives a link extra fields.
function growFronds(a, dress) {
    const s = a.store;
    if (!s.fronds) {
        s.fronds = FROND_BASE.map((base, i) => ({ x: a.boss.x, y: a.boss.y + 40, base,
                                                  ph: i * 1.3, made: 0 }));
    }
    for (const f of s.fronds) {
        while (f.made < FROND.links && f.made * FROND.grow <= a.t) {
            const j = f.made++;
            a.bullet(Object.assign({ x: f.x, y: f.y, f, j, r: size(a, ORB), life: Infinity,
                                     col: j % 2 ? C.lime : C.jade, step: frondLink }, dress(f, j)));
        }
    }
    return s.fronds;
}

// Kelp hoses: from 40 frames in, each frond's tip sprays in dashes (a drop
// every 4 frames for 24 frames, then 16 frames off, the fronds staggered by
// 10) along the way the tip points (6, slowing to 2.6), so the swaying tips
// lay four waving streams, broken into dashes you can slip between, that
// sweep across as the current turns. Every 80 frames
// the bladder halfway along each frond puffs three drops at the player (10
// degrees apart) that set off slowly (2) and speed up to 5.
function kelpHoses(a) {
    const fronds = growFronds(a, (f, j) => (
        j === FROND.links - 1 ? { r: size(a, BALL), col: C.spring }
        : j === 7 ? { r: size(a, BALL), col: C.jade } : {}));
    if (a.t < 40) return;
    fronds.forEach((f, i) => {
        const { pts, angs } = frondPath(f, a.t);
        if (a.t % 4 === 0 && (a.t + i * 10) % 40 < 24) {
            const tip = pts[FROND.links];
            shot(a, { x: tip.x, y: tip.y, dir: angs[FROND.links - 1], v: 6, acc: -0.15, vto: 2.6,
                      r: ORB, col: i % 2 ? C.azure : C.cyan });
        }
        if (a.t % 80 === 0) {
            const q = pts[8], aim = pdir(a.player.x - q.x, a.player.y - q.y);
            for (const off of [-10, 0, 10]) {
                shot(a, { x: q.x, y: q.y, dir: aim + off, v: 2, acc: 0.08, vto: 5,
                          r: ORB, col: C.spring });
            }
        }
    });
}

// Kelp bladders: each frond carries four pods (links 4, 8, 12 and its tip)
// that swell over 50 frames from an orb to a ball and pop into a ring of ten
// drops that set off slowly (1) and speed up to 3.5, then grow back. A frond's
// pods pop root to tip, 12 frames apart, every 160 frames, the fronds taking
// turns 40 frames apart.
const PODS = [3, 7, 11, 14], POD_CYCLE = 160, POD_GAP = 12, POD_SWELL = 50;

function kelpPod(b, a) {
    const u = (a.t - b.popAt) % POD_CYCLE;          // frames since this pod last popped
    const small = size(a, ORB), big = size(a, BALL);
    const left = POD_CYCLE - u;                     // frames until it pops again
    b.r = left <= POD_SWELL ? small + (big - small) * (1 - left / POD_SWELL) : small;
    if (u === 0 && a.t > 40) {
        for (let k = 0; k < 10; k++) {
            shot(a, { x: b.x, y: b.y, dir: k * 36 + b.j * 9, v: 1, acc: 0.05, vto: 3.5,
                      r: ORB, col: k % 2 ? C.cyan : C.spring });
        }
    }
}

function kelpBladders(a) {
    growFronds(a, (f, j) => {
        const n = PODS.indexOf(j);
        if (n < 0) return {};
        const i = FROND_BASE.indexOf(f.base);
        return { col: C.spring, pod: kelpPod, popAt: 40 + i * 40 + n * POD_GAP };
    });
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
        { name: 'Kelp hoses', loop: () => 480, emit: kelpHoses },
        { name: 'Kelp bladders', loop: () => 480, emit: kelpBladders },
        { name: 'Bubbles', loop: () => 270, emit: bubbles },
        { name: 'Tide', loop: () => 200, emit: tide },
    ],
});
})();
