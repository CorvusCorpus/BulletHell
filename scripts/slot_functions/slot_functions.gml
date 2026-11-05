/// @desc Slot tables: a boss's fight written as one row per attack in fight
///       order, from which its phase table is derived. A slot not yet
///       written is a placeholder row (`slot_n`, `slot_s`), so every boss on
///       the roster has its whole fight laid out and each slot can be written
///       in turn by replacing its row.
///
/// A row is `{name, col, hp, time, attack, bg?, move?, at?, hold?,
/// hold_from?, fire_at?, par?, score?, survival?}`, as in Mika's table
/// (`mika_slots`, which has its own derivation). A name makes it a spell.
/// `bg` is a spell's background wash, its `col` if it gives none. `hp` is
/// the slot's health; the boss's total and every threshold are summed from
/// it, so retuning one slot moves nothing else.
///
/// Ziggy's, Velka's and the unbuilt stages' bosses (`roster_slots`) are
/// written this way.

// A placeholder slot's health and clock: about ten seconds of full fire
// (`rank_full_fire`) for a non-spell and fifteen for a spell.
#macro SLOT_STUB_N_HP 300
#macro SLOT_STUB_S_HP 450
#macro SLOT_STUB_N_TIME (24 * FPS)
#macro SLOT_STUB_S_TIME (40 * FPS)

// A placeholder slot's hue (as Mika's unwritten slots).
#macro SLOT_STUB_COL BCOL_BONE

// ---------------------------------------------------------------------------
// Placeholder rows
// ---------------------------------------------------------------------------

/// @desc Placeholder row for non-spell `N_k`.
function slot_n(_k) {
    return {
        slot: "N" + string(_k),
        name: "",
        col: SLOT_STUB_COL,
        hp: SLOT_STUB_N_HP,
        time: SLOT_STUB_N_TIME,
        attack: slot_stub_nonspell,
    };
}

/// @desc Placeholder row for spell `S_k`, named `Placeholder Spell k`.
function slot_s(_k) {
    return {
        slot: "S" + string(_k),
        name: "Placeholder Spell " + string(_k),
        col: SLOT_STUB_COL,
        hp: SLOT_STUB_S_HP,
        time: SLOT_STUB_S_TIME,
        attack: slot_stub_spell,
    };
}

/// @desc Placeholder non-spell: an aimed fan on a beat.
function slot_stub_nonspell(_e, _g, _t) {
    if ((_t mod 50) == 20) {
        fire_fan(_e.x, _e.y, 5, 5.0,
                 aim_at(_e.x, _e.y, _g.player.x, _g.player.y), 40,
                 BSHAPE_RICE, SLOT_STUB_COL, 18);
    }
}

/// @desc Placeholder spell: a slow turning ring and an aimed stack.
function slot_stub_spell(_e, _g, _t) {
    if ((_t mod 50) == 20) {
        fire_ring(_e.x, _e.y, 16, 3.8, _t * 3.3, BSHAPE_ORB, SLOT_STUB_COL,
                  20);
    }
    if ((_t mod 100) == 70) {
        fire_stack(_e.x, _e.y, 3, 6.0, 1.4,
                   aim_at(_e.x, _e.y, _g.player.x, _g.player.y),
                   BSHAPE_KNIFE, SLOT_STUB_COL, 18);
    }
}

// ---------------------------------------------------------------------------
// From a table to a fight
// ---------------------------------------------------------------------------

/// @desc A boss's whole health: every slot's, summed.
function slot_hp(_slots) {
    var _sum = 0;
    for (var _i = 0; _i < array_length(_slots); _i++) _sum += _slots[_i].hp;
    return _sum;
}

/// @desc The phase table derived from a slot table. Built fresh on every
///       call, because phase structs are mutable.
function slot_phases(_slots) {
    var _n = array_length(_slots);
    var _total = max(1, slot_hp(_slots));
    var _left = _total;
    var _out = [];
    for (var _i = 0; _i < _n; _i++) {
        var _s = _slots[_i];
        var _spell = (_s.name != "");
        _left -= _s.hp;
        array_push(_out, {
            kind: _spell ? AttackKind.Spell : AttackKind.NonSpell,
            name: _s.name,
            col: _s.col,
            bg: _spell ? (_s[$ "bg"] ?? _s.col) : -1,
            hp_end: (_i == _n - 1) ? 0 : _left / _total,
            time: _s.time,
            move: _s[$ "move"] ?? BossMove.Drift,
            at: _s[$ "at"],
            hold: _s[$ "hold"],
            hold_from: _s[$ "hold_from"],
            attack: _s.attack,
            fire_at: _s[$ "fire_at"] ?? 0,
            par: _s[$ "par"],
            score: _s[$ "score"],
            survival: _s[$ "survival"],
        });
    }
    return _out;
}

/// @desc A boss with no art of its own yet. Placeholders: Ziggy's sprite,
///       Mika's cut-in portrait and the generic spell background.
function slot_boss_def(_name, _title, _col) {
    return {
        name: _name,
        title: _title,
        sprite: spr_boss_ziggy,
        cutin: spr_cutin_mika,
        col: _col,
        radius: 62,
        spell_bg: SPELLBG_SIGIL,
        final: true,
    };
}

/// @desc A stage def's `bosses` entry (`{name, spawn, phases}`) for a boss
///       given by its def function and its slot table function.
function slot_boss(_def_fn, _slots_fn) {
    return {
        name: _def_fn().name,
        spawn: method({ def_fn: _def_fn, slots_fn: _slots_fn },
                      function(_g) {
            // Called through locals: `check_unknown_functions` can't tell a
            // bare call to a struct member from an unknown function.
            var _d = def_fn;
            var _s = slots_fn;
            var _slots = _s();
            var _b = boss_spawn(FIELD_CX, FIELD_Y0 - 200, slot_hp(_slots),
                                slot_phases(_slots), _d());
            if (_b != undefined) _b.boss.home_y = BOSS_HOME_Y;
            return _b;
        }),
        phases: method({ slots_fn: _slots_fn }, function() {
            var _s = slots_fn;
            return slot_phases(_s());
        }),
    };
}
