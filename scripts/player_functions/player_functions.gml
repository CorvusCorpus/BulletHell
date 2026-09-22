/// @desc Szuix: movement, focus, the shot, the special, and getting hit.
///
/// The player is a struct, and `player_step` takes its input as a struct, so
/// tests can drive it. `input_gather` is the only function that reads a
/// device; `obj_game`'s Step calls it.

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

        // The bomb's seals, allocated once and reused; `live` marks the ones
        // in the air.
        seals: player_seals_new(),

        // The length of the grace now running, so the grace dial has a whole
        // to show a fraction of (`player_draw_grace`).
        grace_max: 1,
        grace_show: 0,    // the dial's own fade in and out; purely visual

        card_t: 0,        // > 0 while his close-up is on screen
        fire_glow: 0,     // eases up while the shot is held: the muzzles

        // Visual only: the sprite's bank, eased toward the direction of
        // travel.
        lean: 0,
        anim: 0,
        entry: 0,         // > 0 while flying in at the start of a stage

        // Harness-only: a posed player can't be hit, so a hit's bullet clear
        // doesn't cut a hole in the pattern being photographed. Separate from
        // `iframe`, which also makes the sprite flicker. Nothing in play sets
        // it.
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

/// @desc Input with nothing held.
function input_idle() {
    return { left: false, right: false, up: false, down: false,
             shoot: false, bomb: false, focus: false };
}

/// @desc Where the player is across the field: -1 at the left wall, 0 on the
///       centre line, +1 at the right. The grove's camera lean reads this.
function player_field_aim(_p) {
    return clamp((_p.x - FIELD_CX) / (FIELD_W / 2), -1, 1);
}

/// @desc Is the player untouchable right now?
function player_invulnerable(_p) {
    return _p.untouchable || _p.iframe > 0 || _p.bomb_t > 0 || _p.entry > 0;
}

/// @desc Frames of grace left: the longer of the hit grace and the bomb
///       grace (they overlap rather than add).
function player_grace_left(_p) {
    return max(_p.iframe, _p.bomb_t);
}

/// @desc Start a grace of `_frames`, keeping the one running if it is longer.
///       Sets `grace_max` for the dial.
function player_grace_begin(_p, _frames) {
    _p.grace_max = max(player_grace_left(_p), _frames);
}

/// @desc One frame of the player. `_g` is the run, for tallying and bombs.
function player_step(_p, _in, _g) {
    // These run even while flying in.
    if (_p.card_t > 0) _p.card_t--;
    var _grace = player_grace_left(_p);
    _p.grace_show += (((_grace > 0 && _p.entry <= 0) ? 1 : 0)
                      - _p.grace_show) * 0.22;

    if (_p.entry > 0) {
        // Flying in: no control, can't be hit.
        _p.entry--;
        _p.y -= 2.6;
        _p.anim++;
        return;
    }

    _p.focus = _in.focus;

    var _spd = _p.focus ? PLAYER_SPD_FOCUS : PLAYER_SPD;
    var _dx = (_in.right ? 1 : 0) - (_in.left ? 1 : 0);
    var _dy = (_in.down ? 1 : 0) - (_in.up ? 1 : 0);

    // Diagonals are normalised to the same speed as straight movement.
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

    // The special is checked before the shot and before collision, so a bomb
    // pressed on the frame a bullet arrives beats the bullet.
    if (_in.bomb && _p.bomb_t <= 0 && _p.mp >= MP_PER_BOMB) {
        player_bomb(_p, _g);
    }
    if (_p.bomb_t > 0) {
        _p.bomb_t--;
        player_bomb_sweep(_p);
    }
    // Seals are stepped outside that branch so they are never cut short.
    player_seals_step(_p);

    // The shot.
    if (_p.shot_t > 0) _p.shot_t--;
    if (_in.shoot && _p.shot_t <= 0) {
        player_fire(_p);
        _p.shot_t = PSHOT_PERIOD;
    }
    _p.fire_glow += ((_in.shoot ? 1 : 0) - _p.fire_glow) * 0.35;
}

/// @desc One volley: two barrels either side of centre, converging slightly,
///       born `PSHOT_MUZZLE` above the player so they clear his sprite.
function player_fire(_p) {
    var _spread = _p.focus ? PSHOT_SPREAD_FOCUS : PSHOT_SPREAD;
    var _off = _p.focus ? PSHOT_OFFSET * 0.5 : PSHOT_OFFSET;
    // 90 is straight up in GameMaker's angles, which is forward here.
    pshot_fire(_p.x - _off, _p.y - PSHOT_MUZZLE, PSHOT_SPD, 90 + _spread,
               PSHOT_DMG);
    pshot_fire(_p.x + _off, _p.y - PSHOT_MUZZLE, PSHOT_SPD, 90 - _spread,
               PSHOT_DMG);
    fx_spark(_p.x, _p.y - PSHOT_MUZZLE + 6, 90, 1.4, COL_SZUIX_LIT, 8, 18);
    // One cue for the volley (the vote count sets the cue's size).
    sfx(Sfx.PShot);
}

/// @desc Cast the special: spend the meter, take the grace, start the sweep.
///       All the immediate feedback (flash, shake, rings, close-up, cue) lands
///       on this frame.
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

    fx_flash_screen(COL_SIGIL, 0.34);
    fx_shake(15);
    fx_flash_at(_p.x, _p.y, COL_RUNE, 1.1);
    fx_ring(_p.x, _p.y, 30, BOMB_CLEAR_R * 1.25, 34, COL_SIGIL, 1.0);
    fx_ring(_p.x, _p.y, 12, 240, 18, c_white, 0.8);
    fx_burst(_p.x, _p.y, 26, 6, 18, COL_RUNE, 30, 22);
    sfx(Sfx.Bomb);

    if (_g != undefined) _g.tally += 0;   // the bomb is not worth points
}

/// @desc The `_each` callback for the bomb's sweep: every other erased bullet
///       (at most 70 a call) leaves a spark that accelerates into the cast
///       point. Bound as a method with `cx`/`cy`, the cast point.
function bomb_mote(_x, _y, _col, _n) {
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

/// @desc One frame of the sweep: a circle growing from the cast point to
///       `BOMB_CLEAR_R` over `BOMB_GROW` frames. Launches the seals at
///       `BOMB_SEAL_AT`.
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
// The seals: after the sweep, `BOMB_SEALS` wisps leave the cast point in a
// pinwheel, then hunt the nearest enemy and burst on it, clearing bullets
// along the way and where they land, and dealing `BOMB_SEAL_DMG`.
// ---------------------------------------------------------------------------

/// @desc Put the seals in the air, evenly round the cast point.
function player_seals_launch(_p) {
    for (var _i = 0; _i < array_length(_p.seals); _i++) {
        var _s = _p.seals[_i];
        _s.live = true;
        _s.x = _p.bomb_x;
        _s.y = _p.bomb_y;
        _s.px = _s.x;
        _s.py = _s.y;
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

/// @desc How many seals are in the air.
function player_seals_live(_p) {
    var _n = 0;
    for (var _i = 0; _i < array_length(_p.seals); _i++) {
        if (_p.seals[_i].live) _n++;
    }
    return _n;
}

/// @desc The nearest enemy a seal may hunt, or `undefined`. Chosen again every
///       frame rather than remembered, because enemy structs are reused. A
///       boss that can't currently be hurt is skipped.
function seal_target(_s) {
    var _best = undefined;
    var _bd = 999999;
    for (var _i = 0; _i < global.enemy_n; _i++) {
        var _e = global.enemies[_i];
        if (_e.leaving) continue;
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
            // The pinwheel: all turning the same way as they spread.
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
                // Nothing to hunt: head for a spot up the field and burst
                // there.
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

        // The wake clears without dropping items: `bullet_clear_circle` drops
        // a shard for the first bullet of every call, which here would be one
        // a frame per seal. The burst pays instead.
        bullet_clear_circle(_s.x, _s.y, BOMB_SEAL_WAKE, false);

        // The trail: two motes a frame, alternating colours.
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

/// @desc One seal going off where it is: clears a circle of bullets (dropping
///       items) and throws flame tongues from `spr_fx_wisp`.
function player_seal_burst(_s) {
    if (!_s.live) return;
    _s.live = false;

    bullet_clear_circle(_s.x, _s.y, BOMB_SEAL_BLAST, true);
    fx_flash_at(_s.x, _s.y, COL_RUNE, 0.9);
    fx_ring(_s.x, _s.y, 16, BOMB_SEAL_BLAST * 1.15, 26, COL_SIGIL, 1.0);
    fx_ring(_s.x, _s.y, 8, BOMB_SEAL_BLAST * 0.55, 16, c_white, 0.8);
    fx_burst(_s.x, _s.y, 14, 4, 13, COL_RUNE, 26, 26);
    for (var _k = 0; _k < 9; _k++) {
        fx_spark(_s.x, _s.y, _k * 40 + random_range(-14, 14),
                 random_range(6, 11), c_white, 18, 150, spr_fx_wisp);
    }
    fx_shake(5);
    sfx(Sfx.WardBurst);
}

/// @desc Take a hit. Returns true if it landed.
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

    // A hit scatters gold point shards to scramble for (not health).
    for (var _i = 0; _i < PLAYER_HIT_SHARDS; _i++) {
        item_spawn(_p.x, _p.y, ItemKind.Tally,
                   lengthdir_x(random_range(2, 7), random(360)),
                   -random_range(3, 8));
    }

    // Clear what is on top of the player, so the grace doesn't run out inside
    // the same wall of bullets.
    bullet_clear_circle(_p.x, _p.y, 190, false);

    if (_p.hp <= 0) {
        _p.hp = 0;
        _p.alive = false;
        // Played as well as the hit cue; `PlayerDown` has the top priority.
        sfx(Sfx.PlayerDown);
    }
    return true;
}

/// @desc Collision against bullets, lasers, rings and enemy bodies, then
///       grazing. Returns true if the player was hit this frame.
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
        // A ring's metal and any live arc between rings.
        if (ring_any_hit(_p.x, _p.y, PLAYER_R)) {
            player_hit(_p);
            return true;
        }
        if (enemy_body_hit(_p.x, _p.y, PLAYER_R)) {
            player_hit(_p);
            return true;
        }
    }

    // Grazing still pays during invulnerability. Bullets pay once each;
    // lasers and ring bands pay on a cooldown.
    var _gz = bullet_graze(_p.x, _p.y, GRAZE_R)
            + laser_graze(_p.x, _p.y, PLAYER_R)
            + ring_graze(_p.x, _p.y, PLAYER_R);
    if (_gz > 0) {
        _p.graze_n += _gz;
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

/// @desc The low-life heartbeat, 0..1: two soft pulses and a rest per
///       `LOW_HP_BEAT` frames.
function player_heartbeat(_t) {
    var _ph = frac(_t / LOW_HP_BEAT);
    // Two gaussians, the second smaller, plus the first again a cycle on so
    // the wrap is not a step.
    var _a = exp(-sqr((_ph - 0.02) / 0.115))
           + exp(-sqr((_ph - 1.02) / 0.115));
    var _b = exp(-sqr((_ph - 0.26) / 0.105)) * 0.66;
    return clamp(max(_a, _b), 0, 1);
}

/// @desc Draw Szuix: a glow under him, muzzle flames while shooting, the
///       sprite (flickering while invulnerable), a red pulse at one hit from
///       death, a cyan blaze as he casts, and the focus rings.
function player_draw(_p) {
    if (!_p.alive) return;

    // The flicker never goes fully off, so the player doesn't lose track of
    // him.
    var _a = 1.0;
    if (_p.iframe > 0) _a = 0.45 + 0.35 * dsin(_p.iframe * 34);

    var _frames = sprite_get_number(spr_szuix);
    var _fr = (_p.anim div 5) mod _frames;
    var _beat = (_p.hp <= HP_PER_HIT) ? player_heartbeat(_p.anim) : 0;

    // A pool of light under him, so the dark sprite stays visible over dark
    // stages.
    gpu_set_blendmode(bm_add);
    var _hs = 190 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _p.x, _p.y, _hs, _hs, 0,
                    _beat > 0.02
                        ? merge_colour(COL_SZUIX, COL_LIFE, _beat * 0.55)
                        : COL_SZUIX,
                    (_p.focus ? 0.30 : 0.40) + _beat * 0.10);
    // The exhaust.
    var _ts = 96 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _p.x, _p.y + 30, _ts, _ts * 1.6, 0,
                    COL_SZUIX_LIT, _p.focus ? 0.34 : 0.55);

    // A flame at each muzzle while the shot is held, eased in and out.
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

    // One hit from death: a red glow on his own outline (`spr_szuix_aura`),
    // additive and kept faint.
    if (_beat > 0.01) {
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(spr_szuix_aura, _fr, _p.x, _p.y, 1, 1, -_p.lean * 7,
                        COL_LIFE, (0.05 + 0.26 * _beat) * _a);
        gpu_set_blendmode(bm_normal);
    }

    // A cyan blaze on his outline over the first half-second of a bomb.
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

/// @desc The grace dial round the player: a faint full circle and a bright
///       arc for the share of grace left, sweeping back to noon, with a bloom
///       on its head. It tightens as it empties and flickers toward the hit
///       colour inside `GRACE_URGENT`. Additive, never filled.
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

    // The whole grace, faintly.
    draw_arc_band(_p.x, _p.y, _rad - 1.5, _rad + 1.5, 0, 360, _col,
                  0.12 * _p.grace_show, 0.12 * _p.grace_show, 60);

    if (_frac > 0.001) {
        // What is left: a soft halo and a bright core.
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

/// @desc The hitbox, shown only while focused, drawn at exactly `PLAYER_R`.
///       Its own function because it is drawn after the bullets.
function player_draw_hitbox(_p) {
    if (!_p.alive || !_p.focus || _p.entry > 0) return;
    var _hs = (PLAYER_R * 2) / sprite_get_width(spr_hitbox);
    draw_sprite_ext(spr_hitbox, 0, _p.x, _p.y, _hs, _hs, 0, c_white, 1);
}

/// @desc The player's shots, additive: a bloom under each, then the flame
///       sprite. `spr_pshot` has its colours baked in and is drawn `c_white`
///       (a tint would multiply the white core away); each shot starts at its
///       own animation phase.
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

/// @desc The special's visuals: the sigil (its rim is exactly where the sweep
///       is erasing bullets, anchored at the cast point), the flaming front of
///       the sweep, the heart that fills and lets go, and the seals. All
///       additive.
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
        // The rim follows the sweep while it grows, then drifts out a little
        // as it dissolves...
        var _grow = min(1, _e / BOMB_GROW);
        var _rad = BOMB_CLEAR_R * _grow
                 * (1 + 0.08 * clamp((_e - 74) / 42.0, 0, 1));
        // ...and draws in slightly just before the seals leave.
        _rad *= 1 - 0.035 * clamp((_e - 26) / (BOMB_SEAL_AT - 26.0), 0, 1)
                * clamp((BOMB_SEAL_AT + 8 - _e) / 8.0, 0, 1);
        // The sprite's outer ring sits 494 of its 512 half-pixels out.
        var _sc = _rad / 494 * (sprite_get_width(spr_fx_sigil) / 1024.0);
        // A flare on the frame the heart lets go.
        var _pulse = 1 + 0.5 * max(0, 1 - abs(_e - BOMB_SEAL_AT) / 10.0);

        // Three layers turning at three rates: rings, script, emblem.
        var _spin = _e * 0.55 + (1 - _grow) * 60;
        draw_sprite_ext(spr_fx_sigil, 0, _bx, _by, _sc, _sc, _spin,
                        COL_SIGIL, 0.85 * _fade * _pulse);
        var _in1 = min(1, max(0, _e - 5) / 14.0);
        draw_sprite_ext(spr_fx_sigil, 1, _bx, _by, _sc * _in1, _sc * _in1,
                        -_e * 0.95, COL_RUNE, 0.9 * _fade * _in1 * _pulse);
        var _in2 = min(1, max(0, _e - 10) / 12.0);
        // The emblem overshoots and settles.
        var _os = _sc * _in2 * (1 + 0.16 * (1 - _in2));
        draw_sprite_ext(spr_fx_sigil, 2, _bx, _by, _os, _os, _e * 0.22,
                        merge_colour(COL_SIGIL, c_white, 0.55),
                        0.9 * _fade * _in2 * _pulse);
        // A faint glow inside the circle.
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
        // 32 flame tongues round the rim, heads outward, each on its own
        // animation frame.
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
    // Fills as the stolen motes arrive and flares when the seals leave.
    var _gather = clamp((_e - 4) / max(1, BOMB_SEAL_AT - 4.0), 0, 1);
    var _after = max(0, 1 - max(0, _e - BOMB_SEAL_AT) / 26.0);
    var _heart = (_e < BOMB_SEAL_AT) ? _gather : _after;
    if (_heart > 0.01) {
        var _pop = 1 + 1.6 * max(0, 1 - abs(_e - BOMB_SEAL_AT) / 8.0);
        var _bw = sprite_get_width(spr_fx_bloom);
        // Drawn directly rather than with `draw_bloom`, which resets the blend
        // mode.
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
        // A turning copy of the sigil's emblem at each seal's heart.
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

/// @desc His close-up on the GUI layer while the special goes off, through the
///       same `draw_eye_card` a boss's spell uses.
function player_draw_card(_p) {
    if (_p.card_t <= 0) return;
    draw_eye_card(spr_eye_szuix, _p.card_t / PLAYER_CARD_TIME);
}
