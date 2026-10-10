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

// Fronds of seaweed grow from his waist, one link at a time, and sway in a
// wave that runs down them, wider toward the tip. A frond's `cfg`: `links`
// `gap` px apart, one more every `grow` frames; sway up to `amp` px at the
// tip, `P` frames a sway, `wave` radians of lag a link; from `back` it draws
// back in, gone by `gone`.
function frondAt(f, j, t) {
    const c = f.cfg;
    const pull = t < c.back ? 1 : Math.max(0, 1 - (t - c.back) / (c.gone - c.back));
    const d = (j + 1) * c.gap * pull;
    const off = c.amp * Math.pow((j + 1) / c.links, 1.5)
                * Math.sin(2 * PI * t / c.P - c.wave * j + f.ph);
    return { x: f.x + dcos(f.dir) * d + dcos(f.dir + 90) * off,
             y: f.y - dsin(f.dir) * d - dsin(f.dir + 90) * off };
}

function frondLink(b, a) {
    const t = a.t - b.f.t0;
    if (t > b.f.cfg.gone || b.f.cut) { b.dead = true; return; }
    const q = frondAt(b.f, b.j, t);
    b.x = q.x;
    b.y = q.y;
}

// Grow each frond in `fronds` a link at a time.
function growFronds(a, fronds) {
    for (const f of fronds) {
        const c = f.cfg, t = a.t - f.t0;
        while (f.made < c.links && f.made * c.grow <= t && t < c.back) {
            const j = f.made++, tip = j === c.links - 1;
            a.bullet({ x: f.x, y: f.y, f, j, r: size(a, tip ? BALL : ORB),
                       col: tip ? C.spring : j % 2 ? C.lime : C.jade, step: frondLink });
        }
    }
}

// Kelp curtains: every 300 frames three long fronds (16 links, 448 px) fan
// out below him, alternate rounds 15 degrees round, swaying up to 70 px. From
// 40 frames in until they draw back, every 30 frames each frond sheds a drop
// from every other link from the sixth out, all at once and all drifting
// square to the frond the way its tip is swaying (2.2, easing to 1.4) and
// sinking (up to 1.2): each shed is a wavy copy of the frond that peels away
// and sinks.
const CURTAIN = { links: 16, gap: 28, grow: 2, amp: 70, P: 120, wave: 0.4, back: 240, gone: 280 };

function kelpCurtains(a) {
    const s = a.store;
    if (a.t % 300 === 1) {
        const turn = Math.floor(a.t / 300) % 2 ? 15 : 0;
        s.fronds = [225, 270, 315].map((dir, i) => (
            { t0: a.t, x: a.boss.x, y: a.boss.y + 40, dir: dir + turn, ph: i * 1.1, made: 0,
              cfg: CURTAIN }));
    }
    const fronds = s.fronds || [];
    growFronds(a, fronds);
    for (const f of fronds) {
        const t = a.t - f.t0;
        if (t < 40 || t >= CURTAIN.back || t % 30) continue;
        const tip = CURTAIN.links - 1;
        const sway = Math.sign(Math.cos(2 * PI * t / CURTAIN.P - CURTAIN.wave * tip + f.ph)) || 1;
        for (let j = 5; j < CURTAIN.links; j += 2) {
            const q = frondAt(f, j, t);
            shot(a, { x: q.x, y: q.y, dir: f.dir + 90 * sway, v: 2.2, acc: -0.02, vto: 1.4,
                      sink: 0.015, sinkTo: 1.2, r: ORB, col: (t / 30) % 2 ? C.azure : C.cyan });
        }
    }
}

// Reaching kelp: every 150 frames three fronds reach out, one at the player
// and one 28 degrees either side, growing fast (18 links, 504 px, a link a
// frame), and sway gently (up to 40 px). 60 frames in they burst: from the
// third link out, each leaf peels off square to the frond, alternately to
// either side, setting off slowly and speeding up to 3.5, so each frond
// becomes two lines opening apart; its tip pops into a ring of eight.
const REACH = { links: 18, gap: 28, grow: 1, amp: 40, P: 90, wave: 0.35, back: 1e9, gone: 1e9 };

function reachingKelp(a) {
    const s = a.store;
    if (a.t % 150 === 1) {
        const aim = pdir(a.player.x - a.boss.x, a.player.y - a.boss.y - 40);
        s.fronds = [-28, 0, 28].map((off, i) => (
            { t0: a.t, x: a.boss.x, y: a.boss.y + 40, dir: aim + off, ph: i * 1.7, made: 0,
              cfg: REACH }));
    }
    const fronds = s.fronds || [];
    growFronds(a, fronds);
    for (const f of fronds) {
        if (a.t - f.t0 !== 60) continue;
        const t = 60;
        for (let j = 2; j < REACH.links; j++) {
            const q = frondAt(f, j, t), side = j % 2 ? 90 : -90;
            if (j === REACH.links - 1) {
                for (let k = 0; k < 8; k++) {
                    shot(a, { x: q.x, y: q.y, dir: f.dir + k * 45, v: 0.5, acc: 0.06, vto: 3,
                              r: ORB, col: C.spring });
                }
                continue;
            }
            shot(a, { x: q.x, y: q.y, dir: f.dir + side, v: 0.4, acc: 0.05, vto: 3.5,
                      r: ORB, col: side > 0 ? C.jade : C.lime });
        }
        f.cut = true;
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
        { name: 'Kelp curtains', loop: () => 600, emit: kelpCurtains },
        { name: 'Reaching kelp', loop: () => 150, emit: reachingKelp },
        { name: 'Bubbles', loop: () => 270, emit: bubbles },
        { name: 'Tide', loop: () => 200, emit: tide },
    ],
});
})();
