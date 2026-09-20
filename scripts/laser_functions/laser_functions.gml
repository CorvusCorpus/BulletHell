/// @desc Lasers: the moving ray, the telegraphed beam, and the curved trail.
///
/// All three share a pool, because there are never many of them and because
/// the thing they have in common -- a warn/fire/fade life, a colour, a width,
/// and a hit test against a *segment* rather than a point -- is most of what
/// each one is.
///
/// **A beam always telegraphs, and the telegraph is not decoration.** A wall
/// of light that appears on one frame across half the screen is not a pattern,
/// it is a coin toss; the warning line is what turns it into a thing the
/// player reads and answers. It is the same rule `BULLET_DELAY_DEFAULT` states
/// for bullets, and it is the reason `laser_beam` takes its warn time as an
/// ordinary argument rather than as an option: writing a beam with no warning
/// should look wrong on the page.
///
/// **A curved laser is a trail of where its head has been.** That is the whole
/// trick, and it is why it looked hard: the head is an ordinary bullet with an
/// angular velocity, and the laser is the last `CURVE_NODES` positions it
/// occupied. Nothing curves; a straight thing moves and its history is the
/// curve. Collision is the same segment test, run down the trail.

function laser_init() {
    global.lasers = [];
    global.laser_n = 0;
}

function laser_blank() {
    return {
        kind: LaserKind.Beam,
        phase: LaserPhase.Warn,
        t: 0,
        x: 0, y: 0, dir: 0,
        len: 100, wid: 20, spd: 0, turn: 0,
        col: BCOL_BONE,
        warn: 60, hot: 120, fade: 20,
        src: undefined,          // a struct with x/y the origin follows
        // **A world point the beam stays trained on**, or `undefined` for one
        // that keeps the heading it was cast with.
        //
        // The field beside this used to be `aim_src`, a flag documented as
        // "whether `dir` follows it too" -- declared, blanked, commented, and
        // read by nothing anywhere in the project. Which is the `GAME_ERROR`
        // shape exactly: what it describes is a real and wanted behaviour, and
        // the description was the whole of it.
        //
        // **Following and aiming are different questions and a beam mounted on
        // something that moves needs both answered.** `src` alone translates
        // the line, so a beam aimed at a spot slides off that spot as its
        // caster travels -- which is right for a swept wall and wrong for
        // anything that was aimed. Trained, the line pivots about the point
        // instead: the root stays on the caster, the spot stays covered, and
        // what sweeps is everywhere else.
        look: undefined,
        nx: [], ny: [], node_n: 0,
        // **A laser is grazed on a cooldown where a bullet is grazed once.**
        // A bullet passes and is gone, so a flag is the whole truth about it;
        // a laser stands there for two seconds, and a flag would pay a player
        // who brushed it for one frame exactly what it pays one who rode the
        // length of it.
        graze_t: 0, graze_cd: LASER_GRAZE_CD,
        resist: false,           // bomb-proof, as a bullet may be
        alive: true,
    };
}

function laser_alloc() {
    if (global.laser_n >= LASER_MAX) return undefined;
    var _i = global.laser_n;
    if (_i >= array_length(global.lasers)) {
        array_push(global.lasers, laser_blank());
    }
    global.laser_n = _i + 1;
    var _l = global.lasers[_i];
    _l.phase = LaserPhase.Warn;
    _l.t = 0;
    _l.spd = 0;
    _l.turn = 0;
    _l.src = undefined;
    _l.look = undefined;
    _l.node_n = 0;
    _l.graze_t = 0;
    _l.graze_cd = LASER_GRAZE_CD;
    _l.resist = false;
    _l.alive = true;
    return _l;
}

function laser_kill_at(_i) {
    var _last = global.laser_n - 1;
    if (_i != _last) {
        var _tmp = global.lasers[_i];
        global.lasers[_i] = global.lasers[_last];
        global.lasers[_last] = _tmp;
    }
    global.laser_n = _last;
}

function laser_count() {
    return global.laser_n;
}

// ---------------------------------------------------------------------------
// The three shapes
// ---------------------------------------------------------------------------

/// @desc An anchored beam that warns, fires, then fades.
/// @param {real} _warn  frames of warning line. **Never pass 0.**
function laser_beam(_x, _y, _dir, _len, _wid, _col, _warn, _hot, _fade = 18) {
    var _l = laser_alloc();
    if (_l == undefined) return undefined;
    _l.kind = LaserKind.Beam;
    _l.x = _x; _l.y = _y; _l.dir = _dir;
    _l.len = _len; _l.wid = _wid;
    _l.col = _col;
    _l.warn = _warn; _l.hot = _hot; _l.fade = _fade;
    // **The charge sounds on the warning, not on the beam.** The telegraph is
    // the whole of what makes a wall of light fair, and a cue that waited for
    // the beam would be announcing it at the moment it is already lethal --
    // which is the audible version of `_warn` being zero.
    sfx(Sfx.LaserCharge);
    return _l;
}

/// @desc A bar of light that travels. Collides like a very long bullet.
///       It has no warning phase -- it is a projectile rather than a wall, so
///       what makes it fair is that it can be seen coming.
function laser_ray(_x, _y, _dir, _spd, _len, _wid, _col, _life) {
    var _l = laser_alloc();
    if (_l == undefined) return undefined;
    _l.kind = LaserKind.Ray;
    _l.phase = LaserPhase.Fire;
    _l.x = _x; _l.y = _y; _l.dir = _dir;
    _l.spd = _spd; _l.len = _len; _l.wid = _wid;
    _l.col = _col;
    _l.warn = 0; _l.hot = _life; _l.fade = 14;
    // A ray has no warning phase -- it is a projectile rather than a wall, so
    // it fires the moment it exists.
    sfx(Sfx.LaserFire);
    return _l;
}

/// @desc A trail laid down by a head that moves at `_spd` and turns by
///       `_turn` degrees a frame. `_life` is how long the head lives; the
///       trail then drains away behind it.
function laser_curve(_x, _y, _dir, _spd, _turn, _wid, _col, _life) {
    var _l = laser_alloc();
    if (_l == undefined) return undefined;
    _l.kind = LaserKind.Curve;
    _l.phase = LaserPhase.Fire;
    _l.x = _x; _l.y = _y; _l.dir = _dir;
    _l.spd = _spd; _l.turn = _turn; _l.wid = _wid;
    _l.col = _col;
    _l.warn = 0; _l.hot = _life; _l.fade = CURVE_NODES;
    _l.node_n = 0;
    sfx(Sfx.LaserFire);
    return _l;
}

// ---------------------------------------------------------------------------
// The step
// ---------------------------------------------------------------------------

function laser_step() {
    for (var _i = global.laser_n - 1; _i >= 0; _i--) {
        var _l = global.lasers[_i];

        // A beam cast by a boss follows the boss, so a boss that drifts drags
        // its beams with it -- which is what makes a swept wall read as
        // something the boss is *doing* rather than as scenery.
        if (_l.src != undefined && _l.kind != LaserKind.Curve) {
            _l.x = _l.src.x;
            _l.y = _l.src.y;
        }

        _l.t++;
        if (_l.graze_t > 0) _l.graze_t--;
        switch (_l.kind) {
            case LaserKind.Beam: laser_step_beam(_l); break;
            case LaserKind.Ray:  laser_step_ray(_l);  break;
            case LaserKind.Curve: laser_step_curve(_l); break;
        }

        if (_l.phase == LaserPhase.Done) {
            laser_kill_at(_i);
        }
    }
}

function laser_step_beam(_l) {
    // **A trained beam re-aims and does not turn**, which is the one place the
    // two could fight: a rate and a target are two ways of saying where the
    // line points, and a beam carrying both would drift off its point by
    // exactly `turn` a frame with nothing to say why.
    if (_l.look != undefined) {
        _l.dir = point_direction(_l.x, _l.y, _l.look.x, _l.look.y);
    } else {
        _l.dir += _l.turn;
    }
    if (_l.phase == LaserPhase.Warn && _l.t >= _l.warn) {
        _l.phase = LaserPhase.Fire;
        _l.t = 0;
        fx_flash_at(_l.x, _l.y, global.bullet_colour[_l.col], 0.35);
        sfx(Sfx.LaserFire);
    } else if (_l.phase == LaserPhase.Fire && _l.t >= _l.hot) {
        _l.phase = LaserPhase.Fade;
        _l.t = 0;
    } else if (_l.phase == LaserPhase.Fade && _l.t >= _l.fade) {
        _l.phase = LaserPhase.Done;
    }
}

function laser_step_ray(_l) {
    _l.dir += _l.turn;
    _l.x += lengthdir_x(_l.spd, _l.dir);
    _l.y += lengthdir_y(_l.spd, _l.dir);

    if (_l.phase == LaserPhase.Fire && _l.t >= _l.hot) {
        _l.phase = LaserPhase.Fade;
        _l.t = 0;
    } else if (_l.phase == LaserPhase.Fade && _l.t >= _l.fade) {
        _l.phase = LaserPhase.Done;
    }

    // The tail is what has to have left, not the head: a ray whose head is off
    // the left of the screen is still lying across the middle of it.
    var _tx = _l.x - lengthdir_x(_l.len, _l.dir);
    var _ty = _l.y - lengthdir_y(_l.len, _l.dir);
    if (min(_l.x, _tx) > FIELD_X1 + CULL_MARGIN
        || max(_l.x, _tx) < FIELD_X0 - CULL_MARGIN
        || min(_l.y, _ty) > FIELD_Y1 + CULL_MARGIN
        || max(_l.y, _ty) < FIELD_Y0 - CULL_MARGIN) {
        _l.phase = LaserPhase.Done;
    }
}

function laser_step_curve(_l) {
    if (_l.phase == LaserPhase.Fire) {
        _l.dir += _l.turn;
        _l.x += lengthdir_x(_l.spd, _l.dir);
        _l.y += lengthdir_y(_l.spd, _l.dir);
        curve_push(_l, _l.x, _l.y);
        if (_l.t >= _l.hot) {
            _l.phase = LaserPhase.Fade;
            _l.t = 0;
        }
    } else {
        // **The head stops and the tail keeps going.** Draining a node a frame
        // is what makes a spent curve look like light running out of a wire
        // rather than a shape being switched off; and because collision reads
        // the same node list, the part that has drained is also the part that
        // has stopped being dangerous.
        curve_drop_oldest(_l);
        if (_l.node_n <= 1) {
            _l.phase = LaserPhase.Done;
        }
    }
}

/// @desc Push a node onto the trail, dropping the oldest once it is full.
///
///       Kept as two parallel arrays of reals rather than an array of structs,
///       because a curve is walked twice a frame -- once to draw and once to
///       collide -- and sixty-four struct dereferences per laser per pass is
///       the one place in this file where that would show.
function curve_push(_l, _x, _y) {
    if (_l.node_n < CURVE_NODES) {
        _l.nx[_l.node_n] = _x;
        _l.ny[_l.node_n] = _y;
        _l.node_n++;
        return;
    }
    for (var _i = 0; _i < CURVE_NODES - 1; _i++) {
        _l.nx[_i] = _l.nx[_i + 1];
        _l.ny[_i] = _l.ny[_i + 1];
    }
    _l.nx[CURVE_NODES - 1] = _x;
    _l.ny[CURVE_NODES - 1] = _y;
}

function curve_drop_oldest(_l) {
    if (_l.node_n <= 0) return;
    for (var _i = 0; _i < _l.node_n - 1; _i++) {
        _l.nx[_i] = _l.nx[_i + 1];
        _l.ny[_i] = _l.ny[_i + 1];
    }
    _l.node_n--;
}

// ---------------------------------------------------------------------------
// Collision
// ---------------------------------------------------------------------------

/// @desc Is a laser dangerous this frame? **Only while it is firing.** A
///       warning line that could kill would make the telegraph a lie, and a
///       fading one that could kill would punish the player for believing it
///       was over.
function laser_is_hot(_l) {
    return _l.phase == LaserPhase.Fire;
}

/// @desc How far a point is from a laser's spine.
///
///       **Split out because a hit and a graze are the same measurement at two
///       radii**, and a laser that killed along one line and paid along a
///       slightly different one would be the kind of disagreement no
///       screenshot and no assertion about either half could ever show.
function laser_spine_dist(_l, _x, _y) {
    if (_l.kind == LaserKind.Curve) {
        var _best = 99999;
        for (var _i = 0; _i < _l.node_n - 1; _i++) {
            _best = min(_best, point_seg_dist(_x, _y, _l.nx[_i], _l.ny[_i],
                                              _l.nx[_i + 1], _l.ny[_i + 1]));
        }
        return _best;
    }

    // A ray's segment runs backwards from its head; a beam's runs forwards
    // from its anchor.
    var _x1, _y1;
    if (_l.kind == LaserKind.Ray) {
        _x1 = _l.x - lengthdir_x(_l.len, _l.dir);
        _y1 = _l.y - lengthdir_y(_l.len, _l.dir);
    } else {
        _x1 = _l.x + lengthdir_x(_l.len, _l.dir);
        _y1 = _l.y + lengthdir_y(_l.len, _l.dir);
    }
    return point_seg_dist(_x, _y, _l.x, _l.y, _x1, _y1);
}

/// @desc Half the width a laser actually kills at.
///
///       A little under the drawn one. Every laser in this genre is drawn
///       wider than it kills, because the glow either side is light rather
///       than beam, and a player who believes the bright core is the hitbox is
///       a player who is right.
function laser_hit_half(_l) {
    return _l.wid * 0.34;
}

/// @desc Does this laser touch a circle at (`_x`, `_y`)?
function laser_hits(_l, _x, _y, _rad) {
    if (!laser_is_hot(_l)) return false;
    return laser_spine_dist(_l, _x, _y) < _rad + laser_hit_half(_l);
}

/// @desc Is any laser touching this circle?
function laser_any_hit(_x, _y, _rad) {
    for (var _i = 0; _i < global.laser_n; _i++) {
        if (laser_hits(global.lasers[_i], _x, _y, _rad)) return true;
    }
    return false;
}

/// @desc Count a graze against every laser being ridden, and start its
///       cooldown. Returns how many paid this frame.
///
///       **Only a firing laser can be grazed.** A warning line is not
///       dangerous, so standing in one is not nerve -- paying for it would be
///       paying the player for reading the telegraph correctly and then
///       ignoring what it said. The same goes for a fading one: the danger is
///       over, and so is the reward.
///
///       The band is the same one `laser_hits` kills in, plus the graze
///       radius, so the distance between being paid and being killed is
///       exactly `GRAZE_R` -- which is the deal a bullet offers and the deal
///       the player has already learnt.
function laser_graze(_x, _y, _rad) {
    var _count = 0;
    for (var _i = 0; _i < global.laser_n; _i++) {
        var _l = global.lasers[_i];
        if (!laser_is_hot(_l) || _l.graze_t > 0) continue;
        if (laser_spine_dist(_l, _x, _y) < _rad + laser_hit_half(_l) + GRAZE_R) {
            _l.graze_t = _l.graze_cd;
            _count++;
        }
    }
    return _count;
}

/// @desc Clear every laser. A phase change does this; so does a bomb, which
///       passes `true` because `resist` means "a bomb cannot take this" and a
///       phase change is not a bomb. Same split as `bullet_clear_circle`.
function laser_clear_all(_spare_resist = false) {
    if (!_spare_resist) {
        var _n = global.laser_n;
        global.laser_n = 0;
        return _n;
    }
    var _gone = 0;
    for (var _i = global.laser_n - 1; _i >= 0; _i--) {
        if (global.lasers[_i].resist) continue;
        laser_kill_at(_i);
        _gone++;
    }
    return _gone;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc How wide and how bright a laser is drawn this frame.
///       Split out because the *shape* of a laser's life -- a thin warning
///       that swells to full and then blooms out as it dies -- is the same for
///       all three kinds, and it is the part a suite can check.
function laser_visual(_l) {
    switch (_l.phase) {
        case LaserPhase.Warn:
            // A hairline that breathes. It stays a hairline right up to the
            // last few frames, then flares -- so the tell is "it got brighter"
            // rather than "it got wider", and a player cannot mistake the
            // warning for the beam.
            var _p = _l.t / max(1, _l.warn);
            var _imminent = max(0, (_p - 0.82) / 0.18);
            return {
                wid: _l.wid * (0.10 + 0.30 * _imminent),
                alpha: 0.34 + 0.30 * _imminent + 0.10 * dsin(_l.t * 14),
            };

        case LaserPhase.Fire:
            // Snaps to full over three frames, so the beam arrives rather than
            // grows -- the growing already happened, in the warning.
            var _in = min(1, _l.t / 3);
            return { wid: _l.wid * _in, alpha: 0.95 };

        case LaserPhase.Fade:
            var _f = 1 - _l.t / max(1, _l.fade);
            return { wid: _l.wid * (1 + (1 - _f) * 0.8), alpha: _f * 0.8 };
    }
    return { wid: 0, alpha: 0 };
}

function laser_draw() {
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.laser_n; _i++) {
        var _l = global.lasers[_i];
        var _v = laser_visual(_l);
        if (_v.alpha <= 0.01) continue;
        var _col = global.bullet_colour[_l.col];

        if (_l.kind == LaserKind.Curve) {
            laser_draw_curve(_l, _v, _col);
        } else {
            var _len = _l.len;
            var _x0 = _l.x;
            var _y0 = _l.y;
            if (_l.kind == LaserKind.Ray) {
                // Drawn from the tail forward, so the sprite's own bright head
                // lands on the ray's head.
                _x0 = _l.x - lengthdir_x(_len, _l.dir);
                _y0 = _l.y - lengthdir_y(_len, _l.dir);
            }
            laser_draw_bar(_x0, _y0, _l.dir, _len, _v.wid, _col, _v.alpha);

            // ...and the light it is coming out of. Beams only: a ray and a
            // curve are drawn from a travelling head that already carries one,
            // and neither keeps the point it was fired from. See
            // `laser_draw_muzzle`.
            if (_l.kind == LaserKind.Beam) laser_draw_muzzle(_l, _col);
        }
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc How big and how bright the light at a beam's root is this frame.
///
///       **Split out for `laser_visual`'s reason**: the shape of a muzzle's
///       life is the part a suite can check, and it has to be checkable
///       beside the bar's, because the one thing a muzzle may not do is
///       outlive the beam it belongs to.
///
///       **Everything is a multiple of the beam's own width**, so a hairline
///       gets a spark and a wall gets a furnace, and nobody has to remember to
///       pick a size. It is the property the ring's band and the meters' glass
///       are built on: the picture is derived from the thing rather than
///       tuned to agree with it.
function laser_muzzle(_l) {
    switch (_l.phase) {
        case LaserPhase.Warn:
            // **A gather, and it is the half of the telegraph the bar cannot
            // give.** A warning line says where the beam will lie; it does not
            // say which end of it is the muzzle, and on an aimed beam that is
            // the thing the player wants -- a line through you from a ring
            // above is answered differently than the same line from beside
            // you. It swells toward the shot rather than holding, on the
            // warning's own curve.
            var _p = _l.t / max(1, _l.warn);
            return { r: _l.wid * (0.85 + 1.70 * _p * _p),
                     alpha: 0.28 + 0.46 * _p * _p };

        case LaserPhase.Fire:
            // Full, with a flicker on it -- a light source that holds
            // perfectly still reads as a decal stuck to the scenery.
            return { r: _l.wid * (2.55 + 0.22 * dsin(_l.t * 23)),
                     alpha: 0.95 };

        case LaserPhase.Fade:
            // Blooms out as it dies, exactly as the bar does, so the two go
            // together rather than one outlasting the other.
            var _f = 1 - _l.t / max(1, _l.fade);
            return { r: _l.wid * (2.55 + (1 - _f) * 2.0), alpha: _f * 0.7 };
    }
    return { r: 0, alpha: 0 };
}

/// @desc The light at a beam's root.
///
///       **A beam was the one kind of laser with a bare end.** A ray is drawn
///       from its tail forward so the sprite's own bright head lands on the
///       head, and a curve caps its head with `spr_laser_node`; both of those
///       are the *live* end of a thing that travels. A beam does not travel,
///       so its root sits still in one place for its whole life -- and with
///       nothing drawn there it is a line that begins in mid-air. Reported
///       against Mika's bolts, where the root sits inside a ring and plainly
///       ought to be burning.
///
///       Three layers, and the first two are the bullets' own rule: a soft
///       bloom carrying the hue and a smaller white one inside it, because
///       white-inside-colour is what makes light read as light at any size.
///       The third is the house's four-pointed spark, and **two of its points
///       run down the beam's own axis** -- which is what a flare on a real
///       source does, and what keeps the muzzle attached to the barrel rather
///       than being a glow that happens to be nearby.
///
///       Additive, like everything else in this pass, so it cannot hide a
///       bullet at any size or any alpha.
function laser_draw_muzzle(_l, _col) {
    var _m = laser_muzzle(_l);
    if (_m.alpha <= 0.01 || _m.r <= 0.5) return;

    var _bw = sprite_get_width(spr_fx_bloom);
    var _bh = sprite_get_height(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _l.x, _l.y, _m.r / _bw, _m.r / _bh, 0,
                    _col, _m.alpha * 0.70);
    var _hot = _m.r * 0.40;
    draw_sprite_ext(spr_fx_bloom, 0, _l.x, _l.y, _hot / _bw, _hot / _bh, 0,
                    c_white, _m.alpha * 0.85);

    var _sw = sprite_get_width(spr_fx_spark);
    var _sh = sprite_get_height(spr_fx_spark);
    var _arm = _m.r * 1.35;
    var _thk = max(1, _m.r * 0.11);
    for (var _k = 0; _k < 4; _k++) {
        draw_sprite_ext(spr_fx_spark, 0, _l.x, _l.y, _arm / _sw, _thk / _sh,
                        _l.dir + _k * 90, _col, _m.alpha * 0.5);
    }
}

/// @desc One straight bar of light, from (`_x`, `_y`) along `_dir`.
///       Two passes: a wide soft body carrying the hue, and a narrow white
///       core over it. **The core is what makes it read as a laser** -- one
///       pass in the hue alone is a coloured stripe, and the same white-inside-
///       colour rule the bullets are built on applies here for the same reason.
function laser_draw_bar(_x, _y, _dir, _len, _wid, _col, _alpha) {
    var _sw = sprite_get_width(spr_laser_body);
    var _sh = sprite_get_height(spr_laser_body);
    draw_sprite_ext(spr_laser_body, 0, _x, _y,
                    _len / _sw, _wid / _sh, _dir, _col, _alpha * 0.85);
    draw_sprite_ext(spr_laser_body, 0, _x, _y,
                    _len / _sw, max(1, _wid * 0.34) / _sh, _dir,
                    c_white, _alpha * 0.8);
}

/// @desc A curve, drawn as a run of bars between its nodes.
///
///       **Segments, not blobs at the nodes.** Blobs were the first answer and
///       they were chosen over a textured triangle strip for good reasons -- a
///       strip needs the sprite's UVs off the texture page, a `pr_trianglestrip`
///       built by hand and a mitre at every node, where blobs overlap into a
///       ribbon for free. The trouble is the words "overlap into": that only
///       holds while the blob is wider than the gap between two of them, and
///       the gap between two nodes is exactly the head's speed, because the
///       trail records one node a frame.
///
///       When the lashes in `No Mere Pawn` were sped up from 7.5 to 12 pixels
///       a frame to suit a wider field, the ribbon came apart into a string of
///       pearls. The hue blobs were still overlapping; it was the *white core*
///       drawn inside each of them -- the brightest part, and so the part the
///       eye follows -- that had become narrower than the spacing.
///
///       A bar from each node to the next cannot come apart at any speed,
///       because it is defined by the gap rather than in spite of it. It is
///       the same `laser_draw_bar` a beam uses, so a curve and a beam are now
///       made of the same light; and it is drawn along precisely the segments
///       `laser_hits` tests, so the picture and the hitbox are the same shape
///       by construction rather than by agreement.
function laser_draw_curve(_l, _v, _col) {
    for (var _i = 0; _i < _l.node_n - 1; _i++) {
        // The head is brightest and the tail thins out, which is what says
        // which end is which -- and which end is about to move.
        var _t = (_l.node_n <= 2) ? 1 : (_i / (_l.node_n - 2));
        var _x0 = _l.nx[_i];
        var _y0 = _l.ny[_i];
        var _len = point_distance(_x0, _y0, _l.nx[_i + 1], _l.ny[_i + 1]);
        if (_len < 0.01) continue;
        var _dir = point_direction(_x0, _y0, _l.nx[_i + 1], _l.ny[_i + 1]);
        // A pixel of overlap, so consecutive bars meet rather than abut --
        // additive blending makes the join invisible and a hairline of
        // background between two segments would not be.
        laser_draw_bar(_x0, _y0, _dir, _len + 1.5,
                       _v.wid * (0.45 + 0.55 * _t), _col,
                       _v.alpha * (0.35 + 0.65 * _t));
    }

    // A cap on the head, which is the one place a bar has a square end that
    // shows -- and which is also where a lash should look hottest.
    if (_l.node_n > 0) {
        var _n = _l.node_n - 1;
        var _cs = _v.wid * 1.15 / sprite_get_width(spr_laser_node);
        draw_sprite_ext(spr_laser_node, 0, _l.nx[_n], _l.ny[_n], _cs, _cs, 0,
                        _col, _v.alpha);
        draw_sprite_ext(spr_laser_node, 0, _l.nx[_n], _l.ny[_n],
                        _cs * 0.5, _cs * 0.5, 0, c_white, _v.alpha);
    }
}
