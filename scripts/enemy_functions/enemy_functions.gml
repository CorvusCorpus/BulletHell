/// @desc The enemy pool (fodder and bosses): spawning, movement helpers,
///       damage, death and drawing.
///
/// Wave enemies are animated objects (a wisp, a grimoire, a cut gem, a stone
/// sentry), never creatures -- the owner's story decision. An enemy carries
/// its behaviour as `act(self, g)`, called once a frame.

function enemy_init() {
    global.enemies = [];
    global.enemy_n = 0;
    // Running total of what every spawned piece of fodder is worth if killed
    // and collected. Read as a difference by `stage_encounter_close`.
    global.enemy_worth = 0;
}

function enemy_blank() {
    return {
        x: 0, y: 0, vx: 0, vy: 0,
        hp: 10, hp_max: 10, r: 26,
        kind: EnemyKind.Wisp,
        col: BCOL_CYAN,
        t: 0,
        flash: 0,
        act: undefined,          // called every frame: act(self, g)
        mem: undefined,          // whatever `act` wants to remember
        red: 0, blue: 0, gold: 0,
        boss: undefined,         // set only on a boss
        leaving: false,
        touch: true,             // does the body hurt the player?
        scale: 1,
    };
}

function enemy_alloc() {
    if (global.enemy_n >= ENEMY_MAX) return undefined;
    var _i = global.enemy_n;
    if (_i >= array_length(global.enemies)) {
        array_push(global.enemies, enemy_blank());
    }
    global.enemy_n = _i + 1;
    return global.enemies[_i];
}

function enemy_kill_at(_i) {
    var _last = global.enemy_n - 1;
    if (_i != _last) {
        var _t = global.enemies[_i];
        global.enemies[_i] = global.enemies[_last];
        global.enemies[_last] = _t;
    }
    global.enemy_n = _last;
}

function enemy_count() {
    return global.enemy_n;
}

/// @desc How many enemies are on the field that are not the boss. What a
///       "wait until the wave is dead" gate in a stage script asks about.
function enemy_count_fodder() {
    var _n = 0;
    for (var _i = 0; _i < global.enemy_n; _i++) {
        if (global.enemies[_i].boss == undefined) _n++;
    }
    return _n;
}

/// @desc Put an enemy on the field.
/// @param {function} _act  called every frame as `_act(enemy, g)`
function enemy_spawn(_kind, _x, _y, _hp, _act, _col = BCOL_CYAN,
                     _red = 0, _blue = 1, _gold = 2) {
    var _e = enemy_alloc();
    if (_e == undefined) return undefined;
    _e.x = _x; _e.y = _y;
    _e.vx = 0; _e.vy = 0;
    _e.hp = _hp; _e.hp_max = _hp;
    _e.r = enemy_radius(_kind);
    _e.kind = _kind;
    _e.col = _col;
    _e.t = 0;
    _e.flash = 0;
    _e.act = _act;
    _e.mem = {};
    _e.red = _red; _e.blue = _blue; _e.gold = _gold;
    _e.boss = undefined;
    // Counted here so any wave shape is graded without reporting anything.
    // Bosses pay out through their phase tables instead.
    if (_kind != EnemyKind.Boss) {
        global.enemy_worth += TALLY_ENEMY + _gold * TALLY_ITEM;
    }
    _e.leaving = false;
    _e.touch = true;
    _e.scale = 1;
    return _e;
}

/// @desc Hit radius for each kind, used both for shooting it and for touching
///       it. Roughly half the sprite's width; update it if the art changes size.
function enemy_radius(_kind) {
    switch (_kind) {
        case EnemyKind.Wisp:     return 30;
        case EnemyKind.Grimoire: return 44;
        case EnemyKind.Gem:      return 36;
        case EnemyKind.Sentry:   return 52;
        case EnemyKind.Boss:     return 62;
    }
    return 32;
}

function enemy_sprite(_kind) {
    switch (_kind) {
        case EnemyKind.Wisp:     return spr_foe_wisp;
        case EnemyKind.Grimoire: return spr_foe_grimoire;
        case EnemyKind.Gem:      return spr_foe_gem;
        case EnemyKind.Sentry:   return spr_foe_sentry;
    }
    return spr_foe_wisp;
}

// ---------------------------------------------------------------------------
// Movement helpers for wave behaviours: come in, act, leave.
// ---------------------------------------------------------------------------

/// @desc Ease toward a point by `_rate` of the remaining distance each frame.
///       Returns true once within 3px.
function enemy_glide(_e, _tx, _ty, _rate = 0.075) {
    _e.x += (_tx - _e.x) * _rate;
    _e.y += (_ty - _e.y) * _rate;
    return point_distance(_e.x, _e.y, _tx, _ty) < 3;
}

/// @desc Drift on a line, forever. The simplest wave there is.
function enemy_drift(_e, _dir, _spd) {
    _e.x += lengthdir_x(_spd, _dir);
    _e.y += lengthdir_y(_spd, _dir);
}

/// @desc A sine weave across the screen -- the standard "swaying fodder".
function enemy_weave(_e, _dir, _spd, _amp, _period) {
    var _side = _dir + 90;
    var _sway = dcos(_e.t * (360 / _period)) * _amp * (360 / _period) * 0.01745;
    _e.x += lengthdir_x(_spd, _dir) + lengthdir_x(_sway, _side);
    _e.y += lengthdir_y(_spd, _dir) + lengthdir_y(_sway, _side);
}

/// @desc Send an enemy off in a straight line: it stops acting, can't be
///       shot or touched, and is culled once off the field.
function enemy_leave(_e, _dir = 270) {
    _e.leaving = true;
    _e.touch = false;
    _e.vx = lengthdir_x(4.5, _dir);
    _e.vy = lengthdir_y(4.5, _dir);
}

// ---------------------------------------------------------------------------
// The step
// ---------------------------------------------------------------------------

function enemy_step(_g) {
    var _l = FIELD_X0 - CULL_MARGIN - 120;
    var _r = FIELD_X1 + CULL_MARGIN + 120;
    // Deeper above than to the sides, because a wave scripted to fly in from
    // the top has to exist off screen before it arrives.
    var _t = FIELD_Y0 - CULL_MARGIN - 220;
    var _b = FIELD_Y1 + CULL_MARGIN + 120;

    for (var _i = global.enemy_n - 1; _i >= 0; _i--) {
        var _e = global.enemies[_i];
        if (_e.flash > 0) _e.flash--;

        if (_e.leaving) {
            _e.x += _e.vx;
            _e.y += _e.vy;
        } else if (_e.act != undefined) {
            _e.act(_e, _g);
        }
        _e.t++;

        if (_e.x < _l || _e.x > _r || _e.y < _t || _e.y > _b) {
            enemy_kill_at(_i);
        }
    }
}

/// @desc Player shots against enemies (swept, like bullets against the
///       player). Returns the tally earned. O(shots x enemies), which is cheap
///       at these counts.
function enemy_take_shots(_g) {
    var _earned = 0;
    for (var _s = global.pshot_n - 1; _s >= 0; _s--) {
        var _sh = global.pshots[_s];
        for (var _i = global.enemy_n - 1; _i >= 0; _i--) {
            var _e = global.enemies[_i];
            if (_e.leaving) continue;
            // A boss can't be damaged during its arrival, a spell
            // declaration or the pause between attacks (`boss_vulnerable`).
            // The shot passes through.
            if (_e.boss != undefined && !boss_vulnerable(_e)) continue;
            if (point_seg_dist(_e.x, _e.y, _sh.px, _sh.py, _sh.x, _sh.y) > _e.r) {
                continue;
            }

            _e.hp -= _sh.dmg;
            _e.flash = ENEMY_FLASH;
            sfx(Sfx.EnemyHit);
            fx_spark(_sh.x, _sh.y, _sh.dir + 180 + random_range(-40, 40),
                     random_range(1, 3.4), COL_SZUIX_LIT, 10, 12);
            pshot_kill_at(_s);

            if (_e.hp <= 0) {
                _earned += enemy_die(_e, _g);
                if (_e.boss == undefined) enemy_kill_at(_i);
            }
            break;      // one shot hits one enemy
        }
    }
    return _earned;
}

/// @desc The bomb's seals against enemies, swept along each seal's path like
///       a shot. Returns the tally earned.
function enemy_take_seals(_p, _g) {
    var _earned = 0;
    var _seals = _p.seals;
    for (var _k = 0; _k < array_length(_seals); _k++) {
        var _s = _seals[_k];
        if (!_s.live) continue;
        for (var _i = global.enemy_n - 1; _i >= 0; _i--) {
            var _e = global.enemies[_i];
            if (_e.leaving) continue;
            // A boss in ceremony takes nothing, exactly as it takes no shots.
            if (_e.boss != undefined && !boss_vulnerable(_e)) continue;
            if (point_seg_dist(_e.x, _e.y, _s.px, _s.py, _s.x, _s.y)
                > _e.r + BOMB_SEAL_R) {
                continue;
            }

            _e.hp -= BOMB_SEAL_DMG;
            _e.flash = ENEMY_FLASH;
            player_seal_burst(_s);
            if (_e.hp <= 0) {
                _earned += enemy_die(_e, _g);
                if (_e.boss == undefined) enemy_kill_at(_i);
            }
            break;      // one seal strikes one thing, and is spent on it
        }
    }
    return _earned;
}

/// @desc What happens when something runs out of health.
function enemy_die(_e, _g) {
    if (_e.boss != undefined) {
        // A boss ends phases instead; `boss_step` handles that.
        return 0;
    }
    var _col = global.bullet_colour[_e.col];
    sfx(Sfx.EnemyDie);
    fx_burst(_e.x, _e.y, ENEMY_DEATH_BITS, 2, 8, _col, 26, 16);
    fx_ring(_e.x, _e.y, 8, 84, 20, _col, 0.8);
    fx_flash_at(_e.x, _e.y, _col, 0.18);
    item_drop_spread(_e.x, _e.y, _e.red, _e.blue, _e.gold);
    return TALLY_ENEMY;
}

/// @desc Does any enemy's body overlap this circle? Bosses included -- flying
///       into one is the same mistake as flying into a bullet.
function enemy_body_hit(_x, _y, _rad) {
    for (var _i = 0; _i < global.enemy_n; _i++) {
        var _e = global.enemies[_i];
        if (!_e.touch || _e.leaving) continue;
        if (point_distance(_x, _y, _e.x, _e.y) < _rad + _e.r * 0.55) {
            return true;
        }
    }
    return false;
}

/// @desc The boss, if one is on the field.
function enemy_find_boss() {
    for (var _i = 0; _i < global.enemy_n; _i++) {
        if (global.enemies[_i].boss != undefined) return global.enemies[_i];
    }
    return undefined;
}

function enemy_clear_all() {
    global.enemy_n = 0;
}

/// @desc Kill every fodder enemy, dropping its items (`wave_sweep_field`).
function enemy_sweep_fodder(_g) {
    for (var _i = global.enemy_n - 1; _i >= 0; _i--) {
        var _e = global.enemies[_i];
        if (_e.boss != undefined) continue;
        enemy_die(_e, _g);
        enemy_kill_at(_i);
    }
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// @desc Draw every enemy in the pool, bosses included. Bosses are drawn from
///       the pool rather than through `boss_ref`, so a departing midboss (no
///       longer referenced) is still drawn.
function enemy_draw() {
    for (var _i = 0; _i < global.enemy_n; _i++) {
        var _e = global.enemies[_i];
        if (_e.boss != undefined) {
            boss_draw(_e);
            continue;
        }

        var _spr = enemy_sprite(_e.kind);
        var _n = sprite_get_number(_spr);
        var _fr = ((_e.t div 6) mod _n);
        var _col = global.bullet_colour[_e.col];

        // A glow under it.
        gpu_set_blendmode(bm_add);
        var _gs = (_e.r * 3.4) / sprite_get_width(spr_fx_bloom);
        draw_sprite_ext(spr_fx_bloom, 0, _e.x, _e.y, _gs, _gs, 0, _col, 0.32);
        gpu_set_blendmode(bm_normal);

        draw_sprite_ext(_spr, _fr, _e.x, _e.y, _e.scale, _e.scale,
                        dsin(_e.t * 2) * 4, _col, _e.leaving ? 0.6 : 1);

        // Hit flash: additive white on top (a blend to white would lose the
        // silhouette on a bright background).
        if (_e.flash > 0) {
            gpu_set_blendmode(bm_add);
            draw_sprite_ext(_spr, _fr, _e.x, _e.y, _e.scale, _e.scale,
                            dsin(_e.t * 2) * 4, c_white,
                            _e.flash / ENEMY_FLASH * 0.85);
            gpu_set_blendmode(bm_normal);
        }
    }
}
