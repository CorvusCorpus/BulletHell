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
/// **Both halves are real now.** The boss's attacks are graded from what the
/// fight already recorded, and the stage's own waves are graded from a window
/// that `stage_functions` opens when fodder arrives and closes when the field
/// clears. `stage_def.encounters` -- the hand-written count that stood in for
/// the second half, and was already wrong by one on stage one -- is gone from
/// every stage that has a timeline; `stage_new` counts the encounters a stage
/// contains before it starts, so the console can draw the sockets.

/// The ladder. **Five tiers, and the top one has to be rare enough to be worth
/// chasing** -- the whole mechanic is a reason to replay a stage that has
/// already been cleared, and a top grade handed out for finishing is not one.
///
/// **They split by hue as well as by value**, which the pair this replaced did
/// not: slag and iron were both dim and both cool, and the only thing telling
/// them apart was the word printed beside them. Dark cool, warm brown, bright
/// cool, bright warm, bright violet is a sequence that reads at thirty pixels
/// in the dark without being read.
enum Mark {
    Stone,       // what is left when you smelt badly
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
///
///       Four of the five are the console's own furniture, which is the point:
///       a ladder made of the plate's own materials belongs to the plate. The
///       fifth is `COL_AMETHYST`, which is `COL_SIGIL` lifted -- the top of the
///       ladder is **Szuix's own magic**, which is the right thing for a game
///       about taking other people's off them, and it is far enough above
///       `COL_ARCANE` in value not to sink into the plate it is drawn on.
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

/// @desc File a mark. **The only way anything gets into a ledger**, and there
///       are exactly two callers: `boss_end_phase` for an attack and
///       `stage_encounter_close` for a wave.
///
///       **A mark carries what earned it, not only what it came to.** The
///       rank card prints the score against its target and what the
///       encounter cost, and the alternative to keeping them here was a
///       second call from both of those places telling the console the same
///       facts the ledger had just been handed. One record of an encounter,
///       and everything that draws it is a read -- which is also what the
///       result screen's itemised list will want when it is written.
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

/// @desc Grade one encounter, from the three facts every encounter has.
///
///       **Clean is the second rung from the top, not the top.** A player who
///       took no hit and spent no sigil has done the thing the attack asked
///       and gets `RANK_BASE` for it; the top mark is something further, and
///       what it is is the score threshold. That ordering is the whole design
///       -- a ladder whose top rung is "did not make a mistake" has nothing
///       left to reward the player who was also *good*.
///
///       **A hit costs two rungs and a bomb costs one.** That is the opposite
///       way round from the first version of this, which ranked a bomb below a
///       hit: a sigil is a resource the player chose to spend, where a hit is
///       one they did not choose at all, and `MP_PER_BOMB` against
///       `ITEM_MP_VALUE` already makes a bomb expensive without the ladder
///       charging twice for it.
///
///       **Nothing here asks whether the attack was beaten.** It used to, and
///       a timeout was a hard `Slag` whatever else had happened -- which is
///       wrong twice. Running a card to its clock can take more skill than
///       breaking it, and a survival spell, where the caster cannot be hurt
///       until the clock runs out, could only ever score the bottom mark under
///       that rule. The anti-hiding argument the branch was carrying is not
///       lost: it lives in the *capture bonus*, which still wants the spell
///       broken, so hiding in a corner costs the points it always cost and no
///       longer costs the medal as well.
function rank_for_encounter(_hits, _bombs, _met) {
    var _t = RANK_BASE - _hits * RANK_HIT_COST - _bombs * RANK_BOMB_COST;
    if (_met) _t++;
    return clamp(_t, 0, Mark.Count - 1);
}

/// @desc The score an encounter has to beat for its top rung.
///
///       **What is finished plus what is dared.** `_award` is what the
///       encounter pays out for simply being completed -- the flat part of an
///       attack's clear bonus, or what a wave's enemies are worth dead and
///       collected -- and the rest is `RANK_GRAZE_RATE` seconds of grazing on
///       top. So the threshold is never "score more than is available"; it is
///       "finish it, and spend the time near the bullets".
///
///       **The flat award is in the target rather than excluded from it** so
///       that failing to finish -- letting half a wave fly off the bottom of
///       the screen -- costs the threshold by itself, without a second rule
///       saying so.
function rank_score_target(_award, _frames) {
    return _award + rank_graze_worth(_frames);
}

/// @desc What grazing at the expected rate is worth over a span of frames.
///
///       **One function because two things have to agree exactly.** It is the
///       whole of the difficulty in a threshold, and it is also what the
///       speed bonus pays back -- so a change to the rate moves the bar and
///       the compensation together, which is the only way they can stay in
///       step.
function rank_graze_worth(_frames) {
    return RANK_GRAZE_RATE * (max(_frames, 0) / FPS) * TALLY_GRAZE;
}

/// @desc What breaking an attack early is worth, on top of the flat award.
///
///       **It is priced as the grazing the player gave up**, and that is the
///       second version of this. The first was a flat `TALLY_SPELL_SPEED`
///       scaled by the clock left, which reads fine and is wrong the moment
///       it is measured: against the threshold it made a fast break *harder*
///       on a long attack and easier on a short one -- twenty-six grazes a
///       second to reach the bar on a forty-second spell broken with three
///       quarters of its clock left, against six on a twenty-four second
///       non-spell. The exchange rate between the two routes to the top mark
///       was the attack's own length, which is nothing anybody chose, and
///       the paragraph above it claimed they were equal.
///
///       Paid this way the arithmetic cancels. A player who finishes with
///       `_frac` of the clock left has had `1 - _frac` of it to graze in, and
///       is handed `_frac` of what the whole clock was worth -- so reaching
///       the threshold takes `RANK_GRAZE_RATE` grazes a second whatever they
///       do, and breaking it fast and staying in to graze really are the
///       same deal. **The flat award drops out of that entirely**, because
///       the threshold contains it too, which is why it is free to be
///       whatever the score wants and was put back to the number it always
///       was.
///
///       None of that is visible by reading it, which is how the first
///       version survived being written down: `test_marks` walks four
///       finishing times and measures the rate each one demands.
function rank_speed_award(_p, _frac) {
    if (_p == undefined) return 0;
    return rank_graze_worth(_p.time) * clamp(_frac, 0, 1);
}

/// @desc The target for one of a boss's attacks.
///
///       **Measured against the attack's clock rather than against how long it
///       actually took**, which is the opposite of the wave rule below and is
///       deliberate: an attack's award already shrinks as its clock runs, so
///       letting the *target* grow with the same seconds would charge for
///       slowness twice and leave a survival spell -- which is all clock by
///       definition -- with a bar nobody could reach.
///
///       A row may carry its own `score` and override the lot. The read is
///       `[$ ]` because almost no row does and a bare `.score` raises.
function rank_attack_target(_p) {
    if (_p == undefined) return 0;
    var _own = _p[$ "score"];
    if (_own != undefined) return _own;
    var _award = (_p.kind == AttackKind.Spell)
        ? TALLY_SPELL_CLEAR : TALLY_PHASE_CLEAR;
    return rank_score_target(_award, _p.time);
}

/// @desc The target for one group of waves.
///
///       **Measured against how long the group actually lasted**, because a
///       wave has no clock to measure against instead. That makes the rate the
///       whole of the requirement and the duration cancel out: kill everything
///       in eight seconds and the bar asks for eight seconds of grazing, take
///       twenty and it asks for twenty. Dawdling buys nothing, which is the
///       job the clock does on an attack.
///
///       `_worth` is what the group's enemies were worth dead and collected,
///       accumulated by `enemy_spawn` as they arrived -- so a wave shape
///       written next year is counted correctly without being told to be.
function rank_wave_target(_worth, _frames) {
    return rank_score_target(_worth, max(_frames, RANK_WAVE_MIN_TIME));
}

/// @desc The standing so far: the mean of what has been earned, to the nearest
///       rung.
///
///       **To the nearest, not floored, which is Bayonetta's arithmetic and is
///       a reversal.** The floor was defended here at length on the grounds
///       that one good encounter must not pay for one bad one -- and it does
///       do that, at the price of making the top of the ladder unreachable by
///       anything except perfection, which is a rung that then does no work.
///       Rounding gives the standing its full range back and leaves the top
///       *overall* grade to `rank_is_perfect`, which is a stricter test than
///       any mean.
///
///       **`floor(x + 0.5)` and not `round`, which is a GML trap.**
///       GameMaker's `round` is banker's rounding: it breaks a tie toward the
///       *even* number, so `round(2.5)` is 2 and `round(3.5)` is 4. On a
///       five-rung ladder that is four halfway points behaving in two
///       different ways -- a run averaging exactly silver-and-a-half rounds
///       down while one averaging gold-and-a-half rounds up -- and the player
///       it happens to has no way of telling it is not a bug. It compiles, it
///       runs, and it is right half the time, which is the worst frequency
///       for a mistake to have.
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
    return clamp(floor(_sum / _n + 0.5), 0, Mark.Count - 1);
}

/// @desc Every encounter at the top mark, and at least one of them.
///
///       **It is not a sixth tier and it must not become one.** `rank_note`
///       clamps to `Mark.Count - 1`, so a sixth member of that enum would be
///       awardable to a single encounter the moment it existed -- and the
///       whole of what this says is that *all* of them were. It is a question
///       about a ledger, so it is a function of one.
function rank_is_perfect(_ledger) {
    if (_ledger == undefined) return false;
    var _n = array_length(_ledger.marks);
    if (_n <= 0) return false;
    for (var _i = 0; _i < _n; _i++) {
        if (_ledger.marks[_i].tier != Mark.Amethyst) return false;
    }
    return true;
}

/// @desc What the standing is called. **ABSOLUTE AMETHYST** when every
///       encounter took the top mark -- Bayonetta's Pure Platinum, in this
///       ladder's own material.
///
///       `_short` drops the first word, for the console's own row: that value
///       is set at 56px in a 416-pixel column beside its tag, and the full
///       name does not fit in it. Nothing is lost by the shortening, because
///       the row is also drawn in a colour no other standing uses.
function rank_overall_name(_ledger, _short = false) {
    if (rank_is_perfect(_ledger)) return _short ? "ABSOLUTE" : "ABSOLUTE AMETHYST";
    return mark_name(rank_overall(_ledger));
}

/// @desc What the standing is drawn in. Perfect is the top tier lit rather
///       than a seventh colour, because it *is* the top tier -- and a run that
///       has earned it should read as amethyst turned up, not as something
///       from a different set.
function rank_overall_colour(_ledger) {
    if (rank_is_perfect(_ledger)) return merge_colour(COL_AMETHYST, c_white, 0.45);
    var _o = rank_overall(_ledger);
    return (_o < 0) ? COL_SLATE : mark_colour(_o);
}

/// @desc How many marks are in it.
function rank_count(_ledger) {
    return (_ledger == undefined) ? 0 : array_length(_ledger.marks);
}
