/// @desc The attack list: every attack of every boss on one stage, pick one.
///
/// **It hangs off the rack rather than replacing it**, so it never has to
/// answer "which stage" -- the rack has already answered that, with its locks
/// and its unbuilt cards and its layout that grows by itself when a stage is
/// added. This screen reads `global.stage_def` exactly as `obj_game` does and
/// lists what it finds. See `practice_functions`.
///
/// **One flat list with headings, not a boss picker and an attack picker.**
/// Two cursors is two things to learn and a mode to be in the wrong one of,
/// and the whole list is eleven lines: a stage has a midboss and a boss, and
/// between them nine attacks. When a stage has thirty, the list scrolls -- and
/// that is still one cursor.

stage = global.stage_def ?? stage_ziggy_def();
bosses = practice_bosses(stage);

// The list, built once. **Headings and attacks in one array**, because the
// thing being drawn is one column and the thing being moved through is one
// column; keeping them apart would mean two loops that have to agree about
// where every row is, which is the arithmetic that puts a cursor next to the
// wrong line.
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
            // What span of the bar this attack occupies. It is the one fact
            // about an attack that is invisible from inside it and the first
            // thing anybody tuning the table wants to see -- a phase given
            // five per cent of a boss's health is over before its pattern has
            // finished its first cycle, and the table is the only place that
            // is legible.
            hp_from: _from,
            hp_to: _p.hp_end,
        });
        _from = _p.hp_end;
    }
}

// Land on whichever attack was practised last, so retrying a neighbouring one
// is one keypress rather than a walk back down the list. Zero on the first
// visit, and after `global.practice` has been cleared by anything else.
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

// **The stage's own world behind it**, so the screen is about a place rather
// than about a list. The fallback matters: `make_bg` is `undefined` on every
// unbuilt stage, and a screen reached down some future path with one of those
// selected would otherwise die before its first frame.
bg = (stage.make_bg != undefined) ? stage.make_bg() : bg_brimstone();
