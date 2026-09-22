/// @desc The attack list for attack practice: every attack of every boss on
///       the stage chosen on the rack (`global.stage_def`), as one scrolling
///       list with a heading per boss.

stage = global.stage_def ?? stage_ziggy_def();
bosses = practice_bosses(stage);

// Headings and attacks in one array of rows.
rows = [];
picks = [];        // which entries in `rows` the cursor may land on
for (var _b = 0; _b < array_length(bosses); _b++) {
    var _boss = bosses[_b];
    var _phases = _boss.phases();
    array_push(rows, { header: true, boss_i: _b, phase_i: -1,
                       label: _boss.name, spell: false, col: BCOL_EMBER,
                       time: 0, hp_from: 1, hp_to: 1 });
    var _from = 1.0;
    for (var _i = 0; _i < array_length(_phases); _i++) {
        var _p = _phases[_i];
        array_push(picks, array_length(rows));
        array_push(rows, {
            header: false, boss_i: _b, phase_i: _i,
            label: practice_attack_label(_boss, _phases, _i),
            spell: (_p.kind == AttackKind.Spell),
            col: _p.col,
            time: _p.time,
            // The span of the boss's health bar this attack occupies.
            hp_from: _from,
            hp_to: _p.hp_end,
        });
        _from = _p.hp_end;
    }
}

// Start on the attack practised last, if any.
pick = 0;
var _was = global.practice;
if (_was != undefined) {
    for (var _i = 0; _i < array_length(picks); _i++) {
        var _r = rows[picks[_i]];
        if (_r.boss_i == _was.boss_i && _r.phase_i == _was.phase_i) pick = _i;
    }
}
cursor = pick;
t = 0;
enter_t = 0;

// ---- row layout, shared by Step (scrolling) and Draw ----------------------
//
// `row_y` is each row's centre relative to the first row's; headings after
// the first get extra space above them.
row_pitch = 52;
row_head = 74;
list_top = 220 + 66;              // the first row's centre, on screen
row_y = [];
var _y = 0;
for (var _i = 0; _i < array_length(rows); _i++) {
    if (rows[_i].header && _i > 0) _y += row_head - row_pitch;
    row_y[_i] = _y;
    _y += rows[_i].header ? row_head : row_pitch;
}
list_span = (array_length(rows) > 0) ? row_y[array_length(rows) - 1] : 0;

// How much of the list the plate can show (the plate ends 150px above the
// bottom of the screen; the last visible row centre is 40px inside it).
list_window = min(list_span, (GAME_H - 150 - 40) - list_top);

// Start already scrolled to the cursor.
scroll_want = (array_length(picks) > 0)
    ? practice_list_scroll(0, row_y[picks[pick]], list_span, list_window,
                           row_head + 26)
    : 0;
scroll = scroll_want;

// The stage's own background (unbuilt stages have no `make_bg`).
bg = (stage.make_bg != undefined) ? stage.make_bg() : bg_brimstone();
