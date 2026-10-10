// Candidates for Sylvia's non-spells: spirals and lasers in the colours of his
// eye (a cyan iris, its blades magenta and indigo). Sketches only; none is in
// the game. Lasers here are the engine's model of `laser_functions`. The "Two
// spirals" patterns are the owner's idea; the rest are first candidates.
(function () {
'use strict';
// The game's bullet hues (`palette`).
const C = { cyan: '#38d6ff', azure: '#448cff', magenta: '#f848e0',
            rose: '#ff80b2', indigo: '#745cff', violet: '#b054fa',
            bone: '#e8eeff' };
const ORB = 7.0, BALL = 15.0;      // hit radii (`bullet_table`)
// The "small" toggle draws and hits each a size down (a ball as an orb, an
// orb as a pellet), which can read better in a sketch.
const size = (a, r) => (a.opts.small ? (r >= BALL ? ORB : 3.3) : r);
const PI = Math.PI;
const dcos = (d) => Math.cos(d * PI / 180), dsin = (d) => Math.sin(d * PI / 180);
const pdir = (dx, dy) => Math.atan2(-dy, dx) * 180 / PI;

// A plain shot: `v` heading `dir`, turning `turn` degrees a frame. From age
// `from` it changes speed by `acc` a frame until it reaches `vto`. `ease`
// scales the turn each frame. `sp` ([t0, c]) bends it along the Iris's spiral
// instead: at its first speed it turns t0 * c / (age + c), and it turns by the
// distance it has come, so slowing down doesn't tighten the curl. `then(b, a)`
// runs once at age `at`.
function shot(a, o) {
    const b = a.bullet(Object.assign({ v: 4, dir: 270, turn: 0, ease: 1, acc: 0,
                                       vto: 0, from: 0, step: moveShot }, o));
    b.r = size(a, b.r);
    b.v0 = b.v;
    b.s = 0;
    return b;
}

function moveShot(b, a) {
    if (b.acc && b.age >= b.from) {
        b.v = b.acc > 0 ? Math.min(b.vto, b.v + b.acc) : Math.max(b.vto, b.v + b.acc);
    }
    if (b.sp) b.turn = b.v * b.sp[0] * b.sp[1] / (b.s + b.sp[1] * b.v0);
    b.s += b.v;
    b.dir += b.turn;
    b.turn *= b.ease;
    b.x += a.dcos(b.dir) * b.v;
    b.y -= a.dsin(b.dir) * b.v;
    if (b.then && b.age === b.at) b.then(b, a);
}

// The Iris's spiral: degrees a frame at first, and how fast that eases off.
const SP = [3.2, 20];

// The Pupil's almond: two curved lasers from (x0, y0) to (x1, y1), bowed out
// `w` either side of the line between, drawn in `frames` (a curve keeps at
// most 64 nodes, so 63 or fewer leaves the whole almond standing).
function almond(a, x0, y0, x1, y1, w, frames, hold, col) {
    const L = Math.hypot(x1 - x0, y1 - y0), R = (L * L / 4 + w * w) / (2 * w);
    const half = Math.asin(L / (2 * R)) * 180 / Math.PI;
    const arc = R * 2 * half * Math.PI / 180;
    const chord = a.pdir(x1 - x0, y1 - y0);
    for (const s of [1, -1]) {
        a.laser({ kind: 'curve', x: x0, y: y0, dir: chord - s * half,
                  turn: s * 2 * half / frames, spd: arc / frames, hot: frames,
                  hold, wid: 26, col });
    }
}

// ---- Two spirals --------------------------------------------------------------

// Sylvia draws two spirals of still pellets side by side, mirror images, the
// left cyan and the right magenta. A pen (an orb) flies from him to each
// spiral's centre in `reach` frames and winds outward at `pen` pixels a frame,
// leaving an orb every `gap` pixels. After `pause` frames the spirals come
// alive (each pattern differently), and a pellet bounces once off a side wall
// (the game's bullets have no bounce yet). He hops after each pair, holding
// `hold` frames. The spiral winds `turns` times from radius `r0` to `r1`,
// counterclockwise from bearing `a0`; the centres are `dx` either side of him
// and `dy` below. Interleaved, every second orb is a second shade (blue on
// the left, white on the right) and moves at `slow` times the speed.
const SPI = { dx: 300, dy: 170, r0: 18, r1: 190, turns: 2.5, a0: 270,
              gap: 30, reach: 20, pen: 16, pause: 22, hold: 210, slow: 0.6 };

// The left spiral's path from its centre, a point every pixel along it:
// {x, y, ang (bearing from the centre), th (degrees wound), dir (heading)}.
const PATH = (() => {
    const out = [], TH = SPI.turns * 360;
    let len = 0, next = 0, px = 0, py = 0;
    for (let th = 0; th <= TH; th += 0.02) {
        const r = SPI.r0 + (SPI.r1 - SPI.r0) * th / TH, ang = SPI.a0 + th;
        const x = dcos(ang) * r, y = -dsin(ang) * r;
        if (th > 0) len += Math.hypot(x - px, y - py);
        if (len >= next) { out.push({ x, y, ang, th }); next += 1; }
        px = x; py = y;
    }
    for (let k = 0; k < out.length; k++) {
        const q = out[Math.min(k + 1, out.length - 1)], o = out[Math.max(0, Math.min(k, out.length - 2))];
        out[k].dir = pdir(q.x - o.x, q.y - o.y);
    }
    return out;
})();
const SPI_N = Math.floor((PATH.length - 1) / SPI.gap) + 1;   // pellets a spiral
// Frames from a pair's start to its coming alive.
const SPI_LIVE = SPI.reach + Math.ceil((PATH.length - 1) / SPI.pen) + SPI.pause;

// Start a pair at the top of each hold; `mode` brings it alive. `twin`
// interleaves it; `rev`, if given, is the frame of the pair its orbs reverse
// (see `reversal`).
function spirals(a, mode, twin = false, rev = undefined) {
    if (a.t % (SPI.hold + a.GAME.stepMove) !== 1) return;
    const pair = { t0: a.t };
    for (const m of [1, -1]) {
        a.bullet({ x: a.boss.x, y: a.boss.y, sx: a.boss.x, sy: a.boss.y,
                   ox: a.boss.x - m * SPI.dx, oy: a.boss.y + SPI.dy, m, pair, mode,
                   col: m > 0 ? C.cyan : C.magenta, r: size(a, BALL), next: 0, step: penStep,
                   col2: twin ? (m > 0 ? C.azure : C.bone) : null, rev });
    }
}

function penStep(b, a) {
    const T = a.t - b.pair.t0;
    if (T <= SPI.reach) {
        const e = 1 - Math.pow(1 - T / SPI.reach, 2);
        b.x = b.sx + (b.ox - b.sx) * e;
        b.y = b.sy + (b.oy - b.sy) * e;
        return;
    }
    const s = Math.min(PATH.length - 1, (T - SPI.reach) * SPI.pen);
    const q = PATH[Math.floor(s)];
    b.x = b.ox + b.m * q.x;
    b.y = b.oy + q.y;
    while (b.next < SPI_N && b.next * SPI.gap <= s) {
        const k = b.next++, p = PATH[k * SPI.gap], two = b.col2 && k % 2;
        a.bullet({ x: b.ox + b.m * p.x, y: b.oy + p.y, ox: b.ox, oy: b.oy, m: b.m,
                   k, p, pair: b.pair, mode: b.mode, col: two ? b.col2 : b.col,
                   f: two ? SPI.slow : 1, revAt: b.rev, r: size(a, ORB),
                   v: 0, dir: 0, live: false, rot: 0, bounced: false,
                   step: pelletStep });
    }
    if (s >= PATH.length - 1) b.dead = true;
}

// Mirror a heading for the right-hand spiral (m = -1).
const mir = (m, d) => (m > 0 ? d : 180 - d);

function pelletStep(b, a) {
    const T = a.t - b.pair.t0;
    if (!b.live) {
        b.mode.wait(b, T);
        if (!b.live) return;
    }
    if (!reversal(b, T) && b.acc) b.v = Math.min(b.vto, b.v + b.acc);
    if (b.curl && !b.bounced) { b.dir += b.curl; b.curl *= REV.ease; }
    b.x += dcos(b.dir) * b.v;
    b.y -= dsin(b.dir) * b.v;
    if (!b.bounced && (b.x < 0 || b.x > a.GAME.fieldW)) {
        b.x = b.x < 0 ? -b.x : 2 * a.GAME.fieldW - b.x;
        b.dir = 180 - b.dir;
        b.bounced = true;
    }
}

// A reversal: at frame `revAt` of its pair an orb brakes over `brake` frames
// to `low` of its speed, flips the part of its heading that circles its
// spiral's centre, so that it swirls the other way, and speeds back up over
// `again` frames. From the flip it also curls that way, `curl` degrees a frame
// shrinking by `ease` a frame, so it spirals rather than kinking. True while
// it holds the orb's speed. An orb that has bounced is left alone.
const REV = { brake: 12, low: 0.3, again: 20, curl: 1.4, ease: 0.975 };
function reversal(b, T) {
    if (b.revAt === undefined || b.bounced) return false;
    const u = T - b.revAt;
    if (u < 0 || u >= REV.brake + REV.again) return false;
    if (u === 0) b.vrev = b.v;
    if (u < REV.brake) {
        b.v = b.vrev * (1 - (1 - REV.low) * (u + 1) / REV.brake);
        return true;
    }
    if (u === REV.brake) {
        const rx = b.x - b.ox, ry = b.y - b.oy, rl = Math.hypot(rx, ry) || 1;
        const ux = rx / rl, uy = ry / rl, vx = dcos(b.dir), vy = -dsin(b.dir);
        const vr = vx * ux + vy * uy;
        b.dir = pdir(2 * vr * ux - vx, 2 * vr * uy - vy);
        b.curl = Math.sign(ux * dsin(b.dir) + uy * dcos(b.dir)) * REV.curl;
    }
    b.v = b.vrev * (REV.low + (1 - REV.low) * (u - REV.brake + 1) / REV.again);
    return true;
}

// Peel: from the loose outer end inward over `span` frames, each pellet sets
// off along the spiral's own heading where it lies, easing up from still.
const PEEL = { span: 72, acc: 0.06, vto: 3.4 };
const peel = { wait(b, T) {
    if (T < SPI_LIVE + PEEL.span * (SPI_N - 1 - b.k) / SPI_N) return;
    Object.assign(b, { live: true, dir: mir(b.m, b.p.dir), acc: PEEL.acc * b.f,
                       vto: PEEL.vto * b.f });
} };

// Spin and fling: each spiral turns as a whole the way that unwinds it,
// spinning up over `ramp` frames to `spin` degrees a frame, and at `at` frames
// every pellet is let go along its circle at the speed it had there (plus
// `kick`), so the outer turns fly fastest.
const FLING = { ramp: 40, spin: 2.0, at: 64, kick: 1.0 };
const fling = { wait(b, T) {
    const u = T - SPI_LIVE;
    if (u < 0) return;
    const w = FLING.spin * Math.min(1, u / FLING.ramp);
    b.rot -= b.m * w;
    const r = Math.hypot(b.p.x, b.p.y), ang = mir(b.m, b.p.ang) + b.rot;
    b.x = b.ox + dcos(ang) * r;
    b.y = b.oy - dsin(ang) * r;
    if (u < FLING.at) return;
    Object.assign(b, { live: true, dir: ang - b.m * 90,
                       v: (w * PI / 180 * r + FLING.kick) * b.f, acc: 0 });
} };

// Inside out: each pellet sets off straight away from its spiral's centre,
// the innermost first, the last `span` frames after; easing up to `vto`, the
// inner turns catch the outer and pass through them, so each spiral turns
// inside out into its mirror image. (At half the span it would settle into a
// ring instead, which is near what the slower orbs of an interleaved pair do.)
const INOUT = { acc: 0.06, vto: 4.0 };
INOUT.span = 2 * (SPI.r1 - SPI.r0) / INOUT.vto;
const inout = { wait(b, T) {
    if (T < SPI_LIVE + INOUT.span * b.p.th / (SPI.turns * 360)) return;
    Object.assign(b, { live: true, dir: mir(b.m, b.p.ang), acc: INOUT.acc * b.f,
                       vto: INOUT.vto * b.f });
} };

// The Iris Rim's three arcs: radius round him, and degrees a frame (a third of
// a turn in 70 frames).
const RIM_R = 200, RIM_TURN = 120 / 70;

Sketch.set({
    id: 'sylvia',
    name: "Sylvia's non-spells: spirals and lasers",
    toggles: [{ id: 'small', label: 'Small bullets' }],
    patterns: [

    { name: 'Two spirals: peel', boss: 'step', hold: SPI.hold,
      loop: () => 2 * (SPI.hold + 45), emit(a) { spirals(a, peel); } },

    { name: 'Two spirals: spin and fling', boss: 'step', hold: SPI.hold,
      loop: () => 2 * (SPI.hold + 45), emit(a) { spirals(a, fling); } },

    { name: 'Two spirals: inside out', boss: 'step', hold: SPI.hold,
      loop: () => 2 * (SPI.hold + 45), emit(a) { spirals(a, inout); } },

    // Peel and fling again, but partway out every orb reverses its swirl
    // (`reversal`): 80 frames into a peel, 36 frames after a fling.
    { name: 'Two spirals: peel, reversing', boss: 'step', hold: SPI.hold,
      loop: () => 2 * (SPI.hold + 45),
      emit(a) { spirals(a, peel, false, SPI_LIVE + 80); } },

    { name: 'Two spirals: spin and fling, reversing', boss: 'step', hold: SPI.hold,
      loop: () => 2 * (SPI.hold + 45),
      emit(a) { spirals(a, fling, false, SPI_LIVE + FLING.at + 36); } },

    { name: 'Two spirals: spin and fling, interleaved', boss: 'step', hold: SPI.hold,
      loop: () => 2 * (SPI.hold + 45), emit(a) { spirals(a, fling, true); } },

    { name: 'Two spirals: inside out, interleaved', boss: 'step', hold: SPI.hold,
      loop: () => 2 * (SPI.hold + 45), emit(a) { spirals(a, inout, true); } },

    // Every 100 frames six blades (curved lasers, magenta and indigo by
    // turns) unfurl from him along a spiral. A strand of cyan orbs streams
    // out along the same spiral midway between each pair of blades, slowing
    // all the way. The iris
    // turns 0.3 degrees a frame. A game curve turns at a fixed rate and so
    // draws a circle; this needs its turn to ease off as it goes out.
    { name: 'Iris', loop: () => 400,
      emit(a) {
        const base = a.t * 0.3;
        if (a.t % 100 === 1) {
            for (let k = 0; k < 6; k++) {
                a.laser({ kind: 'curve', x: a.boss.x, y: a.boss.y,
                          dir: base + k * 60, spd: 7, hot: 110, wid: 22,
                          col: k % 2 ? C.indigo : C.magenta,
                          step: (l) => { l.turn = SP[0] * SP[1] / (l.age + SP[1]); } });
            }
        }
        if (a.t % 5 === 0) {
            for (let k = 0; k < 6; k++) {
                shot(a, { x: a.boss.x, y: a.boss.y, v: 7, dir: base + 30 + k * 60,
                          sp: SP, acc: -0.04, vto: 2.4, col: C.cyan, r: ORB });
            }
        }
      } },

    // Six short beams round him turn steadily, a degree a frame. Every 8
    // frames each tip sheds an orb leaning back against the turn, so the
    // orbs lay six spiral arms, cyan and pink by turns.
    { name: 'Pinwheel', loop: () => 120,
      init(a) {
        for (let k = 0; k < 6; k++) {
            a.laser({ x: a.boss.x, y: a.boss.y, len: 230, wid: 20, warn: 40,
                      hot: 1e9, col: k % 2 ? C.indigo : C.magenta,
                      step: (l) => { l.dir = a.t + k * 60; } });
        }
      },
      emit(a) {
        if (a.t % 8) return;
        for (let k = 0; k < 6; k++) {
            const d = a.t + k * 60;
            shot(a, { x: a.boss.x + a.dcos(d) * 230, y: a.boss.y - a.dsin(d) * 230,
                      v: 4.5, dir: d - 18, acc: -0.08, vto: 2.2, from: 30,
                      col: k % 2 ? C.rose : C.cyan, r: ORB });
        }
      } },

    // A plain two-way spiral: five cyan arms turning one way and five
    // magenta arms the other, fired fast and slowing to a drift. The magenta
    // arms are set half a firing step off the cyan, so the two never leave
    // along the same line.
    { name: 'Woven spiral', loop: () => 120,
      emit(a) {
        if (a.t % 6) return;
        for (let k = 0; k < 5; k++) {
            shot(a, { x: a.boss.x, y: a.boss.y, v: 6, dir: a.t * 1.8 + k * 72,
                      acc: -0.12, vto: 3, from: 20, col: C.cyan, r: ORB });
            shot(a, { x: a.boss.x, y: a.boss.y, v: 6, dir: -a.t * 1.8 + k * 72 + 41.4,
                      acc: -0.12, vto: 3, from: 20, col: C.magenta, r: ORB });
        }
      } },

    // Every 90 frames five pink seeds go out and stop, and each spins out a
    // small iris for 24 frames: four arms of orbs, cyan and magenta by
    // turns, so every bloom is a pinwheel. Alternate volleys turn 36 degrees
    // and spin the other way.
    { name: 'Iris blooms', loop: () => 180,
      emit(a) {
        if (a.t % 90 !== 1) return;
        const n = Math.floor(a.t / 90), way = n % 2 ? -1 : 1;
        for (let k = 0; k < 5; k++) {
            shot(a, { x: a.boss.x, y: a.boss.y, v: 10, dir: 90 + n * 36 + k * 72,
                      acc: -0.22, vto: 0, col: C.rose, r: BALL,
                      step: (b, api) => {
                          moveShot(b, api);
                          const u = b.age - 46;
                          if (u < 0 || u % 6) return;
                          for (let j = 0; j < 4; j++) {
                              shot(api, { x: b.x, y: b.y, v: 3.6, dir: way * u * 7 + j * 90,
                                          col: j % 2 ? C.magenta : C.cyan,
                                          r: ORB });
                          }
                          if (u >= 24) b.dead = true;
                      } });
        }
      } },

    // A slow four-arm spiral, cyan and pink, runs throughout. Every 270
    // frames two magenta curves draw an almond, the slit of his pupil, from
    // him down past the bottom of the field around the player, and it stands
    // for 140 frames. A game curve is lethal only while its head moves; this
    // needs a hold.
    { name: 'Pupil', loop: () => 270,
      emit(a) {
        if (a.t % 270 === 1) {
            const ax = Math.max(380, Math.min(980, a.player.x));
            almond(a, a.boss.x, a.boss.y, ax, 1060, 230, 60, 140, C.magenta);
        }
        if (a.t % 9) return;
        for (let k = 0; k < 4; k++) {
            shot(a, { x: a.boss.x, y: a.boss.y, v: 3.2, dir: a.t * 2 + k * 90,
                      col: k % 2 ? C.rose : C.cyan, r: ORB });
        }
      } },

    // Three curved lasers circle him at a fixed radius (magenta, indigo,
    // violet), the rim of the iris. Every 7 frames each head sheds a pair
    // splayed either side of straight out, cyan one way and pink the other,
    // so the pairs weave a lattice.
    { name: 'Iris rim', loop: () => 210,
      init(a) {
        a.store.rim = [C.magenta, C.indigo, C.violet].map((col, i) => {
            const phi = i * 120;
            return a.laser({ kind: 'curve', x: a.boss.x + a.dcos(phi) * RIM_R,
                             y: a.boss.y - a.dsin(phi) * RIM_R, dir: phi + 90,
                             spd: RIM_R * RIM_TURN * Math.PI / 180, turn: RIM_TURN,
                             hot: 1e9, wid: 22, col });
        });
      },
      emit(a) {
        if (a.t % 7) return;
        for (const h of a.store.rim) {
            const out = h.dir - 90;
            shot(a, { x: h.x, y: h.y, v: 5, dir: out + 35, acc: -0.1, vto: 2.8,
                      from: 24, col: C.cyan, r: ORB });
            shot(a, { x: h.x, y: h.y, v: 5, dir: out - 35, acc: -0.1, vto: 2.8,
                      from: 24, col: C.rose, r: ORB });
        }
      } },

    ],
});
})();
