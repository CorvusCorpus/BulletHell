/// @desc The fodder: what it is, how it moves, and what it leaves behind.
///
/// **Nothing in a wave is a creature.** The stage is full of animated objects
/// -- a wisp, a grimoire, a cut gem, a stone sentry -- and that is a story
/// decision as much as an art one: this is a game about an imp who is sick of
/// being somebody's trash mob, so filling his stages with trash mobs that are
/// people would say the opposite of what the game is about. What he cuts
/// through is somebody's *furniture*.
///
/// An enemy carries its behaviour as a function on the struct, called once a
/// frame with itself and the run. That is the same shape `puzzle_functions` in
/// the Wordsearch project uses for a puzzle's solution: the data describes
/// what happens, and the engine only knows how to run it.

function enemy_init() {
    global.enemies = [];
    global.enemy_n = 0;
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
    _e.leaving = false;
    _e.touch = true;
    _e.scale = 1;
    return _e;
}

/// @desc How big a piece of fodder is, for both hitting it and being hit by
///       it.
///
///       **These moved when the art did**, and they have to: the number is a
///       promise about where the drawn shape is, and a 136-pixel sentry with a
///       40-pixel radius is a sentry the player can stand inside. Every one of
///       them is a little under half the sprite's width, which is the same
///       bargain the bullets make -- generous to the player when they are
///       shooting it and generous again when they are dodging it.
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
// Movement, as reusable pieces
//
// A wave's behaviour is nearly always "come in, do something for a while, go
// away". These are the three parts of that, written so a stage can compose
// them without every wave carrying a copy of the same easing.
// ---------------------------------------------------------------------------

/// @desc Ease toward a point, arriving over `_frames`. Returns true once it
///       has arrived, which is what a wave's `act` switches on.
///
///       **Eased, not linear.** An enemy that flies in at constant speed and
///       stops dead has no weight; decelerating into the hold is most of what
///       makes a wave look choreographed rather than spawned.
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

/// @desc Send an enemy away. It stops firing, stops being worth points, and
///       leaves -- which is how a wave ends when its time is up rather than
///       when it is dead.
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

/// @desc Player shots against enemies. Returns the tally earned.
///
///       O(shots x enemies) and unashamedly so: there are five hundred shots
///       at the very most and rarely more than a dozen enemies, which is a few
///       thousand distance checks -- against the four thousand the bullet pool
///       already does every frame for one player. A spatial index here would
///       be code to maintain in exchange for nothing measurable.
function enemy_take_shots(_g) {
    var _earned = 0;
    for (var _s = global.pshot_n - 1; _s >= 0; _s--) {
        var _sh = global.pshots[_s];
        for (var _i = global.enemy_n - 1; _i >= 0; _i--) {
            var _e = global.enemies[_i];
            if (_e.leaving) continue;
            // **A boss in ceremony takes no damage, and this is the line that
            // says so.** `boss_vulnerable` has always described the rule --
            // false through the arrival, the declaration and the pause between
            // attacks -- and until now nothing read it outside the suites, so
            // a player holding the shot button chipped the boss through every
            // piece of it. In a fight that is a second and a half of free
            // damage against the *next* attack's threshold, which is exactly
            // what the rule exists to prevent; in attack practice it is three
            // seconds against a bar deliberately set to where the attack
            // begins, which would eat a sixth of the thing being practised.
            //
            // The shot passes through rather than being absorbed, on the same
            // terms as `leaving` above: nothing happened, so nothing is drawn
            // to say it did.
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

/// @desc The bomb's seals against enemies. Returns the tally earned.
///
///       **Written beside `enemy_take_shots` and not inside the player**,
///       because everything it has to do -- find the enemy, spend its health,
///       kill it, pay for it -- is this file's business and none of it is the
///       player's. The player owns where a seal *is*; the pool owns what it
///       hits.
///
///       Swept like a shot, against the segment the seal travelled rather
///       than the point it ended on: a seal moves twenty-four pixels a frame
///       and a wisp of fire that passes through a boss without touching it is
///       the same bug the bullets' swept test exists for.
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
        // A boss does not die here; it runs out of a *phase*. `boss_step`
        // owns that, and it owns it because the phase table is the only thing
        // that knows whether the fight is over.
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

/// @desc Send every fodder enemy away and give up their drops. What the end of
///       a stage section does, so the boss arrives on a clean field without
///       the player being robbed of the kills they were owed.
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

/// @desc Draw every enemy on the field.
///
///       **Including the bosses, which is the fix for a boss that could be
///       alive, lethal and invisible at the same time.** This used to skip
///       anything carrying a `boss` struct on the grounds that "the boss draws
///       itself", and the controller drew it -- through `boss_ref`, the run's
///       reference to *the boss it is currently fighting*.
///
///       Those are not the same set. A boss enemy that `boss_ref` does not
///       point at was drawn by nobody, and there are two ordinary ways to have
///       one: the midboss keeps flying after `boss_ref` is released, so it
///       departed invisibly rather than "leaving under its own power" as it is
///       supposed to; and a boss left in the pool by a run that did not clean
///       up after itself is invisible for the whole of the next one, while
///       still firing and still solid to the touch.
///
///       Drawing straight out of the pool makes both impossible. The pool is
///       what exists; the pool is what is drawn; and the controller's opinion
///       about which boss is interesting has nothing to do with it.
function enemy_draw() {
    for (var _i = 0; _i < global.enemy_n; _i++) {
        var _e = global.enemies[_i];
        if (_e.boss != undefined) {
            // A boss carries a sigil and an aura no piece of fodder has, so it
            // has its own routine -- but it is reached from here.
            boss_draw(_e);
            continue;
        }

        var _spr = enemy_sprite(_e.kind);
        var _n = sprite_get_number(_spr);
        var _fr = ((_e.t div 6) mod _n);
        var _col = global.bullet_colour[_e.col];

        // A light under it, so fodder glows like everything else on the field
        // and does not read as a sticker on the background.
        gpu_set_blendmode(bm_add);
        var _gs = (_e.r * 3.4) / sprite_get_width(spr_fx_bloom);
        draw_sprite_ext(spr_fx_bloom, 0, _e.x, _e.y, _gs, _gs, 0, _col, 0.32);
        gpu_set_blendmode(bm_normal);

        draw_sprite_ext(_spr, _fr, _e.x, _e.y, _e.scale, _e.scale,
                        dsin(_e.t * 2) * 4, _col, _e.leaving ? 0.6 : 1);

        // **Hit feedback is additive white on top, not a blend to white.** A
        // blend loses the silhouette against a bright background at exactly
        // the moment the player most wants to know they are hitting something.
        if (_e.flash > 0) {
            gpu_set_blendmode(bm_add);
            draw_sprite_ext(_spr, _fr, _e.x, _e.y, _e.scale, _e.scale,
                            dsin(_e.t * 2) * 4, c_white,
                            _e.flash / ENEMY_FLASH * 0.85);
            gpu_set_blendmode(bm_normal);
        }
    }
}
