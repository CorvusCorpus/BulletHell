/// @desc The shards enemies drop, and how they reach the player.
///
/// Red is health, blue is special, gold is points. **One point each**, which
/// is the whole reason a shard is worth picking up in a game with a hundred-
/// point bar: a hit costs twenty-five and the field gives back one at a time,
/// so recovering from a hit is something you spend a minute doing rather than
/// something a single drop undoes.
///
/// They arc up and then fall, which is Touhou's shape and is not arbitrary: an
/// item that fell straight down from where the enemy died would be collected
/// by standing where you were already standing, and the little arc is what
/// makes going and getting it a decision.

function item_init() {
    global.items = [];
    global.item_n = 0;
    global.item_auto = false;      // set while everything is being pulled in
}

function item_blank() {
    return {
        x: 0, y: 0, vx: 0, vy: 0, kind: ItemKind.Tally, t: 0, drawn: 0,
        homing: false,
    };
}

function item_alloc() {
    if (global.item_n >= ITEM_MAX) return undefined;
    var _i = global.item_n;
    if (_i >= array_length(global.items)) {
        array_push(global.items, item_blank());
    }
    global.item_n = _i + 1;
    return global.items[_i];
}

function item_kill_at(_i) {
    var _last = global.item_n - 1;
    if (_i != _last) {
        var _t = global.items[_i];
        global.items[_i] = global.items[_last];
        global.items[_last] = _t;
    }
    global.item_n = _last;
}

function item_count() {
    return global.item_n;
}

/// @desc Drop one shard.
function item_spawn(_x, _y, _kind, _vx = undefined, _vy = undefined) {
    var _it = item_alloc();
    if (_it == undefined) return undefined;
    _it.x = _x;
    _it.y = _y;
    _it.vx = (_vx == undefined) ? random_range(-1.6, 1.6) : _vx;
    _it.vy = (_vy == undefined) ? random_range(-5.2, -2.6) : _vy;
    _it.kind = _kind;
    _it.t = 0;
    _it.drawn = 0;
    _it.homing = false;
    return _it;
}

/// @desc What a dead enemy leaves behind.
function item_drop_spread(_x, _y, _red, _blue, _gold) {
    for (var _i = 0; _i < _red; _i++)  item_spawn(_x, _y, ItemKind.Health);
    for (var _i = 0; _i < _blue; _i++) item_spawn(_x, _y, ItemKind.Mana);
    for (var _i = 0; _i < _gold; _i++) item_spawn(_x, _y, ItemKind.Tally);
}

/// @desc Advance every shard, and hand the player what it caught.
///       Returns a struct counting what was collected this frame, so the
///       caller does the applying -- which keeps this function pure enough to
///       assert on and keeps every change to the player's numbers in one file.
function item_step(_px, _py) {
    var _got = { hp: 0, mp: 0, tally: 0, n: 0 };

    // **Above the line, everything comes to you.** The point of collection: it
    // is the one thing in the genre that rewards flying up into the pattern,
    // and taking it out would leave no reason ever to go there.
    var _auto = global.item_auto || (_py < ITEM_AUTO_LINE);

    for (var _i = global.item_n - 1; _i >= 0; _i--) {
        var _it = global.items[_i];
        _it.t++;

        var _d = point_distance(_it.x, _it.y, _px, _py);
        if (_auto || _d < ITEM_MAGNET_R) _it.homing = true;

        if (_it.homing) {
            var _dir = point_direction(_it.x, _it.y, _px, _py);
            // Accelerates the closer it gets, so the last stretch snaps in
            // rather than drifting -- collection has to feel like a catch.
            var _spd = ITEM_MAGNET_SPD * (1 + 0.9 * (1 - min(1, _d / ITEM_MAGNET_R)));
            _it.vx = lengthdir_x(_spd, _dir);
            _it.vy = lengthdir_y(_spd, _dir);
        } else {
            _it.vy = min(_it.vy + ITEM_GRAVITY, ITEM_TERMINAL);
            _it.vx *= 0.99;
        }

        _it.x += _it.vx;
        _it.y += _it.vy;

        if (_d < ITEM_R) {
            switch (_it.kind) {
                case ItemKind.Health: _got.hp += ITEM_HP_VALUE; break;
                case ItemKind.Mana:   _got.mp += ITEM_MP_VALUE; break;
            }
            _got.tally += TALLY_ITEM;
            _got.n++;
            fx_spark(_it.x, _it.y, random(360), 2, item_colour(_it.kind), 16, 14);
            item_kill_at(_i);
            continue;
        }

        // Off the bottom, or simply too old. Not off the top: a shard thrown
        // hard by a dying boss goes up before it comes down, and killing it up
        // there would eat the drop.
        if (_it.y > FIELD_Y1 + 80 || _it.t > ITEM_LIFE) {
            item_kill_at(_i);
        }
    }
    return _got;
}

function item_colour(_kind) {
    switch (_kind) {
        case ItemKind.Health: return COL_LIFE;
        case ItemKind.Mana:   return COL_MANA;
    }
    return COL_GRAZE;
}

function item_sprite(_kind) {
    switch (_kind) {
        case ItemKind.Health: return spr_item_red;
        case ItemKind.Mana:   return spr_item_blue;
    }
    return spr_item_gold;
}

function item_clear_all() {
    global.item_n = 0;
}

function item_draw() {
    for (var _i = 0; _i < global.item_n; _i++) {
        var _it = global.items[_i];
        // A slow bob, out of phase per shard from its own age, so a shower of
        // them glitters instead of pulsing as one.
        var _s = 1 + 0.08 * dsin(_it.t * 5 + _i * 37);
        draw_sprite_ext(item_sprite(_it.kind), 0, _it.x, _it.y, _s, _s,
                        dsin(_it.t * 2.2) * 8, c_white, 1);
    }

    // A soft light under each, additive, so a field of shards glows the way a
    // field of bullets does and the two read as the same world.
    gpu_set_blendmode(bm_add);
    for (var _i = 0; _i < global.item_n; _i++) {
        var _it = global.items[_i];
        var _s = 46 / sprite_get_width(spr_fx_bloom);
        draw_sprite_ext(spr_fx_bloom, 0, _it.x, _it.y, _s, _s, 0,
                        item_colour(_it.kind), 0.34);
    }
    gpu_set_blendmode(bm_normal);
}
