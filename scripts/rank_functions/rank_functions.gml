/// @desc Marks: a grade per encounter, and the standing they add up to.
///
/// **A stage is a series of encounters and each one is graded.** That is
/// Bayonetta's shape rather than Touhou's -- Touhou scores a run as one number
/// and hands out a spell-capture bonus, where the character-action games break
/// a level into set pieces and put a medal on each. It fits this game better
/// than the genre's own convention does, because the progression here is
/// Cuphead's: a stage is played in isolation and replayed until it is clean, so
/// what the player wants back from an attempt is *where it went wrong*, and a
/// single number cannot say that. A row of marks can.
///
/// **What is built here is the ledger and the readout, not the scoring.** The
/// boss's attacks are graded for real, because everything a grade needs about
/// them already exists -- `hits_this_phase`, `bombs_this_phase`, and whether
/// the attack was beaten or merely survived. The stage's own waves are *not*:
/// a wave is currently a line in a `{at, fn}` timeline and not a thing with a
/// beginning, an end or an outcome, and giving it those is a change to
/// `stage_functions` rather than to this file. `rank_note` is the seam that
/// change will call, and `stage_def.encounters` is the provisional count that
/// stands in for it until then -- see the note on it in `stage_ziggy`.
///
/// So the console shows a real ledger with real boss marks in it, and sockets
/// for the encounters the stage has not yet learned to report.

/// The ladder. **Five tiers, and the top one has to be rare enough to be worth
/// chasing** -- the whole mechanic is a reason to replay a stage that has
/// already been cleared, and a top grade handed out for finishing is not one.
enum Mark {
    Slag,        // survived it, or ran the clock out
    Iron,
    Silver,
    Gold,
    Adamant,     // clean, and quick
    Count,
}

/// @desc What a tier is called. Metals rather than Bayonetta's stones, and a
///       ladder anyone reads instantly because bronze-silver-gold is universal
///       -- with slag under it, which is what is left when you smelt badly, and
///       adamant over it, which is the one metal that is not.
function mark_name(_t) {
    switch (_t) {
        case Mark.Slag:    return "SLAG";
        case Mark.Iron:    return "IRON";
        case Mark.Silver:  return "SILVER";
        case Mark.Gold:    return "GOLD";
        case Mark.Adamant: return "ADAMANT";
    }
    return "--";
}

/// @desc What a tier is drawn in.
///
///       **The ladder has to read as a ladder in the dark.** Slag and iron are
///       both dim and cool and are told apart by the *name* beside them rather
///       than by hue, which is fine: the two of them mean "this went badly" and
///       the distinction between them matters after the run, not during it.
///       What has to be unmistakable at a glance is the top of the ladder, so
///       gold is the game's own gold and adamant is the one colour on the
///       console that is neither warm nor grey.
function mark_colour(_t) {
    switch (_t) {
        case Mark.Slag:    return merge_colour(COL_SLATE, COL_DUSK, 0.55);
        case Mark.Iron:    return merge_colour(COL_SLATE, COL_SILVER, 0.35);
        case Mark.Silver:  return COL_SILVER;
        case Mark.Gold:    return COL_GRAZE;
        case Mark.Adamant: return merge_colour(COL_MANA, c_white, 0.55);
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

/// @desc File a mark. **The seam the wave grading will call**, and the only
///       way anything gets into a ledger.
function rank_note(_ledger, _label, _tier, _spell = false) {
    if (_ledger == undefined) return;
    array_push(_ledger.marks, {
        label: _label,
        tier: clamp(_tier, 0, Mark.Count - 1),
        spell: _spell,
    });
    _ledger.best = max(_ledger.best, _tier);
    _ledger.flare = 1;
}

/// @desc The standing so far: the mean of what has been earned, rounded down.
///
///       **Rounded down, and that is the whole of the difficulty rule.** A mean
///       that rounds to nearest lets one bad encounter be cancelled by one good
///       one, which makes the standing a measure of the *average* attempt; a
///       floor makes it a measure of the consistent one, so a run of five golds
///       and a slag is not a gold run. That is the character-action convention
///       and it is why those grades are worth having.
///
///       It answers -1 for an empty ledger, which the console draws as no
///       standing at all rather than as the bottom of the ladder -- an attempt
///       nobody has been graded on yet is not a bad attempt.
function rank_overall(_ledger) {
    if (_ledger == undefined) return -1;
    var _n = array_length(_ledger.marks);
    if (_n <= 0) return -1;
    var _sum = 0;
    for (var _i = 0; _i < _n; _i++) _sum += _ledger.marks[_i].tier;
    return clamp(floor(_sum / _n), 0, Mark.Count - 1);
}

/// @desc How many marks are in it.
function rank_count(_ledger) {
    return (_ledger == undefined) ? 0 : array_length(_ledger.marks);
}

/// @desc Grade one of the boss's attacks, from what the fight already recorded.
///
///       **Every input here exists already**, which is why the boss half of
///       this is real where the wave half is a stub: a phase ends knowing
///       whether it was beaten or timed out, how many times the player was hit
///       during it and how many sigils they spent, and those three facts are
///       the whole of what a grade for a danmaku attack should be made of.
///
///       `_frac` is how much of the attack's clock was left when it ended, and
///       it is what separates the top of the ladder from the rest: a spell
///       survived cleanly is a good attempt, and a spell *broken* cleanly with
///       time to spare is the one worth a mark that is hard to get.
function rank_for_attack(_beaten, _hits, _bombs, _frac) {
    if (!_beaten) return Mark.Slag;          // the clock ran out
    if (_bombs > 0) return Mark.Iron;
    if (_hits > 0) return Mark.Silver;
    return (_frac >= 0.35) ? Mark.Adamant : Mark.Gold;
}
