// Candidates for Sylvia's non-spells: spirals and lasers in the colours of his
// eye (a cyan iris, its blades magenta and indigo). Sketches only; none is in
// the game. Lasers here are the engine's model of `laser_functions`.
(function () {
'use strict';
// The game's bullet hues (`palette`).
const C = { cyan: '#38d6ff', magenta: '#f848e0', rose: '#ff80b2',
            indigo: '#745cff', violet: '#b054fa', bone: '#e8eeff' };
const PELLET = 3.3, MOTE = 4.3, ORB = 7.0;

// A plain shot: `v` heading `dir`, turning `turn` degrees a frame. From age
// `from` it changes speed by `acc` a frame until it reaches `vto`. `ease`
// scales the turn each frame. `sp` ([t0, c]) bends it along the Iris's spiral
// instead: at its first speed it turns t0 * c / (age + c), and it turns by the
// distance it has come, so slowing down doesn't tighten the curl. `then(b, a)`
// runs once at age `at`.
function shot(a, o) {
    const b = a.bullet(Object.assign({ v: 4, dir: 270, turn: 0, ease: 1, acc: 0,
                                       vto: 0, from: 0, step: moveShot }, o));
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

// The Iris Rim's three arcs: radius round him, and degrees a frame (a third of
// a turn in 70 frames).
const RIM_R = 200, RIM_TURN = 120 / 70;

Sketch.set({
    id: 'sylvia',
    name: "Sylvia's non-spells: spirals and lasers",
    patterns: [

    // Every 100 frames six blades (curved lasers, magenta and indigo by
    // turns) unfurl from him along a spiral. Two strands of cyan pellets
    // stream out along the same spiral between each pair of blades, slowing
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
                for (const off of [20, 40]) {
                    shot(a, { x: a.boss.x, y: a.boss.y, v: 7, dir: base + off + k * 60,
                              sp: SP, acc: -0.04, vto: 2.4,
                              col: C.cyan, r: PELLET });
                }
            }
        }
      } },

    // Six short beams round him turn steadily, a degree a frame. Every 6
    // frames each tip sheds a pellet leaning back against the turn, so the
    // pellets lay six spiral arms, cyan and pink by turns.
    { name: 'Pinwheel', loop: () => 120,
      init(a) {
        for (let k = 0; k < 6; k++) {
            a.laser({ x: a.boss.x, y: a.boss.y, len: 230, wid: 20, warn: 40,
                      hot: 1e9, col: k % 2 ? C.indigo : C.magenta,
                      step: (l) => { l.dir = a.t + k * 60; } });
        }
      },
      emit(a) {
        if (a.t % 6) return;
        for (let k = 0; k < 6; k++) {
            const d = a.t + k * 60;
            shot(a, { x: a.boss.x + a.dcos(d) * 230, y: a.boss.y - a.dsin(d) * 230,
                      v: 4.5, dir: d - 18, acc: -0.08, vto: 2.2, from: 30,
                      col: k % 2 ? C.rose : C.cyan, r: k % 2 ? MOTE : PELLET });
        }
      } },

    // A plain two-way spiral: five cyan arms turning one way and five
    // magenta arms the other, fired fast and slowing to a drift. The magenta
    // arms are set half a firing step off the cyan, so the two never leave
    // along the same line.
    { name: 'Woven spiral', loop: () => 40,
      emit(a) {
        if (a.t % 4) return;
        for (let k = 0; k < 5; k++) {
            shot(a, { x: a.boss.x, y: a.boss.y, v: 6, dir: a.t * 1.8 + k * 72,
                      acc: -0.12, vto: 2.4, from: 20, col: C.cyan, r: PELLET });
            shot(a, { x: a.boss.x, y: a.boss.y, v: 6, dir: -a.t * 1.8 + k * 72 + 39.6,
                      acc: -0.12, vto: 2.4, from: 20, col: C.magenta, r: MOTE });
        }
      } },

    // Every 90 frames five pink seeds go out and stop, and each spins out a
    // small iris for 24 frames: four arms of pellets, cyan and magenta by
    // turns, so every bloom is a pinwheel. Alternate volleys turn 36 degrees
    // and spin the other way.
    { name: 'Iris blooms', loop: () => 180,
      emit(a) {
        if (a.t % 90 !== 1) return;
        const n = Math.floor(a.t / 90), way = n % 2 ? -1 : 1;
        for (let k = 0; k < 5; k++) {
            shot(a, { x: a.boss.x, y: a.boss.y, v: 10, dir: 90 + n * 36 + k * 72,
                      acc: -0.22, vto: 0, col: C.rose, r: ORB,
                      step: (b, api) => {
                          moveShot(b, api);
                          const u = b.age - 46;
                          if (u < 0 || u % 4) return;
                          for (let j = 0; j < 4; j++) {
                              shot(api, { x: b.x, y: b.y, v: 2.6, dir: way * u * 7 + j * 90,
                                          col: j % 2 ? C.magenta : C.cyan,
                                          r: j % 2 ? MOTE : PELLET });
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
        if (a.t % 6) return;
        for (let k = 0; k < 4; k++) {
            shot(a, { x: a.boss.x, y: a.boss.y, v: 2.8, dir: a.t * 2 + k * 90,
                      col: k % 2 ? C.rose : C.cyan, r: k % 2 ? MOTE : PELLET });
        }
      } },

    // Three curved lasers circle him at a fixed radius (magenta, indigo,
    // violet), the rim of the iris. Every 5 frames each head sheds a pair
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
        if (a.t % 5) return;
        for (const h of a.store.rim) {
            const out = h.dir - 90;
            shot(a, { x: h.x, y: h.y, v: 5, dir: out + 35, acc: -0.1, vto: 2.3,
                      from: 24, col: C.cyan, r: PELLET });
            shot(a, { x: h.x, y: h.y, v: 5, dir: out - 35, acc: -0.1, vto: 2.3,
                      from: 24, col: C.rose, r: MOTE });
        }
      } },

    ],
});
})();
