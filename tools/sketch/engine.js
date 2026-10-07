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
 *   patterns          [{name, emit(api), step?(api), orbit?, orbits?, boss?,
 *                     loop?}]
 * A pattern's `orbit` overrides fields of the set's, its `orbits` replaces
 * them (each over the set's `orbit`), and its `boss` the set's. `loop` is the frames
 * after which it repeats exactly (default one orbit), used for GIFs.
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
let t = 0, B = [], hits = 0, inv = 0, store = {};
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
    const r = onOrbit((o.phase0 || 0) + i * 360 / o.rings + 360 * tt / o.period,
                      o.radius, boss, o);
    r.i = i;
    r.o = o;
    r.size = 1 - o.depth * r.far;
    return r;
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
    if (moves !== 'step') return;
    const cyc = GAME.stepHold + GAME.stepMove;
    const n = Math.floor(t / cyc);
    const to = (t % cyc < GAME.stepHold) ? n : n + 1;
    const tx = GAME.bossX + dsin(to * 137) * GAME.stepX;
    const ty = GAME.bossY + dsin(to * 71) * GAME.stepY;
    boss.x += (tx - boss.x) * GAME.stepRate;
    boss.y += (ty - boss.y) * GAME.stepRate;
}

// Is the boss holding still (`boss_holding`)? Always, unless it steps.
function holding() {
    if (moves !== 'step') return true;
    return t % (GAME.stepHold + GAME.stepMove) < GAME.stepHold;
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
 * `sway` (degrees it swings either side of down while falling). Any bullet
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
    grain, bullet,
};

function step() {
    t++;
    stepBoss();
    if (pat.step) pat.step(api);
    pat.emit(api);
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
    for (const b of B) {
        if (Math.hypot(b.x - pl.x, b.y - pl.y) < b.r + GAME.playerR) {
            hits++;
            inv = 90;
            break;
        }
    }
}

function dot(b, alpha) {
    const s = VIEW;
    g.globalAlpha = alpha;
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
        g.ellipse(boss.x * s, boss.y * s, o.radius * s,
                  o.radius * o.tilt * s, 0, 0, 7);
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
    t = 0; B = []; hits = 0; inv = 0; store = {};
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
