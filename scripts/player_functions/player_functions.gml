/// @desc Szuix: movement, focus, the shot, the special, and getting hit.
///
/// **The player is a struct, not an object**, and `player_step` takes its
/// input as a struct rather than reading the keyboard. Both are for the same
/// reason: a suite has to be able to put a player at a coordinate, hand it
/// eight frames of "hold left and shoot", and assert on where it ended up and
/// what it fired. A player that read `keyboard_check` could only be tested by
/// somebody holding a key down.
///
/// `input_gather` is the one function here that touches a device, and it is
/// called from `obj_game`'s Step -- which is where real time and real input
/// legitimately enter the game.

/// @desc A fresh player at the bottom-centre of the field.
function player_new() {
    return {
        x: FIELD_CX,
        y: FIELD_Y1 - 200,
        hp: HP_MAX,
        mp: 0,
        focus: false,
        alive: true,

        iframe: 0,        // > 0 means untouchable, and flickering
        bomb_t: 0,        // > 0 means the special is going off
        bomb_x: 0,        // where it was cast; the sweep grows from there
        bomb_y: 0,
        shot_t: 0,        // frames until the next volley

        // **The seals, allocated once and never again.** The same bargain
        // every other pool in the game makes: a bomb reuses these structs, so
        // casting one allocates nothing. `live` is the whole of what says
        // which are in the air -- see `player_seals_step`.
        seals: player_seals_new(),

        // How long the grace now running was when it started, so the dial
        // round him has something to be a fraction *of*. See
        // `player_draw_grace`.
        grace_max: 1,
        grace_show: 0,    // the dial's own fade in and out; purely visual

        card_t: 0,        // > 0 while his close-up is on screen
        fire_glow: 0,     // eases up while the shot is held: the muzzles

        // Purely visual. `lean` is where the sprite is banking, and it eases
        // toward where the player is actually going, so a hard left-right
        // reversal reads as a turn rather than as a teleport.
        lean: 0,
        anim: 0,
        entry: 0,         // > 0 while flying in at the start of a stage

        // **Nothing in play ever sets this.** It is the harness's flag: a
        // posed player does not dodge, so it cannot be asked to survive.
        //
        // It is not a convenience. A hit sweeps a 190-pixel circle of bullets
        // off the field -- see `player_hit`, and the reason is sound -- so a
        // posed player being hit does not merely spend health, it *punches a
        // hole in the thing being photographed*. Every picture of `Demon
        // Sealing Hex` taken at less than full life had a bite out of the ward
        // whose whole claim is where its gaps are, and nothing said so: the
        // seal is redrawn twice a cycle, so the evidence was gone by the next
        // movement. What finally reported it was a scene running long enough
        // for the fourth hit to kill the player outright.
        //
        // Distinct from `iframe` rather than expressed with it, because
        // `iframe` *flickers* -- it is the game telling the player they are
        // briefly safe, and a screenshot of a half-transparent Szuix is a
        // screenshot of a state nobody is posing for.
        untouchable: false,

        graze_n: 0,
        hit_n: 0,
        bomb_n: 0,
    };
}

/// @desc The bomb's wisps, one struct each, made once with the player.
function player_seals_new() {
    var _a = [];
    for (var _i = 0; _i < BOMB_SEALS; _i++) {
        array_push(_a, { live: false, x: 0, y: 0, px: 0, py: 0,
                         dir: 0, spd: 0, t: 0, k: _i });
    }
    return _a;
}

/// @desc Read the devices. The only place in `scripts/` that does.
function input_gather() {
    return {
        left:  keyboard_check(vk_left),
        right: keyboard_check(vk_right),
        up:    keyboard_check(vk_up),
        down:  keyboard_check(vk_down),
        shoot: keyboard_check(ord("Z")),
        bomb:  keyboard_check_pressed(ord("X")),
        focus: keyboard_check(vk_shift),
    };
}

/// @desc Input with nothing held. What a suite hands a player it is not
///       driving, and what the game hands it during the intro fly-in.
function input_idle() {
    return { left: false, right: false, up: false, down: false,
             shoot: false, bomb: false, focus: false };
}

/// @desc Where the player is standing across the field: -1 at the left wall,
///       0 on the centre line, +1 at the right.
///
///       **A fraction rather than a coordinate**, because the two things that
///       read it -- the grove's camera today, and whatever wants a "which
///       side is he on" later -- want the answer in the field's own terms and
///       not in pixels. It survived the field becoming a rectangle once
///       already; this is the same seam one level up. See `GROVE_LEAN`.
function player_field_aim(_p) {
    return clamp((_p.x - FIELD_CX) / (FIELD_W / 2), -1, 1);
}

/// @desc Is the player untouchable right now?
function player_invulnerable(_p) {
    return _p.untouchable || _p.iframe > 0 || _p.bomb_t > 0 || _p.entry > 0;
}

/// @desc Frames of grace left, whichever kind is running.
///
///       **The longer of the two, not the sum**, because they overlap: a bomb
///       cast two frames after a hit does not give the player four and a half
///       seconds, it gives them whichever runs out last.
function player_grace_left(_p) {
    return max(_p.iframe, _p.bomb_t);
}

/// @desc Start a grace of `_frames`, keeping whatever is already running if it
///       is longer. The dial reads `grace_max`, so it has to be set wherever
///       the grace itself is.
function player_grace_begin(_p, _frames) {
    _p.grace_max = max(player_grace_left(_p), _frames);
}

/// @desc One frame. `_g` is the controller, for the things a player does that
///       the run has to know about -- banking a tally, starting a bomb.
function player_step(_p, _in, _g) {
    // The two clocks that run whatever else he is doing, including while he
    // is still flying in: the close-up, and the dial's own fade.
    if (_p.card_t > 0) _p.card_t--;
    var _grace = player_grace_left(_p);
    _p.grace_show += (((_grace > 0 && _p.entry <= 0) ? 1 : 0)
                      - _p.grace_show) * 0.22;

    if (_p.entry > 0) {
        // Flying in. The player has no control and cannot be hit, which is
        // what lets a stage open on a moving background instead of on a
        // stationary sprite waiting for the first enemy.
        _p.entry--;
        _p.y -= 2.6;
        _p.anim++;
        return;
    }

    _p.focus = _in.focus;

    var _spd = _p.focus ? PLAYER_SPD_FOCUS : PLAYER_SPD;
    var _dx = (_in.right ? 1 : 0) - (_in.left ? 1 : 0);
    var _dy = (_in.down ? 1 : 0) - (_in.up ? 1 : 0);

    // **Diagonals are normalised.** Without this, moving diagonally is forty
    // per cent faster than moving straight, and every player who notices ends
    // up travelling everywhere at 45 degrees. It is a one-line fix and it is
    // the difference between movement that feels designed and movement that
    // feels like an oversight.
    if (_dx != 0 && _dy != 0) {
        _spd *= 0.70710678;
    }

    _p.x += _dx * _spd;
    _p.y += _dy * _spd;
    _p.x = clamp(_p.x, FIELD_X0 + FIELD_MARGIN, FIELD_X1 - FIELD_MARGIN);
    _p.y = clamp(_p.y, FIELD_Y0 + FIELD_MARGIN, FIELD_Y1 - FIELD_MARGIN);

    _p.lean += (_dx - _p.lean) * 0.18;
    _p.anim++;

    if (_p.iframe > 0) _p.iframe--;

    // The special. **Checked before the shot and before anything can hit**, so
    // a bomb pressed on the frame a bullet arrives beats the bullet -- which
    // is the single most argued-about frame in the genre and the only
    // defensible way round it. A player who reacted in time should live.
    if (_in.bomb && _p.bomb_t <= 0 && _p.mp >= MP_PER_BOMB) {
        player_bomb(_p, _g);
    }
    if (_p.bomb_t > 0) {
        _p.bomb_t--;
        player_bomb_sweep(_p);
    }
    // **The seals are stepped outside that branch**, because they outlive
    // nothing else about the bomb but must not be cut short by it: the last
    // one bursts before the grace ends, and a seal frozen in the air on the
    // frame the grace ran out would be a bullet-sweeping thing that stopped
    // sweeping.
    player_seals_step(_p);

    // The shot.
    if (_p.shot_t > 0) _p.shot_t--;
    if (_in.shoot && _p.shot_t <= 0) {
        player_fire(_p);
        _p.shot_t = PSHOT_PERIOD;
    }
    _p.fire_glow += ((_in.shoot ? 1 : 0) - _p.fire_glow) * 0.35;
}

/// @desc One volley. Two barrels either side of centre, converging slightly.
///
///       **The bolts leave from in front of him, not from inside him.**
///       `spr_szuix` is 122x102 with its origin on his chest, so it reaches 56
///       pixels above the point the player is at -- and the first version of
///       this spawned at `_p.y - 20`, which is halfway up his ribs. Every shot
///       was therefore born underneath his own sprite and only became visible
///       once it had cleared his horns, which read as a character who
///       *leaks* bolts rather than one who throws them. `PSHOT_MUZZLE` is that
///       distance, and it is a little past the top of the sprite so the whole
///       bolt is on screen the frame it appears.
function player_fire(_p) {
    var _spread = _p.focus ? PSHOT_SPREAD_FOCUS : PSHOT_SPREAD;
    var _off = _p.focus ? PSHOT_OFFSET * 0.5 : PSHOT_OFFSET;
    // 90 is straight up in GameMaker's angles, which is forward here.
    pshot_fire(_p.x - _off, _p.y - PSHOT_MUZZLE, PSHOT_SPD, 90 + _spread,
               PSHOT_DMG);
    pshot_fire(_p.x + _off, _p.y - PSHOT_MUZZLE, PSHOT_SPD, 90 - _spread,
               PSHOT_DMG);
    fx_spark(_p.x, _p.y - PSHOT_MUZZLE + 6, 90, 1.4, COL_SZUIX_LIT, 8, 18);
    // One cue for the volley, not one per barrel. The two bolts leave on the
    // same frame from twenty pixels apart, which is one sound by any measure
    // the ear applies -- and asking twice would only make it louder, since
    // `sfx_step` reads the count as size. See `audio_functions`.
    sfx(Sfx.PShot);
}

/// @desc Cast the special: spend the meter, take the grace, start the sweep.
///
///       **The first frame is the whole of the response, and it is loud.**
///       This is the one key in the game pressed under pressure, so the flash,
///       the shake, the shockwave and the close-up all land on the frame X
///       goes down -- the sigil, the theft and the seals are the sentence that
///       follows, and none of them is what tells the player the bomb happened.
///       Same constraint `cue_bomb` is written to: the transient is at sample
///       zero.
function player_bomb(_p, _g) {
    _p.mp -= MP_PER_BOMB;
    player_grace_begin(_p, BOMB_INVULN);
    _p.bomb_t = BOMB_INVULN;
    _p.bomb_x = _p.x;
    _p.bomb_y = _p.y;
    _p.bomb_n++;
    _p.card_t = PLAYER_CARD_TIME;
    for (var _i = 0; _i < array_length(_p.seals); _i++) {
        _p.seals[_i].live = false;
    }

    // **Violet rather than white, and softer than it was.** The wash used to
    // be a near-white 0.55 that took the field with it for a third of a
    // second -- which is a cost worth paying when the flash is all there is,
    // and is simply in the way now that there is a sigil and a close-up to
    // look at. It is his own colour, so the screen says whose spell it is
    // before the card has arrived.
    fx_flash_screen(COL_SIGIL, 0.34);
    fx_shake(15);
    fx_flash_at(_p.x, _p.y, COL_RUNE, 1.1);
    fx_ring(_p.x, _p.y, 30, BOMB_CLEAR_R * 1.25, 34, COL_SIGIL, 1.0);
    fx_ring(_p.x, _p.y, 12, 240, 18, c_white, 0.8);
    fx_burst(_p.x, _p.y, 26, 6, 18, COL_RUNE, 30, 22);
    sfx(Sfx.Bomb);

    if (_g != undefined) _g.tally += 0;   // the bomb is not worth points
}

/// @desc One bullet the sweep has just erased, turned into a mote of stolen
///       magic streaming back to the sigil's heart.
///
///       **Bound to the cast point rather than to the player**, because the
///       circle is anchored where it was cast and he is free to fly out of it
///       -- a mote that chased him would leave the figure it came out of.
///
///       It *accelerates* inward: `drag` above one is a particle that gets
///       faster, and the pull of something being taken reads as ease-in. A
///       decelerating mote reads as debris settling.
function bomb_mote(_x, _y, _col, _n) {
    // Every other bullet, and never more than this many in a frame: a full
    // screen swept is a thousand of them, and the pool would be nothing but
    // motes for the rest of the bomb.
    if ((_n mod 2) != 0 || _n > 70) return;
    var _d = point_distance(_x, _y, cx, cy);
    if (_d < 30) return;
    var _life = 20;
    var _acc = 1.09;
    var _m = fx_spark(_x, _y, point_direction(_x, _y, cx, cy),
                      _d * (_acc - 1) / (power(_acc, _life) - 1),
                      ((_n mod 4) == 0) ? c_white : COL_RUNE, _life, 30);
    _m.drag = _acc;
}

/// @desc The sweep, one frame of it.
///
///       **It grows rather than clearing everything at once.** A bomb that
///       emptied the screen on its first frame would be a screenshot of an
///       empty screen; growing it over `BOMB_GROW` frames means the player
///       watches the wave reach the bullets, and the bullets it reaches turn
///       into score on the way -- which is what makes bombing under pressure
///       feel like a rescue rather than an admission.
///
///       The seals leave `BOMB_SEAL_AT` frames in, which is after the sweep
///       has finished and after the last of what it stole has arrived.
function player_bomb_sweep(_p) {
    var _elapsed = BOMB_INVULN - _p.bomb_t;
    if (_elapsed == BOMB_SEAL_AT) player_seals_launch(_p);
    if (_elapsed > BOMB_GROW) return;
    var _r = BOMB_CLEAR_R * (_elapsed / BOMB_GROW);
    bullet_clear_circle(_p.bomb_x, _p.bomb_y, _r, true,
                        method({ cx: _p.bomb_x, cy: _p.bomb_y }, bomb_mote));
    if (_elapsed == BOMB_GROW) laser_clear_all(true);
}

// ---------------------------------------------------------------------------
// The seals
// ---------------------------------------------------------------------------
//
// **What the sigil took, thrown back.** Six wisps of his fire leave the heart
// of the circle in a pinwheel, spread while they turn, then hunt whatever is
// nearest and burst on it -- clearing what they fly through and a good circle
// of what they land in. It is Fantasy Seal's shape, and the reason it suits an
// imp who steals magic is that the thing he throws is what he has just taken.

/// @desc Put the seals in the air, in a rosette round the sigil's heart.
function player_seals_launch(_p) {
    for (var _i = 0; _i < array_length(_p.seals); _i++) {
        var _s = _p.seals[_i];
        _s.live = true;
        _s.x = _p.bomb_x;
        _s.y = _p.bomb_y;
        _s.px = _s.x;
        _s.py = _s.y;
        // One up the middle, the rest evenly round it -- the same fairness
        // habit `fire_fan` keeps, for the opposite reason: this one is a
        // display and a gap on the centre line would read as a miscount.
        _s.dir = 90 + _i * (360 / BOMB_SEALS);
        _s.spd = BOMB_SEAL_SPD0;
        _s.t = 0;
        _s.k = _i;
    }
    fx_flash_at(_p.bomb_x, _p.bomb_y, c_white, 1.3);
    fx_ring(_p.bomb_x, _p.bomb_y, 20, 320, 24, COL_RUNE, 1.0);
    fx_shake(7);
    sfx(Sfx.WardScatter);
}

/// @desc How many seals are in the air. For the suites, and for anything that
///       ever wants to know whether the bomb is still answering.
function player_seals_live(_p) {
    var _n = 0;
    for (var _i = 0; _i < array_length(_p.seals); _i++) {
        if (_p.seals[_i].live) _n++;
    }
    return _n;
}

/// @desc The nearest thing a seal is allowed to hunt, or `undefined`.
///
///       **Chosen again every frame rather than remembered.** A pool entry is
///       reused once its enemy dies, so a stored reference is a reference to
///       whatever took that slot next -- and re-picking costs six distance
///       checks against a handful of enemies, against a bug that would only
///       ever show up in the one frame after a kill.
function seal_target(_s) {
    var _best = undefined;
    var _bd = 999999;
    for (var _i = 0; _i < global.enemy_n; _i++) {
        var _e = global.enemies[_i];
        if (_e.leaving) continue;
        // A boss in ceremony cannot be hurt, so it cannot be hunted either --
        // a seal that curved into an untouchable boss and burst for nothing
        // would read as the bomb failing. Same line `enemy_take_shots` draws.
        if (_e.boss != undefined && !boss_vulnerable(_e)) continue;
        if (_e.y < FIELD_Y0 - 10) continue;          // not on yet
        var _d = point_distance(_s.x, _s.y, _e.x, _e.y);
        if (_d < _bd) {
            _bd = _d;
            _best = _e;
        }
    }
    return _best;
}

/// @desc Every seal in the air, one frame.
function player_seals_step(_p) {
    for (var _i = 0; _i < array_length(_p.seals); _i++) {
        var _s = _p.seals[_i];
        if (!_s.live) continue;

        _s.t++;
        _s.px = _s.x;
        _s.py = _s.y;

        if (_s.t <= BOMB_SEAL_CURL) {
            // The pinwheel: they all turn the same way, so the six of them
            // open as one figure rather than as six unrelated shots.
            var _f = 1 - _s.t / BOMB_SEAL_CURL;
            _s.dir += 7.0 * _f;
            _s.spd = lerp(BOMB_SEAL_SPD0, 13, 1 - _f);
        } else {
            var _e = seal_target(_s);
            if (_e != undefined) {
                var _want = point_direction(_s.x, _s.y, _e.x, _e.y);
                _s.dir += clamp(angle_difference(_want, _s.dir),
                                -BOMB_SEAL_TURN, BOMB_SEAL_TURN);
                _s.spd = min(BOMB_SEAL_SPD, _s.spd + 1.1);
            } else {
                // Nothing to hunt: carry on up the field and burst there,
                // which keeps the display where the enemies would have been
                // rather than trailing off the bottom of the screen.
                var _rx = FIELD_CX + lengthdir_x(300, _s.k * (360 / BOMB_SEALS));
                var _ry = FIELD_Y0 + FIELD_H * 0.34
                        + lengthdir_y(150, _s.k * (360 / BOMB_SEALS));
                _s.dir += clamp(angle_difference(
                    point_direction(_s.x, _s.y, _rx, _ry), _s.dir), -4, 4);
                _s.spd = min(15, _s.spd + 0.4);
            }
        }

        _s.x += lengthdir_x(_s.spd, _s.dir);
        _s.y += lengthdir_y(_s.spd, _s.dir);

        // **The wake clears but does not pay.** `bullet_clear_circle` drops a
        // shard for the first bullet of every call, so a per-frame sweep with
        // `_to_items` on would mint one a frame per seal -- five hundred over
        // a bomb. The burst pays instead; see `player_seal_burst`.
        bullet_clear_circle(_s.x, _s.y, BOMB_SEAL_WAKE, false);

        // The trail: two motes a frame, alternating between the fire's two
        // colours, dropped behind rather than emitted forward.
        for (var _k = 0; _k < 2; _k++) {
            fx_spark(_s.x + random_range(-7, 7), _s.y + random_range(-7, 7),
                     _s.dir + 180 + random_range(-28, 28),
                     random_range(0.6, 2.2),
                     ((_s.t + _k) mod 2 == 0) ? COL_FLAME : COL_SIGIL,
                     20, 46, spr_fx_bloom);
        }

        if (_s.t >= BOMB_SEAL_LIFE
            || _s.x < FIELD_X0 - 40 || _s.x > FIELD_X1 + 40
            || _s.y < FIELD_Y0 - 40 || _s.y > FIELD_Y1 + 40) {
            player_seal_burst(_s);
        }
    }
}

/// @desc One seal going off, wherever it is.
function player_seal_burst(_s) {
    if (!_s.live) return;
    _s.live = false;

    bullet_clear_circle(_s.x, _s.y, BOMB_SEAL_BLAST, true);
    fx_flash_at(_s.x, _s.y, COL_RUNE, 0.9);
    fx_ring(_s.x, _s.y, 16, BOMB_SEAL_BLAST * 1.15, 26, COL_SIGIL, 1.0);
    fx_ring(_s.x, _s.y, 8, BOMB_SEAL_BLAST * 0.55, 16, c_white, 0.8);
    fx_burst(_s.x, _s.y, 14, 4, 13, COL_RUNE, 26, 26);
    // Tongues of the same fire the seal was made of, thrown outward. They are
    // the `spr_fx_wisp` frames the seal itself is drawn with, which is what
    // makes a burst read as *that thing* coming apart.
    for (var _k = 0; _k < 9; _k++) {
        fx_spark(_s.x, _s.y, _k * 40 + random_range(-14, 14),
                 random_range(6, 11), c_white, 18, 150, spr_fx_wisp);
    }
    fx_shake(5);
    sfx(Sfx.WardBurst);
}

/// @desc Take a hit. Returns true if it landed, so the caller can react.
function player_hit(_p) {
    if (player_invulnerable(_p) || !_p.alive) return false;

    _p.hp -= HP_PER_HIT;
    player_grace_begin(_p, IFRAME_TIME);
    _p.iframe = IFRAME_TIME;
    _p.hit_n++;

    fx_flash_screen(COL_LIFE, 0.5);
    fx_shake(20);
    fx_ring(_p.x, _p.y, 10, 300, 34, COL_LIFE, 1.0);
    fx_burst(_p.x, _p.y, 26, 3, 11, COL_LIFE, 34, 18);
    sfx(Sfx.Hit);

    // **A hit scatters shards.** Touhou drops your power on death and this is
    // the same idea turned round: losing a quarter of the bar puts a handful
    // of recoverable points on the field, so the moment after a hit is a
    // scramble rather than only a loss. They are gold, not red -- being hit
    // must not hand back the health it just took.
    for (var _i = 0; _i < PLAYER_HIT_SHARDS; _i++) {
        item_spawn(_p.x, _p.y, ItemKind.Tally,
                   lengthdir_x(random_range(2, 7), random(360)),
                   -random_range(3, 8));
    }

    // Clear what is on top of the player, or the iframes run out inside the
    // same wall of bullets and the player dies twice to one mistake.
    bullet_clear_circle(_p.x, _p.y, 190, false);

    if (_p.hp <= 0) {
        _p.hp = 0;
        _p.alive = false;
        // **Both, and in this order.** The hit is what happened and the death
        // is what it meant, and they are different lengths in different bands
        // -- so they layer rather than mask, and the frame the run ends on
        // sounds like an ending instead of like one more hit. `sfx_step`
        // spends its budget in priority order and `PlayerDown` outranks
        // everything, so the pair survives even on a frame where the field is
        // also popping.
        sfx(Sfx.PlayerDown);
    }
    return true;
}

/// @desc Collision against everything dangerous, and grazing.
///       Returns true if the player was hit this frame.
function player_collide(_p, _g) {
    if (!_p.alive) return false;

    if (!player_invulnerable(_p)) {
        var _i = bullet_hit_index(_p.x, _p.y, PLAYER_R);
        if (_i >= 0) {
            bullet_kill_at(_i);
            player_hit(_p);
            return true;
        }
        if (laser_any_hit(_p.x, _p.y, PLAYER_R)) {
            player_hit(_p);
            return true;
        }
        // A charged ring's metal, and the current strung between two of them.
        // Both on the same terms as a laser: only ever while they are live,
        // never during the warning that announced them.
        if (ring_any_hit(_p.x, _p.y, PLAYER_R)) {
            player_hit(_p);
            return true;
        }
        if (enemy_body_hit(_p.x, _p.y, PLAYER_R)) {
            player_hit(_p);
            return true;
        }
    }

    // **Grazing is live during invulnerability and that is deliberate.** The
    // three seconds after a hit are the only time a player is free to sit
    // inside a pattern, and letting those seconds pay is what turns being hit
    // into a chance to claw points back rather than three seconds of nothing.
    // **A laser pays too, and until now it did not.** Sliding along a beam is
    // the most deliberate risk this game asks anybody to take -- a bullet
    // passes whether the player is brave or not, where a wall of light is
    // something they have to choose to stay beside -- and it was the one piece
    // of nerve the score said nothing about. It pays on a cooldown rather than
    // once, because a laser is still there a second later; see `laser_graze`.
    var _gz = bullet_graze(_p.x, _p.y, GRAZE_R)
            + laser_graze(_p.x, _p.y, PLAYER_R)
            + ring_graze(_p.x, _p.y, PLAYER_R);
    if (_gz > 0) {
        _p.graze_n += _gz;
        // `sfx_many` rather than a call per bullet: this already knows how
        // many were passed, and the count is what sets the cue's size.
        sfx_many(Sfx.Graze, _gz);
        if (_g != undefined) _g.tally += _gz * TALLY_GRAZE;
        for (var _k = 0; _k < min(_gz, 3); _k++) {
            fx_spark(_p.x + random_range(-18, 18), _p.y + random_range(-18, 18),
                     random(360), 2.4, COL_GRAZE, 18, 12);
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc A heartbeat: two pulses and a rest, over `LOW_HP_BEAT` frames.
///
///       **A rhythm rather than a flash.** A warning that blinks evenly is
///       one the eye stops seeing inside a minute -- the periphery is built
///       to ignore steady repetition and to catch a change in it. Two beats
///       and a gap is the one pattern nobody has to be taught.
///       **Wide pulses rather than sharp ones.** The first version peaked
///       inside four frames, which is a *flash* -- reported as too bright and
///       distracting, and rightly: a hard onset in the corner of the eye is
///       the same signal a bullet arriving makes, and the one thing a warning
///       must not do is imitate the thing it is warning about. Swelling over
///       about ten frames reads as breathing instead.
function player_heartbeat(_t) {
    var _ph = frac(_t / LOW_HP_BEAT);
    // Two gaussians, the second smaller, plus the first again a cycle on so
    // the wrap is not a step.
    var _a = exp(-sqr((_ph - 0.02) / 0.115))
           + exp(-sqr((_ph - 1.02) / 0.115));
    var _b = exp(-sqr((_ph - 0.26) / 0.105)) * 0.66;
    return clamp(max(_a, _b), 0, 1);
}

/// @desc Draw Szuix, his shots, and the two things that say what state he is
///       in: the hitbox while focused, and the flicker while invulnerable.
function player_draw(_p) {
    if (!_p.alive) return;

    // The flicker. Fast enough to be unmistakable, and never fully off -- a
    // player sprite that vanishes for two frames is a player who has lost
    // track of where they are, which is the opposite of what iframes are for.
    var _a = 1.0;
    if (_p.iframe > 0) _a = 0.45 + 0.35 * dsin(_p.iframe * 34);

    var _frames = sprite_get_number(spr_szuix);
    var _fr = (_p.anim div 5) mod _frames;
    var _beat = (_p.hp <= HP_PER_HIT) ? player_heartbeat(_p.anim) : 0;

    // **A pool of light under him, and it is not decoration.** Szuix is a dark
    // blue sprite and the stages he flies over are dark; photographed on the
    // brimstone stage he very nearly disappeared, which for the one thing on
    // screen the player must never lose track of is a bug rather than a mood.
    // A halo underneath is the genre's own answer -- it separates him from the
    // ground without touching the silhouette the commission drew.
    gpu_set_blendmode(bm_add);
    var _hs = 190 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _p.x, _p.y, _hs, _hs, 0,
                    _beat > 0.02
                        ? merge_colour(COL_SZUIX, COL_LIFE, _beat * 0.55)
                        : COL_SZUIX,
                    (_p.focus ? 0.30 : 0.40) + _beat * 0.10);
    // ...and the exhaust, which is what says which way he is going.
    var _ts = 96 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _p.x, _p.y + 30, _ts, _ts * 1.6, 0,
                    COL_SZUIX_LIT, _p.focus ? 0.34 : 0.55);

    // **Where the fire is coming from.** A flame sits at each muzzle while the
    // shot is held, so the stream is something he is *doing* rather than
    // something appearing above his head. It eases in and out with the
    // button, because a muzzle that snapped on and off at twenty volleys a
    // second is a strobe.
    if (_p.fire_glow > 0.02 && _p.entry <= 0) {
        var _off = _p.focus ? PSHOT_OFFSET * 0.5 : PSHOT_OFFSET;
        var _my = _p.y - PSHOT_MUZZLE + 10;
        var _mf = (_p.anim div 2) mod sprite_get_number(spr_pshot);
        for (var _b = -1; _b <= 1; _b += 2) {
            draw_sprite_ext(spr_fx_bloom, 0, _p.x + _b * _off, _my,
                            54 / sprite_get_width(spr_fx_bloom),
                            54 / sprite_get_width(spr_fx_bloom), 0,
                            COL_FLAME, 0.42 * _p.fire_glow);
            draw_sprite_ext(spr_pshot, _mf, _p.x + _b * _off, _my,
                            0.52, 0.52, 90, c_white, 0.75 * _p.fire_glow);
        }
    }
    gpu_set_blendmode(bm_normal);

    draw_sprite_ext(spr_szuix, _fr, _p.x, _p.y, 1, 1, -_p.lean * 7,
                    c_white, _a);

    // **One hit from death, he beats.** His own silhouette lit red, twice a
    // beat, over the sprite -- which is a warning in pixels that are already
    // his rather than a thing added to the screen, so it cannot hide a bullet
    // and cannot be mistaken for one. The console's life meter pulses on the
    // same threshold; this is that fact where the player is looking.
    //
    // **Kept low.** At its first setting it took him to a flat pink twice a
    // second, which is a state nobody can dodge inside -- the warning was
    // competing with the pattern it is supposed to help read. A quarter of
    // that is a red glow along his edge that the periphery catches and the
    // eye never has to stop on.
    if (_beat > 0.01) {
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(spr_szuix_aura, _fr, _p.x, _p.y, 1, 1, -_p.lean * 7,
                        COL_LIFE, (0.05 + 0.26 * _beat) * _a);
        gpu_set_blendmode(bm_normal);
    }

    // The blaze as he casts: the same halo in his own cyan, once, fading over
    // the first half-second of the bomb.
    var _cast = (_p.bomb_t > 0) ? max(0, 1 - (BOMB_INVULN - _p.bomb_t) / 30) : 0;
    if (_cast > 0.01) {
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(spr_szuix_aura, _fr, _p.x, _p.y, 1, 1, -_p.lean * 7,
                        COL_RUNE, _cast);
        gpu_set_blendmode(bm_normal);
    }

    if (_p.focus) {
        var _spin = _p.anim * 1.6;
        gpu_set_blendmode(bm_add);
        var _rs = 74 / sprite_get_width(spr_focus_ring);
        draw_sprite_ext(spr_focus_ring, 0, _p.x, _p.y, _rs, _rs, _spin,
                        COL_SZUIX_LIT, 0.85);
        draw_sprite_ext(spr_focus_ring, 0, _p.x, _p.y, _rs * 0.72, _rs * 0.72,
                        -_spin * 1.7, c_white, 0.55);
        gpu_set_blendmode(bm_normal);
    }
}

/// @desc How much of the grace is left, drawn round him as a dial.
///
///       **Wordsearch's combo ring, on the one number this game never told
///       anybody.** Being invulnerable is a state with an end, and until now
///       the only thing that said so was a flicker that looks the same on its
///       first frame as on its last -- so the moment it ran out arrived
///       without warning, which for the three seconds after a hit is the
///       moment the player is most likely to be somewhere they could not
///       otherwise be.
///
///       A faint circle for the whole grace and a bright arc for what is left
///       of it, sweeping clockwise from noon so the arc retreats to where it
///       started. The **head** of the arc carries the bloom, because the head
///       is the only part that moves and motion is what the eye tracks.
///
///       Two more readings of the same number for whoever is not watching the
///       arc: the ring **tightens** as it empties, and inside `GRACE_URGENT`
///       it flickers and warms toward the colour of being hit.
///
///       Thin, additive and never filled. It is drawn over the field the
///       player is reading, and a disc this size would be a hole in it.
function player_draw_grace(_p) {
    if (!_p.alive || _p.grace_show <= 0.01 || _p.untouchable) return;

    var _left = player_grace_left(_p);
    var _frac = clamp(_left / max(1, _p.grace_max), 0, 1);
    var _urgent = (_frac > 0 && _frac < GRACE_URGENT);
    var _col = _urgent ? merge_colour(COL_RUNE, COL_LIFE, 0.55) : COL_RUNE;
    var _lit = merge_colour(_col, c_white, 0.55);
    var _flick = _urgent ? (0.60 + 0.40 * dsin(_p.anim * 26)) : 1;
    var _rad = lerp(GRACE_RING_R_EMPTY, GRACE_RING_R_FULL, _frac);
    var _a = _p.grace_show * _flick;
    var _to = 90 - 360 * _frac;
    var _steps = max(2, ceil(360 * _frac / 6));

    gpu_set_blendmode(bm_add);

    // The whole grace, so what is missing reads as missing.
    draw_arc_band(_p.x, _p.y, _rad - 1.5, _rad + 1.5, 0, 360, _col,
                  0.12 * _p.grace_show, 0.12 * _p.grace_show, 60);

    if (_frac > 0.001) {
        // A soft halo and a bright core, the two-pass treatment every other
        // light in this game gets, so it reads as the same world rather than
        // as a ring laid over it.
        draw_arc_band(_p.x, _p.y, _rad - 7, _rad + 7, 90, _to, _col,
                      0.05 * _a, 0.24 * _a, _steps);
        draw_arc_band(_p.x, _p.y, _rad - 2, _rad + 2, 90, _to, _lit,
                      0.22 * _a, 0.90 * _a, _steps);
        gpu_set_blendmode(bm_normal);
        draw_bloom(_p.x + lengthdir_x(_rad, _to),
                   _p.y + lengthdir_y(_rad, _to), 34, _lit, 0.55 * _a);
        return;
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The hitbox, and only the hitbox.
///
///       **Drawn after the bullets, which is why it is a function of its own.**
///       Four pixels behind a wall of danmaku is four pixels the player cannot
///       find, and the one moment they most need to find it is the moment the
///       screen is fullest.
///
///       **It appears only while focused, and it is the truth.** Its radius is
///       `PLAYER_R` and the sprite is drawn at exactly that size, so what the
///       player is shown is what the game tests. Anything else here would be a
///       lie the game told sixty times a second.
function player_draw_hitbox(_p) {
    if (!_p.alive || !_p.focus || _p.entry > 0) return;
    var _hs = (PLAYER_R * 2) / sprite_get_width(spr_hitbox);
    draw_sprite_ext(spr_hitbox, 0, _p.x, _p.y, _hs, _hs, 0, c_white, 1);
}

/// @desc The player's own shots. Additive, because they are light and because
///       it keeps them from ever being mistaken for something that can hurt.
///
///       **Two passes: a bloom under the bolt and the bolt over it.** The
///       bloom is what gives a shot presence without making the sprite itself
///       any larger -- a bolt big enough to be felt at 1:1 would be a bolt
///       wide enough to hide a bullet behind, and the player fires two of them
///       every few frames. Light spreading past the shape costs nothing to
///       dodge round and reads as twice the shot.
///       **The bolt is a fireball and it burns**, which is the one thing the
///       old one could not do: it was a single frame tinted `COL_SZUIX_LIT`,
///       and a tint multiplies -- so the white core the sprite was drawn with
///       came out the same flat periwinkle as its rim and what reached the
///       screen was a smooth pointed lozenge. Reported as looking like
///       missiles rather than fire, which is exactly what a symmetric taper
///       with no internal structure is.
///
///       Now the colour is *in* the sprite -- violet at the torn edges, azure
///       through the body, white only at the heart -- and it is drawn
///       `c_white` so none of that is multiplied away. Eight frames of
///       turbulence loop through it, each shot starting at its own phase, so
///       a stream of them flickers instead of pulsing as one object.
function pshot_draw() {
    gpu_set_blendmode(bm_add);
    var _gs = 74 / sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < global.pshot_n; _i++) {
        var _s = global.pshots[_i];
        draw_sprite_ext(spr_fx_bloom, 0, _s.x, _s.y, _gs, _gs, 0,
                        COL_FLAME, 0.30);
    }
    var _n = sprite_get_number(spr_pshot);
    for (var _i = 0; _i < global.pshot_n; _i++) {
        var _s = global.pshots[_i];
        draw_sprite_ext(spr_pshot, (_s.life + _s.flick) mod _n,
                        _s.x, _s.y, 1, 1, _s.dir, c_white, 1);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The special: the sigil, the front of the sweep, the heart, and the
///       seals.
///
///       **The circle is the sweep**, which is the whole reason it is drawn at
///       all: its rim is exactly where bullets are being erased this frame, so
///       a player watching it knows what has been taken and what has not. It
///       is anchored where the bomb was cast rather than to him, because that
///       is where the sweep is anchored -- a circle that followed him would be
///       drawing a boundary that is not the one being enforced.
///
///       Everything here is additive and nothing is filled: it is drawn over
///       a field that still has bullets outside it.
function player_draw_bomb(_p) {
    if (_p.bomb_t <= 0) return;
    var _e = BOMB_INVULN - _p.bomb_t;         // frames since the cast
    var _bx = _p.bomb_x;
    var _by = _p.bomb_y;

    gpu_set_blendmode(bm_add);

    // ---- the sigil ---------------------------------------------------------
    // Alpha: up over six frames, held, then gone by `BOMB_SIGIL_OUT`.
    var _fade = min(1, _e / 6.0)
              * (1 - clamp((_e - 74) / (BOMB_SIGIL_OUT - 74.0), 0, 1));
    if (_fade > 0.01) {
        // The rim follows the sweep exactly while it grows, then drifts out
        // a little as it dissolves.
        var _grow = min(1, _e / BOMB_GROW);
        var _rad = BOMB_CLEAR_R * _grow
                 * (1 + 0.08 * clamp((_e - 74) / 42.0, 0, 1));
        // ...and draws a breath in just before the seals leave.
        _rad *= 1 - 0.035 * clamp((_e - 26) / (BOMB_SEAL_AT - 26.0), 0, 1)
                * clamp((BOMB_SEAL_AT + 8 - _e) / 8.0, 0, 1);
        // The sprite's outer ring sits 494 of its 512 half-pixels out.
        var _sc = _rad / 494 * (sprite_get_width(spr_fx_sigil) / 1024.0);
        // A flare on the frame the heart lets go.
        var _pulse = 1 + 0.5 * max(0, 1 - abs(_e - BOMB_SEAL_AT) / 10.0);

        // The rings, turning one way; the script, turning the other and
        // arriving a few frames later; the emblem last and slowest. Three
        // rates is what makes it read as a mechanism rather than a picture.
        var _spin = _e * 0.55 + (1 - _grow) * 60;
        draw_sprite_ext(spr_fx_sigil, 0, _bx, _by, _sc, _sc, _spin,
                        COL_SIGIL, 0.85 * _fade * _pulse);
        var _in1 = min(1, max(0, _e - 5) / 14.0);
        draw_sprite_ext(spr_fx_sigil, 1, _bx, _by, _sc * _in1, _sc * _in1,
                        -_e * 0.95, COL_RUNE, 0.9 * _fade * _in1 * _pulse);
        var _in2 = min(1, max(0, _e - 10) / 12.0);
        // The emblem overshoots and settles, which is the one piece of motion
        // that makes a thing land rather than appear -- the same easing the
        // boss's name splash uses.
        var _os = _sc * _in2 * (1 + 0.16 * (1 - _in2));
        draw_sprite_ext(spr_fx_sigil, 2, _bx, _by, _os, _os, _e * 0.22,
                        merge_colour(COL_SIGIL, c_white, 0.55),
                        0.9 * _fade * _in2 * _pulse);
        // The ground inside it, barely: a circle this size with nothing in it
        // reads as a wire hoop.
        var _gs = _rad * 1.5 / sprite_get_width(spr_fx_bloom);
        draw_sprite_ext(spr_fx_bloom, 0, _bx, _by, _gs, _gs, 0, COL_SIGIL,
                        0.14 * _fade);
    }

    // ---- the front of the sweep ---------------------------------------------
    if (_e <= BOMB_GROW + 8) {
        var _t = min(1, _e / BOMB_GROW);
        var _r = BOMB_CLEAR_R * _t;
        var _out = max(0, 1 - max(0, _e - BOMB_GROW) / 8.0);
        var _rs = _r * 2 / sprite_get_width(spr_fx_ring);
        draw_sprite_ext(spr_fx_ring, 0, _bx, _by, _rs, _rs, 0, COL_SIGIL,
                        0.85 * _out);
        draw_sprite_ext(spr_fx_ring, 0, _bx, _by, _rs * 0.94, _rs * 0.94, 0,
                        c_white, 0.45 * _out);
        // **The rim is on fire.** Thirty-two tongues of his own flame laid
        // round the circumference, heads outward, each on its own frame of the
        // loop -- so the wave that is erasing the pattern is made of the same
        // thing his shot is made of, rather than being a white ring.
        var _wn = sprite_get_number(spr_fx_wisp);
        var _ws = (0.5 + 0.45 * _t) * _out;
        for (var _i = 0; _i < 32; _i++) {
            var _a = _i * 11.25 + _e * 1.6;
            draw_sprite_ext(spr_fx_wisp, (_e + _i * 3) mod _wn,
                            _bx + lengthdir_x(_r, _a),
                            _by + lengthdir_y(_r, _a),
                            _ws, _ws, _a, c_white, 0.9 * _out);
        }
    }

    // ---- the heart ------------------------------------------------------------
    // It fills as the stolen magic arrives and flares when it lets go.
    var _gather = clamp((_e - 4) / max(1, BOMB_SEAL_AT - 4.0), 0, 1);
    var _after = max(0, 1 - max(0, _e - BOMB_SEAL_AT) / 26.0);
    var _heart = (_e < BOMB_SEAL_AT) ? _gather : _after;
    if (_heart > 0.01) {
        var _pop = 1 + 1.6 * max(0, 1 - abs(_e - BOMB_SEAL_AT) / 8.0);
        var _bw = sprite_get_width(spr_fx_bloom);
        // Drawn here rather than through `draw_bloom`, which sets the blend
        // mode itself and would hand the rest of this routine back in
        // `bm_normal` -- the trap the note at the top of `fx_draw` is about.
        var _core = [[(240 + 200 * _gather) * _pop, COL_SIGIL, 0.22],
                     [(90 + 120 * _gather) * _pop, COL_RUNE, 0.55],
                     [(40 + 60 * _gather) * _pop, c_white, 0.65]];
        for (var _i = 0; _i < array_length(_core); _i++) {
            var _c = _core[_i];
            draw_sprite_ext(spr_fx_bloom, 0, _bx, _by, _c[0] / _bw,
                            _c[0] / _bw, 0, _c[1], _c[2] * _heart);
        }
    }

    // ---- the seals -------------------------------------------------------------
    var _wn2 = sprite_get_number(spr_fx_wisp);
    var _sn = sprite_get_number(spr_fx_sigil);
    for (var _i = 0; _i < array_length(_p.seals); _i++) {
        var _s = _p.seals[_i];
        if (!_s.live) continue;
        var _in = min(1, _s.t / 6.0);
        draw_sprite_ext(spr_fx_bloom, 0, _s.x, _s.y,
                        190 / sprite_get_width(spr_fx_bloom),
                        190 / sprite_get_width(spr_fx_bloom), 0,
                        COL_SIGIL, 0.45 * _in);
        // Each one carries a turning copy of the emblem at its heart, so a
        // seal is recognisably a piece of the circle that threw it.
        var _es = 0.15 * _in * (sprite_get_width(spr_fx_sigil) / 1024.0);
        draw_sprite_ext(spr_fx_sigil, _sn - 1, _s.x, _s.y, _es, _es,
                        _s.t * 4.5, COL_SIGIL, 0.75 * _in);
        draw_sprite_ext(spr_fx_wisp, (_s.t + _i * 2) mod _wn2, _s.x, _s.y,
                        0.92 * _in, 0.92 * _in, _s.dir, c_white, _in);
        draw_sprite_ext(spr_fx_bloom, 0, _s.x, _s.y,
                        52 / sprite_get_width(spr_fx_bloom),
                        52 / sprite_get_width(spr_fx_bloom), 0,
                        c_white, 0.8 * _in);
    }

    gpu_set_blendmode(bm_normal);
}

/// @desc His close-up, on the GUI layer, while the sigil is going off.
///
///       **The same card a boss's spell gets**, through the same function --
///       see `draw_eye_card`. It is the one piece of the bomb that says whose
///       spell this is rather than what it does, which is exactly the job the
///       card does for a boss.
function player_draw_card(_p) {
    if (_p.card_t <= 0) return;
    draw_eye_card(spr_eye_szuix, _p.card_t / PLAYER_CARD_TIME);
}
