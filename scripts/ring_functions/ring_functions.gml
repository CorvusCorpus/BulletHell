/// @desc Rings: large objects on the field that stop the player's fire.
///
/// **This is the first thing in the game that is neither a bullet nor an
/// enemy.** A bullet is something to dodge, an enemy is something to shoot,
/// and a ring is neither: it is furniture the boss puts down, it cannot be
/// destroyed, and what it does is *change where the player is allowed to
/// stand and where they are allowed to shoot from*. Mika's whole fight is
/// built out of them -- see `stage_sanctum` -- and nothing else in the game
/// uses one yet, which is why the pool lives here rather than in his file:
/// there is nothing about a ring that is about him.
///
/// **It blocks along its band and not across its middle, and that is the
/// whole design.** An indestructible shield in front of a boss would be the
/// defect `BossMove` exists to fix -- an attack that cannot be answered, only
/// waited out. A *ring* has a hole in it, so the answer is always there and it
/// is a positional one: line up through the middle, or go round. The player is
/// never told to stop shooting; they are told where to stand to keep shooting.
///
/// Four things a ring can do, and every one of them is a field:
///
/// - **Block.** Player shots that cross the metal are absorbed. Enemy bullets
///   are not, because they are his; and the bomb's seals are not either, which
///   is what stops a walled boss making the one panic button in the game
///   useless.
/// - **Kill.** The metal hurts to touch, always, from the frame it finishes
///   forming. A ring can also be *charged*, after a visible warning, which
///   widens the lethal band to the whole cuff and lights it -- so charging is
///   an escalation of a danger that is already there rather than the only
///   time there is one. It used to be the only time, and a player who flew
///   into a cold ring passed through it; see `RING_KILL_FRAC`.
/// - **Arc.** Two rings can be strung together with a line of current, which
///   is a lethal segment between two moving points -- a wall the player reads
///   off the two objects at its ends rather than off the wall itself.
/// - **Fire.** A ring carries an `act`, called every frame exactly as a boss's
///   attack is, so it can lay down bullets from its own rim or open a beam
///   through its own middle. `ring_fire_rim` and `ring_beam` are the two verbs
///   that turned out to be worth naming.
///
/// **The pool is the bullet pool's shape at a twentieth of the size**: one
/// flat array, swap-remove, structs kept rather than freed, and a refusal
/// rather than a resize past `RING_MAX`. There are never more than a handful,
/// so none of that is for speed -- it is so that a ring behaves the way
/// everything else on this field behaves, including being emptied by
/// `run_clear_field` and by the end of an attack.

// ---------------------------------------------------------------------------
// The pool
// ---------------------------------------------------------------------------

function ring_init() {
    global.rings = [];
    global.ring_n = 0;
    // **A serial, so a stale reference can be told from a live one.** A ring
    // struct is reused out of the pool, so an attack that remembers one and
    // reads it two seconds later may be reading whatever took that slot. The
    // Hex's note about a seal's target is the same trap; there the answer was
    // to re-pick every frame, and here it cannot be, because an attack that
    // spawned three rings means *those* three. So a ring is stamped and
    // `ring_valid` compares the stamp.
    global.ring_seq = 0;
}

function ring_blank() {
    return {
        x: 0, y: 0, vx: 0, vy: 0,
        // Where it was last frame. **Not the same as `vx`/`vy`**, which is
        // only the one way a ring can move: an orbiting ring is carried by
        // its `src` and its offset instead, and both of those move it without
        // either number changing. This is the whole truth about how fast the
        // metal is actually travelling -- see `ring_vel_x`.
        px: 0, py: 0,
        // **No radius.** Every ring is `RING_R` -- see the macro. A field here
        // would be a way for one attack to make a ring that behaves like a
        // different object, and the whole of what the player has to learn is
        // one shape.
        ang: 0, spin: 0,
        col: BCOL_GOLD,
        gen: 0,
        t: 0,
        ttl: 0,                  // 0 is "until something says otherwise"
        form: RING_FORM,         // arriving: visible, harmless, and no block
        fade: -1,                // leaving; -1 is "not"
        warn: 0, hot: 0,         // charging, then charged
        src: undefined,          // a struct with x/y this ring rides
        ox: 0, oy: 0,
        act: undefined,          // function(_ring, _g, _t), every frame
        arc: undefined,          // another ring this one is strung to
        arc_gen: -1, arc_t: 0,
        graze_t: 0,
        alive: true,
    };
}

function ring_count() {
    return global.ring_n;
}

function ring_get(_i) {
    return global.rings[_i];
}

function ring_alloc() {
    if (global.ring_n >= RING_MAX) return undefined;
    var _i = global.ring_n;
    if (_i >= array_length(global.rings)) {
        array_push(global.rings, ring_blank());
    }
    global.ring_n = _i + 1;
    var _g = global.rings[_i];
    _g.vx = 0; _g.vy = 0;
    _g.ang = 0; _g.spin = 0;
    _g.t = 0;
    _g.ttl = 0;
    _g.form = RING_FORM;
    _g.fade = -1;
    _g.warn = 0; _g.hot = 0;
    _g.src = undefined; _g.ox = 0; _g.oy = 0;
    _g.act = undefined;
    _g.arc = undefined; _g.arc_gen = -1; _g.arc_t = 0;
    _g.graze_t = 0;
    _g.alive = true;
    global.ring_seq++;
    _g.gen = global.ring_seq;
    return _g;
}

function ring_kill_at(_i) {
    var _last = global.ring_n - 1;
    global.rings[_i].alive = false;
    if (_i != _last) {
        var _tmp = global.rings[_i];
        global.rings[_i] = global.rings[_last];
        global.rings[_last] = _tmp;
    }
    global.ring_n = _last;
}

/// @desc Empty the field of rings. What the end of an attack does, on the same
///       terms as `bullet_clear_all` -- a ring left over from the last attack
///       is a bug rather than a challenge, and unlike a bullet it would never
///       leave the field on its own.
function ring_clear_all() {
    var _n = global.ring_n;
    for (var _i = 0; _i < _n; _i++) global.rings[_i].alive = false;
    global.ring_n = 0;
    return _n;
}

/// @desc Is this the same ring it was when the reference was taken?
///
///       **Both halves are load-bearing.** `alive` catches one that has been
///       swept, and `gen` catches the far nastier case: the slot being handed
///       straight back out to the next ring, which is live, in the right pool,
///       and not the one the caller meant.
function ring_valid(_ring, _gen) {
    return _ring != undefined && _ring.alive && _ring.gen == _gen;
}

// ---------------------------------------------------------------------------
// Putting one down
// ---------------------------------------------------------------------------

/// @desc A ring at a point, in a colour. `undefined` past the cap.
///
///       **There is no size argument**, and that is the point -- see `RING_R`.
///
///       It arrives over `RING_FORM` frames -- growing, translucent, and
///       harmless in both directions: it does not block and it cannot kill.
///       Same rule and same reason as `BULLET_DELAY_DEFAULT`: a thing that
///       appears fully formed on top of the player is a thing they could not
///       have answered.
function ring_new(_x, _y, _col = BCOL_GOLD, _ttl = 0) {
    var _g = ring_alloc();
    if (_g == undefined) return undefined;
    _g.x = _x; _g.y = _y;
    _g.px = _x; _g.py = _y;
    _g.col = _col;
    _g.ttl = _ttl;
    sfx(Sfx.WardClose);
    return _g;
}

/// @desc Ride something with an `x` and a `y` -- the caster, usually -- at a
///       fixed offset. The same seam a beam uses for its origin, and for the
///       same reason: a ring the boss carries has to drift with him or it
///       reads as scenery he happens to be standing near.
function ring_attach(_ring, _src, _ox = 0, _oy = 0) {
    if (_ring == undefined) return;
    _ring.src = _src;
    _ring.ox = _ox;
    _ring.oy = _oy;
}

/// @desc Charge the band: `_warn` frames of a visible build, then `_hot`
///       frames in which the metal kills.
///
///       **Never call it with `_warn` of zero.** A ring that electrifies on
///       the frame the player is standing in it is a coin toss, which is the
///       argument `laser_beam` makes for taking its warning as an ordinary
///       argument rather than as an option.
function ring_charge(_ring, _warn, _hot) {
    if (_ring == undefined) return;
    _ring.warn = _warn;
    _ring.hot = _hot;
    sfx(Sfx.LaserCharge);
}

/// @desc String current between two rings for `_frames`.
///
///       Held as a reference *and* the serial that went with it, so a ring
///       that dies mid-arc takes its arc with it rather than leaving a lethal
///       line to whatever reuses the slot.
function ring_link(_a, _b, _frames) {
    if (_a == undefined || _b == undefined) return;
    _a.arc = _b;
    _a.arc_gen = _b.gen;
    _a.arc_t = _frames;
}

/// @desc Start a ring leaving. It stops blocking and stops killing at once;
///       the fade is only the picture catching up.
function ring_dismiss(_ring, _frames = RING_FADE) {
    if (_ring == undefined || _ring.fade >= 0) return;
    _ring.fade = _frames;
    _ring.hot = 0;
    _ring.warn = 0;
    _ring.arc_t = 0;
}

// ---------------------------------------------------------------------------
// What a ring is, geometrically
// ---------------------------------------------------------------------------

/// @desc Half the thickness of the metal, in pixels.
///
///       **It takes no argument, because every ring is the same size.** What
///       it is a fraction *of* is quoted in `make_rings.py`, so the band that
///       is drawn and the band that blocks a shot are the same shape by
///       construction -- the property `capsule_half` buys the meters and
///       `laser_draw_curve` buys a curve.
function ring_band_half() {
    return RING_BAND_HALF;
}

/// @desc Is the metal there this frame? False while it is arriving and while
///       it is going.
function ring_solid(_ring) {
    return _ring.alive && _ring.form <= 0 && _ring.fade < 0;
}

/// @desc Is the band *charged* -- lit, and killing at its full width?
///
///       **This is no longer the question "can it kill"**; solid metal kills
///       whatever this answers, and what a charge adds is width and light. It
///       is still false during the warning, and that is still the rule it was
///       written for: what the build-up announces is the escalation, so the
///       escalation may not land before the build-up ends.
///
///       **`warn` has to be tested and the first version did not test it.**
///       `ring_charge` sets both counters at once, because the warning and
///       what follows it are one instruction; so `hot > 0` is true from the
///       frame the charge is *requested*, and a ring read that way was hot for
///       the whole of the build-up it was drawing to say it had not started
///       yet. Nothing about it would look wrong -- the picture is right, the
///       cue is right, the timing is right. `test_rings` is what found it, on
///       its first run.
function ring_is_hot(_ring) {
    return _ring.warn <= 0 && _ring.hot > 0 && ring_solid(_ring);
}

/// @desc Is this ring's arc live, and is the far end still the ring it was?
function ring_arc_live(_ring) {
    return _ring.arc_t > 0 && ring_solid(_ring)
           && ring_valid(_ring.arc, _ring.arc_gen)
           && ring_solid(_ring.arc);
}

/// @desc A point on the band, at `_dir` degrees round it.
function ring_rim_x(_ring, _dir) {
    return _ring.x + lengthdir_x(RING_R, _dir);
}

function ring_rim_y(_ring, _dir) {
    return _ring.y + lengthdir_y(RING_R, _dir);
}

/// @desc How far the metal moved this frame, however it is being moved --
///       under its own `vx`/`vy`, or carried round by the boss it rides.
function ring_vel_x(_ring) {
    return _ring.x - _ring.px;
}

function ring_vel_y(_ring) {
    return _ring.y - _ring.py;
}

/// @desc Where the point at `_dir` round the band will be in `_frames` frames,
///       if the ring goes on travelling as it is now.
///
///       **This is what a bullet fired off a moving ring has to be aimed
///       at.** Every bullet in this game is born as a mark that holds still
///       for its delay and only then goes live -- and a ring that is orbiting
///       its caster covers six pixels a frame, so over those frames the metal
///       slides on and the *hole* arrives where the mark is sitting. What that
///       reaches a player as is sand coming out of the middle of the ring
///       about half the time, which is exactly how it was reported. Firing
///       from where the metal is going to be puts the grain on the band on the
///       frame it becomes a grain; the mark leads the ring by a few pixels
///       until then, which reads as the mill throwing it.
///
///       A ring that is not moving leads by nothing, so nothing that stands
///       still is affected by any of this.
function ring_rim_at_x(_ring, _dir, _frames) {
    return _ring.x + ring_vel_x(_ring) * _frames + lengthdir_x(RING_R, _dir);
}

function ring_rim_at_y(_ring, _dir, _frames) {
    return _ring.y + ring_vel_y(_ring) * _frames + lengthdir_y(RING_R, _dir);
}

/// @desc How far a point is from the band -- zero on the metal, rising both
///       inward and outward.
///
///       **Split out because a hit and a graze are the same measurement at two
///       radii**, exactly as `laser_spine_dist` is. A ring that killed along
///       one line and paid along a slightly different one is a disagreement no
///       screenshot and no assertion about either half could ever show.
function ring_band_dist(_ring, _x, _y) {
    return abs(point_distance(_ring.x, _ring.y, _x, _y) - RING_R);
}

/// @desc Does the segment from (`_x0`,`_y0`) to (`_x1`,`_y1`) cross the band?
///
///       **Swept, and it has to be.** A player shot travels `PSHOT_SPD` --
///       thirty-six pixels a frame -- against a band that is twenty-three at a
///       200-pixel ring, so a point test would miss two shots in three and the
///       ring would read as leaking. Same defect and same fix as
///       `bullet_hit_index`.
///
///       The distance from the centre along a segment runs from its closest
///       approach to whichever end is furthest, and takes every value between,
///       so the segment meets the annulus exactly when that interval overlaps
///       the band. Two distance calls and a compare, with no root-finding.
function ring_seg_crosses(_ring, _x0, _y0, _x1, _y1) {
    var _half = RING_BAND_HALF;
    var _lo = point_seg_dist(_ring.x, _ring.y, _x0, _y0, _x1, _y1);
    if (_lo > RING_R + _half) return false;
    var _hi = max(point_distance(_ring.x, _ring.y, _x0, _y0),
                  point_distance(_ring.x, _ring.y, _x1, _y1));
    return _hi >= RING_R - _half;
}

// ---------------------------------------------------------------------------
// The step
// ---------------------------------------------------------------------------

function ring_step(_g) {
    for (var _i = global.ring_n - 1; _i >= 0; _i--) {
        var _r = global.rings[_i];

        // Kept before anything moves it, so `ring_vel_x` is this frame's
        // travel by the time the ring's own `act` runs and fires anything.
        _r.px = _r.x;
        _r.py = _r.y;

        if (_r.src != undefined) {
            _r.x = _r.src.x + _r.ox;
            _r.y = _r.src.y + _r.oy;
        } else {
            _r.x += _r.vx;
            _r.y += _r.vy;
        }

        _r.ang += _r.spin;

        if (_r.form > 0) _r.form--;
        if (_r.graze_t > 0) _r.graze_t--;
        if (_r.arc_t > 0) _r.arc_t--;

        // The charge: the warning runs down, and the frame it reaches zero the
        // band goes live. `hot` is set at the same time as `warn`, so a ring
        // that is never charged never touches either.
        if (_r.warn > 0) {
            _r.warn--;
            if (_r.warn == 0 && _r.hot > 0) {
                sfx(Sfx.LaserFire);
                fx_flash_at(_r.x, _r.y, global.bullet_colour[_r.col], 0.30);
            }
        } else if (_r.hot > 0) {
            _r.hot--;
        }

        // **The behaviour runs while the ring is arriving.** A ring that could
        // not fire until it had finished forming would open every attack with
        // a silent half-second, and the pattern is what the player is reading
        // the ring's arrival *for*.
        if (_r.act != undefined && _r.fade < 0) _r.act(_r, _g, _r.t);

        _r.t++;

        if (_r.ttl > 0 && _r.t >= _r.ttl && _r.fade < 0) {
            ring_dismiss(_r);
        }

        if (_r.fade >= 0) {
            _r.fade--;
            if (_r.fade < 0) {
                ring_kill_at(_i);
                continue;
            }
        }

        // Culled on geometry like everything else, and generously: a ring is
        // large, and one whose near edge is still on screen is still in the
        // way.
        var _out = RING_R + CULL_MARGIN;
        if (_r.x < FIELD_X0 - _out || _r.x > FIELD_X1 + _out
            || _r.y < FIELD_Y0 - _out || _r.y > FIELD_Y1 + _out) {
            ring_kill_at(_i);
        }
    }
}

// ---------------------------------------------------------------------------
// Blocking
// ---------------------------------------------------------------------------

/// @desc Absorb every player shot that crosses a ring's metal. Answers how
///       many were stopped.
///
///       **Called before `enemy_take_shots` and that ordering is the whole
///       mechanic**: a shot eaten here never reaches the boss behind it. Run
///       the other way round and a ring would be scenery with a spark effect.
///
///       The spark is put *on the band* rather than where the shot happened to
///       be when the frame ended, because at thirty-six pixels a frame those
///       are not the same place -- and a shot visibly dying a ring's width
///       past the ring is a shot the player thinks got through.
function ring_block_shots() {
    var _stopped = 0;
    for (var _s = global.pshot_n - 1; _s >= 0; _s--) {
        var _sh = global.pshots[_s];
        for (var _i = global.ring_n - 1; _i >= 0; _i--) {
            var _r = global.rings[_i];
            if (!ring_solid(_r)) continue;
            if (!ring_seg_crosses(_r, _sh.px, _sh.py, _sh.x, _sh.y)) {
                continue;
            }

            var _dir = point_direction(_r.x, _r.y, _sh.x, _sh.y);
            var _hx = ring_rim_x(_r, _dir);
            var _hy = ring_rim_y(_r, _dir);
            fx_spark(_hx, _hy, _dir + 180 + random_range(-50, 50),
                     random_range(1, 3), global.bullet_colour[_r.col], 10, 10);
            pshot_kill_at(_s);
            _stopped++;
            break;      // one shot is stopped by one ring
        }
    }
    return _stopped;
}

// ---------------------------------------------------------------------------
// Hurting
// ---------------------------------------------------------------------------

/// @desc How wide this ring's band kills, in pixels either side of the metal's
///       centre line.
///
///       Cold, a little under the drawn metal, on the genre's rule: a laser is
///       drawn wider than it kills because the glow either side is light
///       rather than beam, and a ring is drawn with a bevel and a chain on it
///       for the same reason. A player who believes the black of the cuff is
///       the hitbox is a player who is right.
///
///       Charged, the whole cuff -- see `RING_HOT_KILL_FRAC`. **It takes the
///       ring now and it did not use to**, because there is a cold width to
///       tell apart from a hot one; there is still no size argument, since
///       every ring is `RING_R`.
function ring_kill_half(_ring) {
    return RING_BAND_HALF
           * (ring_is_hot(_ring) ? RING_HOT_KILL_FRAC : RING_KILL_FRAC);
}

/// @desc Half the width the current kills at.
///
///       Split out for the reason `laser_hit_half` is: the drawing and the
///       collision have to be the same number, and the *jitter* on the drawn
///       bolt is bounded by it -- see `ring_draw_arcs`.
function ring_arc_half() {
    return RING_ARC_WID * 0.34;
}

/// @desc Where the arc between two rings runs. Answers `undefined` if it does
///       not.
function ring_arc_ends(_ring) {
    if (!ring_arc_live(_ring)) return undefined;
    return { x0: _ring.x, y0: _ring.y, x1: _ring.arc.x, y1: _ring.arc.y };
}

/// @desc Is this ring touching a circle -- by its metal or by its arc?
///
///       **The metal, not only a charged band.** `ring_solid` is the whole of
///       the condition: a ring that is still forming cannot hurt anybody and
///       neither can one that is leaving, which is the arrival telegraph a
///       bullet's delay mark is, one object up. Everything between those is
///       metal hanging in the air.
function ring_hits(_ring, _x, _y, _rad) {
    if (ring_solid(_ring)
        && ring_band_dist(_ring, _x, _y) < _rad + ring_kill_half(_ring)) {
        return true;
    }
    var _a = ring_arc_ends(_ring);
    if (_a != undefined
        && point_seg_dist(_x, _y, _a.x0, _a.y0, _a.x1, _a.y1)
           < _rad + ring_arc_half()) {
        return true;
    }
    return false;
}

/// @desc Is any ring touching this circle?
function ring_any_hit(_x, _y, _rad) {
    for (var _i = 0; _i < global.ring_n; _i++) {
        if (ring_hits(global.rings[_i], _x, _y, _rad)) return true;
    }
    return false;
}

/// @desc Count a graze against every live ring being ridden, and start its
///       cooldown. Answers how many paid.
///
///       **On a cooldown, exactly as a laser is.** A bullet passes and is
///       gone, so a flag is the whole truth about it; a band stands there for
///       as long as the ring does, and a flag would pay somebody who brushed
///       it for one frame what it pays somebody who rode round it. The band is
///       `ring_kill_half` plus `GRAZE_R`, off the same measurement the kill
///       uses, so what the player learnt from the bullets still holds here --
///       and it follows the kill from cold metal to charged without being
///       told, because it asks the same function.
function ring_graze(_x, _y, _rad) {
    var _n = 0;
    for (var _i = 0; _i < global.ring_n; _i++) {
        var _r = global.rings[_i];
        if (_r.graze_t > 0) continue;
        var _near = false;
        if (ring_solid(_r)) {
            _near = ring_band_dist(_r, _x, _y)
                    < _rad + ring_kill_half(_r) + GRAZE_R;
        }
        if (!_near) {
            var _a = ring_arc_ends(_r);
            if (_a != undefined) {
                _near = point_seg_dist(_x, _y, _a.x0, _a.y0, _a.x1, _a.y1)
                        < _rad + ring_arc_half() + GRAZE_R;
            }
        }
        if (!_near) continue;
        _r.graze_t = RING_GRAZE_CD;
        _n++;
    }
    return _n;
}

// ---------------------------------------------------------------------------
// What a ring fires
//
// **A ring's `act` is a boss attack one level down**, with the same signature
// and the same habits: a function of the frame count, written as a `switch` on
// `_t mod period`. What is named here is only the two things that turned out
// to be awkward to write by hand every time -- a volley off the rim, and a
// beam through the middle.
// ---------------------------------------------------------------------------

/// @desc `_n` bullets evenly round the band, each travelling straight out.
///
///       **Fired from the metal rather than from the centre**, which is the
///       whole visual: the ring is what is shooting, so the bullets have to
///       leave it rather than pass through it. Firing them from the middle
///       looks identical for one frame and then wrong for ever after, because
///       the delay marks appear inside the hole.
function ring_fire_rim(_ring, _n, _spd, _dir0, _shape, _col,
                       _delay = BULLET_DELAY_DEFAULT) {
    for (var _i = 0; _i < _n; _i++) {
        var _a = _dir0 + _i * (360 / _n);
        fire(ring_rim_at_x(_ring, _a, _delay),
             ring_rim_at_y(_ring, _a, _delay), _spd, _a,
             _shape, _col, _delay);
    }
}

/// @desc The same, but every bullet runs *round* the band rather than out of
///       it -- a tangential volley, which is what a ring that has been spun up
///       throws off.
function ring_fire_tangent(_ring, _n, _spd, _dir0, _shape, _col, _sign = 1,
                           _delay = BULLET_DELAY_DEFAULT) {
    for (var _i = 0; _i < _n; _i++) {
        var _a = _dir0 + _i * (360 / _n);
        fire(ring_rim_at_x(_ring, _a, _delay),
             ring_rim_at_y(_ring, _a, _delay), _spd,
             _a + 90 * _sign, _shape, _col, _delay);
    }
}

/// @desc A beam through the ring's middle, which follows the ring.
///
///       Anchored at the centre and not at the rim, because that is what the
///       hole is for: a ring with a beam coming out of it is a portal, and a
///       ring with a beam coming off its edge is a gun somebody bolted a hoop
///       to.
function ring_beam(_ring, _dir, _len, _wid, _col, _warn, _hot, _fade = 18) {
    var _l = laser_beam(_ring.x, _ring.y, _dir, _len, _wid, _col, _warn, _hot,
                        _fade);
    if (_l != undefined) _l.src = _ring;
    return _l;
}

// ---------------------------------------------------------------------------
// Drawing
//
// **Rings are drawn before the bullets and that is what makes an opaque object
// this size affordable.** The near parallax layer is capped at `BG_NEAR_ALPHA`
// and kept out of the middle of the screen because it draws *over* live
// danmaku; a ring draws under all of it, so no arrangement of rings can hide a
// bullet. What they can hide is the boss, which is the point.
// ---------------------------------------------------------------------------

/// @desc How bright and how big a ring is drawn this frame. Split out for the
///       reason `laser_visual` is: the shape of a ring's life is the part a
///       suite can check.
function ring_visual(_ring) {
    if (_ring.fade >= 0) {
        var _f = _ring.fade / max(1, RING_FADE);
        return { scale: 1 + (1 - _f) * 0.14, alpha: _f, charge: 0 };
    }
    // Charge: a build through the warning, full while hot, and it is a
    // *pulse* rather than a ramp, because a steady brightening is the one
    // signal the periphery is built to stop noticing.
    var _c = 0;
    if (_ring.warn > 0 && _ring.hot > 0) {
        var _p = 1 - _ring.warn / max(1, RING_WARN);
        _c = _p * (0.45 + 0.55 * abs(dsin(_ring.warn * 9)));
    } else if (_ring.hot > 0) {
        _c = 1;
    }
    if (_ring.form > 0) {
        var _in = 1 - _ring.form / max(1, RING_FORM);
        return { scale: 0.72 + 0.28 * _in, alpha: _in * 0.85, charge: _c };
    }
    return { scale: 1, alpha: 1, charge: _c };
}

function ring_draw() {
    var _half = sprite_get_width(spr_ring) * 0.5 * RING_SPR_LINE;

    for (var _i = 0; _i < global.ring_n; _i++) {
        var _r = global.rings[_i];
        var _v = ring_visual(_r);
        if (_v.alpha <= 0.01) continue;
        var _col = global.bullet_colour[_r.col];
        var _k = (RING_R * _v.scale) / _half;

        draw_sprite_ext(spr_ring, 0, _r.x, _r.y, _k, _k, _r.ang, c_white,
                        _v.alpha);

        // The charge, additive over the metal, in the attack's own hue -- so
        // the marking is what lights up and the black cuff underneath does
        // not move. See `make_rings.py` on why the sprite's colour is baked.
        if (_v.charge > 0.01) {
            gpu_set_blendmode(bm_add);
            draw_sprite_ext(spr_ring, 0, _r.x, _r.y, _k, _k, _r.ang, _col,
                            _v.alpha * _v.charge * 0.9);
            var _gs = (RING_R * 2.8) / sprite_get_width(spr_fx_bloom);
            draw_sprite_ext(spr_fx_bloom, 0, _r.x, _r.y, _gs, _gs, 0, _col,
                            _v.alpha * _v.charge * 0.10);
            gpu_set_blendmode(bm_normal);
        }
    }

    ring_draw_arcs();
}

/// @desc The current strung between two rings.
///
///       **Drawn as a jagged run of bars off the same segment the collision
///       reads, and the jitter is bounded by the width that kills.** A bolt
///       has to wander or it is a rod, and every pixel it wanders is a pixel
///       where the picture and the hitbox disagree -- so the wander is capped
///       under `ring_arc_half`, which means the drawn line never leaves the
///       lethal band it is drawn to represent. The first version let it stray
///       twenty-six pixels off a segment that kills within nine, on a player
///       whose hitbox is four: a bolt that visibly missed and killed anyway,
///       which is the least readable death this genre has.
///
///       The wander is a hash of the node index, the frame and the ring's own
///       serial rather than `random`, so one arc is one bolt however many
///       times a frame it is drawn.
function ring_draw_arcs() {
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.ring_n; _i++) {
        var _r = global.rings[_i];
        var _a = ring_arc_ends(_r);
        if (_a == undefined) continue;

        var _col = global.bullet_colour[_r.col];
        var _len = point_distance(_a.x0, _a.y0, _a.x1, _a.y1);
        if (_len < 1) continue;
        var _dir = point_direction(_a.x0, _a.y0, _a.x1, _a.y1);
        var _nx = lengthdir_x(1, _dir + 90);
        var _ny = lengthdir_y(1, _dir + 90);
        // Inside the band that kills, so a bolt that visibly misses did.
        var _amp = min(ring_arc_half() * 0.9, _len * 0.03);

        var _px = _a.x0;
        var _py = _a.y0;
        for (var _k = 1; _k <= RING_ARC_NODES; _k++) {
            var _t = _k / RING_ARC_NODES;
            // Zero at both ends, so the bolt is pinned to the two rings.
            var _w = dsin(_t * 180) * _amp
                     * dsin(_k * 137 + _r.t * 43 + _r.gen * 61);
            var _qx = _a.x0 + (_a.x1 - _a.x0) * _t + _nx * _w;
            var _qy = _a.y0 + (_a.y1 - _a.y0) * _t + _ny * _w;
            var _sl = point_distance(_px, _py, _qx, _qy);
            if (_sl > 0.01) {
                laser_draw_bar(_px, _py, point_direction(_px, _py, _qx, _qy),
                               _sl + 1.5, RING_ARC_WID, _col, 0.9);
            }
            _px = _qx;
            _py = _qy;
        }
    }
    gpu_set_blendmode(bm_normal);
}
