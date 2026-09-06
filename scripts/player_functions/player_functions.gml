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

        // Purely visual. `lean` is where the sprite is banking, and it eases
        // toward where the player is actually going, so a hard left-right
        // reversal reads as a turn rather than as a teleport.
        lean: 0,
        anim: 0,
        entry: 0,         // > 0 while flying in at the start of a stage

        graze_n: 0,
        hit_n: 0,
        bomb_n: 0,
    };
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

/// @desc Is the player untouchable right now?
function player_invulnerable(_p) {
    return _p.iframe > 0 || _p.bomb_t > 0 || _p.entry > 0;
}

/// @desc One frame. `_g` is the controller, for the things a player does that
///       the run has to know about -- banking a tally, starting a bomb.
function player_step(_p, _in, _g) {
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

    // The shot.
    if (_p.shot_t > 0) _p.shot_t--;
    if (_in.shoot && _p.shot_t <= 0) {
        player_fire(_p);
        _p.shot_t = PSHOT_PERIOD;
    }
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
}

/// @desc Cast the special: spend the meter, take the grace, start the sweep.
function player_bomb(_p, _g) {
    _p.mp -= MP_PER_BOMB;
    _p.bomb_t = BOMB_INVULN;
    _p.bomb_x = _p.x;
    _p.bomb_y = _p.y;
    _p.bomb_n++;

    fx_flash_screen(COL_SZUIX_LIT, 0.55);
    fx_shake(16);
    fx_ring(_p.x, _p.y, 40, BOMB_CLEAR_R * 1.15, 46, COL_SZUIX_LIT, 1.0);
    fx_ring(_p.x, _p.y, 20, BOMB_CLEAR_R * 0.7, 30, c_white, 0.7);
    fx_burst(_p.x, _p.y, 40, 4, 15, COL_SZUIX_LIT, 40, 20);
    fx_text(_p.x, _p.y - 90, "SIGIL BREAK", COL_SZUIX_LIT, 60, 1.4);

    if (_g != undefined) _g.tally += 0;   // the bomb is not worth points
}

/// @desc The sweep, one frame of it.
///
///       **It grows rather than clearing everything at once.** A bomb that
///       emptied the screen on its first frame would be a screenshot of an
///       empty screen; growing it over `BOMB_GROW` frames means the player
///       watches the wave reach the bullets, and the bullets it reaches turn
///       into score on the way -- which is what makes bombing under pressure
///       feel like a rescue rather than an admission.
function player_bomb_sweep(_p) {
    var _elapsed = BOMB_INVULN - _p.bomb_t;
    if (_elapsed > BOMB_GROW) return;
    var _r = BOMB_CLEAR_R * (_elapsed / BOMB_GROW);
    bullet_clear_circle(_p.bomb_x, _p.bomb_y, _r, true);
    if (_elapsed == BOMB_GROW) laser_clear_all(true);
}

/// @desc Take a hit. Returns true if it landed, so the caller can react.
function player_hit(_p) {
    if (player_invulnerable(_p) || !_p.alive) return false;

    _p.hp -= HP_PER_HIT;
    _p.iframe = IFRAME_TIME;
    _p.hit_n++;

    fx_flash_screen(COL_LIFE, 0.5);
    fx_shake(20);
    fx_ring(_p.x, _p.y, 10, 300, 34, COL_LIFE, 1.0);
    fx_burst(_p.x, _p.y, 26, 3, 11, COL_LIFE, 34, 18);

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
            + laser_graze(_p.x, _p.y, PLAYER_R);
    if (_gz > 0) {
        _p.graze_n += _gz;
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

/// @desc Draw Szuix, his shots, and the two things that say what state he is
///       in: the hitbox while focused, and the flicker while invulnerable.
function player_draw(_p) {
    if (!_p.alive) return;

    // The flicker. Fast enough to be unmistakable, and never fully off -- a
    // player sprite that vanishes for two frames is a player who has lost
    // track of where they are, which is the opposite of what iframes are for.
    var _a = 1.0;
    if (_p.iframe > 0) _a = 0.45 + 0.35 * dsin(_p.iframe * 34);

    // **A pool of light under him, and it is not decoration.** Szuix is a dark
    // blue sprite and the stages he flies over are dark; photographed on the
    // brimstone stage he very nearly disappeared, which for the one thing on
    // screen the player must never lose track of is a bug rather than a mood.
    // A halo underneath is the genre's own answer -- it separates him from the
    // ground without touching the silhouette the commission drew.
    gpu_set_blendmode(bm_add);
    var _hs = 190 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _p.x, _p.y, _hs, _hs, 0,
                    COL_SZUIX, _p.focus ? 0.30 : 0.40);
    // ...and the exhaust, which is what says which way he is going.
    var _ts = 96 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _p.x, _p.y + 30, _ts, _ts * 1.6, 0,
                    COL_SZUIX_LIT, _p.focus ? 0.34 : 0.55);
    gpu_set_blendmode(bm_normal);

    var _frames = sprite_get_number(spr_szuix);
    var _fr = (_p.anim div 5) mod _frames;
    draw_sprite_ext(spr_szuix, _fr, _p.x, _p.y, 1, 1, -_p.lean * 7,
                    c_white, _a);

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
function pshot_draw() {
    gpu_set_blendmode(bm_add);
    var _gs = 62 / sprite_get_width(spr_fx_bloom);
    for (var _i = 0; _i < global.pshot_n; _i++) {
        var _s = global.pshots[_i];
        draw_sprite_ext(spr_fx_bloom, 0, _s.x, _s.y, _gs, _gs, 0,
                        COL_SZUIX, 0.34);
    }
    for (var _i = 0; _i < global.pshot_n; _i++) {
        var _s = global.pshots[_i];
        draw_sprite_ext(spr_pshot, 0, _s.x, _s.y, 1, 1, _s.dir,
                        COL_SZUIX_LIT, 0.95);
    }
    gpu_set_blendmode(bm_normal);
}

/// @desc The special's wave, while it is growing.
function player_draw_bomb(_p) {
    if (_p.bomb_t <= 0) return;
    var _elapsed = BOMB_INVULN - _p.bomb_t;
    if (_elapsed > BOMB_GROW + 20) return;

    var _t = min(1, _elapsed / BOMB_GROW);
    var _r = BOMB_CLEAR_R * _t;
    gpu_set_blendmode(bm_add);
    var _s = _r * 2 / sprite_get_width(spr_fx_ring);
    draw_sprite_ext(spr_fx_ring, 0, _p.bomb_x, _p.bomb_y, _s, _s, 0,
                    COL_SZUIX_LIT, (1 - _t) * 0.9);
    var _g = _r * 1.6 / sprite_get_width(spr_fx_bloom);
    draw_sprite_ext(spr_fx_bloom, 0, _p.bomb_x, _p.bomb_y, _g, _g, 0,
                    COL_SZUIX, (1 - _t) * 0.5);
    gpu_set_blendmode(bm_normal);
}
