/// @desc The bullet pool, and the API a pattern is written in.
///
/// **Bullets are structs in a flat pool, not objects.** A screen of danmaku is
/// two to four thousand bullets, and four thousand GameMaker instances is four
/// thousand Step events, four thousand Draw events, an `instance_create` and a
/// destroy for every one of them, and a collision system that wants to know
/// about all of it. The pool is one array, one loop, one draw pass, and one
/// distance check per bullet against a single point. That is the whole reason
/// this runs at sixty frames.
///
/// It is the same argument `obj_game` in the Wordsearch project makes for not
/// giving a board tile an object: a bullet has no behaviour that needs to be
/// resolved locally, so an object per bullet buys nothing and costs everything.
///
/// **A dead bullet is swapped with the last live one and the count drops.**
/// Order does not matter to a bullet, so removal is O(1) and the array stays
/// dense -- and the struct beyond the count is *kept*, not freed, so a pattern
/// that fires a thousand bullets a second allocates nothing after its first
/// second. The step loop runs backwards for the same reason: a swap-remove at
/// `i` moves an unvisited bullet into `i`, and a forward loop would skip it.
///
/// **The firing API is modelled on Danmakufu ph3.** `fire` is `CreateShotA1`:
/// a position, a speed, an angle, a graphic and a delay. Everything else --
/// rings, fans, stacks, spirals -- is built out of it, and every one of those
/// returns nothing while `fire` returns the bullet, because the single-shot
/// case is the one that wants tweaking afterwards and the pattern case never
/// does.
///
/// **A bullet is moved by one of two models and told what to do by a queue.**
/// `fire` gives the polar one -- direction, speed, acceleration, turn rate --
/// which is ph3's A-series and what nearly every pattern in this game is
/// written in. `fire_xy` and `bullet_force` give the Cartesian one, which is
/// its B-series, and the reason it is here rather than being folded into the
/// first is that a force in a single axis has no polar expression at all: a
/// bullet that falls, arcs or is blown sideways cannot be written as a speed
/// and a heading. `dir` and `spd` stay true on both, so nothing downstream
/// ever asks which one a bullet is on.
///
/// The queue is `BQ` and it is ph3's `AddPattern` family: a sorted list of
/// things to do at particular frames, walked off the front. What it replaced
/// was a single modifier slot, which allowed a bullet exactly one event ever
/// -- so "aim at 20, accelerate at 40, break into six at 80" was a pattern
/// this engine could not hold.

// ---------------------------------------------------------------------------
// The pool
// ---------------------------------------------------------------------------

/// @desc Create the pool. Called once, from obj_boot.
function danmaku_init() {
    global.bullets = [];
    global.bullet_n = 0;
    global.bullet_peak = 0;
    global.bullet_refused = 0;

    global.pshots = [];
    global.pshot_n = 0;
}

/// @desc A blank bullet struct. Only ever called when the pool has to grow.
function bullet_blank() {
    return {
        x: 0, y: 0, px: 0, py: 0,

        // The polar half of the motion model, and the one nearly every bullet
        // in the game is on.
        dir: 0, spd: 0, acc: 0, spd_min: -9999, spd_max: 9999,
        turn: 0,

        // The Cartesian half -- ph3's B-series. `cart` says which of the two
        // is moving this bullet; `dir` and `spd` are kept true on both, so
        // collision, aiming and every oriented sprite go on reading one
        // motion model whichever one is doing the work.
        cart: false,
        vx: 0, vy: 0, ax: 0, ay: 0,
        vx_min: -9999, vx_max: 9999, vy_min: -9999, vy_max: 9999,

        shape: BSHAPE_ORB, col: BCOL_BONE, r: 5, scale: 1,
        angle: 0, spin: 0,
        delay: 0, delay0: 0,

        // Leaving by time rather than by leaving the field. A fading bullet is
        // already harmless -- see `bullet_fade`.
        fade_t: 0, fade_n: 1,

        life: 0,

        // What it does every frame, and what it has been told to do on
        // particular ones. The queue's slots are kept the way the pool's
        // structs are: `q_n` is how many are in use and the array beyond it is
        // last time's, so a pattern that schedules three events on every
        // bullet it fires allocates nothing after its first second.
        bmod: BMod.Plain, mod_a: 0, mod_b: 0,
        q: [], q_n: 0, q_i: 0,

        // **Bomb-proof.** A sweep the player caused spares it; a sweep the
        // game causes does not. See `bullet_clear_circle`.
        resist: false,

        grazed: false,
    };
}

/// @desc How many bullets are live.
function bullet_count() {
    return global.bullet_n;
}

/// @desc The live bullet at `_i`. Only valid for `_i < bullet_count()`.
function bullet_get(_i) {
    return global.bullets[_i];
}

/// @desc Take a slot off the pool, growing it if it has to. `undefined` past
///       the cap -- **a refusal, not a resize**. A pool that grows without
///       limit turns a runaway pattern into a machine that stops responding,
///       which is far harder to find than a pattern that visibly stops firing.
function bullet_alloc() {
    if (global.bullet_n >= BULLET_MAX) {
        global.bullet_refused++;
        return undefined;
    }
    var _i = global.bullet_n;
    if (_i >= array_length(global.bullets)) {
        array_push(global.bullets, bullet_blank());
    }
    global.bullet_n = _i + 1;
    if (global.bullet_n > global.bullet_peak) {
        global.bullet_peak = global.bullet_n;
    }
    return global.bullets[_i];
}

/// @desc Retire the bullet at index `_i`, in O(1).
function bullet_kill_at(_i) {
    var _last = global.bullet_n - 1;
    if (_i != _last) {
        var _tmp = global.bullets[_i];
        global.bullets[_i] = global.bullets[_last];
        global.bullets[_last] = _tmp;
    }
    global.bullet_n = _last;
}

// ---------------------------------------------------------------------------
// Firing
// ---------------------------------------------------------------------------

/// @desc Fire one bullet. The ph3 `CreateShotA1`, and everything else is built
///       out of it. Returns the bullet so the caller can set `turn`, a `bmod`
///       or a scale on it; `undefined` if the pool is full, and **every caller
///       must cope with that** -- see `bullet_alloc`.
/// @param {real} _x
/// @param {real} _y
/// @param {real} _spd
/// @param {real} _dir     degrees, GameMaker's sense: 0 is right, 90 is up
/// @param {real} _shape   BSHAPE_*
/// @param {real} _col     BCOL_*
/// @param {real} _delay   frames spent intangible, fading in. See below.
function fire(_x, _y, _spd, _dir, _shape, _col, _delay = BULLET_DELAY_DEFAULT) {
    var _b = bullet_alloc();
    if (_b == undefined) return undefined;

    _b.x = _x;  _b.y = _y;
    _b.px = _x; _b.py = _y;
    _b.dir = _dir;
    _b.spd = _spd;
    _b.acc = 0;
    _b.spd_min = -9999;
    _b.spd_max = 9999;
    _b.turn = 0;
    // **Every field the pool reuses is reset here, without exception.** A
    // struct beyond `bullet_n` is last second's bullet rather than a blank
    // one, so a field left out of this list is a bullet inheriting a force, a
    // fade or a queue from whatever held its slot before it -- which reaches a
    // player as one bullet in a thousand behaving like a different pattern, at
    // random, in a fight nobody has changed.
    _b.cart = false;
    _b.vx = 0; _b.vy = 0; _b.ax = 0; _b.ay = 0;
    _b.vx_min = -9999; _b.vx_max = 9999;
    _b.vy_min = -9999; _b.vy_max = 9999;
    _b.shape = _shape;
    _b.col = _col;
    _b.r = global.bshape_radius[_shape];
    _b.scale = 1;
    _b.angle = _dir;
    // **A star-shaped bullet turns on its own, and the rate is a property of
    // the shape rather than of the caller.** Every danmaku game in the genre
    // spins its stars, and a pattern that had to remember to ask would have
    // half its stars spinning and half not. `angle` starts at the firing
    // direction, so a ring of them is phase-scattered for free -- which is
    // what stops thirty spinning stars reading as one turning object.
    //
    // Zero for everything oriented, because there `angle` *is* the heading
    // and adding to it would aim the sprite somewhere the bullet is not going.
    _b.spin = global.bshape_spin[_shape];
    _b.delay = _delay;
    _b.delay0 = max(1, _delay);
    _b.fade_t = 0;
    _b.fade_n = 1;
    _b.life = 0;
    _b.bmod = BMod.Plain;
    _b.mod_a = 0;
    _b.mod_b = 0;
    _b.q_n = 0;
    _b.q_i = 0;
    _b.resist = false;
    _b.grazed = false;

    // **Every bullet asks for a sound and the frame gets one.** `sfx` costs an
    // array increment and nothing else; `sfx_step` turns however many arrived
    // this frame into a single voice whose gain and pitch say how many there
    // were. That is why this can sit in the hottest function in the game
    // without a cooldown, a counter or a rule at the call site -- see the
    // docstring on `audio_functions`, which is entirely about this line.
    //
    // On fire rather than when the delay expires, because the mark *is* the
    // telegraph: what the player has to react to appears now, and a cue that
    // waited for the bullet to go live would arrive after the moment it was
    // warning about.
    sfx(sfx_for_shape(_shape));
    return _b;
}

/// @desc Fire one bullet in Cartesian components. The ph3 `CreateShotB1`.
///
///       **The polar model cannot express a force in one axis, and that is the
///       whole reason this exists.** `dir`, `spd`, `acc` and `turn` bend a path
///       only along its own direction, so anything that falls, arcs, lobs or is
///       blown sideways -- the entire gravity family -- has no expression in it
///       at all. Everything else the B-series does is a convenience this could
///       live without.
///
///       `dir` and `spd` are derived from the components rather than left
///       blank, because an oriented shape reads `dir` on its first frame and a
///       needle fired as a pair of components should not point right until it
///       has moved once.
function fire_xy(_x, _y, _vx, _vy, _shape, _col, _delay = BULLET_DELAY_DEFAULT) {
    var _b = fire(_x, _y, point_distance(0, 0, _vx, _vy),
                  point_direction(0, 0, _vx, _vy), _shape, _col, _delay);
    if (_b == undefined) return undefined;
    _b.cart = true;
    _b.vx = _vx;
    _b.vy = _vy;
    return _b;
}

/// @desc Give a bullet a per-axis force, putting it on the Cartesian model to
///       carry it. `fire_xy` and this together are the ph3 `CreateShotB2`, and
///       a *polar* bullet handed a force converts here -- which is what makes
///       "fire an aimed fan and let it fall" one extra line rather than a
///       different way of writing the fan.
///
///       **The caps are sign-aware**, on the same terms as `BQ.Accel`'s: they
///       are read off the velocity the bullet already has, so a cap can only
///       ever be a terminal velocity and never a shove. `BQ_KEEP` is no cap at
///       all, which is not the same as a cap of zero.
function bullet_force(_u, _ax, _ay, _vx_cap = BQ_KEEP, _vy_cap = BQ_KEEP) {
    if (_u == undefined) return undefined;
    if (!_u.cart) {
        _u.cart = true;
        _u.vx = lengthdir_x(_u.spd, _u.dir);
        _u.vy = lengthdir_y(_u.spd, _u.dir);
    }
    _u.ax = _ax;
    _u.ay = _ay;
    if (_vx_cap != BQ_KEEP) {
        _u.vx_min = min(_u.vx, _vx_cap);
        _u.vx_max = max(_u.vx, _vx_cap);
    }
    if (_vy_cap != BQ_KEEP) {
        _u.vy_min = min(_u.vy, _vy_cap);
        _u.vy_max = max(_u.vy, _vy_cap);
    }
    return _u;
}

/// @desc Put a bullet back on the polar model, keeping the velocity it has.
///
///       **A polar instruction wins.** A bullet told to aim, or to change its
///       speed, is being described in `dir` and `spd`; leaving it on the
///       Cartesian model would mean a force set forty frames ago silently
///       overriding the instruction that has just arrived. Nothing has to be
///       recomputed, because `bullet_step` keeps `dir` and `spd` true on both
///       models -- which is most of why it bothers to.
function bullet_repolar(_u) {
    _u.cart = false;
    _u.ax = 0;
    _u.ay = 0;
}

/// @desc Start a bullet fading out, and stop it being able to kill.
///
///       **Harmless from this frame on**, which is the whole point of a fade
///       delete rather than a delete: what the player watches leave has
///       already stopped mattering, so the fade is a courtesy to the eye and
///       never a window in which a ghost can still land a hit. It is also why
///       a bullet deleted by *time* fades rather than vanishing -- one that
///       blinks out in the middle of the field reads as a bug in the game
///       rather than as a rule of the pattern.
function bullet_fade(_u, _frames = BULLET_FADE_DEFAULT) {
    if (_u == undefined) return undefined;
    if (_u.fade_t > 0) return _u;          // already on its way out
    _u.fade_n = max(1, _frames);
    _u.fade_t = _u.fade_n;
    return _u;
}

/// @desc The angle from one point to another, in GameMaker's sense.
///       Pure, and takes the target explicitly rather than reading the player
///       out of a global -- which is what lets a suite aim a pattern at a
///       coordinate and assert on where the bullets went.
function aim_at(_x, _y, _tx, _ty) {
    return point_direction(_x, _y, _tx, _ty);
}

/// @desc `_n` bullets evenly around a full circle, starting at `_dir0`.
function fire_ring(_x, _y, _n, _spd, _dir0, _shape, _col,
                   _delay = BULLET_DELAY_DEFAULT) {
    if (_n <= 0) return;
    var _step = 360 / _n;
    for (var _i = 0; _i < _n; _i++) {
        fire(_x, _y, _spd, _dir0 + _i * _step, _shape, _col, _delay);
    }
}

/// @desc `_n` bullets spread across `_arc` degrees, centred on `_dir`.
///
///       **One bullet goes down the centre line, and that is a rule about
///       fairness rather than about geometry.** With an even `_n` the fan has
///       a gap on the aim line, so an aimed even fan is a pattern the player
///       survives by standing still -- and an aimed odd fan is one they must
///       move for. Both are legitimate; what is not legitimate is not knowing
///       which one you wrote. `_n - 1` divisions is what puts the ends at
///       `_dir +/- _arc/2` and the middle where you would expect it.
function fire_fan(_x, _y, _n, _spd, _dir, _arc, _shape, _col,
                  _delay = BULLET_DELAY_DEFAULT) {
    if (_n <= 0) return;
    if (_n == 1) {
        fire(_x, _y, _spd, _dir, _shape, _col, _delay);
        return;
    }
    var _step = _arc / (_n - 1);
    var _start = _dir - _arc * 0.5;
    for (var _i = 0; _i < _n; _i++) {
        fire(_x, _y, _spd, _start + _i * _step, _shape, _col, _delay);
    }
}

/// @desc `_n` bullets down one line at rising speeds -- a "stack".
///       The workhorse of aimed pressure: it arrives as a stream rather than a
///       wall, so the player is asked to move once and then keep moving.
function fire_stack(_x, _y, _n, _spd0, _spd_step, _dir, _shape, _col,
                    _delay = BULLET_DELAY_DEFAULT) {
    for (var _i = 0; _i < _n; _i++) {
        fire(_x, _y, _spd0 + _i * _spd_step, _dir, _shape, _col, _delay);
    }
}

/// @desc A ring of stacks: `_rings` speeds, `_n` around each.
function fire_ring_stack(_x, _y, _n, _rings, _spd0, _spd_step, _dir0,
                         _shape, _col, _delay = BULLET_DELAY_DEFAULT) {
    for (var _s = 0; _s < _rings; _s++) {
        fire_ring(_x, _y, _n, _spd0 + _s * _spd_step, _dir0, _shape, _col,
                  _delay);
    }
}

/// @desc A fan of stacks: `_rows` speeds, `_n` across `_arc` in each.
///
///       **`fire_ring_stack`'s missing sibling, and the difference between a
///       fan and a volley.** One fan is a wall that arrives all at once: the
///       player steps out of one gap and is done with it. The same fan sent at
///       three speeds arrives as three arcs a beat apart, so the answer is a
///       move and then two more moves -- which is what `fire_stack` does for a
///       single line, one dimension up.
///
///       **Each row is turned by `_skew` from the one in front**, because
///       three rows fired down identical headings put their gaps on the same
///       radial lines and the whole volley has one answer. Half a step is the
///       useful value and the default is zero, so a caller who wants the
///       columns to line up can still have that.
function fire_fan_stack(_x, _y, _n, _rows, _spd0, _spd_step, _dir, _arc,
                        _shape, _col, _delay = BULLET_DELAY_DEFAULT,
                        _skew = 0) {
    for (var _r = 0; _r < _rows; _r++) {
        fire_fan(_x, _y, _n, _spd0 + _r * _spd_step, _dir + _r * _skew, _arc,
                 _shape, _col, _delay);
    }
}

/// @desc `_n` bullets at random angles inside `_arc` of `_dir`, random speeds.
///       Deliberately the only random helper: a pattern made of noise is a
///       pattern nobody can learn, so this is for texture over a readable
///       shape and never for the shape itself.
function fire_spray(_x, _y, _n, _spd0, _spd1, _dir, _arc, _shape, _col,
                    _delay = BULLET_DELAY_DEFAULT) {
    for (var _i = 0; _i < _n; _i++) {
        fire(_x, _y, random_range(_spd0, _spd1),
             _dir + random_range(-_arc * 0.5, _arc * 0.5), _shape, _col,
             _delay);
    }
}

// ---------------------------------------------------------------------------
// Scheduled events
//
// **A bullet used to be allowed exactly one event in its life**: a single
// modifier slot with a frame number beside it, which meant "accelerate at 30
// and then turn at 60" was not a thing that could be written -- and neither
// was any of ph3's `AddPattern` chain, which is how most of the genre's
// second-half patterns are built. The queue is that slot made into a list.
//
// It is sorted on insertion and walked off the front, so the cost to a bullet
// carrying no events is one integer compare -- the same bargain `BMod` makes,
// and the reason the ninety per cent of bullets that are plain go on costing
// what they always did.
//
// Every kind has a named helper below, because `bullet_schedule(_b, 40,
// BQ.Split, 6.2, 30, 12)` is four numbers whose meaning is in an enum comment
// somewhere else, and a pattern is meant to read as a paragraph.
// ---------------------------------------------------------------------------

/// @desc Schedule one event at frame `_at` of a bullet's life. Sorted on
///       insert, so a pattern may add them in any order it likes; **refused**
///       past `BULLET_QUEUE_MAX` rather than growing, on the same terms as the
///       pool itself. Returns the bullet, so calls chain.
///
///       Takes `undefined` and answers `undefined`, because `fire` does -- a
///       pattern that fires into a full pool should not have to test before
///       every line that decorates what it fired.
function bullet_schedule(_u, _at, _kind, _a = 0, _b = 0, _c = 0, _d = 0) {
    if (_u == undefined) return undefined;
    if (_u.q_n >= BULLET_QUEUE_MAX) return _u;

    if (_u.q_n >= array_length(_u.q)) {
        array_push(_u.q, { at: 0, kind: BQ.Aim, a: 0, b: 0, c: 0, d: 0 });
    }
    var _e = _u.q[_u.q_n];
    _e.at = _at;
    _e.kind = _kind;
    _e.a = _a;
    _e.b = _b;
    _e.c = _c;
    _e.d = _d;
    _u.q_n++;

    // Walk it down to where its frame belongs. The array's *references* move
    // rather than the slots' contents, so nothing is ever reallocated and a
    // bullet that has queued eight events once queues eight for free forever
    // after. Insertion order is nearly always sorted already, so this is
    // nearly always one compare.
    var _i = _u.q_n - 1;
    while (_i > _u.q_i && _u.q[_i - 1].at > _u.q[_i].at) {
        var _tmp = _u.q[_i - 1];
        _u.q[_i - 1] = _u.q[_i];
        _u.q[_i] = _tmp;
        _i--;
    }
    return _u;
}

/// @desc Turn to face the target at `_at`, plus `_off` degrees of lead or lag.
///       ph3's `AddPatternA4`, and the old `BMod.Aimed`.
function bullet_aim_at(_u, _at, _off = 0) {
    return bullet_schedule(_u, _at, BQ.Aim, _off);
}

/// @desc Set speed and direction outright at `_at`. ph3's `AddPatternA1`.
///       `BQ_KEEP` leaves either of them alone, because zero speed and zero
///       degrees are both things a pattern might genuinely mean.
function bullet_move_at(_u, _at, _spd = BQ_KEEP, _dir = BQ_KEEP) {
    return bullet_schedule(_u, _at, BQ.Move, _spd, _dir);
}

/// @desc Start accelerating at `_at`, up to `_cap`. The old `BMod.Accel`.
function bullet_accel_at(_u, _at, _acc, _cap = BQ_KEEP) {
    return bullet_schedule(_u, _at, BQ.Accel, _acc, _cap);
}

/// @desc Start turning at `_at`, `_turn` degrees a frame. The old `BMod.Turn`.
function bullet_turn_at(_u, _at, _turn) {
    return bullet_schedule(_u, _at, BQ.Turn, _turn);
}

/// @desc Apply a per-axis force at `_at` -- gravity that switches on partway,
///       which is the shape most lobbed patterns actually want.
function bullet_force_at(_u, _at, _ax, _ay, _vx_cap = BQ_KEEP,
                         _vy_cap = BQ_KEEP) {
    return bullet_schedule(_u, _at, BQ.Force, _ax, _ay, _vx_cap, _vy_cap);
}

/// @desc Burst into `_n` children at `_at` **and die**. The old `BMod.Split`.
function bullet_split_at(_u, _at, _n, _spd, _off = 0) {
    return bullet_schedule(_u, _at, BQ.Split, _spd, _off, _n);
}

/// @desc Shed `_n` children at `_at`, `_dist` pixels out, **and keep going**.
///       ph3's `ObjShot_AddShotA1`/`A2`, and the difference from a split is
///       the whole of why it is a separate kind: a bullet that drops a wake
///       behind it is a different pattern from one that bursts, and the old
///       modifier could only express the second.
function bullet_shed_at(_u, _at, _n, _spd, _off = 0, _dist = 0) {
    return bullet_schedule(_u, _at, BQ.Shed, _spd, _off, _n, _dist);
}

/// @desc A wake: shed `_times` times, every `_period` frames from `_from`.
///
///       Written as `_times` ordinary entries rather than as a repeating one,
///       because a repeating entry cannot be walked off the front of a sorted
///       list and the whole queue would have to be rescanned every frame for
///       every bullet. `BULLET_QUEUE_MAX` is the ceiling on how long a wake
///       can be, which is a real limit and a deliberate one.
function bullet_shed_every(_u, _from, _period, _times, _n, _spd, _off = 0,
                           _dist = 0) {
    for (var _k = 0; _k < _times; _k++) {
        bullet_shed_at(_u, _from + _k * _period, _n, _spd, _off, _dist);
    }
    return _u;
}

/// @desc Change what a bullet *is* at `_at`. ph3's `AddPatternA3`.
///
///       **The hitbox follows the picture**, because `bullet_table` is the one
///       place either of them is decided and a bullet drawn as a needle while
///       colliding as the orb it used to be is the exact lie that file exists
///       to prevent.
function bullet_graphic_at(_u, _at, _shape, _col) {
    return bullet_schedule(_u, _at, BQ.Graphic, _shape, _col);
}

/// @desc Give a bullet a lifetime. ph3's `ObjShot_SetDeleteFrame`, except that
///       it fades rather than vanishing -- see `bullet_fade`.
///
///       **Without this a bullet only ever leaves by leaving the field**, and
///       there are patterns that never do: anything homing, and anything with
///       a turn rate high enough to orbit, stays in the pool for the whole
///       fight. The pool is a refusal rather than a resize, so what that
///       reaches a player as is a boss whose later patterns quietly stop
///       firing.
function bullet_expire_at(_u, _at, _frames = BULLET_FADE_DEFAULT) {
    return bullet_schedule(_u, _at, BQ.Fade, _frames);
}

/// @desc The burst both `BQ.Split` and `BQ.Shed` fire.
///
///       **The children carry the parent's shape and colour**, which is what
///       makes a burst legible as *that bullet* going off rather than as one
///       bullet vanishing and some unrelated ones appearing. They are born
///       intangible like everything else -- a burst on top of the player is
///       exactly the case the delay marks exist for.
function bullet_spawn_children(_u, _n, _spd, _off, _dist) {
    var _count = max(1, _n);
    var _step = 360 / _count;
    for (var _k = 0; _k < _count; _k++) {
        var _dir = _u.dir + _off + _k * _step;
        fire(_u.x + lengthdir_x(_dist, _dir),
             _u.y + lengthdir_y(_dist, _dir),
             _spd, _dir, _u.shape, _u.col, BULLET_SPLIT_DELAY);
    }
}

/// @desc Apply every scheduled event whose frame has come. Answers **true if
///       the bullet is spent**, which today only a split is -- the caller kills
///       it, so "how a bullet leaves" stays in the step loop rather than being
///       faked by shoving it off the edge of the world and letting the cull
///       find it.
function bullet_run_queue(_u, _tx, _ty) {
    while (_u.q_i < _u.q_n) {
        var _e = _u.q[_u.q_i];
        if (_u.life < _e.at) break;
        _u.q_i++;

        switch (_e.kind) {
            case BQ.Aim:
                _u.dir = aim_at(_u.x, _u.y, _tx, _ty) + _e.a;
                bullet_repolar(_u);
                break;

            case BQ.Move:
                if (_e.a != BQ_KEEP) _u.spd = _e.a;
                if (_e.b != BQ_KEEP) _u.dir = _e.b;
                bullet_repolar(_u);
                break;

            case BQ.Accel:
                _u.acc = _e.a;
                if (_e.b != BQ_KEEP) {
                    _u.spd_min = min(_u.spd, _e.b);
                    _u.spd_max = max(_u.spd, _e.b);
                }
                bullet_repolar(_u);
                break;

            case BQ.Turn:
                _u.turn = _e.a;
                bullet_repolar(_u);
                break;

            case BQ.Force:
                bullet_force(_u, _e.a, _e.b, _e.c, _e.d);
                break;

            case BQ.Split:
                bullet_spawn_children(_u, _e.c, _e.a, _e.b, 0);
                return true;

            case BQ.Shed:
                bullet_spawn_children(_u, _e.c, _e.a, _e.b, _e.d);
                break;

            case BQ.Graphic:
                _u.shape = _e.a;
                _u.col = _e.b;
                _u.r = global.bshape_radius[_e.a];
                // The new shape's default spin, for the same reason `fire`
                // takes it: a pellet that becomes a star mid-flight should
                // turn like every other star on the field.
                _u.spin = global.bshape_spin[_e.a];
                break;

            case BQ.Fade:
                bullet_fade(_u, _e.a);
                break;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// The step
// ---------------------------------------------------------------------------

/// @desc Advance every bullet one frame, cull what has left, and resolve the
///       modifiers. `_tx`/`_ty` is what an aiming or homing bullet aims at.
function bullet_step(_tx, _ty) {
    var _l = FIELD_X0 - CULL_MARGIN;
    var _t = FIELD_Y0 - CULL_MARGIN;
    var _r = FIELD_X1 + CULL_MARGIN;
    var _b = FIELD_Y1 + CULL_MARGIN;

    // The pool is hoisted out of the loop. Under the VM runtime every
    // `global.x` is a hash lookup, and this loop runs a few thousand times a
    // frame -- so a local reference to the array is one of the two or three
    // changes in this file that are actually worth making for speed.
    var _pool = global.bullets;
    var _oriented = global.bshape_oriented;

    // Backwards, because a swap-remove at `_i` moves an unvisited bullet into
    // `_i` and a forward loop would step straight past it.
    for (var _i = global.bullet_n - 1; _i >= 0; _i--) {
        var _u = _pool[_i];

        if (_u.delay > 0) {
            _u.delay--;
            // A delayed bullet does not move. It is a mark on the floor saying
            // something is about to be here, and a mark that drifted would be
            // a promise the bullet then breaks.
            continue;
        }

        // On its way out by time rather than by leaving. It is already
        // harmless -- `bullet_fade` says why -- so this is only how long the
        // light takes to go.
        if (_u.fade_t > 0) {
            _u.fade_t--;
            if (_u.fade_t <= 0) {
                bullet_kill_at(_i);
                continue;
            }
        }

        // Two integer compares for a bullet that is doing neither, which is
        // nearly all of them.
        if (_u.q_i < _u.q_n && bullet_run_queue(_u, _tx, _ty)) {
            bullet_kill_at(_i);
            continue;
        }

        if (_u.bmod != BMod.Plain) {
            bullet_apply_mod(_u, _tx, _ty);
        }

        if (_u.cart) {
            // **The Cartesian model, and the one thing the polar one cannot
            // do.** Each axis carries its own force and its own cap, which is
            // what makes a bullet fall, arc or drift sideways.
            _u.vx = clamp(_u.vx + _u.ax, _u.vx_min, _u.vx_max);
            _u.vy = clamp(_u.vy + _u.ay, _u.vy_min, _u.vy_max);

            _u.px = _u.x;
            _u.py = _u.y;
            _u.x += _u.vx;
            _u.y += _u.vy;

            // `dir` and `spd` are kept true rather than left stale, so an
            // oriented sprite points where it is going, a later polar
            // instruction has something honest to start from, and nothing
            // downstream ever has to ask which model this bullet is on. A
            // stationary bullet keeps the heading it had, because
            // `point_direction` of nothing is right rather than unchanged.
            _u.spd = point_distance(0, 0, _u.vx, _u.vy);
            if (_u.spd > 0) _u.dir = point_direction(0, 0, _u.vx, _u.vy);
        } else {
            _u.spd = clamp(_u.spd + _u.acc, _u.spd_min, _u.spd_max);
            _u.dir += _u.turn;

            _u.px = _u.x;
            _u.py = _u.y;
            _u.x += lengthdir_x(_u.spd, _u.dir);
            _u.y += lengthdir_y(_u.spd, _u.dir);
        }

        if (_oriented[_u.shape]) {
            _u.angle = _u.dir;
        } else {
            _u.angle += _u.spin;
        }

        _u.life++;

        if (_u.x < _l || _u.x > _r || _u.y < _t || _u.y > _b) {
            bullet_kill_at(_i);
        }
    }
}

/// @desc The two behaviours that are not events: a bullet doing one of these
///       is doing it on every frame it has, so neither carries a frame number
///       and neither belongs in the queue.
///
///       Both are described in `dir`, so a bullet carrying a force is put back
///       on the polar model here -- once, on the first frame the two disagree.
function bullet_apply_mod(_u, _tx, _ty) {
    if (_u.cart) bullet_repolar(_u);

    switch (_u.bmod) {
        case BMod.Home:
            // **Weakly, and with a cap.** A bullet that turns as fast as it
            // likes is unavoidable rather than hard, which is the line this
            // whole genre is drawn on. `mod_a` is degrees per frame.
            var _want = aim_at(_u.x, _u.y, _tx, _ty);
            _u.dir += clamp(angle_difference(_want, _u.dir), -_u.mod_a, _u.mod_a);
            break;

        case BMod.Wander:
            _u.dir += dsin(_u.life * _u.mod_b) * _u.mod_a;
            break;
    }
}

// ---------------------------------------------------------------------------
// Clearing
// ---------------------------------------------------------------------------

/// @desc Sweep every bullet within `_rad` of a point.
///       `_to_items` turns each into score, which is what a bomb and a cleared
///       spell both do. Returns how many went.
///
///       **A bullet marked `resist` survives this, and that is the difference
///       between the two sweeps.** A circle is something the *player* did --
///       a bomb, or the mercy clear that follows a hit -- and `resist` exists
///       to say "this one cannot be bombed away", which is how the genre
///       writes a survival spell. `bullet_clear_all` takes everything,
///       because that is the *game* changing what is on the field and a
///       bullet left over from the previous attack is a bug rather than a
///       challenge.
function bullet_clear_circle(_x, _y, _rad, _to_items) {
    var _n = 0;
    var _r2 = _rad * _rad;
    for (var _i = global.bullet_n - 1; _i >= 0; _i--) {
        var _u = global.bullets[_i];
        if (_u.resist) continue;
        var _dx = _u.x - _x;
        var _dy = _u.y - _y;
        if (_dx * _dx + _dy * _dy > _r2) continue;
        if (_to_items && (_n mod CLEAR_ITEM_EVERY) == 0) {
            item_spawn(_u.x, _u.y, ItemKind.Tally);
        }
        fx_bullet_pop(_u.x, _u.y, _u.col);
        bullet_kill_at(_i);
        _n++;
    }
    return _n;
}

/// @desc Sweep the whole field. What a phase change does.
function bullet_clear_all(_to_items) {
    var _n = global.bullet_n;
    for (var _i = _n - 1; _i >= 0; _i--) {
        var _u = global.bullets[_i];
        if (_to_items && (_i mod CLEAR_ITEM_EVERY) == 0) {
            item_spawn(_u.x, _u.y, ItemKind.Tally);
        }
        fx_bullet_pop(_u.x, _u.y, _u.col);
    }
    global.bullet_n = 0;
    return _n;
}

// ---------------------------------------------------------------------------
// Collision
// ---------------------------------------------------------------------------

/// @desc The distance from a point to a line segment.
///
///       **Bullets are tested against the segment they travelled, not the
///       point they landed on.** A dart at speed twenty-four moves twenty-four
///       pixels between frames and the player's hitbox is four; a point test
///       therefore misses roughly four times in five, and the bug it produces
///       is the worst kind there is -- a bullet that passes *through* the
///       player and does nothing, at random, which reads as the game being
///       broken rather than as the player being lucky.
function point_seg_dist(_px, _py, _x0, _y0, _x1, _y1) {
    var _dx = _x1 - _x0;
    var _dy = _y1 - _y0;
    var _len2 = _dx * _dx + _dy * _dy;
    if (_len2 <= 0.0001) {
        return point_distance(_px, _py, _x0, _y0);
    }
    var _t = clamp(((_px - _x0) * _dx + (_py - _y0) * _dy) / _len2, 0, 1);
    return point_distance(_px, _py, _x0 + _dx * _t, _y0 + _dy * _t);
}

/// @desc The first bullet that would hit a circle at (`_x`, `_y`), or -1.
///       Returns the *index*, so the caller can kill it without searching.
///
///       **Rejected on a box before it is measured on a segment.** This runs
///       over every live bullet every frame, and `point_seg_dist` is a GML
///       call with a dozen operations in it -- which under the VM runtime is
///       the single most expensive thing in this file. Nearly every bullet is
///       nowhere near the player, and two subtractions and two compares throw
///       those out before any of the real work happens.
function bullet_hit_index(_x, _y, _rad) {
    var _n = global.bullet_n;
    var _pool = global.bullets;
    for (var _i = 0; _i < _n; _i++) {
        var _u = _pool[_i];
        // Intangible either side of its life: still fading in, or already
        // fading out. **A bullet the player can see leaving has stopped being
        // able to kill them**, which is the courtesy that makes a timed
        // deletion readable rather than a trick.
        if (_u.delay > 0 || _u.fade_t > 0) continue;

        var _reach = _rad + _u.r;
        // The box has to cover the whole segment travelled, not just where the
        // bullet ended up -- otherwise a fast bullet is rejected here and the
        // swept test never runs, which is the tunnelling bug this was written
        // to prevent, reintroduced one level down.
        var _lo_x = min(_u.px, _u.x) - _reach;
        if (_x < _lo_x) continue;
        if (_x > max(_u.px, _u.x) + _reach) continue;
        var _lo_y = min(_u.py, _u.y) - _reach;
        if (_y < _lo_y) continue;
        if (_y > max(_u.py, _u.y) + _reach) continue;

        if (point_seg_dist(_x, _y, _u.px, _u.py, _u.x, _u.y) < _reach) {
            return _i;
        }
    }
    return -1;
}

/// @desc Mark every ungrazed bullet within `_rad` as grazed, and count them.
///
///       **A bullet is grazed once, ever.** Without the flag a player parked
///       beside a slow bullet grazes it sixty times a second, which turns the
///       one mechanic that rewards nerve into one that rewards loitering.
///
///       Squared distance, inline: no `sqrt` and no call. Same argument as
///       `bullet_hit_index` -- this walks the whole pool every frame.
function bullet_graze(_x, _y, _rad) {
    var _n = global.bullet_n;
    var _pool = global.bullets;
    var _count = 0;
    for (var _i = 0; _i < _n; _i++) {
        var _u = _pool[_i];
        if (_u.grazed || _u.delay > 0 || _u.fade_t > 0) continue;
        var _dx = _u.x - _x;
        var _dy = _u.y - _y;
        var _reach = _rad + _u.r;
        if (_dx * _dx + _dy * _dy < _reach * _reach) {
            _u.grazed = true;
            _count++;
        }
    }
    return _count;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc Which sprite frame a bullet is on.
///       **The only place the two axes are folded together.** A shape's frames
///       are its colours, and an animated shape's are colour-major with the
///       animation inside -- see `tools/make_bullets.py`.
function bullet_frame(_shape, _col, _life) {
    var _f = global.bshape_frames[_shape];
    if (_f <= 1) return _col;
    return _col * _f + ((_life div 3) mod _f);
}

/// @desc Draw every bullet. One pass, no state changes inside the loop except
///       the one blend-mode switch the delay marks need.
function bullet_draw() {
    var _n = global.bullet_n;

    // Pass one: the live bullets, in the normal blend. Drawn first so a delay
    // mark -- which is a *warning* -- is never hidden under the bullets
    // already on the field.
    for (var _i = 0; _i < _n; _i++) {
        var _u = global.bullets[_i];
        if (_u.delay > 0) continue;
        draw_sprite_ext(global.bshape_sprite[_u.shape],
                        bullet_frame(_u.shape, _u.col, _u.life),
                        _u.x, _u.y, _u.scale, _u.scale, _u.angle,
                        c_white,
                        (_u.fade_t > 0) ? _u.fade_t / _u.fade_n : 1);
    }

    // Pass two: the marks. Additive, oversized, and shrinking onto the spot
    // the bullet will occupy, so the shape of what is coming is legible before
    // any of it can hurt.
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < _n; _i++) {
        var _u = global.bullets[_i];
        if (_u.delay <= 0) continue;
        var _t = _u.delay / _u.delay0;                 // 1 at birth, 0 at live
        var _s = _u.scale * (1 + (BULLET_DELAY_SCALE - 1) * _t);
        draw_sprite_ext(global.bshape_sprite[_u.shape],
                        bullet_frame(_u.shape, _u.col, 0),
                        _u.x, _u.y, _s, _s, _u.angle,
                        c_white, 0.30 * (1 - _t) + 0.14);
    }
    gpu_set_blendmode(bm_normal);
}

// ---------------------------------------------------------------------------
// The player's own shots
//
// A separate, smaller pool. They differ from enemy bullets in every way that
// matters -- they are tested against a handful of enemies rather than against
// one point, they carry damage, and they never graze -- so sharing the pool
// would mean a branch per bullet per frame to ask which kind it was.
// ---------------------------------------------------------------------------

function pshot_fire(_x, _y, _spd, _dir, _dmg) {
    if (global.pshot_n >= PSHOT_MAX) return undefined;
    var _i = global.pshot_n;
    if (_i >= array_length(global.pshots)) {
        array_push(global.pshots, {
            x: 0, y: 0, px: 0, py: 0, dir: 0, spd: 0, dmg: 0, life: 0,
        });
    }
    global.pshot_n = _i + 1;
    var _s = global.pshots[_i];
    _s.x = _x;  _s.y = _y;
    _s.px = _x; _s.py = _y;
    _s.dir = _dir;
    _s.spd = _spd;
    _s.dmg = _dmg;
    _s.life = 0;
    return _s;
}

function pshot_kill_at(_i) {
    var _last = global.pshot_n - 1;
    if (_i != _last) {
        var _tmp = global.pshots[_i];
        global.pshots[_i] = global.pshots[_last];
        global.pshots[_last] = _tmp;
    }
    global.pshot_n = _last;
}

function pshot_step() {
    for (var _i = global.pshot_n - 1; _i >= 0; _i--) {
        var _s = global.pshots[_i];
        _s.px = _s.x;
        _s.py = _s.y;
        _s.x += lengthdir_x(_s.spd, _s.dir);
        _s.y += lengthdir_y(_s.spd, _s.dir);
        _s.life++;
        if (_s.x < FIELD_X0 - 60 || _s.x > FIELD_X1 + 60
            || _s.y < FIELD_Y0 - 60 || _s.y > FIELD_Y1 + 60) {
            pshot_kill_at(_i);
        }
    }
}

function pshot_count() {
    return global.pshot_n;
}
