/// @desc Marks: a grade per encounter (each boss attack and each group of
///       waves), and the overall standing they average to.
///
/// Boss attacks are graded by `boss_end_phase`; wave groups by
/// `stage_encounter_close`. A mark starts at `RANK_BASE` (gold) for a clean
/// encounter, loses `RANK_HIT_COST` per hit and `RANK_BOMB_COST` per bomb, and
/// gains one rung for meeting the score threshold. Whether the attack was
/// broken or timed out doesn't affect the mark (the capture bonus covers that).

/// The ladder, bottom to top.
enum Mark {
    Stone,
    Bronze,
    Silver,
    Gold,        // clean: RANK_BASE, and what an encounter starts from
    Amethyst,    // clean, and over the score threshold
    Count,
}

/// @desc What a tier is called.
function mark_name(_t) {
    switch (_t) {
        case Mark.Stone:    return "STONE";
        case Mark.Bronze:   return "BRONZE";
        case Mark.Silver:   return "SILVER";
        case Mark.Gold:     return "GOLD";
        case Mark.Amethyst: return "AMETHYST";
    }
    return "--";
}

/// @desc What a tier is drawn in.
function mark_colour(_t) {
    switch (_t) {
        case Mark.Stone:    return COL_STONE;
        case Mark.Bronze:   return COL_BRONZE;
        case Mark.Silver:   return COL_SILVER;
        case Mark.Gold:     return COL_GRAZE;
        case Mark.Amethyst: return COL_AMETHYST;
    }
    return COL_SLATE;
}

/// @desc A fresh ledger. One per attempt, held on the run.
function rank_ledger_new() {
    return {
        marks: [],       // { label, tier, spell }
        best: -1,        // the highest tier earned, for the flare
        flare: 0,        // set to 1 when a mark lands, and decayed by the HUD
    };
}

/// @desc File a mark (callers: `boss_end_phase`, `stage_encounter_close`).
///       The mark keeps the score, target, hits and bombs that produced it,
///       which the rank card reads.
function rank_note(_ledger, _label, _tier, _spell = false,
                   _earned = 0, _target = 0, _hits = 0, _bombs = 0) {
    if (_ledger == undefined) return;
    array_push(_ledger.marks, {
        label: _label,
        tier: clamp(_tier, 0, Mark.Count - 1),
        spell: _spell,
        earned: _earned,
        target: _target,
        hits: _hits,
        bombs: _bombs,
    });
    _ledger.best = max(_ledger.best, _tier);
    _ledger.flare = 1;
}

/// @desc Grade one encounter: `RANK_BASE`, minus the hit and bomb costs, plus
///       one if the score threshold was met (`_met`).
function rank_for_encounter(_hits, _bombs, _met) {
    var _t = RANK_BASE - _hits * RANK_HIT_COST - _bombs * RANK_BOMB_COST;
    if (_met) _t++;
    return clamp(_t, 0, Mark.Count - 1);
}

/// @desc The score threshold for an encounter's top rung: `_award` (what
///       finishing it pays: an attack's flat clear bonus, or what a wave's
///       enemies are worth) plus `RANK_GRAZE_RATE` grazes a second over
///       `_frames`.
function rank_score_target(_award, _frames) {
    return _award + rank_graze_worth(_frames);
}

/// @desc What grazing at `RANK_GRAZE_RATE` is worth over a span of frames.
///       Shared by the threshold and the speed award so the two stay in step.
function rank_graze_worth(_frames) {
    return RANK_GRAZE_RATE * (max(_frames, 0) / FPS) * TALLY_GRAZE;
}

/// @desc The speed bonus for breaking an attack with `_frac` of its clock
///       left: `_frac` of what grazing for the whole clock is worth. This makes
///       the threshold ask for the same graze rate however early the attack is
///       broken, so stalling an attack to graze gains nothing (`test_marks`
///       checks this).
function rank_speed_award(_p, _frac) {
    if (_p == undefined) return 0;
    return rank_graze_worth(_p.time) * clamp(_frac, 0, 1);
}

/// @desc The target for one of a boss's attacks, measured over the attack's
///       full clock (the speed award covers finishing early). A phase row may
///       set its own `score` to override it; read with `[$ ]` because most
///       rows don't have the field.
function rank_attack_target(_p) {
    if (_p == undefined) return 0;
    var _own = _p[$ "score"];
    if (_own != undefined) return _own;
    var _award = (_p.kind == AttackKind.Spell)
        ? TALLY_SPELL_CLEAR : TALLY_PHASE_CLEAR;
    return rank_score_target(_award, _p.time);
}

/// @desc The target for one group of waves, measured over how long the group
///       actually lasted (at least `RANK_WAVE_MIN_TIME`). `_worth` is what its
///       enemies were worth, accumulated by `enemy_spawn`.
function rank_wave_target(_worth, _frames) {
    return rank_score_target(_worth, max(_frames, RANK_WAVE_MIN_TIME));
}

/// @desc The standing so far: the mean tier, rounded half up. -1 for an empty
///       ledger (drawn as no standing).
///
///       Uses `floor(x + 0.5)` because GML's `round` is banker's rounding
///       (`round(2.5)` is 2, `round(3.5)` is 4), which would treat halfway
///       averages inconsistently.
function rank_overall(_ledger) {
    if (_ledger == undefined) return -1;
    var _n = array_length(_ledger.marks);
    if (_n <= 0) return -1;
    var _sum = 0;
    for (var _i = 0; _i < _n; _i++) _sum += _ledger.marks[_i].tier;
    return clamp(floor(_sum / _n + 0.5), 0, Mark.Count - 1);
}

/// @desc True when there is at least one mark and every mark is Amethyst.
///       This "perfect" standing is not a tier in `Mark` (a sixth enum member
///       would become awardable to a single encounter, since `rank_note`
///       clamps to `Mark.Count - 1`).
function rank_is_perfect(_ledger) {
    if (_ledger == undefined) return false;
    var _n = array_length(_ledger.marks);
    if (_n <= 0) return false;
    for (var _i = 0; _i < _n; _i++) {
        if (_ledger.marks[_i].tier != Mark.Amethyst) return false;
    }
    return true;
}

/// @desc What the standing is called: ABSOLUTE AMETHYST when perfect.
///       `_short` gives just "ABSOLUTE", for places the full name doesn't fit.
function rank_overall_name(_ledger, _short = false) {
    if (rank_is_perfect(_ledger)) return _short ? "ABSOLUTE" : "ABSOLUTE AMETHYST";
    return mark_name(rank_overall(_ledger));
}

/// @desc What the standing is drawn in. Perfect is amethyst lightened.
function rank_overall_colour(_ledger) {
    if (rank_is_perfect(_ledger)) return merge_colour(COL_AMETHYST, c_white, 0.45);
    var _o = rank_overall(_ledger);
    return (_o < 0) ? COL_SLATE : mark_colour(_o);
}

/// @desc How many marks are in it.
function rank_count(_ledger) {
    return (_ledger == undefined) ? 0 : array_length(_ledger.marks);
}
