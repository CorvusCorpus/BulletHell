/* Pattern sketches: a quick browser model of a danmaku pattern, for trying an
 * idea before building it in GML. `sketch.html` runs it; `tools/sketch.py`
 * opens it, and renders GIFs and preview sheets headlessly.
 *
 * This is not the game. The numbers in GAME and RADIUS are copied from the
 * project by hand and won't follow it if it changes. Bullets are drawn as dots
 * about their in-game size, not with the game's sprites, and the boss is a
 * placeholder oval, either still or hopping between stations as the game's
 * `BossMove.Step` does (`boss: 'step'`).
 *
 * Conventions follow GameMaker so a sketch ports almost line for line:
 * field pixels with y down, angles in degrees, 0 to the right and 90 up
 * (`lengthdir_x/_y`), time in frames at 60 a second.
 *
 * A set file (`sets/<id>.js`) calls `Sketch.set({...})`:
 *   id, name          the set's file name and title
 *   orbit             rings orbiting the boss in 2.5D (optional): rings,
 *                     radius, tilt, depth, dim, period (frames a turn), way
 *                     (+1 counterclockwise on screen, -1 clockwise)
 *   boss              'still' (default) or 'step'
 *   toggles           [{id, label}] checkboxes, read as `api.opts[id]`
 *   orbits            several orbits instead (each with the same fields, plus
 *                     `phase0`, the degrees its first ring starts round)
 *                     An orbit may also give `radiusAt(t)` (a radius that
 *                     changes) and `turnAt(t)` (degrees turned by frame `t`,
 *                     for a turn that isn't steady); see `orbitRadius`.
 *   patterns          [{name, emit(api), step?(api), orbit?, orbits?, boss?,
 *                     hold?, bossAt?(api), loop?}]
 * A pattern's `orbit` overrides fields of the set's, its `orbits` replaces
 * them (each over the set's `orbit`), and its `boss` the set's. `hold` is the
 * frames a stepping boss holds between hops (a phase's `hold`; default
 * BOSS_STEP_HOLD). `bossAt` returns where the boss is each frame ({x, y}), for a
 * pattern that moves him itself. `loop` is the frames
 * after which it repeats exactly (default one orbit), used for GIFs.
 *
 * A pattern fires through `api.grain`, `api.bullet` and `api.laser` (see each).
 */
(function () {
'use strict';

const GAME = {
    fieldW: 1360, fieldH: 992,         // FIELD_W, FIELD_H
    bossX: 680, bossY: 250,            // the field's middle, BOSS_HOME_Y
    playerX: 680, playerY: 860,
    playerR: 4.0,                      // PLAYER_R
    playerSpd: 11.0,                   // PLAYER_SPD
    playerFocus: 4.6,                  // PLAYER_SPD_FOCUS
    ringR: 72,                         // RING_R
    stepHold: 195, stepMove: 45,       // BOSS_STEP_HOLD, BOSS_STEP_MOVE
    stepX: 140, stepY: 24,             // BOSS_STEP_X, BOSS_STEP_Y
    stepRate: 0.10,                    // BOSS_STEP_RATE
};

// Hit radii of a few shapes at scale 1 (`bullet_table`).
const RADIUS = { pellet: 3.3, orb: 7.0, mote: 4.3 };

const COL = {
    ember: '#ff6a2a', amber: '#ffb627', bone: '#f6e6bd', gold: '#c9a24a',
    cyan: '#5ad1e6', red: '#ff4058', violet: '#b07cff', white: '#ffffff',
};

const VIEW = 0.5;          // canvas pixels per field pixel at scale 1
const CULL = 30;           // how far past the field a bullet lives
const BG = '#120c24';

const dsin = (a) => Math.sin(a * Math.PI / 180);
const dcos = (a) => Math.cos(a * Math.PI / 180);
// GameMaker's `point_direction` from the origin to (dx, dy).
const pdir = (dx, dy) => Math.atan2(-dy, dx) * 180 / Math.PI;
const wrap = (a) => ((a % 360) + 360) % 360;

const sets = {};
let set = null, pat = null, orbit = null, orbits = [], moves = 'still';
const boss = { x: GAME.bossX, y: GAME.bossY };
let t = 0, B = [], L = [], hits = 0, inv = 0, store = {};
const opts = {};
const pl = { x: GAME.playerX, y: GAME.playerY, tx: GAME.playerX,
             ty: GAME.playerY, focus: false, show: true };
let cv = null, g = null, scale = 1, label = '', listeners = [];

// ---- rings -----------------------------------------------------------------

/* Ring `i` at frame `tt`. `p` is its phase: 0 as it comes round to the front
 * half, 90 straight in front of the boss, 180 as it leaves the front, 270
 * straight behind; it counts up without wrapping. `orb` is the GameMaker
 * angle round the boss, `far` is dsin(orb) (1 at the back, -1 in front), and
 * `size` is how much larger or smaller depth makes it. */
function ringAt(i, tt, o = orbit) {
    const turned = o.turnAt ? o.turnAt(tt) : 360 * tt / o.period;
    const r = onOrbit((o.phase0 || 0) + i * 360 / o.rings + turned,
                      orbitRadius(o, tt), boss, o);
    r.i = i;
    r.o = o;
    r.size = 1 - o.depth * r.far;
    return r;
}

// Orbit `o`'s radius at frame `tt`: its `radiusAt`, or its steady `radius`.
function orbitRadius(o, tt) {
    return o.radiusAt ? o.radiusAt(tt) : o.radius;
}

// The GameMaker angle round the boss at phase `p` on orbit `o` (see `ringAt`).
function orbOf(p, o = orbit) {
    return (o.way > 0) ? p + 180 : -p;
}

// The point at phase `p` on a level circle of radius `rad` round `c` (the
// boss, by default), seen at orbit `o`'s tilt and turning its way.
function onOrbit(p, rad, c = boss, o = orbit) {
    const orb = orbOf(p, o), far = dsin(orb);
    return {
        p, orb, far,
        x: c.x + dcos(orb) * rad,
        y: c.y - dsin(orb) * rad * o.tilt,
        behind: far > 0,
    };
}

// ---- the boss --------------------------------------------------------------

// `BossMove.Step` (`boss_move_step`): hold, hop to the next station, hold.
function stepBoss() {
    if (pat.bossAt) {
        const q = pat.bossAt(api);
        boss.x = q.x;
        boss.y = q.y;
        return;
    }
    if (moves !== 'step') return;
    const hold = pat.hold || GAME.stepHold, cyc = hold + GAME.stepMove;
    const n = Math.floor(t / cyc);
    const to = (t % cyc < hold) ? n : n + 1;
    const tx = GAME.bossX + dsin(to * 137) * GAME.stepX;
    const ty = GAME.bossY + dsin(to * 71) * GAME.stepY;
    boss.x += (tx - boss.x) * GAME.stepRate;
    boss.y += (ty - boss.y) * GAME.stepRate;
}

// Is the boss holding still (`boss_holding`)? Always, unless it steps.
function holding() {
    if (moves !== 'step') return true;
    const hold = pat.hold || GAME.stepHold;
    return t % (hold + GAME.stepMove) < hold;
}

// Did ring `i`'s phase pass `deg` (mod 360) on this frame?
function passed(i, deg, o = orbit) {
    const a = ringAt(i, t - 1, o).p - deg, b = ringAt(i, t, o).p - deg;
    return Math.floor(a / 360) !== Math.floor(b / 360);
}

// A point on ring `r`'s metal in direction `dir`.
function rim(r, dir) {
    const s = GAME.ringR * r.size * 0.85;
    return { x: r.x + dcos(dir) * s, y: r.y - dsin(dir) * s };
}

// ---- bullets ---------------------------------------------------------------

/* A sand grain after `mika_sand_dress`: it leaves at `v` heading `dir`, holds
 * that for `hold` frames, brakes by `brake` a frame to `flr`, then turns `curl`
 * degrees a frame until it has bent `bend` degrees. Extras, all off by
 * default: `fall` (a downward drift it eases into once settled), `down` (turns
 * it toward straight down at that many degrees a frame once settled) with
 * `sway` (degrees it swings either side of down while falling). `len` draws
 * it as a pointed shard that long along its heading, `hollow` as a ring. Any bullet
 * is removed at `life` frames, the backstop the game's sand has
 * (`MIKA_SAND_LIFE`). */
function grain(o) {
    const b = Object.assign({
        x: 0, y: 0, v: 8, dir: 0, hold: 8, brake: 0.4, flr: 1.8, curl: 0,
        bend: 0, fall: 0, down: 0, sway: 0, col: COL.amber, r: RADIUS.pellet,
        age: 0, dy: 0, cull: true, life: 1500,
    }, o);
    B.push(b);
    return b;
}

/* A bullet with its own behaviour: `step(b, api)` moves it each frame and sets
 * `b.dead` to remove it. Set `cull: false` for one that may leave the field and
 * come back. A bullet on the far side of an orbit is drawn and hits like any
 * other, as in the game (the owner's rule: a dimmed or harmless far side is a
 * blind spot). */
function bullet(o) {
    const b = Object.assign({ x: 0, y: 0, col: COL.amber, r: RADIUS.pellet,
                              age: 0, cull: true, life: 1500 }, o);
    B.push(b);
    return b;
}

function stepGrain(b) {
    if (b.age >= b.hold && b.v > b.flr) {
        b.v = Math.max(b.flr, b.v - b.brake);
    } else if (b.v <= b.flr) {
        if (b.bend > 0) { b.dir += b.curl; b.bend -= Math.abs(b.curl); }
        if (b.fall) b.dy = Math.min(b.fall, b.dy + 0.02);
        if (b.down) {
            const want = 270 + (b.sway ? b.sway * Math.sin((b.age - b.hold) * 0.05) : 0);
            let e = wrap(want - b.dir + 180) - 180;
            b.dir += Math.max(-b.down, Math.min(b.down, e));
        }
    }
    b.x += dcos(b.dir) * b.v;
    b.y += -dsin(b.dir) * b.v + b.dy;
}

// ---- lasers --------------------------------------------------------------------

/* A laser, after `laser_functions`. `kind` 'beam' (the default) is anchored at
 * (x, y) and runs `len` toward `dir`: a thin harmless line for `warn` frames,
 * lethal for `hot`, then narrowing away over `fade`. 'curve' is the trail of a
 * head moving at `spd` and turning `turn` degrees a frame for `hot` frames, at
 * most CURVE_NODES nodes long (`laser_curve`); then it drains a node a frame,
 * harmless. Either may take `step(l, api)`, run first each frame, to move,
 * re-aim or re-turn it. `hold` is sketch only (the game's curves don't have
 * it): frames a curve's whole trail stays lethal after its head stops, before
 * it drains. A laser kills at about a third of its drawn width
 * (`laser_hit_half`). */
const CURVE_NODES = 64;

function laser(o) {
    const l = Object.assign({
        kind: 'beam', x: 0, y: 0, dir: 270, len: 1400, wid: 30, col: COL.cyan,
        warn: 30, hot: 60, fade: 12, spd: 8, turn: 0, hold: 0, age: 0,
    }, o);
    if (l.kind === 'curve') { l.warn = 0; l.nx = [l.x]; l.ny = [l.y]; }
    L.push(l);
    return l;
}

// Advance laser `l` a frame; true once it is spent.
function stepLaser(l) {
    l.age++;
    if (l.step) l.step(l, api);
    if (l.kind !== 'curve') return l.age >= l.warn + l.hot + l.fade;
    if (l.age <= l.hot) {
        l.dir += l.turn;
        l.x += dcos(l.dir) * l.spd;
        l.y -= dsin(l.dir) * l.spd;
        l.nx.push(l.x); l.ny.push(l.y);
        if (l.nx.length > CURVE_NODES) { l.nx.shift(); l.ny.shift(); }
        return false;
    }
    if (l.age <= l.hot + l.hold) return false;
    l.nx.shift(); l.ny.shift();
    return l.nx.length <= 1;
}

function laserLethal(l) {
    if (l.kind === 'curve') return l.age <= l.hot + l.hold;
    return l.age >= l.warn && l.age < l.warn + l.hot;
}

function segDist(px, py, x0, y0, x1, y1) {
    const dx = x1 - x0, dy = y1 - y0, dd = dx * dx + dy * dy;
    const u = dd ? Math.max(0, Math.min(1, ((px - x0) * dx + (py - y0) * dy) / dd)) : 0;
    return Math.hypot(px - x0 - u * dx, py - y0 - u * dy);
}

// How far (x, y) is from laser `l`'s spine.
function laserDist(l, x, y) {
    if (l.kind !== 'curve') {
        return segDist(x, y, l.x, l.y, l.x + dcos(l.dir) * l.len,
                       l.y - dsin(l.dir) * l.len);
    }
    let best = Infinity;
    for (let k = 0; k + 1 < l.nx.length; k++) {
        best = Math.min(best, segDist(x, y, l.nx[k], l.ny[k], l.nx[k + 1], l.ny[k + 1]));
    }
    return best;
}

// ---- the frame ---------------------------------------------------------------

const api = {
    GAME, RADIUS, COL, dsin, dcos, pdir, wrap,
    get t() { return t; },
    get orbit() { return orbit; },
    get orbits() { return orbits; },
    // Ring `i` of orbit `k`.
    ringOf: (k, i) => ringAt(i, t, orbits[k]),
    get boss() { return { x: boss.x, y: boss.y }; },
    get holding() { return holding(); },
    get player() { return pl; },
    opts, get store() { return store; },
    ring: (i) => ringAt(i, t), ringAt, passed, rim, orbOf, onOrbit,
    grain, bullet, laser,
};

function step() {
    t++;
    stepBoss();
    if (pat.step) pat.step(api);
    pat.emit(api);
    for (let k = L.length - 1; k >= 0; k--) {
        if (stepLaser(L[k])) {
            L[k] = L[L.length - 1];
            L.pop();
        }
    }
    for (let k = B.length - 1; k >= 0; k--) {
        const b = B[k];
        b.age++;
        if (b.step) b.step(b, api); else stepGrain(b);
        const out = b.x < -CULL || b.x > GAME.fieldW + CULL
                    || b.y < -CULL || b.y > GAME.fieldH + CULL;
        if (b.dead || (b.cull && out) || b.age > b.life) {
            B[k] = B[B.length - 1];
            B.pop();
        }
    }

    const sp = pl.focus ? GAME.playerFocus : GAME.playerSpd;
    const dx = pl.tx - pl.x, dy = pl.ty - pl.y, dl = Math.hypot(dx, dy);
    if (dl > sp) { pl.x += dx / dl * sp; pl.y += dy / dl * sp; }
    else { pl.x = pl.tx; pl.y = pl.ty; }
    pl.x = Math.max(20, Math.min(GAME.fieldW - 20, pl.x));
    pl.y = Math.max(20, Math.min(GAME.fieldH - 20, pl.y));

    if (inv > 0) { inv--; return; }
    if (!pl.show) return;
    const hit = B.some((b) => Math.hypot(b.x - pl.x, b.y - pl.y) < b.r + GAME.playerR)
             || L.some((l) => laserLethal(l)
                              && laserDist(l, pl.x, pl.y) < l.wid * 0.34 + GAME.playerR);
    if (hit) {
        hits++;
        inv = 90;
    }
}

function dot(b, alpha) {
    const s = VIEW;
    g.globalAlpha = alpha;
    if (b.len) { shard(b); g.globalAlpha = 1; return; }
    if (b.hollow) {
        // A hollow ring shot: its hit radius is about the ring's middle.
        g.strokeStyle = b.col;
        g.lineWidth = Math.max(1.5, b.r * s * 0.35);
        g.beginPath();
        g.arc(b.x * s, b.y * s, b.r * s * 1.6, 0, 7);
        g.stroke();
        g.globalAlpha = 1;
        return;
    }
    g.fillStyle = b.col;
    g.beginPath();
    g.arc(b.x * s, b.y * s, Math.max(2, b.r * s * 1.7), 0, 7);
    g.fill();
    g.fillStyle = '#fff8e8';
    g.beginPath();
    g.arc(b.x * s, b.y * s, Math.max(0.8, b.r * s * 0.5), 0, 7);
    g.fill();
    g.globalAlpha = 1;
}

// A long bullet (`len` set: a crystal or shard), drawn as a pointed diamond
// `len` long along its heading (or along `face`, if set), with a pale core.
function shard(b) {
    const s = VIEW, L = b.len * s * 0.5, W = Math.max(2, b.r * s * 1.4);
    const d = b.face !== undefined ? b.face : b.dir;
    const ux = dcos(d), uy = -dsin(d), vx = -uy, vy = ux;
    const x = b.x * s, y = b.y * s;
    for (const [k, col] of [[1, b.col], [0.45, '#ffffff']]) {
        g.fillStyle = col;
        g.beginPath();
        g.moveTo(x + ux * L * k, y + uy * L * k);
        g.lineTo(x + vx * W * k, y + vy * W * k);
        g.lineTo(x - ux * L * k, y - uy * L * k);
        g.lineTo(x - vx * W * k, y - vy * W * k);
        g.closePath();
        g.fill();
    }
}

// A laser drawn as light: a body in its colour round a white-hot core. A
// beam's warning is a thin line and a fading beam narrows; a draining curve is
// drawn faint, as it is harmless.
function drawLaser(l) {
    const s = VIEW;
    g.beginPath();
    if (l.kind === 'curve') {
        if (l.nx.length < 2) return;
        g.moveTo(l.nx[0] * s, l.ny[0] * s);
        for (let k = 1; k < l.nx.length; k++) g.lineTo(l.nx[k] * s, l.ny[k] * s);
    } else {
        g.moveTo(l.x * s, l.y * s);
        g.lineTo((l.x + dcos(l.dir) * l.len) * s, (l.y - dsin(l.dir) * l.len) * s);
    }
    g.lineCap = 'round';
    g.lineJoin = 'round';
    g.strokeStyle = l.col;
    if (l.kind !== 'curve' && l.age < l.warn) {
        g.globalAlpha = 0.5;
        g.lineWidth = 1.5;
        g.stroke();
        g.globalAlpha = 1;
        return;
    }
    let w = l.wid * s;
    if (l.kind !== 'curve' && l.age >= l.warn + l.hot) {
        w *= Math.max(0, 1 - (l.age - l.warn - l.hot) / l.fade);
    }
    const on = laserLethal(l) ? 1 : 0.4;
    g.globalAlpha = 0.3 * on; g.lineWidth = w; g.stroke();
    g.globalAlpha = 0.85 * on; g.lineWidth = w * 0.55; g.stroke();
    g.strokeStyle = '#ffffff';
    g.globalAlpha = 0.95 * on; g.lineWidth = Math.max(1, w * 0.2); g.stroke();
    g.globalAlpha = 1;
}

function drawRing(r) {
    const s = VIEW, rad = GAME.ringR * r.size * s;
    g.globalAlpha = r.behind ? 1 - r.o.dim * r.far : 1;
    g.strokeStyle = COL.gold;
    g.lineWidth = 5 * s * r.size;
    g.beginPath(); g.arc(r.x * s, r.y * s, rad, 0, 7); g.stroke();
    g.strokeStyle = COL.cyan;
    g.lineWidth = 1;
    g.beginPath(); g.arc(r.x * s, r.y * s, rad - 3, 0, 7); g.stroke();
    g.globalAlpha = 1;
}

function draw() {
    const s = VIEW;
    g.setTransform(scale, 0, 0, scale, 0, 0);
    g.fillStyle = BG;
    g.fillRect(0, 0, GAME.fieldW * s, GAME.fieldH * s);

    const rings = [];
    for (const o of orbits) {
        g.strokeStyle = 'rgba(201,162,74,0.18)';
        g.lineWidth = 1;
        g.beginPath();
        const rad = orbitRadius(o, t);
        g.ellipse(boss.x * s, boss.y * s, rad * s, rad * o.tilt * s, 0, 0, 7);
        g.stroke();
        for (let i = 0; i < o.rings; i++) rings.push(ringAt(i, t, o));
    }

    for (const r of rings) if (r.behind) drawRing(r);
    g.fillStyle = '#2a1d4e';
    g.strokeStyle = COL.gold;
    g.lineWidth = 1.5;
    g.beginPath();
    g.ellipse(boss.x * s, boss.y * s, 22, 30, 0, 0, 7);
    g.fill(); g.stroke();
    for (const r of rings) if (!r.behind) drawRing(r);
    for (const l of L) drawLaser(l);
    for (const b of B) dot(b, 1);

    if (pl.show) {
        g.globalAlpha = (inv > 0 && (inv >> 3) % 2) ? 0.35 : 1;
        g.fillStyle = '#4f8bff';
        g.beginPath();
        g.moveTo(pl.x * s, pl.y * s - 11);
        g.lineTo(pl.x * s - 8, pl.y * s + 8);
        g.lineTo(pl.x * s + 8, pl.y * s + 8);
        g.closePath(); g.fill();
        g.fillStyle = '#fff';
        g.beginPath(); g.arc(pl.x * s, pl.y * s, 2.4, 0, 7); g.fill();
        g.globalAlpha = 1;
    }
    if (label) {
        g.font = '500 13px Georgia, serif';
        g.fillStyle = 'rgba(214,180,98,0.85)';
        g.fillText(label, 14, GAME.fieldH * s - 14);
    }
    for (const f of listeners) f({ t, grains: B.length, hits });
}

// ---- control -----------------------------------------------------------------

function restart() {
    t = 0; B = []; L = []; hits = 0; inv = 0; store = {};
    boss.x = GAME.bossX;
    boss.y = GAME.bossY;
    pl.x = pl.tx = GAME.playerX;
    pl.y = pl.ty = GAME.playerY;
    if (pat.init) pat.init(api);
}

function choose(which) {
    const ps = set.patterns;
    let k = typeof which === 'number' ? which
          : ps.findIndex((p) => slug(p.name) === slug(which));
    if (k < 0 || k >= ps.length) throw new Error('no pattern ' + which);
    pat = ps[k];
    moves = pat.boss || set.boss || 'still';
    const base = { rings: 2, radius: 205, tilt: 0.53, depth: 0.2, dim: 0.55,
                   period: 172, way: 1, phase0: 0 };
    const list = pat.orbits || set.orbits;
    if (list) {
        orbits = list.map((o) => Object.assign({}, base, set.orbit || {}, o));
    } else if (set.orbit) {
        orbits = [Object.assign({}, base, set.orbit, pat.orbit || {})];
    } else {
        orbits = [];
    }
    orbit = orbits.length ? orbits[0] : null;
    restart();
    return k;
}

function slug(s) {
    return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
}

function mount(canvas, sc) {
    cv = canvas;
    g = cv.getContext('2d');
    resize(sc);
}

function resize(sc) {
    scale = sc;
    cv.width = Math.round(GAME.fieldW * VIEW * sc);
    cv.height = Math.round(GAME.fieldH * VIEW * sc);
}

window.Sketch = {
    GAME, VIEW,
    set(def) { sets[def.id] = def; },
    get sets() { return sets; },
    use(id) { set = sets[id]; if (!set) throw new Error('no set ' + id); return set; },
    get current() { return set; },
    get pattern() { return pat; },
    choose, restart, step, draw, mount, resize, slug, opts, player: pl,
    onFrame(f) { listeners.push(f); },
    get t() { return t; },
    get grains() { return B.length; },
    // The live bullets, for measuring a pattern (read only).
    get bullets() { return B; },
    get lasers() { return L; },
    get hits() { return hits; },
    // The frames after which the current pattern repeats exactly.
    get loop() { return pat.loop ? pat.loop(orbit) : (orbit ? orbit.period : 120); },
    // Headless capture (`tools/sketch.py`).
    capture: {
        prepare(sc, text) { resize(sc); label = text; pl.show = false; },
        advance(n) { for (let k = 0; k < n; k++) step(); },
        frame() { draw(); return cv.toDataURL('image/png'); },
    },
};
})();
