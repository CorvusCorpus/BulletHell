// Candidates for Corvus's non-spells, from his design: scythes whose blades
// carry glowing cyan runes, black wings and feathers, a chain, the reaper's
// harvest, and the crypt's maze. Sketches only; none is in the game. All but
// the last leave out his gimmick (closing in to strike); "Lunge" uses it.
(function () {
'use strict';
// The game's bullet hues (`palette`).
const C = { cyan: '#38d6ff', azure: '#448cff', indigo: '#745cff',
            violet: '#b054fa', bone: '#e8eeff' };
const ORB = 7.0, BALL = 15.0;      // hit radii (`bullet_table`)
const KNIFE = 4.5, KLEN = 40;      // a blade or feather: hit radius and length
const PI = Math.PI;
const dcos = (d) => Math.cos(d * PI / 180), dsin = (d) => Math.sin(d * PI / 180);
const pdir = (dx, dy) => Math.atan2(-dy, dx) * 180 / PI;
const smooth = (f) => { f = Math.max(0, Math.min(1, f)); return f * f * (3 - 2 * f); };
const aim = (a, b) => pdir(a.player.x - b.x, a.player.y - b.y);

// The "small" toggle draws and hits each bullet a size down (a ball as an
// orb, an orb as a pellet, a blade shorter and thinner), which can read
// better in a sketch.
const size = (a, r) => (!a.opts.small ? r : r >= BALL ? ORB : r >= ORB ? 3.3 : r * 0.55);

// A shot: speed `v` heading `dir`, changing speed by `acc` a frame until it
// reaches `vto`, turning `turn` degrees a frame. `ev` is a list of
// [age, fn(b, a)] run in order as it reaches each age (the game's scheduled
// bullet events). `track` points it at the player each frame (while still).
// `len` draws it as a blade that long along its heading.
function shot(a, o) {
    const b = a.bullet(Object.assign({ v: 0, dir: 270, acc: 0, vto: 0, turn: 0,
                                       step: move }, o));
    b.r = size(a, b.r);
    if (b.len && a.opts.small) b.len *= 0.6;
    return b;
}

function move(b, a) {
    while (b.ev && b.ev.length && b.ev[0][0] <= b.age) b.ev.shift()[1](b, a);
    if (b.acc) b.v = b.acc > 0 ? Math.min(b.vto, b.v + b.acc) : Math.max(b.vto, b.v + b.acc);
    if (b.track) b.dir = aim(a, b);
    b.dir += b.turn;
    b.x += dcos(b.dir) * b.v;
    b.y -= dsin(b.dir) * b.v;
}

const blade = (a, o) => shot(a, Object.assign({ r: KNIFE, len: KLEN, col: C.bone }, o));

// ---- Feather dive ----------------------------------------------------------

// Every 60 frames he beats his wings: each throws a fan of nine feathers up
// and out (10 to 80 degrees off level), which brake to a stop in 26 frames
// and hang, turning to point at the player. From the outermost in, one every
// 3 frames, each dives at where the player is then, speeding up to 8.
function featherDive(a) {
    if (a.t % 60 !== 1) return;
    for (const m of [1, -1]) {
        for (let k = 0; k < 9; k++) {
            const d = 10 + k * 8.75;
            shot(a, { x: a.boss.x + m * 80, y: a.boss.y - 10, v: 10, acc: -0.38, vto: 0,
                      dir: m > 0 ? d : 180 - d, r: KNIFE, len: 34,
                      col: k % 2 ? C.indigo : C.azure,
                      ev: [[26, (b) => { b.track = true; }],
                           [34 + k * 3, (b, api) => { b.track = false; b.dir = aim(api, b);
                                                     b.acc = 0.3; b.vto = 8; }]] });
        }
    }
}

// ---- Reaping slash -----------------------------------------------------------

// Every 90 frames he swings his scythe, alternating right-to-left and back.
// In 14 frames the swing lays two arcs round a point just below him, 150
// degrees across the front: silver blades along the swing at radius 300 and
// cyan orbs at 240. They hang 18 frames; then, from where the swing began,
// one a frame, each sets off outward leaning 25 degrees the swing's way, fast
// (7) and braking to a crawl (1.2), and 70 frames later speeds up again to 5.
const SLASH = { every: 90, draw: 14, hold: 18, from: 195, span: 150, gap: 28 };
function reapingSlash(a) {
    const s = a.store;
    if (a.t % SLASH.every === 1) {
        s.sw = { t0: a.t, m: Math.floor(a.t / SLASH.every) % 2 ? -1 : 1,
                 cx: a.boss.x, cy: a.boss.y + 20, laid: [0, 0] };
    }
    const sw = s.sw, u = a.t - sw.t0;
    if (u > SLASH.draw) return;
    [[300, true], [240, false]].forEach(([R, isBlade], ring) => {
        const n = Math.round(R * SLASH.span * PI / 180 / SLASH.gap) + 1;
        while (sw.laid[ring] < n && sw.laid[ring] * SLASH.draw / (n - 1) <= u) {
            const k = sw.laid[ring]++;
            const th = (sw.m > 0 ? SLASH.from + SLASH.span : SLASH.from) - sw.m * SLASH.span * k / (n - 1);
            const go = SLASH.draw + SLASH.hold + k - u;
            const o = { x: sw.cx + R * dcos(th), y: sw.cy - R * dsin(th), dir: th - sw.m * 90,
                        ev: [[go, (b) => { b.dir = th - sw.m * 25; b.v = 7; b.acc = -0.2; b.vto = 1.2; }],
                             [go + 70, (b) => { b.acc = 0.08; b.vto = 5; }]] };
            if (isBlade) blade(a, o);
            else shot(a, Object.assign(o, { r: ORB, col: C.cyan }));
        }
    });
}

// ---- Boomerang sickles -------------------------------------------------------

// Every 180 frames two sickles (nine blades on an 80-degree arc of radius 80)
// appear at his sides and spin up over 30 frames, then are thrown: each flies
// a loop out to its side, across the bottom (passing the other) and back up
// the far side to his hand in 150 frames, fastest near him and slowest at the
// bottom, spinning 9 degrees a frame. Every 6 frames its leading tip sheds a
// cyan orb straight out from the sickle's middle, which drifts out, slowing,
// and 60 frames later speeds up to 3.
const SICKLE = { every: 180, wind: 30, fly: 150, side: 90, A: 330, B: 270,
                 rad: 80, arc: 80, n: 9, spin: 9, shed: 6 };

// Sickle `sk`'s middle and turn at frame `t` of its life.
function sickleAt(sk, t) {
    const sx = sk.bx + sk.m * SICKLE.side, sy = sk.by + 10, w = SICKLE.wind;
    if (t < w) return { x: sx, y: sy, rot: -sk.m * SICKLE.spin * t * t / (2 * w) };
    const u = (t - w) / SICKLE.fly, th = 2 * PI * (u + 0.12 * Math.sin(2 * PI * u));
    return { x: sx + sk.m * SICKLE.A * Math.sin(th), y: sy + SICKLE.B * (1 - Math.cos(th)),
             rot: -sk.m * SICKLE.spin * (w / 2 + t - w) };
}

const sickleAngle = (c, j) => c.rot + (j - (SICKLE.n - 1) / 2) * SICKLE.arc / (SICKLE.n - 1);

function sickleBlade(b, a) {
    const t = a.t - b.sk.t0;
    if (t > SICKLE.wind + SICKLE.fly) { b.dead = true; return; }
    const c = sickleAt(b.sk, t), al = sickleAngle(c, b.j);
    b.x = c.x + dcos(al) * SICKLE.rad;
    b.y = c.y - dsin(al) * SICKLE.rad;
    b.dir = al + 90;
}

function boomerangSickles(a) {
    const s = a.store;
    s.sk = (s.sk || []).filter((sk) => a.t - sk.t0 <= SICKLE.wind + SICKLE.fly);
    if (a.t % SICKLE.every === 1) {
        for (const m of [1, -1]) {
            const sk = { t0: a.t, m, bx: a.boss.x, by: a.boss.y };
            s.sk.push(sk);
            for (let j = 0; j < SICKLE.n; j++) {
                a.bullet({ x: a.boss.x, y: a.boss.y, sk, j, r: size(a, KNIFE),
                           len: a.opts.small ? KLEN * 0.6 : KLEN, col: C.bone,
                           step: sickleBlade });
            }
        }
    }
    for (const sk of s.sk) {
        const t = a.t - sk.t0;
        if (t < SICKLE.wind || t % SICKLE.shed) continue;
        const c = sickleAt(sk, t);
        const al = sickleAngle(c, sk.m > 0 ? 0 : SICKLE.n - 1);
        shot(a, { x: c.x + dcos(al) * SICKLE.rad, y: c.y - dsin(al) * SICKLE.rad,
                  dir: al, v: 1.6, acc: -0.02, vto: 0.8, r: ORB, col: C.cyan,
                  ev: [[60, (b) => { b.acc = 0.05; b.vto = 3; }]] });
    }
}

// ---- Crypt gates -------------------------------------------------------------

// Every 110 frames a wall rises below him, laid from the middle outward in 12
// frames: a row of stones across the field, 20 px apart, with two gaps 150 px
// wide, sinking at 1.6 a frame. 70 frames in, its stretches slide over 24
// frames so each gap moves 200 px (inward on one wall, outward on the next);
// 120 frames in it speeds up to 3.5. Each wall puts its gaps somewhere new, so
// the way through winds. Every 40 frames he throws three blades at the player.
const GATE = { every: 110, gap: 150, step: 20, sink: 1.6, shiftAt: 70, shiftFor: 24,
               move: 200, fastAt: 120, fast: 3.5, lay: 12, edge: 10 };

// The x of stone `i` of a wall whose gaps' left edges are e1 < e2.
function gateX(i, e1, e2) {
    let x = GATE.edge + i * GATE.step;
    if (x >= e1) x += GATE.gap;
    if (x >= e2) x += GATE.gap;
    return x;
}

function gateStone(b, a) {
    const w = b.w, t = a.t - w.t0;
    b.vy = t < GATE.fastAt ? GATE.sink : Math.min(GATE.fast, (b.vy || GATE.sink) + 0.05);
    b.y += b.vy;
    const f = smooth((t - GATE.shiftAt) / GATE.shiftFor);
    b.x = gateX(b.i, w.a1, w.a2) * (1 - f) + gateX(b.i, w.b1, w.b2) * f;
}

function cryptGates(a) {
    const s = a.store, W = a.GAME.fieldW;
    if (a.t % GATE.every === 1) {
        const k = Math.floor(a.t / GATE.every), into = k % 2 ? -1 : 1;
        const c1 = [300, 360, 330, 390][k % 4], c2 = [1060, 1000, 1030, 970][k % 4];
        const n = Math.floor((W - 2 * GATE.edge - 2 * GATE.gap) / GATE.step) + 1;
        const w = { t0: a.t, y: a.boss.y + 60, n, made: 0,
                    a1: c1 - GATE.gap / 2, a2: c2 - GATE.gap / 2,
                    b1: c1 + into * GATE.move - GATE.gap / 2,
                    b2: c2 - into * GATE.move - GATE.gap / 2 };
        w.order = [...Array(n).keys()].sort((i, j) =>
            Math.abs(gateX(i, w.a1, w.a2) - W / 2) - Math.abs(gateX(j, w.a1, w.a2) - W / 2));
        s.wall = w;
    }
    const w = s.wall, u = a.t - w.t0;
    while (w.made < w.n) {
        const i = w.order[w.made], x = gateX(i, w.a1, w.a2);
        if (Math.abs(x - W / 2) > (W / 2) * (u + 1) / GATE.lay) break;
        a.bullet({ x, y: w.y + GATE.sink * u, w, i, r: size(a, ORB),
                   col: i % 4 ? C.bone : C.cyan, step: gateStone });
        w.made++;
    }
    if (a.t % 40 === 21) {
        for (const off of [-12, 0, 12]) {
            const b = blade(a, { x: a.boss.x, y: a.boss.y, v: 5.5, col: C.cyan });
            b.dir = aim(a, b) + off;
        }
    }
}

// ---- Pendulum chain ------------------------------------------------------------

// He swings a chain below him from one hand like a pendulum: twelve silver
// links and a cyan head, 50 to 358 px out, 80 frames a swing, its swing
// widening from 20 to 65 degrees over two and a half swings. Its head sheds a
// cyan orb every 4 frames straight out from his hand, which drifts out and 80
// frames later speeds up to 3.2. At the bottom of the last swing he lets go:
// each link flies on along its swing at 0.22 of its speed there (the head
// fastest), brakes to a stop in 40 frames, hangs 30, then drops, speeding up
// to 5.5. Then the other hand, swinging the other way.
const CHAIN = { links: 12, r0: 50, gap: 28, P: 80, swings: 2.5, amp0: 20, amp1: 65,
                keep: 0.22, brake: 40, hang: 30, every: 240 };
const CHAIN_T = CHAIN.P * CHAIN.swings;

function chainAt(ch, k, t) {
    const amp = CHAIN.amp0 + (CHAIN.amp1 - CHAIN.amp0) * Math.min(1, t / CHAIN_T);
    const ang = 270 + ch.m * amp * Math.sin(2 * PI * t / CHAIN.P);
    const r = CHAIN.r0 + k * CHAIN.gap;
    return { x: ch.hx + dcos(ang) * r, y: ch.hy - dsin(ang) * r, ang };
}

function chainLink(b, a) {
    const t = a.t - b.ch.t0;
    if (t < CHAIN_T) {
        const q = chainAt(b.ch, b.k, t);
        b.x = q.x; b.y = q.y; b.dir = q.ang;
        return;
    }
    if (t === CHAIN_T) {
        const p0 = chainAt(b.ch, b.k, t - 1), p1 = chainAt(b.ch, b.k, t);
        const vx = p1.x - p0.x, vy = p1.y - p0.y, v = Math.hypot(vx, vy) * CHAIN.keep;
        Object.assign(b, { step: move, x: p1.x, y: p1.y, dir: pdir(vx, vy), v, turn: 0,
                           acc: -v / CHAIN.brake, vto: 0,
                           ev: [[b.age + CHAIN.brake + CHAIN.hang,
                                 (bb) => { bb.dir = 270; bb.acc = 0.12; bb.vto = 5.5; }]] });
    }
}

function pendulumChain(a) {
    const s = a.store;
    if (a.t % CHAIN.every === 1) {
        const m = Math.floor(a.t / CHAIN.every) % 2 ? -1 : 1;
        s.ch = { t0: a.t, m, hx: a.boss.x + m * 60, hy: a.boss.y + 20 };
        for (let k = 0; k < CHAIN.links; k++) {
            const head = k === CHAIN.links - 1;
            a.bullet({ x: s.ch.hx, y: s.ch.hy, ch: s.ch, k,
                       r: size(a, head ? BALL : ORB), col: head ? C.cyan : C.bone,
                       step: chainLink });
        }
    }
    const ch = s.ch, t = a.t - ch.t0;
    if (t < CHAIN_T && t % 4 === 0) {
        const q = chainAt(ch, CHAIN.links - 1, t);
        shot(a, { x: q.x, y: q.y, dir: q.ang, v: 1.8, r: ORB, col: C.cyan,
                  ev: [[80, (b) => { b.acc = 0.04; b.vto = 3.2; }]] });
    }
}

// ---- Lunge (his gimmick) -------------------------------------------------------

// Every 160 frames: he rises 30 px over 10 frames, then dashes in 18 frames
// (speeding up) to 220 px above where the player was as the dash began,
// dropping a feather every 2 frames on the way. There he cuts a ring: twenty
// silver blades and ten cyan orbs burst outward, speeding up. He holds 22
// frames and glides home over 60. Each feather hangs 40 frames, then falls,
// leaning alternately left and right, speeding up to 3.5.
const LUNGE = { every: 160, home: { x: 680, y: 250 } };

function lungeAt(a) {
    const u = a.t % LUNGE.every, h = LUNGE.home, s = a.store;
    if (u === 30 || !s.to) {
        s.to = { x: Math.max(200, Math.min(1160, a.player.x)),
                 y: Math.max(h.y, a.player.y - 220) };
    }
    if (u < 20) return h;
    if (u < 30) return { x: h.x, y: h.y - 30 * smooth((u - 20) / 10) };
    if (u < 48) {
        const f = Math.pow((u - 30) / 18, 2);
        return { x: h.x + (s.to.x - h.x) * f, y: h.y - 30 + (s.to.y - h.y + 30) * f };
    }
    if (u < 70) return s.to;
    if (u < 130) {
        const f = smooth((u - 70) / 60);
        return { x: s.to.x + (h.x - s.to.x) * f, y: s.to.y + (h.y - s.to.y) * f };
    }
    return h;
}

function lunge(a) {
    const u = a.t % LUNGE.every;
    if (u >= 30 && u < 48 && u % 2 === 0) {
        const lean = u % 4 ? 15 : -15;
        shot(a, { x: a.boss.x, y: a.boss.y, r: KNIFE, len: 34, col: C.indigo, dir: 270 + lean,
                  ev: [[40, (b) => { b.acc = 0.06; b.vto = 3.5; }]] });
    }
    if (u === 48) {
        for (let k = 0; k < 20; k++) {
            blade(a, { x: a.boss.x, y: a.boss.y, dir: k * 18, v: 1, acc: 0.3, vto: 7.5 });
        }
        for (let k = 0; k < 10; k++) {
            shot(a, { x: a.boss.x, y: a.boss.y, dir: 9 + k * 36, v: 0.5, acc: 0.12, vto: 3.5,
                      r: ORB, col: C.cyan });
        }
    }
}

Sketch.set({
    id: 'corvus',
    name: "Corvus's non-spells: blades, feathers and the crypt",
    toggles: [{ id: 'small', label: 'Small bullets' }],
    patterns: [
        { name: 'Feather dive', loop: () => 120, emit: featherDive },
        { name: 'Reaping slash', loop: () => 180, emit: reapingSlash },
        { name: 'Boomerang sickles', loop: () => 180, emit: boomerangSickles },
        { name: 'Crypt gates', loop: () => 440, emit: cryptGates },
        { name: 'Pendulum chain', loop: () => 480, emit: pendulumChain },
        { name: 'Lunge (his gimmick)', loop: () => 320, bossAt: lungeAt, emit: lunge },
    ],
});
})();
